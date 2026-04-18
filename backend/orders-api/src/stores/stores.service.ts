import { ForbiddenException, Injectable, Logger, NotFoundException, Optional } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Pool } from 'pg';
import { TenantContextService } from '../identity/tenant-context.service';
import { AlgoliaSyncService } from '../search/algolia-sync.service';
import type { StoreRecord } from './stores.types';
import { logAuditJson } from '../common/audit-log';
import { resolvePublicUrl } from '../common/public-url';

@Injectable()
export class StoresService {
  private readonly logger = new Logger(StoresService.name);
  private readonly pool: Pool;
  private schemaReady = false;

  constructor(
    private readonly algoliaSync: AlgoliaSyncService,
    @Optional() private readonly tenant?: TenantContextService,
  ) {
    const connectionString = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
    if (!connectionString) {
      // Fail-lazy: log at boot so operators see the problem in Railway logs,
      // but do NOT throw — throwing here would kill `NestFactory.create` and
      // prevent `/health` from ever responding, causing platform restart loops
      // without surfacing the root cause.
      this.logger.error(
        'DATABASE_URL / ORDERS_DATABASE_URL missing — StoresService DB queries will fail at runtime until env is set.',
      );
    }
    this.pool = new Pool({ connectionString });
  }

  private actor() {
    const snap = this.tenant?.getSnapshot();
    const userId = snap?.uid?.trim() || null;
    const role = snap?.activeRole?.trim() || 'customer';
    const isPrivileged = role === 'admin' || role === 'system_internal';
    return { userId, role, isPrivileged };
  }

  private deny(resourceId: string, action: string, reason: string): never {
    const { userId } = this.actor();
    this.logger.warn(
      JSON.stringify({
        kind: 'authorization_violation',
        userId,
        resourceId,
        resourceType: 'store',
        action,
        reason,
      }),
    );
    throw new ForbiddenException('Access denied');
  }

  private logSensitiveAudit(action: string, entity: string, entityId: string): void {
    const { userId, role } = this.actor();
    logAuditJson('audit', {
      userId: userId ?? 'unknown',
      role,
      action,
      entity,
      entityId,
      timestamp: new Date().toISOString(),
    });
  }

  private mapStore(row: Record<string, unknown>): StoreRecord {
    return {
      id: String(row.id),
      ownerId: String(row.owner_id ?? ''),
      tenantId: row.tenant_id != null ? String(row.tenant_id) : null,
      name: String(row.name ?? ''),
      description: String(row.description ?? ''),
      category: String(row.category ?? ''),
      status: String(row.status ?? 'approved'),
      isFeatured: Boolean(row.is_featured),
      isBoosted: Boolean(row.is_boosted),
      boostExpiresAt: row.boost_expires_at != null ? new Date(String(row.boost_expires_at)).toISOString() : null,
      storeType: String(row.store_type ?? 'retail'),
      hasActivePromotions: Boolean(row.has_active_promotions),
      // In current model, active store offers represent real discounted catalog pricing.
      hasDiscountedProducts: Boolean(row.has_discounted_products),
      freeDelivery: Boolean(row.free_delivery),
      storeTypeId: row.store_type_id != null ? String(row.store_type_id) : null,
      storeTypeKey: row.store_type_key != null ? String(row.store_type_key) : null,
      imageUrl: resolvePublicUrl(row.image_url as string | null | undefined),
      logoUrl: resolvePublicUrl(row.logo_url as string | null | undefined),
      createdAt: new Date(String(row.created_at)).toISOString(),
    };
  }

  private readonly storeColumns =
    `id, owner_id, tenant_id, name, description, category, status,
     is_featured, is_boosted, boost_expires_at, store_type, store_type_id, store_type_key,
     image_url, logo_url, created_at,
     EXISTS (
       SELECT 1
       FROM store_offers so
       WHERE so.store_id = stores.id
         AND (so.valid_until IS NULL OR so.valid_until > NOW())
     ) AS has_active_promotions,
     EXISTS (
       SELECT 1
       FROM store_offers so
       WHERE so.store_id = stores.id
         AND (so.valid_until IS NULL OR so.valid_until > NOW())
     ) AS has_discounted_products,
     (delivery_fee IS NOT NULL AND delivery_fee <= 0) AS free_delivery`;

  private async ensureSchema(): Promise<void> {
    if (this.schemaReady) return;
    await this.pool.query(`
      CREATE TABLE IF NOT EXISTS sub_categories (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        home_section_id UUID REFERENCES home_sections(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        image TEXT,
        sort_order INT DEFAULT 0,
        is_active BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMP DEFAULT NOW()
      );
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT TRUE;
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS is_featured boolean NOT NULL DEFAULT false;
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS is_boosted boolean NOT NULL DEFAULT false;
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS boost_expires_at timestamptz;
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS store_type text NOT NULL DEFAULT 'retail';
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS delivery_fee numeric(12,2);
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS store_type_id uuid;
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS store_type_key text;
      CREATE TABLE IF NOT EXISTS store_boost_requests (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
        boost_type TEXT NOT NULL,
        duration_days INT NOT NULL,
        price NUMERIC(12,2) NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        reviewed_at TIMESTAMPTZ
      );
      CREATE INDEX IF NOT EXISTS idx_store_boost_requests_store_status_created
        ON store_boost_requests (store_id, status, created_at DESC);
      CREATE TABLE IF NOT EXISTS store_types (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name TEXT NOT NULL,
        key TEXT NOT NULL UNIQUE,
        icon TEXT,
        image TEXT,
        display_order INT NOT NULL DEFAULT 0,
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMP NOT NULL DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_store_types_active_order ON store_types (is_active, display_order, created_at);
      CREATE TABLE IF NOT EXISTS system_versions (
        key text PRIMARY KEY,
        version bigint NOT NULL DEFAULT 1,
        updated_at timestamptz NOT NULL DEFAULT now()
      );
      INSERT INTO system_versions (key, version) VALUES ('store_types_version', 1)
      ON CONFLICT (key) DO NOTHING;
      CREATE INDEX IF NOT EXISTS idx_sub_categories_section_active_sort
        ON sub_categories (home_section_id, is_active, sort_order, created_at);
    `);
    this.schemaReady = true;
  }

  async list(limit = 50): Promise<{ items: StoreRecord[] }> {
    await this.ensureSchema();
    await this.clearExpiredBoosts();
    const { userId, isPrivileged, role } = this.actor();
    if (!userId && !isPrivileged) {
      this.deny('list', 'read', 'missing_actor');
    }
    const safeLimit = Math.min(Math.max(1, Number(limit) || 50), 200);
    let q;
    if (isPrivileged) {
      q = await this.pool.query(`SELECT ${this.storeColumns} FROM stores ORDER BY is_boosted DESC, created_at DESC LIMIT $1`, [safeLimit]);
    } else if (role === 'store_owner') {
      q = await this.pool.query(`SELECT ${this.storeColumns} FROM stores WHERE owner_id = $1 ORDER BY is_boosted DESC, created_at DESC LIMIT $2`, [
        userId,
        safeLimit,
      ]);
    } else {
      q = await this.pool.query(
        `SELECT ${this.storeColumns} FROM stores WHERE status = 'approved' ORDER BY is_boosted DESC, created_at DESC LIMIT $1`,
        [safeLimit],
      );
    }
    return { items: q.rows.map((row) => this.mapStore(row as Record<string, unknown>)) };
  }

  /**
   * Public (unauthenticated) store directory used by the mobile home page.
   * Returns all `approved` stores; if the DB is empty / unreachable, falls
   * back to a hard-coded mock list so the UI never renders an empty shell.
   */
  async listPublic(limit = 50): Promise<{ items: StoreRecord[]; source: 'db' | 'mock' }> {
    const safeLimit = Math.min(Math.max(1, Number(limit) || 50), 200);

    // Try DB first. Any failure (schema not migrated, DB down, etc.) is logged
    // and swallowed so we can still return mock data to the client.
    try {
      await this.ensureSchema();
      await this.clearExpiredBoosts();
      const q = await this.pool.query(
        `SELECT ${this.storeColumns} FROM stores WHERE status = 'approved'
         ORDER BY is_boosted DESC, created_at DESC LIMIT $1`,
        [safeLimit],
      );
      const rows = q.rows.map((row) => this.mapStore(row as Record<string, unknown>));
      if (rows.length > 0) return { items: rows, source: 'db' };
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      this.logger.warn(`[StoresPublic] DB query failed, returning mock list: ${msg}`);
    }

    return { items: StoresService.mockStores(), source: 'mock' };
  }

  /**
   * Arabic demo stores used as a graceful fallback whenever the DB has no
   * approved rows yet (e.g. fresh Railway deployment before migration 024 is
   * applied). Safe to ship — ids are deterministic UUIDs prefixed with
   * `00000000-0000-0000-0000-0000000000xx` so they cannot collide with real rows.
   */
  static mockStores(): StoreRecord[] {
    const now = new Date().toISOString();
    const base = {
      tenantId: null,
      status: 'approved',
      isFeatured: false,
      isBoosted: false,
      boostExpiresAt: null,
      hasActivePromotions: false,
      hasDiscountedProducts: false,
      freeDelivery: false,
      createdAt: now,
    } as const;
    return [
      {
        ...base,
        id: '00000000-0000-0000-0000-000000000001',
        ownerId: 'seed_owner_mock_1',
        name: 'متجر الأمل للإلكترونيات',
        description: 'هواتف، إكسسوارات، وأجهزة ذكية بأسعار تنافسية.',
        category: 'إلكترونيات',
        storeType: 'retail',
        storeTypeId: null,
        storeTypeKey: 'retail',
        imageUrl: 'https://picsum.photos/seed/mock-store-1/600/400',
        logoUrl: 'https://picsum.photos/seed/mock-store-1-logo/200/200',
        hasActivePromotions: true,
        hasDiscountedProducts: true,
      },
      {
        ...base,
        id: '00000000-0000-0000-0000-000000000002',
        ownerId: 'seed_owner_mock_2',
        name: 'سوبرماركت النور',
        description: 'خضروات وفواكه طازجة، منتجات منزلية، توصيل سريع.',
        category: 'سوبرماركت',
        storeType: 'retail',
        storeTypeId: null,
        storeTypeKey: 'retail',
        imageUrl: 'https://picsum.photos/seed/mock-store-2/600/400',
        logoUrl: 'https://picsum.photos/seed/mock-store-2-logo/200/200',
        freeDelivery: true,
        isFeatured: true,
      },
      {
        ...base,
        id: '00000000-0000-0000-0000-000000000003',
        ownerId: 'seed_owner_mock_3',
        name: 'أزياء الريم',
        description: 'ملابس نسائية ورجالية، تصاميم حديثة ومتنوعة.',
        category: 'أزياء',
        storeType: 'retail',
        storeTypeId: null,
        storeTypeKey: 'retail',
        imageUrl: 'https://picsum.photos/seed/mock-store-3/600/400',
        logoUrl: 'https://picsum.photos/seed/mock-store-3-logo/200/200',
        hasActivePromotions: true,
      },
      {
        ...base,
        id: '00000000-0000-0000-0000-000000000004',
        ownerId: 'seed_owner_mock_4',
        name: 'مخزن أدوات البيت',
        description: 'كل ما تحتاجه للمنزل من أدوات مطبخ وتنظيف.',
        category: 'أدوات منزلية',
        storeType: 'retail',
        storeTypeId: null,
        storeTypeKey: 'retail',
        imageUrl: 'https://picsum.photos/seed/mock-store-4/600/400',
        logoUrl: 'https://picsum.photos/seed/mock-store-4-logo/200/200',
      },
      {
        ...base,
        id: '00000000-0000-0000-0000-000000000005',
        ownerId: 'seed_owner_mock_5',
        name: 'مطعم الشام',
        description: 'وجبات شامية أصيلة وأطباق شعبية.',
        category: 'مطاعم',
        storeType: 'retail',
        storeTypeId: null,
        storeTypeKey: 'retail',
        imageUrl: 'https://picsum.photos/seed/mock-store-5/600/400',
        logoUrl: 'https://picsum.photos/seed/mock-store-5-logo/200/200',
        freeDelivery: true,
      },
    ];
  }

  async listStoreTypesPublic(): Promise<{ data: Array<Record<string, unknown>>; items: Array<Record<string, unknown>>; version: number }> {
    await this.ensureSchema();
    const q = await this.pool.query(
      `SELECT id::text, name, key, icon, image, display_order AS "displayOrder"
       FROM store_types
       WHERE is_active = TRUE
       ORDER BY display_order ASC, created_at ASC`,
    );
    const vq = await this.pool.query(
      `SELECT version FROM system_versions WHERE key = 'store_types_version' LIMIT 1`,
    );
    const version = Number(vq.rows[0]?.['version'] ?? 1);
    return { data: q.rows as Array<Record<string, unknown>>, items: q.rows as Array<Record<string, unknown>>, version };
  }

  async byId(id: string): Promise<StoreRecord> {
    await this.ensureSchema();
    await this.clearExpiredBoosts();
    const { userId, role, isPrivileged } = this.actor();
    if (!userId && !isPrivileged) {
      this.deny(id, 'read', 'missing_actor');
    }
    let q;
    if (isPrivileged) {
      q = await this.pool.query(`SELECT ${this.storeColumns} FROM stores WHERE id = $1::uuid LIMIT 1`, [id.trim()]);
    } else if (role === 'store_owner') {
      q = await this.pool.query(`SELECT ${this.storeColumns} FROM stores WHERE id = $1::uuid AND owner_id = $2 LIMIT 1`, [id.trim(), userId]);
    } else {
      q = await this.pool.query(`SELECT ${this.storeColumns} FROM stores WHERE id = $1::uuid AND status = 'approved' LIMIT 1`, [id.trim()]);
    }
    if (q.rows.length === 0) throw new NotFoundException('Store not found');
    return this.mapStore(q.rows[0] as Record<string, unknown>);
  }

  async create(input: Partial<StoreRecord> & { ownerId: string; name: string }): Promise<StoreRecord> {
    await this.ensureSchema();
    const { userId, isPrivileged } = this.actor();
    const ownerId = input.ownerId.trim();
    if (!isPrivileged && userId !== ownerId) {
      this.deny(ownerId, 'create', 'owner_id_mismatch');
    }
    const id = input.id?.trim() || randomUUID();
    const inserted = await this.pool.query(
      `INSERT INTO stores (id, owner_id, tenant_id, name, description, category, status, store_type, created_at)
       VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, $8, NOW())
       RETURNING ${this.storeColumns}`,
      [
        id,
        ownerId,
        input.tenantId?.trim() || null,
        input.name.trim(),
        input.description?.trim() || '',
        input.category?.trim() || '',
        input.status?.trim() || 'approved',
        input.storeType?.trim() || 'retail',
      ],
    );
    const created = this.mapStore(inserted.rows[0] as Record<string, unknown>);
    await this.algoliaSync.safeSyncStore({
      id: created.id,
      name: created.name,
      description: created.description,
      category: created.category,
      createdAt: created.createdAt,
    });
    this.logSensitiveAudit('CREATE_STORE', 'store', created.id);
    return created;
  }

  async patch(id: string, input: Partial<StoreRecord>): Promise<StoreRecord> {
    await this.ensureSchema();
    const { userId, isPrivileged } = this.actor();
    const currentQ = await this.pool.query(`SELECT ${this.storeColumns} FROM stores WHERE id = $1::uuid LIMIT 1`, [id.trim()]);
    if (currentQ.rows.length === 0) throw new NotFoundException('Store not found');
    const current = this.mapStore(currentQ.rows[0] as Record<string, unknown>);
    if (!isPrivileged && current.ownerId !== userId) {
      this.deny(id, 'update', 'owner_mismatch');
    }
    const updated = await this.pool.query(
      `UPDATE stores
       SET name = $2, description = $3, category = $4, status = $5, store_type = $8
       WHERE id = $1::uuid AND ($6::boolean = true OR owner_id = $7)
       RETURNING ${this.storeColumns}`,
      [
        id.trim(),
        input.name?.trim() ?? current.name,
        input.description?.trim() ?? current.description,
        input.category?.trim() ?? current.category,
        input.status?.trim() ?? current.status,
        isPrivileged,
        userId ?? '',
        input.storeType?.trim() ?? current.storeType,
      ],
    );
    if (updated.rows.length === 0) {
      this.deny(id, 'update', 'query_scope_denied');
    }
    const patched = this.mapStore(updated.rows[0] as Record<string, unknown>);
    await this.algoliaSync.safeSyncStore({
      id: patched.id,
      name: patched.name,
      description: patched.description,
      category: patched.category,
      createdAt: patched.createdAt,
    });
    this.logSensitiveAudit('UPDATE_STORE', 'store', patched.id);
    return patched;
  }

  async delete(id: string): Promise<{ deleted: true }> {
    await this.ensureSchema();
    const { userId, isPrivileged } = this.actor();
    const currentQ = await this.pool.query(`SELECT owner_id FROM stores WHERE id = $1::uuid LIMIT 1`, [id.trim()]);
    if (currentQ.rows.length === 0) throw new NotFoundException('Store not found');
    const ownerId = String((currentQ.rows[0] as Record<string, unknown>).owner_id ?? '');
    if (!isPrivileged && ownerId !== userId) {
      this.deny(id, 'delete', 'owner_mismatch');
    }
    const q = await this.pool.query(
      `DELETE FROM stores WHERE id = $1::uuid AND ($2::boolean = true OR owner_id = $3)`,
      [id.trim(), isPrivileged, userId ?? ''],
    );
    if ((q.rowCount ?? 0) === 0) {
      this.deny(id, 'delete', 'query_scope_denied');
    }
    await this.algoliaSync.safeDeleteStore(id.trim());
    this.logSensitiveAudit('DELETE_STORE', 'store', id.trim());
    return { deleted: true };
  }

  async bySubCategory(id: string): Promise<{ items: StoreRecord[] }> {
    await this.ensureSchema();
    const q = await this.pool.query(
      `SELECT DISTINCT ${this.storeColumns}
       FROM stores
       INNER JOIN products p ON p.store_id = stores.id
       WHERE p.sub_category_id = $1::uuid
         AND p.is_active = TRUE
       ORDER BY is_boosted DESC, created_at DESC`,
      [id.trim()],
    );
    return { items: q.rows.map((row) => this.mapStore(row as Record<string, unknown>)) };
  }

  private async clearExpiredBoosts(): Promise<void> {
    await this.pool.query(
      `UPDATE stores
       SET is_boosted = FALSE, boost_expires_at = NULL
       WHERE is_boosted = TRUE
         AND boost_expires_at IS NOT NULL
         AND boost_expires_at < NOW()`,
    );
  }

  private resolveBoostPrice(boostType: string, durationDays: number): number {
    const base = (() => {
      if (boostType === 'featured_store') return 3;
      if (boostType === 'top_listing') return 2.5;
      if (boostType === 'banner_ad') return 4;
      return 0;
    })();
    return Math.round(base * durationDays * 100) / 100;
  }

  async createBoostRequest(
    storeId: string,
    body: { boostType: string; durationDays: number },
  ): Promise<{ id: string; price: number; status: string }> {
    await this.ensureSchema();
    const sid = storeId.trim();
    const bt = body.boostType.trim();
    const dd = Number(body.durationDays);
    if (!['featured_store', 'top_listing', 'banner_ad'].includes(bt)) {
      throw new ForbiddenException('invalid_boost_type');
    }
    if (![3, 7, 14].includes(dd)) {
      throw new ForbiddenException('invalid_duration');
    }
    const { userId, isPrivileged } = this.actor();
    if (!isPrivileged) {
      const q = await this.pool.query(`SELECT owner_id FROM stores WHERE id = $1::uuid LIMIT 1`, [sid]);
      if (q.rows.length === 0) throw new NotFoundException('Store not found');
      const owner = String((q.rows[0] as Record<string, unknown>).owner_id ?? '');
      if (owner !== (userId ?? '')) this.deny(sid, 'create_boost_request', 'owner_mismatch');
    }
    const price = this.resolveBoostPrice(bt, dd);
    const ins = await this.pool.query(
      `INSERT INTO store_boost_requests (store_id, boost_type, duration_days, price, status)
       VALUES ($1::uuid, $2, $3, $4, 'pending')
       RETURNING id::text, status`,
      [sid, bt, dd, price],
    );
    const id = String((ins.rows[0] as Record<string, unknown>).id ?? '');
    this.logSensitiveAudit('CREATE_STORE_BOOST_REQUEST', 'store_boost_request', id);
    return { id, price, status: 'pending' };
  }

  async listMyBoostRequests(storeId: string): Promise<{ items: Array<Record<string, unknown>> }> {
    await this.ensureSchema();
    await this.clearExpiredBoosts();
    const sid = storeId.trim();
    const { userId, isPrivileged } = this.actor();
    if (!isPrivileged) {
      const q = await this.pool.query(`SELECT owner_id FROM stores WHERE id = $1::uuid LIMIT 1`, [sid]);
      if (q.rows.length === 0) throw new NotFoundException('Store not found');
      const owner = String((q.rows[0] as Record<string, unknown>).owner_id ?? '');
      if (owner !== (userId ?? '')) this.deny(sid, 'list_boost_requests', 'owner_mismatch');
    }
    const q = await this.pool.query(
      `SELECT id::text, store_id::text AS "storeId", boost_type AS "boostType", duration_days AS "durationDays",
              price, status, created_at AS "createdAt"
       FROM store_boost_requests
       WHERE store_id = $1::uuid
       ORDER BY created_at DESC`,
      [sid],
    );
    return { items: q.rows as Array<Record<string, unknown>> };
  }
}
