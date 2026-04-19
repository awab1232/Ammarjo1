-- Auto-retry scheduling when delivery_status = no_driver_found (see DriversService.processNoDriverAutoRetries).

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS no_driver_found_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivery_auto_retry_count INT NOT NULL DEFAULT 0;

COMMENT ON COLUMN orders.no_driver_found_at IS 'Set when entering no_driver_found; used for 60s delayed auto retry.';
COMMENT ON COLUMN orders.delivery_auto_retry_count IS 'Automatic re-assign attempts after no_driver_found (max 2 in app code).';

CREATE INDEX IF NOT EXISTS idx_orders_no_driver_auto_retry
  ON orders (delivery_status, no_driver_found_at)
  WHERE delivery_status = 'no_driver_found' AND no_driver_found_at IS NOT NULL;
