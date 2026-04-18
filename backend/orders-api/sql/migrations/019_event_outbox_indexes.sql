-- Additive performance indexes for event_outbox (high throughput, multi-worker).
-- Uses plain CREATE INDEX (not CONCURRENTLY) so this file runs via Node/postgres
-- migration runner, which executes inside a transaction-capable session.
-- For zero-lock builds on huge tables, run equivalent CONCURRENTLY statements manually in psql.

-- Claim path: pending + ready rows ordered by next_attempt_at, created_at (matches worker ORDER BY).
CREATE INDEX IF NOT EXISTS idx_event_outbox_pending_claim
  ON event_outbox (next_attempt_at ASC, created_at ASC)
  WHERE status = 'pending';

-- Timeline / analytics: picked_by_worker_at range scans
CREATE INDEX IF NOT EXISTS idx_event_outbox_picked_by_worker_at
  ON event_outbox (picked_by_worker_at)
  WHERE picked_by_worker_at IS NOT NULL;

-- Alert / dashboard: status + retry_count for backlog histograms
CREATE INDEX IF NOT EXISTS idx_event_outbox_status_retry
  ON event_outbox (status, retry_count)
  WHERE status IN ('pending', 'processing', 'failed');

-- Optional: created_at for time-window scans (if not already covered by existing idx)
CREATE INDEX IF NOT EXISTS idx_event_outbox_created_at
  ON event_outbox (created_at DESC);

-- ---------------------------------------------------------------------------
-- Partitioning (manual migration project — NOT applied here):
-- For sustained 1M+ rows/day, consider RANGE partitioning on created_at (monthly)
-- or on a generated date from event_id. Requires table rewrite; plan a maintenance window.
-- ---------------------------------------------------------------------------
