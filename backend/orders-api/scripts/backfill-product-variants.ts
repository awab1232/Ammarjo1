import { randomUUID } from 'node:crypto';
import { Pool } from 'pg';

async function main() {
  const url = process.env.DATABASE_URL?.trim();
  if (!url) {
    throw new Error('DATABASE_URL is required');
  }

  const pool = new Pool({ connectionString: url, max: 4, idleTimeoutMillis: 30_000 });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const products = await client.query<{
      id: string;
      name: string;
      price: string;
    }>(
      `SELECT p.id, p.name, p.price
       FROM products p
       WHERE NOT EXISTS (
         SELECT 1 FROM product_variants pv WHERE pv.product_id = p.id
       )`,
    );

    let created = 0;
    for (const p of products.rows) {
      const variantId = randomUUID();
      await client.query(
        `INSERT INTO product_variants (id, product_id, sku, price, stock, is_default, created_at)
         VALUES ($1::uuid, $2::uuid, $3, $4, $5, true, NOW())`,
        [variantId, p.id, `LEGACY-${p.id.slice(0, 8)}`, Number(p.price ?? 0), 999999],
      );
      await client.query(
        `INSERT INTO product_variant_options (id, variant_id, option_type, option_value)
         VALUES ($1::uuid, $2::uuid, 'size', 'default')`,
        [randomUUID(), variantId],
      );
      created += 1;
    }

    if (created > 0) {
      await client.query(
        `UPDATE products
         SET has_variants = true
         WHERE id IN (
           SELECT DISTINCT product_id
           FROM product_variants
           WHERE product_id IS NOT NULL
         )`,
      );
    }

    await client.query('COMMIT');
    console.log(
      JSON.stringify({
        kind: 'product_variants_backfill_completed',
        createdVariants: created,
      }),
    );
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
    await pool.end();
  }
}

void main().catch((error) => {
  console.error(
    JSON.stringify({
      kind: 'product_variants_backfill_failed',
      error: error instanceof Error ? error.message : String(error),
    }),
  );
  process.exit(1);
});
