package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

const service = "catalog"

func newLogger() *slog.Logger {
	h := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		ReplaceAttr: func(_ []string, a slog.Attr) slog.Attr {
			switch a.Key {
			case slog.TimeKey:
				a.Key = "ts"
			case slog.LevelKey:
				a.Value = slog.StringValue(lowerLevel(a.Value.String()))
			case slog.MessageKey:
				a.Key = "msg"
			}
			return a
		},
	})
	return slog.New(h).With("service", service)
}

func lowerLevel(s string) string {
	switch s {
	case "INFO":
		return "info"
	case "WARN":
		return "warn"
	case "ERROR":
		return "error"
	case "DEBUG":
		return "debug"
	}
	return s
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// healthcheck lets the distroless image probe itself: `catalog -healthcheck`.
func healthcheck(addr string) int {
	c := http.Client{Timeout: 2 * time.Second}
	resp, err := c.Get("http://127.0.0.1" + addr + "/healthz")
	if err != nil || resp.StatusCode != http.StatusOK {
		return 1
	}
	return 0
}

func main() {
	addr := ":" + env("PORT", "8081")
	if len(os.Args) > 1 && os.Args[1] == "-healthcheck" {
		os.Exit(healthcheck(addr))
	}

	log := newLogger()
	slog.SetDefault(log)

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Error("DATABASE_URL is required")
		os.Exit(1)
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	store, err := newPGStore(ctx, dbURL) // lazy: connections are opened on first use, /readyz reports DB state
	if err != nil {
		log.Error("bad DATABASE_URL", "error", err.Error())
		os.Exit(1)
	}

	chaos := NewChaos(nil, nil)
	app := &server{store: store, log: log}
	public := &http.Server{
		Addr:              addr,
		Handler:           withTrace(log, withAccessLog(chaos.Middleware(app.routes()))),
		ReadHeaderTimeout: 5 * time.Second,
	}
	admin := &http.Server{
		Addr:              ":" + env("ADMIN_PORT", "9000"),
		Handler:           chaos.AdminHandler(os.Getenv("CHAOS_TOKEN")),
		ReadHeaderTimeout: 5 * time.Second,
	}

	for _, s := range []*http.Server{public, admin} {
		go func() {
			log.Info("listening", "addr", s.Addr)
			if err := s.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
				log.Error("server failed", "error", err.Error())
				stop()
			}
		}()
	}

	<-ctx.Done()
	shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = public.Shutdown(shutdown)
	_ = admin.Shutdown(shutdown)
	log.Info("stopped")
}
