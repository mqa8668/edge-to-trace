package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"text/template"
	"time"
)

const maxKept = 200

var received atomic.Int64

// Alert is one alert from an Alertmanager webhook payload (version 4).
type Alert struct {
	Status       string            `json:"status"`
	Labels       map[string]string `json:"labels"`
	Annotations  map[string]string `json:"annotations"`
	StartsAt     time.Time         `json:"startsAt"`
	EndsAt       time.Time         `json:"endsAt"`
	GeneratorURL string            `json:"generatorURL,omitempty"`
	Fingerprint  string            `json:"fingerprint,omitempty"`
	ReceivedAt   time.Time         `json:"receivedAt"`
	Text         string            `json:"text,omitempty"`
}

// Payload is the Alertmanager webhook body.
type Payload struct {
	Version string  `json:"version"`
	Status  string  `json:"status"`
	Alerts  []Alert `json:"alerts"`
}

// Store keeps the most recent alerts in memory.
type Store struct {
	mu     sync.Mutex
	alerts []Alert
}

func (s *Store) Add(now time.Time, in []Alert) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, a := range in {
		a.ReceivedAt = now
		s.alerts = append(s.alerts, a)
	}
	if n := len(s.alerts); n > maxKept {
		s.alerts = append([]Alert(nil), s.alerts[n-maxKept:]...)
	}
}

// List returns alerts newest first, filtered by status and alertname when they are non-empty.
func (s *Store) List(status, name string) []Alert {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []Alert{}
	for i := len(s.alerts) - 1; i >= 0; i-- {
		a := s.alerts[i]
		if status != "" && a.Status != status {
			continue
		}
		if name != "" && a.Labels["alertname"] != name {
			continue
		}
		out = append(out, a)
	}
	return out
}

func parsePayload(body []byte) (Payload, error) {
	var p Payload
	if err := json.Unmarshal(body, &p); err != nil {
		return p, err
	}
	if !strings.HasPrefix(p.Version, "4") {
		return p, fmt.Errorf("unsupported webhook version %q", p.Version)
	}
	return p, nil
}

// Renderer renders the same template Alertmanager uses for Telegram, so offline demos show the same message.
type Renderer struct{ t *template.Template }

func NewRenderer(path string) (*Renderer, error) {
	if path == "" {
		return &Renderer{}, nil
	}
	t, err := template.New("t").Funcs(funcs).ParseFiles(path)
	if err != nil {
		return nil, err
	}
	return &Renderer{t: t}, nil
}

// funcs mirrors the subset of Alertmanager template functions that telegram.tmpl uses.
var funcs = template.FuncMap{
	"toUpper": strings.ToUpper,
	"toLower": strings.ToLower,
	"reReplaceAll": func(pattern, repl, text string) string {
		return regexp.MustCompile(pattern).ReplaceAllString(text, repl)
	},
	"since": time.Since,
	"humanizeDuration": func(d time.Duration) string {
		d = d.Round(time.Second)
		h, m, s := int(d.Hours()), int(d.Minutes())%60, int(d.Seconds())%60
		var parts []string
		if h > 0 {
			parts = append(parts, fmt.Sprintf("%dh", h))
		}
		if m > 0 {
			parts = append(parts, fmt.Sprintf("%dm", m))
		}
		if s > 0 || len(parts) == 0 {
			parts = append(parts, fmt.Sprintf("%ds", s))
		}
		return strings.Join(parts, " ")
	},
}

var (
	links = regexp.MustCompile(`<a href="[^"]*">([^<]*)</a>`)
	tags  = regexp.MustCompile(`</?(b|code)>`)
)

// plain turns the Telegram HTML into text for the offline view.
func plain(s string) string {
	return strings.NewReplacer("&amp;", "&", "&lt;", "<", "&gt;", ">").Replace(tags.ReplaceAllString(links.ReplaceAllString(s, "$1"), ""))
}

// Render returns the message for one alert, with the Telegram HTML tags removed.
func (r *Renderer) Render(a Alert) string {
	if r == nil || r.t == nil {
		return ""
	}
	var b strings.Builder
	data := struct{ Alerts []Alert }{[]Alert{a}}
	if err := r.t.ExecuteTemplate(&b, "e2t.telegram", data); err != nil {
		return "template error: " + err.Error()
	}
	return strings.TrimSpace(plain(b.String()))
}

func newMux(st *Store, log *slog.Logger, now func() time.Time, rd *Renderer) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /webhook", func(w http.ResponseWriter, r *http.Request) {
		body := http.MaxBytesReader(w, r.Body, 1<<20)
		dec := json.NewDecoder(body)
		var raw json.RawMessage
		if err := dec.Decode(&raw); err != nil {
			http.Error(w, "bad json", http.StatusBadRequest)
			return
		}
		p, err := parsePayload(raw)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		t := now()
		for i := range p.Alerts {
			p.Alerts[i].Text = rd.Render(p.Alerts[i])
		}
		st.Add(t, p.Alerts)
		received.Add(int64(len(p.Alerts)))
		for _, a := range p.Alerts {
			log.Info("alert", "alert_status", a.Status, "alertname", a.Labels["alertname"],
				"severity", a.Labels["severity"], "summary", a.Annotations["summary"],
				"runbook_url", a.Annotations["runbook_url"], "text", a.Text)
		}
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("GET /alerts", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(st.List(q.Get("status"), q.Get("alertname")))
	})
	mux.HandleFunc("GET /messages", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		for _, a := range st.List(q.Get("status"), q.Get("alertname")) {
			fmt.Fprintf(w, "%s\n\n", a.Text)
		}
	})
	mux.HandleFunc("GET /metrics", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		fmt.Fprintf(w, "# TYPE alert_sink_alerts_received_total counter\nalert_sink_alerts_received_total %d\n", received.Load())
	})
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write([]byte("ok")) })
	return mux
}

func newLogger() *slog.Logger {
	h := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		ReplaceAttr: func(_ []string, a slog.Attr) slog.Attr {
			switch a.Key {
			case slog.TimeKey:
				a.Key = "ts"
			case slog.LevelKey:
				a.Value = slog.StringValue(strings.ToLower(a.Value.String()))
			}
			return a
		},
	})
	return slog.New(h).With("service", "alert-sink")
}

func main() {
	hc := flag.Bool("healthcheck", false, "probe /healthz and exit")
	flag.Parse()
	addr := ":9095"
	if *hc {
		c := http.Client{Timeout: 2 * time.Second}
		resp, err := c.Get("http://127.0.0.1:9095/healthz")
		if err != nil || resp.StatusCode != 200 {
			os.Exit(1)
		}
		return
	}
	log := newLogger()
	rd, err := NewRenderer(os.Getenv("ALERT_TEMPLATE"))
	if err != nil {
		log.Error("template", "err", err.Error())
		os.Exit(1)
	}
	srv := &http.Server{Addr: addr, Handler: newMux(&Store{}, log, time.Now, rd), ReadHeaderTimeout: 5 * time.Second}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	go func() {
		<-ctx.Done()
		sc, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(sc)
	}()
	log.Info("listening", "addr", addr)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Error("server", "err", err.Error())
		os.Exit(1)
	}
}
