-- Hybrid Store Builder additive schema
-- Feature-flagged runtime: ENABLE_HYBRID_STORE_BUILDER=1

CREATE TABLE IF NOT EXISTS stores_builder (
  id uuid PRIMARY KEY,
  store_id text NOT NULL UNIQUE,
  owner_id text NOT NULL,
  store_type text NOT NULL CHECK (store_type IN ('construction_store', 'home_store', 'wholesale_store')),
  mode text NOT NULL DEFAULT 'AI' CHECK (mode IN ('AI', 'MANUAL')),
  ai_generated boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stores_builder_owner_id ON stores_builder (owner_id);
CREATE INDEX IF NOT EXISTS idx_stores_builder_store_type ON stores_builder (store_type);

CREATE TABLE IF NOT EXISTS store_categories (
  id uuid PRIMARY KEY,
  store_id text NOT NULL,
  name text NOT NULL,
  image_url text NOT NULL DEFAULT '',
  parent_id uuid NULL REFERENCES store_categories(id) ON DELETE SET NULL,
  sort_order int NOT NULL DEFAULT 0,
  is_ai_generated boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_store_categories_store_id ON store_categories (store_id);
CREATE INDEX IF NOT EXISTS idx_store_categories_parent_id ON store_categories (parent_id);
CREATE INDEX IF NOT EXISTS idx_store_categories_store_sort ON store_categories (store_id, sort_order ASC, created_at ASC);

CREATE TABLE IF NOT EXISTS store_layout_sections (
  id uuid PRIMARY KEY,
  store_id text NOT NULL,
  section_type text NOT NULL CHECK (section_type IN ('featured_products', 'new_arrivals', 'offers', 'category_previews')),
  sort_order int NOT NULL DEFAULT 0,
  config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_ai_generated boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_store_layout_sections_store_id ON store_layout_sections (store_id);
CREATE INDEX IF NOT EXISTS idx_store_layout_sections_store_sort ON store_layout_sections (store_id, sort_order ASC, created_at ASC);

CREATE TABLE IF NOT EXISTS store_ai_suggestions (
  id uuid PRIMARY KEY,
  store_id text NOT NULL,
  type text NOT NULL CHECK (type IN ('category', 'layout', 'product')),
  suggestion_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_store_ai_suggestions_store_id ON store_ai_suggestions (store_id);
CREATE INDEX IF NOT EXISTS idx_store_ai_suggestions_store_created_at
  ON store_ai_suggestions (store_id, created_at DESC);

