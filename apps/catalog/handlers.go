package main

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
)

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

type server struct {
	store Store
	log   *slog.Logger
}

func (s *server) routes() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("GET /readyz", s.ready)
	mux.HandleFunc("GET /products/popular", s.popular)
	mux.HandleFunc("GET /products/{id}", s.product)
	mux.HandleFunc("POST /reservations", s.reserve)
	return mux
}

func (s *server) ready(w http.ResponseWriter, r *http.Request) {
	if err := s.store.Ping(r.Context()); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "db unavailable"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (s *server) product(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(r.PathValue("id"))
	if err != nil || id < 1 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid product id"})
		return
	}
	p, err := s.store.GetProduct(r.Context(), id)
	switch {
	case errors.Is(err, ErrNotFound):
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "product not found"})
	case err != nil:
		s.fail(w, r, err)
	default:
		writeJSON(w, http.StatusOK, p)
	}
}

func (s *server) popular(w http.ResponseWriter, r *http.Request) {
	limit := 10
	if v := r.URL.Query().Get("limit"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 1 || n > 100 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "limit must be 1..100"})
			return
		}
		limit = n
	}
	ps, err := s.store.Popular(r.Context(), limit)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"products": ps})
}

func (s *server) reserve(w http.ResponseWriter, r *http.Request) {
	var req struct {
		ProductID int `json:"product_id"`
		Quantity  int `json:"quantity"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&req); err != nil ||
		req.ProductID < 1 || req.Quantity < 1 || req.Quantity > 100 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "product_id >= 1 and 1 <= quantity <= 100 required"})
		return
	}
	res, err := s.store.Reserve(r.Context(), req.ProductID, req.Quantity)
	switch {
	case errors.Is(err, ErrNotFound):
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "product not found"})
	case errors.Is(err, ErrInsufficientStock):
		writeJSON(w, http.StatusConflict, map[string]string{"error": "insufficient stock"})
	case err != nil:
		s.fail(w, r, err)
	default:
		writeJSON(w, http.StatusCreated, res)
	}
}

func (s *server) fail(w http.ResponseWriter, r *http.Request, err error) {
	logger(r).Error("store error", "error", err.Error())
	writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
}

// ---- logging middleware ----

type ctxKey struct{}

// logger returns the request-scoped logger (with trace_id) or the default one.
func logger(r *http.Request) *slog.Logger {
	if l, ok := r.Context().Value(ctxKey{}).(*slog.Logger); ok {
		return l
	}
	return slog.Default()
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}
