-- 026_demo_home_seed.sql
-- Development-only seed that fills the home-page with visible data:
--   * 3 Arabic store types:     مواد بناء / أدوات منزلية / جملة
--   * 12 stores (5 + 5 + 2) with Arabic names, descriptions and images
--   * 6 products per store (72 total) with Arabic names, images and prices
--   * 3 home sections:          متاجر مميزة / الأكثر مبيعًا / عروض اليوم
--   * 4 promotional banners with Arabic titles
--   * 6 store_offers (today's discounts) with Arabic copy
--   * Star ratings_aggregates for every demo store
--
-- Everything is idempotent (`ON CONFLICT DO UPDATE`). All deterministic UUIDs
-- start with a discriminator prefix so the rows are trivial to locate and
-- wipe with `WHERE owner_id LIKE 'demo_owner_%'` / `WHERE title LIKE '%[DEMO]%'`.

SET client_encoding TO 'UTF8';

-- =========================================================================
-- 1. STORE TYPES (3 Arabic categories)
-- =========================================================================
INSERT INTO store_types (id, name, key, icon, image, display_order, is_active) VALUES
  ('aaaa1111-0000-0000-0000-000000000001', 'مواد بناء',    'construction', 'construction', 'https://picsum.photos/seed/type_construction/640/360', 1, TRUE),
  ('aaaa1111-0000-0000-0000-000000000002', 'أدوات منزلية', 'home',         'home',         'https://picsum.photos/seed/type_home/640/360',          2, TRUE),
  ('aaaa1111-0000-0000-0000-000000000003', 'جملة',        'wholesale',     'warehouse',    'https://picsum.photos/seed/type_wholesale/640/360',     3, TRUE)
ON CONFLICT (key) DO UPDATE SET
  id            = EXCLUDED.id,
  name          = EXCLUDED.name,
  icon          = EXCLUDED.icon,
  image         = EXCLUDED.image,
  display_order = EXCLUDED.display_order,
  is_active     = EXCLUDED.is_active;

-- =========================================================================
-- 2. STORES (12)
-- =========================================================================
INSERT INTO stores (
  id, owner_id, tenant_id, name, description, category,
  store_type, store_type_id, store_type_key,
  status, is_featured, is_boosted,
  phone, sell_scope, city, cities,
  logo_url, image_url, delivery_fee, created_at
) VALUES
  -- مواد بناء (construction) — 5 stores
  ('bbbb0000-0000-0000-0000-000000000001','demo_owner_1', NULL,
   'شركة البناء الحديث', 'شركة متخصصة في توريد مواد البناء الحديثة بأسعار تنافسية وجودة أوروبية.',
   'مواد بناء', 'construction_store','aaaa1111-0000-0000-0000-000000000001','construction',
   'approved', TRUE, TRUE, '+962790000101','city','عمّان', ARRAY['عمّان'],
   'https://picsum.photos/seed/store_const_1/400/400','https://picsum.photos/seed/store_const_1_wide/1200/600',
   1.50, NOW()),

  ('bbbb0000-0000-0000-0000-000000000002','demo_owner_2', NULL,
   'متجر الإسمنت الذهبي', 'كل ما يتعلق بالإسمنت والخلطات الجاهزة لمشاريع البناء الصغيرة والكبيرة.',
   'مواد بناء', 'construction_store','aaaa1111-0000-0000-0000-000000000001','construction',
   'approved', TRUE, FALSE,'+962790000102','city','الزرقاء', ARRAY['الزرقاء'],
   'https://picsum.photos/seed/store_const_2/400/400','https://picsum.photos/seed/store_const_2_wide/1200/600',
   1.75, NOW()),

  ('bbbb0000-0000-0000-0000-000000000003','demo_owner_3', NULL,
   'معرض الحديد والتسليح', 'تشكيلة واسعة من حديد التسليح والقضبان بجميع المقاسات.',
   'مواد بناء', 'construction_store','aaaa1111-0000-0000-0000-000000000001','construction',
   'approved', FALSE, TRUE, '+962790000103','city','إربد', ARRAY['إربد'],
   'https://picsum.photos/seed/store_const_3/400/400','https://picsum.photos/seed/store_const_3_wide/1200/600',
   2.00, NOW()),

  ('bbbb0000-0000-0000-0000-000000000004','demo_owner_4', NULL,
   'مؤسسة البناء السريع', 'خدمات توريد مواد البناء مع توصيل سريع داخل المملكة.',
   'مواد بناء', 'construction_store','aaaa1111-0000-0000-0000-000000000001','construction',
   'approved', FALSE, FALSE,'+962790000104','city','العقبة', ARRAY['العقبة'],
   'https://picsum.photos/seed/store_const_4/400/400','https://picsum.photos/seed/store_const_4_wide/1200/600',
   3.00, NOW()),

  ('bbbb0000-0000-0000-0000-000000000005','demo_owner_5', NULL,
   'متجر مواد البناء الراقي', 'أدوات ومواد بناء بجودة عالية مع ضمان لمدة عام كامل.',
   'مواد بناء', 'construction_store','aaaa1111-0000-0000-0000-000000000001','construction',
   'approved', FALSE, FALSE,'+962790000105','city','السلط', ARRAY['السلط'],
   'https://picsum.photos/seed/store_const_5/400/400','https://picsum.photos/seed/store_const_5_wide/1200/600',
   1.25, NOW()),

  -- أدوات منزلية (home) — 5 stores
  ('bbbb0000-0000-0000-0000-000000000006','demo_owner_6', NULL,
   'بيت الأدوات المنزلية', 'كل ما يحتاجه البيت العصري من أدوات مطبخ وتجهيزات منزلية.',
   'أدوات منزلية', 'home_store','aaaa1111-0000-0000-0000-000000000002','home',
   'approved', TRUE, TRUE, '+962790000106','city','عمّان', ARRAY['عمّان'],
   'https://picsum.photos/seed/store_home_1/400/400','https://picsum.photos/seed/store_home_1_wide/1200/600',
   1.50, NOW()),

  ('bbbb0000-0000-0000-0000-000000000007','demo_owner_7', NULL,
   'متجر التجهيزات المطبخية', 'أواني وتجهيزات مطبخية بأفضل الماركات العالمية.',
   'أدوات منزلية', 'home_store','aaaa1111-0000-0000-0000-000000000002','home',
   'approved', TRUE, FALSE,'+962790000107','city','إربد', ARRAY['إربد'],
   'https://picsum.photos/seed/store_home_2/400/400','https://picsum.photos/seed/store_home_2_wide/1200/600',
   1.75, NOW()),

  ('bbbb0000-0000-0000-0000-000000000008','demo_owner_8', NULL,
   'عالم الأجهزة المنزلية', 'أجهزة كهربائية منزلية ذكية مع كفالة رسمية وخدمة ما بعد البيع.',
   'أدوات منزلية', 'home_store','aaaa1111-0000-0000-0000-000000000002','home',
   'approved', FALSE, TRUE, '+962790000108','city','الزرقاء', ARRAY['الزرقاء'],
   'https://picsum.photos/seed/store_home_3/400/400','https://picsum.photos/seed/store_home_3_wide/1200/600',
   2.00, NOW()),

  ('bbbb0000-0000-0000-0000-000000000009','demo_owner_9', NULL,
   'ركن الأثاث المودرن', 'تشكيلات أثاث منزلي عصري يلبي احتياجات العائلة الأردنية.',
   'أدوات منزلية', 'home_store','aaaa1111-0000-0000-0000-000000000002','home',
   'approved', FALSE, FALSE,'+962790000109','city','المفرق', ARRAY['المفرق'],
   'https://picsum.photos/seed/store_home_4/400/400','https://picsum.photos/seed/store_home_4_wide/1200/600',
   2.50, NOW()),

  ('bbbb0000-0000-0000-0000-000000000010','demo_owner_10', NULL,
   'متجر الديكور الأنيق', 'قطع ديكور، إضاءة وستائر تمنح منزلك طابعاً مميزاً.',
   'أدوات منزلية', 'home_store','aaaa1111-0000-0000-0000-000000000002','home',
   'approved', TRUE, FALSE,'+962790000110','city','عمّان', ARRAY['عمّان'],
   'https://picsum.photos/seed/store_home_5/400/400','https://picsum.photos/seed/store_home_5_wide/1200/600',
   1.00, NOW()),

  -- جملة (wholesale) — 2 stores
  ('bbbb0000-0000-0000-0000-000000000011','demo_owner_11', NULL,
   'تاجر الجملة الذهبي', 'مواد غذائية واستهلاكية بأسعار الجملة الحقيقية لأصحاب المحلات.',
   'جملة', 'wholesale_store','aaaa1111-0000-0000-0000-000000000003','wholesale',
   'approved', TRUE, TRUE, '+962790000111','all_jordan','', ARRAY['all_jordan'],
   'https://picsum.photos/seed/store_whs_1/400/400','https://picsum.photos/seed/store_whs_1_wide/1200/600',
   0.00, NOW()),

  ('bbbb0000-0000-0000-0000-000000000012','demo_owner_12', NULL,
   'مستودع الجملة الشامل', 'مستودع جملة متكامل يغطي احتياجات التجار من المواد الاستهلاكية والمنزلية.',
   'جملة', 'wholesale_store','aaaa1111-0000-0000-0000-000000000003','wholesale',
   'approved', FALSE, TRUE, '+962790000112','all_jordan','', ARRAY['all_jordan'],
   'https://picsum.photos/seed/store_whs_2/400/400','https://picsum.photos/seed/store_whs_2_wide/1200/600',
   0.00, NOW())
ON CONFLICT (id) DO UPDATE SET
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

-- =========================================================================
-- 3. PRODUCTS (6 per store, 72 total)
-- Generated deterministically via md5(store_id || idx) so re-runs are stable.
-- =========================================================================
DO $$
DECLARE
  s            record;
  prod_names   text[];
  prod_prices  numeric[];
  i            int;
  pid          uuid;
BEGIN
  FOR s IN
    SELECT id, store_type_key
    FROM stores
    WHERE owner_id LIKE 'demo_owner_%'
    ORDER BY created_at
  LOOP
    IF s.store_type_key = 'construction' THEN
      prod_names  := ARRAY['أسمنت بورتلاندي','حديد تسليح 12 ملم','رمل بناء ناعم','بلاط سيراميك','طوب أحمر','دهان جدران'];
      prod_prices := ARRAY[6.5, 12.0, 25.0, 18.5, 0.35, 22.0];
    ELSIF s.store_type_key = 'home' THEN
      prod_names  := ARRAY['طقم أواني طبخ','غلاية كهربائية','مكنسة كهربائية','كرسي خشبي','سجادة عصرية','مصباح ليد'];
      prod_prices := ARRAY[45.0, 18.0, 75.0, 30.0, 55.0, 12.5];
    ELSE  -- wholesale
      prod_names  := ARRAY['سكر ناعم - شيكارة 50كغم','زيت زيتون - كرتونة','أرز بسمتي - كيس 25كغم','شاي أخضر - كرتونة','قهوة تركية - كرتونة','عدس أحمر - كيس 25كغم'];
      prod_prices := ARRAY[45.0, 120.0, 85.0, 95.0, 150.0, 40.0];
    END IF;

    FOR i IN 1..6 LOOP
      pid := md5(s.id::text || ':prod:' || i::text)::uuid;
      INSERT INTO products (id, store_id, name, description, price, image_url, is_boosted, is_trending, created_at)
      VALUES (
        pid, s.id,
        prod_names[i],
        prod_names[i] || ' — منتج مميز بجودة عالية وسعر منافس.',
        prod_prices[i],
        'https://picsum.photos/seed/' || replace(pid::text, '-', '') || '/600/600',
        (i = 1),           -- first product of every store is "boosted"
        (i IN (2, 3)),     -- products 2 + 3 are "trending"
        NOW()
      )
      ON CONFLICT (id) DO UPDATE SET
        name        = EXCLUDED.name,
        description = EXCLUDED.description,
        price       = EXCLUDED.price,
        image_url   = EXCLUDED.image_url,
        is_boosted  = EXCLUDED.is_boosted,
        is_trending = EXCLUDED.is_trending;
    END LOOP;
  END LOOP;
END $$;

-- =========================================================================
-- 4. HOME SECTIONS (3 required by spec)
-- =========================================================================
INSERT INTO home_sections (id, name, image, type, is_active, sort_order, store_type_id)
VALUES
  ('cccc0000-0000-0000-0000-000000000001', 'متاجر مميزة',    'https://picsum.photos/seed/home_featured/800/400', 'featured_stores', TRUE, 1, NULL),
  ('cccc0000-0000-0000-0000-000000000002', 'الأكثر مبيعًا',  'https://picsum.photos/seed/home_bestsellers/800/400','best_sellers',    TRUE, 2, NULL),
  ('cccc0000-0000-0000-0000-000000000003', 'عروض اليوم',    'https://picsum.photos/seed/home_deals/800/400',      'today_deals',     TRUE, 3, NULL)
ON CONFLICT (id) DO UPDATE SET
  name       = EXCLUDED.name,
  image      = EXCLUDED.image,
  type       = EXCLUDED.type,
  is_active  = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order;

-- =========================================================================
-- 5. BANNERS (4 Arabic banners)
-- =========================================================================
INSERT INTO banners (id, title, subtitle, image_url, link_type, link_target, sort_order, is_active)
VALUES
  ('dddd0000-0000-0000-0000-000000000001',
   'خصومات مواد البناء', 'حتى 25% على الإسمنت والحديد هذا الأسبوع',
   'https://picsum.photos/seed/banner_1/1200/500', 'section', 'construction', 1, TRUE),
  ('dddd0000-0000-0000-0000-000000000002',
   'أدوات منزلية عصرية', 'تشكيلة جديدة من أدوات المطبخ والأجهزة الذكية',
   'https://picsum.photos/seed/banner_2/1200/500', 'section', 'home', 2, TRUE),
  ('dddd0000-0000-0000-0000-000000000003',
   'عروض تجار الجملة', 'أسعار جملة حقيقية للمواد الغذائية والاستهلاكية',
   'https://picsum.photos/seed/banner_3/1200/500', 'section', 'wholesale', 3, TRUE),
  ('dddd0000-0000-0000-0000-000000000004',
   'توصيل مجاني داخل عمّان', 'عند الطلب بقيمة 30 دينار أو أكثر',
   'https://picsum.photos/seed/banner_4/1200/500', 'none', '', 4, TRUE)
ON CONFLICT (id) DO UPDATE SET
  title       = EXCLUDED.title,
  subtitle    = EXCLUDED.subtitle,
  image_url   = EXCLUDED.image_url,
  link_type   = EXCLUDED.link_type,
  link_target = EXCLUDED.link_target,
  sort_order  = EXCLUDED.sort_order,
  is_active   = EXCLUDED.is_active,
  updated_at  = NOW();

-- =========================================================================
-- 6. PROMOTIONS — store_offers (6 "today's deals")
-- =========================================================================
INSERT INTO store_offers (id, store_id, title, description, discount_percent, valid_until, image_url)
VALUES
  ('eeee0000-0000-0000-0000-000000000001', 'bbbb0000-0000-0000-0000-000000000001',
   'تخفيضات الأسمنت', 'خصم 15% على جميع أكياس الأسمنت لفترة محدودة',
   15, NOW() + INTERVAL '14 days', 'https://picsum.photos/seed/offer_1/800/400'),
  ('eeee0000-0000-0000-0000-000000000002', 'bbbb0000-0000-0000-0000-000000000003',
   'عرض الحديد المميز', 'خصم 10% على حديد التسليح عيار 12 و 14 ملم',
   10, NOW() + INTERVAL '10 days', 'https://picsum.photos/seed/offer_2/800/400'),
  ('eeee0000-0000-0000-0000-000000000003', 'bbbb0000-0000-0000-0000-000000000006',
   'أسبوع الأدوات المنزلية', 'خصومات حتى 20% على جميع أدوات المطبخ',
   20, NOW() + INTERVAL '7 days', 'https://picsum.photos/seed/offer_3/800/400'),
  ('eeee0000-0000-0000-0000-000000000004', 'bbbb0000-0000-0000-0000-000000000008',
   'عرض الأجهزة الكهربائية', 'خصم 12% على الأجهزة المنزلية الذكية',
   12, NOW() + INTERVAL '5 days', 'https://picsum.photos/seed/offer_4/800/400'),
  ('eeee0000-0000-0000-0000-000000000005', 'bbbb0000-0000-0000-0000-000000000010',
   'تخفيضات الديكور', 'خصم 25% على الإضاءة والستائر',
   25, NOW() + INTERVAL '21 days', 'https://picsum.photos/seed/offer_5/800/400'),
  ('eeee0000-0000-0000-0000-000000000006', 'bbbb0000-0000-0000-0000-000000000011',
   'عرض الجملة الشهري', 'أسعار جملة حصرية على المواد الغذائية',
   8, NOW() + INTERVAL '30 days', 'https://picsum.photos/seed/offer_6/800/400')
ON CONFLICT (id) DO UPDATE SET
  title            = EXCLUDED.title,
  description      = EXCLUDED.description,
  discount_percent = EXCLUDED.discount_percent,
  valid_until      = EXCLUDED.valid_until,
  image_url        = EXCLUDED.image_url;

-- =========================================================================
-- 7. RATINGS AGGREGATES (stars for home carousel)
-- =========================================================================
INSERT INTO ratings_aggregates (target_type, target_id, avg_rating, total_reviews, updated_at)
SELECT 'store', s.id::text,
       ROUND((3.8 + (random() * 1.1))::numeric, 2) AS avg_rating,
       (12 + floor(random() * 80))::int            AS total_reviews,
       NOW()
FROM stores s
WHERE s.owner_id LIKE 'demo_owner_%'
ON CONFLICT (target_type, target_id) DO UPDATE SET
  avg_rating    = EXCLUDED.avg_rating,
  total_reviews = EXCLUDED.total_reviews,
  updated_at    = NOW();
