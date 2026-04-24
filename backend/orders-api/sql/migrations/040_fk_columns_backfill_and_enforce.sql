-- 040_fk_columns_backfill_and_enforce.sql
-- Strict stabilization:
-- - Backfill new FK-backed columns.
-- - Abort migration if any required FK column remains NULL.
-- - Enforce NOT NULL on required canonical columns.

SET client_encoding TO 'UTF8';

-- Backfill orders.store_id_uuid
UPDATE orders o
SET store_id_uuid = s.id
FROM stores s
WHERE o.store_id_uuid IS NULL
  AND s.id::text = COALESCE(NULLIF(o.store_id, ''), NULLIF(o.store_id_legacy, ''));

-- Backfill cart_items.store_id_uuid
UPDATE cart_items c
SET store_id_uuid = s.id
FROM stores s
WHERE c.store_id_uuid IS NULL
  AND s.id::text = COALESCE(NULLIF(c.store_id, ''), NULLIF(c.store_id_legacy, ''));

-- Backfill tenders.user_id
UPDATE tenders
SET user_id = customer_uid
WHERE user_id IS NULL OR btrim(user_id) = '';

-- Backfill tender_offers.store_id_uuid
UPDATE tender_offers t
SET store_id_uuid = s.id
FROM stores s
WHERE t.store_id_uuid IS NULL
  AND s.id::text = COALESCE(NULLIF(t.store_id, ''), NULLIF(t.store_id_legacy, ''));

DO $$
DECLARE
  v_orders_null bigint;
  v_cart_null bigint;
  v_tenders_null bigint;
  v_offers_null bigint;
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

ALTER TABLE orders ALTER COLUMN store_id_uuid SET NOT NULL;
ALTER TABLE cart_items ALTER COLUMN store_id_uuid SET NOT NULL;
ALTER TABLE tenders ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE tender_offers ALTER COLUMN store_id_uuid SET NOT NULL;
