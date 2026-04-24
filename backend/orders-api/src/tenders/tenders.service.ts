import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { buildPgPoolConfig } from '../infrastructure/database/pg-ssl';

import { logAuditJson } from '../common/audit-log';

export interface CreateTenderInput {
  customerUid: string;
  category: string;
  categoryId?: string | null;
  description: string;
  city: string;
  userName: string;
  storeTypeId?: string | null;
  storeTypeKey?: string | null;
  storeTypeName?: string | null;
  imageBase64?: string | null;
  imageUrl?: string | null;
}

export interface SubmitOfferInput {
  actorUid: string;
  tenderId: string;
  storeId: string;
  storeName: string;
  price: number;
  note: string;
}

/**
 * Customer-facing tenders service (public `/tenders` routes).
 *
 * Owns two tables:
 *  - `tenders`        — the tender request itself (one per customer + category).
 *  - `tender_offers`  — store replies for a given tender.
 *
 * Mutations are routed through `withClient` so schema bootstrap runs once per
 * process against the shared `DATABASE_URL` pool.
 */
@Injectable()
export class TendersService {
  private readonly pool: Pool | null;
  private tablesReady = false;

  constructor() {
    const url = process.env.DATABASE_URL?.trim();
    this.pool = url
      ? new Pool(
          buildPgPoolConfig(url, {
            max: Number(process.env.TENDERS_PG_POOL_MAX || 4),
            idleTimeoutMillis: 30_000,
          }),
        )
      : null;
  }

  private requireDb(): Pool {
    if (!this.pool) throw new ServiceUnavailableException('tenders database not configured');
    return this.pool;
  }

  private async withClient<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.requireDb().connect();
    try {
      await this.ensureTables(client);
      return await fn(client);
    } finally {
      client.release();
    }
  }

  private async ensureTables(client: PoolClient): Promise<void> {
    if (this.tablesReady) return;
    await client.query(`
      CREATE TABLE IF NOT EXISTS tenders (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        customer_uid text NOT NULL,
        user_id text,
        customer_name text NOT NULL DEFAULT '',
        category text NOT NULL DEFAULT '',
        category_id uuid,
        description text NOT NULL DEFAULT '',
        city text NOT NULL DEFAULT '',
        image_url text,
        image_base64 text,
        store_type_id uuid,
        store_type_key text,
        store_type_name text,
        status text NOT NULL DEFAULT 'open',
        accepted_offer_id uuid,
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
      );
      ALTER TABLE tenders ADD COLUMN IF NOT EXISTS user_id text;
      ALTER TABLE tenders ADD COLUMN IF NOT EXISTS category_id uuid;
      UPDATE tenders
      SET user_id = customer_uid
      WHERE user_id IS NULL OR btrim(user_id) = '';
      CREATE INDEX IF NOT EXISTS idx_tenders_customer ON tenders (customer_uid, updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_tenders_user_id ON tenders (user_id, updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_tenders_status_type ON tenders (status, store_type_id, updated_at DESC);

      CREATE TABLE IF NOT EXISTS tender_offers (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        tender_id uuid NOT NULL REFERENCES tenders(id) ON DELETE CASCADE,
        store_id text NOT NULL DEFAULT '',
        store_id_uuid uuid,
        store_name text NOT NULL DEFAULT '',
        store_owner_uid text NOT NULL DEFAULT '',
        price numeric(12,2) NOT NULL DEFAULT 0,
        note text NOT NULL DEFAULT '',
        status text NOT NULL DEFAULT 'pending',
        created_at timestamptz NOT NULL DEFAULT now(),
        updated_at timestamptz NOT NULL DEFAULT now()
      );
      ALTER TABLE tender_offers ADD COLUMN IF NOT EXISTS store_id_uuid uuid;
      CREATE INDEX IF NOT EXISTS idx_tender_offers_tender ON tender_offers (tender_id, updated_at DESC);
    `);
    this.tablesReady = true;
  }

  private rowToTender(row: Record<string, unknown>): Record<string, unknown> {
    const createdAt = row['created_at'] ?? null;
    return {
      id: row['id'],
      customerUid: row['customer_uid'] ?? row['user_id'],
      userId: row['user_id'] ?? row['customer_uid'],
      userName: row['customer_name'],
      customerName: row['customer_name'],
      category: row['category'],
      categoryId: row['category_id'],
      description: row['description'],
      city: row['city'],
      imageUrl: row['image_url'],
      storeTypeId: row['store_type_id'],
      storeTypeKey: row['store_type_key'],
      storeTypeName: row['store_type_name'],
      status: row['status'],
      acceptedOfferId: row['accepted_offer_id'],
      createdAt,
      expiresAt: createdAt,
      updatedAt: row['updated_at'],
    };
  }

  private rowToOffer(row: Record<string, unknown>): Record<string, unknown> {
    return {
      id: row['id'],
      tenderId: row['tender_id'],
      storeId: row['store_id'],
      storeIdUuid: row['store_id_uuid'],
      storeName: row['store_name'],
      storeOwnerUid: row['store_owner_uid'],
      storeOwnerId: row['store_owner_uid'],
      price: Number(row['price']),
      note: row['note'],
      status: row['status'],
      createdAt: row['created_at'],
      updatedAt: row['updated_at'],
    };
  }

  async create(input: CreateTenderInput): Promise<Record<string, unknown>> {
    if (!input.customerUid.trim()) throw new BadRequestException('missing_customer');
    if (!input.category.trim() && !input.description.trim()) {
      throw new BadRequestException('category_or_description_required');
    }
    return this.withClient(async (client) => {
      const q = await client.query(
        `INSERT INTO tenders
           (customer_uid, user_id, customer_name, category, category_id, description, city,
            image_url, image_base64, store_type_id, store_type_key, store_type_name)
         VALUES ($1,$1,$2,$3, NULLIF($4,'')::uuid,$5,$6,$7,$8, NULLIF($9,'')::uuid, NULLIF($10,''), NULLIF($11,''))
         RETURNING id::text, customer_uid, user_id, customer_name, category, category_id::text AS category_id, description, city,
                   image_url, store_type_id::text AS store_type_id, store_type_key, store_type_name,
                   status, accepted_offer_id::text AS accepted_offer_id, created_at, updated_at`,
        [
          input.customerUid.trim(),
          (input.userName || '').trim(),
          input.category.trim(),
          input.categoryId?.trim() || '',
          input.description.trim(),
          input.city.trim(),
          input.imageUrl?.trim() || null,
          input.imageBase64?.trim() || null,
          input.storeTypeId?.trim() || '',
          input.storeTypeKey?.trim() || '',
          input.storeTypeName?.trim() || '',
        ],
      );
      logAuditJson('audit', {
        action: 'tender_created',
        tenderId: q.rows[0]?.['id'],
        customerUid: input.customerUid.trim(),
      });
      return this.rowToTender(q.rows[0] as Record<string, unknown>);
    });
  }

  async listMine(customerUid: string, limit = 50): Promise<{ items: Record<string, unknown>[] }> {
    if (!customerUid.trim()) return { items: [] };
    const lim = Math.min(200, Math.max(1, limit));
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id::text, customer_uid, user_id, customer_name, category, category_id::text AS category_id, description, city,
                image_url, store_type_id::text AS store_type_id, store_type_key, store_type_name,
                status, accepted_offer_id::text AS accepted_offer_id, created_at, updated_at
         FROM tenders
         WHERE user_id = $1 OR customer_uid = $1
         ORDER BY updated_at DESC
         LIMIT $2`,
        [customerUid.trim(), lim],
      );
      return { items: (q.rows as Record<string, unknown>[]).map((r) => this.rowToTender(r)) };
    });
  }

  /**
   * Open feed for stores: returns open tenders targeted at a given store-type
   * (by id or key). Callers pass the store's own type so targeting is symmetric
   * with `_notifyTargetedStores` on the client side.
   */
  async listOpenForStore(params: {
    actorUid: string;
    storeTypeId?: string;
    storeTypeKey?: string;
    city?: string;
    limit?: number;
  }): Promise<{ items: Record<string, unknown>[] }> {
    const lim = Math.min(200, Math.max(1, params.limit ?? 50));
    const sid = (params.storeTypeId ?? '').trim();
    const skey = (params.storeTypeKey ?? '').trim().toLowerCase();
    const city = (params.city ?? '').trim();
    return this.withClient(async (client) => {
      const actorUid = (params.actorUid ?? '').trim();
      if (!actorUid) throw new BadRequestException('missing_actor_uid');
      const where: string[] = [`status = 'open'`];
      const vals: unknown[] = [];
      let n = 1;
      const ownStores = await client.query(
        `SELECT id::text AS id, store_type_id::text AS store_type_id, lower(store_type_key) AS store_type_key, city
         FROM stores
         WHERE owner_id = $1`,
        [actorUid],
      );
      const ownStoreIds = new Set(
        ownStores.rows.map((r) => String(r['id'] ?? '').trim()).filter((v) => v.length > 0),
      );
      if (ownStoreIds.size === 0) {
        return { items: [] };
      }
      if (sid) {
        const ownsRequestedType = ownStores.rows.some(
          (r) => String(r['store_type_id'] ?? '').trim() === sid,
        );
        if (!ownsRequestedType) {
          return { items: [] };
        }
        where.push(`store_type_id = $${n++}::uuid`);
        vals.push(sid);
      } else if (skey) {
        const ownsRequestedKey = ownStores.rows.some(
          (r) => String(r['store_type_key'] ?? '').trim() === skey,
        );
        if (!ownsRequestedKey) {
          return { items: [] };
        }
        where.push(`lower(store_type_key) = $${n++}`);
        vals.push(skey);
      }
      if (city) {
        where.push(`(city = '' OR city = $${n++})`);
        vals.push(city);
      }
      vals.push(lim);
      const q = await client.query(
        `SELECT id::text, customer_uid, user_id, customer_name, category, category_id::text AS category_id, description, city,
                image_url, store_type_id::text AS store_type_id, store_type_key, store_type_name,
                status, accepted_offer_id::text AS accepted_offer_id, created_at, updated_at
         FROM tenders
         WHERE ${where.join(' AND ')}
         ORDER BY updated_at DESC
         LIMIT $${n}`,
        vals,
      );
      return { items: (q.rows as Record<string, unknown>[]).map((r) => this.rowToTender(r)) };
    });
  }

  async getById(id: string, actorUid: string, isAdmin = false): Promise<Record<string, unknown>> {
    if (!id.trim()) throw new BadRequestException('missing_tender_id');
    const actor = actorUid.trim();
    if (!actor) throw new ForbiddenException('forbidden');
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id::text, customer_uid, user_id, customer_name, category, category_id::text AS category_id, description, city,
                image_url, store_type_id::text AS store_type_id, store_type_key, store_type_name,
                status, accepted_offer_id::text AS accepted_offer_id, created_at, updated_at,
                EXISTS (
                  SELECT 1
                  FROM tender_offers o
                  WHERE o.tender_id = tenders.id
                    AND o.store_owner_uid = $2
                ) AS has_actor_offer
         FROM tenders WHERE id = $1::uuid`,
        [id.trim(), actor],
      );
      if (q.rows.length === 0) throw new NotFoundException('tender_not_found');
      const row = q.rows[0] as Record<string, unknown>;
      const isOwner = String(row['user_id'] ?? row['customer_uid'] ?? '').trim() === actor;
      const hasActorOffer = row['has_actor_offer'] === true;
      if (!isAdmin && !isOwner && !hasActorOffer) {
        throw new ForbiddenException('forbidden');
      }
      return this.rowToTender(row);
    });
  }

  async listOffers(
    tenderId: string,
    actorUid: string,
    isAdmin = false,
  ): Promise<{ items: Record<string, unknown>[] }> {
    if (!tenderId.trim()) throw new BadRequestException('missing_tender_id');
    const actor = actorUid.trim();
    if (!actor) throw new ForbiddenException('forbidden');
    return this.withClient(async (client) => {
      const tender = await client.query(
        `SELECT COALESCE(user_id, customer_uid) AS user_id
         FROM tenders
         WHERE id = $1::uuid
         LIMIT 1`,
        [tenderId.trim()],
      );
      if (tender.rows.length === 0) throw new NotFoundException('tender_not_found');
      const isOwner = String(tender.rows[0]?.['user_id'] ?? '').trim() === actor;
      if (!isAdmin && !isOwner) {
        const actorOffer = await client.query(
          `SELECT 1
           FROM tender_offers
           WHERE tender_id = $1::uuid
             AND store_owner_uid = $2
           LIMIT 1`,
          [tenderId.trim(), actor],
        );
        if (actorOffer.rows.length === 0) {
          throw new ForbiddenException('forbidden');
        }
        const ownOffers = await client.query(
          `SELECT id::text, tender_id::text, store_id, store_name, store_owner_uid,
                  price, note, status, created_at, updated_at
           FROM tender_offers
           WHERE tender_id = $1::uuid
             AND store_owner_uid = $2
           ORDER BY created_at ASC`,
          [tenderId.trim(), actor],
        );
        return { items: (ownOffers.rows as Record<string, unknown>[]).map((r) => this.rowToOffer(r)) };
      }
      const q = await client.query(
        `SELECT id::text, tender_id::text, store_id, store_name, store_owner_uid,
                price, note, status, created_at, updated_at
         FROM tender_offers
         WHERE tender_id = $1::uuid
         ORDER BY created_at ASC`,
        [tenderId.trim()],
      );
      return { items: (q.rows as Record<string, unknown>[]).map((r) => this.rowToOffer(r)) };
    });
  }

  async submitOffer(input: SubmitOfferInput): Promise<Record<string, unknown>> {
    const actorUid = input.actorUid.trim();
    if (!actorUid) throw new BadRequestException('missing_actor_uid');
    if (!input.tenderId.trim()) throw new BadRequestException('missing_tender_id');
    if (!input.storeId.trim()) throw new BadRequestException('missing_store_id');
    if (!Number.isFinite(input.price) || input.price < 0) throw new BadRequestException('invalid_price');
    return this.withClient(async (client) => {
      const store = await client.query(
        `SELECT id::text AS id, owner_id, name
         FROM stores
         WHERE id::text = $1
         LIMIT 1`,
        [input.storeId.trim()],
      );
      if (store.rows.length === 0) throw new NotFoundException('store_not_found');
      if (String(store.rows[0]['owner_id'] ?? '').trim() !== actorUid) {
        throw new ForbiddenException('forbidden');
      }
      const sel = await client.query(`SELECT status FROM tenders WHERE id = $1::uuid`, [input.tenderId.trim()]);
      if (sel.rows.length === 0) throw new NotFoundException('tender_not_found');
      if (String(sel.rows[0]['status']) !== 'open') throw new BadRequestException('tender_closed');
      const q = await client.query(
        `INSERT INTO tender_offers (tender_id, store_id, store_id_uuid, store_name, store_owner_uid, price, note)
         VALUES ($1::uuid, $2, NULLIF($2,'')::uuid, $3, $4, $5, $6)
         RETURNING id::text, tender_id::text, store_id, store_id_uuid::text AS store_id_uuid, store_name, store_owner_uid,
                   price, note, status, created_at, updated_at`,
        [
          input.tenderId.trim(),
          input.storeId.trim(),
          input.storeName.trim().length > 0
              ? input.storeName.trim()
              : String(store.rows[0]['name'] ?? '').trim(),
          actorUid,
          input.price,
          input.note.trim(),
        ],
      );
      await client.query(`UPDATE tenders SET updated_at = NOW() WHERE id = $1::uuid`, [input.tenderId.trim()]);
      logAuditJson('audit', {
        action: 'tender_offer_submitted',
        tenderId: input.tenderId.trim(),
        offerId: q.rows[0]?.['id'],
        storeId: input.storeId.trim(),
      });
      return this.rowToOffer(q.rows[0] as Record<string, unknown>);
    });
  }

  async patchOffer(
    customerUid: string,
    tenderId: string,
    offerId: string,
    body: { status?: string },
  ): Promise<Record<string, unknown>> {
    const status = (body.status ?? '').trim().toLowerCase();
    if (!status) throw new BadRequestException('missing_status');
    const allowed = new Set(['accepted', 'rejected', 'withdrawn']);
    if (!allowed.has(status)) throw new BadRequestException('invalid_status');

    return this.withClient(async (client) => {
      const tSel = await client.query(
        `SELECT COALESCE(user_id, customer_uid) AS user_id, status FROM tenders WHERE id = $1::uuid`,
        [tenderId.trim()],
      );
      if (tSel.rows.length === 0) throw new NotFoundException('tender_not_found');
      if (String(tSel.rows[0]['user_id']) !== customerUid.trim()) {
        throw new ForbiddenException('forbidden');
      }

      const oSel = await client.query(
        `SELECT id::text FROM tender_offers WHERE id = $1::uuid AND tender_id = $2::uuid`,
        [offerId.trim(), tenderId.trim()],
      );
      if (oSel.rows.length === 0) throw new NotFoundException('offer_not_found');

      const upd = await client.query(
        `UPDATE tender_offers SET status = $1, updated_at = NOW()
         WHERE id = $2::uuid AND tender_id = $3::uuid
         RETURNING id::text, tender_id::text, store_id, store_name, store_owner_uid,
                   price, note, status, created_at, updated_at`,
        [status, offerId.trim(), tenderId.trim()],
      );

      if (status === 'accepted') {
        await client.query(
          `UPDATE tenders SET status = 'closed', accepted_offer_id = $1::uuid, updated_at = NOW()
           WHERE id = $2::uuid`,
          [offerId.trim(), tenderId.trim()],
        );
        await client.query(
          `UPDATE tender_offers SET status = 'rejected', updated_at = NOW()
           WHERE tender_id = $1::uuid AND id <> $2::uuid AND status = 'pending'`,
          [tenderId.trim(), offerId.trim()],
        );
      }

      logAuditJson('audit', {
        action: 'tender_offer_patched',
        tenderId: tenderId.trim(),
        offerId: offerId.trim(),
        status,
      });
      return this.rowToOffer(upd.rows[0] as Record<string, unknown>);
    });
  }

  /** Customer-initiated tender lifecycle (close/delete). */
  async patchTenderStatus(
    customerUid: string,
    tenderId: string,
    body: { status?: string },
  ): Promise<{ ok: true }> {
    const status = (body.status ?? '').trim().toLowerCase();
    if (!status) throw new BadRequestException('missing_status');
    if (!['closed', 'cancelled'].includes(status)) throw new BadRequestException('invalid_status');
    return this.withClient(async (client) => {
      const sel = await client.query(
        `SELECT COALESCE(user_id, customer_uid) AS user_id FROM tenders WHERE id = $1::uuid`,
        [tenderId.trim()],
      );
      if (sel.rows.length === 0) throw new NotFoundException('tender_not_found');
      if (String(sel.rows[0]['user_id']) !== customerUid.trim()) {
        throw new ForbiddenException('forbidden');
      }
      await client.query(
        `UPDATE tenders SET status = $1, updated_at = NOW() WHERE id = $2::uuid`,
        [status, tenderId.trim()],
      );
      return { ok: true as const };
    });
  }

  async deleteTender(customerUid: string, tenderId: string): Promise<{ ok: true }> {
    return this.withClient(async (client) => {
      const sel = await client.query(
        `SELECT COALESCE(user_id, customer_uid) AS user_id FROM tenders WHERE id = $1::uuid`,
        [tenderId.trim()],
      );
      if (sel.rows.length === 0) throw new NotFoundException('tender_not_found');
      if (String(sel.rows[0]['user_id']) !== customerUid.trim()) {
        throw new ForbiddenException('forbidden');
      }
      await client.query(`DELETE FROM tenders WHERE id = $1::uuid`, [tenderId.trim()]);
      logAuditJson('audit', { action: 'tender_deleted', tenderId: tenderId.trim() });
      return { ok: true as const };
    });
  }
}
