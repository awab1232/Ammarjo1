-- Adds phone + password-hash columns to `users` so the app can log in with
-- phone + password (OTP stays only for signup verification).
--
-- Safe to run multiple times (all statements are idempotent).

ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_updated_at TIMESTAMPTZ;

-- Normalised phone lookup (E.164). Unique partial index so multiple NULLs are allowed.
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_phone_e164
  ON users ((NULLIF(btrim(phone), '')))
  WHERE phone IS NOT NULL AND btrim(phone) <> '';

CREATE INDEX IF NOT EXISTS idx_users_phone ON users (phone)
  WHERE phone IS NOT NULL;

COMMENT ON COLUMN users.phone           IS 'Normalised E.164 phone (e.g. +9627XXXXXXXX) used for phone+password login.';
COMMENT ON COLUMN users.password_hash   IS 'bcrypt hash of the user password (NULL for accounts that have not set one).';
COMMENT ON COLUMN users.password_updated_at IS 'Timestamp of the last password set/change.';
