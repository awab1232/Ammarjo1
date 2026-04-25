import { OnModuleDestroy } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import type { IProductService } from '../architecture/contracts/i-product.service';
import { DomainId } from '../architecture/domain-id';
import type { CatalogProductRow } from './product-search.types';

function createDefaultCatalogPool(): Pool | null {
  const url = process.env.DATABASE_URL?.trim();
  if (!url) {
    return null;
  }
  try {
    return new Pool({
      connectionString: url,
      max: Number(process.env.CATALOG_PG_POOL_MAX || 5),
      idleTimeoutMillis: 30_000,
    });
  } catch (e) {
    console.error('[CatalogPgService] pool init failed:', e);
    return null;
  }
}

/**
 * PostgreSQL access for `catalog_products` (same DATABASE_URL as orders).
 */
export class CatalogPgService implements OnModuleDestroy, IProductService {
  readonly domainId = DomainId.Search;
  private pool: Pool | null = null;
  /** When false, [pool] is owned by the caller; do not end on destroy. */
  private readonly ownsPool: boolean;

  constructor(optionalPool?: Pool) {
    if (optionalPool) {
      this.pool = optionalPool;
      this.ownsPool = false;
    } else {
      this.pool = createDefaultCatalogPool();
      this.ownsPool = true;
    }
  }

  isEnabled(): boolean {
    return this.pool != null;
  }

  isCatalogEnabled(): boolean {
    return this.isEnabled();
  }

  async onModuleDestroy(): Promise<void> {
    if (this.ownsPool && this.pool) {
      await this.pool.end();
      this.pool = null;
    }
  }

  private async connect(): Promise<PoolClient | null> {
    if (!this.pool) return null;
    return this.pool.connect();
  }

  async findAllForSync(limit: number, offset: number): Promise<CatalogProductRow[]> {
    const client = await this.connect();
    if (!client) return [];
    try {
      const r = await client.query<CatalogProductRow>(
        `SELECT product_id, store_id, name, description, price_numeric, currency,
                category_ids, image_url, stock_status, searchable_text, updated_at
         FROM catalog_products
         ORDER BY product_id ASC
         LIMIT $1 OFFSET $2`,
        [limit, offset],
      );
      return r.rows;
    } finally {
      client.release();
    }
  }

  async count(): Promise<number> {
    const client = await this.connect();
    if (!client) return 0;
    try {
      const r = await client.query<{ n: string }>(`SELECT COUNT(*)::text AS n FROM catalog_products`);
      return Number.parseInt(r.rows[0]?.n ?? '0', 10) || 0;
    } finally {
      client.release();
    }
  }

  async upsert(row: CatalogProductRow): Promise<void> {
    const client = await this.connect();
    if (!client) return;
    const price = typeof row.price_numeric === 'number' ? row.price_numeric : Number(row.price_numeric);
    const searchText =
      row.searchable_text?.trim() ||
      `${row.name} ${row.description}`.trim().slice(0, 8000);
    try {
      await client.query(
        `INSERT INTO catalog_products (
          product_id, store_id, name, description, price_numeric, currency,
          category_ids, image_url, stock_status, searchable_text, updated_at
        ) VALUES (
          $1, $2, $3, $4, $5, $6, $7::integer[], $8, $9, $10, NOW()
        )
        ON CONFLICT (product_id) DO UPDATE SET
          store_id = EXCLUDED.store_id,
          name = EXCLUDED.name,
          description = EXCLUDED.description,
          price_numeric = EXCLUDED.price_numeric,
          currency = EXCLUDED.currency,
          category_ids = EXCLUDED.category_ids,
          image_url = EXCLUDED.image_url,
          stock_status = EXCLUDED.stock_status,
          searchable_text = EXCLUDED.searchable_text,
          updated_at = NOW()`,
        [
          row.product_id,
          row.store_id,
          row.name,
          row.description,
          Number.isFinite(price) ? price : 0,
          row.currency || 'JOD',
          row.category_ids ?? [],
          row.image_url,
          row.stock_status || 'instock',
          searchText,
        ],
      );
    } finally {
      client.release();
    }
  }

  /** Upsert then report insert vs update (for domain events). */
  async upsertReturningOp(row: CatalogProductRow): Promise<'insert' | 'update'> {
    const before = await this.findById(row.product_id);
    await this.upsert(row);
    return before ? 'update' : 'insert';
  }

  async findById(productId: number): Promise<CatalogProductRow | null> {
    const client = await this.connect();
    if (!client) return null;
    try {
      const r = await client.query<CatalogProductRow>(
        `SELECT product_id, store_id, name, description, price_numeric, currency,
                category_ids, image_url, stock_status, searchable_text, updated_at
         FROM catalog_products WHERE product_id = $1`,
        [productId],
      );
      return r.rows[0] ?? null;
    } finally {
      client.release();
    }
  }
}
