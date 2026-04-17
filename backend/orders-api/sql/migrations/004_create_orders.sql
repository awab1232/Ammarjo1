-- Orders authoritative store (PostgreSQL). Firebase remains mirror / fallback for unmigrated rows.
-- Apply once: psql "$DATABASE_URL" -f database/orders_schema.sql

CREATE TABLE IF NOT EXISTS orders (
  order_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  store_id TEXT NOT NULL DEFAULT '',
  items JSONB NOT NULL DEFAULT '[]'::jsonb,
  subtotal_numeric NUMERIC(18, 4),
  shipping_numeric NUMERIC(18, 4),
  total_numeric NUMERIC(18, 4),
  currency TEXT NOT NULL DEFAULT 'JOD',
  write_source TEXT NOT NULL DEFAULT 'firebase',
  customer_email TEXT,
  status TEXT,
  billing JSONB,
  delivery_address TEXT,
  list_title TEXT,
  -- Full normalized order document for API round-trip (idempotent replays merge here).
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE orders ADD COLUMN IF NOT EXISTS variant_id TEXT;

CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders (user_id);
CREATE INDEX IF NOT EXISTS idx_orders_store_id ON orders (store_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders (created_at DESC);

-- Listing + filters (multi-instance safe; apply on existing DBs with migration snippet below).
CREATE INDEX IF NOT EXISTS idx_orders_user_created_desc ON orders (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);
CREATE INDEX IF NOT EXISTS idx_orders_user_status_created ON orders (user_id, status, created_at DESC);

COMMENT ON TABLE orders IS 'Primary order storage for new writes; legacy orders may exist only in Firestore.';
