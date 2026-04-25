-- Driver earnings column + ledger (80% of delivery fee credited on delivered; see DriversService).

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS driver_earnings_amount NUMERIC(10,2) DEFAULT 0;

CREATE TABLE IF NOT EXISTS driver_earnings_ledger (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES drivers(id),
  order_id TEXT NOT NULL REFERENCES orders(order_id),
  amount NUMERIC(10,2) NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  paid_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_driver_earnings_ledger_driver ON driver_earnings_ledger (driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_earnings_ledger_order ON driver_earnings_ledger (order_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_driver_earnings_ledger_order_id ON driver_earnings_ledger (order_id);

COMMENT ON COLUMN orders.driver_earnings_amount IS 'Last recorded driver share for this order (JOD, optional denormalized total).';
COMMENT ON TABLE driver_earnings_ledger IS 'Per-delivery driver earnings; status pending until payout.';
