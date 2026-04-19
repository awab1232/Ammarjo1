-- Caps optional customer-triggered retries after `no_driver_found` (see DriversService.retryAssignment).

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS delivery_manual_retries INT NOT NULL DEFAULT 0;

COMMENT ON COLUMN orders.delivery_manual_retries IS 'Count of POST /orders/:id/retry-assignment calls (capped in application code).';
