package main

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type fakeStore struct {
	products map[int]Product
	pingErr  error
}

func (f *fakeStore) GetProduct(_ context.Context, id int) (Product, error) {
	p, ok := f.products[id]
	if !ok {
		return Product{}, ErrNotFound
	}
	return p, nil
}
func (f *fakeStore) Popular(_ context.Context, limit int) ([]Product, error) {
	out := []Product{}
	for _, p := range f.products {
		out = append(out, p)
	}
	if len(out) > limit {
		out = out[:limit]
	}
	return out, nil
}
func (f *fakeStore) Reserve(_ context.Context, id, qty int) (Reservation, error) {
	p, ok := f.products[id]
	if !ok {
		return Reservation{}, ErrNotFound
	}
	if p.Stock < qty {
		return Reservation{}, ErrInsufficientStock
	}
	return Reservation{OrderID: 1, ProductID: id, Quantity: qty, StockLeft: p.Stock - qty}, nil
}
func (f *fakeStore) Ping(context.Context) error { return f.pingErr }

func testServer() (*server, *fakeStore) {
	fs := &fakeStore{products: map[int]Product{1: {ID: 1, Title: "T", Stock: 5, Popularity: 9}}}
	return &server{store: fs, log: slog.New(slog.NewTextHandler(io.Discard, nil))}, fs
}

func do(h http.Handler, method, path, body string, hdr map[string]string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	for k, v := range hdr {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestHandlers(t *testing.T) {
	s, fs := testServer()
	h := s.routes()
	cases := []struct {
		name, method, path, body string
		want                     int
	}{
		{"product ok", "GET", "/products/1", "", 200},
		{"product missing", "GET", "/products/99", "", 404},
		{"product bad id", "GET", "/products/abc", "", 400},
		{"popular ok", "GET", "/products/popular?limit=3", "", 200},
		{"popular bad limit", "GET", "/products/popular?limit=0", "", 400},
		{"reserve ok", "POST", "/reservations", `{"product_id":1,"quantity":2}`, 201},
		{"reserve conflict", "POST", "/reservations", `{"product_id":1,"quantity":6}`, 409},
		{"reserve unknown", "POST", "/reservations", `{"product_id":7,"quantity":1}`, 404},
		{"reserve invalid", "POST", "/reservations", `{"product_id":1,"quantity":0}`, 400},
		{"healthz", "GET", "/healthz", "", 200},
		{"readyz", "GET", "/readyz", "", 200},
	}
	for _, c := range cases {
		if got := do(h, c.method, c.path, c.body, nil).Code; got != c.want {
			t.Errorf("%s: got %d want %d", c.name, got, c.want)
		}
	}
	fs.pingErr = context.DeadlineExceeded
	if got := do(h, "GET", "/readyz", "", nil).Code; got != 503 {
		t.Errorf("readyz with db down: got %d want 503", got)
	}
}

func TestParseTraceparent(t *testing.T) {
	good := "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
	if tid, pid, ok := parseTraceparent(good); !ok || tid != "4bf92f3577b34da6a3ce929d0e0e4736" || pid != "00f067aa0ba902b7" {
		t.Fatalf("valid header rejected: %v %v %v", tid, pid, ok)
	}
	bad := []string{"", "garbage", "00-short-00f067aa0ba902b7-01",
		"00-00000000000000000000000000000000-00f067aa0ba902b7-01",
		"00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01",
		"ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
		"00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01"}
	for _, b := range bad {
		if _, _, ok := parseTraceparent(b); ok {
			t.Errorf("accepted invalid traceparent %q", b)
		}
	}
}

func TestLoggerCarriesTraceID(t *testing.T) {
	var buf strings.Builder
	base := slog.New(slog.NewJSONHandler(&buf, nil))
	s, _ := testServer()
	h := withTrace(base, withAccessLog(s.routes()))
	do(h, "GET", "/products/1", "", map[string]string{"traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"})
	if !strings.Contains(buf.String(), `"trace_id":"4bf92f3577b34da6a3ce929d0e0e4736"`) {
		t.Fatalf("trace_id missing from log: %s", buf.String())
	}
	buf.Reset()
	do(h, "GET", "/healthz", "", nil)
	if buf.Len() != 0 {
		t.Fatalf("health probe should not be logged: %s", buf.String())
	}
}

func TestChaosRatiosAndTTL(t *testing.T) {
	now := time.Unix(1000, 0)
	rolls := []float64{0.1, 0.9, 0.9, 0.1} // call 1: latency hit, error miss; call 2: latency miss, error hit
	i := 0
	c := NewChaos(func() time.Time { return now }, func() float64 { v := rolls[i%len(rolls)]; i++; return v })

	if d, f := c.Decide(); d != 0 || f {
		t.Fatal("inactive chaos must be a no-op")
	}
	if err := c.Set(ChaosConfig{LatencyMs: 800, LatencyRatio: 0.6, ErrorRatio: 0.25, TTLSeconds: 60}); err != nil {
		t.Fatal(err)
	}
	if d, f := c.Decide(); d != 800*time.Millisecond || f {
		t.Fatalf("roll 0.1/0.9: got delay=%v fail=%v", d, f)
	}
	// latency miss (0.9 >= 0.6), error hit (0.1 < 0.25)
	if d, f := c.Decide(); d != 0 || !f {
		t.Fatalf("second call: got delay=%v fail=%v", d, f)
	}
	now = now.Add(61 * time.Second)
	if st := c.State(); st.Active {
		t.Fatal("chaos must expire after ttl")
	}
	if d, f := c.Decide(); d != 0 || f {
		t.Fatal("expired chaos must be a no-op")
	}
}

func TestChaosValidationAndDefaults(t *testing.T) {
	c := NewChaos(nil, nil)
	for _, bad := range []ChaosConfig{{LatencyMs: -1}, {LatencyRatio: 1.5}, {ErrorRatio: -0.1}, {TTLSeconds: 3601}} {
		if c.Set(bad) == nil {
			t.Errorf("accepted invalid config %+v", bad)
		}
	}
	if err := c.Set(ChaosConfig{ErrorRatio: 1}); err != nil {
		t.Fatal(err)
	}
	if st := c.State(); st.Config.TTLSeconds != 900 || !st.Active {
		t.Fatalf("default ttl not applied: %+v", st)
	}
}

func TestChaosAdminAuthAndMiddleware(t *testing.T) {
	c := NewChaos(nil, nil)
	admin := c.AdminHandler("s3cret")
	if got := do(admin, "GET", "/admin/chaos", "", nil).Code; got != 403 {
		t.Errorf("no token: got %d", got)
	}
	if got := do(c.AdminHandler(""), "GET", "/admin/chaos", "", map[string]string{"X-Chaos-Token": ""}).Code; got != 403 {
		t.Errorf("empty configured token must disable admin: got %d", got)
	}
	hdr := map[string]string{"X-Chaos-Token": "s3cret"}
	if got := do(admin, "POST", "/admin/chaos", `{"error_ratio":1,"ttl_seconds":30}`, hdr).Code; got != 200 {
		t.Fatalf("set chaos: got %d", got)
	}
	s, _ := testServer()
	h := c.Middleware(s.routes())
	if got := do(h, "GET", "/products/1", "", nil).Code; got != 503 {
		t.Errorf("error_ratio=1 should 503, got %d", got)
	}
	if got := do(h, "GET", "/healthz", "", nil).Code; got != 200 {
		t.Errorf("healthz must be exempt, got %d", got)
	}
	if got := do(admin, "DELETE", "/admin/chaos", "", hdr).Code; got != 200 {
		t.Fatalf("reset: got %d", got)
	}
	if got := do(h, "GET", "/products/1", "", nil).Code; got != 200 {
		t.Errorf("after reset should be 200, got %d", got)
	}
	if got := do(admin, "POST", "/admin/chaos", `{"latency_ratio":5}`, hdr).Code; got != 422 {
		t.Errorf("invalid ratio: got %d", got)
	}
}
