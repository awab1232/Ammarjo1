-- Store domain + sessions (Node/postgres migration runner — no psql meta-commands)
CREATE TABLE IF NOT EXISTS stores (
  id UUID PRIMARY KEY,
  owner_id TEXT NOT NULL,
  tenant_id TEXT,
  name TEXT NOT NULL,
  description TEXT DEFAULT '',
  category TEXT DEFAULT '',
  status TEXT DEFAULT 'approved',
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE stores ADD COLUMN IF NOT EXISTS is_featured BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS is_boosted BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS boost_expires_at TIMESTAMPTZ;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS store_type TEXT NOT NULL DEFAULT 'retail';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS delivery_fee NUMERIC(12,2);
ALTER TABLE stores ADD COLUMN IF NOT EXISTS phone TEXT NOT NULL DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS sell_scope TEXT NOT NULL DEFAULT 'city';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS city TEXT NOT NULL DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS cities TEXT[] NOT NULL DEFAULT '{}'::text[];
ALTER TABLE stores ADD COLUMN IF NOT EXISTS store_type_id UUID;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS store_type_key TEXT;

CREATE TABLE IF NOT EXISTS store_categories (
  id UUID PRIMARY KEY,
  store_id UUID NOT NULL,
  name TEXT NOT NULL,
  order_index INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS store_products (
  id UUID PRIMARY KEY,
  store_id UUID NOT NULL,
  category_id UUID,
  name TEXT NOT NULL,
  price NUMERIC(12,2) DEFAULT 0,
  has_variants BOOLEAN NOT NULL DEFAULT false,
  images JSONB DEFAULT '[]'::jsonb,
  stock INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE store_products ADD COLUMN IF NOT EXISTS is_boosted BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE store_products ADD COLUMN IF NOT EXISTS is_trending BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS store_boost_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  boost_type TEXT NOT NULL,
  duration_days INT NOT NULL,
  price NUMERIC(12,2) NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_store_boost_requests_status_created
  ON store_boost_requests (status, created_at DESC);

CREATE TABLE IF NOT EXISTS product_variants (
  id UUID PRIMARY KEY,
  product_id UUID,
  wholesale_product_id UUID,
  sku TEXT,
  price NUMERIC(18,4) NOT NULL DEFAULT 0,
  stock INTEGER NOT NULL DEFAULT 0,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT chk_product_variants_target
    CHECK ((product_id IS NOT NULL) OR (wholesale_product_id IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS product_variant_options (
  id UUID PRIMARY KEY,
  variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
  option_type TEXT NOT NULL CHECK (option_type IN ('color', 'size', 'weight', 'dimension')),
  option_value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS variant_options (
  id UUID PRIMARY KEY,
  variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('size', 'color', 'measurement')),
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS service_requests (
  id UUID PRIMARY KEY,
  tenant_id TEXT,
  customer_id TEXT NOT NULL,
  technician_id TEXT,
  technician_email TEXT,
  conversation_id TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending',
  description TEXT NOT NULL DEFAULT '',
  title TEXT DEFAULT 'طلب خدمة',
  category_id TEXT DEFAULT '',
  notes TEXT DEFAULT '',
  image_url TEXT DEFAULT '',
  chat_id TEXT DEFAULT '',
  earnings_amount NUMERIC(12,2) DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE service_requests ADD COLUMN IF NOT EXISTS title TEXT DEFAULT 'طلب خدمة';
ALTER TABLE service_requests ADD COLUMN IF NOT EXISTS tenant_id TEXT;
ALTER TABLE service_requests ADD COLUMN IF NOT EXISTS notes TEXT DEFAULT '';
ALTER TABLE service_requests ADD COLUMN IF NOT EXISTS image_url TEXT DEFAULT '';
ALTER TABLE service_requests ADD COLUMN IF NOT EXISTS chat_id TEXT DEFAULT '';
ALTER TABLE service_requests ADD COLUMN IF NOT EXISTS earnings_amount NUMERIC(12,2) DEFAULT 0;
ALTER TABLE store_products ADD COLUMN IF NOT EXISTS has_variants BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON product_variants (product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_wholesale_product_id ON product_variants (wholesale_product_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_product_variants_sku_unique ON product_variants (sku) WHERE sku IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_product_variant_options_variant_id ON product_variant_options (variant_id);
CREATE INDEX IF NOT EXISTS idx_variant_options_variant_id ON variant_options (variant_id);
CREATE INDEX IF NOT EXISTS idx_service_requests_tenant_id ON service_requests (tenant_id);

CREATE TABLE IF NOT EXISTS ratings_reviews (
  id UUID PRIMARY KEY,
  target_type TEXT NOT NULL,
  target_id TEXT NOT NULL,
  reviewer_id TEXT NOT NULL,
  reviewer_name TEXT,
  rating INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
  review_text TEXT,
  delivery_speed INT CHECK (delivery_speed IS NULL OR (delivery_speed >= 1 AND delivery_speed <= 5)),
  product_quality INT CHECK (product_quality IS NULL OR (product_quality >= 1 AND product_quality <= 5)),
  service_request_id UUID,
  order_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ratings_aggregates (
  target_type TEXT NOT NULL,
  target_id TEXT NOT NULL,
  avg_rating NUMERIC(4,2) NOT NULL DEFAULT 0,
  total_reviews INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (target_type, target_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ratings_unique_by_order_target
  ON ratings_reviews (reviewer_id, order_id, target_type, target_id)
  WHERE order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ratings_target_created
  ON ratings_reviews (target_type, target_id, created_at DESC);

CREATE TABLE IF NOT EXISTS technician_join_requests (
  id UUID PRIMARY KEY,
  firebase_uid TEXT,
  email TEXT NOT NULL DEFAULT '',
  display_name TEXT NOT NULL DEFAULT '',
  specialties TEXT[] NOT NULL DEFAULT '{}'::text[],
  category_id TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  city TEXT NOT NULL DEFAULT '',
  cities TEXT[] NOT NULL DEFAULT '{}'::text[],
  status TEXT NOT NULL DEFAULT 'pending',
  rejection_reason TEXT,
  reviewed_by TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_technician_join_requests_status_created
  ON technician_join_requests (status, created_at DESC);

CREATE TABLE IF NOT EXISTS admin_technicians (
  id TEXT PRIMARY KEY,
  firebase_uid TEXT,
  email TEXT NOT NULL DEFAULT '',
  display_name TEXT NOT NULL DEFAULT '',
  specialties TEXT[] NOT NULL DEFAULT '{}'::text[],
  category TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  city TEXT NOT NULL DEFAULT '',
  cities TEXT[] NOT NULL DEFAULT '{}'::text[],
  status TEXT NOT NULL DEFAULT 'approved',
  approved_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_admin_technicians_firebase_uid
  ON admin_technicians (firebase_uid);

-- ─── User Sessions (device tracking) ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_sessions (
  id            UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid  TEXT    NOT NULL,
  device_id     TEXT    NOT NULL,
  device_name   TEXT    NOT NULL DEFAULT '',
  device_os     TEXT    NOT NULL DEFAULT '',
  app_version   TEXT    NOT NULL DEFAULT '',
  ip_address    TEXT,
  is_trusted    BOOLEAN NOT NULL DEFAULT TRUE,
  last_login_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_sessions_uid_device
  ON user_sessions (firebase_uid, device_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_uid_last
  ON user_sessions (firebase_uid, last_login_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_sessions_last_login
  ON user_sessions (last_login_at DESC);
