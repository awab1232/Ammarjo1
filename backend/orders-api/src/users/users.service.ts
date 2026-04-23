import { Injectable, Logger, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { Pool, type PoolClient } from 'pg';
import { buildPgPoolConfig } from '../infrastructure/database/pg-ssl';
import { normalizeDbRoleToAppRole } from '../identity/db-user-role.util';
import { permissionsForRole, type AppRole } from '../identity/rbac-roles.config';
import type { TenantContextSnapshot } from '../identity/tenant-context.types';

function isPgUniqueViolationOnFirebaseUid(e: unknown): boolean {
  if (e === null || typeof e !== 'object') {
    return false;
  }
  return (e as { code?: string; constraint?: string }).code === '23505';
}

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
  private readonly logger = new Logger(UsersService.name);
  private readonly pool: Pool | null;

  constructor() {
    const url = process.env.DATABASE_URL?.trim();
    this.pool = url
      ? new Pool(
          buildPgPoolConfig(url, {
            max: Number(process.env.USERS_PG_POOL_MAX || 6),
            idleTimeoutMillis: 30_000,
          }),
        )
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
      try {
        const ins = await client.query(
          `INSERT INTO users (firebase_uid, email, role, is_active)
           VALUES ($1, $2, 'customer', true)
           ON CONFLICT (firebase_uid)
           DO UPDATE SET email = COALESCE(NULLIF(EXCLUDED.email, ''), users.email)
           RETURNING id, firebase_uid, email, role, tenant_id, store_id, wholesaler_id, store_type, is_active`,
          [uid, email],
        );
        const row = ins.rows[0];
        if (!row) {
          throw new ServiceUnavailableException('user provisioning failed');
        }
        return this.mapRow(row as Record<string, unknown>);
      } catch (e) {
        // Legacy binary without ON CONFLICT, or rare race: fall back to SELECT by firebase_uid.
        if (isPgUniqueViolationOnFirebaseUid(e)) {
          const sel = await client.query(
            `SELECT id, firebase_uid, email, role, tenant_id, store_id, wholesaler_id, store_type, is_active
             FROM users
             WHERE firebase_uid = $1
             LIMIT 1`,
            [uid],
          );
          const r = sel.rows[0];
          if (r) {
            return this.mapRow(r as Record<string, unknown>);
          }
        }
        throw e;
      }
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

  /**
   * Optional profile coordinates (migration 032+). Used when order payload has no delivery_lat/lng.
   */
  /**
   * Lightweight write for client GPS — used as delivery coordinate fallback on order create.
   * Returns false if DB unavailable or user row missing (caller should not throw).
   */
  async updateLastKnownLocation(firebaseUid: string, lat: number, lng: number): Promise<boolean> {
    const uid = firebaseUid.trim();
    if (!uid || !this.pool) {
      return false;
    }
    try {
      const r = await this.withClient(async (client) => {
        const u = await client.query(
          `UPDATE users SET last_lat = $1, last_lng = $2 WHERE firebase_uid = $3`,
          [lat, lng, uid],
        );
        return (u.rowCount ?? 0) > 0;
      });
      if (!r) {
        this.logger.warn(JSON.stringify({ kind: 'user_location_no_row', userId: uid }));
      }
      return r;
    } catch (e) {
      this.logger.warn(
        JSON.stringify({
          kind: 'user_location_update_failed',
          userId: uid,
          error: e instanceof Error ? e.message : String(e),
        }),
      );
      return false;
    }
  }

  async getLastKnownCoords(firebaseUid: string): Promise<{ lat: number; lng: number } | null> {
    const uid = firebaseUid.trim();
    if (!uid) {
      return null;
    }
    try {
      return await this.withClient(async (client) => {
        const r = await client.query<{ last_lat: unknown; last_lng: unknown }>(
          `SELECT last_lat, last_lng FROM users WHERE firebase_uid = $1 LIMIT 1`,
          [uid],
        );
        if (r.rows.length === 0) {
          return null;
        }
        const row = r.rows[0];
        const lat = Number(row.last_lat);
        const lng = Number(row.last_lng);
        if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
          return null;
        }
        return { lat, lng };
      });
    } catch {
      return null;
    }
  }

  /**
   * Public profile for GET /users/:firebaseUid (self-only). Uses `profile_json` when present.
   */
  async findProfileRowByFirebaseUid(firebaseUid: string): Promise<{
    row: AppUserRow;
    phone: string | null;
    profile: Record<string, unknown>;
    banned: boolean;
  } | null> {
    const uid = firebaseUid.trim();
    if (!uid) return null;
    if (!this.pool) {
      return null;
    }
    return this.withClient(async (client) => {
      const r = await client.query(
        `SELECT id, firebase_uid, email, role, tenant_id, store_id, wholesaler_id, store_type, is_active,
                phone, profile_json, COALESCE(banned, false) AS banned
         FROM users
         WHERE firebase_uid = $1
         LIMIT 1`,
        [uid],
      );
      if (r.rows.length === 0) return null;
      const raw = r.rows[0] as Record<string, unknown>;
      const pj = raw['profile_json'];
      const profile =
        pj != null && typeof pj === 'object' && !Array.isArray(pj) ? (pj as Record<string, unknown>) : {};
      return {
        row: this.mapRow(raw),
        phone: raw['phone'] != null ? String(raw['phone']) : null,
        profile,
        banned: raw['banned'] === true,
      };
    });
  }

  /**
   * Merge into `users.profile_json` and update email/phone columns. Self-only; caller enforces.
   */
  async patchUserProfile(firebaseUid: string, body: Record<string, unknown>): Promise<void> {
    const uid = firebaseUid.trim();
    if (!uid) {
      throw new NotFoundException('user not found');
    }
    return this.withClient(async (client) => {
      const cur = await client.query(
        `SELECT profile_json, email, phone FROM users WHERE firebase_uid = $1 FOR UPDATE`,
        [uid],
      );
      if (cur.rows.length === 0) {
        throw new NotFoundException('user not found');
      }
      const raw = cur.rows[0] as Record<string, unknown>;
      const pj = raw['profile_json'];
      const next: Record<string, unknown> =
        pj != null && typeof pj === 'object' && !Array.isArray(pj) ? { ...(pj as Record<string, unknown>) } : {};

      if (typeof body['loyaltyPointsDelta'] === 'number' && Number.isFinite(body['loyaltyPointsDelta'])) {
        const curPts = Math.max(0, Math.floor(Number(next['loyaltyPoints'] ?? 0)));
        next['loyaltyPoints'] = curPts + Math.floor(body['loyaltyPointsDelta']);
      }
      const apo = body['addPointsForOrder'];
      if (apo != null && typeof apo === 'object' && !Array.isArray(apo)) {
        const p = (apo as Record<string, unknown>)['points'];
        if (typeof p === 'number' && Number.isFinite(p)) {
          const curPts = Math.max(0, Math.floor(Number(next['loyaltyPoints'] ?? 0)));
          next['loyaltyPoints'] = curPts + Math.floor(p);
        }
      }
      for (const [k, v] of Object.entries(body)) {
        if (v == null) continue;
        if (k === 'loyaltyPointsDelta' || k === 'addPointsForOrder') continue;
        if (k === 'loyaltyPoints' && typeof v === 'number' && Number.isFinite(v)) {
          next['loyaltyPoints'] = Math.max(0, Math.floor(v));
          continue;
        }
        if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') {
          next[k] = v;
        }
      }

      let newEmail: string | null = raw['email'] != null ? String(raw['email']) : null;
      if (typeof body['email'] === 'string' && body['email'].trim()) {
        newEmail = body['email'].trim();
      } else if (next['email'] != null && String(next['email']).trim()) {
        newEmail = String(next['email']).trim();
      }
      let newPhone: string | null = raw['phone'] != null ? String(raw['phone']) : null;
      if (typeof body['phone'] === 'string' && body['phone'].trim()) {
        newPhone = body['phone'].trim();
      } else if (next['phone'] != null && String(next['phone']).trim()) {
        newPhone = String(next['phone']).trim();
      }

      await client.query(
        `UPDATE users
         SET profile_json = $2::jsonb, email = $3, phone = $4
         WHERE firebase_uid = $1`,
        [uid, JSON.stringify(next), newEmail, newPhone],
      );
    });
  }
}
