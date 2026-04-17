CREATE TABLE IF NOT EXISTS wholesalers (
  id uuid PRIMARY KEY,
  owner_id text NOT NULL,
  name text NOT NULL,
  logo text NOT NULL DEFAULT '',
  cover_image text NOT NULL DEFAULT '',
  description text NOT NULL DEFAULT '',
  category text NOT NULL DEFAULT '',
  city text NOT NULL DEFAULT '',
  phone text NOT NULL DEFAULT '',
  email text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'approved' CHECK (status IN ('pending', 'approved', 'rejected')),
  commission numeric(6,2) NOT NULL DEFAULT 8.00,
  delivery_days int NULL,
  delivery_fee numeric(12,2) NULL,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wholesalers_status ON wholesalers (status);
CREATE INDEX IF NOT EXISTS idx_wholesalers_owner ON wholesalers (owner_id);
CREATE INDEX IF NOT EXISTS idx_wholesalers_name ON wholesalers (name);

CREATE TABLE IF NOT EXISTS wholesale_products (
  id uuid PRIMARY KEY,
  wholesaler_id uuid NOT NULL REFERENCES wholesalers(id) ON DELETE CASCADE,
  product_code text NOT NULL,
  name text NOT NULL,
  image_url text NOT NULL DEFAULT '',
  unit text NOT NULL DEFAULT '',
  category_id text NULL,
  has_variants boolean NOT NULL DEFAULT false,
  stock int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (wholesaler_id, product_code)
);

ALTER TABLE wholesale_products ADD COLUMN IF NOT EXISTS has_variants boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_wholesale_products_wholesaler ON wholesale_products (wholesaler_id);
CREATE INDEX IF NOT EXISTS idx_wholesale_products_category ON wholesale_products (category_id);
CREATE INDEX IF NOT EXISTS idx_wholesale_products_name ON wholesale_products (name);

CREATE TABLE IF NOT EXISTS wholesale_pricing_rules (
  id uuid PRIMARY KEY,
  wholesale_product_id uuid NOT NULL REFERENCES wholesale_products(id) ON DELETE CASCADE,
  min_qty int NOT NULL,
  max_qty int NULL,
  price numeric(14,4) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wholesale_pricing_rules_product ON wholesale_pricing_rules (wholesale_product_id);

CREATE TABLE IF NOT EXISTS wholesale_orders (
  id uuid PRIMARY KEY,
  wholesaler_id uuid NOT NULL REFERENCES wholesalers(id) ON DELETE RESTRICT,
  store_id text NOT NULL,
  store_owner_id text NOT NULL,
  store_name text NOT NULL DEFAULT '',
  subtotal numeric(18,4) NOT NULL DEFAULT 0,
  commission numeric(18,4) NOT NULL DEFAULT 0,
  net_amount numeric(18,4) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled')),
  items jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wholesale_orders_store_id ON wholesale_orders (store_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wholesale_orders_wholesaler_id ON wholesale_orders (wholesaler_id, created_at DESC);
