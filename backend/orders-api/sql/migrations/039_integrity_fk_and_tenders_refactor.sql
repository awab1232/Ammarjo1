-- 039_integrity_fk_and_tenders_refactor.sql
SET client_encoding TO 'UTF8';

ALTER TABLE stores
  ADD CONSTRAINT fk_stores_owner_uid
  FOREIGN KEY (owner_id) REFERENCES users(firebase_uid)
  ON UPDATE CASCADE
  ON DELETE RESTRICT
  NOT VALID;

ALTER TABLE orders ADD COLUMN IF NOT EXISTS store_id_legacy text;
UPDATE orders SET store_id_legacy = store_id WHERE store_id_legacy IS NULL;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS store_id_uuid uuid;
UPDATE orders o
SET store_id_uuid = s.id
FROM stores s
WHERE s.id::text = o.store_id
  AND o.store_id_uuid IS NULL;
ALTER TABLE orders
  ADD CONSTRAINT fk_orders_store_uuid
  FOREIGN KEY (store_id_uuid) REFERENCES stores(id)
  ON UPDATE CASCADE
  ON DELETE RESTRICT
  NOT VALID;
CREATE INDEX IF NOT EXISTS idx_orders_store_id_uuid ON orders (store_id_uuid);

ALTER TABLE cart_items ADD COLUMN IF NOT EXISTS store_id_legacy text;
UPDATE cart_items SET store_id_legacy = store_id WHERE store_id_legacy IS NULL;
ALTER TABLE cart_items ADD COLUMN IF NOT EXISTS store_id_uuid uuid;
UPDATE cart_items c
SET store_id_uuid = s.id
FROM stores s
WHERE s.id::text = c.store_id
  AND c.store_id_uuid IS NULL;
ALTER TABLE cart_items
  ADD CONSTRAINT fk_cart_items_user_uid
  FOREIGN KEY (user_id) REFERENCES users(firebase_uid)
  ON UPDATE CASCADE
  ON DELETE CASCADE
  NOT VALID;
ALTER TABLE cart_items
  ADD CONSTRAINT fk_cart_items_store_uuid
  FOREIGN KEY (store_id_uuid) REFERENCES stores(id)
  ON UPDATE CASCADE
  ON DELETE RESTRICT
  NOT VALID;
CREATE INDEX IF NOT EXISTS idx_cart_items_store_id_uuid ON cart_items (store_id_uuid);

ALTER TABLE tenders ADD COLUMN IF NOT EXISTS user_id text;
UPDATE tenders
SET user_id = customer_uid
WHERE user_id IS NULL OR btrim(user_id) = '';
ALTER TABLE tenders ADD COLUMN IF NOT EXISTS category_id uuid;
ALTER TABLE tenders
  ADD CONSTRAINT fk_tenders_customer_uid
  FOREIGN KEY (customer_uid) REFERENCES users(firebase_uid)
  ON UPDATE CASCADE
  ON DELETE CASCADE
  NOT VALID;
ALTER TABLE tenders
  ADD CONSTRAINT fk_tenders_user_id
  FOREIGN KEY (user_id) REFERENCES users(firebase_uid)
  ON UPDATE CASCADE
  ON DELETE CASCADE
  NOT VALID;
ALTER TABLE tenders
  ADD CONSTRAINT fk_tenders_category_id
  FOREIGN KEY (category_id) REFERENCES categories(id)
  ON UPDATE CASCADE
  ON DELETE SET NULL
  NOT VALID;
CREATE INDEX IF NOT EXISTS idx_tenders_user_id_updated ON tenders (user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_tenders_category_id ON tenders (category_id);

ALTER TABLE tender_offers ADD COLUMN IF NOT EXISTS store_id_legacy text;
UPDATE tender_offers SET store_id_legacy = store_id WHERE store_id_legacy IS NULL;
ALTER TABLE tender_offers ADD COLUMN IF NOT EXISTS store_id_uuid uuid;
UPDATE tender_offers t
SET store_id_uuid = s.id
FROM stores s
WHERE s.id::text = t.store_id
  AND t.store_id_uuid IS NULL;
ALTER TABLE tender_offers
  ADD CONSTRAINT fk_tender_offers_store_uuid
  FOREIGN KEY (store_id_uuid) REFERENCES stores(id)
  ON UPDATE CASCADE
  ON DELETE RESTRICT
  NOT VALID;
CREATE INDEX IF NOT EXISTS idx_tender_offers_store_id_uuid ON tender_offers (store_id_uuid);

CREATE TABLE IF NOT EXISTS technicians (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id text NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  category_id uuid,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_technicians_user_uid
    FOREIGN KEY (user_id) REFERENCES users(firebase_uid)
    ON UPDATE CASCADE
    ON DELETE CASCADE
    NOT VALID,
  CONSTRAINT fk_technicians_category
    FOREIGN KEY (category_id) REFERENCES categories(id)
    ON UPDATE CASCADE
    ON DELETE SET NULL
    NOT VALID
);
CREATE INDEX IF NOT EXISTS idx_technicians_user_id ON technicians (user_id);
CREATE INDEX IF NOT EXISTS idx_technicians_status ON technicians (status);
CREATE INDEX IF NOT EXISTS idx_technicians_category_id ON technicians (category_id);
