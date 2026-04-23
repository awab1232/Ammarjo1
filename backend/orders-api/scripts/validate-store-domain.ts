import { Pool } from 'pg';

async function main() {
  const url = process.env.DATABASE_URL?.trim();
  if (!url) throw new Error('DATABASE_URL is required');

  const pool = new Pool({ connectionString: url, max: 4, idleTimeoutMillis: 30_000 });
  const client = await pool.connect();
  try {
    const sourceStoreCount = Number((await client.query(`SELECT COUNT(*)::int AS n FROM wholesalers`)).rows[0]?.n ?? 0);
    const realStoreCount = Number((await client.query(`SELECT COUNT(*)::int AS n FROM stores`)).rows[0]?.n ?? 0);

    const storesWithoutCategories = Number(
      (
        await client.query(
          `SELECT COUNT(*)::int AS n
           FROM stores s
           WHERE NOT EXISTS (SELECT 1 FROM categories c WHERE c.store_id = s.id)`,
        )
      ).rows[0]?.n ?? 0,
    );
    const storesWithoutProducts = Number(
      (
        await client.query(
          `SELECT COUNT(*)::int AS n
           FROM stores s
           WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.store_id = s.id)`,
        )
      ).rows[0]?.n ?? 0,
    );

    const orphanCategories = Number(
      (
        await client.query(
          `SELECT COUNT(*)::int AS n
           FROM categories c
           LEFT JOIN stores s ON s.id = c.store_id
           WHERE s.id IS NULL`,
        )
      ).rows[0]?.n ?? 0,
    );
    const orphanProductsByStore = Number(
      (
        await client.query(
          `SELECT COUNT(*)::int AS n
           FROM products p
           LEFT JOIN stores s ON s.id = p.store_id
           WHERE s.id IS NULL`,
        )
      ).rows[0]?.n ?? 0,
    );
    const orphanProductsByCategory = Number(
      (
        await client.query(
          `SELECT COUNT(*)::int AS n
           FROM products p
           LEFT JOIN categories c ON c.id = p.category_id
           WHERE p.category_id IS NOT NULL AND c.id IS NULL`,
        )
      ).rows[0]?.n ?? 0,
    );

    const failures: string[] = [];
    if (realStoreCount < sourceStoreCount) {
      failures.push(`stores_count_mismatch source=${sourceStoreCount} real=${realStoreCount}`);
    }
    if (storesWithoutCategories > 0) failures.push(`stores_without_categories=${storesWithoutCategories}`);
    if (storesWithoutProducts > 0) failures.push(`stores_without_products=${storesWithoutProducts}`);
    if (orphanCategories > 0) failures.push(`orphan_categories=${orphanCategories}`);
    if (orphanProductsByStore > 0) failures.push(`orphan_products_by_store=${orphanProductsByStore}`);
    if (orphanProductsByCategory > 0) failures.push(`orphan_products_by_category=${orphanProductsByCategory}`);

    const payload = {
      kind: failures.length > 0 ? 'store_domain_seed_validation_failed' : 'store_domain_seed_validation_passed',
      metrics: {
        sourceStoreCount,
        realStoreCount,
        storesWithoutCategories,
        storesWithoutProducts,
        orphanCategories,
        orphanProductsByStore,
        orphanProductsByCategory,
      },
      failures,
    };

    if (failures.length > 0) {
      console.error(JSON.stringify(payload));
      process.exit(2);
    } else {
      console.log(JSON.stringify(payload));
    }
  } finally {
    client.release();
    await pool.end();
  }
}

void main().catch((e) => {
  console.error(
    JSON.stringify({
      kind: 'store_domain_seed_validation_failed',
      message: e instanceof Error ? e.message : String(e),
    }),
  );
  process.exit(1);
});

