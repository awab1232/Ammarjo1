import { randomUUID } from 'node:crypto';
import { Pool } from 'pg';

type SeedMode = 'dry-run' | 'run';

function resolveMode(): SeedMode {
  const arg = (process.argv[2] || '').trim().toLowerCase();
  if (arg === 'run' || arg === '--run') return 'run';
  return 'dry-run';
}

function isUuidLike(v: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v);
}

async function main() {
  const mode = resolveMode();
  const url = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
  if (!url) throw new Error('DATABASE_URL or ORDERS_DATABASE_URL is required');

  const pool = new Pool({ connectionString: url, max: 4, idleTimeoutMillis: 30_000 });
  const client = await pool.connect();
  try {
    const sourceStores = await client.query(
      `SELECT id, owner_id, name, status
       FROM wholesalers
       ORDER BY created_at ASC`,
    );
    const sourceCategories = await client.query(
      `SELECT id, store_id, name, parent_id, sort_order
       FROM store_categories
       WHERE store_id ~* '^[0-9a-f-]{36}$'
       ORDER BY created_at ASC`,
    );
    const sourceProducts = await client.query(
      `SELECT id, wholesaler_id, category_id, name, image_url
       FROM wholesale_products
       ORDER BY created_at ASC`,
    );

    const invalidStores = sourceStores.rows.filter(
      (r) => !isUuidLike(String(r.id ?? '')) || String(r.owner_id ?? '').trim() === '' || String(r.name ?? '').trim() === '',
    );
    const invalidCategories = sourceCategories.rows.filter(
      (r) =>
        !isUuidLike(String(r.id ?? '')) ||
        !isUuidLike(String(r.store_id ?? '')) ||
        String(r.name ?? '').trim() === '' ||
        (r.parent_id != null && !isUuidLike(String(r.parent_id))),
    );
    const invalidProducts = sourceProducts.rows.filter(
      (r) =>
        !isUuidLike(String(r.id ?? '')) ||
        !isUuidLike(String(r.wholesaler_id ?? '')) ||
        String(r.name ?? '').trim() === '',
    );

    const duplicateStoreIds = sourceStores.rows.length - new Set(sourceStores.rows.map((r) => String(r.id))).size;
    const duplicateCategoryIds =
      sourceCategories.rows.length - new Set(sourceCategories.rows.map((r) => String(r.id))).size;
    const duplicateProductIds = sourceProducts.rows.length - new Set(sourceProducts.rows.map((r) => String(r.id))).size;

    const existingStoreIds = await client.query(`SELECT id FROM stores`);
    const existingCategoryIds = await client.query(`SELECT id FROM categories`);
    const existingProductIds = await client.query(`SELECT id FROM products`);

    const existingStoresSet = new Set(existingStoreIds.rows.map((r) => String(r.id)));
    const existingCategoriesSet = new Set(existingCategoryIds.rows.map((r) => String(r.id)));
    const existingProductsSet = new Set(existingProductIds.rows.map((r) => String(r.id)));

    const plannedStores = sourceStores.rows.filter((r) => !existingStoresSet.has(String(r.id)) && isUuidLike(String(r.id)));
    const plannedCategories = sourceCategories.rows.filter(
      (r) => !existingCategoriesSet.has(String(r.id)) && isUuidLike(String(r.id)) && isUuidLike(String(r.store_id)),
    );
    const plannedProducts = sourceProducts.rows.filter(
      (r) => !existingProductsSet.has(String(r.id)) && isUuidLike(String(r.id)) && isUuidLike(String(r.wholesaler_id)),
    );

    console.log(
      JSON.stringify({
        kind: 'store_domain_seed_plan',
        mode,
        source: 'wholesale_tables',
        totals: {
          sourceStores: sourceStores.rows.length,
          sourceCategories: sourceCategories.rows.length,
          sourceProducts: sourceProducts.rows.length,
          existingStores: existingStoresSet.size,
          existingCategories: existingCategoriesSet.size,
          existingProducts: existingProductsSet.size,
          willInsertStores: plannedStores.length,
          willInsertCategories: plannedCategories.length,
          willInsertProducts: plannedProducts.length,
        },
        duplicates: {
          stores: duplicateStoreIds,
          categories: duplicateCategoryIds,
          products: duplicateProductIds,
        },
        invalid: {
          stores: invalidStores.length,
          categories: invalidCategories.length,
          products: invalidProducts.length,
        },
      }),
    );

    if (mode === 'dry-run') {
      return;
    }

    await client.query('BEGIN');
    try {
      let insertedStores = 0;
      for (const r of plannedStores) {
        const id = String(r.id);
        if (!isUuidLike(id)) continue;
        const storeType = 'construction_store';
        const res = await client.query(
          `INSERT INTO stores (id, owner_id, name, store_type, status, created_at)
           VALUES ($1::uuid, $2, $3, $4, $5, NOW())
           ON CONFLICT (id) DO NOTHING`,
          [
            id,
            String(r.owner_id ?? '').trim() || randomUUID(),
            String(r.name ?? '').trim() || 'Store',
            storeType,
            String(r.status ?? 'approved').trim() || 'approved',
          ],
        );
        insertedStores += res.rowCount ?? 0;
      }

      let insertedCategories = 0;
      for (const r of plannedCategories) {
        const id = String(r.id);
        const storeId = String(r.store_id);
        if (!isUuidLike(id) || !isUuidLike(storeId)) continue;
        const parentIdRaw = r.parent_id != null ? String(r.parent_id) : null;
        const parentId = parentIdRaw != null && isUuidLike(parentIdRaw) ? parentIdRaw : null;
        const res = await client.query(
          `INSERT INTO categories (id, store_id, name, parent_id, sort_order, created_at)
           VALUES ($1::uuid, $2::uuid, $3, $4::uuid, $5, NOW())
           ON CONFLICT (id) DO NOTHING`,
          [id, storeId, String(r.name ?? '').trim() || 'Category', parentId, Number(r.sort_order ?? 0)],
        );
        insertedCategories += res.rowCount ?? 0;
      }

      let insertedProducts = 0;
      for (const r of plannedProducts) {
        const id = String(r.id);
        const storeId = String(r.wholesaler_id);
        if (!isUuidLike(id) || !isUuidLike(storeId)) continue;
        const categoryIdRaw = r.category_id != null ? String(r.category_id) : null;
        const categoryId = categoryIdRaw != null && isUuidLike(categoryIdRaw) ? categoryIdRaw : null;
        const res = await client.query(
          `INSERT INTO products (id, store_id, category_id, name, description, price, image_url, created_at)
           VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $5, $6, $7, NOW())
           ON CONFLICT (id) DO NOTHING`,
          [
            id,
            storeId,
            categoryId,
            String(r.name ?? '').trim() || 'Product',
            '',
            0,
            String(r.image_url ?? '').trim(),
          ],
        );
        insertedProducts += res.rowCount ?? 0;
      }

      await client.query('COMMIT');
      console.log(
        JSON.stringify({
          kind: 'store_domain_seed_completed',
          inserted: {
            stores: insertedStores,
            categories: insertedCategories,
            products: insertedProducts,
          },
        }),
      );
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    }
  } finally {
    client.release();
    await pool.end();
  }
}

void main().catch((e) => {
  console.error(
    JSON.stringify({
      kind: 'store_domain_seed_failed',
      message: e instanceof Error ? e.message : String(e),
    }),
  );
  process.exit(1);
});

