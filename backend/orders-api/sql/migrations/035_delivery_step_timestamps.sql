-- Per-step timestamps for delivery timeline (Flutter OrderTrackingPage).

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS delivery_on_the_way_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivery_delivered_at TIMESTAMPTZ;

COMMENT ON COLUMN orders.delivery_on_the_way_at IS 'When delivery_status became on_the_way';
COMMENT ON COLUMN orders.delivery_delivered_at IS 'When delivery_status became delivered';
