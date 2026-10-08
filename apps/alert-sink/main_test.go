package main

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

const body = `{"version":"4","status":"firing","alerts":[
 {"status":"firing","labels":{"alertname":"A","severity":"page"},"annotations":{"summary":"s"}},
 {"status":"resolved","labels":{"alertname":"B"},"annotations":{}}]}`

func srv() (*httptest.Server, *Store) {
	st := &Store{}
	log := slog.New(slog.NewJSONHandler(io.Discard, nil))
	return httptest.NewServer(newMux(st, log, func() time.Time { return time.Unix(0, 0) }, nil)), st
}

func TestWebhookAndFilter(t *testing.T) {
	s, st := srv()
	defer s.Close()
	resp, err := http.Post(s.URL+"/webhook", "application/json", strings.NewReader(body))
	if err != nil || resp.StatusCode != 200 {
		t.Fatalf("webhook: %v %v", err, resp)
	}
	if got := len(st.List("", "")); got != 2 {
		t.Fatalf("want 2 alerts, got %d", got)
	}
	if got := len(st.List("firing", "")); got != 1 {
		t.Fatalf("want 1 firing, got %d", got)
	}
	if got := len(st.List("", "B")); got != 1 {
		t.Fatalf("want 1 named B, got %d", got)
	}
}

func TestRejectsBadPayload(t *testing.T) {
	s, _ := srv()
	defer s.Close()
	for _, b := range []string{"nope", `{"version":"3","alerts":[]}`} {
		resp, _ := http.Post(s.URL+"/webhook", "application/json", strings.NewReader(b))
		if resp.StatusCode != 400 {
			t.Fatalf("%q: want 400 got %d", b, resp.StatusCode)
		}
	}
}

func TestKeepsLastN(t *testing.T) {
	st := &Store{}
	for i := 0; i < maxKept+50; i++ {
		st.Add(time.Now(), []Alert{{Status: "firing", Labels: map[string]string{"alertname": "X"}}})
	}
	if got := len(st.List("", "")); got != maxKept {
		t.Fatalf("want %d got %d", maxKept, got)
	}
}

func TestRendersSharedTemplate(t *testing.T) {
	p := t.TempDir() + "/t.tmpl"
	tmpl := `{{ define "e2t.telegram" }}{{ range .Alerts }}<b>{{ .Labels.severity | toUpper }}: {{ .Labels.alertname }}</b> burn {{ .Annotations.burn_rate }}{{ end }}{{ end }}`
	if err := os.WriteFile(p, []byte(tmpl), 0o600); err != nil {
		t.Fatal(err)
	}
	rd, err := NewRenderer(p)
	if err != nil {
		t.Fatal(err)
	}
	got := rd.Render(Alert{Labels: map[string]string{"severity": "page", "alertname": "X"}, Annotations: map[string]string{"burn_rate": "15.0x"}})
	if got != "PAGE: X burn 15.0x" {
		t.Fatalf("got %q", got)
	}
}

// Runs from a checkout (skipped inside the image build, where only this directory is copied).
func TestRepoTelegramTemplate(t *testing.T) {
	const p = "../../alertmanager/templates/telegram.tmpl"
	if _, err := os.Stat(p); err != nil {
		t.Skip("template not in build context")
	}
	rd, err := NewRenderer(p)
	if err != nil {
		t.Fatal(err)
	}
	base := Alert{
		Status:      "firing",
		Labels:      map[string]string{"severity": "page", "alertname": "StorefrontLatencyBurn", "sloth_service": "storefront", "sloth_slo": "latency"},
		Annotations: map[string]string{"burn_rate": "17.2x", "budget_left": "84.10", "slo_objective": "99% < 300ms", "burn_window": "1h", "runbook_url": "http://r", "dashboard_url": "http://d?a=1&b=2"},
		StartsAt:    time.Now().Add(-5 * time.Minute),
	}
	check := func(a Alert, want ...string) string {
		t.Helper()
		got := rd.Render(a)
		for _, w := range want {
			if !strings.Contains(got, w) {
				t.Fatalf("missing %q in:\n%s", w, got)
			}
		}
		if strings.Contains(got, "<b>") || strings.Contains(got, "<code>") || strings.Contains(got, "<a ") || strings.Contains(got, "&lt;") {
			t.Fatalf("html tags leaked:\n%s", got)
		}
		return got
	}
	got := check(base, "PAGE · StorefrontLatencyBurn", "latency · 99% < 300ms", "17.2× over 1h · budget 84% left", "(firing 5m)", "Dashboard · Runbook")

	exhausted := base
	exhausted.Annotations = map[string]string{"burn_rate": "13.3x", "budget_left": "0.00"}
	check(exhausted, "13.3× · budget exhausted")

	resolved := base
	resolved.Status = "resolved"
	resolved.EndsAt = resolved.StartsAt.Add(27 * time.Minute)
	if out := check(resolved, "RESOLVED · StorefrontLatencyBurn", "fired for 27m"); strings.Contains(out, "\nBurn") {
		t.Fatalf("resolved message has a Burn row:\n%s", out)
	}

	future := base
	future.StartsAt = time.Now().Add(2 * time.Hour)
	check(future, "firing just now")
	secs := base
	secs.StartsAt = time.Now().Add(-10*time.Second - 10*time.Millisecond)
	check(secs, "firing 10s)")

	plainAlert := Alert{Status: "firing", Labels: map[string]string{"severity": "ticket", "alertname": "PostgresDown"}, Annotations: map[string]string{"summary": "db down"}, StartsAt: time.Now()}
	out := check(plainAlert, "TICKET · PostgresDown", "What   db down")
	if strings.Contains(out, "SLO") || strings.Contains(out, "\nBurn") {
		t.Fatalf("non-SLO alert has SLO rows:\n%s", out)
	}
	t.Log("\n" + got)
}
