-- App users: source of truth for RBAC (Firebase ID token is identity only).
-- Apply: psql "$DATABASE_URL" -f database/users_schema.sql

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid TEXT UNIQUE NOT NULL,
  email TEXT,
  role TEXT NOT NULL DEFAULT 'customer',
  tenant_id UUID,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Optional scoped ids (preferred over token claims for store_owner / wholesaler_owner).
ALTER TABLE users ADD COLUMN IF NOT EXISTS store_id TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS wholesaler_id TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS store_type TEXT;

CREATE INDEX IF NOT EXISTS idx_users_firebase_uid ON users (firebase_uid);
CREATE INDEX IF NOT EXISTS idx_users_role ON users (role);
CREATE INDEX IF NOT EXISTS idx_users_tenant_id ON users (tenant_id);

COMMENT ON TABLE users IS 'Backend RBAC source of truth; firebase_uid maps to Firebase Auth uid.';
