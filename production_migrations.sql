-- production_migrations.sql
-- Consolidated, idempotent production migration for 035 -> 043.
-- PostgreSQL target. Safe to re-run.

SET client_encoding TO 'UTF8';
CREATE EXTENSION IF NOT EXISTS pgcrypto;

BEGIN;

-- =========================================================
-- 035_delivery_step_timestamps.sql
-- =========================================================
ALTER TABLE IF EXISTS orders
  ADD COLUMN IF NOT EXISTS delivery_on_the_way_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivery_delivered_at TIMESTAMPTZ;

COMMENT ON COLUMN orders.delivery_on_the_way_at IS 'When delivery_status became on_the_way';
COMMENT ON COLUMN orders.delivery_delivered_at IS 'When delivery_status became delivered';

-- =========================================================
-- 036_notifications_queue_and_devices.sql
-- =========================================================
CREATE TABLE IF NOT EXISTS user_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  fcm_token TEXT NOT NULL UNIQUE,
  platform TEXT NOT NULL DEFAULT 'unknown',
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_devices_user_id ON user_devices (user_id);
CREATE INDEX IF NOT EXISTS idx_user_devices_last_seen_at ON user_devices (last_seen_at DESC);

ALTER TABLE IF EXISTS user_notifications
  ADD COLUMN IF NOT EXISTS event_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_notifications_user_event_id
  ON user_notifications (user_id, event_id)
  WHERE event_id IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_queue_status') THEN
    CREATE TYPE notification_queue_status AS ENUM ('pending', 'sent', 'failed');
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS notifications_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB,
  status notification_queue_status NOT NULL DEFAULT 'pending',
  retry_count INT NOT NULL DEFAULT 0,
  max_retries INT NOT NULL DEFAULT 3,
  event_id TEXT,
  inbox_notification_id UUID,
  last_attempt_at TIMESTAMPTZ,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_queue_status_created
  ON notifications_queue (status, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_notifications_queue_user_status
  ON notifications_queue (user_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS uq_notifications_queue_user_event_id
  ON notifications_queue (user_id, event_id)
  WHERE event_id IS NOT NULL;

-- =========================================================
-- 037_users_phone_password_hardening.sql
-- =========================================================
ALTER TABLE IF EXISTS users ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE IF EXISTS users ADD COLUMN IF NOT EXISTS password_hash TEXT;
ALTER TABLE IF EXISTS users ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_phone_non_empty
  ON users ((NULLIF(btrim(phone), '')))
  WHERE phone IS NOT NULL AND btrim(phone) <> '';

CREATE INDEX IF NOT EXISTS idx_users_phone_lookup
  ON users (phone)
  WHERE phone IS NOT NULL AND btrim(phone) <> '';

COMMENT ON COLUMN users.firebase_uid IS 'Firebase UID from OTP verification token.';
COMMENT ON COLUMN users.phone IS 'Normalized Jordan phone for phone+password login (9627XXXXXXXX or +9627XXXXXXXX).';
COMMENT ON COLUMN users.password_hash IS 'bcrypt password hash managed by backend.';

-- =========================================================
-- 038_users_role_default_customer.sql
-- =========================================================
ALTER TABLE IF EXISTS users ADD COLUMN IF NOT EXISTS role TEXT;
UPDATE users SET role = 'customer' WHERE role IS NULL OR btrim(role) = '';
ALTER TABLE IF EXISTS users ALTER COLUMN role SET DEFAULT 'customer';
ALTER TABLE IF EXISTS users ALTER COLUMN role SET NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_role ON users (role);

-- =========================================================
-- 039_integrity_fk_and_tenders_refactor.sql
-- =========================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'stores')
     AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_stores_owner_uid') THEN
    ALTER TABLE stores
      ADD CONSTRAINT fk_stores_owner_uid
      FOREIGN KEY (owner_id) REFERENCES users(firebase_uid)
      ON UPDATE CASCADE
      ON DELETE RESTRICT
      NOT VALID;
  END IF;
END$$;

ALTER TABLE IF EXISTS orders ADD COLUMN IF NOT EXISTS store_id_legacy TEXT;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'store_id'
  ) THEN
    UPDATE orders SET store_id_legacy = store_id WHERE store_id_legacy IS NULL;
  END IF;
END$$;

ALTER TABLE IF EXISTS orders ADD COLUMN IF NOT EXISTS store_id_uuid UUID;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'store_id'
  ) THEN
    UPDATE orders o
    SET store_id_uuid = s.id
    FROM stores s
    WHERE s.id::text = o.store_id
      AND o.store_id_uuid IS NULL;
  END IF;
END$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'orders')
     AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_orders_store_uuid') THEN
    ALTER TABLE orders
      ADD CONSTRAINT fk_orders_store_uuid
      FOREIGN KEY (store_id_uuid) REFERENCES stores(id)
      ON UPDATE CASCADE
      ON DELETE RESTRICT
      NOT VALID;
  END IF;
END$$;
CREATE INDEX IF NOT EXISTS idx_orders_store_id_uuid ON orders (store_id_uuid);

ALTER TABLE IF EXISTS cart_items ADD COLUMN IF NOT EXISTS store_id_legacy TEXT;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'cart_items' AND column_name = 'store_id'
  ) THEN
    UPDATE cart_items SET store_id_legacy = store_id WHERE store_id_legacy IS NULL;
  END IF;
END$$;

ALTER TABLE IF EXISTS cart_items ADD COLUMN IF NOT EXISTS store_id_uuid UUID;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'cart_items' AND column_name = 'store_id'
  ) THEN
    UPDATE cart_items c
    SET store_id_uuid = s.id
    FROM stores s
    WHERE s.id::text = c.store_id
      AND c.store_id_uuid IS NULL;
  END IF;
END$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'cart_items')
     AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_cart_items_user_uid') THEN
    ALTER TABLE cart_items
      ADD CONSTRAINT fk_cart_items_user_uid
      FOREIGN KEY (user_id) REFERENCES users(firebase_uid)
      ON UPDATE CASCADE
      ON DELETE CASCADE
      NOT VALID;
  END IF;
END$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'cart_items')
     AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_cart_items_store_uuid') THEN
    ALTER TABLE cart_items
      ADD CONSTRAINT fk_cart_items_store_uuid
      FOREIGN KEY (store_id_uuid) REFERENCES stores(id)
      ON UPDATE CASCADE
      ON DELETE RESTRICT
      NOT VALID;
  END IF;
END$$;

CREATE INDEX IF NOT EXISTS idx_cart_items_store_id_uuid ON cart_items (store_id_uuid);

ALTER TABLE IF EXISTS tenders ADD COLUMN IF NOT EXISTS user_id TEXT;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tenders' AND column_name = 'customer_uid'
  ) THEN
    UPDATE tenders
    SET user_id = customer_uid
    WHERE user_id IS NULL OR btrim(user_id) = '';
  END IF;
END$$;

ALTER TABLE IF EXISTS tenders ADD COLUMN IF NOT EXISTS category_id UUID;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tenders' AND column_name = 'customer_uid'
  ) AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_tenders_customer_uid') THEN
    ALTER TABLE tenders
      ADD CONSTRAINT fk_tenders_customer_uid
      FOREIGN KEY (customer_uid) REFERENCES users(firebase_uid)
      ON UPDATE CASCADE
      ON DELETE CASCADE
      NOT VALID;
  END IF;
END$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tenders')
     AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_tenders_user_id') THEN
    ALTER TABLE tenders
      ADD CONSTRAINT fk_tenders_user_id
      FOREIGN KEY (user_id) REFERENCES users(firebase_uid)
      ON UPDATE CASCADE
      ON DELETE CASCADE
      NOT VALID;
  END IF;
END$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tenders')
     AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_tenders_category_id') THEN
    ALTER TABLE tenders
      ADD CONSTRAINT fk_tenders_category_id
      FOREIGN KEY (category_id) REFERENCES categories(id)
      ON UPDATE CASCADE
      ON DELETE SET NULL
      NOT VALID;
  END IF;
END$$;

CREATE INDEX IF NOT EXISTS idx_tenders_user_id_updated ON tenders (user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_tenders_category_id ON tenders (category_id);

ALTER TABLE IF EXISTS tender_offers ADD COLUMN IF NOT EXISTS store_id_legacy TEXT;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tender_offers' AND column_name = 'store_id'
  ) THEN
    UPDATE tender_offers SET store_id_legacy = store_id WHERE store_id_legacy IS NULL;
  END IF;
END$$;

ALTER TABLE IF EXISTS tender_offers ADD COLUMN IF NOT EXISTS store_id_uuid UUID;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tender_offers' AND column_name = 'store_id'
  ) THEN
    UPDATE tender_offers t
    SET store_id_uuid = s.id
    FROM stores s
    WHERE s.id::text = t.store_id
      AND t.store_id_uuid IS NULL;
  END IF;
END$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tender_offers')
     AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_tender_offers_store_uuid') THEN
    ALTER TABLE tender_offers
      ADD CONSTRAINT fk_tender_offers_store_uuid
      FOREIGN KEY (store_id_uuid) REFERENCES stores(id)
      ON UPDATE CASCADE
      ON DELETE RESTRICT
      NOT VALID;
  END IF;
END$$;

CREATE INDEX IF NOT EXISTS idx_tender_offers_store_id_uuid ON tender_offers (store_id_uuid);

CREATE TABLE IF NOT EXISTS technicians (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  category_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'technicians')
     AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_technicians_user_uid') THEN
    ALTER TABLE technicians
      ADD CONSTRAINT fk_technicians_user_uid
      FOREIGN KEY (user_id) REFERENCES users(firebase_uid)
      ON UPDATE CASCADE
      ON DELETE CASCADE
      NOT VALID;
  END IF;
END$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'technicians')
     AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_technicians_category') THEN
    ALTER TABLE technicians
      ADD CONSTRAINT fk_technicians_category
      FOREIGN KEY (category_id) REFERENCES categories(id)
      ON UPDATE CASCADE
      ON DELETE SET NULL
      NOT VALID;
  END IF;
END$$;

CREATE INDEX IF NOT EXISTS idx_technicians_user_id ON technicians (user_id);
CREATE INDEX IF NOT EXISTS idx_technicians_status ON technicians (status);
CREATE INDEX IF NOT EXISTS idx_technicians_category_id ON technicians (category_id);

-- =========================================================
-- 040_fk_columns_backfill_and_enforce.sql
-- =========================================================
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'store_id'
  ) OR EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'store_id_legacy'
  ) THEN
    UPDATE orders o
    SET store_id_uuid = s.id
    FROM stores s
    WHERE o.store_id_uuid IS NULL
      AND s.id::text = COALESCE(NULLIF(o.store_id, ''), NULLIF(o.store_id_legacy, ''));
  END IF;
END$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'cart_items' AND column_name = 'store_id'
  ) OR EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'cart_items' AND column_name = 'store_id_legacy'
  ) THEN
    UPDATE cart_items c
    SET store_id_uuid = s.id
    FROM stores s
    WHERE c.store_id_uuid IS NULL
      AND s.id::text = COALESCE(NULLIF(c.store_id, ''), NULLIF(c.store_id_legacy, ''));
  END IF;
END$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tenders' AND column_name = 'customer_uid'
  ) THEN
    UPDATE tenders
    SET user_id = customer_uid
    WHERE user_id IS NULL OR btrim(user_id) = '';
  END IF;
END$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tender_offers' AND column_name = 'store_id'
  ) OR EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tender_offers' AND column_name = 'store_id_legacy'
  ) THEN
    UPDATE tender_offers t
    SET store_id_uuid = s.id
    FROM stores s
    WHERE t.store_id_uuid IS NULL
      AND s.id::text = COALESCE(NULLIF(t.store_id, ''), NULLIF(t.store_id_legacy, ''));
  END IF;
END$$;

DO $$
DECLARE
  v_orders_null BIGINT;
  v_cart_null BIGINT;
  v_tenders_null BIGINT;
  v_offers_null BIGINT;
BEGIN
  SELECT COUNT(*) INTO v_orders_null FROM orders WHERE store_id_uuid IS NULL;
  SELECT COUNT(*) INTO v_cart_null FROM cart_items WHERE store_id_uuid IS NULL;
  SELECT COUNT(*) INTO v_tenders_null FROM tenders WHERE user_id IS NULL OR btrim(user_id) = '';
  SELECT COUNT(*) INTO v_offers_null FROM tender_offers WHERE store_id_uuid IS NULL;

  IF v_orders_null > 0 OR v_cart_null > 0 OR v_tenders_null > 0 OR v_offers_null > 0 THEN
    RAISE EXCEPTION
      'FK backfill incomplete: orders.store_id_uuid=% cart_items.store_id_uuid=% tenders.user_id=% tender_offers.store_id_uuid=%',
      v_orders_null, v_cart_null, v_tenders_null, v_offers_null;
  END IF;
END $$;

ALTER TABLE IF EXISTS orders ALTER COLUMN store_id_uuid SET NOT NULL;
ALTER TABLE IF EXISTS cart_items ALTER COLUMN store_id_uuid SET NOT NULL;
ALTER TABLE IF EXISTS tenders ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE IF EXISTS tender_offers ALTER COLUMN store_id_uuid SET NOT NULL;

-- =========================================================
-- 041_strict_closure_enforcement.sql
-- =========================================================
CREATE TABLE IF NOT EXISTS tender_images (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tender_id UUID NOT NULL REFERENCES tenders(id) ON DELETE CASCADE,
  image_url TEXT,
  image_base64 TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tender_images_tender_id ON tender_images (tender_id, created_at);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tenders') THEN
    ALTER TABLE tenders ALTER COLUMN category_id SET NOT NULL;
  END IF;
END$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'technicians') THEN
    ALTER TABLE technicians ALTER COLUMN category_id SET NOT NULL;
  END IF;
END$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_stores_owner_uid') THEN
    ALTER TABLE stores VALIDATE CONSTRAINT fk_stores_owner_uid;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_orders_store_uuid') THEN
    ALTER TABLE orders VALIDATE CONSTRAINT fk_orders_store_uuid;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_cart_items_user_uid') THEN
    ALTER TABLE cart_items VALIDATE CONSTRAINT fk_cart_items_user_uid;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_cart_items_store_uuid') THEN
    ALTER TABLE cart_items VALIDATE CONSTRAINT fk_cart_items_store_uuid;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_tenders_user_id') THEN
    ALTER TABLE tenders VALIDATE CONSTRAINT fk_tenders_user_id;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_tenders_category_id') THEN
    ALTER TABLE tenders VALIDATE CONSTRAINT fk_tenders_category_id;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_tender_offers_store_uuid') THEN
    ALTER TABLE tender_offers VALIDATE CONSTRAINT fk_tender_offers_store_uuid;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_technicians_user_uid') THEN
    ALTER TABLE technicians VALIDATE CONSTRAINT fk_technicians_user_uid;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_technicians_category') THEN
    ALTER TABLE technicians VALIDATE CONSTRAINT fk_technicians_category;
  END IF;
END$$;

-- NOTE: Legacy-column DROP operations intentionally omitted for idempotent/safe production runs.

-- =========================================================
-- 042_add_driver_earnings.sql
-- =========================================================
ALTER TABLE IF EXISTS orders
  ADD COLUMN IF NOT EXISTS driver_earnings_amount NUMERIC(10,2) DEFAULT 0;

CREATE TABLE IF NOT EXISTS driver_earnings_ledger (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES drivers(id),
  order_id TEXT NOT NULL REFERENCES orders(order_id),
  amount NUMERIC(10,2) NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  paid_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_driver_earnings_ledger_driver ON driver_earnings_ledger (driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_earnings_ledger_order ON driver_earnings_ledger (order_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_driver_earnings_ledger_order_id ON driver_earnings_ledger (order_id);

COMMENT ON COLUMN orders.driver_earnings_amount IS 'Last recorded driver share for this order (JOD, optional denormalized total).';
COMMENT ON TABLE driver_earnings_ledger IS 'Per-delivery driver earnings; status pending until payout.';

-- =========================================================
-- 043_user_saved_address_and_placeholder.sql
-- =========================================================
ALTER TABLE IF EXISTS users
  ADD COLUMN IF NOT EXISTS saved_address JSONB;

COMMENT ON COLUMN users.saved_address IS 'Optional delivery address JSON: address1, address2, city, notes, lat, lng.';

INSERT INTO users (firebase_uid, email, role, is_active)
VALUES ('_account_deleted_placeholder_', NULL, 'customer', false)
ON CONFLICT (firebase_uid) DO NOTHING;

COMMIT;
