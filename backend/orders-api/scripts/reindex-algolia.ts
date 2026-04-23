import { Pool } from 'pg';
import algoliasearch from 'algoliasearch';
import type { SearchIndex } from 'algoliasearch';

type StoreRow = {
  id: string;
  name: string;
  description: string | null;
  category: string | null;
  created_at: Date | string | null;
};

type ProductRow = {
  id: string;
  name: string;
  description: string | null;
  price: number | string | null;
  store_id: string | null;
  category_id: string | null;
  created_at: Date | string | null;
};

type CategoryRow = {
  id: string;
  name: string;
  store_id: string | null;
  created_at: Date | string | null;
};

const BATCH_SIZE = 100;

function toIso(v: Date | string | null): string | undefined {
  if (v == null) return undefined;
  const d = v instanceof Date ? v : new Date(String(v));
  return Number.isNaN(d.getTime()) ? undefined : d.toISOString();
}

function requiredEnv(name: string): string {
  const v = process.env[name]?.trim();
  if (!v) {
    throw new Error(`${name} is required`);
  }
  return v;
}

async function saveInBatches(index: SearchIndex, records: Array<Record<string, unknown>>, entityType: string): Promise<void> {
  let processed = 0;
  for (let i = 0; i < records.length; i += BATCH_SIZE) {
    const chunk = records.slice(i, i + BATCH_SIZE);
    await index.saveObjects(chunk);
    processed += chunk.length;
    console.log(
      JSON.stringify({
        kind: 'algolia_reindex_progress',
        entityType,
        processed,
        total: records.length,
      }),
    );
  }
}

async function main() {
  const appId = requiredEnv('ALGOLIA_APP_ID');
  const apiKey = requiredEnv('ALGOLIA_API_KEY');
  const productsIndexName = requiredEnv('ALGOLIA_INDEX_PRODUCTS');
  const storesIndexName = requiredEnv('ALGOLIA_INDEX_STORES');
  const categoriesIndexName = process.env.ALGOLIA_INDEX_CATEGORIES?.trim() || `${storesIndexName}_categories`;

  const databaseUrl = process.env.DATABASE_URL?.trim();
  if (!databaseUrl) {
    throw new Error('DATABASE_URL is required');
  }

  const client = algoliasearch(appId, apiKey);
  const storesIndex = client.initIndex(storesIndexName);
  const productsIndex = client.initIndex(productsIndexName);
  const categoriesIndex = client.initIndex(categoriesIndexName);

  const pool = new Pool({ connectionString: databaseUrl, max: 5, idleTimeoutMillis: 30_000 });
  const db = await pool.connect();
  try {
    const storesQ = await db.query<StoreRow>(
      `SELECT id, name, description, category, created_at
       FROM stores
       ORDER BY created_at ASC`,
    );
    const productsQ = await db.query<ProductRow>(
      `SELECT id, name, description, price, store_id, category_id, created_at
       FROM products
       ORDER BY created_at ASC`,
    );
    const categoriesQ = await db.query<CategoryRow>(
      `SELECT id, name, store_id, created_at
       FROM categories
       ORDER BY created_at ASC`,
    );

    await storesIndex.clearObjects();
    await productsIndex.clearObjects();
    await categoriesIndex.clearObjects();

    const storeObjects = storesQ.rows.map((r) => ({
      objectID: r.id,
      id: r.id,
      name: r.name,
      description: r.description ?? '',
      storeType: r.category ?? '',
      createdAt: toIso(r.created_at),
    }));
    const productObjects = productsQ.rows.map((r) => ({
      objectID: r.id,
      id: r.id,
      name: r.name,
      description: r.description ?? '',
      price: r.price == null ? 0 : Number(r.price),
      storeId: r.store_id ?? undefined,
      categoryId: r.category_id ?? undefined,
      createdAt: toIso(r.created_at),
    }));
    const categoryObjects = categoriesQ.rows.map((r) => ({
      objectID: r.id,
      id: r.id,
      name: r.name,
      storeId: r.store_id ?? undefined,
      createdAt: toIso(r.created_at),
    }));

    await saveInBatches(storesIndex, storeObjects, 'store');
    await saveInBatches(productsIndex, productObjects, 'product');
    await saveInBatches(categoriesIndex, categoryObjects, 'category');

    console.log(
      JSON.stringify({
        kind: 'algolia_reindex_completed',
        totals: {
          stores: storeObjects.length,
          products: productObjects.length,
          categories: categoryObjects.length,
        },
      }),
    );
  } finally {
    db.release();
    await pool.end();
  }
}

void main().catch((error) => {
  console.error(
    JSON.stringify({
      kind: 'algolia_reindex_failed',
      error: error instanceof Error ? error.message : String(error),
    }),
  );
  process.exit(1);
});
