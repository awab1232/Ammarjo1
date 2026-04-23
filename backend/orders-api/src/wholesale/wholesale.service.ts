import {
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  Optional,
  ServiceUnavailableException,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Pool, type PoolClient } from 'pg';
import { DomainEventEmitterService } from '../events/domain-event-emitter.service';
import { DomainEventNames } from '../events/domain-event-names';
import { assertWholesaleStoreTypeAccess } from '../identity/tenant-access';
import { TenantContextService } from '../identity/tenant-context.service';
import { ProductVariantsService } from '../stores/product-variants.service';
import { logAuditJson } from '../common/audit-log';
import type {
  CreateWholesaleOrderDto,
  WholesaleCategoryWriteDto,
  WholesaleJoinRequestDto,
  WholesaleOrder,
  WholesaleProductWriteDto,
  WholesalePriceRule,
  WholesaleProduct,
  WholesaleStorePatchDto,
  WholesaleStore,
  UpdateWholesaleOrderStatusDto,
} from './wholesale.types';

@Injectable()
export class WholesaleService {
  private readonly logger = new Logger(WholesaleService.name);
  private readonly pool: Pool | null;
  private readonly wholesalerColumns =
    'id, owner_id, name, logo, cover_image, description, category, city, phone, email, status, commission, delivery_days, delivery_fee, created_at, updated_at';
  private readonly wholesaleOrderColumns =
    'id, wholesaler_id, store_id, store_owner_id, store_name, subtotal, commission, net_amount, status, items, created_at, updated_at';

  constructor(
    private readonly events: DomainEventEmitterService,
    private readonly variants: ProductVariantsService,
    @Optional() private readonly tenant?: TenantContextService,
  ) {
    const url = process.env.DATABASE_URL?.trim();
    this.pool = url
      ? new Pool({
          connectionString: url,
          max: Number(process.env.WHOLESALE_PG_POOL_MAX || 6),
          idleTimeoutMillis: 30_000,
        })
      : null;
  }

  private requireDb(): Pool {
    if (!this.pool) throw new ServiceUnavailableException('wholesale database not configured');
    return this.pool;
  }

  private actorIdOrThrow(): string {
    const uid = this.tenant?.getSnapshot().uid?.trim();
    if (!uid) throw new ForbiddenException('Authenticated actor is required');
    return uid;
  }

  private actorRole(): string {
    const snap = this.tenant?.getSnapshot();
    const role = snap?.activeRole?.trim() || '';
    const storeType = String(snap?.storeType ?? '').trim().toLowerCase();
    if (role === 'store_owner' && storeType === 'wholesale') {
      return 'wholesaler_owner';
    }
    return role;
  }

  private isPrivilegedRole(): boolean {
    const role = this.actorRole();
    return role === 'admin' || role === 'system_internal';
  }

  private logAuthorizationViolation(
    resourceId: string,
    resourceType: string,
    action: string,
    reason: string,
  ): void {
    const userId = this.tenant?.getSnapshot().uid ?? null;
    this.logger.warn(
      JSON.stringify({
        kind: 'authorization_violation',
        userId,
        resourceId,
        resourceType,
        action,
        reason,
      }),
    );
  }

  private logSensitiveAudit(action: string, entity: string, entityId: string): void {
    const snap = this.tenant?.getSnapshot();
    logAuditJson('audit', {
      userId: snap?.uid ?? 'unknown',
      role: snap?.activeRole ?? '',
      action,
      entity,
      entityId,
      timestamp: new Date().toISOString(),
    });
  }

  private async assertWholesalerOwnerByStoreRef(client: PoolClient, storeRef: string, action: string): Promise<void> {
    if (this.isPrivilegedRole()) return;
    const actor = this.actorIdOrThrow();
    if (this.actorRole() !== 'wholesaler_owner') {
      this.logAuthorizationViolation(storeRef, 'wholesaler_store', action, 'role_not_allowed');
      throw new ForbiddenException('Access denied');
    }
    const q = await client.query(`SELECT id FROM wholesalers WHERE id::text = $1 AND owner_id = $2 LIMIT 1`, [
      storeRef.trim(),
      actor,
    ]);
    if (q.rows.length === 0) {
      this.logAuthorizationViolation(storeRef, 'wholesaler_store', action, 'owner_mismatch');
      throw new ForbiddenException('Access denied');
    }
  }

  private async assertWholesalerOwnerByProductRef(client: PoolClient, productId: string, action: string): Promise<string> {
    if (this.isPrivilegedRole()) {
      const q = await client.query(`SELECT wholesaler_id::text AS wid FROM wholesale_products WHERE id = $1::uuid LIMIT 1`, [
        productId.trim(),
      ]);
      if (q.rows.length === 0) throw new NotFoundException('Wholesale product not found');
      return String((q.rows[0] as Record<string, unknown>).wid ?? '');
    }
    const actor = this.actorIdOrThrow();
    const q = await client.query(
      `SELECT p.wholesaler_id::text AS wid
       FROM wholesale_products p
       JOIN wholesalers w ON w.id = p.wholesaler_id
       WHERE p.id = $1::uuid AND w.owner_id = $2
       LIMIT 1`,
      [productId.trim(), actor],
    );
    if (q.rows.length === 0) {
      this.logAuthorizationViolation(productId, 'wholesale_product', action, 'owner_mismatch');
      throw new ForbiddenException('Access denied');
    }
    return String((q.rows[0] as Record<string, unknown>).wid ?? '');
  }

  private async assertWholesalerOwnerByVariantRef(client: PoolClient, variantId: string, action: string): Promise<void> {
    if (this.isPrivilegedRole()) return;
    const actor = this.actorIdOrThrow();
    const q = await client.query(
      `SELECT pv.id
       FROM product_variants pv
       JOIN wholesale_products p ON p.id = pv.wholesale_product_id
       JOIN wholesalers w ON w.id = p.wholesaler_id
       WHERE pv.id = $1::uuid AND w.owner_id = $2
       LIMIT 1`,
      [variantId.trim(), actor],
    );
    if (q.rows.length === 0) {
      this.logAuthorizationViolation(variantId, 'wholesale_variant', action, 'owner_mismatch');
      throw new ForbiddenException('Access denied');
    }
  }

  private withClient<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    return this.requireDb()
      .connect()
      .then(async (client) => {
        try {
          return await fn(client);
        } finally {
          client.release();
        }
      });
  }

  private mapStore(row: Record<string, unknown>): WholesaleStore {
    return {
      id: String(row.id),
      ownerId: String(row.owner_id),
      name: String(row.name ?? ''),
      logo: String(row.logo ?? ''),
      coverImage: String(row.cover_image ?? ''),
      description: String(row.description ?? ''),
      category: String(row.category ?? ''),
      city: String(row.city ?? ''),
      phone: String(row.phone ?? ''),
      email: String(row.email ?? ''),
      status: String(row.status ?? 'approved'),
      commission: Number(row.commission ?? 8),
      deliveryDays: row.delivery_days != null ? Number(row.delivery_days) : null,
      deliveryFee: row.delivery_fee != null ? Number(row.delivery_fee) : null,
      createdAt: new Date(String(row.created_at)).toISOString(),
    };
  }

  private mapOrder(row: Record<string, unknown>): WholesaleOrder {
    return {
      id: String(row.id),
      wholesalerId: String(row.wholesaler_id),
      storeId: String(row.store_id),
      storeOwnerId: String(row.store_owner_id),
      storeName: String(row.store_name ?? ''),
      subtotal: Number(row.subtotal ?? 0),
      commission: Number(row.commission ?? 0),
      netAmount: Number(row.net_amount ?? 0),
      status: String(row.status ?? 'pending'),
      items: Array.isArray(row.items) ? (row.items as Array<Record<string, unknown>>) : [],
      createdAt: new Date(String(row.created_at)).toISOString(),
    };
  }

  private mapProductRow(x: Record<string, unknown>): WholesaleProduct {
    return {
      id: String(x.id),
      wholesalerId: String(x.wholesaler_id),
      productCode: String(x.product_code ?? ''),
      name: String(x.name ?? ''),
      imageUrl: String(x.image_url ?? ''),
      unit: String(x.unit ?? ''),
      categoryId: x.category_id != null ? String(x.category_id) : null,
      stock: Number(x.stock ?? 0),
      hasVariants: Boolean(x.has_variants),
      quantityPrices: (Array.isArray(x.quantity_prices) ? x.quantity_prices : []) as WholesalePriceRule[],
    };
  }

  async listStores(limit = 30, cursor?: string): Promise<{ items: WholesaleStore[]; nextCursor: string | null }> {
    this.actorIdOrThrow();
    assertWholesaleStoreTypeAccess();
    return this.withClient(async (client) => {
      const l = Math.min(Math.max(1, Number(limit) || 30), 100);
      const params: unknown[] = [];
      let where = `WHERE status = 'approved'`;
      let idx = 1;
      if (cursor?.trim()) {
        where += ` AND id > $${idx++}::uuid`;
        params.push(cursor.trim());
      }
      params.push(l + 1);
      const q = await client.query(
        `SELECT ${this.wholesalerColumns} FROM wholesalers
         ${where}
         ORDER BY id ASC
         LIMIT $${idx}`,
        params,
      );
      const rows = q.rows.map((x) => this.mapStore(x as Record<string, unknown>));
      const hasMore = rows.length > l;
      const items = hasMore ? rows.slice(0, l) : rows;
      const nextCursor = hasMore && items.length > 0 ? items[items.length - 1]!.id : null;
      return { items, nextCursor };
    });
  }

  async getStoreById(id: string): Promise<WholesaleStore> {
    const actor = this.actorIdOrThrow();
    const storeId = id.trim();
    if (!storeId) {
      throw new NotFoundException('Store not found');
    }
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT ${this.wholesalerColumns}
         FROM wholesalers
         WHERE id = $1::uuid
           AND (
             $2::boolean = true
             OR owner_id = $3
             OR status = 'approved'
           )
         LIMIT 1`,
        [storeId, this.isPrivilegedRole(), actor],
      );
      if (q.rows.length === 0) {
        throw new NotFoundException('Store not found');
      }
      return this.mapStore(q.rows[0] as Record<string, unknown>);
    });
  }

  async listStoreCategories(
    storeId: string,
  ): Promise<Array<{ id: string; storeId: string; name: string; imageUrl: string; order: number; isActive: boolean }>> {
    this.actorIdOrThrow();
    const sid = storeId.trim();
    if (!sid) {
      return [];
    }
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id, store_id, name, image_url, sort_order
         FROM store_categories
         WHERE store_id = $1
         ORDER BY sort_order ASC, created_at ASC`,
        [sid],
      );
      return q.rows.map((row) => {
        const r = row as Record<string, unknown>;
        return {
          id: String(r.id),
          storeId: String(r.store_id),
          name: String(r.name ?? ''),
          imageUrl: String(r.image_url ?? ''),
          order: Number(r.sort_order ?? 0),
          isActive: true,
        };
      });
    });
  }

  async listProducts(input: {
    storeId?: string;
    limit?: number;
    cursor?: string;
  }): Promise<{ items: WholesaleProduct[]; nextCursor: string | null }> {
    const actor = this.actorIdOrThrow();
    assertWholesaleStoreTypeAccess();
    return this.withClient(async (client) => {
      const limit = Math.min(Math.max(1, Number(input.limit ?? 30) || 30), 100);
      const params: unknown[] = [];
      const clauses: string[] = [];
      let idx = 1;
      if (input.storeId?.trim()) {
        clauses.push(`p.wholesaler_id = $${idx++}::uuid`);
        params.push(input.storeId.trim());
      }
      if (input.cursor?.trim()) {
        clauses.push(`p.id > $${idx++}::uuid`);
        params.push(input.cursor.trim());
      }
      if (!this.isPrivilegedRole()) {
        if (this.actorRole() === 'wholesaler_owner') {
          clauses.push(
            `EXISTS (SELECT 1 FROM wholesalers w WHERE w.id = p.wholesaler_id AND w.owner_id = $${idx++})`,
          );
          params.push(actor);
        } else {
          clauses.push(`EXISTS (SELECT 1 FROM wholesalers w WHERE w.id = p.wholesaler_id AND w.status = 'approved')`);
        }
      }
      const where = clauses.length > 0 ? `WHERE ${clauses.join(' AND ')}` : '';
      params.push(limit + 1);
      const q = await client.query(
        `SELECT p.*,
            COALESCE(
              json_agg(
                json_build_object('minQty', r.min_qty, 'maxQty', r.max_qty, 'price', r.price)
                ORDER BY r.min_qty ASC
              ) FILTER (WHERE r.id IS NOT NULL),
              '[]'::json
            ) AS quantity_prices
         FROM wholesale_products p
         LEFT JOIN wholesale_pricing_rules r ON r.wholesale_product_id = p.id
         ${where}
         GROUP BY p.id
         ORDER BY p.id ASC
         LIMIT $${idx}`,
        params,
      );
      const rows = q.rows.map((row) => this.mapProductRow(row as Record<string, unknown>));
      const hasMore = rows.length > limit;
      const items = hasMore ? rows.slice(0, limit) : rows;
      const nextCursor = hasMore && items.length > 0 ? items[items.length - 1]!.id : null;
      return { items, nextCursor };
    });
  }

  async getProductById(id: string): Promise<WholesaleProduct | null> {
    const actor = this.actorIdOrThrow();
    assertWholesaleStoreTypeAccess();
    return this.withClient(async (client) => {
      const extraFilter =
        !this.isPrivilegedRole() && this.actorRole() === 'wholesaler_owner'
          ? ` AND EXISTS (SELECT 1 FROM wholesalers w2 WHERE w2.id = p.wholesaler_id AND w2.owner_id = $2)`
          : !this.isPrivilegedRole()
            ? ` AND EXISTS (SELECT 1 FROM wholesalers w2 WHERE w2.id = p.wholesaler_id AND w2.status = 'approved')`
            : '';
      const params = !this.isPrivilegedRole() && this.actorRole() === 'wholesaler_owner' ? [id.trim(), actor] : [id.trim()];
      const q = await client.query(
        `SELECT p.*,
            COALESCE(
              json_agg(
                json_build_object('minQty', r.min_qty, 'maxQty', r.max_qty, 'price', r.price)
                ORDER BY r.min_qty ASC
              ) FILTER (WHERE r.id IS NOT NULL),
              '[]'::json
            ) AS quantity_prices
         FROM wholesale_products p
         LEFT JOIN wholesale_pricing_rules r ON r.wholesale_product_id = p.id
         WHERE p.id = $1::uuid
         ${extraFilter}
         GROUP BY p.id
         LIMIT 1`,
        params,
      );
      if (q.rows.length === 0) return null;
      const x = q.rows[0] as Record<string, unknown>;
      const product = this.mapProductRow(x);
      this.events.dispatch(DomainEventNames.WHOLESALE_PRODUCT_VIEWED, product.id, {
        productId: product.id,
        wholesalerId: product.wholesalerId,
      });
      return product;
    });
  }

  async createOrder(body: CreateWholesaleOrderDto): Promise<WholesaleOrder> {
    const actor = this.actorIdOrThrow();
    assertWholesaleStoreTypeAccess();
    return this.withClient(async (client) => {
      await client.query('BEGIN');
      try {
        for (const item of body.items) {
          const p = await client.query<{ has_variants: boolean }>(
            `SELECT has_variants FROM wholesale_products WHERE id = $1::uuid LIMIT 1`,
            [item.productId.trim()],
          );
          if (p.rows.length === 0) {
            throw new NotFoundException('Wholesale product not found');
          }
          if (Boolean(p.rows[0]?.has_variants) && (!item.variantId || !item.variantId.trim())) {
            throw new ForbiddenException('variantId is required for variant-based product');
          }
          if (item.variantId?.trim()) {
            const vq = await client.query<{
              price: string;
              sku: string | null;
              options_json: Array<{ optionType: string; optionValue: string }> | null;
            }>(
              `SELECT pv.price,
                      pv.sku,
                      (
                        SELECT COALESCE(
                          json_agg(
                            json_build_object(
                              'optionType', pvo.option_type,
                              'optionValue', pvo.option_value
                            )
                          ),
                          '[]'::json
                        )
                        FROM product_variant_options pvo
                        WHERE pvo.variant_id = pv.id
                      ) AS options_json
               FROM product_variants pv
               WHERE pv.id = $1::uuid AND pv.wholesale_product_id = $2::uuid
               LIMIT 1`,
              [item.variantId.trim(), item.productId.trim()],
            );
            if (vq.rows.length === 0) {
              throw new ForbiddenException('Invalid variantId for product');
            }
            const variantRow = vq.rows[0];
            item.unitPrice = Number(variantRow.price ?? 0);
            item.total = Number(item.unitPrice) * Number(item.quantity);
            const itemMutable = item as unknown as Record<string, unknown>;
            itemMutable['variant_snapshot'] = {
              variantId: item.variantId.trim(),
              price: Number(variantRow.price ?? 0),
              sku: variantRow.sku ?? '',
              options: Array.isArray(variantRow.options_json) ? variantRow.options_json : [],
            };
          }
        }
        const subtotal = body.items.reduce((sum, i) => sum + Number(i.total || 0), 0);
        const commissionRate = Number(body.commissionRate ?? 0.08);
        const commission = subtotal * commissionRate;
        const netAmount = subtotal - commission;
        const id = randomUUID();
        const inserted = await client.query(
          `INSERT INTO wholesale_orders (
             id, wholesaler_id, store_id, store_owner_id, store_name, subtotal, commission, net_amount, status, items, created_at, updated_at
           ) VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6, $7, $8, 'pending', $9::jsonb, NOW(), NOW())
           RETURNING *`,
          [
            id,
            body.wholesalerId,
            body.storeId.trim(),
            actor,
            body.storeName.trim(),
            subtotal,
            commission,
            netAmount,
            JSON.stringify(body.items),
          ],
        );
        const order = this.mapOrder(inserted.rows[0] as Record<string, unknown>);
        await this.events.enqueueInTransaction(client, DomainEventNames.WHOLESALE_ORDER_CREATED, order.id, {
          orderId: order.id,
          wholesalerId: order.wholesalerId,
          storeId: order.storeId,
          storeOwnerId: order.storeOwnerId,
          subtotal: order.subtotal,
        });
        await client.query('COMMIT');
        return order;
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      }
    });
  }

  async listOrders(input: {
    storeId?: string;
    wholesalerId?: string;
    limit?: number;
    cursor?: string;
  }): Promise<{ items: WholesaleOrder[]; nextCursor: string | null }> {
    const actor = this.actorIdOrThrow();
    assertWholesaleStoreTypeAccess();
    return this.withClient(async (client) => {
      const limit = Math.min(Math.max(1, Number(input.limit ?? 30) || 30), 100);
      const params: unknown[] = [];
      const clauses: string[] = [];
      let idx = 1;
      if (input.storeId?.trim()) {
        clauses.push(`store_id = $${idx++}`);
        params.push(input.storeId.trim());
      }
      if (input.wholesalerId?.trim()) {
        clauses.push(`wholesaler_id = $${idx++}::uuid`);
        params.push(input.wholesalerId.trim());
      }
      if (!this.isPrivilegedRole()) {
        if (this.actorRole() === 'wholesaler_owner') {
          const owned = await client.query<{ id: string }>(`SELECT id::text AS id FROM wholesalers WHERE owner_id = $1`, [actor]);
          const ids = owned.rows.map((x) => x.id);
          if (ids.length === 0) {
            return { items: [], nextCursor: null };
          }
          clauses.push(`wholesaler_id::text = ANY($${idx++}::text[])`);
          params.push(ids);
        } else {
          clauses.push(`store_owner_id = $${idx++}`);
          params.push(actor);
        }
      }
      if (input.cursor?.trim()) {
        clauses.push(`(created_at, id) < ($${idx++}::timestamptz, $${idx++}::uuid)`);
        const raw = JSON.parse(Buffer.from(input.cursor.trim(), 'base64url').toString('utf8')) as {
          c?: string;
          id?: string;
        };
        params.push(raw.c ?? '', raw.id ?? '');
      }
      const where = clauses.length > 0 ? `WHERE ${clauses.join(' AND ')}` : '';
      params.push(limit + 1);
      const q = await client.query(
        `SELECT ${this.wholesaleOrderColumns} FROM wholesale_orders
         ${where}
         ORDER BY created_at DESC, id DESC
         LIMIT $${idx}`,
        params,
      );
      const rows = q.rows.map((x) => this.mapOrder(x as Record<string, unknown>));
      const hasMore = rows.length > limit;
      const items = hasMore ? rows.slice(0, limit) : rows;
      const last = items.length > 0 ? items[items.length - 1] : null;
      const nextCursor =
        hasMore && last
          ? Buffer.from(JSON.stringify({ c: last.createdAt, id: last.id }), 'utf8').toString('base64url')
          : null;
      return { items, nextCursor };
    });
  }

  async updateOrderStatus(id: string, body: UpdateWholesaleOrderStatusDto): Promise<WholesaleOrder> {
    const actor = this.actorIdOrThrow();
    return this.withClient(async (client) => {
      if (!this.isPrivilegedRole()) {
        const qOwner = await client.query(
          `SELECT o.id, o.store_owner_id, w.owner_id AS wholesaler_owner_id
           FROM wholesale_orders o
           JOIN wholesalers w ON w.id = o.wholesaler_id
           WHERE o.id = $1::uuid
           LIMIT 1`,
          [id.trim()],
        );
        if (qOwner.rows.length === 0) throw new NotFoundException('Wholesale order not found');
        const row = qOwner.rows[0] as Record<string, unknown>;
        const allowed =
          String(row.store_owner_id ?? '') === actor || String(row.wholesaler_owner_id ?? '') === actor;
        if (!allowed) {
          this.logAuthorizationViolation(id, 'wholesale_order', 'update_status', 'owner_mismatch');
          throw new ForbiddenException('Access denied');
        }
      }
      const q = await client.query(
        `UPDATE wholesale_orders SET status = $2, updated_at = NOW() WHERE id = $1::uuid RETURNING *`,
        [id.trim(), body.status.trim()],
      );
      if (q.rows.length === 0) throw new NotFoundException('Wholesale order not found');
      return this.mapOrder(q.rows[0] as Record<string, unknown>);
    });
  }

  async submitJoinRequest(body: WholesaleJoinRequestDto): Promise<WholesaleStore> {
    this.actorIdOrThrow();
    return this.withClient(async (client) => {
      const id = randomUUID();
      const q = await client.query(
        `INSERT INTO wholesalers (
          id, owner_id, name, description, category, city, phone, email, status, created_at, updated_at
        ) VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, $8, 'pending', NOW(), NOW())
        RETURNING *`,
        [
          id,
          body.applicantId.trim(),
          body.wholesalerName.trim(),
          (body.description ?? '').trim(),
          (body.category ?? '').trim(),
          (body.city ?? '').trim(),
          body.applicantPhone.trim(),
          body.applicantEmail.trim(),
        ],
      );
      return this.mapStore(q.rows[0] as Record<string, unknown>);
    });
  }

  async createProduct(body: WholesaleProductWriteDto): Promise<WholesaleProduct> {
    this.actorIdOrThrow();
    return this.withClient(async (client) => {
      await this.assertWholesalerOwnerByStoreRef(client, body.storeId, 'create_product');
      await client.query('BEGIN');
      try {
        if (body.hasVariants === true && (!body.variants || body.variants.length === 0)) {
          throw new ForbiddenException('Product with hasVariants=true must include variants');
        }
        const id = randomUUID();
        const inserted = await client.query(
          `INSERT INTO wholesale_products (
             id, wholesaler_id, product_code, name, image_url, unit, category_id, has_variants, stock, created_at, updated_at
           ) VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6, $7, $8, $9, NOW(), NOW())
           RETURNING *`,
          [
            id,
            body.storeId.trim(),
            id,
            body.name.trim(),
            (body.imageUrl ?? '').trim(),
            (body.unit ?? '').trim(),
            body.categoryId?.trim() || null,
            body.hasVariants === true,
            Number(body.stock ?? 0),
          ],
        );
        if (Array.isArray(body.quantityPrices)) {
          for (const rule of body.quantityPrices) {
            await client.query(
              `INSERT INTO wholesale_pricing_rules (id, wholesale_product_id, min_qty, max_qty, price, created_at)
               VALUES ($1::uuid, $2::uuid, $3, $4, $5, NOW())`,
              [randomUUID(), id, Number(rule.minQty ?? 1), rule.maxQty ?? null, Number(rule.price ?? 0)],
            );
          }
        }
        if (body.variants) {
          for (const variant of body.variants) {
            await this.variants.createForWholesaleProduct(id, variant);
          }
        }
        const row = await this.getProductById(id);
        await client.query('COMMIT');
        if (!row) throw new NotFoundException('Created product not found');
        this.logSensitiveAudit('CREATE_PRODUCT', 'wholesale_product', row.id);
        return row;
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      }
    });
  }

  async updateProduct(id: string, body: WholesaleProductWriteDto): Promise<WholesaleProduct> {
    this.actorIdOrThrow();
    return this.withClient(async (client) => {
      const ownedStoreId = await this.assertWholesalerOwnerByProductRef(client, id.trim(), 'update_product');
      if (body.storeId.trim() !== ownedStoreId) {
        this.logAuthorizationViolation(id, 'wholesale_product', 'update_product', 'store_reassignment_forbidden');
        throw new ForbiddenException('Access denied');
      }
      await client.query('BEGIN');
      try {
        if (body.hasVariants === true && (!body.variants || body.variants.length === 0)) {
          const existing = await this.variants.listByWholesaleProduct(id.trim());
          if (existing.items.length === 0) {
            throw new ForbiddenException('Product with hasVariants=true must include variants');
          }
        }
        const q = await client.query(
          `UPDATE wholesale_products
           SET wholesaler_id = $2::uuid,
               name = $3,
               image_url = $4,
               unit = $5,
               category_id = $6,
               stock = $7,
               has_variants = COALESCE($8, has_variants),
               updated_at = NOW()
           WHERE id = $1::uuid
           RETURNING *`,
          [
            id.trim(),
            body.storeId.trim(),
            body.name.trim(),
            (body.imageUrl ?? '').trim(),
            (body.unit ?? '').trim(),
            body.categoryId?.trim() || null,
            Number(body.stock ?? 0),
            body.hasVariants ?? null,
          ],
        );
        if (q.rows.length === 0) throw new NotFoundException('Wholesale product not found');
        await client.query(`DELETE FROM wholesale_pricing_rules WHERE wholesale_product_id = $1::uuid`, [id.trim()]);
        if (Array.isArray(body.quantityPrices)) {
          for (const rule of body.quantityPrices) {
            await client.query(
              `INSERT INTO wholesale_pricing_rules (id, wholesale_product_id, min_qty, max_qty, price, created_at)
               VALUES ($1::uuid, $2::uuid, $3, $4, $5, NOW())`,
              [randomUUID(), id.trim(), Number(rule.minQty ?? 1), rule.maxQty ?? null, Number(rule.price ?? 0)],
            );
          }
        }
        if (body.variants != null) {
          const existing = await this.variants.listByWholesaleProduct(id.trim());
          for (const variant of existing.items) {
            await this.variants.deleteVariant(variant.id);
          }
          for (const variant of body.variants) {
            await this.variants.createForWholesaleProduct(id.trim(), variant);
          }
        }
        const row = await this.getProductById(id.trim());
        await client.query('COMMIT');
        if (!row) throw new NotFoundException('Updated product not found');
        this.logSensitiveAudit('UPDATE_PRODUCT', 'wholesale_product', row.id);
        return row;
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      }
    });
  }

  async deleteProduct(id: string): Promise<{ deleted: true }> {
    const actor = this.actorIdOrThrow();
    return this.withClient(async (client) => {
      if (!this.isPrivilegedRole()) {
        const qOwner = await client.query(
          `SELECT p.id
           FROM wholesale_products p
           JOIN wholesalers w ON w.id = p.wholesaler_id
           WHERE p.id = $1::uuid AND w.owner_id = $2
           LIMIT 1`,
          [id.trim(), actor],
        );
        if (qOwner.rows.length === 0) {
          this.logAuthorizationViolation(id, 'wholesale_product', 'delete', 'owner_mismatch');
          throw new ForbiddenException('Access denied');
        }
      }
      await client.query(`DELETE FROM wholesale_products WHERE id = $1::uuid`, [id.trim()]);
      this.logSensitiveAudit('DELETE_PRODUCT', 'wholesale_product', id.trim());
      return { deleted: true };
    });
  }

  async createCategory(body: WholesaleCategoryWriteDto): Promise<{ id: string; storeId: string; name: string; order: number }> {
    this.actorIdOrThrow();
    return this.withClient(async (client) => {
      await this.assertWholesalerOwnerByStoreRef(client, body.storeId, 'create_category');
      const id = randomUUID();
      const q = await client.query(
        `INSERT INTO store_categories (id, store_id, name, image_url, sort_order, is_ai_generated, created_at, updated_at)
         VALUES ($1::uuid, $2, $3, '', $4, false, NOW(), NOW())
         RETURNING id, store_id, name, sort_order`,
        [id, body.storeId.trim(), body.name.trim(), Number(body.order ?? 0)],
      );
      const row = q.rows[0] as Record<string, unknown>;
      return { id: String(row.id), storeId: String(row.store_id), name: String(row.name), order: Number(row.sort_order ?? 0) };
    });
  }

  async updateCategory(
    id: string,
    body: WholesaleCategoryWriteDto,
  ): Promise<{ id: string; storeId: string; name: string; order: number }> {
    this.actorIdOrThrow();
    return this.withClient(async (client) => {
      await this.assertWholesalerOwnerByStoreRef(client, body.storeId, 'update_category');
      const q = await client.query(
        `UPDATE store_categories
         SET store_id = $2, name = $3, sort_order = $4, updated_at = NOW()
         WHERE id = $1::uuid
         RETURNING id, store_id, name, sort_order`,
        [id.trim(), body.storeId.trim(), body.name.trim(), Number(body.order ?? 0)],
      );
      if (q.rows.length === 0) throw new NotFoundException('Category not found');
      const row = q.rows[0] as Record<string, unknown>;
      return { id: String(row.id), storeId: String(row.store_id), name: String(row.name), order: Number(row.sort_order ?? 0) };
    });
  }

  async deleteCategory(id: string): Promise<{ deleted: true }> {
    const actor = this.actorIdOrThrow();
    return this.withClient(async (client) => {
      if (!this.isPrivilegedRole()) {
        const qOwner = await client.query(
          `SELECT c.id
           FROM store_categories c
           JOIN wholesalers w ON w.id::text = c.store_id
           WHERE c.id = $1::uuid AND w.owner_id = $2
           LIMIT 1`,
          [id.trim(), actor],
        );
        if (qOwner.rows.length === 0) {
          this.logAuthorizationViolation(id, 'wholesale_category', 'delete', 'owner_mismatch');
          throw new ForbiddenException('Access denied');
        }
      }
      await client.query(`DELETE FROM store_categories WHERE id = $1::uuid`, [id.trim()]);
      return { deleted: true };
    });
  }

  async patchStore(id: string, body: WholesaleStorePatchDto): Promise<WholesaleStore> {
    const actor = this.actorIdOrThrow();
    return this.withClient(async (client) => {
      if (!this.isPrivilegedRole()) {
        const owns = await client.query(`SELECT id FROM wholesalers WHERE id = $1::uuid AND owner_id = $2 LIMIT 1`, [
          id.trim(),
          actor,
        ]);
        if (owns.rows.length === 0) {
          this.logAuthorizationViolation(id, 'wholesale_store', 'update', 'owner_mismatch');
          throw new ForbiddenException('Access denied');
        }
      }
      const current = await client.query(
        `SELECT ${this.wholesalerColumns} FROM wholesalers WHERE id = $1::uuid LIMIT 1`,
        [id.trim()],
      );
      if (current.rows.length === 0) throw new NotFoundException('Store not found');
      const now = current.rows[0] as Record<string, unknown>;
      const q = await client.query(
        `UPDATE wholesalers
         SET name = $2,
             logo = $3,
             cover_image = $4,
             description = $5,
             category = $6,
             city = $7,
             phone = $8,
             email = $9,
             status = $10,
             updated_at = NOW()
         WHERE id = $1::uuid
         RETURNING ${this.wholesalerColumns}`,
        [
          id.trim(),
          body.name ?? String(now.name ?? ''),
          body.logo ?? String(now.logo ?? ''),
          body.coverImage ?? String(now.cover_image ?? ''),
          body.description ?? String(now.description ?? ''),
          body.category ?? String(now.category ?? ''),
          body.city ?? String(now.city ?? ''),
          body.phone ?? String(now.phone ?? ''),
          body.email ?? String(now.email ?? ''),
          body.status ?? String(now.status ?? 'approved'),
        ],
      );
      return this.mapStore(q.rows[0] as Record<string, unknown>);
    });
  }

  async listProductVariants(productId: string) {
    return this.withClient(async (client) => {
      await this.assertWholesalerOwnerByProductRef(client, productId.trim(), 'list_product_variants');
      return this.variants.listByWholesaleProduct(productId.trim());
    });
  }

  async createProductVariant(
    productId: string,
    body: {
      sku?: string;
      price: number;
      stock: number;
      isDefault?: boolean;
      options: Array<{ optionType: 'color' | 'size' | 'weight' | 'dimension'; optionValue: string }>;
    },
  ) {
    return this.withClient(async (client) => {
      await this.assertWholesalerOwnerByProductRef(client, productId.trim(), 'create_product_variant');
      return this.variants.createForWholesaleProduct(productId.trim(), body);
    });
  }

  async patchVariant(
    variantId: string,
    body: {
      sku?: string;
      price?: number;
      stock?: number;
      isDefault?: boolean;
      options?: Array<{ optionType: 'color' | 'size' | 'weight' | 'dimension'; optionValue: string }>;
    },
  ) {
    return this.withClient(async (client) => {
      await this.assertWholesalerOwnerByVariantRef(client, variantId.trim(), 'patch_product_variant');
      return this.variants.patchVariant(variantId.trim(), body);
    });
  }

  async deleteVariant(variantId: string) {
    return this.withClient(async (client) => {
      await this.assertWholesalerOwnerByVariantRef(client, variantId.trim(), 'delete_product_variant');
      return this.variants.deleteVariant(variantId.trim());
    });
  }
}
