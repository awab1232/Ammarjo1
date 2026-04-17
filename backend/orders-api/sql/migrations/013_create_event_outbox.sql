-- Domain event outbox (durable delivery, worker-driven). Run against the same DB as orders/catalog.
-- PostgreSQL 13+ (gen_random_uuid).

CREATE TABLE IF NOT EXISTS event_outbox (
  event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL CHECK (status IN ('pending', 'processing', 'processed', 'failed')),
  retry_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  emitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  picked_by_worker_at TIMESTAMPTZ,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processing_started_at TIMESTAMPTZ,
  trace_id TEXT,
  source_service TEXT,
  correlation_id TEXT
);

CREATE INDEX IF NOT EXISTS idx_event_outbox_worker
  ON event_outbox (status, next_attempt_at, created_at)
  WHERE status IN ('pending', 'processing');

COMMENT ON TABLE event_outbox IS 'Durable domain events; worker claims pending rows, dispatches handlers, marks processed/failed.';
