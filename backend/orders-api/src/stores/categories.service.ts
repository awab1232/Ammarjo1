import { ForbiddenException, Injectable, Logger, Optional } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Pool } from 'pg';
import { TenantContextService } from '../identity/tenant-context.service';
import { AlgoliaSyncService } from '../search/algolia-sync.service';
import type { StoreCategoryRecord } from './stores.types';

@Injectable()
export class CategoriesService {
  private readonly logger = new Logger(CategoriesService.name);
  private readonly pool: Pool;

  constructor(
    private readonly algoliaSync: AlgoliaSyncService,
    @Optional() private readonly tenant?: TenantContextService,
  ) {
    const connectionString = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
    if (!connectionString) throw new Error('DATABASE_URL or ORDERS_DATABASE_URL is required for CategoriesService');
    this.pool = new Pool({ connectionString });
  }

  private actor() {
    const snap = this.tenant?.getSnapshot();
    const userId = snap?.uid?.trim() || null;
    const role = snap?.activeRole?.trim() || 'customer';
    const isPrivileged = role === 'admin' || role === 'system_internal';
    return { userId, role, isPrivileged };
  }

  private logViolation(resourceId: string, action: string, reason: string): void {
    const { userId } = this.actor();
    this.logger.warn(
      JSON.stringify({
        kind: 'authorization_violation',
        userId,
        resourceId,
        resourceType: 'category',
        action,
        reason,
      }),
    );
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
        this.logViolation(storeId, action, 'owner_mismatch');
        throw new ForbiddenException('Access denied');
      }
      return;
    }
    if (status !== 'approved') {
      this.logViolation(storeId, action, 'store_not_public');
      throw new ForbiddenException('Access denied');
    }
  }

  private map(row: Record<string, unknown>): StoreCategoryRecord {
    return {
      id: String(row.id),
      storeId: String(row.store_id),
      name: String(row.name ?? ''),
      orderIndex: Number(row.sort_order ?? 0),
      createdAt: new Date(String(row.created_at)).toISOString(),
    };
  }

  async list(storeId: string): Promise<{ items: StoreCategoryRecord[] }> {
    await this.ensureStoreAccess(storeId, 'read');
    const q = await this.pool.query(
      `SELECT id, store_id, name, sort_order, created_at FROM categories WHERE store_id = $1::uuid ORDER BY sort_order ASC, created_at ASC`,
      [storeId.trim()],
    );
    return { items: q.rows.map((row) => this.map(row as Record<string, unknown>)) };
  }

  async create(
    storeId: string,
    input: { name: string; orderIndex?: number },
  ): Promise<StoreCategoryRecord> {
    await this.ensureStoreAccess(storeId, 'create');
    const id = randomUUID();
    const q = await this.pool.query(
      `INSERT INTO categories (id, store_id, name, sort_order, created_at) VALUES ($1::uuid, $2::uuid, $3, $4, NOW()) RETURNING id, store_id, name, sort_order, created_at`,
      [id, storeId.trim(), input.name.trim(), Number(input.orderIndex ?? 0)],
    );
    const created = this.map(q.rows[0] as Record<string, unknown>);
    await this.algoliaSync.safeSyncCategory({
      id: created.id,
      name: created.name,
      storeId: created.storeId,
      createdAt: created.createdAt,
    });
    return created;
  }

  async patch(
    storeId: string,
    categoryId: string,
    input: { name?: string; orderIndex?: number },
  ): Promise<StoreCategoryRecord> {
    await this.ensureStoreAccess(storeId, 'update');
    const q = await this.pool.query(
      `UPDATE categories
       SET name = COALESCE($3, name),
           sort_order = COALESCE($4, sort_order)
       WHERE id = $1::uuid AND store_id = $2::uuid
       RETURNING id, store_id, name, sort_order, created_at`,
      [categoryId.trim(), storeId.trim(), input.name?.trim() || null, input.orderIndex ?? null],
    );
    if (q.rows.length === 0) {
      this.logViolation(categoryId, 'update', 'query_scope_denied');
      throw new ForbiddenException('Access denied');
    }
    const patched = this.map(q.rows[0] as Record<string, unknown>);
    await this.algoliaSync.safeSyncCategory({
      id: patched.id,
      name: patched.name,
      storeId: patched.storeId,
      createdAt: patched.createdAt,
    });
    return patched;
  }

  async delete(storeId: string, categoryId: string): Promise<{ deleted: true }> {
    await this.ensureStoreAccess(storeId, 'delete');
    const q = await this.pool.query(`DELETE FROM categories WHERE id = $1::uuid AND store_id = $2::uuid`, [
      categoryId.trim(),
      storeId.trim(),
    ]);
    if ((q.rowCount ?? 0) === 0) {
      this.logViolation(categoryId, 'delete', 'query_scope_denied');
      throw new ForbiddenException('Access denied');
    }
    await this.algoliaSync.safeDeleteCategory(categoryId.trim());
    return { deleted: true };
  }

  async listPublic(limit = 200): Promise<{ items: StoreCategoryRecord[] }> {
    const safeLimit = Math.min(Math.max(1, limit), 500);
    const q = await this.pool.query(
      `SELECT c.id, c.store_id, c.name, c.sort_order, c.created_at
       FROM categories c
       INNER JOIN stores s ON s.id = c.store_id
       WHERE s.status = 'approved'
       ORDER BY c.sort_order ASC, c.created_at ASC
       LIMIT $1`,
      [safeLimit],
    );
    return { items: q.rows.map((row) => this.map(row as Record<string, unknown>)) };
  }

  async patchById(
    categoryId: string,
    input: { name?: string; orderIndex?: number },
  ): Promise<StoreCategoryRecord> {
    const q = await this.pool.query(`SELECT store_id::text AS sid FROM categories WHERE id = $1::uuid LIMIT 1`, [categoryId.trim()]);
    if (q.rows.length === 0) throw new ForbiddenException('Access denied');
    const storeId = String((q.rows[0] as Record<string, unknown>).sid ?? '');
    return this.patch(storeId, categoryId, input);
  }

  async deleteById(categoryId: string): Promise<{ deleted: true }> {
    const q = await this.pool.query(`SELECT store_id::text AS sid FROM categories WHERE id = $1::uuid LIMIT 1`, [categoryId.trim()]);
    if (q.rows.length === 0) throw new ForbiddenException('Access denied');
    const storeId = String((q.rows[0] as Record<string, unknown>).sid ?? '');
    return this.delete(storeId, categoryId);
  }
}
