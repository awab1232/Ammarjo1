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

-- 008 already created store_categories (catalog shape: order_index, no parent_id).
-- CREATE IF NOT EXISTS is then a no-op; add hybrid-builder columns before indexes.
ALTER TABLE store_categories ADD COLUMN IF NOT EXISTS parent_id uuid;
ALTER TABLE store_categories ADD COLUMN IF NOT EXISTS image_url text NOT NULL DEFAULT '';
ALTER TABLE store_categories ADD COLUMN IF NOT EXISTS sort_order int NOT NULL DEFAULT 0;
ALTER TABLE store_categories ADD COLUMN IF NOT EXISTS is_ai_generated boolean NOT NULL DEFAULT true;
ALTER TABLE store_categories ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT NOW();

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'store_categories'
      AND column_name = 'order_index'
  ) THEN
    UPDATE store_categories SET sort_order = COALESCE(order_index, sort_order);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'store_categories'
      AND c.conname = 'store_categories_parent_id_fkey'
  ) THEN
    ALTER TABLE store_categories
      ADD CONSTRAINT store_categories_parent_id_fkey
      FOREIGN KEY (parent_id) REFERENCES store_categories(id) ON DELETE SET NULL;
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

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

