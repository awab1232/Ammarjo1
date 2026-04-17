-- Production database hardening (PostgreSQL).
-- Apply during a maintenance window. Review for conflicts with existing constraints.
-- CONNECTION: same database as DATABASE_URL / ORDERS_DATABASE_URL.

-- Lookup indexes (IF NOT EXISTS is safe to re-run)
CREATE INDEX IF NOT EXISTS idx_users_email_lower ON users (lower(trim(email)))
  WHERE email IS NOT NULL AND length(trim(email)) > 0;

CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders (user_id);

CREATE INDEX IF NOT EXISTS idx_products_store_id ON products (store_id);

-- SKU uniqueness: prefer per-product scope (avoids collisions across stores).
-- If your deployment requires globally unique SKUs, replace with UNIQUE (sku) WHERE ...
CREATE UNIQUE INDEX IF NOT EXISTS uq_product_variants_product_sku
  ON product_variants (product_id, sku)
  WHERE sku IS NOT NULL AND length(trim(sku)) > 0;

-- Optional: enforce unique non-null emails (uncomment if duplicates are cleaned up first)
-- CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email_lower ON users (lower(trim(email)))
--   WHERE email IS NOT NULL AND length(trim(email)) > 0;
