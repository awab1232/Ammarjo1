-- 041_strict_closure_enforcement.sql
SET client_encoding TO 'UTF8';

-- Canonical tender images relation
CREATE TABLE IF NOT EXISTS tender_images (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tender_id uuid NOT NULL REFERENCES tenders(id) ON DELETE CASCADE,
  image_url text,
  image_base64 text,
  created_at timestamptz NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_tender_images_tender_id ON tender_images (tender_id, created_at);

-- Enforce non-null critical relations
ALTER TABLE tenders ALTER COLUMN category_id SET NOT NULL;
ALTER TABLE technicians ALTER COLUMN category_id SET NOT NULL;

-- Validate previously deferred constraints
ALTER TABLE stores VALIDATE CONSTRAINT fk_stores_owner_uid;
ALTER TABLE orders VALIDATE CONSTRAINT fk_orders_store_uuid;
ALTER TABLE cart_items VALIDATE CONSTRAINT fk_cart_items_user_uid;
ALTER TABLE cart_items VALIDATE CONSTRAINT fk_cart_items_store_uuid;
ALTER TABLE tenders VALIDATE CONSTRAINT fk_tenders_user_id;
ALTER TABLE tenders VALIDATE CONSTRAINT fk_tenders_category_id;
ALTER TABLE tender_offers VALIDATE CONSTRAINT fk_tender_offers_store_uuid;
ALTER TABLE technicians VALIDATE CONSTRAINT fk_technicians_user_uid;
ALTER TABLE technicians VALIDATE CONSTRAINT fk_technicians_category;

-- Drop legacy columns after migration to strict canonical model
ALTER TABLE orders DROP COLUMN IF EXISTS store_id;
ALTER TABLE orders DROP COLUMN IF EXISTS store_id_legacy;

ALTER TABLE cart_items DROP COLUMN IF EXISTS store_id;
ALTER TABLE cart_items DROP COLUMN IF EXISTS store_id_legacy;

ALTER TABLE tenders DROP COLUMN IF EXISTS customer_uid;
ALTER TABLE tenders DROP COLUMN IF EXISTS category;

ALTER TABLE tender_offers DROP COLUMN IF EXISTS store_id;
ALTER TABLE tender_offers DROP COLUMN IF EXISTS store_id_legacy;
