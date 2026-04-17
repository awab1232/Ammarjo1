import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { Pool, type PoolClient } from 'pg';
import { normalizeDbRoleToAppRole } from '../identity/db-user-role.util';
import { permissionsForRole, type AppRole } from '../identity/rbac-roles.config';
import type { TenantContextSnapshot } from '../identity/tenant-context.types';

export type AppUserRow = {
  id: string;
  firebase_uid: string;
  email: string | null;
  role: string;
  tenant_id: string | null;
  store_id: string | null;
  wholesaler_id: string | null;
  store_type: string | null;
  is_active: boolean;
};

@Injectable()
export class UsersService {
  private readonly pool: Pool | null;

  constructor() {
    const url = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
    this.pool = url
      ? new Pool({
          connectionString: url,
          max: Number(process.env.USERS_PG_POOL_MAX || 6),
          idleTimeoutMillis: 30_000,
        })
      : null;
  }

  private requireDb(): Pool {
    if (!this.pool) throw new ServiceUnavailableException('users database not configured');
    return this.pool;
  }

  private async withClient<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.requireDb().connect();
    try {
      return await fn(client);
    } finally {
      client.release();
    }
  }

  private mapRow(row: Record<string, unknown>): AppUserRow {
    return {
      id: String(row.id),
      firebase_uid: String(row.firebase_uid),
      email: row.email != null ? String(row.email) : null,
      role: String(row.role ?? 'customer'),
      tenant_id: row.tenant_id != null ? String(row.tenant_id) : null,
      store_id: row.store_id != null ? String(row.store_id) : null,
      wholesaler_id: row.wholesaler_id != null ? String(row.wholesaler_id) : null,
      store_type: row.store_type != null ? String(row.store_type) : null,
      is_active: row.is_active === true || row.is_active === null,
    };
  }

  /**
   * Ensure a row exists for the Firebase user; default role customer.
   */
  async ensureUser(decoded: DecodedIdToken): Promise<AppUserRow> {
    const uid = decoded.uid?.trim();
    if (!uid) {
      throw new ServiceUnavailableException('invalid token uid');
    }
    const email = decoded.email != null ? String(decoded.email).trim() : null;
    return this.withClient(async (client) => {
      const sel = await client.query(
        `SELECT id, firebase_uid, email, role, tenant_id, store_id, wholesaler_id, store_type, is_active
         FROM users WHERE firebase_uid = $1 LIMIT 1`,
        [uid],
      );
      if (sel.rows.length > 0) {
        const cur = this.mapRow(sel.rows[0] as Record<string, unknown>);
        if (email != null && email.length > 0 && (cur.email == null || cur.email !== email)) {
          await client.query(`UPDATE users SET email = $2 WHERE id = $1::uuid`, [cur.id, email]);
          return { ...cur, email };
        }
        return cur;
      }
      const ins = await client.query(
        `INSERT INTO users (firebase_uid, email, role, is_active)
         VALUES ($1, $2, 'customer', true)
         RETURNING id, firebase_uid, email, role, tenant_id, store_id, wholesaler_id, store_type, is_active`,
        [uid, email],
      );
      const row = ins.rows[0];
      if (!row) {
        throw new ServiceUnavailableException('user provisioning failed');
      }
      return this.mapRow(row as Record<string, unknown>);
    });
  }

  /**
   * Merge DB RBAC + optional claim fallbacks for store/wholesale scope (additive).
   */
  mergeSnapshotWithUser(
    base: TenantContextSnapshot,
    row: AppUserRow,
    decoded: DecodedIdToken | undefined,
  ): TenantContextSnapshot {
    if (!row.is_active) {
      return {
        ...base,
        internalUserId: row.id,
        persistedRole: row.role,
        roles: [row.role],
        activeRole: 'customer',
        permissions: [],
        tenantId: null,
        storeId: null,
        storeType: null,
        wholesalerId: null,
      };
    }
    const d = decoded as Record<string, unknown> | undefined;
    const claimStoreId =
      d && typeof d['storeId'] === 'string' && d['storeId'].trim() ? String(d['storeId']).trim() : null;
    const claimWholesalerId =
      d && typeof d['wholesalerId'] === 'string' && d['wholesalerId'].trim()
        ? String(d['wholesalerId']).trim()
        : null;
    const claimStoreType =
      (d && typeof d['storeType'] === 'string' && d['storeType'].trim()
        ? String(d['storeType']).trim()
        : null) ??
      (d && typeof d['store_type'] === 'string' && d['store_type'].trim()
        ? String(d['store_type']).trim()
        : null);
    const claimTenantId =
      d && typeof d['tenantId'] === 'string' && d['tenantId'].trim() ? String(d['tenantId']).trim() : null;

    const appRole = normalizeDbRoleToAppRole(row.role);
    const storeId = row.store_id?.trim() || claimStoreId;
    const wholesalerId = row.wholesaler_id?.trim() || claimWholesalerId;
    const storeType = row.store_type?.trim() || claimStoreType;
    const tenantUuid = row.tenant_id?.trim();
    const tenantId =
      tenantUuid ||
      claimTenantId ||
      (appRole === 'store_owner' ? storeId : null) ||
      wholesalerId ||
      null;

    return {
      ...base,
      internalUserId: row.id,
      persistedRole: row.role,
      roles: [row.role],
      activeRole: appRole,
      permissions: [...permissionsForRole(appRole as AppRole)],
      tenantId,
      storeId: storeId ?? null,
      storeType: storeType ?? null,
      wholesalerId: wholesalerId ?? null,
    };
  }

  async updateRoleByFirebaseUid(
    firebaseUid: string,
    role: string,
    tenantId: string | null,
    storeId: string | null,
    storeType: string | null,
  ): Promise<AppUserRow | null> {
    const uid = firebaseUid.trim();
    if (!uid) return null;
    return this.withClient(async (client) => {
      const r = await client.query(
        `INSERT INTO users (firebase_uid, email, role, tenant_id, store_id, wholesaler_id, store_type, is_active)
         VALUES ($1, NULL, $2, $3::uuid, $4, NULL, $5, true)
         ON CONFLICT (firebase_uid) DO UPDATE SET
           role = EXCLUDED.role,
           tenant_id = EXCLUDED.tenant_id,
           store_id = EXCLUDED.store_id,
           wholesaler_id = NULL,
           store_type = EXCLUDED.store_type
         RETURNING id, firebase_uid, email, role, tenant_id, store_id, wholesaler_id, store_type, is_active`,
        [uid, role, tenantId, storeId, storeType],
      );
      const row = r.rows[0];
      if (!row) return null;
      return this.mapRow(row as Record<string, unknown>);
    });
  }

  async findFirebaseUidByEmailNormalized(email: string): Promise<string | null> {
    const e = email.trim().toLowerCase();
    if (!e) return null;
    return this.withClient(async (client) => {
      const r = await client.query(
        `SELECT firebase_uid FROM users WHERE lower(trim(coalesce(email, ''))) = $1 LIMIT 1`,
        [e],
      );
      if (r.rows.length === 0) return null;
      const uid = String(r.rows[0]['firebase_uid'] ?? '').trim();
      return uid.length > 0 ? uid : null;
    });
  }

  /** Admin / support inboxes for internal broadcast (matches legacy Firestore role names where synced). */
  async listAdminFirebaseUids(): Promise<string[]> {
    return this.withClient(async (client) => {
      const r = await client.query(
        `SELECT firebase_uid FROM users
         WHERE is_active = true AND role = ANY($1::text[])`,
        [['admin', 'system_internal', 'full_admin', 'support']],
      );
      return r.rows
        .map((row) => String(row['firebase_uid'] ?? '').trim())
        .filter((x) => x.length > 0);
    });
  }
}
