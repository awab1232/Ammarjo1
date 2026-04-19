-- ETA, assignment timeout anchor, optional user profile coordinates for delivery geocoding.

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS last_lat NUMERIC,
  ADD COLUMN IF NOT EXISTS last_lng NUMERIC;

COMMENT ON COLUMN users.last_lat IS 'Last known customer latitude (optional; used when order payload lacks coords).';
COMMENT ON COLUMN users.last_lng IS 'Last known customer longitude.';

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS eta_minutes INT,
  ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_orders_assigned_timeout
  ON orders (delivery_status, assigned_at)
  WHERE delivery_status = 'assigned' AND assigned_at IS NOT NULL;

COMMENT ON COLUMN orders.eta_minutes IS 'Estimated drive time to customer at assign time (40 km/h assumption).';
COMMENT ON COLUMN orders.assigned_at IS 'When current driver was assigned; used for 30s accept timeout.';
