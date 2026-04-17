-- Phase 6 performance hardening indexes (additive).
-- Run in production with CONCURRENTLY (outside transaction) when needed.

-- service_requests: cursor + status dashboards
CREATE INDEX IF NOT EXISTS idx_service_requests_status_updated_at
  ON service_requests (status, updated_at DESC, id DESC);

-- ratings_reviews: target timeline reads
CREATE INDEX IF NOT EXISTS idx_ratings_reviews_target_created
  ON ratings_reviews (target_type, target_id, created_at DESC);

-- wholesale_orders: admin activity and store/wholesaler reads
CREATE INDEX IF NOT EXISTS idx_wholesale_orders_created_at
  ON wholesale_orders (created_at DESC);

-- event_outbox: DLQ and lag scans
CREATE INDEX IF NOT EXISTS idx_event_outbox_failed_at
  ON event_outbox (failed_at DESC)
  WHERE failed_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_event_outbox_status_next_attempt
  ON event_outbox (status, next_attempt_at ASC, created_at ASC);

