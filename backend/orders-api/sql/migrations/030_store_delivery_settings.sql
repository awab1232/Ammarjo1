-- Store delivery: own drivers vs none, fee, free-delivery threshold, covered governorates (text[]).

ALTER TABLE stores ADD COLUMN IF NOT EXISTS has_own_drivers boolean NOT NULL DEFAULT true;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS free_delivery_min_order numeric(12,2);
ALTER TABLE stores ADD COLUMN IF NOT EXISTS delivery_areas text[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN stores.has_own_drivers IS 'true = store uses its own drivers; false = no delivery service';
COMMENT ON COLUMN stores.delivery_fee IS 'Delivery charge (JOD); used when has_own_drivers';
COMMENT ON COLUMN stores.free_delivery_min_order IS 'Subtotal at or above this gets free delivery (when set)';
COMMENT ON COLUMN stores.delivery_areas IS 'Governorate names (Arabic), e.g. عمّان; empty = all Jordan';
