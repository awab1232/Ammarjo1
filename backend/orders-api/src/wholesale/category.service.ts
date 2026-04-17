import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Pool } from 'pg';
import { CreateCategoryDto } from './store-domain.types';
import { WholesaleService } from './wholesale.service';

@Injectable()
export class CategoryService {
  private readonly logger = new Logger(CategoryService.name);
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

  async getCategoriesByStore(storeId: string) {
    const sid = storeId.trim();
    const q = await this.requireDb().query(
      `SELECT id, store_id, name, parent_id, sort_order, created_at
       FROM categories
       WHERE store_id = $1::uuid
       ORDER BY sort_order ASC, created_at ASC`,
      [sid],
    );
    if (q.rows.length === 0) {
      if (!this.isFallbackEnabled()) {
        this.emitCutoverStatus(0, false);
        return [];
      }
      this.logger.log(
        JSON.stringify({
          kind: 'store_domain_fallback_used',
          store_domain_source: 'fallback',
          reason: 'categories_empty',
          storeId: sid,
        }),
      );
      const out = await this.wholesale.listStoreCategories(sid);
      this.emitCutoverStatus(0, true);
      return out;
    }
    const items = q.rows.map((row) => {
      const r = row as Record<string, unknown>;
      return {
        id: String(r.id),
        storeId: String(r.store_id),
        name: String(r.name ?? ''),
        imageUrl: '',
        parentId: r.parent_id != null ? String(r.parent_id) : null,
        order: Number(r.sort_order ?? 0),
        isActive: true,
      };
    });
    this.logger.log(
      JSON.stringify({
        store_domain_source: 'real',
        storeId: sid,
        categoryCount: items.length,
      }),
    );
    this.emitCutoverStatus(items.length, false);
    return items;
  }

  async createCategory(input: CreateCategoryDto) {
    const id = input.id?.trim() || randomUUID();
    const inserted = await this.requireDb().query(
      `INSERT INTO categories (id, store_id, name, parent_id, sort_order, created_at)
       VALUES ($1::uuid, $2::uuid, $3, $4::uuid, $5, NOW())
       RETURNING id, store_id, name, parent_id, sort_order, created_at`,
      [
        id,
        input.storeId.trim(),
        input.name.trim(),
        input.parentId?.trim() || null,
        Number(input.sortOrder ?? 0),
      ],
    );
    const row = inserted.rows[0] as Record<string, unknown>;
    return {
      id: String(row.id),
      storeId: String(row.store_id),
      name: String(row.name ?? ''),
      imageUrl: '',
      parentId: row.parent_id != null ? String(row.parent_id) : null,
      order: Number(row.sort_order ?? 0),
      isActive: true,
    };
  }
}

