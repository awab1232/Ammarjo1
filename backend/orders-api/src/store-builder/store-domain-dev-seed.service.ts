import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { Pool } from 'pg';
import { deterministicUuidFromSeed } from './deterministic-uuid';

export const DEV_SEED_HYBRID_STORE_ID = 'store_demo_1';
export const DEV_SEED_OWNER_ID = 'demo_owner';

@Injectable()
export class StoreDomainDevSeedService {
  private readonly logger = new Logger(StoreDomainDevSeedService.name);
  private readonly pool: Pool | null;

  constructor() {
    const url = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
    this.pool = url
      ? new Pool({
          connectionString: url,
          max: Number(process.env.STORE_DOMAIN_PG_POOL_MAX || 6),
          idleTimeoutMillis: 30_000,
        })
      : null;
  }

  private requireDb(): Pool {
    if (!this.pool) throw new ServiceUnavailableException('database not configured');
    return this.pool;
  }

  domainStoreUuid(): string {
    return deterministicUuidFromSeed(`domain:stores:${DEV_SEED_HYBRID_STORE_ID}`);
  }

  private hybridCategoryDomainId(hybridCategoryId: string): string {
    return deterministicUuidFromSeed(`domain:category:${hybridCategoryId}`);
  }

  private productDomainId(index: number): string {
    return deterministicUuidFromSeed(`domain:product:${DEV_SEED_HYBRID_STORE_ID}:${index}`);
  }

  /**
   * Mirror hybrid store_categories into domain `categories` (+ domain `stores` row).
   * Optionally inserts 20–50 demo products distributed across categories (idempotent).
   */
  async seedDomainFromHybrid(
    hybridStoreId: string,
    options: { includeProducts: boolean },
  ): Promise<{ categoryCount: number; productCount: number; productsInsertedThisRun: number }> {
    const storeUuid = this.domainStoreUuid();
    const client = await this.requireDb().connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `INSERT INTO stores (id, owner_id, name, store_type, status, created_at)
         VALUES ($1::uuid, $2, $3, $4, 'approved', NOW())
         ON CONFLICT (id) DO NOTHING`,
        [storeUuid, DEV_SEED_OWNER_ID, 'Demo Store (seed)', 'construction_store'],
      );

      const hybridCats = await client.query(
        `SELECT id, name, parent_id, sort_order
         FROM store_categories
         WHERE store_id = $1
         ORDER BY parent_id NULLS FIRST, sort_order ASC, created_at ASC`,
        [hybridStoreId],
      );

      const parents = hybridCats.rows.filter((r) => r.parent_id == null);
      const children = hybridCats.rows.filter((r) => r.parent_id != null);

      for (const r of parents) {
        const hid = String(r.id);
        const domainId = this.hybridCategoryDomainId(hid);
        await client.query(
          `INSERT INTO categories (id, store_id, name, parent_id, sort_order, created_at)
           VALUES ($1::uuid, $2::uuid, $3, NULL, $4, NOW())
           ON CONFLICT (id) DO NOTHING`,
          [domainId, storeUuid, String(r.name ?? 'Category'), Number(r.sort_order ?? 0)],
        );
      }

      for (const r of children) {
        const hid = String(r.id);
        const domainId = this.hybridCategoryDomainId(hid);
        const parentHybrid = String(r.parent_id);
        const parentDomain = this.hybridCategoryDomainId(parentHybrid);
        await client.query(
          `INSERT INTO categories (id, store_id, name, parent_id, sort_order, created_at)
           VALUES ($1::uuid, $2::uuid, $3, $4::uuid, $5, NOW())
           ON CONFLICT (id) DO NOTHING`,
          [domainId, storeUuid, String(r.name ?? 'Category'), parentDomain, Number(r.sort_order ?? 0)],
        );
      }

      const domainCategoryIds = hybridCats.rows.map((row) => this.hybridCategoryDomainId(String(row.id)));

      let productsInsertedThisRun = 0;
      if (options.includeProducts && domainCategoryIds.length > 0) {
        const productTarget = 20 + Math.floor(Math.random() * 31);
        for (let i = 1; i <= productTarget; i++) {
          const catId = domainCategoryIds[(i - 1) % domainCategoryIds.length]!;
          const pid = this.productDomainId(i);
          const price = Number((5 + Math.random() * 495).toFixed(2));
          const res = await client.query(
            `INSERT INTO products (id, store_id, category_id, name, description, price, image_url, created_at)
             VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $5, $6, $7, NOW())
             ON CONFLICT (id) DO NOTHING`,
            [
              pid,
              storeUuid,
              catId,
              `Product ${i}`,
              '',
              price,
              '',
            ],
          );
          productsInsertedThisRun += res.rowCount ?? 0;
        }
      }

      const totalProductsRow = await client.query(
        `SELECT COUNT(*)::int AS n FROM products WHERE store_id = $1::uuid`,
        [storeUuid],
      );
      const productCount = Number(totalProductsRow.rows[0]?.n ?? 0);

      await client.query('COMMIT');
      return {
        categoryCount: hybridCats.rows.length,
        productCount,
        productsInsertedThisRun,
      };
    } catch (e) {
      await client.query('ROLLBACK');
      this.logger.error(
        JSON.stringify({
          kind: 'dev_seed_domain_failed',
          hybridStoreId,
          reason: e instanceof Error ? e.message : String(e),
        }),
      );
      throw e;
    } finally {
      client.release();
    }
  }

}
