import { BadRequestException, Injectable, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';

export type CartItemRow = {
  id: string;
  productId: number;
  variantId: string | null;
  quantity: number;
  priceSnapshot: string;
  productName: string;
  imageUrl: string | null;
  storeId: string;
  storeName: string;
  createdAt: string;
  updatedAt: string;
};

@Injectable()
export class CartService {
  private readonly pool: Pool | null;

  constructor() {
    const url = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
    this.pool = url
      ? new Pool({
          connectionString: url,
          max: Number(process.env.CART_PG_POOL_MAX || 6),
          idleTimeoutMillis: 30_000,
        })
      : null;
  }

  private requireDb(): Pool {
    if (!this.pool) throw new ServiceUnavailableException('cart database not configured');
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

  private mapRow(row: Record<string, unknown>): CartItemRow {
    return {
      id: String(row.id),
      productId: Number(row.product_id ?? 0),
      variantId: row.variant_id != null ? String(row.variant_id) : null,
      quantity: Number(row.quantity ?? 0),
      priceSnapshot: String(row.price_snapshot ?? '0'),
      productName: String(row.product_name ?? ''),
      imageUrl: row.image_url != null ? String(row.image_url) : null,
      storeId: String(row.store_id ?? ''),
      storeName: String(row.store_name ?? ''),
      createdAt: new Date(String(row.created_at)).toISOString(),
      updatedAt: new Date(String(row.updated_at)).toISOString(),
    };
  }

  async list(userId: string): Promise<{ items: CartItemRow[] }> {
    const uid = userId.trim();
    if (!uid) throw new BadRequestException('user required');
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id, product_id, variant_id, quantity, price_snapshot, product_name, image_url, store_id, store_name, created_at, updated_at
         FROM cart_items WHERE user_id = $1 ORDER BY created_at ASC`,
        [uid],
      );
      return { items: q.rows.map((r) => this.mapRow(r as Record<string, unknown>)) };
    });
  }

  private async assertStockOk(
    client: PoolClient,
    productId: number,
    storeId: string,
  ): Promise<void> {
    const q = await client.query(
      `SELECT stock_status FROM catalog_products WHERE product_id = $1 AND store_id = $2 LIMIT 1`,
      [productId, storeId],
    );
    if (q.rows.length === 0) return;
    const ss = String(q.rows[0]['stock_status'] ?? 'instock').trim().toLowerCase();
    if (ss === 'outofstock') {
      throw new BadRequestException('product_out_of_stock');
    }
  }

  async addItem(
    userId: string,
    body: {
      productId: number;
      variantId?: string | null;
      quantity: number;
      priceSnapshot: string;
      productName?: string;
      imageUrl?: string | null;
      storeId?: string;
      storeName?: string;
    },
  ): Promise<{ item: CartItemRow }> {
    const uid = userId.trim();
    if (!uid) throw new BadRequestException('user required');
    const qty = Math.floor(Number(body.quantity));
    if (!Number.isFinite(qty) || qty <= 0) throw new BadRequestException('invalid_quantity');
    const pid = Math.floor(Number(body.productId));
    if (!Number.isFinite(pid) || pid <= 0) throw new BadRequestException('invalid_product_id');
    const storeId = (body.storeId ?? 'ammarjo').trim() || 'ammarjo';
    const storeName = (body.storeName ?? 'متجر').trim() || 'متجر';
    const variantKey = body.variantId != null && String(body.variantId).trim() !== '' ? String(body.variantId).trim() : null;
    const price = String(body.priceSnapshot ?? '').trim();
    if (!price) throw new BadRequestException('price_snapshot_required');

    return this.withClient(async (client) => {
      await this.assertStockOk(client, pid, storeId);

      const existing = await client.query(
        `SELECT id, quantity FROM cart_items
         WHERE user_id = $1 AND product_id = $2 AND COALESCE(variant_id, '') = COALESCE($3::text, '')
         LIMIT 1`,
        [uid, pid, variantKey],
      );
      if (existing.rows.length > 0) {
        const curId = String(existing.rows[0]['id']);
        const curQty = Number(existing.rows[0]['quantity'] ?? 0);
        const nextQty = curQty + qty;
        const u = await client.query(
          `UPDATE cart_items SET quantity = $2, price_snapshot = $3::numeric, updated_at = NOW(),
             product_name = COALESCE(NULLIF($4::text, ''), product_name),
             image_url = COALESCE($5, image_url)
           WHERE id = $1::uuid AND user_id = $6
           RETURNING id, product_id, variant_id, quantity, price_snapshot, product_name, image_url, store_id, store_name, created_at, updated_at`,
          [curId, nextQty, price, body.productName ?? '', body.imageUrl ?? null, uid],
        );
        const row = u.rows[0];
        if (!row) throw new NotFoundException();
        return { item: this.mapRow(row as Record<string, unknown>) };
      }

      const ins = await client.query(
        `INSERT INTO cart_items (
           user_id, product_id, variant_id, quantity, price_snapshot, product_name, image_url, store_id, store_name
         ) VALUES ($1, $2, $3, $4, $5::numeric, $6, $7, $8, $9)
         RETURNING id, product_id, variant_id, quantity, price_snapshot, product_name, image_url, store_id, store_name, created_at, updated_at`,
        [
          uid,
          pid,
          variantKey,
          qty,
          price,
          body.productName ?? '',
          body.imageUrl ?? null,
          storeId,
          storeName,
        ],
      );
      const row = ins.rows[0];
      if (!row) throw new ServiceUnavailableException('cart insert failed');
      return { item: this.mapRow(row as Record<string, unknown>) };
    });
  }

  async patchItem(
    userId: string,
    lineId: string,
    body: { quantity: number },
  ): Promise<{ item: CartItemRow }> {
    const uid = userId.trim();
    const id = lineId.trim();
    if (!uid || !id) throw new BadRequestException('invalid');
    const qty = Math.floor(Number(body.quantity));
    if (!Number.isFinite(qty) || qty <= 0) throw new BadRequestException('invalid_quantity');

    return this.withClient(async (client) => {
      const sel = await client.query(
        `SELECT product_id, store_id FROM cart_items WHERE id = $1::uuid AND user_id = $2 LIMIT 1`,
        [id, uid],
      );
      if (sel.rows.length === 0) throw new NotFoundException();
      const productId = Number(sel.rows[0]['product_id'] ?? 0);
      const storeId = String(sel.rows[0]['store_id'] ?? 'ammarjo');
      await this.assertStockOk(client, productId, storeId);

      const u = await client.query(
        `UPDATE cart_items SET quantity = $3, updated_at = NOW()
         WHERE id = $1::uuid AND user_id = $2
         RETURNING id, product_id, variant_id, quantity, price_snapshot, product_name, image_url, store_id, store_name, created_at, updated_at`,
        [id, uid, qty],
      );
      const row = u.rows[0];
      if (!row) throw new NotFoundException();
      return { item: this.mapRow(row as Record<string, unknown>) };
    });
  }

  async removeItem(userId: string, lineId: string): Promise<{ ok: true }> {
    const uid = userId.trim();
    const id = lineId.trim();
    if (!uid || !id) throw new BadRequestException('invalid');
    return this.withClient(async (client) => {
      const r = await client.query(`DELETE FROM cart_items WHERE id = $1::uuid AND user_id = $2`, [id, uid]);
      if (r.rowCount === 0) throw new NotFoundException();
      return { ok: true as const };
    });
  }

  async clear(userId: string): Promise<{ ok: true }> {
    const uid = userId.trim();
    if (!uid) throw new BadRequestException('user required');
    await this.withClient(async (client) => {
      await client.query(`DELETE FROM cart_items WHERE user_id = $1`, [uid]);
    });
    return { ok: true as const };
  }
}
