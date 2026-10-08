package main

import (
	"context"
	"log/slog"
	"net/http"
	"time"
)

// withTrace parses the incoming W3C traceparent and attaches a logger carrying trace_id.
// There is no OTel SDK here on purpose: Beyla continues the same trace from the kernel side.
func withTrace(base *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		l := base
		if tid, pid, ok := parseTraceparent(r.Header.Get("traceparent")); ok {
			l = base.With("trace_id", tid, "parent_span_id", pid)
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, l)))
	})
}

// withAccessLog logs one JSON line per request, except health probes.
func withAccessLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(sw, r)
		if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" {
			return
		}
		level := slog.LevelInfo
		if sw.status >= 500 {
			level = slog.LevelError
		}
		logger(r).Log(r.Context(), level, "request",
			"method", r.Method, "path", r.URL.Path, "status", sw.status,
			"duration_ms", float64(time.Since(start).Microseconds())/1000)
	})
}
