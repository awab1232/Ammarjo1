-- Per-store commission % + per-order ledger lines (additive; safe on re-run).
ALTER TABLE stores ADD COLUMN IF NOT EXISTS commission_percent numeric(12,4) NOT NULL DEFAULT 0;

ALTER TABLE store_commission_orders ADD COLUMN IF NOT EXISTS commission_percent numeric(12,4) NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS store_commission_ledger_entry (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  order_id text NOT NULL,
  amount numeric(18,4) NOT NULL,
  commission_percent numeric(12,4) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (store_id, order_id)
);

CREATE INDEX IF NOT EXISTS idx_store_commission_ledger_entry_store_created
  ON store_commission_ledger_entry (store_id, created_at DESC);
