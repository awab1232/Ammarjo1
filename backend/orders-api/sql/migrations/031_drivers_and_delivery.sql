-- Delivery drivers + order assignment (extends existing orders table; order_id stays TEXT PK).

CREATE TABLE IF NOT EXISTS drivers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT,
  phone TEXT,
  -- Links driver app login (Firebase UID) to this row; required for authenticated driver routes.
  auth_uid TEXT UNIQUE,
  is_available BOOLEAN NOT NULL DEFAULT true,
  status TEXT NOT NULL DEFAULT 'offline',
  current_lat NUMERIC,
  current_lng NUMERIC,
  -- Last order this driver rejected (UX / debugging); exclusions for reassignment use order_driver_rejections.
  last_rejected_order_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_drivers_auth_uid ON drivers (auth_uid) WHERE auth_uid IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_drivers_available_online
  ON drivers (is_available, status)
  WHERE is_available = true AND status = 'online';

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS driver_id UUID REFERENCES drivers (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS delivery_status TEXT DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS delivery_lat NUMERIC,
  ADD COLUMN IF NOT EXISTS delivery_lng NUMERIC,
  ADD COLUMN IF NOT EXISTS delivery_assign_attempts INT NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_orders_driver_id ON orders (driver_id);
CREATE INDEX IF NOT EXISTS idx_orders_delivery_status ON orders (delivery_status);

COMMENT ON COLUMN orders.delivery_status IS 'pending | assigned | accepted | on_the_way | delivered | cancelled';

-- Tracks every driver who rejected an order so reassignment never loops infinitely.
CREATE TABLE IF NOT EXISTS order_driver_rejections (
  order_id TEXT NOT NULL REFERENCES orders (order_id) ON DELETE CASCADE,
  driver_id UUID NOT NULL REFERENCES drivers (id) ON DELETE CASCADE,
  rejected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (order_id, driver_id)
);

CREATE INDEX IF NOT EXISTS idx_order_driver_rejections_driver ON order_driver_rejections (driver_id);
