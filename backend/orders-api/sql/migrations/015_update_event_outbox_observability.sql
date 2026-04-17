-- Additive migration: observability + lifecycle columns for existing event_outbox deployments.
-- Safe to run multiple times (IF NOT EXISTS).

ALTER TABLE event_outbox ADD COLUMN IF NOT EXISTS trace_id TEXT;
ALTER TABLE event_outbox ADD COLUMN IF NOT EXISTS source_service TEXT;
ALTER TABLE event_outbox ADD COLUMN IF NOT EXISTS correlation_id TEXT;
ALTER TABLE event_outbox ADD COLUMN IF NOT EXISTS emitted_at TIMESTAMPTZ;
ALTER TABLE event_outbox ADD COLUMN IF NOT EXISTS picked_by_worker_at TIMESTAMPTZ;
ALTER TABLE event_outbox ADD COLUMN IF NOT EXISTS failed_at TIMESTAMPTZ;

UPDATE event_outbox SET emitted_at = COALESCE(emitted_at, created_at) WHERE emitted_at IS NULL;

COMMENT ON COLUMN event_outbox.trace_id IS 'Shared across related events in one logical operation.';
COMMENT ON COLUMN event_outbox.source_service IS 'orders | catalog | system';
COMMENT ON COLUMN event_outbox.correlation_id IS 'Business key: orderId, productId chain, etc.';
COMMENT ON COLUMN event_outbox.emitted_at IS 'When the event row was written (enqueue).';
COMMENT ON COLUMN event_outbox.picked_by_worker_at IS 'Last time a worker claimed this row for delivery.';
COMMENT ON COLUMN event_outbox.failed_at IS 'When the row entered terminal failed (dead-letter) state.';
