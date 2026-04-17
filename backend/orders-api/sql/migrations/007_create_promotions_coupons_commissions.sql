-- Additive schema: store offers + commission ledger (PostgreSQL source of truth).
-- Apply: psql "$DATABASE_URL" -f database/store_offers_commissions_schema.sql

CREATE TABLE IF NOT EXISTS store_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  discount_percent numeric(8,4) NOT NULL DEFAULT 0,
  valid_until timestamptz,
  image_url text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_store_offers_store ON store_offers(store_id, created_at DESC);

CREATE TABLE IF NOT EXISTS store_commission_ledger (
  store_id uuid PRIMARY KEY REFERENCES stores(id) ON DELETE CASCADE,
  total_commission numeric(18,4) NOT NULL DEFAULT 0,
  total_paid numeric(18,4) NOT NULL DEFAULT 0,
  balance numeric(18,4) NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS store_commission_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  order_id text NOT NULL,
  order_total numeric(18,4) NOT NULL,
  commission_amount numeric(18,4) NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE(store_id, order_id)
);

CREATE INDEX IF NOT EXISTS idx_store_commission_orders_store ON store_commission_orders(store_id, recorded_at DESC);
