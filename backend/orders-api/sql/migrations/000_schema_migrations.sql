-- Migration tracking table (runner also ensures this exists before checks).
-- Applied once; subsequent boots skip via schema_migrations row for this filename.

CREATE TABLE IF NOT EXISTS schema_migrations (
  filename TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
