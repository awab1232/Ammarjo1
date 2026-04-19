import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';

import { logAuditJson } from '../common/audit-log';
import { HomeService } from '../home/home.service';
import { isValidPersistedRole, normalizeDbRoleToAppRole } from '../identity/db-user-role.util';

function logAdminAction(input: {
  adminUid: string;
  action: string;
  targetId?: string | null;
  targetType?: string | null;
  extra?: Record<string, unknown>;
}): void {
  logAuditJson('admin_action', {
    adminId: input.adminUid,
    action: input.action,
    targetId: input.targetId ?? null,
    targetType: input.targetType ?? null,
    ...input.extra,
  });
}

@Injectable()
export class AdminRestService {
  private readonly pool: Pool | null;
  private auxTablesReady = false;

  constructor() {
    const url = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
    this.pool = url
      ? new Pool({
          connectionString: url,
          max: Number(process.env.ADMIN_REST_PG_POOL_MAX || 8),
          idleTimeoutMillis: 30_000,
        })
      : null;
  }

  private requireDb(): Pool {
    if (!this.pool) throw new ServiceUnavailableException('admin database not configured');
    return this.pool;
  }

  private async withClient<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.requireDb().connect();
    try {
      await this.ensureAuxTables(client);
      return await fn(client);
    } finally {
      client.release();
    }
  }

  private async ensureAuxTables(client: PoolClient): Promise<void> {
    if (this.auxTablesReady) return;
    await client.query(`
      CREATE TABLE IF NOT EXISTS admin_coupons (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        code text NOT NULL UNIQUE,
        name text NOT NULL DEFAULT '',
        payload jsonb NOT NULL DEFAULT '{}'::jsonb,
        status text NOT NULL DEFAULT 'active',
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE INDEX IF NOT EXISTS idx_admin_coupons_status ON admin_coupons (status, updated_at DESC);

      CREATE TABLE IF NOT EXISTS admin_promotions (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        name text NOT NULL DEFAULT '',
        promo_type text NOT NULL DEFAULT 'percentage',
        payload jsonb NOT NULL DEFAULT '{}'::jsonb,
        status text NOT NULL DEFAULT 'active',
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE INDEX IF NOT EXISTS idx_admin_promotions_status ON admin_promotions (status, updated_at DESC);

      CREATE TABLE IF NOT EXISTS admin_tenders (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        title text NOT NULL DEFAULT '',
        status text NOT NULL DEFAULT 'pending',
        payload jsonb NOT NULL DEFAULT '{}'::jsonb,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE INDEX IF NOT EXISTS idx_admin_tenders_status ON admin_tenders (status, updated_at DESC);

      CREATE TABLE IF NOT EXISTS admin_support_tickets (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        subject text NOT NULL DEFAULT '',
        status text NOT NULL DEFAULT 'open',
        payload jsonb NOT NULL DEFAULT '{}'::jsonb,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE INDEX IF NOT EXISTS idx_admin_support_tickets_status ON admin_support_tickets (status, updated_at DESC);

      CREATE TABLE IF NOT EXISTS admin_categories (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        name text NOT NULL DEFAULT '',
        kind text NOT NULL DEFAULT 'general',
        status text NOT NULL DEFAULT 'active',
        payload jsonb NOT NULL DEFAULT '{}'::jsonb,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE INDEX IF NOT EXISTS idx_admin_categories_kind ON admin_categories (kind, updated_at DESC);

      CREATE TABLE IF NOT EXISTS admin_settings (
        id int PRIMARY KEY,
        payload jsonb NOT NULL DEFAULT '{}'::jsonb,
        updated_at timestamptz NOT NULL DEFAULT now()
      );
      INSERT INTO admin_settings (id, payload) VALUES (1, '{}'::jsonb)
      ON CONFLICT (id) DO NOTHING;

      CREATE TABLE IF NOT EXISTS home_sections (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        name text NOT NULL,
        image text,
        type text NOT NULL,
        is_active boolean NOT NULL DEFAULT TRUE,
        sort_order int NOT NULL DEFAULT 0,
        created_at timestamp NOT NULL DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_home_sections_active_sort ON home_sections (is_active, sort_order, created_at);
      CREATE TABLE IF NOT EXISTS store_types (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        name text NOT NULL,
        key text NOT NULL UNIQUE,
        icon text,
        image text,
        display_order int NOT NULL DEFAULT 0,
        is_active boolean NOT NULL DEFAULT TRUE,
        created_at timestamp NOT NULL DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_store_types_active_order ON store_types (is_active, display_order, created_at);
      CREATE TABLE IF NOT EXISTS system_versions (
        key text PRIMARY KEY,
        version bigint NOT NULL DEFAULT 1,
        updated_at timestamptz NOT NULL DEFAULT now()
      );
      INSERT INTO system_versions (key, version) VALUES ('store_types_version', 1)
      ON CONFLICT (key) DO NOTHING;
      INSERT INTO system_versions (key, version) VALUES ('home_sections_version', 1)
      ON CONFLICT (key) DO NOTHING;
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS store_type_id uuid REFERENCES store_types(id) ON DELETE SET NULL;
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS store_type_key text;
      ALTER TABLE home_sections ADD COLUMN IF NOT EXISTS store_type_id uuid REFERENCES store_types(id) ON DELETE CASCADE;
      CREATE INDEX IF NOT EXISTS idx_home_sections_store_type ON home_sections (store_type_id, is_active, sort_order, created_at);
      CREATE TABLE IF NOT EXISTS sub_categories (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        home_section_id uuid REFERENCES home_sections(id) ON DELETE CASCADE,
        name text NOT NULL,
        image text,
        sort_order int DEFAULT 0,
        is_active boolean DEFAULT TRUE,
        created_at timestamp DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_sub_categories_section_active_sort
        ON sub_categories (home_section_id, is_active, sort_order, created_at);

      CREATE TABLE IF NOT EXISTS home_cms (
        id smallint PRIMARY KEY,
        slider jsonb NOT NULL DEFAULT '[]'::jsonb,
        offers jsonb NOT NULL DEFAULT '[]'::jsonb,
        bottom_banner jsonb,
        updated_at timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT home_cms_singleton CHECK (id = 1)
      );
      INSERT INTO home_cms (id) VALUES (1) ON CONFLICT DO NOTHING;
      INSERT INTO system_versions (key, version) VALUES ('home_cms_version', 1)
      ON CONFLICT (key) DO NOTHING;

      ALTER TABLE stores ADD COLUMN IF NOT EXISTS is_featured boolean NOT NULL DEFAULT false;
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS is_boosted boolean NOT NULL DEFAULT false;
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS boost_expires_at timestamptz;
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS store_type text NOT NULL DEFAULT 'retail';
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS phone text NOT NULL DEFAULT '';
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS sell_scope text NOT NULL DEFAULT 'city';
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS city text NOT NULL DEFAULT '';
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS cities text[] NOT NULL DEFAULT '{}'::text[];
      ALTER TABLE products ADD COLUMN IF NOT EXISTS is_boosted boolean NOT NULL DEFAULT false;
      ALTER TABLE products ADD COLUMN IF NOT EXISTS is_trending boolean NOT NULL DEFAULT false;
      CREATE TABLE IF NOT EXISTS store_boost_requests (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        store_id uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
        boost_type text NOT NULL,
        duration_days int NOT NULL,
        price numeric(12,2) NOT NULL,
        status text NOT NULL DEFAULT 'pending',
        created_at timestamptz NOT NULL DEFAULT now(),
        reviewed_at timestamptz
      );
      CREATE INDEX IF NOT EXISTS idx_store_boost_requests_status_created
        ON store_boost_requests (status, created_at DESC);
      CREATE TABLE IF NOT EXISTS technician_join_requests (
        id uuid PRIMARY KEY,
        firebase_uid text,
        email text NOT NULL DEFAULT '',
        display_name text NOT NULL DEFAULT '',
        specialties text[] NOT NULL DEFAULT '{}'::text[],
        category_id text NOT NULL DEFAULT '',
        phone text NOT NULL DEFAULT '',
        city text NOT NULL DEFAULT '',
        cities text[] NOT NULL DEFAULT '{}'::text[],
        status text NOT NULL DEFAULT 'pending',
        rejection_reason text,
        reviewed_by text,
        reviewed_at timestamptz,
        created_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE INDEX IF NOT EXISTS idx_technician_join_requests_status_created
        ON technician_join_requests (status, created_at DESC);
      CREATE TABLE IF NOT EXISTS admin_technicians (
        id text PRIMARY KEY,
        firebase_uid text,
        email text NOT NULL DEFAULT '',
        display_name text NOT NULL DEFAULT '',
        specialties text[] NOT NULL DEFAULT '{}'::text[],
        category text NOT NULL DEFAULT '',
        phone text NOT NULL DEFAULT '',
        city text NOT NULL DEFAULT '',
        cities text[] NOT NULL DEFAULT '{}'::text[],
        status text NOT NULL DEFAULT 'approved',
        approved_at timestamptz,
        updated_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE INDEX IF NOT EXISTS idx_admin_technicians_firebase_uid
        ON admin_technicians (firebase_uid);
    `);
    this.auxTablesReady = true;
  }

  private async logAudit(
    client: PoolClient,
    adminUid: string,
    action: string,
    targetType: string | null,
    targetId: string | null,
    payload?: Record<string, unknown>,
  ): Promise<void> {
    await client.query(
      `INSERT INTO admin_audit_log (admin_firebase_uid, action, target_type, target_id, payload)
       VALUES ($1, $2, $3, $4, $5::jsonb)`,
      [adminUid, action, targetType, targetId, JSON.stringify(payload ?? {})],
    );
  }

  private async getVersion(client: PoolClient, key: string): Promise<number> {
    const q = await client.query(
      `SELECT version FROM system_versions WHERE key = $1 LIMIT 1`,
      [key.trim()],
    );
    return Number(q.rows[0]?.['version'] ?? 1);
  }

  private async bumpVersion(client: PoolClient, key: string): Promise<number> {
    const q = await client.query(
      `INSERT INTO system_versions (key, version, updated_at)
       VALUES ($1, 2, NOW())
       ON CONFLICT (key)
       DO UPDATE SET version = system_versions.version + 1, updated_at = NOW()
       RETURNING version`,
      [key.trim()],
    );
    return Number(q.rows[0]?.['version'] ?? 1);
  }

  async listUsers(
    adminUid: string,
    limit = 50,
    offset = 0,
  ): Promise<{ items: unknown[]; total: number; nextOffset: number | null }> {
    const lim = Math.min(Math.max(1, limit), 100);
    const off = Math.max(0, offset);
    logAdminAction({ adminUid, action: 'list_users' });
    return this.withClient(async (client) => {
      const c = await client.query(`SELECT COUNT(*)::int AS n FROM users`);
      const total = Number(c.rows[0]?.['n'] ?? 0);
      const q = await client.query(
        `SELECT id::text, firebase_uid, email, role, is_active, banned, banned_reason,
                wallet_balance, created_at
         FROM users
         ORDER BY created_at DESC
         LIMIT $1 OFFSET $2`,
        [lim, off],
      );
      const nextOffset = off + lim < total ? off + lim : null;
      return { items: q.rows, total, nextOffset };
    });
  }

  async getUser(adminUid: string, id: string): Promise<Record<string, unknown>> {
    logAdminAction({ adminUid, action: 'get_user', targetId: id, targetType: 'user' });
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id::text, firebase_uid, email, role, is_active, banned, banned_reason,
                wallet_balance, store_id, wholesaler_id, store_type, created_at
         FROM users WHERE id = $1::uuid OR firebase_uid = $1`,
        [id.trim()],
      );
      if (q.rows.length === 0) throw new NotFoundException();
      return q.rows[0] as Record<string, unknown>;
    });
  }

  async patchUser(
    adminUid: string,
    id: string,
    body: {
      role?: string;
      banned?: boolean;
      bannedReason?: string | null;
      walletBalance?: number;
    },
  ): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const sel = await client.query(`SELECT id::text FROM users WHERE id = $1::uuid OR firebase_uid = $1`, [id.trim()]);
      if (sel.rows.length === 0) throw new NotFoundException();
      const uid = String(sel.rows[0]['id']);
      const patches: string[] = [];
      const vals: unknown[] = [];
      let i = 1;
      if (body.role != null && body.role.trim() !== '') {
        const role = normalizeDbRoleToAppRole(body.role.trim());
        if (!isValidPersistedRole(role)) {
          throw new BadRequestException('invalid_role');
        }
        patches.push(`role = $${i++}`);
        vals.push(role);
      }
      if (body.banned != null) {
        patches.push(`banned = $${i++}`);
        vals.push(body.banned);
      }
      if (body.bannedReason !== undefined) {
        patches.push(`banned_reason = $${i++}`);
        vals.push(body.bannedReason);
      }
      if (body.walletBalance != null && Number.isFinite(body.walletBalance)) {
        patches.push(`wallet_balance = $${i++}`);
        vals.push(body.walletBalance);
      }
      if (patches.length === 0) throw new BadRequestException('no_fields');
      vals.push(uid);
      await client.query(`UPDATE users SET ${patches.join(', ')} WHERE id = $${i}::uuid`, vals);
      await this.logAudit(client, adminUid, 'patch_user', 'user', uid, body as Record<string, unknown>);
      logAdminAction({ adminUid, action: 'patch_user', targetId: uid, targetType: 'user', extra: body as Record<string, unknown> });
      return { ok: true as const };
    });
  }

  async deleteUser(adminUid: string, id: string): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const r = await client.query(`DELETE FROM users WHERE id = $1::uuid OR firebase_uid = $1`, [id.trim()]);
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'delete_user', 'user', id, {});
      logAdminAction({ adminUid, action: 'delete_user', targetId: id, targetType: 'user' });
      return { ok: true as const };
    });
  }

  async listStores(
    adminUid: string,
    limit = 50,
    offset = 0,
  ): Promise<{ items: unknown[]; total: number; nextOffset: number | null }> {
    logAdminAction({ adminUid, action: 'list_stores' });
    const lim = Math.min(Math.max(1, limit), 200);
    const off = Math.max(0, offset);
    return this.withClient(async (client) => {
      const c = await client.query(`SELECT COUNT(*)::int AS n FROM stores`);
      const total = Number(c.rows[0]?.['n'] ?? 0);
      await client.query(
        `ALTER TABLE stores ADD COLUMN IF NOT EXISTS commission_percent numeric(12,4) NOT NULL DEFAULT 0`,
      );
      const q = await client.query(
        `SELECT id::text, owner_id, name, category, status, store_type AS "storeType",
                is_featured AS "isFeatured", is_boosted AS "isBoosted", boost_expires_at AS "boostExpiresAt",
                COALESCE(commission_percent, 0)::float AS "commissionPercent",
                created_at
         FROM stores
         ORDER BY created_at DESC LIMIT $1 OFFSET $2`,
        [lim, off],
      );
      const nextOffset = off + lim < total ? off + lim : null;
      return { items: q.rows, total, nextOffset };
    });
  }

  async patchStoreCommissionPercent(
    adminUid: string,
    storeId: string,
    commissionPercent: number,
  ): Promise<{ ok: true }> {
    const pct = Number(commissionPercent);
    if (!Number.isFinite(pct) || pct < 0 || pct > 100) {
      throw new BadRequestException('commission_percent must be between 0 and 100');
    }
    logAdminAction({ adminUid, action: 'patch_store_commission', targetId: storeId, targetType: 'store', extra: { pct } });
    return this.withClient(async (client) => {
      await client.query(
        `ALTER TABLE stores ADD COLUMN IF NOT EXISTS commission_percent numeric(12,4) NOT NULL DEFAULT 0`,
      );
      const r = await client.query(`UPDATE stores SET commission_percent = $2 WHERE id = $1::uuid RETURNING id`, [
        storeId.trim(),
        pct,
      ]);
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'patch_store_commission', 'store', storeId, { commissionPercent: pct });
      return { ok: true as const };
    });
  }

  async getStoreCommissionReport(adminUid: string, storeId: string): Promise<Record<string, unknown>> {
    logAdminAction({ adminUid, action: 'get_store_commission_report', targetId: storeId, targetType: 'store' });
    return this.withClient(async (client) => {
      await client.query(
        `ALTER TABLE stores ADD COLUMN IF NOT EXISTS commission_percent numeric(12,4) NOT NULL DEFAULT 0`,
      );
      await client.query(
        `ALTER TABLE store_commission_orders ADD COLUMN IF NOT EXISTS commission_percent numeric(12,4) NOT NULL DEFAULT 0`,
      );
      const storeRow = await client.query(
        `SELECT COALESCE(commission_percent, 0)::float AS commission_percent FROM stores WHERE id = $1::uuid LIMIT 1`,
        [storeId.trim()],
      );
      if (storeRow.rows.length === 0) throw new NotFoundException();
      const agg = await client.query(
        `SELECT COALESCE(SUM(commission_amount), 0)::numeric AS total_commission, COUNT(*)::int AS order_count
         FROM store_commission_orders WHERE store_id = $1::uuid`,
        [storeId.trim()],
      );
      const a = agg.rows[0] as Record<string, unknown>;
      const s = storeRow.rows[0] as Record<string, unknown>;
      return {
        storeId: storeId.trim(),
        commissionPercent: Number(s.commission_percent ?? 0),
        totalCommission: Number(a.total_commission ?? 0),
        orderCount: Number(a.order_count ?? 0),
      };
    });
  }

  async patchStoreStatus(adminUid: string, storeId: string, status: string): Promise<{ ok: true }> {
    const s = status.trim();
    if (!s) throw new BadRequestException('status');
    return this.withClient(async (client) => {
      const current = await client.query(
        `SELECT owner_id, store_type
         FROM stores
         WHERE id = $1::uuid
         LIMIT 1`,
        [storeId.trim()],
      );
      if (current.rows.length === 0) throw new NotFoundException();
      const row = current.rows[0] as Record<string, unknown>;
      const ownerId = String(row['owner_id'] ?? '').trim();
      const storeType = String(row['store_type'] ?? 'retail').trim().toLowerCase() || 'retail';
      const r = await client.query(`UPDATE stores SET status = $2 WHERE id = $1::uuid`, [storeId.trim(), s]);
      if (r.rowCount === 0) throw new NotFoundException();
      if (s === 'approved' && ownerId.length > 0) {
        await client.query(
          `INSERT INTO users (firebase_uid, email, role, tenant_id, store_id, wholesaler_id, store_type, is_active)
           VALUES ($1, NULL, 'store_owner', $2::uuid, $2, NULL, $3, true)
           ON CONFLICT (firebase_uid) DO UPDATE SET
             role = 'store_owner',
             tenant_id = EXCLUDED.tenant_id,
             store_id = EXCLUDED.store_id,
             wholesaler_id = NULL,
             store_type = EXCLUDED.store_type,
             is_active = true`,
          [ownerId, storeId.trim(), storeType],
        );
      }
      await this.logAudit(client, adminUid, 'patch_store_status', 'store', storeId, { status: s });
      logAdminAction({ adminUid, action: 'patch_store_status', targetId: storeId, targetType: 'store', extra: { status: s } });
      return { ok: true as const };
    });
  }

  async patchStoreFeatures(
    adminUid: string,
    storeId: string,
    body: { isFeatured?: boolean; isBoosted?: boolean; boostExpiresAt?: string | null },
  ): Promise<{ ok: true }> {
    if (body.isFeatured === undefined && body.isBoosted === undefined && body.boostExpiresAt === undefined) {
      throw new BadRequestException('no_fields');
    }
    return this.withClient(async (client) => {
      const patches: string[] = [];
      const vals: unknown[] = [];
      let n = 1;
      if (body.isFeatured !== undefined) {
        patches.push(`is_featured = $${n++}`);
        vals.push(body.isFeatured);
      }
      if (body.isBoosted !== undefined) {
        patches.push(`is_boosted = $${n++}`);
        vals.push(body.isBoosted);
      }
      if (body.boostExpiresAt !== undefined) {
        patches.push(`boost_expires_at = $${n++}::timestamptz`);
        vals.push(body.boostExpiresAt);
      }
      vals.push(storeId.trim());
      const r = await client.query(
        `UPDATE stores SET ${patches.join(', ')} WHERE id = $${n}::uuid`,
        vals,
      );
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'patch_store_features', 'store', storeId, {
        isFeatured: body.isFeatured,
        isBoosted: body.isBoosted,
        boostExpiresAt: body.boostExpiresAt,
      });
      logAdminAction({
        adminUid,
        action: 'patch_store_features',
        targetId: storeId,
        targetType: 'store',
      });
      return { ok: true as const };
    });
  }

  async listBoostRequests(
    adminUid: string,
    status = 'all',
  ): Promise<{ items: unknown[] }> {
    logAdminAction({ adminUid, action: 'list_boost_requests' });
    return this.withClient(async (client) => {
      await client.query(
        `UPDATE stores
         SET is_boosted = FALSE, boost_expires_at = NULL
         WHERE is_boosted = TRUE
           AND boost_expires_at IS NOT NULL
           AND boost_expires_at < NOW()`,
      );
      const st = status.trim().toLowerCase();
      const q =
        st === 'all'
          ? await client.query(
              `SELECT br.id::text, br.store_id::text AS "storeId", s.name AS "storeName", s.store_type AS "storeType",
                      br.boost_type AS "boostType", br.duration_days AS "durationDays", br.price, br.status,
                      br.created_at AS "createdAt"
               FROM store_boost_requests br
               INNER JOIN stores s ON s.id = br.store_id
               ORDER BY br.created_at DESC`,
            )
          : await client.query(
              `SELECT br.id::text, br.store_id::text AS "storeId", s.name AS "storeName", s.store_type AS "storeType",
                      br.boost_type AS "boostType", br.duration_days AS "durationDays", br.price, br.status,
                      br.created_at AS "createdAt"
               FROM store_boost_requests br
               INNER JOIN stores s ON s.id = br.store_id
               WHERE br.status = $1
               ORDER BY br.created_at DESC`,
              [st],
            );
      return { items: q.rows };
    });
  }

  async patchBoostRequestStatus(
    adminUid: string,
    requestId: string,
    status: 'approved' | 'rejected',
  ): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const sel = await client.query(
        `SELECT id::text, store_id::text AS "storeId", duration_days AS "durationDays", status
         FROM store_boost_requests
         WHERE id = $1::uuid
         LIMIT 1`,
        [requestId.trim()],
      );
      if (sel.rows.length === 0) throw new NotFoundException();
      const row = sel.rows[0] as Record<string, unknown>;
      const storeId = String(row['storeId'] ?? '');
      const durationDays = Number(row['durationDays'] ?? 0);
      const currentStatus = String(row['status'] ?? 'pending');
      if (currentStatus !== 'pending') throw new BadRequestException('already_reviewed');

      await client.query(
        `UPDATE store_boost_requests
         SET status = $2, reviewed_at = NOW()
         WHERE id = $1::uuid`,
        [requestId.trim(), status],
      );

      if (status === 'approved') {
        await client.query(
          `UPDATE stores
           SET is_boosted = TRUE,
               boost_expires_at = NOW() + make_interval(days => $2::int)
           WHERE id = $1::uuid`,
          [storeId, durationDays],
        );
      }

      await this.logAudit(client, adminUid, 'patch_boost_request_status', 'store_boost_request', requestId, {
        status,
      });
      logAdminAction({ adminUid, action: 'patch_boost_request_status', targetId: requestId, targetType: 'store_boost_request' });
      return { ok: true as const };
    });
  }

  async patchProductBoost(
    adminUid: string,
    productId: string,
    body: { isBoosted?: boolean; isTrending?: boolean },
  ): Promise<{ ok: true }> {
    const patches: string[] = [];
    const vals: unknown[] = [];
    let n = 1;
    if (body.isBoosted !== undefined) {
      patches.push(`is_boosted = $${n++}`);
      vals.push(body.isBoosted);
    }
    if (body.isTrending !== undefined) {
      patches.push(`is_trending = $${n++}`);
      vals.push(body.isTrending);
    }
    if (patches.length === 0) throw new BadRequestException('no_fields');
    vals.push(productId.trim());
    return this.withClient(async (client) => {
      const r = await client.query(
        `UPDATE products SET ${patches.join(', ')} WHERE id = $${n}::uuid`,
        vals,
      );
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'patch_product_boost', 'product', productId, {
        isBoosted: body.isBoosted,
        isTrending: body.isTrending,
      });
      logAdminAction({
        adminUid,
        action: 'patch_product_boost',
        targetId: productId,
        targetType: 'product',
      });
      return { ok: true as const };
    });
  }

  async listRatings(
    adminUid: string,
    targetType = 'all',
    limit = 50,
    offset = 0,
  ): Promise<{ items: unknown[]; total: number; nextOffset: number | null }> {
    logAdminAction({ adminUid, action: 'list_ratings', extra: { targetType } });
    const lim = Math.min(Math.max(1, limit), 200);
    const off = Math.max(0, offset);
    return this.withClient(async (client) => {
      const tt = targetType.trim().toLowerCase();
      const countQ =
        tt === 'all'
          ? await client.query(`SELECT COUNT(*)::int AS n FROM ratings_reviews`)
          : await client.query(`SELECT COUNT(*)::int AS n FROM ratings_reviews WHERE target_type = $1`, [tt]);
      const total = Number(countQ.rows[0]?.['n'] ?? 0);
      const listQ =
        tt === 'all'
          ? await client.query(
              `SELECT id::text, target_type AS "targetType", target_id AS "targetId", reviewer_id AS "reviewerId",
                      reviewer_name AS "reviewerName", rating, review_text AS "reviewText",
                      delivery_speed AS "deliverySpeed", product_quality AS "productQuality",
                      order_id AS "orderId", created_at AS "createdAt"
               FROM ratings_reviews
               ORDER BY created_at DESC
               LIMIT $1 OFFSET $2`,
              [lim, off],
            )
          : await client.query(
              `SELECT id::text, target_type AS "targetType", target_id AS "targetId", reviewer_id AS "reviewerId",
                      reviewer_name AS "reviewerName", rating, review_text AS "reviewText",
                      delivery_speed AS "deliverySpeed", product_quality AS "productQuality",
                      order_id AS "orderId", created_at AS "createdAt"
               FROM ratings_reviews
               WHERE target_type = $1
               ORDER BY created_at DESC
               LIMIT $2 OFFSET $3`,
              [tt, lim, off],
            );
      const nextOffset = off + lim < total ? off + lim : null;
      return { items: listQ.rows, total, nextOffset };
    });
  }

  async patchRating(
    adminUid: string,
    id: string,
    body: { reviewText?: string },
  ): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      if (body.reviewText === undefined) throw new BadRequestException('no_fields');
      const r = await client.query(
        `UPDATE ratings_reviews
         SET review_text = $2
         WHERE id = $1::uuid`,
        [id.trim(), body.reviewText?.trim() ?? null],
      );
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'patch_rating', 'rating', id, body as Record<string, unknown>);
      return { ok: true as const };
    });
  }

  async deleteRating(adminUid: string, id: string): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const rowQ = await client.query(
        `SELECT target_type, target_id FROM ratings_reviews WHERE id = $1::uuid LIMIT 1`,
        [id.trim()],
      );
      if (rowQ.rows.length === 0) throw new NotFoundException();
      const row = rowQ.rows[0] as Record<string, unknown>;
      const targetType = String(row.target_type ?? '');
      const targetId = String(row.target_id ?? '');
      await client.query(`DELETE FROM ratings_reviews WHERE id = $1::uuid`, [id.trim()]);
      const agg = await client.query(
        `SELECT AVG(rating)::numeric(4,2) AS avg_rating, COUNT(*)::int AS total_reviews
         FROM ratings_reviews
         WHERE target_type = $1 AND target_id = $2`,
        [targetType, targetId],
      );
      const avg = Number(agg.rows[0]?.['avg_rating'] ?? 0);
      const total = Number(agg.rows[0]?.['total_reviews'] ?? 0);
      await client.query(
        `INSERT INTO ratings_aggregates (target_type, target_id, avg_rating, total_reviews, updated_at)
         VALUES ($1, $2, $3, $4, NOW())
         ON CONFLICT (target_type, target_id)
         DO UPDATE SET avg_rating = EXCLUDED.avg_rating, total_reviews = EXCLUDED.total_reviews, updated_at = NOW()`,
        [targetType, targetId, avg, total],
      );
      await this.logAudit(client, adminUid, 'delete_rating', 'rating', id, {});
      return { ok: true as const };
    });
  }

  async listTechnicians(adminUid: string): Promise<{ items: unknown[] }> {
    logAdminAction({ adminUid, action: 'list_technicians' });
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id, email, display_name, specialties, category, phone, city, cities, status, updated_at FROM admin_technicians ORDER BY updated_at DESC`,
      );
      return { items: q.rows };
    });
  }

  async patchTechnicianStatus(adminUid: string, id: string, status: string): Promise<{ ok: true }> {
    const s = status.trim();
    return this.withClient(async (client) => {
      const r = await client.query(
        `UPDATE admin_technicians SET status = $2, updated_at = NOW() WHERE id = $1`,
        [id.trim(), s],
      );
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'patch_technician_status', 'technician', id, { status: s });
      logAdminAction({ adminUid, action: 'patch_technician_status', targetId: id, targetType: 'technician' });
      return { ok: true as const };
    });
  }

  async listReports(adminUid: string): Promise<{ items: unknown[] }> {
    logAdminAction({ adminUid, action: 'list_reports' });
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id::text, reporter_id, subject, body, status, created_at FROM admin_reports ORDER BY created_at DESC LIMIT 200`,
      );
      return { items: q.rows };
    });
  }

  async systemLogs(adminUid: string, limit = 100): Promise<{ items: unknown[] }> {
    logAdminAction({ adminUid, action: 'system_logs' });
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT event_id::text, event_type, entity_id, status, created_at, failed_at
         FROM event_outbox
         ORDER BY created_at DESC
         LIMIT $1`,
        [Math.min(limit, 500)],
      );
      return { items: q.rows };
    });
  }

  async analyticsOverview(adminUid: string): Promise<Record<string, unknown>> {
    logAdminAction({ adminUid, action: 'analytics_overview' });
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT
           (SELECT COUNT(*)::int FROM users) AS users_count,
           (SELECT COUNT(*)::int FROM stores) AS stores_count,
           (SELECT COUNT(*)::int FROM orders) AS orders_count,
           (SELECT COUNT(*)::int FROM service_requests) AS service_requests_count,
           (SELECT COALESCE(SUM(total_numeric),0)::numeric FROM orders) AS orders_revenue`,
      );
      return (q.rows[0] ?? {}) as Record<string, unknown>;
    });
  }

  async analyticsFinance(adminUid: string): Promise<Record<string, unknown>> {
    logAdminAction({ adminUid, action: 'analytics_finance' });
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT
           COALESCE(SUM(total_commission),0)::numeric AS total_commission,
           COALESCE(SUM(total_paid),0)::numeric AS total_paid,
           COALESCE(SUM(balance),0)::numeric AS outstanding_balance
         FROM store_commission_ledger`,
      );
      return (q.rows[0] ?? {}) as Record<string, unknown>;
    });
  }

  async analyticsActivity(adminUid: string): Promise<{ items: unknown[] }> {
    logAdminAction({ adminUid, action: 'analytics_activity' });
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT date_trunc('day', created_at)::date::text AS day, COUNT(*)::int AS orders
         FROM orders
         WHERE created_at >= NOW() - interval '14 days'
         GROUP BY 1
         ORDER BY 1 ASC`,
      );
      return { items: q.rows };
    });
  }

  private safeEmailDocId(email: string): string {
    return email
      .trim()
      .toLowerCase()
      .replace(/[/#\[\]]/g, '_');
  }

  async listOrders(
    adminUid: string,
    limit = 50,
    offset = 0,
  ): Promise<{ items: unknown[]; total: number; nextOffset: number | null }> {
    logAdminAction({ adminUid, action: 'list_orders' });
    const lim = Math.min(Math.max(1, limit), 100);
    const off = Math.max(0, offset);
    return this.withClient(async (client) => {
      const c = await client.query(`SELECT COUNT(*)::int AS n FROM orders`);
      const total = Number(c.rows[0]?.['n'] ?? 0);
      const q = await client.query(
        `SELECT order_id, user_id, store_id, status, total_numeric, currency, created_at, payload
         FROM orders
         ORDER BY created_at DESC
         LIMIT $1 OFFSET $2`,
        [lim, off],
      );
      const nextOffset = off + lim < total ? off + lim : null;
      return { items: q.rows, total, nextOffset };
    });
  }

  async listAuditLogs(
    adminUid: string,
    limit = 50,
    offset = 0,
  ): Promise<{ items: unknown[]; total: number; nextOffset: number | null }> {
    logAdminAction({ adminUid, action: 'list_audit_logs' });
    const lim = Math.min(Math.max(1, limit), 200);
    const off = Math.max(0, offset);
    return this.withClient(async (client) => {
      const c = await client.query(`SELECT COUNT(*)::int AS n FROM admin_audit_log`);
      const total = Number(c.rows[0]?.['n'] ?? 0);
      const q = await client.query(
        `SELECT id, admin_firebase_uid, action, target_type, target_id, payload, created_at
         FROM admin_audit_log
         ORDER BY created_at DESC
         LIMIT $1 OFFSET $2`,
        [lim, off],
      );
      const nextOffset = off + lim < total ? off + lim : null;
      return { items: q.rows, total, nextOffset };
    });
  }

  async getMigrationStatus(_adminUid: string): Promise<{ payload: Record<string, unknown> }> {
    return this.withClient(async (client) => {
      const q = await client.query(`SELECT payload, updated_at FROM admin_migration_status WHERE id = 1 LIMIT 1`);
      if (q.rows.length === 0) return { payload: {} };
      const row = q.rows[0] as Record<string, unknown>;
      const raw = row['payload'];
      const payload =
        raw != null && typeof raw === 'object' && !Array.isArray(raw)
          ? (raw as Record<string, unknown>)
          : {};
      return { payload };
    });
  }

  async patchMigrationStatus(adminUid: string, payload: Record<string, unknown>): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      await client.query(
        `INSERT INTO admin_migration_status (id, payload, updated_at)
         VALUES (1, $1::jsonb, NOW())
         ON CONFLICT (id) DO UPDATE SET payload = EXCLUDED.payload, updated_at = NOW()`,
        [JSON.stringify(payload)],
      );
      await this.logAudit(client, adminUid, 'patch_migration_status', 'migration', '1', payload);
      logAdminAction({ adminUid, action: 'patch_migration_status' });
      return { ok: true as const };
    });
  }

  async listTechnicianJoinRequests(adminUid: string): Promise<{ items: unknown[] }> {
    logAdminAction({ adminUid, action: 'list_technician_join_requests' });
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id::text, email, display_name, specialties, category_id, phone, city, cities, status,
                rejection_reason, reviewed_by, reviewed_at, created_at
         FROM technician_join_requests
         ORDER BY created_at DESC
         LIMIT 500`,
      );
      return { items: q.rows };
    });
  }

  async patchTechnicianJoinRequest(
    adminUid: string,
    id: string,
    body: { status: string; rejectionReason?: string | null; reviewedBy?: string | null },
  ): Promise<{ ok: true }> {
    const st = body.status.trim();
    if (st !== 'approved' && st !== 'rejected' && st !== 'pending') {
      throw new BadRequestException('status');
    }
    return this.withClient(async (client) => {
      const sel = await client.query(
        `SELECT id, firebase_uid, email, display_name, specialties, category_id, phone, city, cities
         FROM technician_join_requests WHERE id = $1::uuid`,
        [id.trim()],
      );
      if (sel.rows.length === 0) throw new NotFoundException();
      const row = sel.rows[0] as Record<string, unknown>;
      const firebaseUid = String(row['firebase_uid'] ?? '').trim();
      const email = String(row['email'] ?? '');
      await client.query(
        `UPDATE technician_join_requests
         SET status = $2,
             rejection_reason = $3,
             reviewed_by = $4,
             reviewed_at = NOW()
         WHERE id = $1::uuid`,
        [
          id.trim(),
          st,
          st === 'rejected' ? (body.rejectionReason ?? '').trim() || null : null,
          (body.reviewedBy ?? adminUid).trim() || null,
        ],
      );
      if (st === 'approved' && email) {
        const tid = this.safeEmailDocId(email);
        await client.query(
          `INSERT INTO admin_technicians (
             id, firebase_uid, email, display_name, specialties, category, phone, city, cities, status, approved_at, updated_at
           ) VALUES (
             $1, $2, $3, $4, $5::text[], $6, $7, $8, $9::text[], 'approved', NOW(), NOW()
           )
           ON CONFLICT (id) DO UPDATE SET
             firebase_uid = EXCLUDED.firebase_uid,
             display_name = EXCLUDED.display_name,
             specialties = EXCLUDED.specialties,
             category = EXCLUDED.category,
             phone = EXCLUDED.phone,
             city = EXCLUDED.city,
             cities = EXCLUDED.cities,
             status = 'approved',
             approved_at = COALESCE(admin_technicians.approved_at, NOW()),
             updated_at = NOW()`,
          [
            tid,
            firebaseUid || null,
            email,
            String(row['display_name'] ?? ''),
            row['specialties'] ?? [],
            String(row['category_id'] ?? ''),
            String(row['phone'] ?? ''),
            String(row['city'] ?? ''),
            row['cities'] ?? [],
          ],
        );
        if (firebaseUid.length > 0) {
          await client.query(
            `INSERT INTO users (firebase_uid, email, role, tenant_id, store_id, wholesaler_id, store_type, is_active)
             VALUES ($1, $2, 'technician', NULL, NULL, NULL, NULL, true)
             ON CONFLICT (firebase_uid) DO UPDATE SET
               email = COALESCE(EXCLUDED.email, users.email),
               role = 'technician',
               store_id = NULL,
               wholesaler_id = NULL,
               store_type = NULL,
               is_active = true`,
            [firebaseUid, email || null],
          );
        } else {
          await client.query(
            `UPDATE users
             SET role = 'technician',
                 store_id = NULL,
                 wholesaler_id = NULL,
                 store_type = NULL,
                 is_active = true
             WHERE lower(trim(coalesce(email, ''))) = $1`,
            [email.trim().toLowerCase()],
          );
        }
      }
      await this.logAudit(client, adminUid, 'patch_technician_join_request', 'technician_join_request', id, {
        status: st,
      });
      logAdminAction({ adminUid, action: 'patch_technician_join_request', targetId: id });
      return { ok: true as const };
    });
  }

  async patchTechnicianProfile(
    adminUid: string,
    id: string,
    body: {
      displayName?: string;
      email?: string;
      phone?: string;
      city?: string;
      category?: string;
      specialties?: string[];
      cities?: string[];
      status?: string;
    },
  ): Promise<{ ok: true }> {
    const patches: string[] = [];
    const vals: unknown[] = [];
    let n = 1;
    if (body.displayName !== undefined) {
      patches.push(`display_name = $${n++}`);
      vals.push(body.displayName);
    }
    if (body.email !== undefined) {
      patches.push(`email = $${n++}`);
      vals.push(body.email);
    }
    if (body.phone !== undefined) {
      patches.push(`phone = $${n++}`);
      vals.push(body.phone);
    }
    if (body.city !== undefined) {
      patches.push(`city = $${n++}`);
      vals.push(body.city);
    }
    if (body.category !== undefined) {
      patches.push(`category = $${n++}`);
      vals.push(body.category);
    }
    if (body.specialties !== undefined) {
      patches.push(`specialties = $${n++}::text[]`);
      vals.push(body.specialties);
    }
    if (body.cities !== undefined) {
      patches.push(`cities = $${n++}::text[]`);
      vals.push(body.cities);
    }
    if (body.status !== undefined) {
      patches.push(`status = $${n++}`);
      vals.push(body.status);
    }
    if (patches.length === 0) throw new BadRequestException('no_fields');
    patches.push(`updated_at = NOW()`);
    vals.push(id.trim());
    return this.withClient(async (client) => {
      const r = await client.query(
        `UPDATE admin_technicians SET ${patches.join(', ')} WHERE id = $${n}`,
        vals,
      );
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'patch_technician_profile', 'technician', id, body as Record<string, unknown>);
      logAdminAction({ adminUid, action: 'patch_technician_profile', targetId: id });
      return { ok: true as const };
    });
  }

  async patchReport(
    adminUid: string,
    id: string,
    body: { status?: string; subject?: string; bodyText?: string },
  ): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const patches: string[] = [];
      const vals: unknown[] = [];
      let n = 1;
      if (body.status != null && body.status.trim() !== '') {
        patches.push(`status = $${n++}`);
        vals.push(body.status.trim());
      }
      if (body.subject !== undefined) {
        patches.push(`subject = $${n++}`);
        vals.push(body.subject);
      }
      if (body.bodyText !== undefined) {
        patches.push(`body = $${n++}`);
        vals.push(body.bodyText);
      }
      if (patches.length === 0) throw new BadRequestException('no_fields');
      patches.push(`updated_at = NOW()`);
      vals.push(id.trim());
      const r = await client.query(
        `UPDATE admin_reports SET ${patches.join(', ')} WHERE id = $${n}::uuid`,
        vals,
      );
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'patch_report', 'report', id, body as Record<string, unknown>);
      logAdminAction({ adminUid, action: 'patch_report', targetId: id });
      return { ok: true as const };
    });
  }

  async listCoupons(
    adminUid: string,
    limit = 50,
    offset = 0,
  ): Promise<{ items: unknown[]; total: number; nextOffset: number | null }> {
    logAdminAction({ adminUid, action: 'list_coupons' });
    const lim = Math.min(Math.max(1, limit), 200);
    const off = Math.max(0, offset);
    return this.withClient(async (client) => {
      const c = await client.query(`SELECT COUNT(*)::int AS n FROM admin_coupons`);
      const total = Number(c.rows[0]?.['n'] ?? 0);
      const q = await client.query(
        `SELECT id::text, code, name, status, payload, created_at, updated_at
         FROM admin_coupons
         ORDER BY updated_at DESC
         LIMIT $1 OFFSET $2`,
        [lim, off],
      );
      const nextOffset = off + lim < total ? off + lim : null;
      return { items: q.rows, total, nextOffset };
    });
  }

  /** Public/safe catalog: active coupons only, no payload secrets. */
  async listCouponsSanitized(
    limit = 50,
    offset = 0,
  ): Promise<{ items: unknown[]; total: number; nextOffset: number | null }> {
    const lim = Math.min(Math.max(1, limit), 200);
    const off = Math.max(0, offset);
    return this.withClient(async (client) => {
      const c = await client.query(
        `SELECT COUNT(*)::int AS n FROM admin_coupons WHERE lower(trim(status)) = 'active'`,
      );
      const total = Number(c.rows[0]?.['n'] ?? 0);
      const q = await client.query(
        `SELECT id::text, code, name, status, created_at, updated_at
         FROM admin_coupons
         WHERE lower(trim(status)) = 'active'
         ORDER BY updated_at DESC
         LIMIT $1 OFFSET $2`,
        [lim, off],
      );
      const nextOffset = off + lim < total ? off + lim : null;
      return { items: q.rows, total, nextOffset };
    });
  }

  async createCoupon(
    adminUid: string,
    body: { code: string; name?: string; status?: string; payload?: Record<string, unknown> },
  ): Promise<{ ok: true; id: string }> {
    const code = body.code.trim().toUpperCase();
    if (!code) throw new BadRequestException('code');
    return this.withClient(async (client) => {
      const r = await client.query(
        `INSERT INTO admin_coupons (code, name, status, payload)
         VALUES ($1, $2, $3, $4::jsonb)
         RETURNING id::text`,
        [code, (body.name ?? '').trim(), (body.status ?? 'active').trim() || 'active', JSON.stringify(body.payload ?? {})],
      );
      const id = String(r.rows[0]?.['id'] ?? '');
      await this.logAudit(client, adminUid, 'create_coupon', 'coupon', id, body as Record<string, unknown>);
      logAdminAction({ adminUid, action: 'create_coupon', targetId: id, targetType: 'coupon' });
      return { ok: true as const, id };
    });
  }

  async patchCoupon(
    adminUid: string,
    id: string,
    body: { code?: string; name?: string; status?: string; payload?: Record<string, unknown> },
  ): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const patches: string[] = [];
      const vals: unknown[] = [];
      let n = 1;
      if (body.code !== undefined) {
        patches.push(`code = $${n++}`);
        vals.push(body.code.trim().toUpperCase());
      }
      if (body.name !== undefined) {
        patches.push(`name = $${n++}`);
        vals.push(body.name.trim());
      }
      if (body.status !== undefined) {
        patches.push(`status = $${n++}`);
        vals.push(body.status.trim());
      }
      if (body.payload !== undefined) {
        patches.push(`payload = $${n++}::jsonb`);
        vals.push(JSON.stringify(body.payload));
      }
      if (patches.length === 0) throw new BadRequestException('no_fields');
      patches.push(`updated_at = NOW()`);
      vals.push(id.trim());
      const r = await client.query(`UPDATE admin_coupons SET ${patches.join(', ')} WHERE id = $${n}::uuid`, vals);
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'patch_coupon', 'coupon', id, body as Record<string, unknown>);
      logAdminAction({ adminUid, action: 'patch_coupon', targetId: id, targetType: 'coupon' });
      return { ok: true as const };
    });
  }

  async deleteCoupon(adminUid: string, id: string): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const r = await client.query(`DELETE FROM admin_coupons WHERE id = $1::uuid`, [id.trim()]);
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'delete_coupon', 'coupon', id, {});
      logAdminAction({ adminUid, action: 'delete_coupon', targetId: id, targetType: 'coupon' });
      return { ok: true as const };
    });
  }

  async listPromotions(
    adminUid: string,
    limit = 50,
    offset = 0,
  ): Promise<{ items: unknown[]; total: number; nextOffset: number | null }> {
    logAdminAction({ adminUid, action: 'list_promotions' });
    const lim = Math.min(Math.max(1, limit), 200);
    const off = Math.max(0, offset);
    return this.withClient(async (client) => {
      const c = await client.query(`SELECT COUNT(*)::int AS n FROM admin_promotions`);
      const total = Number(c.rows[0]?.['n'] ?? 0);
      const q = await client.query(
        `SELECT id::text, name, promo_type, status, payload, created_at, updated_at
         FROM admin_promotions
         ORDER BY updated_at DESC
         LIMIT $1 OFFSET $2`,
        [lim, off],
      );
      const nextOffset = off + lim < total ? off + lim : null;
      return { items: q.rows, total, nextOffset };
    });
  }

  /** Public/safe catalog: active promotions only, no payload column. */
  async listPromotionsSanitized(
    limit = 50,
    offset = 0,
  ): Promise<{ items: unknown[]; total: number; nextOffset: number | null }> {
    const lim = Math.min(Math.max(1, limit), 200);
    const off = Math.max(0, offset);
    return this.withClient(async (client) => {
      const c = await client.query(
        `SELECT COUNT(*)::int AS n FROM admin_promotions WHERE lower(trim(status)) = 'active'`,
      );
      const total = Number(c.rows[0]?.['n'] ?? 0);
      const q = await client.query(
        `SELECT id::text, name, promo_type, status, created_at, updated_at
         FROM admin_promotions
         WHERE lower(trim(status)) = 'active'
         ORDER BY updated_at DESC
         LIMIT $1 OFFSET $2`,
        [lim, off],
      );
      const nextOffset = off + lim < total ? off + lim : null;
      return { items: q.rows, total, nextOffset };
    });
  }

  async createPromotion(
    adminUid: string,
    body: { name: string; promoType?: string; status?: string; payload?: Record<string, unknown> },
  ): Promise<{ ok: true; id: string }> {
    const name = body.name.trim();
    if (!name) throw new BadRequestException('name');
    return this.withClient(async (client) => {
      const r = await client.query(
        `INSERT INTO admin_promotions (name, promo_type, status, payload)
         VALUES ($1, $2, $3, $4::jsonb)
         RETURNING id::text`,
        [
          name,
          (body.promoType ?? 'percentage').trim() || 'percentage',
          (body.status ?? 'active').trim() || 'active',
          JSON.stringify(body.payload ?? {}),
        ],
      );
      const id = String(r.rows[0]?.['id'] ?? '');
      await this.logAudit(client, adminUid, 'create_promotion', 'promotion', id, body as Record<string, unknown>);
      logAdminAction({ adminUid, action: 'create_promotion', targetId: id, targetType: 'promotion' });
      return { ok: true as const, id };
    });
  }

  async patchPromotion(
    adminUid: string,
    id: string,
    body: { name?: string; promoType?: string; status?: string; payload?: Record<string, unknown> },
  ): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const patches: string[] = [];
      const vals: unknown[] = [];
      let n = 1;
      if (body.name !== undefined) {
        patches.push(`name = $${n++}`);
        vals.push(body.name.trim());
      }
      if (body.promoType !== undefined) {
        patches.push(`promo_type = $${n++}`);
        vals.push(body.promoType.trim());
      }
      if (body.status !== undefined) {
        patches.push(`status = $${n++}`);
        vals.push(body.status.trim());
      }
      if (body.payload !== undefined) {
        patches.push(`payload = $${n++}::jsonb`);
        vals.push(JSON.stringify(body.payload));
      }
      if (patches.length === 0) throw new BadRequestException('no_fields');
      patches.push(`updated_at = NOW()`);
      vals.push(id.trim());
      const r = await client.query(`UPDATE admin_promotions SET ${patches.join(', ')} WHERE id = $${n}::uuid`, vals);
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'patch_promotion', 'promotion', id, body as Record<string, unknown>);
      logAdminAction({ adminUid, action: 'patch_promotion', targetId: id, targetType: 'promotion' });
      return { ok: true as const };
    });
  }

  async deletePromotion(adminUid: string, id: string): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const r = await client.query(`DELETE FROM admin_promotions WHERE id = $1::uuid`, [id.trim()]);
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'delete_promotion', 'promotion', id, {});
      logAdminAction({ adminUid, action: 'delete_promotion', targetId: id, targetType: 'promotion' });
      return { ok: true as const };
    });
  }

  async getHomeCms(adminUid: string): Promise<Record<string, unknown>> {
    logAdminAction({ adminUid, action: 'get_home_cms' });
    return this.withClient(async (client) => {
      const rowQ = await client.query(`SELECT slider, offers, bottom_banner FROM home_cms WHERE id = 1 LIMIT 1`);
      const version = await this.getVersion(client, 'home_cms_version');
      const row = rowQ.rows[0] as Record<string, unknown> | undefined;
      if (!row) {
        return { ...HomeService.defaultCmsPayload(), version } as unknown as Record<string, unknown>;
      }
      const merged = HomeService.mergeCmsFromDb(row['slider'], row['offers'], row['bottom_banner'], version);
      return merged as unknown as Record<string, unknown>;
    });
  }

  async patchHomeCms(
    adminUid: string,
    body: {
      primarySlider?: unknown;
      offers?: unknown;
      bottomBanner?: unknown;
    },
  ): Promise<{ ok: true; version: number }> {
    return this.withClient(async (client) => {
      const rowQ = await client.query(`SELECT slider, offers, bottom_banner FROM home_cms WHERE id = 1 LIMIT 1`);
      const cur = (rowQ.rows[0] ?? {}) as Record<string, unknown>;
      const nextSlider = body.primarySlider !== undefined ? body.primarySlider : cur['slider'];
      const nextOffers = body.offers !== undefined ? body.offers : cur['offers'];
      const nextBottom = body.bottomBanner !== undefined ? body.bottomBanner : cur['bottom_banner'];
      await client.query(
        `UPDATE home_cms SET
           slider = $1::jsonb,
           offers = $2::jsonb,
           bottom_banner = $3::jsonb,
           updated_at = now()
         WHERE id = 1`,
        [JSON.stringify(nextSlider ?? []), JSON.stringify(nextOffers ?? []), nextBottom == null ? null : JSON.stringify(nextBottom)],
      );
      const version = await this.bumpVersion(client, 'home_cms_version');
      await this.logAudit(client, adminUid, 'patch_home_cms', 'home_cms', '1', body as Record<string, unknown>);
      logAdminAction({ adminUid, action: 'patch_home_cms', targetId: '1', targetType: 'home_cms' });
      return { ok: true as const, version };
    });
  }

  async listHomeSections(adminUid: string): Promise<{ data: unknown[]; items: unknown[]; version: number }> {
    logAdminAction({ adminUid, action: 'list_home_sections' });
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id::text, name, image, type, store_type_id::text AS "storeTypeId",
                is_active AS "isActive", sort_order AS "sortOrder", created_at AS "createdAt"
         FROM home_sections
         ORDER BY sort_order ASC, created_at ASC`,
      );
      const version = await this.getVersion(client, 'home_sections_version');
      return { data: q.rows, items: q.rows, version };
    });
  }

  async createHomeSection(
    adminUid: string,
    body: {
      name: string;
      image?: string | null;
      type: string;
      storeTypeId?: string | null;
      isActive?: boolean;
      sortOrder?: number;
    },
  ): Promise<{ ok: true; id: string }> {
    const name = body.name.trim();
    const type = body.type.trim();
    if (!name) throw new BadRequestException('name');
    if (!type) throw new BadRequestException('type');
    return this.withClient(async (client) => {
      const r = await client.query(
        `INSERT INTO home_sections (name, image, type, store_type_id, is_active, sort_order)
         VALUES ($1, $2, $3, $4::uuid, $5, $6)
         RETURNING id::text`,
        [
          name,
          body.image ?? null,
          type,
          (body as Record<string, unknown>)['storeTypeId'] != null
              ? String((body as Record<string, unknown>)['storeTypeId'] ?? '').trim()
              : null,
          body.isActive ?? true,
          Number.isFinite(body.sortOrder) ? body.sortOrder : 0,
        ],
      );
      const id = String(r.rows[0]?.['id'] ?? '');
      await this.logAudit(client, adminUid, 'create_home_section', 'home_section', id, {
        name,
        type,
      });
      await this.bumpVersion(client, 'home_sections_version');
      logAdminAction({ adminUid, action: 'create_home_section', targetId: id, targetType: 'home_section' });
      return { ok: true as const, id };
    });
  }

  async patchHomeSection(
    adminUid: string,
    id: string,
    body: {
      name?: string;
      image?: string | null;
      type?: string;
      storeTypeId?: string | null;
      isActive?: boolean;
      sortOrder?: number;
    },
  ): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const patches: string[] = [];
      const vals: unknown[] = [];
      let n = 1;
      if (body.name !== undefined) {
        patches.push(`name = $${n++}`);
        vals.push(body.name.trim());
      }
      if (body.image !== undefined) {
        patches.push(`image = $${n++}`);
        vals.push(body.image);
      }
      if (body.type !== undefined) {
        patches.push(`type = $${n++}`);
        vals.push(body.type.trim());
      }
      if ((body as Record<string, unknown>)['storeTypeId'] !== undefined) {
        patches.push(`store_type_id = $${n++}::uuid`);
        const raw = String((body as Record<string, unknown>)['storeTypeId'] ?? '').trim();
        vals.push(raw.length === 0 ? null : raw);
      }
      if (body.isActive !== undefined) {
        patches.push(`is_active = $${n++}`);
        vals.push(body.isActive);
      }
      if (body.sortOrder !== undefined && Number.isFinite(body.sortOrder)) {
        patches.push(`sort_order = $${n++}`);
        vals.push(body.sortOrder);
      }
      if (patches.length === 0) throw new BadRequestException('no_fields');
      vals.push(id.trim());
      const r = await client.query(`UPDATE home_sections SET ${patches.join(', ')} WHERE id = $${n}::uuid`, vals);
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'patch_home_section', 'home_section', id, body as Record<string, unknown>);
      await this.bumpVersion(client, 'home_sections_version');
      logAdminAction({ adminUid, action: 'patch_home_section', targetId: id, targetType: 'home_section' });
      return { ok: true as const };
    });
  }

  async deleteHomeSection(adminUid: string, id: string): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const r = await client.query(`DELETE FROM home_sections WHERE id = $1::uuid`, [id.trim()]);
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'delete_home_section', 'home_section', id, {});
      await this.bumpVersion(client, 'home_sections_version');
      logAdminAction({ adminUid, action: 'delete_home_section', targetId: id, targetType: 'home_section' });
      return { ok: true as const };
    });
  }

  async listSubCategories(
    adminUid: string,
    sectionId: string,
  ): Promise<{ data: unknown[]; items: unknown[]; version: number }> {
    const sid = sectionId.trim();
    if (!sid) throw new BadRequestException('sectionId');
    logAdminAction({ adminUid, action: 'list_sub_categories', targetId: sid, targetType: 'home_section' });
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id::text, home_section_id::text AS "home_section_id", name, image,
                sort_order AS "sortOrder", is_active AS "isActive", created_at AS "createdAt"
         FROM sub_categories
         WHERE home_section_id = $1::uuid
         ORDER BY sort_order ASC, created_at ASC`,
        [sid],
      );
      const version = await this.getVersion(client, 'home_sections_version');
      return { data: q.rows, items: q.rows, version };
    });
  }

  async listStoreTypes(adminUid: string): Promise<{ data: unknown[]; items: unknown[]; version: number }> {
    logAdminAction({ adminUid, action: 'list_store_types' });
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id::text, name, key, icon, image, display_order AS "displayOrder",
                is_active AS "isActive", created_at AS "createdAt"
         FROM store_types
         ORDER BY display_order ASC, created_at ASC`,
      );
      const version = await this.getVersion(client, 'store_types_version');
      return { data: q.rows, items: q.rows, version };
    });
  }

  async createStoreType(
    adminUid: string,
    body: {
      name: string;
      key: string;
      icon?: string | null;
      image?: string | null;
      displayOrder?: number;
      isActive?: boolean;
    },
  ): Promise<{ ok: true; id: string }> {
    const name = body.name.trim();
    const key = body.key.trim().toLowerCase();
    if (!name) throw new BadRequestException('name');
    if (!key) throw new BadRequestException('key');
    return this.withClient(async (client) => {
      const r = await client.query(
        `INSERT INTO store_types (name, key, icon, image, display_order, is_active)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id::text`,
        [
          name,
          key,
          body.icon ?? null,
          body.image ?? null,
          Number.isFinite(body.displayOrder) ? body.displayOrder : 0,
          body.isActive ?? true,
        ],
      );
      const id = String(r.rows[0]?.['id'] ?? '');
      await this.logAudit(client, adminUid, 'create_store_type', 'store_type', id, body as Record<string, unknown>);
      await this.bumpVersion(client, 'store_types_version');
      return { ok: true as const, id };
    });
  }

  async patchStoreType(
    adminUid: string,
    id: string,
    body: {
      name?: string;
      key?: string;
      icon?: string | null;
      image?: string | null;
      displayOrder?: number;
      isActive?: boolean;
    },
  ): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const patches: string[] = [];
      const vals: unknown[] = [];
      let n = 1;
      if (body.name !== undefined) {
        patches.push(`name = $${n++}`);
        vals.push(body.name.trim());
      }
      if (body.key !== undefined) {
        patches.push(`key = $${n++}`);
        vals.push(body.key.trim().toLowerCase());
      }
      if (body.icon !== undefined) {
        patches.push(`icon = $${n++}`);
        vals.push(body.icon);
      }
      if (body.image !== undefined) {
        patches.push(`image = $${n++}`);
        vals.push(body.image);
      }
      if (body.displayOrder !== undefined && Number.isFinite(body.displayOrder)) {
        patches.push(`display_order = $${n++}`);
        vals.push(body.displayOrder);
      }
      if (body.isActive !== undefined) {
        patches.push(`is_active = $${n++}`);
        vals.push(body.isActive);
      }
      if (patches.length === 0) throw new BadRequestException('no_fields');
      vals.push(id.trim());
      const r = await client.query(`UPDATE store_types SET ${patches.join(', ')} WHERE id = $${n}::uuid`, vals);
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'patch_store_type', 'store_type', id, body as Record<string, unknown>);
      await this.bumpVersion(client, 'store_types_version');
      return { ok: true as const };
    });
  }

  async deleteStoreType(adminUid: string, id: string): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const r = await client.query(`DELETE FROM store_types WHERE id = $1::uuid`, [id.trim()]);
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'delete_store_type', 'store_type', id, {});
      await this.bumpVersion(client, 'store_types_version');
      return { ok: true as const };
    });
  }

  async createSubCategory(
    adminUid: string,
    body: {
      homeSectionId: string;
      name: string;
      image?: string | null;
      sortOrder?: number;
      isActive?: boolean;
    },
  ): Promise<{ ok: true; id: string }> {
    const homeSectionId = body.homeSectionId.trim();
    const name = body.name.trim();
    if (!homeSectionId) throw new BadRequestException('homeSectionId');
    if (!name) throw new BadRequestException('name');
    return this.withClient(async (client) => {
      const r = await client.query(
        `INSERT INTO sub_categories (home_section_id, name, image, sort_order, is_active)
         VALUES ($1::uuid, $2, $3, $4, $5)
         RETURNING id::text`,
        [
          homeSectionId,
          name,
          body.image ?? null,
          Number.isFinite(body.sortOrder) ? body.sortOrder : 0,
          body.isActive ?? true,
        ],
      );
      const id = String(r.rows[0]?.['id'] ?? '');
      await this.logAudit(client, adminUid, 'create_sub_category', 'sub_category', id, body as Record<string, unknown>);
      await this.bumpVersion(client, 'home_sections_version');
      logAdminAction({ adminUid, action: 'create_sub_category', targetId: id, targetType: 'sub_category' });
      return { ok: true as const, id };
    });
  }

  async patchSubCategory(
    adminUid: string,
    id: string,
    body: {
      name?: string;
      image?: string | null;
      sortOrder?: number;
      isActive?: boolean;
      homeSectionId?: string;
    },
  ): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const patches: string[] = [];
      const vals: unknown[] = [];
      let n = 1;
      if (body.name !== undefined) {
        patches.push(`name = $${n++}`);
        vals.push(body.name.trim());
      }
      if (body.image !== undefined) {
        patches.push(`image = $${n++}`);
        vals.push(body.image);
      }
      if (body.sortOrder !== undefined && Number.isFinite(body.sortOrder)) {
        patches.push(`sort_order = $${n++}`);
        vals.push(body.sortOrder);
      }
      if (body.isActive !== undefined) {
        patches.push(`is_active = $${n++}`);
        vals.push(body.isActive);
      }
      if (body.homeSectionId !== undefined) {
        patches.push(`home_section_id = $${n++}::uuid`);
        vals.push(body.homeSectionId.trim());
      }
      if (patches.length === 0) throw new BadRequestException('no_fields');
      vals.push(id.trim());
      const r = await client.query(`UPDATE sub_categories SET ${patches.join(', ')} WHERE id = $${n}::uuid`, vals);
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'patch_sub_category', 'sub_category', id, body as Record<string, unknown>);
      await this.bumpVersion(client, 'home_sections_version');
      logAdminAction({ adminUid, action: 'patch_sub_category', targetId: id, targetType: 'sub_category' });
      return { ok: true as const };
    });
  }

  async deleteSubCategory(adminUid: string, id: string): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const r = await client.query(`DELETE FROM sub_categories WHERE id = $1::uuid`, [id.trim()]);
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'delete_sub_category', 'sub_category', id, {});
      await this.bumpVersion(client, 'home_sections_version');
      logAdminAction({ adminUid, action: 'delete_sub_category', targetId: id, targetType: 'sub_category' });
      return { ok: true as const };
    });
  }

  async listTenders(adminUid: string): Promise<{ items: unknown[] }> {
    logAdminAction({ adminUid, action: 'list_tenders' });
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id::text, title, status, payload, created_at, updated_at
         FROM admin_tenders
         ORDER BY updated_at DESC
         LIMIT 500`,
      );
      return { items: q.rows };
    });
  }

  async patchTender(
    adminUid: string,
    id: string,
    body: { status?: string; title?: string; payload?: Record<string, unknown> },
  ): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const patches: string[] = [];
      const vals: unknown[] = [];
      let n = 1;
      if (body.status !== undefined) {
        patches.push(`status = $${n++}`);
        vals.push(body.status.trim());
      }
      if (body.title !== undefined) {
        patches.push(`title = $${n++}`);
        vals.push(body.title.trim());
      }
      if (body.payload !== undefined) {
        patches.push(`payload = $${n++}::jsonb`);
        vals.push(JSON.stringify(body.payload));
      }
      if (patches.length === 0) throw new BadRequestException('no_fields');
      patches.push(`updated_at = NOW()`);
      vals.push(id.trim());
      const r = await client.query(`UPDATE admin_tenders SET ${patches.join(', ')} WHERE id = $${n}::uuid`, vals);
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'patch_tender', 'tender', id, body as Record<string, unknown>);
      logAdminAction({ adminUid, action: 'patch_tender', targetId: id, targetType: 'tender' });
      return { ok: true as const };
    });
  }

  async listSupportTickets(adminUid: string): Promise<{ items: unknown[] }> {
    logAdminAction({ adminUid, action: 'list_support_tickets' });
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id::text, subject, status, payload, created_at, updated_at
         FROM admin_support_tickets
         ORDER BY updated_at DESC
         LIMIT 500`,
      );
      return { items: q.rows };
    });
  }

  async patchSupportTicket(
    adminUid: string,
    id: string,
    body: { status?: string; subject?: string; payload?: Record<string, unknown> },
  ): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const patches: string[] = [];
      const vals: unknown[] = [];
      let n = 1;
      if (body.status !== undefined) {
        patches.push(`status = $${n++}`);
        vals.push(body.status.trim());
      }
      if (body.subject !== undefined) {
        patches.push(`subject = $${n++}`);
        vals.push(body.subject.trim());
      }
      if (body.payload !== undefined) {
        patches.push(`payload = $${n++}::jsonb`);
        vals.push(JSON.stringify(body.payload));
      }
      if (patches.length === 0) throw new BadRequestException('no_fields');
      patches.push(`updated_at = NOW()`);
      vals.push(id.trim());
      const r = await client.query(`UPDATE admin_support_tickets SET ${patches.join(', ')} WHERE id = $${n}::uuid`, vals);
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'patch_support_ticket', 'support_ticket', id, body as Record<string, unknown>);
      logAdminAction({ adminUid, action: 'patch_support_ticket', targetId: id, targetType: 'support_ticket' });
      return { ok: true as const };
    });
  }

  async listWholesalers(adminUid: string): Promise<{ items: unknown[] }> {
    logAdminAction({ adminUid, action: 'list_wholesalers' });
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id::text, owner_id, name, description, category, city, phone, email, status, commission, created_at
         FROM wholesalers
         ORDER BY created_at DESC
         LIMIT 500`,
      );
      return { items: q.rows };
    });
  }

  async patchWholesaler(
    adminUid: string,
    id: string,
    body: { status?: string; name?: string; category?: string; city?: string; commission?: number },
  ): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const patches: string[] = [];
      const vals: unknown[] = [];
      let n = 1;
      if (body.status !== undefined) {
        patches.push(`status = $${n++}`);
        vals.push(body.status.trim());
      }
      if (body.name !== undefined) {
        patches.push(`name = $${n++}`);
        vals.push(body.name.trim());
      }
      if (body.category !== undefined) {
        patches.push(`category = $${n++}`);
        vals.push(body.category.trim());
      }
      if (body.city !== undefined) {
        patches.push(`city = $${n++}`);
        vals.push(body.city.trim());
      }
      if (body.commission !== undefined && Number.isFinite(body.commission)) {
        patches.push(`commission = $${n++}`);
        vals.push(body.commission);
      }
      if (patches.length === 0) throw new BadRequestException('no_fields');
      vals.push(id.trim());
      const r = await client.query(`UPDATE wholesalers SET ${patches.join(', ')} WHERE id = $${n}::uuid`, vals);
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'patch_wholesaler', 'wholesaler', id, body as Record<string, unknown>);
      logAdminAction({ adminUid, action: 'patch_wholesaler', targetId: id, targetType: 'wholesaler' });
      return { ok: true as const };
    });
  }

  async listCategories(adminUid: string, kind = 'all'): Promise<{ items: unknown[] }> {
    logAdminAction({ adminUid, action: 'list_categories', extra: { kind } });
    return this.withClient(async (client) => {
      const useKind = kind.trim().toLowerCase();
      const q =
        useKind === 'all'
          ? await client.query(
              `SELECT id::text, name, kind, status, payload, created_at, updated_at
               FROM admin_categories
               ORDER BY updated_at DESC
               LIMIT 500`,
            )
          : await client.query(
              `SELECT id::text, name, kind, status, payload, created_at, updated_at
               FROM admin_categories
               WHERE kind = $1
               ORDER BY updated_at DESC
               LIMIT 500`,
              [useKind],
            );
      return { items: q.rows };
    });
  }

  async createCategory(
    adminUid: string,
    body: { name: string; kind?: string; status?: string; payload?: Record<string, unknown> },
  ): Promise<{ ok: true; id: string }> {
    const name = body.name.trim();
    if (!name) throw new BadRequestException('name');
    return this.withClient(async (client) => {
      const r = await client.query(
        `INSERT INTO admin_categories (name, kind, status, payload)
         VALUES ($1, $2, $3, $4::jsonb)
         RETURNING id::text`,
        [name, (body.kind ?? 'general').trim() || 'general', (body.status ?? 'active').trim() || 'active', JSON.stringify(body.payload ?? {})],
      );
      const id = String(r.rows[0]?.['id'] ?? '');
      await this.logAudit(client, adminUid, 'create_category', 'category', id, body as Record<string, unknown>);
      logAdminAction({ adminUid, action: 'create_category', targetId: id, targetType: 'category' });
      return { ok: true as const, id };
    });
  }

  async patchCategory(
    adminUid: string,
    id: string,
    body: { name?: string; kind?: string; status?: string; payload?: Record<string, unknown> },
  ): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const patches: string[] = [];
      const vals: unknown[] = [];
      let n = 1;
      if (body.name !== undefined) {
        patches.push(`name = $${n++}`);
        vals.push(body.name.trim());
      }
      if (body.kind !== undefined) {
        patches.push(`kind = $${n++}`);
        vals.push(body.kind.trim());
      }
      if (body.status !== undefined) {
        patches.push(`status = $${n++}`);
        vals.push(body.status.trim());
      }
      if (body.payload !== undefined) {
        patches.push(`payload = $${n++}::jsonb`);
        vals.push(JSON.stringify(body.payload));
      }
      if (patches.length === 0) throw new BadRequestException('no_fields');
      patches.push(`updated_at = NOW()`);
      vals.push(id.trim());
      const r = await client.query(`UPDATE admin_categories SET ${patches.join(', ')} WHERE id = $${n}::uuid`, vals);
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'patch_category', 'category', id, body as Record<string, unknown>);
      logAdminAction({ adminUid, action: 'patch_category', targetId: id, targetType: 'category' });
      return { ok: true as const };
    });
  }

  async deleteCategory(adminUid: string, id: string): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const r = await client.query(`DELETE FROM admin_categories WHERE id = $1::uuid`, [id.trim()]);
      if (r.rowCount === 0) throw new NotFoundException();
      await this.logAudit(client, adminUid, 'delete_category', 'category', id, {});
      logAdminAction({ adminUid, action: 'delete_category', targetId: id, targetType: 'category' });
      return { ok: true as const };
    });
  }

  async getSettings(adminUid: string): Promise<{ payload: Record<string, unknown> }> {
    logAdminAction({ adminUid, action: 'get_settings' });
    return this.withClient(async (client) => {
      const q = await client.query(`SELECT payload FROM admin_settings WHERE id = 1 LIMIT 1`);
      const row = (q.rows[0] ?? {}) as Record<string, unknown>;
      const payload = row['payload'];
      return {
        payload:
          payload != null && typeof payload === 'object' && !Array.isArray(payload)
            ? (payload as Record<string, unknown>)
            : {},
      };
    });
  }

  async patchSettings(adminUid: string, payload: Record<string, unknown>): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      await client.query(
        `INSERT INTO admin_settings (id, payload, updated_at)
         VALUES (1, $1::jsonb, NOW())
         ON CONFLICT (id) DO UPDATE SET payload = EXCLUDED.payload, updated_at = NOW()`,
        [JSON.stringify(payload)],
      );
      await this.logAudit(client, adminUid, 'patch_settings', 'settings', '1', payload);
      logAdminAction({ adminUid, action: 'patch_settings' });
      return { ok: true as const };
    });
  }

  async findOrCreateOpenSupportTicket(
    firebaseUid: string,
    customerName: string,
  ): Promise<{ id: string; created: boolean }> {
    const uid = firebaseUid.trim();
    const name = customerName.trim() || 'عميل';
    return this.withClient(async (client) => {
      const open = await client.query(
        `SELECT id::text AS id FROM admin_support_tickets
         WHERE status = 'open'
           AND (payload->>'customerUid') = $1
         ORDER BY updated_at DESC
         LIMIT 1`,
        [uid],
      );
      if (open.rows.length > 0) {
        return { id: String(open.rows[0]['id']), created: false };
      }
      const payload = {
        customerUid: uid,
        customerName: name,
        messages: [] as unknown[],
      };
      const ins = await client.query(
        `INSERT INTO admin_support_tickets (subject, status, payload)
         VALUES ($1, 'open', $2::jsonb)
         RETURNING id::text AS id`,
        [`دعم — ${name}`, JSON.stringify(payload)],
      );
      const id = String(ins.rows[0]?.['id'] ?? '');
      return { id, created: true };
    });
  }

  async getSupportTicketForCustomer(
    firebaseUid: string,
    ticketId: string,
  ): Promise<Record<string, unknown> | null> {
    const uid = firebaseUid.trim();
    return this.withClient(async (client) => {
      const r = await client.query(
        `SELECT id::text AS id, status, payload FROM admin_support_tickets WHERE id = $1::uuid`,
        [ticketId.trim()],
      );
      if (r.rows.length === 0) return null;
      const row = r.rows[0] as Record<string, unknown>;
      const payload = row['payload'];
      let p: Record<string, unknown> = {};
      if (payload != null && typeof payload === 'object' && !Array.isArray(payload)) {
        p = payload as Record<string, unknown>;
      }
      if (String(p['customerUid'] ?? '') !== uid) {
        return null;
      }
      const messages = p['messages'];
      return {
        id: row['id'],
        status: row['status'],
        messages: Array.isArray(messages) ? messages : [],
      };
    });
  }

  async listSupportTicketsForCustomer(firebaseUid: string): Promise<{ items: unknown[] }> {
    const uid = firebaseUid.trim();
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id::text AS id, status, payload, updated_at
         FROM admin_support_tickets
         WHERE (payload->>'customerUid') = $1
         ORDER BY updated_at DESC
         LIMIT 100`,
        [uid],
      );
      return {
        items: q.rows.map((row) => {
          const p = row['payload'] as Record<string, unknown>;
          const messages = p['messages'];
          return {
            id: row['id'],
            status: row['status'],
            messages: Array.isArray(messages) ? messages : [],
          };
        }),
      };
    });
  }

  async patchSupportTicketForCustomer(
    firebaseUid: string,
    ticketId: string,
    body: {
      status?: string;
      message?: { senderId?: string; senderName?: string; text?: string; createdAt?: string };
    },
  ): Promise<{ ok: true }> {
    const uid = firebaseUid.trim();
    return this.withClient(async (client) => {
      const r = await client.query(`SELECT payload FROM admin_support_tickets WHERE id = $1::uuid`, [
        ticketId.trim(),
      ]);
      if (r.rows.length === 0) throw new NotFoundException();
      const row = r.rows[0] as { payload: unknown };
      let payload: Record<string, unknown> = {};
      if (row.payload != null && typeof row.payload === 'object' && !Array.isArray(row.payload)) {
        payload = { ...(row.payload as Record<string, unknown>) };
      }
      if (String(payload['customerUid'] ?? '') !== uid) {
        throw new ForbiddenException('forbidden');
      }
      if (body.message) {
        const messages = Array.isArray(payload['messages']) ? [...(payload['messages'] as unknown[])] : [];
        messages.push({
          senderId: body.message.senderId ?? '',
          senderName: body.message.senderName ?? '',
          text: body.message.text ?? '',
          createdAt: body.message.createdAt ?? new Date().toISOString(),
        });
        payload['messages'] = messages;
      }
      const statusCol = body.status !== undefined ? body.status.trim() : undefined;
      if (statusCol !== undefined) {
        await client.query(
          `UPDATE admin_support_tickets SET payload = $1::jsonb, status = $2, updated_at = NOW() WHERE id = $3::uuid`,
          [JSON.stringify(payload), statusCol, ticketId.trim()],
        );
      } else {
        await client.query(
          `UPDATE admin_support_tickets SET payload = $1::jsonb, updated_at = NOW() WHERE id = $2::uuid`,
          [JSON.stringify(payload), ticketId.trim()],
        );
      }
      return { ok: true as const };
    });
  }
}
