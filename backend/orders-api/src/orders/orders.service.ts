import {
  BadRequestException,
  forwardRef,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
  Optional,
  ServiceUnavailableException,
} from '@nestjs/common';
import { DriversService } from '../drivers/drivers.service';
import { ConsistencyPolicyService } from '../architecture/consistency/consistency-policy.service';
import { randomUUID } from 'node:crypto';
import { Pool } from 'pg';
import { buildPgPoolConfig } from '../infrastructure/database/pg-ssl';
import type { OrderComputed } from './order-computed';
import { computeOrderServiceFields } from './order-computed';
import { decodeOrderListCursor, type OrderListCursorPayload } from './order-cursor';
import type {
  CreateOrderResult,
  OrderGetResponse,
  StoredOrder,
  UserOrdersListResponse,
} from './order-types';
export type {
  CreateOrderResult,
  OrderGetResponse,
  StoredOrder,
  UserOrdersListResponse,
} from './order-types';
import { OrdersPgService } from './orders-pg.service';
import { assertOrderPayload, normalizeCustomerEmail, resolveOrderStoreId } from './order-rules';
import { logOrderError, logOrderEvent } from './order-logger';
import { OrderMetricsService } from './order-metrics.service';
import { validateShadowOrderPayload } from './order-validation';
import { DomainEventNames } from '../events/domain-event-names';
import { DomainEventEmitterService } from '../events/domain-event-emitter.service';
import { isTenantEnforcementEnabled } from '../identity/identity.config';
import {
  assertCreateOrderTenantScope,
  assertTenantAccess,
} from '../identity/tenant-access';
import { getTenantContext } from '../identity/tenant-context.storage';
import type { IOrderService } from '../architecture/contracts/i-order.service';
import { DomainId } from '../architecture/domain-id';
import { StoreCommissionsService } from '../stores/store-commissions.service';
import { UsersService } from '../users/users.service';
import { resolveDeliveryCoordinates } from './delivery-coordinates.util';
import { NotificationsService } from '../notifications/notifications.service';

const AMOUNT_EPS = 0.001;

const LIST_LIMIT_DEFAULT = 30;

function near(a: number, b: number): boolean {
  return Math.abs(a - b) < AMOUNT_EPS;
}

function num(v: unknown): number | null {
  if (v == null) return null;
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function clampLimit(n: number | undefined): number {
  if (n == null || Number.isNaN(n)) {
    return LIST_LIMIT_DEFAULT;
  }
  return Math.min(Math.max(1, Math.floor(n)), 50);
}

@Injectable()
export class OrdersService implements IOrderService {
  readonly domainId = DomainId.Orders;
  private readonly logger = new Logger(OrdersService.name);

  private readonly pool: Pool | null;

  constructor(
    private readonly metrics: OrderMetricsService,
    private readonly pg: OrdersPgService,
    private readonly domainEvents: DomainEventEmitterService,
    private readonly users: UsersService,
    private readonly notificationsService: NotificationsService,
    @Optional() private readonly consistencyPolicy?: ConsistencyPolicyService,
    @Optional() private readonly storeCommissions?: StoreCommissionsService,
    @Optional() @Inject(forwardRef(() => DriversService)) private readonly driversService?: DriversService,
  ) {
    const url = process.env.DATABASE_URL?.trim();
    this.pool = url
      ? new Pool(
          buildPgPoolConfig(url, {
            max: 4,
            idleTimeoutMillis: 30_000,
          }),
        )
      : null;
  }

  private ensureDbPool(): void {
    return;
  }

  private async enforceVariantSelections(items: Array<Record<string, unknown>>): Promise<void> {
    this.ensureDbPool();
    if (!this.pool || items.length === 0) return;
    const client = await this.pool.connect();
    try {
      for (const item of items) {
        const productIdRaw = item.productId ?? item['product_id'];
        if (productIdRaw == null) continue;
        const productId = String(productIdRaw).trim();
        if (!productId) continue;
        const pq = await client.query<{ has_variants: boolean }>(
          `SELECT has_variants FROM products WHERE id::text = $1 LIMIT 1`,
          [productId],
        );
        if (pq.rows.length === 0) continue;
        const hasVariants = Boolean(pq.rows[0]?.has_variants);
        const variantId = item.variantId != null ? String(item.variantId).trim() : '';
        if (hasVariants && !variantId) {
          throw new BadRequestException('variantId is required for variant-based product');
        }
        if (!variantId) continue;
        const vq = await client.query<{
          price: string;
          sku: string | null;
          options_json: Array<{ optionType: string; optionValue: string }> | null;
        }>(
          `SELECT pv.price,
                  pv.sku,
                  (
                    SELECT json_agg(
                      json_build_object(
                        'optionType', pvo.option_type,
                        'optionValue', pvo.option_value
                      )
                    )
                    FROM product_variant_options pvo
                    WHERE pvo.variant_id = pv.id
                  ) AS options_json
           FROM product_variants pv
           WHERE pv.id::text = $1 AND pv.product_id::text = $2
           LIMIT 1`,
          [variantId, productId],
        );
        if (vq.rows.length === 0) {
          this.logger.warn(
            JSON.stringify({
              kind: 'variant_missing_error',
              productId,
              variantId,
            }),
          );
          throw new BadRequestException('Invalid variantId for selected product');
        }
        const variantRow = vq.rows[0];
        const variantPrice = Number(variantRow.price ?? 0);
        const quantity = Number(item.quantity ?? 1);
        item['unitPrice'] = variantPrice;
        item['price'] = variantPrice.toFixed(3);
        item['lineTotal'] = variantPrice * quantity;
        item['variant_snapshot'] = {
          variantId,
          price: variantPrice,
          sku: variantRow.sku ?? '',
          options: Array.isArray(variantRow.options_json) ? variantRow.options_json : [],
        };
      }
    } finally {
      client.release();
    }
  }

  /** POST /orders — PostgreSQL only; fails closed when storage is unavailable or write errors. */
  async create(body: Record<string, unknown>, firebaseUid: string): Promise<CreateOrderResult> {
    try {
      assertOrderPayload(body, firebaseUid);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      throw new BadRequestException(msg);
    }

    if (!this.pg.isEnabled()) {
      throw new ServiceUnavailableException('PostgreSQL is required for order writes');
    }

    const orderId = String(body.orderId).trim();
    const eventTraceId = randomUUID();
    const validation = validateShadowOrderPayload(body, firebaseUid);

    const items = body.items as StoredOrder['items'];
    if (Array.isArray(items)) {
      await this.enforceVariantSelections(items as Array<Record<string, unknown>>);
    }
    const storeId =
      (body.storeId != null && String(body.storeId).trim()) ||
      resolveOrderStoreId(items as { storeId?: string }[]);

    assertCreateOrderTenantScope(firebaseUid, storeId);

    const totalHint = num(body['totalNumeric']) ?? num(body['total']) ?? 0;
    if (this.storeCommissions && storeId && totalHint > 0) {
      void this.storeCommissions.logCommissionPreviewAtOrderCreate(storeId, totalHint).catch(() => undefined);
    }

    const wsRaw = body.writeSource;
    const writeSource: 'backend' | 'firebase' =
      wsRaw === 'backend' || wsRaw === 'firebase' ? wsRaw : 'firebase';

    const order: StoredOrder = {
      ...body,
      orderId,
      firebaseOrderId: body.firebaseOrderId != null ? String(body.firebaseOrderId) : orderId,
      customerUid: firebaseUid,
      customerEmail: normalizeCustomerEmail(String(body.customerEmail)),
      storeId,
      items,
      source: 'app',
      writeSource,
      status: 'processing',
      receivedAt: new Date().toISOString(),
      shadowValidation: validation,
    };

    const bodyMap = body as Record<string, unknown>;
    const deliveryCoords = await resolveDeliveryCoordinates(bodyMap, firebaseUid, this.users);
    if (deliveryCoords) {
      order.deliveryLat = deliveryCoords.lat;
      order.deliveryLng = deliveryCoords.lng;
    } else {
      this.logger.warn(
        JSON.stringify({
          kind: 'delivery_coords_missing_after_resolve',
          orderId,
          userId: firebaseUid,
        }),
      );
      if (process.env.DELIVERY_COORDS_REQUIRED?.trim() === '1') {
        throw new BadRequestException('Missing delivery coordinates (deliveryLat/deliveryLng or profile)');
      }
    }

    let pgOp: 'insert' | 'update' | 'skipped' | null = null;
    try {
      pgOp = await this.pg.upsertOrderReturningOp(order);
    } catch (e) {
      logOrderError(e, { userId: firebaseUid, orderId });
      this.metrics.recordError();
      throw new ServiceUnavailableException('PostgreSQL order write failed');
    }
    if (pgOp === 'skipped') {
      throw new ServiceUnavailableException('PostgreSQL order write unavailable');
    }

    const storageCheck = this.storageSelfCheck(order, body);

    this.metrics.recordOrderCreated(validation.ok);
    this.metrics.recordWritePayloadSource(writeSource);
    if (!storageCheck.ok) {
      this.metrics.recordError();
    }

    logOrderEvent({
      kind: 'order_write',
      userId: firebaseUid,
      orderId,
      writeSource,
      mirrorStatus: 'client_async',
    });
    logOrderEvent({
      kind: 'order_created',
      userId: firebaseUid,
      orderId,
      validationOk: validation.ok,
      mismatchCount: validation.mismatches.length,
      storageCheckOk: storageCheck.ok,
    });
    if (!validation.ok) {
      logOrderEvent({
        kind: 'validation_detail',
        userId: firebaseUid,
        orderId,
        mismatches: validation.mismatches,
      });
    }
    if (!storageCheck.ok) {
      logOrderError(new Error(`storage_self_check: ${storageCheck.reasons.join('; ')}`), {
        userId: firebaseUid,
        orderId,
      });
    }

    if (pgOp != null) {
      const orderEventPayload = { orderId, storeId, customerUid: firebaseUid };
      const eventMeta = {
        traceId: eventTraceId,
        sourceService: 'orders' as const,
        correlationId: orderId,
      };
      if (pgOp === 'update') {
        this.domainEvents.dispatch(DomainEventNames.ORDER_UPDATED, orderId, orderEventPayload, eventMeta);
      } else {
        this.domainEvents.dispatch(DomainEventNames.ORDER_CREATED, orderId, orderEventPayload, eventMeta);
      }
    }

    const pgWriteOccurred = pgOp === 'insert' || pgOp === 'update';
    this.consistencyPolicy?.validateOrdersWriteTargetsPostgres(pgWriteOccurred, 'OrdersService.create');

    if (pgOp === 'insert' && this.driversService) {
      void this.driversService.autoAssignDriver(orderId).catch((err: unknown) =>
        console.error('[OrdersService] autoAssign failed:', err),
      );
    }
    if (pgOp === 'insert' && this.pool && storeId) {
      void this.pool
        .query<{ owner_id: string }>(
          `SELECT owner_id FROM stores WHERE id = $1::uuid LIMIT 1`,
          [storeId],
        )
        .then((r) => {
          const storeOwnerId = String(r.rows[0]?.owner_id ?? '').trim();
          if (!storeOwnerId) return;
          return this.notificationsService.sendPushToUser(storeOwnerId, {
            title: 'طلب جديد',
            body: 'لديك طلب جديد في متجرك',
            data: { orderId: order.orderId, type: 'new_order' },
          });
        })
        .catch((err: unknown) => console.error('[OrdersService] notify store failed:', err));
    }

    return { order, validation, storageCheck };
  }

  private storageSelfCheck(stored: StoredOrder, input: Record<string, unknown>): {
    ok: boolean;
    reasons: string[];
  } {
    const reasons: string[] = [];
    if (stored.orderId !== String(input.orderId).trim()) {
      reasons.push('orderId');
    }
    const inStore = input.storeId != null ? String(input.storeId).trim() : '';
    if (inStore && stored.storeId !== inStore) {
      reasons.push('storeId');
    }
    const inTotal = num(input.totalNumeric);
    const stTotal = num(stored.totalNumeric);
    if (inTotal != null && stTotal != null && !near(inTotal, stTotal)) {
      reasons.push('totalNumeric');
    }
    const itIn = input.items;
    const itSt = stored.items;
    if (Array.isArray(itIn) && Array.isArray(itSt) && itIn.length !== itSt.length) {
      reasons.push('items.length');
    }

    return { ok: reasons.length === 0, reasons };
  }

  /** GET /orders/:id — PostgreSQL only. */
  async getByIdWithComputed(orderId: string, firebaseUid: string): Promise<OrderGetResponse> {
    const id = orderId.trim();
    let order: StoredOrder | null = null;

    if (!this.pg.isEnabled()) {
      throw new NotFoundException('Order not found');
    }

    const fromPg = await this.pg.findPayloadById(id);
    if (fromPg) {
      const owner = fromPg.customerUid != null ? String(fromPg.customerUid) : '';
      if (owner && owner !== firebaseUid) {
        throw new NotFoundException('Order not found');
      }
      const canonicalStoreId = String(fromPg.storeId ?? '').trim();
      if (!canonicalStoreId) {
        throw new ServiceUnavailableException('ORDER_INVALID_NO_STORE_UUID');
      }
      order = fromPg;
    }

    if (!order) {
      throw new NotFoundException('Order not found');
    }

    assertTenantAccess({
      resourceUserId: order.customerUid,
      storeId: order.storeId,
    });

    const computed = computeOrderServiceFields(order as Record<string, unknown>);
    return { order, computed };
  }

  /**
   * GET /users/:id/orders — cursor pagination from PostgreSQL.
   * Pass `?legacy=1` for a raw array (deprecated clients).
   */
  async listForUser(
    userId: string,
    firebaseUid: string,
    opts: { cursor?: string; limit?: number; legacyFormat?: boolean } = {},
  ): Promise<UserOrdersListResponse | StoredOrder[]> {
    if (userId !== firebaseUid) {
      if (
        !isTenantEnforcementEnabled() ||
        getTenantContext()?.activeRole !== 'admin'
      ) {
        throw new BadRequestException('Cannot list orders for another user');
      }
    }

    const cursorRaw = opts.cursor?.trim();
    const cursorDecoded: OrderListCursorPayload | null = cursorRaw
      ? decodeOrderListCursor(cursorRaw)
      : null;
    if (cursorRaw && !cursorDecoded) {
      throw new BadRequestException('Invalid cursor');
    }

    const limit = clampLimit(opts.limit);

    const body = await this.listForUserInner(userId, firebaseUid, {
      limit,
      cursor: cursorDecoded,
    });

    if (opts.legacyFormat) {
      return body.items;
    }
    return body;
  }

  /**
   * GET /stores/:storeId/orders — owner dashboard; PostgreSQL only.
   */
  async listForStore(
    storeId: string,
    firebaseUid: string,
    opts: { cursor?: string; limit?: number } = {},
  ): Promise<UserOrdersListResponse> {
    const ctx = getTenantContext();
    const role = ctx?.activeRole ?? 'customer';
    const isPrivileged = role === 'admin' || role === 'system_internal';
    if (!isPrivileged) {
      if (role !== 'store_owner') {
        throw new BadRequestException('Store orders require store_owner or admin');
      }
      const ok = await this.verifyStoreOwnerAccess(storeId.trim(), firebaseUid);
      if (!ok) {
        throw new BadRequestException('Access denied');
      }
    }

    const cursorRaw = opts.cursor?.trim();
    const cursorDecoded: OrderListCursorPayload | null = cursorRaw ? decodeOrderListCursor(cursorRaw) : null;
    if (cursorRaw && !cursorDecoded) {
      throw new BadRequestException('Invalid cursor');
    }

    const limit = clampLimit(opts.limit);
    if (!this.pg.isEnabled()) {
      return {
        items: [],
        nextCursor: null,
        hasMore: false,
        useFirestoreFallback: false,
      };
    }
    const { items, nextCursor, hasMore } = await this.pg.findPayloadsByStoreIdPaginated(
      storeId,
      limit,
      cursorDecoded,
    );
    for (const item of items) {
      const canonicalStoreId = String(item.storeId ?? '').trim();
      if (!canonicalStoreId) {
        throw new ServiceUnavailableException('ORDER_INVALID_NO_STORE_UUID');
      }
    }
    return {
      items,
      nextCursor,
      hasMore,
      useFirestoreFallback: false,
    };
  }

  private async verifyStoreOwnerAccess(storeId: string, firebaseUid: string): Promise<boolean> {
    if (!this.pool) return false;
    const client = await this.pool.connect();
    try {
      const r = await client.query<{ owner_id: string }>(
        `SELECT owner_id FROM stores WHERE id = $1::uuid LIMIT 1`,
        [storeId.trim()],
      );
      if (r.rows.length === 0) return false;
      return String(r.rows[0].owner_id ?? '') === firebaseUid.trim();
    } finally {
      client.release();
    }
  }

  private async listForUserInner(
    userId: string,
    firebaseUid: string,
    args: {
      limit: number;
      cursor: OrderListCursorPayload | null;
    },
  ): Promise<UserOrdersListResponse> {
    const { limit, cursor } = args;

    if (!this.pg.isEnabled()) {
      return {
        items: [],
        nextCursor: null,
        hasMore: false,
        useFirestoreFallback: false,
      };
    }

    let pg: { items: StoredOrder[]; nextCursor: string | null; hasMore: boolean };
    pg = await this.pg.findPayloadsByUserIdPaginated(userId, limit, cursor);
    for (const item of pg.items) {
      const canonicalStoreId = String(item.storeId ?? '').trim();
      if (!canonicalStoreId) {
        throw new ServiceUnavailableException('ORDER_INVALID_NO_STORE_UUID');
      }
    }

    return {
      items: pg.items,
      nextCursor: pg.nextCursor,
      hasMore: pg.hasMore,
      useFirestoreFallback: false,
    };
  }

  isOrderStorageConfigured(): boolean {
    return this.pg.isEnabled();
  }

  async updateStatus(
    orderId: string,
    status: string,
    firebaseUid: string,
  ): Promise<{ orderId: string; status: string }> {
    const id = orderId.trim();
    const next = status.trim().toLowerCase();
    if (!id || !next) {
      throw new BadRequestException('orderId and status are required');
    }
    const order = await this.pg.findPayloadById(id);
    if (!order) {
      throw new NotFoundException('Order not found');
    }
    const ctx = getTenantContext();
    const role = ctx?.activeRole ?? 'customer';
    const isAdmin = role === 'admin' || role === 'system_internal';
    const isOwner = String(order.customerUid ?? '').trim() === firebaseUid.trim();
    const storeIdOrder = String(order.storeId ?? '').trim();
    const ctxStore = String(ctx?.storeId ?? '').trim();
    const isScopedStoreOwner =
      role === 'store_owner' && ctxStore.length > 0 && ctxStore === storeIdOrder;
    const wid = String((order as Record<string, unknown>)['wholesalerId'] ?? '').trim();
    const ctxWid = String(ctx?.wholesalerId ?? '').trim();
    const isWholesaleStoreOwner =
      role === 'store_owner' && String(ctx?.storeType ?? '').trim().toLowerCase() === 'wholesale';
    const isWholesaler =
      (String(role).toLowerCase() === 'wholesaler' || String(role).toLowerCase() === 'wholesaler_owner' || isWholesaleStoreOwner) &&
      wid.length > 0 &&
      wid === ctxWid;
    if (!isAdmin && !isOwner && !isScopedStoreOwner && !isWholesaler) {
      throw new NotFoundException('Order not found');
    }

    const prev = String(order.status ?? 'pending').trim().toLowerCase();
    const terminalDone = new Set(['delivered', 'completed']);
    if (terminalDone.has(prev)) {
      throw new BadRequestException('Order is final');
    }
    if (prev === 'cancelled') {
      throw new BadRequestException('Order is cancelled');
    }
    const flow = ['pending', 'processing', 'shipped', 'delivered'];
    const pi = flow.indexOf(prev);
    const ni = flow.indexOf(next);
    if (isOwner && !isAdmin && !isScopedStoreOwner && !isWholesaler && next !== 'cancelled') {
      throw new BadRequestException('Customers can only cancel their orders');
    }
    if (next === 'cancelled' && isOwner && !isAdmin) {
      const nonCancelable = new Set(['shipped', 'delivered', 'completed']);
      if (nonCancelable.has(prev)) {
        throw new BadRequestException('Order can only be cancelled before delivery');
      }
    }
    if (next !== 'cancelled' && ni >= 0 && pi >= 0 && ni < pi) {
      throw new BadRequestException('Invalid status transition');
    }

    const patched: StoredOrder = {
      ...order,
      status: next,
      updatedAt: new Date().toISOString(),
    };
    await this.pg.upsertOrder(patched);

    logOrderEvent({
      kind: 'order_status_updated',
      orderId: id,
      status: next,
      firebaseUid,
    });

    const wasDelivered = terminalDone.has(prev);
    const nowDelivered = terminalDone.has(next);
    if (!wasDelivered && nowDelivered && storeIdOrder) {
      const t = num(order.totalNumeric) ?? 0;
      await this.storeCommissions?.recordCommissionOnDelivery(storeIdOrder, id, t);
    }
    if (!wasDelivered && nowDelivered && this.driversService) {
      const dRaw = (patched as unknown as Record<string, unknown>)['driverId'] ?? (order as unknown as Record<string, unknown>)['driverId'];
      const driverId = dRaw != null ? String(dRaw).trim() : '';
      const ship = num((patched as unknown as Record<string, unknown>)['shippingNumeric']) ?? num((order as unknown as Record<string, unknown>)['shippingNumeric']);
      void this.driversService.recordPendingEarningOnDeliveredOrder(id, driverId || null, ship);
    }

    return { orderId: id, status: next };
  }

  async adminCancelOrder(
    orderId: string,
    reason: string,
    adminUid: string,
  ): Promise<{ orderId: string; status: string }> {
    const id = orderId.trim();
    const why = reason.trim();
    if (!id) throw new BadRequestException('orderId is required');
    if (why.length < 10) throw new BadRequestException('reason must be at least 10 characters');
    if (!this.pool) throw new ServiceUnavailableException('database unavailable');

    const client = await this.pool.connect();
    try {
      const res = await client.query<{
        customer_uid: string | null;
        store_id_uuid: string | null;
      }>(
        `UPDATE orders
         SET status = 'cancelled',
             cancellation_reason = $2,
             cancelled_by = 'admin',
             cancelled_at = NOW(),
             updated_at = NOW()
         WHERE order_id = $1
         RETURNING customer_uid, store_id_uuid::text`,
        [id, why],
      );
      if (res.rowCount === 0) {
        throw new NotFoundException('Order not found');
      }

      const customerUid = String(res.rows[0]?.customer_uid ?? '').trim();
      const storeId = String(res.rows[0]?.store_id_uuid ?? '').trim();

      if (customerUid) {
        void this.notificationsService.sendPushToUser(customerUid, {
          title: 'تم إلغاء الطلب',
          body: `تم إلغاء طلبك من قبل الإدارة: ${why}`,
          data: { orderId: id, type: 'order_cancelled_by_admin' },
        });
      }

      if (storeId) {
        void client
          .query<{ owner_id: string }>(
            `SELECT owner_id FROM stores WHERE id = $1::uuid LIMIT 1`,
            [storeId],
          )
          .then((q) => {
            const storeOwnerUid = String(q.rows[0]?.owner_id ?? '').trim();
            if (!storeOwnerUid) return;
            return this.notificationsService.sendPushToUser(storeOwnerUid, {
              title: 'إلغاء طلب من الإدارة',
              body: `تم إلغاء الطلب #${id} من قبل الإدارة`,
              data: { orderId: id, type: 'order_cancelled_by_admin' },
            });
          })
          .catch(() => undefined);
      }

      logOrderEvent({
        kind: 'order_status_updated',
        orderId: id,
        firebaseUid: adminUid,
        status: 'cancelled',
      });
      return { orderId: id, status: 'cancelled' };
    } finally {
      client.release();
    }
  }

  async pingOrderStorage(): Promise<{ ok: boolean; error?: string }> {
    if (!this.pg.isEnabled()) {
      return { ok: false, error: 'not_configured' };
    }
    const r = await this.pg.ping();
    return r.ok ? { ok: true } : { ok: false, error: r.error };
  }
}
