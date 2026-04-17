-- Additive multi-region + idempotency columns for shared-global PostgreSQL outbox.
-- Apply before setting EVENT_OUTBOX_MULTI_REGION=1.
-- No breaking changes: new columns nullable; existing rows remain valid.

ALTER TABLE event_outbox ADD COLUMN IF NOT EXISTS region TEXT;
ALTER TABLE event_outbox ADD COLUMN IF NOT EXISTS processing_region TEXT;
ALTER TABLE event_outbox ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

COMMENT ON COLUMN event_outbox.region IS 'Target region for delivery; NULL = any region may claim.';
COMMENT ON COLUMN event_outbox.processing_region IS 'Region that claimed the row (SKIP LOCKED + region filter prevents cross-region dupes).';
COMMENT ON COLUMN event_outbox.idempotency_key IS 'Optional app-supplied dedupe key; globally unique when set.';

-- At most one row per non-null idempotency_key (distributed idempotency).
CREATE UNIQUE INDEX IF NOT EXISTS idx_event_outbox_idempotency_key
  ON event_outbox (idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_event_outbox_region_pending
  ON event_outbox (region, status, next_attempt_at)
  WHERE status = 'pending';
