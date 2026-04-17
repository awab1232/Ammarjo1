CREATE TABLE IF NOT EXISTS ratings_reviews (
  id uuid PRIMARY KEY,
  target_type text NOT NULL CHECK (target_type IN ('technician', 'store', 'home_store')),
  target_id text NOT NULL,
  reviewer_id text NOT NULL,
  rating int NOT NULL CHECK (rating >= 1 AND rating <= 5),
  review_text text NULL,
  service_request_id uuid NULL,
  order_id text NULL,
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ratings_reviews_target ON ratings_reviews (target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_ratings_reviews_reviewer ON ratings_reviews (reviewer_id);
CREATE INDEX IF NOT EXISTS idx_ratings_reviews_service_request_id ON ratings_reviews (service_request_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_ratings_reviews_reviewer_service_request
  ON ratings_reviews (reviewer_id, service_request_id)
  WHERE service_request_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS ratings_aggregates (
  target_type text NOT NULL CHECK (target_type IN ('technician', 'store', 'home_store')),
  target_id text NOT NULL,
  avg_rating numeric(4,2) NOT NULL DEFAULT 0,
  total_reviews int NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (target_type, target_id)
);

