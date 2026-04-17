-- Shopping cart + in-app notification inbox (PostgreSQL source of truth).
-- Apply: psql "$DATABASE_URL" -f database/cart_and_user_notifications_schema.sql

CREATE TABLE IF NOT EXISTS cart_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  product_id INTEGER NOT NULL,
  variant_id TEXT,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  price_snapshot NUMERIC(18, 4) NOT NULL,
  product_name TEXT NOT NULL DEFAULT '',
  image_url TEXT,
  store_id TEXT NOT NULL DEFAULT 'ammarjo',
  store_name TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cart_items_user_id ON cart_items (user_id);
CREATE INDEX IF NOT EXISTS idx_cart_items_user_product ON cart_items (user_id, product_id);

CREATE TABLE IF NOT EXISTS user_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'general',
  read BOOLEAN NOT NULL DEFAULT FALSE,
  reference_id TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_notifications_user_created ON user_notifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_notifications_unread ON user_notifications (user_id, read) WHERE read = FALSE;

COMMENT ON TABLE cart_items IS 'Per-user cart; Firebase Auth uid in user_id.';
COMMENT ON TABLE user_notifications IS 'In-app notification feed; push delivery remains via Cloud Functions / FCM.';
