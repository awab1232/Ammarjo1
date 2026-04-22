-- Persistent notification delivery infrastructure.
-- Keeps existing APIs intact while adding durable device tokens + queue + retries.

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

ALTER TABLE user_notifications
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
