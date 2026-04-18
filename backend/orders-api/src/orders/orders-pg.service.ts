import { Injectable, OnModuleDestroy, Optional } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { DbRouterService } from '../infrastructure/database/db-router.service';
import { DataRoutingService } from '../infrastructure/routing/data-routing.service';
import { isMultiRegionRoutingEnabled } from '../infrastructure/routing/routing.config';
import { safeErrorMessage } from '../config/safe-log';
import { encodeOrderListCursor, type OrderListCursorPayload } from './order-cursor';
import type { StoredOrder } from './order-types';

/**
 * PostgreSQL persistence for orders. Disabled when DATABASE_URL / ORDERS_DATABASE_URL is unset.
 * Optional multi-country pools when ENABLE_MULTI_REGION=1 (see DataRoutingService).
 */
@Injectable()
export class OrdersPgService implements OnModuleDestroy {
  private pool: Pool | null = null;
  private readonly countryPrimaryPools = new Map<string, Pool>();
  private readonly countryReplicaPools = new Map<string, Pool>();

  constructor(
    @Optional() private readonly dbRouter?: DbRouterService,
    @Optional() private readonly dataRouting?: DataRoutingService,
  ) {
    if (isMultiRegionRoutingEnabled() && this.dataRouting) {
      this.initMultiCountryPools();
      if (this.countryPrimaryPools.size > 0) {
        return;
      }
    }
    if (this.dbRouter?.isActive()) {
      return;
    }
    const url = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
    if (!url) {
      return;
    }
    try {
      this.pool = new Pool({
        connectionString: url,
        max: Number(process.env.ORDERS_PG_POOL_MAX || 10),
        idleTimeoutMillis: 30_000,
      });
      this.pool.on('connect', (c) => {
        void c.query("SET client_encoding TO 'UTF8'").catch(() => undefined);
      });
    } catch (e) {
      // Security: never log connection strings or credentials.
      console.error('[OrdersPgService] failed to init pool:', safeErrorMessage(e));
      this.pool = null;
    }
  }

  private initMultiCountryPools(): void {
    const jo = process.env.ORDERS_DATABASE_URL_JO?.trim() || process.env.DATABASE_URL_JO?.trim();
    const eg = process.env.ORDERS_DATABASE_URL_EG?.trim() || process.env.DATABASE_URL_EG?.trim();
    const fallback = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();

    const addPrimary = (url: string, key: string) => {
      try {
        const p = new Pool({
          connectionString: url,
          max: Number(process.env.ORDERS_PG_POOL_MAX || 10),
          idleTimeoutMillis: 30_000,
        });
        this.countryPrimaryPools.set(key, p);
      } catch (e) {
        console.error(`[OrdersPgService] pool ${key} init failed:`, safeErrorMessage(e));
      }
    };

    if (jo) {
      addPrimary(jo, 'primary_pg_jo');
    }
    if (eg) {
      addPrimary(eg, 'primary_pg_eg');
    }
    if (fallback) {
      if (!this.countryPrimaryPools.has('primary_pg_jo')) {
        addPrimary(fallback, 'primary_pg_jo');
      }
      if (!this.countryPrimaryPools.has('primary_pg_eg')) {
        addPrimary(fallback, 'primary_pg_eg');
      }
      if (!this.countryPrimaryPools.has('primary')) {
        addPrimary(fallback, 'primary');
      }
    }

    const rjo =
      process.env.ORDERS_DATABASE_READ_REPLICA_URL_JO?.trim() ||
      process.env.DATABASE_READ_REPLICA_URL_JO?.trim();
    const reg =
      process.env.ORDERS_DATABASE_READ_REPLICA_URL_EG?.trim() ||
      process.env.DATABASE_READ_REPLICA_URL_EG?.trim();
    const rfb = process.env.DATABASE_READ_REPLICA_URL?.trim() || process.env.ORDERS_DATABASE_READ_REPLICA_URL?.trim();

    const addReplica = (url: string, key: string) => {
      try {
        const p = new Pool({
          connectionString: url,
          max: Number(process.env.DB_READ_REPLICA_POOL_MAX || 8),
          idleTimeoutMillis: 30_000,
        });
        this.countryReplicaPools.set(key, p);
      } catch (e) {
        console.error(`[OrdersPgService] replica ${key} init failed:`, safeErrorMessage(e));
      }
    };

    if (rjo) {
      addReplica(rjo, 'replica_jo');
    }
    if (reg) {
      addReplica(reg, 'replica_eg');
    }
    if (rfb) {
      if (!this.countryReplicaPools.has('replica_jo')) {
        addReplica(rfb, 'replica_jo');
      }
      if (!this.countryReplicaPools.has('replica_eg')) {
        addReplica(rfb, 'replica_eg');
      }
    }
  }

  private usingMultiCountry(): boolean {
    return (
      isMultiRegionRoutingEnabled() &&
      this.countryPrimaryPools.size > 0 &&
      this.dataRouting != null
    );
  }

  isEnabled(): boolean {
    if (this.usingMultiCountry()) {
      return true;
    }
    if (this.dbRouter?.isActive()) {
      return true;
    }
    return this.pool != null;
  }

  async onModuleDestroy(): Promise<void> {
    for (const p of this.countryPrimaryPools.values()) {
      await p.end().catch(() => undefined);
    }
    this.countryPrimaryPools.clear();
    for (const p of this.countryReplicaPools.values()) {
      await p.end().catch(() => undefined);
    }
    this.countryReplicaPools.clear();
    if (this.pool) {
      await this.pool.end();
      this.pool = null;
    }
  }

  private usingRouter(): boolean {
    return this.dbRouter?.isActive() === true;
  }

  private async getWriteClient(): Promise<PoolClient | null> {
    if (this.usingMultiCountry() && this.dataRouting) {
      const key = this.dataRouting.resolveDatabase();
      const pool =
        this.countryPrimaryPools.get(key) ?? this.countryPrimaryPools.get('primary') ?? null;
      if (!pool) {
        return null;
      }
      try {
        return await pool.connect();
      } catch (e) {
        console.error('[OrdersPgService] primary connect failed:', safeErrorMessage(e));
        return null;
      }
    }
    if (this.usingRouter()) {
      return this.dbRouter!.getWriteClient();
    }
    if (!this.pool) return null;
    return this.pool.connect();
  }

  /** Read paths may use replica when DB read routing is enabled. */
  private async getReadClient(): Promise<PoolClient | null> {
    if (this.usingMultiCountry() && this.dataRouting) {
      const rr = this.dataRouting.resolveReadReplica();
      if (rr !== 'primary') {
        const rep = this.countryReplicaPools.get(rr);
        if (rep) {
          try {
            return await rep.connect();
          } catch (e) {
            console.warn('[OrdersPgService] country replica failed, using primary:', safeErrorMessage(e));
          }
        }
      }
      const pk = this.dataRouting.resolveDatabase();
      const pool =
        this.countryPrimaryPools.get(pk) ?? this.countryPrimaryPools.get('primary') ?? null;
      if (!pool) {
        return null;
      }
      try {
        return await pool.connect();
      } catch (e) {
        console.error('[OrdersPgService] read primary connect failed:', safeErrorMessage(e));
        return null;
      }
    }
    if (this.usingRouter()) {
      return this.dbRouter!.getReadClient();
    }
    return this.getWriteClient();
  }

  private async getClient(): Promise<PoolClient | null> {
    return this.getWriteClient();
  }

  /** Idempotent upsert — same order_id replaces row (safe retries). */
  async upsertOrder(order: StoredOrder): Promise<void> {
    await this.upsertOrderReturningOp(order);
  }

  /**
   * Same as [upsertOrder] but reports whether the row existed before write (for domain events).
   */
  async upsertOrderReturningOp(order: StoredOrder): Promise<'insert' | 'update' | 'skipped'> {
    const client = await this.getClient();
    if (!client) {
      return 'skipped';
    }

    const orderId = String(order.orderId).trim();
    const userId = order.customerUid != null ? String(order.customerUid) : '';
    const storeId = String(order.storeId ?? '').trim();
    const itemsJson = JSON.stringify(order.items ?? []);
    const sub = num(order.subtotalNumeric);
    const ship = num(order.shippingNumeric);
    const total = num(order.totalNumeric);
    const currency = String(order.currency ?? 'JOD');
    const ws = String(order.writeSource ?? 'firebase');
    const email = String(order.customerEmail ?? '');
    const status = order.status != null ? String(order.status) : 'processing';
    const billingRaw = order['billing'];
    const billing = billingRaw != null ? JSON.stringify(billingRaw) : null;
    const delivery =
      order['deliveryAddress'] != null ? String(order['deliveryAddress']) : null;
    const listTitle = order['listTitle'] != null ? String(order['listTitle']) : null;
    const payload = JSON.stringify(order);

    try {
      const existed = await client.query(`SELECT 1 FROM orders WHERE order_id = $1 LIMIT 1`, [
        orderId,
      ]);
      const wasUpdate = existed.rows.length > 0;

      await client.query(
        `INSERT INTO orders (
          order_id, user_id, store_id, items,
          subtotal_numeric, shipping_numeric, total_numeric,
          currency, write_source, customer_email, status,
          billing, delivery_address, list_title, payload, updated_at
        ) VALUES (
          $1, $2, $3, $4::jsonb,
          $5, $6, $7,
          $8, $9, $10, $11,
          $12::jsonb, $13, $14, $15::jsonb, NOW()
        )
        ON CONFLICT (order_id) DO UPDATE SET
          user_id = EXCLUDED.user_id,
          store_id = EXCLUDED.store_id,
          items = EXCLUDED.items,
          subtotal_numeric = EXCLUDED.subtotal_numeric,
          shipping_numeric = EXCLUDED.shipping_numeric,
          total_numeric = EXCLUDED.total_numeric,
          currency = EXCLUDED.currency,
          write_source = EXCLUDED.write_source,
          customer_email = EXCLUDED.customer_email,
          status = EXCLUDED.status,
          billing = EXCLUDED.billing,
          delivery_address = EXCLUDED.delivery_address,
          list_title = EXCLUDED.list_title,
          payload = EXCLUDED.payload,
          updated_at = NOW()`,
        [
          orderId,
          userId,
          storeId,
          itemsJson,
          sub,
          ship,
          total,
          currency,
          ws,
          email,
          status,
          billing,
          delivery,
          listTitle,
          payload,
        ],
      );
      return wasUpdate ? 'update' : 'insert';
    } finally {
      client.release();
    }
  }

  async findPayloadById(orderId: string): Promise<StoredOrder | null> {
    const client = await this.getReadClient();
    if (!client) return null;
    try {
      const r = await client.query<{ payload: unknown }>(
        `SELECT payload FROM orders WHERE order_id = $1`,
        [orderId.trim()],
      );
      if (r.rows.length === 0) return null;
      const raw = r.rows[0].payload;
      if (raw == null || typeof raw !== 'object') return null;
      return raw as StoredOrder;
    } finally {
      client.release();
    }
  }

  /**
   * Keyset pagination on (created_at DESC, order_id DESC).
   * Fetches [limit]+1 rows to compute [hasMore]; [nextCursor] is the last row of the returned page.
   */
  async findPayloadsByUserIdPaginated(
    userId: string,
    limit: number,
    cursor: OrderListCursorPayload | null,
  ): Promise<{ items: StoredOrder[]; nextCursor: string | null; hasMore: boolean }> {
    const client = await this.getReadClient();
    if (!client) {
      return { items: [], nextCursor: null, hasMore: false };
    }
    const lim = Math.min(Math.max(1, limit), 50);
    const fetchN = lim + 1;
    try {
      let r: {
        rows: Array<{ payload: unknown; created_at: Date; order_id: string }>;
      };
      if (cursor == null) {
        r = await client.query(
          `SELECT payload, created_at, order_id
           FROM orders
           WHERE user_id = $1
           ORDER BY created_at DESC, order_id DESC
           LIMIT $2`,
          [userId.trim(), fetchN],
        );
      } else {
        r = await client.query(
          `SELECT payload, created_at, order_id
           FROM orders
           WHERE user_id = $1
             AND (created_at, order_id) < ($2::timestamptz, $3::text)
           ORDER BY created_at DESC, order_id DESC
           LIMIT $4`,
          [userId.trim(), cursor.c, cursor.o, fetchN],
        );
      }
      const rows = r.rows;
      const hasMore = rows.length > lim;
      const slice = hasMore ? rows.slice(0, lim) : rows;
      const items = slice
        .map((row) => row.payload)
        .filter((p): p is Record<string, unknown> => p != null && typeof p === 'object')
        .map((p) => p as StoredOrder);
      let nextCursor: string | null = null;
      if (hasMore && slice.length > 0) {
        const last = slice[slice.length - 1];
        nextCursor = encodeOrderListCursor(new Date(last.created_at), last.order_id);
      }
      return { items, nextCursor, hasMore };
    } finally {
      client.release();
    }
  }

  /**
   * Store-scoped order listing (owner dashboard). Same cursor shape as user lists.
   */
  async findPayloadsByStoreIdPaginated(
    storeId: string,
    limit: number,
    cursor: OrderListCursorPayload | null,
  ): Promise<{ items: StoredOrder[]; nextCursor: string | null; hasMore: boolean }> {
    const client = await this.getReadClient();
    if (!client) {
      return { items: [], nextCursor: null, hasMore: false };
    }
    const sid = storeId.trim();
    const lim = Math.min(Math.max(1, limit), 50);
    const fetchN = lim + 1;
    try {
      let r: {
        rows: Array<{ payload: unknown; created_at: Date; order_id: string }>;
      };
      if (cursor == null) {
        r = await client.query(
          `SELECT payload, created_at, order_id
           FROM orders
           WHERE store_id = $1
           ORDER BY created_at DESC, order_id DESC
           LIMIT $2`,
          [sid, fetchN],
        );
      } else {
        r = await client.query(
          `SELECT payload, created_at, order_id
           FROM orders
           WHERE store_id = $1
             AND (created_at, order_id) < ($2::timestamptz, $3::text)
           ORDER BY created_at DESC, order_id DESC
           LIMIT $4`,
          [sid, cursor.c, cursor.o, fetchN],
        );
      }
      const rows = r.rows;
      const hasMore = rows.length > lim;
      const slice = hasMore ? rows.slice(0, lim) : rows;
      const items = slice
        .map((row) => row.payload)
        .filter((p): p is Record<string, unknown> => p != null && typeof p === 'object')
        .map((p) => p as StoredOrder);
      let nextCursor: string | null = null;
      if (hasMore && slice.length > 0) {
        const last = slice[slice.length - 1];
        nextCursor = encodeOrderListCursor(new Date(last.created_at), last.order_id);
      }
      return { items, nextCursor, hasMore };
    } finally {
      client.release();
    }
  }

  /** Connectivity check for /health (no pool → not configured). */
  async ping(): Promise<{ ok: boolean; error?: string }> {
    if (this.usingMultiCountry() && this.dataRouting) {
      const key = this.dataRouting.resolveDatabase();
      const pool =
        this.countryPrimaryPools.get(key) ??
        this.countryPrimaryPools.get('primary') ??
        [...this.countryPrimaryPools.values()][0] ??
        null;
      if (!pool) {
        return { ok: false, error: 'not_configured' };
      }
      const client = await pool.connect();
      try {
        await client.query('SELECT 1');
        return { ok: true };
      } catch (e) {
        return {
          ok: false,
          error: e instanceof Error ? e.message : String(e),
        };
      } finally {
        client.release();
      }
    }
    if (this.usingRouter()) {
      return this.dbRouter!.pingPrimary();
    }
    if (!this.pool) {
      return { ok: false, error: 'not_configured' };
    }
    const client = await this.pool.connect();
    try {
      await client.query('SELECT 1');
      return { ok: true };
    } catch (e) {
      return {
        ok: false,
        error: e instanceof Error ? e.message : String(e),
      };
    } finally {
      client.release();
    }
  }
}

function num(v: unknown): number | null {
  if (v == null) return null;
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}
