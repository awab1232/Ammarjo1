-- Hardening for phone+password auth architecture.
-- Safe to run repeatedly.

ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_phone_non_empty
  ON users ((NULLIF(btrim(phone), '')))
  WHERE phone IS NOT NULL AND btrim(phone) <> '';

CREATE INDEX IF NOT EXISTS idx_users_phone_lookup
  ON users (phone)
  WHERE phone IS NOT NULL AND btrim(phone) <> '';

COMMENT ON COLUMN users.firebase_uid IS 'Firebase UID from OTP verification token.';
COMMENT ON COLUMN users.phone IS 'Normalized Jordan phone for phone+password login (9627XXXXXXXX or +9627XXXXXXXX).';
COMMENT ON COLUMN users.password_hash IS 'bcrypt password hash managed by backend.';
