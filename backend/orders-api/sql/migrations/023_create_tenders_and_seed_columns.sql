-- 023_create_tenders_and_seed_columns.sql
-- Clean-up migration that:
--  1. Ensures the database client encoding is UTF-8 (Arabic text safety).
--  2. Relaxes the `stores.store_type` CHECK constraint to accept retail/wholesale.
--  3. Adds `description`, `category`, `logo_url`, `image_url` columns to `stores`
--     (the stores.service expects these but they were never created in the
--     initial schema).
--  4. Adds an `avatar_url` column to `admin_technicians` for profile images.
--  5. Creates the missing lookup / domain tables: `store_types`,
--     `home_sections`, `sub_categories`.
--  6. Creates the customer-facing `tenders` + `tender_offers` tables that
--     back the new `/tenders/*` REST routes.

SET client_encoding TO 'UTF8';

-- --------------------------------------------------------------------------
-- 1. stores: missing columns + relaxed check
-- --------------------------------------------------------------------------
ALTER TABLE stores ADD COLUMN IF NOT EXISTS description text NOT NULL DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS category    text NOT NULL DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS logo_url    text NOT NULL DEFAULT '';
ALTER TABLE stores ADD COLUMN IF NOT EXISTS image_url   text NOT NULL DEFAULT '';

ALTER TABLE stores DROP CONSTRAINT IF EXISTS stores_store_type_check;
ALTER TABLE stores
  ADD CONSTRAINT stores_store_type_check
  CHECK (store_type IN (
    'construction_store',
    'home_store',
    'wholesale_store',
    'retail',
    'wholesale'
  ));

-- --------------------------------------------------------------------------
-- 2. admin_technicians: avatar column
-- --------------------------------------------------------------------------
ALTER TABLE admin_technicians ADD COLUMN IF NOT EXISTS avatar_url text NOT NULL DEFAULT '';

-- --------------------------------------------------------------------------
-- 3. store_types (referenced by stores.store_type_id)
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS store_types (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  key text NOT NULL UNIQUE,
  icon text,
  image text,
  display_order int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT TRUE,
  created_at timestamptz NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_store_types_active_order
  ON store_types (is_active, display_order, created_at);

-- --------------------------------------------------------------------------
-- 4. home_sections + sub_categories (home feed targeting)
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS home_sections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  image text,
  type text NOT NULL,
  is_active boolean NOT NULL DEFAULT TRUE,
  sort_order int NOT NULL DEFAULT 0,
  store_type_id uuid REFERENCES store_types(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_home_sections_active_sort
  ON home_sections (is_active, sort_order, created_at);
CREATE INDEX IF NOT EXISTS idx_home_sections_store_type
  ON home_sections (store_type_id, is_active, sort_order, created_at);

CREATE TABLE IF NOT EXISTS sub_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  home_section_id uuid REFERENCES home_sections(id) ON DELETE CASCADE,
  name text NOT NULL,
  image text,
  sort_order int DEFAULT 0,
  is_active boolean DEFAULT TRUE,
  created_at timestamptz NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_sub_categories_section_active_sort
  ON sub_categories (home_section_id, is_active, sort_order, created_at);

-- --------------------------------------------------------------------------
-- 5. tenders + tender_offers (customer-facing /tenders routes)
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tenders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_uid text NOT NULL,
  customer_name text NOT NULL DEFAULT '',
  category text NOT NULL DEFAULT '',
  description text NOT NULL DEFAULT '',
  city text NOT NULL DEFAULT '',
  image_url text,
  image_base64 text,
  store_type_id uuid,
  store_type_key text,
  store_type_name text,
  status text NOT NULL DEFAULT 'open',
  accepted_offer_id uuid,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_tenders_customer
  ON tenders (customer_uid, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_tenders_status_type
  ON tenders (status, store_type_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS tender_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tender_id uuid NOT NULL REFERENCES tenders(id) ON DELETE CASCADE,
  store_id text NOT NULL DEFAULT '',
  store_name text NOT NULL DEFAULT '',
  store_owner_uid text NOT NULL DEFAULT '',
  price numeric(12,2) NOT NULL DEFAULT 0,
  note text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_tender_offers_tender
  ON tender_offers (tender_id, updated_at DESC);
