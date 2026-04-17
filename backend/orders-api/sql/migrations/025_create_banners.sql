-- 025_create_banners.sql
-- Creates the home-page `banners` table that the Flutter home carousel
-- reads from. Idempotent and UTF-8 safe.

SET client_encoding TO 'UTF8';

CREATE TABLE IF NOT EXISTS banners (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title       text NOT NULL DEFAULT '',
  subtitle    text NOT NULL DEFAULT '',
  image_url   text NOT NULL DEFAULT '',
  link_type   text NOT NULL DEFAULT 'none',  -- 'store' | 'product' | 'section' | 'external' | 'none'
  link_target text NOT NULL DEFAULT '',
  sort_order  int  NOT NULL DEFAULT 0,
  is_active   boolean NOT NULL DEFAULT TRUE,
  valid_from  timestamptz,
  valid_until timestamptz,
  created_at  timestamptz NOT NULL DEFAULT NOW(),
  updated_at  timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_banners_active_sort
  ON banners (is_active, sort_order, created_at DESC);
