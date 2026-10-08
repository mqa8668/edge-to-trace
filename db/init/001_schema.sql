-- Fixed schema for the demo app. No migration framework on purpose (see docs/architecture.md).
CREATE TABLE products (
    id           integer PRIMARY KEY,
    sku          text    NOT NULL UNIQUE,
    title        text    NOT NULL,
    author       text    NOT NULL,
    price_cents  integer NOT NULL CHECK (price_cents > 0),
    stock        integer NOT NULL CHECK (stock >= 0),
    popularity   integer NOT NULL DEFAULT 0
);

CREATE INDEX products_popularity_idx ON products (popularity DESC, id);

CREATE TABLE orders (
    id          bigserial PRIMARY KEY,
    product_id  integer     NOT NULL REFERENCES products (id),
    quantity    integer     NOT NULL CHECK (quantity > 0),
    created_at  timestamptz NOT NULL DEFAULT now()
);
