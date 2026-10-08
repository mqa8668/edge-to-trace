package main

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"math/rand/v2"
	"net/http"
	"sync"
	"time"
)

const (
	defaultTTL = 900 * time.Second
	maxTTL     = 3600 * time.Second
)

// ChaosConfig is the wire format of POST /admin/chaos.
type ChaosConfig struct {
	LatencyMs    int     `json:"latency_ms"`
	LatencyRatio float64 `json:"latency_ratio"`
	ErrorRatio   float64 `json:"error_ratio"`
	TTLSeconds   int     `json:"ttl_seconds"`
}

// Validate checks ranges. Anything out of range is rejected, never clamped.
func (c ChaosConfig) Validate() error {
	switch {
	case c.LatencyMs < 0 || c.LatencyMs > 60000:
		return errors.New("latency_ms must be between 0 and 60000")
	case c.LatencyRatio < 0 || c.LatencyRatio > 1:
		return errors.New("latency_ratio must be between 0 and 1")
	case c.ErrorRatio < 0 || c.ErrorRatio > 1:
		return errors.New("error_ratio must be between 0 and 1")
	case c.TTLSeconds < 0 || time.Duration(c.TTLSeconds)*time.Second > maxTTL:
		return errors.New("ttl_seconds must be between 0 and 3600")
	}
	return nil
}

// Chaos holds the runtime fault-injection state. It heals itself when the TTL expires.
type Chaos struct {
	mu      sync.Mutex
	cfg     ChaosConfig
	expires time.Time
	now     func() time.Time
	rand    func() float64
}

func NewChaos(now func() time.Time, rnd func() float64) *Chaos {
	if now == nil {
		now = time.Now
	}
	if rnd == nil {
		rnd = rand.Float64
	}
	return &Chaos{now: now, rand: rnd}
}

func (c *Chaos) Set(cfg ChaosConfig) error {
	if err := cfg.Validate(); err != nil {
		return err
	}
	ttl := time.Duration(cfg.TTLSeconds) * time.Second
	if ttl == 0 {
		ttl = defaultTTL
		cfg.TTLSeconds = int(defaultTTL / time.Second)
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.cfg = cfg
	c.expires = c.now().Add(ttl)
	return nil
}

func (c *Chaos) Reset() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.cfg = ChaosConfig{}
	c.expires = time.Time{}
}

// State is the JSON returned by GET /admin/chaos.
type ChaosState struct {
	Active           bool        `json:"active"`
	Config           ChaosConfig `json:"config"`
	RemainingSeconds int         `json:"remaining_seconds"`
}

func (c *Chaos) State() ChaosState {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.expires.IsZero() || !c.now().Before(c.expires) {
		return ChaosState{}
	}
	return ChaosState{Active: true, Config: c.cfg, RemainingSeconds: int(c.expires.Sub(c.now()).Seconds())}
}

// Decide returns the delay to inject and whether the request should fail with 503.
func (c *Chaos) Decide() (time.Duration, bool) {
	st := c.State()
	if !st.Active {
		return 0, false
	}
	var delay time.Duration
	if st.Config.LatencyMs > 0 && c.rand() < st.Config.LatencyRatio {
		delay = time.Duration(st.Config.LatencyMs) * time.Millisecond
	}
	fail := st.Config.ErrorRatio > 0 && c.rand() < st.Config.ErrorRatio
	return delay, fail
}

// Middleware injects latency and 503s. Health endpoints are never touched.
func (c *Chaos) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" {
			next.ServeHTTP(w, r)
			return
		}
		delay, fail := c.Decide()
		if delay > 0 {
			select {
			case <-time.After(delay):
			case <-r.Context().Done():
				return
			}
		}
		if fail {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "chaos: injected failure"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

// AdminHandler serves /admin/chaos. With an empty token the admin API is disabled.
func (c *Chaos) AdminHandler(token string) http.Handler {
	mux := http.NewServeMux()
	auth := func(h http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			got := r.Header.Get("X-Chaos-Token")
			if token == "" || subtle.ConstantTimeCompare([]byte(got), []byte(token)) != 1 {
				writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
				return
			}
			h(w, r)
		}
	}
	mux.HandleFunc("GET /admin/chaos", auth(func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, c.State())
	}))
	mux.HandleFunc("POST /admin/chaos", auth(func(w http.ResponseWriter, r *http.Request) {
		var cfg ChaosConfig
		dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
		dec.DisallowUnknownFields()
		if err := dec.Decode(&cfg); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
			return
		}
		if err := c.Set(cfg); err != nil {
			writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, c.State())
	}))
	mux.HandleFunc("DELETE /admin/chaos", auth(func(w http.ResponseWriter, _ *http.Request) {
		c.Reset()
		writeJSON(w, http.StatusOK, c.State())
	}))
	return mux
}
