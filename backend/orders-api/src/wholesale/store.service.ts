import { Injectable, Logger, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Pool } from 'pg';
import { CreateStoreDto } from './store-domain.types';
import { WholesaleService } from './wholesale.service';

@Injectable()
export class StoreService {
  private readonly logger = new Logger(StoreService.name);
  private readonly pool: Pool | null;
  private readonly storeColumns = 'id, owner_id, name, store_type, status, created_at';
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

  private mapStore(row: Record<string, unknown>) {
    return {
      id: String(row.id),
      ownerId: String(row.owner_id ?? ''),
      name: String(row.name ?? ''),
      logo: '',
      coverImage: '',
      description: '',
      category: '',
      city: '',
      phone: '',
      email: '',
      status: String(row.status ?? 'approved'),
      commission: 8,
      deliveryDays: null,
      deliveryFee: null,
      createdAt: new Date(String(row.created_at)).toISOString(),
      storeType: String(row.store_type ?? ''),
    };
  }

  async getStores(limit = 30, cursor?: string) {
    const l = Math.min(Math.max(1, Number(limit) || 30), 100);
    const params: Array<string | number> = [];
    let where = '';
    let idx = 1;
    if (cursor?.trim()) {
      where = `WHERE id > $${idx++}::uuid`;
      params.push(cursor.trim());
    }
    params.push(l + 1);
    const q = await this.requireDb().query(
      `SELECT ${this.storeColumns} FROM stores
       ${where}
       ORDER BY id ASC
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
          store_domain_source: 'fallback',
          reason: 'stores_empty',
        }),
      );
      const out = await this.wholesale.listStores(limit, cursor);
      this.emitCutoverStatus(0, true);
      return out;
    }
    const rows = q.rows.map((x) => this.mapStore(x as Record<string, unknown>));
    const hasMore = rows.length > l;
    const items = hasMore ? rows.slice(0, l) : rows;
    const nextCursor = hasMore && items.length > 0 ? items[items.length - 1]!.id : null;
    this.logger.log(
      JSON.stringify({
        store_domain_source: 'real',
        count: items.length,
      }),
    );
    this.emitCutoverStatus(items.length, false);
    return { items, nextCursor };
  }

  async getStoreById(id: string) {
    const sid = id.trim();
    const q = await this.requireDb().query(
      `SELECT ${this.storeColumns} FROM stores WHERE id = $1::uuid LIMIT 1`,
      [sid],
    );
    if (q.rows.length === 0) {
      if (!this.isFallbackEnabled()) {
        this.emitCutoverStatus(0, false);
        throw new NotFoundException('Store not found');
      }
      this.logger.log(
        JSON.stringify({
          kind: 'store_domain_fallback_used',
          store_domain_source: 'fallback',
          reason: 'store_not_found',
          storeId: sid,
        }),
      );
      const out = await this.wholesale.getStoreById(sid);
      this.emitCutoverStatus(0, true);
      return out;
    }
    this.logger.log(
      JSON.stringify({
        store_domain_source: 'real',
        storeId: sid,
      }),
    );
    this.emitCutoverStatus(1, false);
    return this.mapStore(q.rows[0] as Record<string, unknown>);
  }

  async createStore(input: CreateStoreDto) {
    const id = input.id?.trim() || randomUUID();
    const storeType = input.storeType?.trim();
    if (storeType !== 'construction_store' && storeType !== 'home_store') {
      throw new NotFoundException('storeType must be construction_store or home_store');
    }
    const inserted = await this.requireDb().query(
      `INSERT INTO stores (id, owner_id, name, store_type, status, created_at)
       VALUES ($1::uuid, $2, $3, $4, $5, NOW())
       RETURNING ${this.storeColumns}`,
      [id, input.ownerId.trim(), input.name.trim(), storeType, (input.status ?? 'approved').trim()],
    );
    return this.mapStore(inserted.rows[0] as Record<string, unknown>);
  }
}

