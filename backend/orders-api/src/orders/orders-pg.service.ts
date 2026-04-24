import { Injectable, OnModuleDestroy, Optional, ServiceUnavailableException } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { DbRouterService } from '../infrastructure/database/db-router.service';
import { buildPgPoolConfig } from '../infrastructure/database/pg-ssl';
import { DataRoutingService } from '../infrastructure/routing/data-routing.service';
import { isMultiRegionRoutingEnabled } from '../infrastructure/routing/routing.config';
import { safeErrorMessage } from '../config/safe-log';
import { encodeOrderListCursor, type OrderListCursorPayload } from './order-cursor';
import { mergeStoredOrderWithDeliveryColumns } from './delivery-order-merge';
import type { StoredOrder } from './order-types';

/**
 * PostgreSQL persistence for orders. Disabled when DATABASE_URL is unset.
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
    const url = process.env.DATABASE_URL?.trim();
    if (!url) {
      return;
    }
    try {
      this.pool = new Pool(
        buildPgPoolConfig(url, {
          max: Number(process.env.ORDERS_PG_POOL_MAX || 10),
          idleTimeoutMillis: 30_000,
        }),
      );
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
    const jo = process.env.DATABASE_URL?.trim();
    const eg = process.env.DATABASE_URL?.trim();
    const fallback = process.env.DATABASE_URL?.trim();

    const addPrimary = (url: string, key: string) => {
      try {
        const p = new Pool(
          buildPgPoolConfig(url, {
            max: Number(process.env.ORDERS_PG_POOL_MAX || 10),
            idleTimeoutMillis: 30_000,
          }),
        );
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

    const rjo = process.env.DATABASE_URL?.trim();
    const reg = process.env.DATABASE_URL?.trim();
    const rfb = process.env.DATABASE_URL?.trim();

    const addReplica = (url: string, key: string) => {
      try {
        const p = new Pool(
          buildPgPoolConfig(url, {
            max: Number(process.env.DB_READ_REPLICA_POOL_MAX || 8),
            idleTimeoutMillis: 30_000,
          }),
        );
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
      try {
        return await this.dbRouter!.getWriteClient();
      } catch (e) {
        this.logOrdersReadSqlError('getWriteClient/dbRouter', e);
        return null;
      }
    }
    if (!this.pool) return null;
    try {
      return await this.pool.connect();
    } catch (e) {
      this.logOrdersReadSqlError('getWriteClient/pool.connect', e);
      return null;
    }
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
      try {
        return await this.dbRouter!.getReadClient();
      } catch (e) {
        this.logOrdersReadSqlError('getReadClient/dbRouter', e);
        return null;
      }
    }
    return this.getWriteClient();
  }

  private async getClient(): Promise<PoolClient | null> {
    return this.getWriteClient();
  }

  private logOrdersReadSqlError(scope: string, error: unknown): void {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`ORDERS QUERY FAILED [${scope}]: ${message}`);
    console.error(`ORDERS QUERY FAILED [${scope}] full:`, error);
    console.error(`[OrdersPgService] ${scope} SQL safe: ${safeErrorMessage(error)}`);
  }

  /** Keyset cursor encoding must never throw (invalid dates from DB → null cursor). */
  private safeEncodeListCursor(createdAt: unknown, orderId: string, scope: string): string | null {
    try {
      const d =
        createdAt instanceof Date ? createdAt : new Date(createdAt as string | number | Date);
      if (Number.isNaN(d.getTime())) {
        return null;
      }
      const oid = String(orderId ?? '').trim();
      if (!oid) {
        return null;
      }
      return encodeOrderListCursor(d, oid);
    } catch (e) {
      this.logOrdersReadSqlError(`${scope}/encode_cursor`, e);
      return null;
    }
  }

  /**
   * Runs [fn] inside BEGIN/COMMIT on the primary write pool (delivery / driver flows).
   * Returns null when PostgreSQL is not configured.
   */
  async runInTransaction<R>(fn: (client: PoolClient) => Promise<R>): Promise<R | null> {
    const client = await this.getWriteClient();
    if (!client) {
      return null;
    }
    try {
      await client.query('BEGIN');
      const out = await fn(client);
      await client.query('COMMIT');
      return out;
    } catch (e) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw e;
    } finally {
      client.release();
    }
  }

  /**
   * Single-statement write without transaction wrapper (caller composes transactions via [runInTransaction]).
   */
  async withWriteClient<R>(fn: (client: PoolClient) => Promise<R>): Promise<R | null> {
    const client = await this.getWriteClient();
    if (!client) {
      return null;
    }
    try {
      return await fn(client);
    } finally {
      client.release();
    }
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
    if (!storeId) {
      throw new ServiceUnavailableException('ORDER_INVALID_NO_STORE_UUID');
    }
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
    const deliveryLat = num(order['deliveryLat']);
    const deliveryLng = num(order['deliveryLng']);

    try {
      const existed = await client.query(`SELECT 1 FROM orders WHERE order_id = $1 LIMIT 1`, [
        orderId,
      ]);
      const wasUpdate = existed.rows.length > 0;

      await client.query(
        `INSERT INTO orders (
          order_id, user_id, store_id_uuid, items,
          subtotal_numeric, shipping_numeric, total_numeric,
          currency, write_source, customer_email, status,
          billing, delivery_address, list_title, payload,
          delivery_lat, delivery_lng, updated_at
        ) VALUES (
          $1, $2, $3::uuid, $4::jsonb,
          $5, $6, $7,
          $8, $9, $10, $11,
          $12::jsonb, $13, $14, $15::jsonb,
          $16, $17, NOW()
        )
        ON CONFLICT (order_id) DO UPDATE SET
          user_id = EXCLUDED.user_id,
          store_id_uuid = EXCLUDED.store_id_uuid,
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
          delivery_lat = EXCLUDED.delivery_lat,
          delivery_lng = EXCLUDED.delivery_lng,
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
          deliveryLat,
          deliveryLng,
        ],
      );
      return wasUpdate ? 'update' : 'insert';
    } finally {
      client.release();
    }
  }

  async findPayloadById(orderId: string): Promise<StoredOrder | null> {
    const client = await this.getReadClient();
    if (!client) {
      throw new ServiceUnavailableException(
        JSON.stringify({ code: 'orders_read_client_unavailable', scope: 'findPayloadById' }),
      );
    }
    try {
      const r = await client.query<{
        payload: unknown;
        created_at: Date;
        driver_id: string | null;
        delivery_status: string | null;
        delivery_lat: string | null;
        delivery_lng: string | null;
        eta_minutes: string | null;
        assigned_at: Date | null;
        delivery_on_the_way_at: Date | null;
        delivery_delivered_at: Date | null;
        driver_name: string | null;
        driver_phone: string | null;
        delivery_manual_retries: string | number | null;
      }>(
        `SELECT o.payload, o.created_at, o.driver_id, o.delivery_status, o.delivery_lat, o.delivery_lng, o.eta_minutes, o.assigned_at,
                o.delivery_on_the_way_at, o.delivery_delivered_at,
                o.delivery_manual_retries,
                NULL::text AS driver_name, NULL::text AS driver_phone
         FROM orders o
         WHERE o.order_id = $1`,
        [orderId.trim()],
      );
      if (r.rows.length === 0) return null;
      const row = r.rows[0];
      const raw = row.payload;
      if (raw == null || typeof raw !== 'object') return null;
      return mergeStoredOrderWithDeliveryColumns(raw, {
        driver_id: row.driver_id ?? null,
        delivery_status: row.delivery_status ?? null,
        delivery_lat: row.delivery_lat ?? null,
        delivery_lng: row.delivery_lng ?? null,
        eta_minutes: row.eta_minutes ?? null,
        assigned_at: row.assigned_at ?? null,
        created_at: row.created_at,
        delivery_on_the_way_at: row.delivery_on_the_way_at ?? null,
        delivery_delivered_at: row.delivery_delivered_at ?? null,
        driver_name: row.driver_name ?? null,
        driver_phone: row.driver_phone ?? null,
        delivery_manual_retries: row.delivery_manual_retries ?? null,
      });
    } catch (e) {
      this.logOrdersReadSqlError('findPayloadById', e);
      throw new ServiceUnavailableException(
        JSON.stringify({ code: 'orders_query_failed', scope: 'findPayloadById', orderId: orderId.trim() }),
      );
    } finally {
      client.release();
    }
  }

  private async assertStrictOrderIntegrity(client: PoolClient): Promise<void> {
    const q = await client.query(
      `SELECT COUNT(*) AS bad_orders
       FROM orders
       WHERE user_id IS NULL OR btrim(user_id) = '' OR store_id_uuid IS NULL`,
    );
    const badOrders = Number(q.rows[0]?.['bad_orders'] ?? 0);
    if (badOrders > 0) {
      throw new ServiceUnavailableException(
        JSON.stringify({ code: 'orders_integrity_violation', badOrders }),
      );
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
      throw new ServiceUnavailableException(
        JSON.stringify({ code: 'orders_read_client_unavailable', scope: 'findPayloadsByUserIdPaginated' }),
      );
    }
    const lim = Math.min(Math.max(1, limit), 50);
    const fetchN = lim + 1;
    let lastQueryText = '';
    let lastQueryParams: unknown[] = [];
    try {
      await this.assertStrictOrderIntegrity(client);
      let r: {
        rows: Array<{
          payload: unknown;
          created_at: Date;
          order_id: string;
          driver_id?: string | null;
          delivery_status?: string | null;
          delivery_lat?: string | null;
          delivery_lng?: string | null;
          eta_minutes?: string | null;
          assigned_at?: Date | null;
          delivery_on_the_way_at?: Date | null;
          delivery_delivered_at?: Date | null;
          driver_name?: string | null;
          driver_phone?: string | null;
          delivery_manual_retries?: string | number | null;
        }>;
      };
      const trackedQuery = (text: string, params: unknown[]) => {
        lastQueryText = text;
        lastQueryParams = params;
        return client.query(text, params);
      };
      const runQuery = async (compact: boolean) => {
        if (cursor == null) {
          if (compact) {
            return trackedQuery(
              `SELECT o.payload, o.created_at, o.order_id
               FROM orders o
               WHERE o.user_id = $1
               ORDER BY o.created_at DESC, o.order_id DESC
               LIMIT $2`,
              [userId.trim(), fetchN],
            );
          }
          return trackedQuery(
            `SELECT o.payload, o.created_at, o.order_id,
                    o.driver_id, o.delivery_status, o.delivery_lat, o.delivery_lng, o.eta_minutes, o.assigned_at,
                    o.delivery_on_the_way_at, o.delivery_delivered_at,
                    o.delivery_manual_retries,
                    NULL::text AS driver_name, NULL::text AS driver_phone
             FROM orders o
             WHERE o.user_id = $1
             ORDER BY o.created_at DESC, o.order_id DESC
             LIMIT $2`,
            [userId.trim(), fetchN],
          );
        }
        if (compact) {
          return trackedQuery(
            `SELECT o.payload, o.created_at, o.order_id
             FROM orders o
             WHERE o.user_id = $1
               AND (o.created_at, o.order_id) < ($2::timestamptz, $3::text)
             ORDER BY o.created_at DESC, o.order_id DESC
             LIMIT $4`,
            [userId.trim(), cursor.c, cursor.o, fetchN],
          );
        }
        return trackedQuery(
          `SELECT o.payload, o.created_at, o.order_id,
                  o.driver_id, o.delivery_status, o.delivery_lat, o.delivery_lng, o.eta_minutes, o.assigned_at,
                  o.delivery_on_the_way_at, o.delivery_delivered_at,
                  o.delivery_manual_retries,
                  NULL::text AS driver_name, NULL::text AS driver_phone
           FROM orders o
           WHERE o.user_id = $1
             AND (o.created_at, o.order_id) < ($2::timestamptz, $3::text)
           ORDER BY o.created_at DESC, o.order_id DESC
           LIMIT $4`,
          [userId.trim(), cursor.c, cursor.o, fetchN],
        );
      };
      r = await runQuery(false);
      const rows = r.rows;
      const hasMore = rows.length > lim;
      const slice = hasMore ? rows.slice(0, lim) : rows;
      const items: StoredOrder[] = [];
      for (const row of slice) {
        const p = row.payload;
        if (p == null || typeof p !== 'object' || Array.isArray(p)) {
          continue;
        }
        try {
          items.push(
            mergeStoredOrderWithDeliveryColumns(p, {
              driver_id: row.driver_id ?? null,
              delivery_status: row.delivery_status ?? null,
              delivery_lat: row.delivery_lat ?? null,
              delivery_lng: row.delivery_lng ?? null,
              eta_minutes: row.eta_minutes ?? null,
              assigned_at: row.assigned_at ?? null,
              created_at: row.created_at,
              delivery_on_the_way_at: row.delivery_on_the_way_at ?? null,
              delivery_delivered_at: row.delivery_delivered_at ?? null,
              driver_name: row.driver_name ?? null,
              driver_phone: row.driver_phone ?? null,
              delivery_manual_retries: row.delivery_manual_retries ?? null,
            }),
          );
        } catch {
          continue;
        }
      }
      let nextCursor: string | null = null;
      if (hasMore && slice.length > 0) {
        const last = slice[slice.length - 1];
        nextCursor = this.safeEncodeListCursor(last.created_at, last.order_id, 'findPayloadsByUserIdPaginated');
      }
      return { items, nextCursor, hasMore };
    } catch (e) {
      console.warn(
        '[OrdersPgService] findPayloadsByUserIdPaginated query failed',
        JSON.stringify({
          query: lastQueryText,
          params: lastQueryParams,
        }),
      );
      this.logOrdersReadSqlError('findPayloadsByUserIdPaginated', e);
      throw new ServiceUnavailableException(
        JSON.stringify({
          code: 'orders_query_failed',
          scope: 'findPayloadsByUserIdPaginated',
          userId: userId.trim(),
        }),
      );
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
      throw new ServiceUnavailableException(
        JSON.stringify({ code: 'orders_read_client_unavailable', scope: 'findPayloadsByStoreIdPaginated' }),
      );
    }
    const sid = storeId.trim();
    const lim = Math.min(Math.max(1, limit), 50);
    const fetchN = lim + 1;
    try {
      await this.assertStrictOrderIntegrity(client);
      let r: {
        rows: Array<{
          payload: unknown;
          created_at: Date;
          order_id: string;
          driver_id?: string | null;
          delivery_status?: string | null;
          delivery_lat?: string | null;
          delivery_lng?: string | null;
          eta_minutes?: string | null;
          assigned_at?: Date | null;
          delivery_on_the_way_at?: Date | null;
          delivery_delivered_at?: Date | null;
          driver_name?: string | null;
          driver_phone?: string | null;
          delivery_manual_retries?: string | number | null;
        }>;
      };
      const runQuery = async (compact: boolean) => {
        if (cursor == null) {
          if (compact) {
            return client.query(
              `SELECT o.payload, o.created_at, o.order_id
               FROM orders o
               WHERE o.store_id_uuid = $1::uuid
               ORDER BY o.created_at DESC, o.order_id DESC
               LIMIT $2`,
              [sid, fetchN],
            );
          }
          return client.query(
            `SELECT o.payload, o.created_at, o.order_id,
                    o.driver_id, o.delivery_status, o.delivery_lat, o.delivery_lng, o.eta_minutes, o.assigned_at,
                    o.delivery_on_the_way_at, o.delivery_delivered_at,
                    o.delivery_manual_retries,
                    NULL::text AS driver_name, NULL::text AS driver_phone
             FROM orders o
             WHERE o.store_id_uuid = $1::uuid
             ORDER BY o.created_at DESC, o.order_id DESC
             LIMIT $2`,
            [sid, fetchN],
          );
        }
        if (compact) {
          return client.query(
            `SELECT o.payload, o.created_at, o.order_id
             FROM orders o
             WHERE o.store_id_uuid = $1::uuid
               AND (o.created_at, o.order_id) < ($2::timestamptz, $3::text)
             ORDER BY o.created_at DESC, o.order_id DESC
             LIMIT $4`,
            [sid, cursor.c, cursor.o, fetchN],
          );
        }
        return client.query(
          `SELECT o.payload, o.created_at, o.order_id,
                  o.driver_id, o.delivery_status, o.delivery_lat, o.delivery_lng, o.eta_minutes, o.assigned_at,
                  o.delivery_on_the_way_at, o.delivery_delivered_at,
                  o.delivery_manual_retries,
                  NULL::text AS driver_name, NULL::text AS driver_phone
           FROM orders o
           WHERE o.store_id_uuid = $1::uuid
             AND (o.created_at, o.order_id) < ($2::timestamptz, $3::text)
           ORDER BY o.created_at DESC, o.order_id DESC
           LIMIT $4`,
          [sid, cursor.c, cursor.o, fetchN],
        );
      };
      r = await runQuery(false);
      const rows = r.rows;
      const hasMore = rows.length > lim;
      const slice = hasMore ? rows.slice(0, lim) : rows;
      const items: StoredOrder[] = [];
      for (const row of slice) {
        const p = row.payload;
        if (p == null || typeof p !== 'object' || Array.isArray(p)) {
          continue;
        }
        try {
          items.push(
            mergeStoredOrderWithDeliveryColumns(p, {
              driver_id: row.driver_id ?? null,
              delivery_status: row.delivery_status ?? null,
              delivery_lat: row.delivery_lat ?? null,
              delivery_lng: row.delivery_lng ?? null,
              eta_minutes: row.eta_minutes ?? null,
              assigned_at: row.assigned_at ?? null,
              created_at: row.created_at,
              delivery_on_the_way_at: row.delivery_on_the_way_at ?? null,
              delivery_delivered_at: row.delivery_delivered_at ?? null,
              driver_name: row.driver_name ?? null,
              driver_phone: row.driver_phone ?? null,
              delivery_manual_retries: row.delivery_manual_retries ?? null,
            }),
          );
        } catch {
          continue;
        }
      }
      let nextCursor: string | null = null;
      if (hasMore && slice.length > 0) {
        const last = slice[slice.length - 1];
        nextCursor = this.safeEncodeListCursor(last.created_at, last.order_id, 'findPayloadsByStoreIdPaginated');
      }
      return { items, nextCursor, hasMore };
    } catch (e) {
      this.logOrdersReadSqlError('findPayloadsByStoreIdPaginated', e);
      throw new ServiceUnavailableException(
        JSON.stringify({
          code: 'orders_query_failed',
          scope: 'findPayloadsByStoreIdPaginated',
          storeId: sid,
        }),
      );
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

/** Numeric columns from pg may arrive as string. */
function numish(v: unknown): number | null {
  return num(v);
}

function intish(v: unknown): number | null {
  if (v == null) return null;
  if (typeof v === 'number' && Number.isFinite(v)) {
    return Math.trunc(v);
  }
  const n = Number.parseInt(String(v), 10);
  return Number.isFinite(n) ? n : null;
}
