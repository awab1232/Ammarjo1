import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Pool } from 'pg';
import { CreateProductDto } from './store-domain.types';
import { WholesaleService } from './wholesale.service';

@Injectable()
export class ProductService {
  private readonly logger = new Logger(ProductService.name);
  private readonly pool: Pool | null;
  private realHits = 0;
  private fallbackHits = 0;

  constructor(private readonly wholesale: WholesaleService) {
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
    if (!this.pool) throw new ServiceUnavailableException('store domain database not configured');
    return this.pool;
  }

  private isFallbackEnabled(): boolean {
    return (process.env.STORE_DOMAIN_FALLBACK_ENABLED ?? 'true').trim().toLowerCase() !== 'false';
  }

  private emitCutoverStatus(realCount: number, fallbackUsed: boolean): void {
    if (fallbackUsed) {
      this.fallbackHits += 1;
    } else {
      this.realHits += 1;
    }
    const total = this.realHits + this.fallbackHits;
    const percentRealUsage = total > 0 ? Number(((this.realHits / total) * 100).toFixed(2)) : 0;
    this.logger.log(
      JSON.stringify({
        kind: 'store_domain_cutover_status',
        real_count: realCount,
        fallback_used: fallbackUsed,
        percent_real_usage: percentRealUsage,
      }),
    );
  }

  async getProductsByStore(input: {
    storeId?: string;
    limit?: number;
    cursor?: string;
  }): Promise<{ items: Array<Record<string, unknown>>; nextCursor: string | null }> {
    const limit = Math.min(Math.max(1, Number(input.limit ?? 30) || 30), 100);
    const params: Array<string | number> = [];
    const clauses: string[] = [];
    let idx = 1;
    if (input.storeId?.trim()) {
      clauses.push(`p.store_id = $${idx++}::uuid`);
      params.push(input.storeId.trim());
    }
    if (input.cursor?.trim()) {
      clauses.push(`p.id > $${idx++}::uuid`);
      params.push(input.cursor.trim());
    }
    const where = clauses.length > 0 ? `WHERE ${clauses.join(' AND ')}` : '';
    params.push(limit + 1);
    const q = await this.requireDb().query(
      `SELECT p.id, p.store_id, p.category_id, p.name, p.description, p.price, p.image_url, p.created_at
       FROM products p
       ${where}
       ORDER BY p.id ASC
       LIMIT $${idx}`,
      params,
    );
    if (q.rows.length === 0) {
      if (!this.isFallbackEnabled()) {
        this.emitCutoverStatus(0, false);
        return { items: [], nextCursor: null };
      }
      this.logger.log(
        JSON.stringify({
          kind: 'store_domain_fallback_used',
          product_domain_source: 'fallback',
          reason: 'products_empty',
          storeId: input.storeId ?? null,
        }),
      );
      const out = await this.wholesale.listProducts(input);
      this.emitCutoverStatus(0, true);
      return out;
    }
    const rows = q.rows.map((row) => {
      const r = row as Record<string, unknown>;
      return {
        id: String(r.id),
        wholesalerId: String(r.store_id),
        productCode: String(r.id),
        name: String(r.name ?? ''),
        imageUrl: String(r.image_url ?? ''),
        unit: '',
        categoryId: r.category_id != null ? String(r.category_id) : null,
        stock: 0,
        description: String(r.description ?? ''),
        quantityPrices: [
          {
            minQty: 1,
            maxQty: null,
            price: Number(r.price ?? 0),
          },
        ],
      };
    });
    const hasMore = rows.length > limit;
    const items = hasMore ? rows.slice(0, limit) : rows;
    const nextCursor = hasMore && items.length > 0 ? String(items[items.length - 1]!.id) : null;
    this.logger.log(
      JSON.stringify({
        product_domain_source: 'real',
        count: items.length,
        storeId: input.storeId ?? null,
      }),
    );
    this.emitCutoverStatus(items.length, false);
    return { items, nextCursor };
  }

  async createProduct(input: CreateProductDto) {
    const id = input.id?.trim() || randomUUID();
    const inserted = await this.requireDb().query(
      `INSERT INTO products (id, store_id, category_id, name, description, price, image_url, created_at)
       VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $5, $6, $7, NOW())
       RETURNING id, store_id, category_id, name, description, price, image_url, created_at`,
      [
        id,
        input.storeId.trim(),
        input.categoryId?.trim() || null,
        input.name.trim(),
        (input.description ?? '').trim(),
        Number(input.price),
        (input.imageUrl ?? '').trim(),
      ],
    );
    const r = inserted.rows[0] as Record<string, unknown>;
    return {
      id: String(r.id),
      wholesalerId: String(r.store_id),
      productCode: String(r.id),
      name: String(r.name ?? ''),
      imageUrl: String(r.image_url ?? ''),
      unit: '',
      categoryId: r.category_id != null ? String(r.category_id) : null,
      stock: 0,
      description: String(r.description ?? ''),
      quantityPrices: [
        {
          minQty: 1,
          maxQty: null,
          price: Number(r.price ?? 0),
        },
      ],
    };
  }
}

