-- Canonical product rows for search indexing (PostgreSQL source of truth for sync; Algolia is a derived index).
-- Apply: psql "$DATABASE_URL" -f database/catalog_products_schema.sql

CREATE TABLE IF NOT EXISTS catalog_products (
  product_id INTEGER PRIMARY KEY,
  store_id TEXT NOT NULL DEFAULT 'ammarjo',
  name TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  price_numeric NUMERIC(18, 4) NOT NULL DEFAULT 0,
  has_variants BOOLEAN NOT NULL DEFAULT false,
  default_variant_id TEXT,
  min_variant_price NUMERIC(18, 4),
  currency TEXT NOT NULL DEFAULT 'JOD',
  category_ids INTEGER[] NOT NULL DEFAULT '{}',
  image_url TEXT,
  stock_status TEXT NOT NULL DEFAULT 'instock',
  searchable_text TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_catalog_products_store ON catalog_products (store_id);
CREATE INDEX IF NOT EXISTS idx_catalog_products_updated ON catalog_products (updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_catalog_products_category ON catalog_products USING GIN (category_ids);
CREATE INDEX IF NOT EXISTS idx_catalog_products_has_variants ON catalog_products (has_variants);

COMMENT ON TABLE catalog_products IS 'Source of truth for product search sync to Algolia; populate via ETL or internal upsert API.';
