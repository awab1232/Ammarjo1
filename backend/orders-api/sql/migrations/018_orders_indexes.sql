-- Run on existing deployments that already applied orders_schema.sql without the newer indexes.
CREATE INDEX IF NOT EXISTS idx_orders_user_created_desc ON orders (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);
CREATE INDEX IF NOT EXISTS idx_orders_user_status_created ON orders (user_id, status, created_at DESC);
