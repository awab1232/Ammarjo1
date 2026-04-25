-- Customer saved delivery address (JSON) + system placeholder user for order FK reassign on account delete.

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS saved_address JSONB;

COMMENT ON COLUMN users.saved_address IS 'Optional delivery address JSON: address1, address2, city, notes, lat, lng.';

INSERT INTO users (firebase_uid, email, role, is_active)
VALUES ('_account_deleted_placeholder_', NULL, 'customer', false)
ON CONFLICT (firebase_uid) DO NOTHING;
