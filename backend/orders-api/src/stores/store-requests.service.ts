import { BadRequestException, ConflictException, ForbiddenException, Injectable, ServiceUnavailableException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Pool } from 'pg';

@Injectable()
export class StoreRequestsService {
  private readonly pool: Pool | null;
  private schemaReady = false;

  constructor() {
    const url = process.env.DATABASE_URL?.trim();
    this.pool = url ? new Pool({ connectionString: url, max: Number(process.env.STORE_REQUESTS_PG_POOL_MAX || 4) }) : null;
  }

  private requireDb(): Pool {
    if (!this.pool) throw new ServiceUnavailableException('store requests database not configured');
    return this.pool;
  }

  private async ensureSchema(): Promise<void> {
    if (this.schemaReady) return;
    await this.requireDb().query(`
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS phone text NOT NULL DEFAULT '';
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS sell_scope text NOT NULL DEFAULT 'city';
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS city text NOT NULL DEFAULT '';
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS cities text[] NOT NULL DEFAULT '{}'::text[];
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS store_type_id uuid;
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS store_type_key text;
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
      CREATE UNIQUE INDEX IF NOT EXISTS idx_technician_join_requests_uid_unique
        ON technician_join_requests (firebase_uid)
        WHERE firebase_uid IS NOT NULL;
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
    this.schemaReady = true;
  }

  async submitStoreRequest(body: Record<string, unknown>, actorUid: string): Promise<{ ok: true; requestId: string; status: string }> {
    await this.ensureSchema();
    const applicantId = String(body['applicantId'] ?? '').trim();
    if (!applicantId || applicantId !== actorUid.trim()) {
      throw new ForbiddenException('applicant_mismatch');
    }
    const storeName = String(body['storeName'] ?? '').trim();
    const phone = String(body['phone'] ?? '').trim();
    const description = String(body['description'] ?? '').trim();
    const storeType = String(body['storeType'] ?? 'retail').trim().toLowerCase();
    const sellScope = String(body['sellScope'] ?? 'city').trim().toLowerCase();
    const city = String(body['city'] ?? '').trim();
    const category = String(body['category'] ?? '').trim();
    const storeTypeId = String(body['storeTypeId'] ?? '').trim();
    const rawCities = Array.isArray(body['cities']) ? (body['cities'] as unknown[]) : [];
    const cities = rawCities.map((x) => String(x ?? '').trim()).filter((x) => x.length > 0);
    if (!storeName || !phone || !description) throw new BadRequestException('missing_store_request_fields');
    if (storeType !== 'retail' && storeType !== 'wholesale') throw new BadRequestException('invalid_store_type');
    if (sellScope !== 'city' && sellScope !== 'all_jordan') throw new BadRequestException('invalid_sell_scope');
    if (cities.length === 0) throw new BadRequestException('cities_required');

    const client = await this.requireDb().connect();
    try {
      const existing = await client.query(
        `SELECT id::text
         FROM stores
         WHERE owner_id = $1
           AND status = ANY($2::text[])
         ORDER BY created_at DESC
         LIMIT 1`,
        [actorUid.trim(), ['pending', 'under_review', 'approved']],
      );
      if (existing.rows.length > 0) {
        throw new ConflictException('store_request_exists');
      }
      let storeTypeKey: string | null = null;
      if (storeTypeId) {
        const typeQ = await client.query(`SELECT key FROM store_types WHERE id = $1::uuid LIMIT 1`, [storeTypeId]);
        if (typeQ.rows.length > 0) {
          storeTypeKey = String(typeQ.rows[0]['key'] ?? '').trim() || null;
        }
      }
      const id = randomUUID();
      await client.query(
        `INSERT INTO stores (
           id, owner_id, tenant_id, name, description, category, status, store_type, store_type_id, store_type_key,
           phone, sell_scope, city, cities, created_at
         ) VALUES (
           $1::uuid, $2, NULL, $3, $4, $5, 'pending', $6, $7::uuid, $8, $9, $10, $11, $12::text[], NOW()
         )`,
        [
          id,
          actorUid.trim(),
          storeName,
          description,
          category,
          storeType,
          storeTypeId || null,
          storeTypeKey,
          phone,
          sellScope,
          city,
          cities,
        ],
      );
      return { ok: true as const, requestId: id, status: 'pending' };
    } finally {
      client.release();
    }
  }

  async submitTechnicianRequest(body: Record<string, unknown>, actorUid: string): Promise<{ ok: true; requestId: string; status: string }> {
    await this.ensureSchema();
    const claimedApplicant = String(body['applicantId'] ?? body['firebaseUid'] ?? '').trim();
    if (claimedApplicant.length > 0 && claimedApplicant !== actorUid.trim()) {
      throw new ForbiddenException('applicant_mismatch');
    }
    const email = String(body['email'] ?? '').trim().toLowerCase();
    const displayName = String(body['displayName'] ?? body['fullName'] ?? '').trim();
    const phone = String(body['phone'] ?? '').trim();
    const city = String(body['city'] ?? '').trim();
    const categoryId = String(body['categoryId'] ?? '').trim();
    const rawSpecs = Array.isArray(body['specialties']) ? (body['specialties'] as unknown[]) : [];
    const specialties = rawSpecs.map((x) => String(x ?? '').trim()).filter((x) => x.length > 0);
    if (!email || !displayName || !phone || !city || !categoryId || specialties.length === 0) {
      throw new BadRequestException('missing_technician_request_fields');
    }

    const client = await this.requireDb().connect();
    try {
      const existing = await client.query(
        `SELECT id::text
         FROM technician_join_requests
         WHERE (firebase_uid = $1 AND $1 <> '') OR lower(trim(email)) = $2
         LIMIT 1`,
        [actorUid.trim(), email],
      );
      const cities = [city];
      if (existing.rows.length > 0) {
        const id = String(existing.rows[0]['id'] ?? '').trim();
        await client.query(
          `UPDATE technician_join_requests
           SET firebase_uid = $2,
               email = $3,
               display_name = $4,
               specialties = $5::text[],
               category_id = $6,
               phone = $7,
               city = $8,
               cities = $9::text[],
               status = 'pending',
               rejection_reason = NULL,
               reviewed_by = NULL,
               reviewed_at = NULL
           WHERE id = $1::uuid`,
          [id, actorUid.trim(), email, displayName, specialties, categoryId, phone, city, cities],
        );
        return { ok: true as const, requestId: id, status: 'pending' };
      }
      const id = randomUUID();
      await client.query(
        `INSERT INTO technician_join_requests (
           id, firebase_uid, email, display_name, specialties, category_id, phone, city, cities, status, created_at
         ) VALUES (
           $1::uuid, $2, $3, $4, $5::text[], $6, $7, $8, $9::text[], 'pending', NOW()
         )`,
        [id, actorUid.trim(), email, displayName, specialties, categoryId, phone, city, cities],
      );
      return { ok: true as const, requestId: id, status: 'pending' };
    } finally {
      client.release();
    }
  }
}
