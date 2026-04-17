-- Final post-migration safety patch (additive only).
-- Rules:
-- - No drops
-- - No destructive data changes
-- - IF NOT EXISTS everywhere possible

-- 1) ORDERS DOMAIN FIX (variant support on order_items if table exists)
DO $$
BEGIN
  IF to_regclass('public.order_items') IS NOT NULL THEN
    ALTER TABLE public.order_items
      ADD COLUMN IF NOT EXISTS variant_id UUID;
    ALTER TABLE public.order_items
      ADD COLUMN IF NOT EXISTS variant_snapshot JSONB;
  END IF;
END $$;

-- 2) ANALYTICS BACKEND MIGRATION FINAL
CREATE TABLE IF NOT EXISTS analytics_daily (
  id UUID PRIMARY KEY,
  date DATE UNIQUE,
  total_orders INT DEFAULT 0,
  total_revenue NUMERIC DEFAULT 0,
  total_users INT DEFAULT 0,
  total_stores INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS analytics_events (
  id UUID PRIMARY KEY,
  event_type TEXT,
  user_id UUID,
  payload JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

-- 3) TENANT ISOLATION HARDENING
ALTER TABLE IF EXISTS stores ADD COLUMN IF NOT EXISTS tenant_id UUID;
ALTER TABLE IF EXISTS products ADD COLUMN IF NOT EXISTS tenant_id UUID;
ALTER TABLE IF EXISTS orders ADD COLUMN IF NOT EXISTS tenant_id UUID;
ALTER TABLE IF EXISTS service_requests ADD COLUMN IF NOT EXISTS tenant_id UUID;
ALTER TABLE IF EXISTS wholesale_orders ADD COLUMN IF NOT EXISTS tenant_id UUID;

-- 4) PERFORMANCE INDEXES
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);

CREATE INDEX IF NOT EXISTS idx_products_store_id ON products(store_id);
CREATE INDEX IF NOT EXISTS idx_products_category_id ON products(category_id);

CREATE INDEX IF NOT EXISTS idx_service_requests_status ON service_requests(status);
CREATE INDEX IF NOT EXISTS idx_service_requests_technician ON service_requests(technician_id);

CREATE INDEX IF NOT EXISTS idx_stores_owner_id ON stores(owner_id);

-- 5) OUTBOX SAFETY CHECK
CREATE INDEX IF NOT EXISTS idx_event_outbox_status ON event_outbox(status);
CREATE INDEX IF NOT EXISTS idx_event_outbox_created ON event_outbox(created_at);
