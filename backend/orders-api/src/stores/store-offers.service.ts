import { ForbiddenException, Injectable, Logger, NotFoundException, Optional } from '@nestjs/common';
import { Pool } from 'pg';
import { TenantContextService } from '../identity/tenant-context.service';

export type StoreOfferRecord = {
  id: string;
  storeId: string;
  title: string;
  description: string;
  discountPercent: number;
  validUntil: string | null;
  imageUrl: string;
  createdAt: string;
};

@Injectable()
export class StoreOffersService {
  private readonly logger = new Logger(StoreOffersService.name);
  private readonly pool: Pool;

  constructor(@Optional() private readonly tenant?: TenantContextService) {
    const connectionString = process.env.DATABASE_URL?.trim();
    if (!connectionString) {
      this.logger.error(
        'DATABASE_URL missing — StoreOffersService DB queries will fail at runtime until env is set.',
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

  private async ensureStoreAccess(storeId: string, action: string): Promise<void> {
    const { userId, role, isPrivileged } = this.actor();
    if (isPrivileged) return;
    const q = await this.pool.query(`SELECT owner_id, status FROM stores WHERE id = $1::uuid LIMIT 1`, [storeId.trim()]);
    if (q.rows.length === 0) throw new ForbiddenException('Access denied');
    const ownerId = String((q.rows[0] as Record<string, unknown>).owner_id ?? '');
    const status = String((q.rows[0] as Record<string, unknown>).status ?? '');
    if (role === 'store_owner') {
      if (!userId || ownerId !== userId) {
        this.logger.warn(JSON.stringify({ kind: 'authorization_violation', resourceType: 'offer', action, storeId }));
        throw new ForbiddenException('Access denied');
      }
      return;
    }
    if (status !== 'approved') throw new ForbiddenException('Access denied');
  }

  private mapRow(row: Record<string, unknown>): StoreOfferRecord {
    return {
      id: String(row.id),
      storeId: String(row.store_id),
      title: String(row.title ?? ''),
      description: String(row.description ?? ''),
      discountPercent: Number(row.discount_percent ?? 0),
      validUntil: row.valid_until != null ? new Date(String(row.valid_until)).toISOString() : null,
      imageUrl: String(row.image_url ?? ''),
      createdAt: new Date(String(row.created_at)).toISOString(),
    };
  }

  async list(storeId: string): Promise<{ items: StoreOfferRecord[] }> {
    await this.ensureStoreAccess(storeId, 'list_offers');
    const q = await this.pool.query(
      `SELECT id, store_id, title, description, discount_percent, valid_until, image_url, created_at
       FROM store_offers WHERE store_id = $1::uuid ORDER BY created_at DESC`,
      [storeId.trim()],
    );
    return { items: q.rows.map((r) => this.mapRow(r as Record<string, unknown>)) };
  }

  async create(
    storeId: string,
    body: {
      title: string;
      description?: string;
      discountPercent: number;
      validUntil?: string;
      imageUrl?: string;
    },
  ): Promise<StoreOfferRecord> {
    await this.ensureStoreAccess(storeId, 'create_offer');
    const id = await this.pool.query(
      `INSERT INTO store_offers (store_id, title, description, discount_percent, valid_until, image_url)
       VALUES ($1::uuid, $2, $3, $4, $5::timestamptz, $6)
       RETURNING id, store_id, title, description, discount_percent, valid_until, image_url, created_at`,
      [
        storeId.trim(),
        body.title.trim(),
        (body.description ?? '').trim(),
        body.discountPercent,
        body.validUntil != null && body.validUntil.trim() !== '' ? body.validUntil : null,
        (body.imageUrl ?? '').trim(),
      ],
    );
    return this.mapRow(id.rows[0] as Record<string, unknown>);
  }

  async patch(
    offerId: string,
    body: { title?: string; description?: string; discountPercent?: number; validUntil?: string | null; imageUrl?: string },
  ): Promise<StoreOfferRecord> {
    const q0 = await this.pool.query(`SELECT store_id FROM store_offers WHERE id = $1::uuid LIMIT 1`, [offerId.trim()]);
    if (q0.rows.length === 0) throw new NotFoundException('Offer not found');
    const sid = String((q0.rows[0] as Record<string, unknown>).store_id);
    await this.ensureStoreAccess(sid, 'patch_offer');

    const sets: string[] = [];
    const vals: unknown[] = [];
    let i = 1;
    if (body.title != null) {
      sets.push(`title = $${i++}`);
      vals.push(body.title.trim());
    }
    if (body.description != null) {
      sets.push(`description = $${i++}`);
      vals.push(body.description.trim());
    }
    if (body.discountPercent != null) {
      sets.push(`discount_percent = $${i++}`);
      vals.push(body.discountPercent);
    }
    if (body.validUntil !== undefined) {
      sets.push(`valid_until = $${i++}`);
      vals.push(body.validUntil != null && body.validUntil.trim() !== '' ? body.validUntil : null);
    }
    if (body.imageUrl != null) {
      sets.push(`image_url = $${i++}`);
      vals.push(body.imageUrl.trim());
    }
    if (sets.length === 0) {
      const cur = await this.pool.query(
        `SELECT id, store_id, title, description, discount_percent, valid_until, image_url, created_at FROM store_offers WHERE id = $1::uuid`,
        [offerId.trim()],
      );
      return this.mapRow(cur.rows[0] as Record<string, unknown>);
    }
    vals.push(offerId.trim());
    const r = await this.pool.query(
      `UPDATE store_offers SET ${sets.join(', ')} WHERE id = $${i}::uuid
       RETURNING id, store_id, title, description, discount_percent, valid_until, image_url, created_at`,
      vals,
    );
    return this.mapRow(r.rows[0] as Record<string, unknown>);
  }

  async delete(offerId: string): Promise<void> {
    const q0 = await this.pool.query(`SELECT store_id FROM store_offers WHERE id = $1::uuid LIMIT 1`, [offerId.trim()]);
    if (q0.rows.length === 0) throw new NotFoundException('Offer not found');
    const sid = String((q0.rows[0] as Record<string, unknown>).store_id);
    await this.ensureStoreAccess(sid, 'delete_offer');
    await this.pool.query(`DELETE FROM store_offers WHERE id = $1::uuid`, [offerId.trim()]);
  }
}
