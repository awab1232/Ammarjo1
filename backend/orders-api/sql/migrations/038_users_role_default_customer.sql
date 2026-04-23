-- Ensure RBAC role column exists and defaults to customer.
-- Safe to run repeatedly.

ALTER TABLE users ADD COLUMN IF NOT EXISTS role TEXT;
UPDATE users SET role = 'customer' WHERE role IS NULL OR btrim(role) = '';
ALTER TABLE users ALTER COLUMN role SET DEFAULT 'customer';
ALTER TABLE users ALTER COLUMN role SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_users_role ON users (role);

