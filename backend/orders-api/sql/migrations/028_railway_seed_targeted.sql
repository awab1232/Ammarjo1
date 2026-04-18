-- 028_railway_seed_targeted.sql
-- Seed مطلوب لـ Railway بعد تطبيق بقية الهجرات:
--   • 3 أقسام رئيسية: مطاعم، بقالة، صحة
--   • 4 متاجر وهمية معتمدة بالعربي
--   • سلايدر الصفحة الرئيسية (home_cms): بنران فقط
--
-- آمن للتكرار (UPSERT). يفترض وجود جداول store_types و home_sections و stores
-- (من الهجرات السابقة) وإزالة قيد store_type القديم (023).

SET client_encoding TO 'UTF8';

-- ---------------------------------------------------------------------------
-- أنواع المتاجر: تجزئة للربط مع المتاجر الوهمية
-- ---------------------------------------------------------------------------
INSERT INTO store_types (id, name, key, icon, image, display_order, is_active)
VALUES
  (
    '11111111-1111-1111-1111-111111111101',
    'تجزئة',
    'retail',
    'shopping_bag',
    'https://picsum.photos/seed/rail-type-retail/640/360',
    1,
    TRUE
  )
ON CONFLICT (key) DO UPDATE SET
  name          = EXCLUDED.name,
  icon          = EXCLUDED.icon,
  image         = EXCLUDED.image,
  display_order = EXCLUDED.display_order,
  is_active     = EXCLUDED.is_active;

-- ---------------------------------------------------------------------------
-- 3 أقسام رئيسية (تُعرض في التطبيق من GET /home/sections)
-- ---------------------------------------------------------------------------
INSERT INTO home_sections (id, name, image, type, is_active, sort_order, store_type_id, created_at)
VALUES
  (
    'bbbbbbbb-0000-0000-0000-000000000001',
    'مطاعم',
    'https://picsum.photos/seed/rail-sec-rest/800/400',
    'stores',
    TRUE,
    1,
    NULL,
    NOW()
  ),
  (
    'bbbbbbbb-0000-0000-0000-000000000002',
    'بقالة',
    'https://picsum.photos/seed/rail-sec-grocery/800/400',
    'stores',
    TRUE,
    2,
    NULL,
    NOW()
  ),
  (
    'bbbbbbbb-0000-0000-0000-000000000003',
    'صحة',
    'https://picsum.photos/seed/rail-sec-health/800/400',
    'stores',
    TRUE,
    3,
    NULL,
    NOW()
  )
ON CONFLICT (id) DO UPDATE SET
  name       = EXCLUDED.name,
  image      = EXCLUDED.image,
  type       = EXCLUDED.type,
  is_active  = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order;

-- ---------------------------------------------------------------------------
-- 4 متاجر وهمية (status = approved) — تظهر في GET /stores/public
-- ---------------------------------------------------------------------------
INSERT INTO stores (
  id,
  owner_id,
  tenant_id,
  name,
  description,
  category,
  store_type,
  store_type_id,
  store_type_key,
  status,
  is_featured,
  is_boosted,
  phone,
  sell_scope,
  city,
  cities,
  logo_url,
  image_url,
  delivery_fee,
  created_at
)
VALUES
  (
    'aaaaaaaa-0000-0000-0000-000000000001',
    'rail_seed_owner_1',
    NULL,
    'مطعم الشام',
    'مأكولات شامية ووجبات منزلية مع توصيل سريع.',
    'مطاعم',
    'retail',
    '11111111-1111-1111-1111-111111111101',
    'retail',
    'approved',
    TRUE,
    FALSE,
    '+962790000101',
    'city',
    'عمّان',
    ARRAY['عمّان']::text[],
    'https://picsum.photos/seed/rail-st1-logo/320/320',
    'https://picsum.photos/seed/rail-st1-cover/1200/600',
    1.50,
    NOW()
  ),
  (
    'aaaaaaaa-0000-0000-0000-000000000002',
    'rail_seed_owner_2',
    NULL,
    'سوبرماركت النور',
    'خضار وفواكه طازجة ومستلزمات يومية.',
    'بقالة',
    'retail',
    '11111111-1111-1111-1111-111111111101',
    'retail',
    'approved',
    FALSE,
    TRUE,
    '+962790000102',
    'city',
    'إربد',
    ARRAY['إربد']::text[],
    'https://picsum.photos/seed/rail-st2-logo/320/320',
    'https://picsum.photos/seed/rail-st2-cover/1200/600',
    0.00,
    NOW()
  ),
  (
    'aaaaaaaa-0000-0000-0000-000000000003',
    'rail_seed_owner_3',
    NULL,
    'صيدلية الحياة',
    'مستلزمات صحية وعناية شخصية بأسعار مناسبة.',
    'صحة',
    'retail',
    '11111111-1111-1111-1111-111111111101',
    'retail',
    'approved',
    FALSE,
    FALSE,
    '+962790000103',
    'city',
    'الزرقاء',
    ARRAY['الزرقاء']::text[],
    'https://picsum.photos/seed/rail-st3-logo/320/320',
    'https://picsum.photos/seed/rail-st3-cover/1200/600',
    2.00,
    NOW()
  ),
  (
    'aaaaaaaa-0000-0000-0000-000000000004',
    'rail_seed_owner_4',
    NULL,
    'كافيه نجوم',
    'قهوة مختصة ومشروبات باردة وحلويات.',
    'مطاعم',
    'retail',
    '11111111-1111-1111-1111-111111111101',
    'retail',
    'approved',
    TRUE,
    FALSE,
    '+962790000104',
    'city',
    'عمّان',
    ARRAY['عمّان']::text[],
    'https://picsum.photos/seed/rail-st4-logo/320/320',
    'https://picsum.photos/seed/rail-st4-cover/1200/600',
    1.00,
    NOW()
  )
ON CONFLICT (id) DO UPDATE SET
  owner_id       = EXCLUDED.owner_id,
  name           = EXCLUDED.name,
  description    = EXCLUDED.description,
  category       = EXCLUDED.category,
  store_type     = EXCLUDED.store_type,
  store_type_id  = EXCLUDED.store_type_id,
  store_type_key = EXCLUDED.store_type_key,
  status         = EXCLUDED.status,
  is_featured    = EXCLUDED.is_featured,
  is_boosted     = EXCLUDED.is_boosted,
  phone          = EXCLUDED.phone,
  sell_scope     = EXCLUDED.sell_scope,
  city           = EXCLUDED.city,
  cities         = EXCLUDED.cities,
  logo_url       = EXCLUDED.logo_url,
  image_url      = EXCLUDED.image_url,
  delivery_fee   = EXCLUDED.delivery_fee;

-- ---------------------------------------------------------------------------
-- متوسط تقييم بسيط لكل متجر (لعرض النجوم في الواجهة إن وُجدت)
-- ---------------------------------------------------------------------------
INSERT INTO ratings_aggregates (target_type, target_id, avg_rating, total_reviews, updated_at)
VALUES
  ('store', 'aaaaaaaa-0000-0000-0000-000000000001', 4.60, 42, NOW()),
  ('store', 'aaaaaaaa-0000-0000-0000-000000000002', 4.45, 28, NOW()),
  ('store', 'aaaaaaaa-0000-0000-0000-000000000003', 4.80, 15, NOW()),
  ('store', 'aaaaaaaa-0000-0000-0000-000000000004', 4.20, 33, NOW())
ON CONFLICT (target_type, target_id) DO UPDATE SET
  avg_rating    = EXCLUDED.avg_rating,
  total_reviews = EXCLUDED.total_reviews,
  updated_at    = EXCLUDED.updated_at;

-- ---------------------------------------------------------------------------
-- home_cms: بنران للسلايدر (يستهلكهما GET /home/cms و GET /banners)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS home_cms (
  id smallint PRIMARY KEY,
  slider jsonb NOT NULL DEFAULT '[]'::jsonb,
  offers jsonb NOT NULL DEFAULT '[]'::jsonb,
  bottom_banner jsonb,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT home_cms_singleton CHECK (id = 1)
);

CREATE TABLE IF NOT EXISTS system_versions (
  key text PRIMARY KEY,
  version bigint NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO system_versions (key, version)
VALUES ('home_cms_version', 1)
ON CONFLICT (key) DO NOTHING;

INSERT INTO home_cms (id, slider, offers, bottom_banner)
VALUES (
  1,
  '[
    {"id":"rail-b1","imageUrl":"https://picsum.photos/seed/rail-banner-a/900/360","title":"عروض المطاعم والكافيهات"},
    {"id":"rail-b2","imageUrl":"https://picsum.photos/seed/rail-banner-b/900/360","title":"تسوق البقالة والصحة بسهولة"}
  ]'::jsonb,
  '[]'::jsonb,
  NULL
)
ON CONFLICT (id) DO UPDATE SET
  slider     = EXCLUDED.slider,
  offers     = EXCLUDED.offers,
  updated_at = now();

UPDATE system_versions
SET version = version + 1, updated_at = now()
WHERE key = 'home_cms_version';

INSERT INTO system_versions (key, version)
VALUES ('home_sections_version', 1)
ON CONFLICT (key) DO NOTHING;

UPDATE system_versions
SET version = version + 1, updated_at = now()
WHERE key = 'home_sections_version';
