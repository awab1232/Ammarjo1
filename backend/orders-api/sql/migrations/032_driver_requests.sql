-- Driver onboarding: user submits request; admin approves → row in `drivers`.

CREATE TABLE IF NOT EXISTS driver_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_uid TEXT NOT NULL,
  full_name TEXT NOT NULL,
  phone TEXT NOT NULL,
  identity_image_url TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_at TIMESTAMPTZ,
  reviewed_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_driver_requests_auth_created ON driver_requests (auth_uid, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_driver_requests_one_pending_per_auth
  ON driver_requests (auth_uid) WHERE status = 'pending';
