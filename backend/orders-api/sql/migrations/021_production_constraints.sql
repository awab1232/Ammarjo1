-- Production integrity constraints (PostgreSQL).
-- Apply during a maintenance window after reviewing data (orphans, duplicate emails).
-- CONNECTION: same database as DATABASE_URL / ORDERS_DATABASE_URL.

-- -----------------------------------------------------------------------------
-- 1) Unique non-empty emails (normalized by lower(trim(...)) for lookups)
-- -----------------------------------------------------------------------------
-- Before applying, deduplicate: SELECT lower(trim(email)), count(*) FROM users GROUP BY 1 HAVING count(*) > 1;
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email_normalized
  ON users (lower(trim(email)))
  WHERE email IS NOT NULL AND length(trim(email)) > 0;

-- -----------------------------------------------------------------------------
-- 2) orders.user_id stores Firebase Auth UID — FK to users.firebase_uid (not users.id)
-- -----------------------------------------------------------------------------
-- Orphan cleanup example (review before running):
-- DELETE FROM orders o WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.firebase_uid = o.user_id);
DO $$
BEGIN
  ALTER TABLE orders
    ADD CONSTRAINT fk_orders_user_firebase
    FOREIGN KEY (user_id) REFERENCES users (firebase_uid);
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_foreign_key THEN
    RAISE NOTICE 'fk_orders_user_firebase skipped: fix orphan user_id rows first';
END $$;

-- -----------------------------------------------------------------------------
-- 3) products.store_id → stores.id (domain schema already defines this; safe if missing)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  ALTER TABLE products
    ADD CONSTRAINT fk_products_store
    FOREIGN KEY (store_id) REFERENCES stores (id) ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_foreign_key THEN
    RAISE NOTICE 'fk_products_store skipped: fix orphan store_id rows first';
END $$;

-- -----------------------------------------------------------------------------
-- 4) SKU uniqueness (same as production-hardening-indexes.sql; idempotent)
-- -----------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_product_variants_product_sku
  ON product_variants (product_id, sku)
  WHERE sku IS NOT NULL AND length(trim(sku)) > 0;
