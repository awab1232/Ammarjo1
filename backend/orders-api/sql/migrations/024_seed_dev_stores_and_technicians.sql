-- 024_seed_dev_stores_and_technicians.sql
-- Idempotent development seed:
--   * 2 baseline store_types (retail / wholesale) with Arabic names.
--   * 5 fake stores: 3 retail + 2 wholesale (Arabic names, JO cities).
--   * 3 approved technicians with Arabic display names and avatar URLs.
--
-- All Arabic strings are embedded as UTF-8 literals. `client_encoding` is
-- forced to UTF-8 at the top of the file so psql does not try to transcode
-- on ingestion.

SET client_encoding TO 'UTF8';

-- --------------------------------------------------------------------------
-- 1. store_types (retail + wholesale)
-- --------------------------------------------------------------------------
INSERT INTO store_types (id, name, key, icon, image, display_order, is_active)
VALUES
  ('11111111-1111-1111-1111-111111111101', 'تجزئة', 'retail',    'shopping_bag', 'https://images.unsplash.com/photo-1601924994987-69e26d50dc26?auto=format&fit=crop&w=640&q=80', 1, TRUE),
  ('11111111-1111-1111-1111-111111111102', 'جملة',  'wholesale', 'warehouse',    'https://images.unsplash.com/photo-1553413077-190dd305871c?auto=format&fit=crop&w=640&q=80',   2, TRUE)
ON CONFLICT (key) DO UPDATE SET
  name          = EXCLUDED.name,
  icon          = EXCLUDED.icon,
  image         = EXCLUDED.image,
  display_order = EXCLUDED.display_order,
  is_active     = EXCLUDED.is_active;

-- --------------------------------------------------------------------------
-- 2. stores (3 retail + 2 wholesale)
--    owner_id uses a synthetic `seed_owner_*` value so these rows are easy
--    to spot and delete via `WHERE owner_id LIKE 'seed_owner_%'`.
-- --------------------------------------------------------------------------
INSERT INTO stores (
  id, owner_id, tenant_id, name, description, category,
  store_type, store_type_id, store_type_key,
  status, is_featured, is_boosted,
  phone, sell_scope, city, cities,
  logo_url, image_url, delivery_fee, created_at
) VALUES
  ( '22222222-2222-2222-2222-222222222201',
    'seed_owner_retail_1',
    NULL,
    'متجر الأمين للأدوات المنزلية',
    'أدوات منزلية وتجهيزات مطابخ بأسعار منافسة.',
    'أدوات منزلية',
    'retail',
    '11111111-1111-1111-1111-111111111101',
    'retail',
    'approved', TRUE,  FALSE,
    '+962790000011', 'city', 'عمّان', ARRAY['عمّان'],
    'https://images.unsplash.com/photo-1556911220-e15b29be8c8f?auto=format&fit=crop&w=320&q=80',
    'https://images.unsplash.com/photo-1556911220-e15b29be8c8f?auto=format&fit=crop&w=1024&q=80',
    1.50,
    NOW() ),

  ( '22222222-2222-2222-2222-222222222202',
    'seed_owner_retail_2',
    NULL,
    'متجر النور للإلكترونيات',
    'أجهزة إلكترونية وهواتف ذكية وإكسسوارات أصلية.',
    'إلكترونيات',
    'retail',
    '11111111-1111-1111-1111-111111111101',
    'retail',
    'approved', FALSE, TRUE,
    '+962790000012', 'city', 'إربد', ARRAY['إربد'],
    'https://images.unsplash.com/photo-1518441902113-c1d3d3b3f3f3?auto=format&fit=crop&w=320&q=80',
    'https://images.unsplash.com/photo-1518441902113-c1d3d3b3f3f3?auto=format&fit=crop&w=1024&q=80',
    2.00,
    NOW() ),

  ( '22222222-2222-2222-2222-222222222203',
    'seed_owner_retail_3',
    NULL,
    'متجر السلام للملابس',
    'ملابس رجالية ونسائية بتشكيلات عصرية.',
    'ملابس',
    'retail',
    '11111111-1111-1111-1111-111111111101',
    'retail',
    'approved', FALSE, FALSE,
    '+962790000013', 'city', 'الزرقاء', ARRAY['الزرقاء'],
    'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=320&q=80',
    'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=1024&q=80',
    1.75,
    NOW() ),

  ( '22222222-2222-2222-2222-222222222204',
    'seed_owner_wholesale_1',
    NULL,
    'مستودع البركة للجملة',
    'مستودع جملة للمواد الغذائية والاستهلاكية بأسعار الجملة الحقيقية.',
    'مواد غذائية',
    'wholesale',
    '11111111-1111-1111-1111-111111111102',
    'wholesale',
    'approved', TRUE,  FALSE,
    '+962790000021', 'all_jordan', '', ARRAY['all_jordan'],
    'https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=320&q=80',
    'https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=1024&q=80',
    0.00,
    NOW() ),

  ( '22222222-2222-2222-2222-222222222205',
    'seed_owner_wholesale_2',
    NULL,
    'جملة الشرق لمواد البناء',
    'مواد بناء وإسمنت وحديد تسليح جملة بكميات مفتوحة.',
    'مواد بناء',
    'wholesale',
    '11111111-1111-1111-1111-111111111102',
    'wholesale',
    'approved', FALSE, TRUE,
    '+962790000022', 'all_jordan', '', ARRAY['all_jordan'],
    'https://images.unsplash.com/photo-1503387762-592deb58ef4e?auto=format&fit=crop&w=320&q=80',
    'https://images.unsplash.com/photo-1503387762-592deb58ef4e?auto=format&fit=crop&w=1024&q=80',
    0.00,
    NOW() )
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

-- --------------------------------------------------------------------------
-- 3. admin_technicians (3 approved technicians)
-- --------------------------------------------------------------------------
INSERT INTO admin_technicians (
  id, firebase_uid, email, display_name,
  specialties, category, phone, city, cities,
  status, approved_at, avatar_url, updated_at
) VALUES
  ( 'seed_tech_1',
    NULL,
    'ahmad.khateeb@example.jo',
    'أحمد الخطيب',
    ARRAY['كهرباء', 'تمديدات كهربائية']::text[],
    'كهرباء',
    '+962790001001', 'عمّان', ARRAY['عمّان', 'الزرقاء'],
    'approved', NOW(),
    'https://randomuser.me/api/portraits/men/31.jpg',
    NOW() ),

  ( 'seed_tech_2',
    NULL,
    'mohammad.zoubi@example.jo',
    'محمد الزعبي',
    ARRAY['سباكة', 'صيانة منزلية']::text[],
    'سباكة',
    '+962790001002', 'إربد', ARRAY['إربد', 'المفرق'],
    'approved', NOW(),
    'https://randomuser.me/api/portraits/men/45.jpg',
    NOW() ),

  ( 'seed_tech_3',
    NULL,
    'sara.najjar@example.jo',
    'سارة النجار',
    ARRAY['تكييف', 'تبريد']::text[],
    'تكييف',
    '+962790001003', 'عمّان', ARRAY['عمّان'],
    'approved', NOW(),
    'https://randomuser.me/api/portraits/women/68.jpg',
    NOW() )
ON CONFLICT (id) DO UPDATE SET
  email        = EXCLUDED.email,
  display_name = EXCLUDED.display_name,
  specialties  = EXCLUDED.specialties,
  category     = EXCLUDED.category,
  phone        = EXCLUDED.phone,
  city         = EXCLUDED.city,
  cities       = EXCLUDED.cities,
  status       = EXCLUDED.status,
  avatar_url   = EXCLUDED.avatar_url,
  updated_at   = NOW();
