package main

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrNotFound          = errors.New("not found")
	ErrInsufficientStock = errors.New("insufficient stock")
)

type Product struct {
	ID         int    `json:"id"`
	SKU        string `json:"sku"`
	Title      string `json:"title"`
	Author     string `json:"author"`
	PriceCents int    `json:"price_cents"`
	Stock      int    `json:"stock"`
	Popularity int    `json:"popularity"`
}

type Reservation struct {
	OrderID   int64 `json:"order_id"`
	ProductID int   `json:"product_id"`
	Quantity  int   `json:"quantity"`
	StockLeft int   `json:"stock_left"`
}

// Store is the persistence boundary; handlers are tested against a fake.
type Store interface {
	GetProduct(ctx context.Context, id int) (Product, error)
	Popular(ctx context.Context, limit int) ([]Product, error)
	Reserve(ctx context.Context, productID, qty int) (Reservation, error)
	Ping(ctx context.Context) error
}

type pgStore struct{ pool *pgxpool.Pool }

func newPGStore(ctx context.Context, url string) (*pgStore, error) {
	cfg, err := pgxpool.ParseConfig(url)
	if err != nil {
		return nil, err
	}
	cfg.MaxConns = 10
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, err
	}
	return &pgStore{pool: pool}, nil
}

const productCols = "id, sku, title, author, price_cents, stock, popularity"

func scanProduct(row pgx.Row) (Product, error) {
	var p Product
	err := row.Scan(&p.ID, &p.SKU, &p.Title, &p.Author, &p.PriceCents, &p.Stock, &p.Popularity)
	return p, err
}

func (s *pgStore) GetProduct(ctx context.Context, id int) (Product, error) {
	p, err := scanProduct(s.pool.QueryRow(ctx, "SELECT "+productCols+" FROM products WHERE id = $1", id))
	if errors.Is(err, pgx.ErrNoRows) {
		return Product{}, ErrNotFound
	}
	return p, err
}

func (s *pgStore) Popular(ctx context.Context, limit int) ([]Product, error) {
	rows, err := s.pool.Query(ctx, "SELECT "+productCols+" FROM products ORDER BY popularity DESC, id LIMIT $1", limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Product{}
	for rows.Next() {
		p, err := scanProduct(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (s *pgStore) Reserve(ctx context.Context, productID, qty int) (Reservation, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return Reservation{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var stock int
	err = tx.QueryRow(ctx, "SELECT stock FROM products WHERE id = $1 FOR UPDATE", productID).Scan(&stock)
	if errors.Is(err, pgx.ErrNoRows) {
		return Reservation{}, ErrNotFound
	}
	if err != nil {
		return Reservation{}, err
	}
	if stock < qty {
		return Reservation{}, ErrInsufficientStock
	}
	if _, err = tx.Exec(ctx, "UPDATE products SET stock = stock - $2 WHERE id = $1", productID, qty); err != nil {
		return Reservation{}, err
	}
	res := Reservation{ProductID: productID, Quantity: qty, StockLeft: stock - qty}
	err = tx.QueryRow(ctx, "INSERT INTO orders (product_id, quantity) VALUES ($1, $2) RETURNING id", productID, qty).Scan(&res.OrderID)
	if err != nil {
		return Reservation{}, err
	}
	return res, tx.Commit(ctx)
}

func (s *pgStore) Ping(ctx context.Context) error { return s.pool.Ping(ctx) }
