-- Real Store + Product domain source-of-truth schema (additive only).
-- Apply: psql "$DATABASE_URL" -f database/store_product_domain_schema.sql

CREATE TABLE IF NOT EXISTS stores (
  id uuid PRIMARY KEY,
  owner_id text NOT NULL,
  name text NOT NULL,
  store_type text NOT NULL CHECK (store_type IN ('construction_store', 'home_store')),
  status text NOT NULL DEFAULT 'approved',
  created_at timestamptz NOT NULL DEFAULT NOW()
);
ALTER TABLE stores ADD COLUMN IF NOT EXISTS is_featured boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS categories (
  id uuid PRIMARY KEY,
  store_id uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  name text NOT NULL,
  parent_id uuid NULL REFERENCES categories(id) ON DELETE SET NULL,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS products (
  id uuid PRIMARY KEY,
  store_id uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  category_id uuid NULL REFERENCES categories(id) ON DELETE SET NULL,
  name text NOT NULL,
  description text NOT NULL DEFAULT '',
  price numeric(18,4) NOT NULL DEFAULT 0,
  has_variants boolean NOT NULL DEFAULT false,
  image_url text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT NOW()
);
ALTER TABLE products ADD COLUMN IF NOT EXISTS is_boosted boolean NOT NULL DEFAULT false;
ALTER TABLE products ADD COLUMN IF NOT EXISTS is_trending boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS product_variants (
  id uuid PRIMARY KEY,
  product_id uuid NULL REFERENCES products(id) ON DELETE CASCADE,
  wholesale_product_id uuid NULL,
  sku text,
  price numeric(18,4) NOT NULL DEFAULT 0,
  stock int NOT NULL DEFAULT 0,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_product_variants_target
    CHECK ((product_id IS NOT NULL) OR (wholesale_product_id IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS product_variant_options (
  id uuid PRIMARY KEY,
  variant_id uuid NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
  option_type text NOT NULL CHECK (option_type IN ('color', 'size', 'weight', 'dimension')),
  option_value text NOT NULL
);

-- Compatibility alias table for integrations expecting `variant_options`.
CREATE TABLE IF NOT EXISTS variant_options (
  id uuid PRIMARY KEY,
  variant_id uuid NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('size', 'color', 'measurement')),
  value text NOT NULL
);

ALTER TABLE products ADD COLUMN IF NOT EXISTS has_variants boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_stores_owner_id ON stores (owner_id);
CREATE INDEX IF NOT EXISTS idx_categories_store_id ON categories (store_id);
CREATE INDEX IF NOT EXISTS idx_categories_parent_id ON categories (parent_id);
CREATE INDEX IF NOT EXISTS idx_products_store_id ON products (store_id);
CREATE INDEX IF NOT EXISTS idx_products_category_id ON products (category_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON product_variants (product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_wholesale_product_id ON product_variants (wholesale_product_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_product_variants_sku_unique ON product_variants (sku) WHERE sku IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_product_variant_options_variant_id ON product_variant_options (variant_id);
CREATE INDEX IF NOT EXISTS idx_variant_options_variant_id ON variant_options (variant_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_product_variants_default_per_product
  ON product_variants (product_id) WHERE is_default = true;
CREATE UNIQUE INDEX IF NOT EXISTS uniq_product_variants_default_per_wholesale_product
  ON product_variants (wholesale_product_id) WHERE is_default = true;

