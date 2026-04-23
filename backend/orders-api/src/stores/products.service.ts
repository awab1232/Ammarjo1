import { ForbiddenException, Injectable, Logger, Optional } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Pool } from 'pg';
import { TenantContextService } from '../identity/tenant-context.service';
import { AlgoliaSyncService } from '../search/algolia-sync.service';
import { ProductVariantsService } from './product-variants.service';
import type { StoreProductRecord } from './stores.types';
import { logAuditJson } from '../common/audit-log';
import { resolvePublicUrl } from '../common/public-url';

@Injectable()
export class ProductsService {
  private readonly logger = new Logger(ProductsService.name);
  private readonly pool: Pool;
  private schemaReady = false;

  constructor(
    private readonly algoliaSync: AlgoliaSyncService,
    private readonly variants: ProductVariantsService,
    @Optional() private readonly tenant?: TenantContextService,
  ) {
    const connectionString = process.env.DATABASE_URL?.trim();
    if (!connectionString) {
      this.logger.error(
        'DATABASE_URL missing — ProductsService DB queries will fail at runtime until env is set.',
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

  private async ensureEnhancedSchema(): Promise<void> {
    if (this.schemaReady) return;
    await this.pool.query(`
      ALTER TABLE products ADD COLUMN IF NOT EXISTS sub_category_id uuid REFERENCES sub_categories(id) ON DELETE SET NULL;
      ALTER TABLE products ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT TRUE;
      ALTER TABLE products ADD COLUMN IF NOT EXISTS stock int DEFAULT 0;
      ALTER TABLE products ADD COLUMN IF NOT EXISTS image text;
      ALTER TABLE products ADD COLUMN IF NOT EXISTS is_boosted boolean NOT NULL DEFAULT false;
      ALTER TABLE products ADD COLUMN IF NOT EXISTS is_trending boolean NOT NULL DEFAULT false;
      ALTER TABLE products ADD COLUMN IF NOT EXISTS created_at timestamp DEFAULT NOW();
      CREATE INDEX IF NOT EXISTS idx_products_store ON products(store_id);
      CREATE INDEX IF NOT EXISTS idx_products_subcategory ON products(sub_category_id);
    `);
    this.schemaReady = true;
  }

  private logViolation(resourceId: string, action: string, reason: string): void {
    const { userId } = this.actor();
    this.logger.warn(
      JSON.stringify({
        kind: 'authorization_violation',
        userId,
        resourceId,
        resourceType: 'product',
        action,
        reason,
      }),
    );
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

  private async ensureWriteStoreOwnership(storeId: string, action: string): Promise<void> {
    const { userId, role, isPrivileged } = this.actor();
    if (isPrivileged) return;
    if (role !== 'store_owner') {
      this.logViolation(storeId, action, 'role_not_allowed');
      throw new ForbiddenException('NOT_OWNER');
    }
    const q = await this.pool.query(`SELECT owner_id FROM stores WHERE id = $1::uuid LIMIT 1`, [storeId.trim()]);
    if (q.rows.length === 0) {
      this.logViolation(storeId, action, 'store_not_found');
      throw new ForbiddenException('NOT_OWNER');
    }
    const ownerId = String((q.rows[0] as Record<string, unknown>).owner_id ?? '');
    if (!userId || ownerId !== userId) {
      this.logViolation(storeId, action, 'owner_mismatch');
      throw new ForbiddenException('NOT_OWNER');
    }
  }

  private async resolveOwnedStoreIdForProduct(productId: string, action: string): Promise<string> {
    const q = await this.pool.query(`SELECT store_id::text AS sid FROM products WHERE id = $1::uuid LIMIT 1`, [
      productId.trim(),
    ]);
    if (q.rows.length === 0) throw new ForbiddenException('NOT_OWNER');
    const storeId = String((q.rows[0] as Record<string, unknown>).sid ?? '');
    await this.ensureWriteStoreOwnership(storeId, action);
    return storeId;
  }

  private map(row: Record<string, unknown>): StoreProductRecord {
    return {
      id: String(row.id),
      storeId: String(row.store_id),
      categoryId: row.category_id != null ? String(row.category_id) : null,
      name: String(row.name ?? ''),
      description: String(row.description ?? ''),
      price: Number(row.display_price ?? row.price ?? 0),
      hasVariants: Boolean(row.has_variants),
      images: row.image_url ? [resolvePublicUrl(String(row.image_url))] : [],
      stock: Number(row.display_stock ?? 0),
      createdAt: new Date(String(row.created_at)).toISOString(),
    };
  }

  async list(storeId: string): Promise<{ items: StoreProductRecord[] }> {
    await this.ensureEnhancedSchema();
    await this.ensureStoreAccess(storeId, 'read');
    const q = await this.pool.query(
      `SELECT p.id, p.store_id, p.category_id, p.name, p.description, p.price, p.has_variants, p.image_url, p.created_at,
              COALESCE(
                (
                  SELECT pv.price
                  FROM product_variants pv
                  WHERE pv.product_id = p.id AND pv.is_default = true
                  ORDER BY pv.created_at ASC
                  LIMIT 1
                ),
                (
                  SELECT MIN(pv2.price)
                  FROM product_variants pv2
                  WHERE pv2.product_id = p.id
                ),
                p.price
              ) AS display_price,
              COALESCE(
                (
                  SELECT pv.stock
                  FROM product_variants pv
                  WHERE pv.product_id = p.id AND pv.is_default = true
                  ORDER BY pv.created_at ASC
                  LIMIT 1
                ),
                (
                  SELECT pv3.stock
                  FROM product_variants pv3
                  WHERE pv3.product_id = p.id
                  ORDER BY pv3.price ASC, pv3.created_at ASC
                  LIMIT 1
                ),
                0
              ) AS display_stock
       FROM products p
       WHERE p.store_id = $1::uuid
       ORDER BY p.created_at DESC`,
      [storeId.trim()],
    );
    return { items: q.rows.map((row) => this.map(row as Record<string, unknown>)) };
  }

  async create(
    storeId: string,
    input: {
      categoryId?: string;
      name: string;
      price: number;
      images?: string[];
      stock?: number;
      hasVariants?: boolean;
      variants?: Array<{
        sku?: string;
        price: number;
        stock: number;
        isDefault?: boolean;
        options: Array<{ optionType: 'color' | 'size' | 'weight' | 'dimension'; optionValue: string }>;
      }>;
    },
  ): Promise<StoreProductRecord> {
    await this.ensureEnhancedSchema();
    await this.ensureWriteStoreOwnership(storeId, 'create');
    const wantsVariants = input.hasVariants === true;
    if (wantsVariants && (!Array.isArray(input.variants) || input.variants.length === 0)) {
      throw new ForbiddenException('Product with hasVariants=true must include variants');
    }
    const q = await this.pool.query(
      `INSERT INTO products (id, store_id, category_id, name, description, price, has_variants, image_url, created_at)
       VALUES ($1::uuid, $2::uuid, $3::uuid, $4, '', $5, $6, $7, NOW())
       RETURNING id, store_id, category_id, name, description, price, has_variants, image_url, created_at`,
      [
        randomUUID(),
        storeId.trim(),
        input.categoryId?.trim() || null,
        input.name.trim(),
        Number(input.price),
        wantsVariants,
        input.images?.[0]?.trim() || '',
      ],
    );
    let created = this.map(q.rows[0] as Record<string, unknown>);
    if (wantsVariants && input.variants) {
      for (const variant of input.variants) {
        await this.variants.createForProduct(created.id, variant);
      }
      const withVariants = await this.list(storeId);
      const found = withVariants.items.find((x) => x.id === created.id);
      if (found) created = found;
    }
    await this.algoliaSync.safeSyncProduct({
      id: created.id,
      name: created.name,
      description: created.description,
      storeId: created.storeId,
      categoryId: created.categoryId,
      price: created.price,
      createdAt: created.createdAt,
    });
    this.logSensitiveAudit('CREATE_PRODUCT', 'product', created.id);
    return created;
  }

  async patch(
    storeId: string,
    productId: string,
    input: {
      categoryId?: string;
      name?: string;
      price?: number;
      images?: string[];
      stock?: number;
      hasVariants?: boolean;
      variants?: Array<{
        sku?: string;
        price: number;
        stock: number;
        isDefault?: boolean;
        options: Array<{ optionType: 'color' | 'size' | 'weight' | 'dimension'; optionValue: string }>;
      }>;
    },
  ): Promise<StoreProductRecord> {
    await this.ensureEnhancedSchema();
    await this.ensureWriteStoreOwnership(storeId, 'update');
    const currentQ = await this.pool.query(
      `SELECT has_variants FROM products WHERE id = $1::uuid AND store_id = $2::uuid LIMIT 1`,
      [productId.trim(), storeId.trim()],
    );
    if (currentQ.rows.length === 0) {
      throw new ForbiddenException('Access denied');
    }
    const currentHasVariants = Boolean((currentQ.rows[0] as Record<string, unknown>).has_variants);
    const nextHasVariants = input.hasVariants ?? currentHasVariants;
    if (nextHasVariants && (!input.variants || input.variants.length === 0)) {
      const existing = await this.variants.listByProduct(productId.trim());
      if (existing.items.length === 0) {
        throw new ForbiddenException('Product with hasVariants=true must include variants');
      }
    }
    const q = await this.pool.query(
      `UPDATE products
       SET category_id = COALESCE($3::uuid, category_id),
           name = COALESCE($4, name),
           price = COALESCE($5, price),
           image_url = COALESCE($6, image_url),
           has_variants = COALESCE($7, has_variants)
       WHERE id = $1::uuid AND store_id = $2::uuid
       RETURNING id, store_id, category_id, name, description, price, has_variants, image_url, created_at`,
      [
        productId.trim(),
        storeId.trim(),
        input.categoryId?.trim() || null,
        input.name?.trim() || null,
        input.price ?? null,
        input.images?.[0]?.trim() || null,
        input.hasVariants ?? null,
      ],
    );
    if (q.rows.length === 0) {
      this.logViolation(productId, 'update', 'query_scope_denied');
      throw new ForbiddenException('Access denied');
    }
    let patched = this.map(q.rows[0] as Record<string, unknown>);
    if (input.variants != null) {
      const existing = await this.variants.listByProduct(productId.trim());
      for (const row of existing.items) {
        await this.variants.deleteVariant(row.id);
      }
      for (const variant of input.variants) {
        await this.variants.createForProduct(productId.trim(), variant);
      }
      const relist = await this.list(storeId);
      const found = relist.items.find((x) => x.id === productId.trim());
      if (found) patched = found;
    }
    await this.algoliaSync.safeSyncProduct({
      id: patched.id,
      name: patched.name,
      description: patched.description,
      storeId: patched.storeId,
      categoryId: patched.categoryId,
      price: patched.price,
      createdAt: patched.createdAt,
    });
    this.logSensitiveAudit('UPDATE_PRODUCT', 'product', patched.id);
    return patched;
  }

  async delete(storeId: string, productId: string): Promise<{ deleted: true }> {
    await this.ensureEnhancedSchema();
    await this.ensureWriteStoreOwnership(storeId, 'delete');
    const q = await this.pool.query(`DELETE FROM products WHERE id = $1::uuid AND store_id = $2::uuid`, [
      productId.trim(),
      storeId.trim(),
    ]);
    if ((q.rowCount ?? 0) === 0) {
      this.logViolation(productId, 'delete', 'query_scope_denied');
      throw new ForbiddenException('Access denied');
    }
    await this.algoliaSync.safeDeleteProduct(productId.trim());
    this.logSensitiveAudit('DELETE_PRODUCT', 'product', productId.trim());
    return { deleted: true };
  }

  async listPublic(limit = 100): Promise<{ items: StoreProductRecord[] }> {
    await this.ensureEnhancedSchema();
    const safeLimit = Math.min(Math.max(1, limit), 200);
    const q = await this.pool.query(
      `SELECT p.id, p.store_id, p.category_id, p.name, p.description, p.price, p.has_variants, p.image_url, p.created_at,
              COALESCE(
                (SELECT pv.price FROM product_variants pv WHERE pv.product_id = p.id AND pv.is_default = true ORDER BY pv.created_at ASC LIMIT 1),
                (SELECT MIN(pv2.price) FROM product_variants pv2 WHERE pv2.product_id = p.id),
                p.price
              ) AS display_price,
              COALESCE(
                (SELECT pv.stock FROM product_variants pv WHERE pv.product_id = p.id AND pv.is_default = true ORDER BY pv.created_at ASC LIMIT 1),
                (SELECT pv3.stock FROM product_variants pv3 WHERE pv3.product_id = p.id ORDER BY pv3.price ASC, pv3.created_at ASC LIMIT 1),
                0
              ) AS display_stock
       FROM products p
       INNER JOIN stores s ON s.id = p.store_id
       WHERE s.status = 'approved'
       ORDER BY p.created_at DESC
       LIMIT $1`,
      [safeLimit],
    );
    return { items: q.rows.map((row) => this.map(row as Record<string, unknown>)) };
  }

  async getPublicById(productId: string): Promise<StoreProductRecord> {
    await this.ensureEnhancedSchema();
    const q = await this.pool.query(
      `SELECT p.id, p.store_id, p.category_id, p.name, p.description, p.price, p.has_variants, p.image_url, p.created_at,
              COALESCE(
                (SELECT pv.price FROM product_variants pv WHERE pv.product_id = p.id AND pv.is_default = true ORDER BY pv.created_at ASC LIMIT 1),
                (SELECT MIN(pv2.price) FROM product_variants pv2 WHERE pv2.product_id = p.id),
                p.price
              ) AS display_price,
              COALESCE(
                (SELECT pv.stock FROM product_variants pv WHERE pv.product_id = p.id AND pv.is_default = true ORDER BY pv.created_at ASC LIMIT 1),
                (SELECT pv3.stock FROM product_variants pv3 WHERE pv3.product_id = p.id ORDER BY pv3.price ASC, pv3.created_at ASC LIMIT 1),
                0
              ) AS display_stock
       FROM products p
       INNER JOIN stores s ON s.id = p.store_id
       WHERE p.id = $1::uuid AND s.status = 'approved'
       LIMIT 1`,
      [productId.trim()],
    );
    if (q.rows.length === 0) throw new ForbiddenException('Access denied');
    return this.map(q.rows[0] as Record<string, unknown>);
  }

  async patchById(
    productId: string,
    input: {
      categoryId?: string;
      name?: string;
      price?: number;
      images?: string[];
      stock?: number;
      hasVariants?: boolean;
      variants?: Array<{
        sku?: string;
        price: number;
        stock: number;
        isDefault?: boolean;
        options: Array<{ optionType: 'color' | 'size' | 'weight' | 'dimension'; optionValue: string }>;
      }>;
    },
  ): Promise<StoreProductRecord> {
    await this.ensureEnhancedSchema();
    const q = await this.pool.query(`SELECT store_id::text AS sid FROM products WHERE id = $1::uuid LIMIT 1`, [productId.trim()]);
    if (q.rows.length === 0) throw new ForbiddenException('Access denied');
    const storeId = String((q.rows[0] as Record<string, unknown>).sid ?? '');
    return this.patch(storeId, productId, input);
  }

  async deleteById(productId: string): Promise<{ deleted: true }> {
    await this.ensureEnhancedSchema();
    const q = await this.pool.query(`SELECT store_id::text AS sid FROM products WHERE id = $1::uuid LIMIT 1`, [productId.trim()]);
    if (q.rows.length === 0) throw new ForbiddenException('Access denied');
    const storeId = String((q.rows[0] as Record<string, unknown>).sid ?? '');
    return this.delete(storeId, productId);
  }

  async filterProducts(input: {
    subCategoryId?: string;
    storeId?: string;
    sectionId?: string;
    search?: string;
    minPrice?: number;
    maxPrice?: number;
    limit?: number;
    offset?: number;
  }): Promise<{ items: Array<Record<string, unknown>>; total: number }> {
    await this.ensureEnhancedSchema();
    const where: string[] = [`p.is_active = TRUE`];
    const values: unknown[] = [];
    let n = 1;
    if (input.storeId?.trim()) {
      where.push(`p.store_id = $${n++}::uuid`);
      values.push(input.storeId.trim());
    }
    if (input.subCategoryId?.trim()) {
      where.push(`p.sub_category_id = $${n++}::uuid`);
      values.push(input.subCategoryId.trim());
    }
    if (input.sectionId?.trim()) {
      where.push(`sc.home_section_id = $${n++}::uuid`);
      values.push(input.sectionId.trim());
    }
    if (input.search?.trim()) {
      where.push(`LOWER(p.name) LIKE $${n++}`);
      values.push(`%${input.search.trim().toLowerCase()}%`);
    }
    if (Number.isFinite(input.minPrice)) {
      where.push(`p.price >= $${n++}`);
      values.push(input.minPrice);
    }
    if (Number.isFinite(input.maxPrice)) {
      where.push(`p.price <= $${n++}`);
      values.push(input.maxPrice);
    }
    const safeLimit = Math.min(Math.max(1, Number(input.limit ?? 30)), 200);
    const safeOffset = Math.max(0, Number(input.offset ?? 0));
    const whereSql = where.join(' AND ');
    const totalQ = await this.pool.query(
      `SELECT COUNT(*)::int AS n
       FROM products p
       LEFT JOIN sub_categories sc ON sc.id = p.sub_category_id
       WHERE ${whereSql}`,
      values,
    );
    const total = Number(totalQ.rows[0]?.['n'] ?? 0);
    const itemsQ = await this.pool.query(
      `SELECT p.id::text, p.store_id::text AS store_id, p.sub_category_id::text AS sub_category_id,
              p.name, p.description, p.price, COALESCE(NULLIF(p.image, ''), p.image_url) AS image,
              COALESCE(p.stock, 0)::int AS stock,
              p.is_boosted AS "isBoosted", p.is_trending AS "isTrending"
       FROM products p
       LEFT JOIN sub_categories sc ON sc.id = p.sub_category_id
       WHERE ${whereSql}
       ORDER BY p.created_at DESC
       LIMIT $${n++} OFFSET $${n++}`,
      [...values, safeLimit, safeOffset],
    );
    return { items: itemsQ.rows as Array<Record<string, unknown>>, total };
  }

  async createAdminProduct(input: {
    storeId: string;
    subCategoryId?: string | null;
    name: string;
    description?: string;
    price?: number;
    image?: string | null;
    stock?: number;
    isActive?: boolean;
  }): Promise<{ id: string }> {
    await this.ensureEnhancedSchema();
    await this.ensureWriteStoreOwnership(input.storeId, 'create_admin_product');
    const r = await this.pool.query(
      `INSERT INTO products (id, store_id, sub_category_id, name, description, price, image, stock, is_active, created_at)
       VALUES (gen_random_uuid(), $1::uuid, $2::uuid, $3, $4, $5, $6, $7, $8, NOW())
       RETURNING id::text`,
      [
        input.storeId.trim(),
        input.subCategoryId?.trim() || null,
        input.name.trim(),
        input.description?.trim() || '',
        Number(input.price ?? 0),
        input.image ?? null,
        Number(input.stock ?? 0),
        input.isActive ?? true,
      ],
    );
    const id = String(r.rows[0]?.['id'] ?? '');
    this.logSensitiveAudit('CREATE_PRODUCT', 'product', id);
    return { id };
  }

  async patchAdminProduct(
    id: string,
    input: {
      storeId?: string;
      subCategoryId?: string | null;
      name?: string;
      description?: string;
      price?: number;
      image?: string | null;
      stock?: number;
      isActive?: boolean;
    },
  ): Promise<{ ok: true }> {
    await this.ensureEnhancedSchema();
    const ownedStoreId = await this.resolveOwnedStoreIdForProduct(id, 'patch_admin_product');
    if (input.storeId !== undefined) {
      const nextStoreId = input.storeId.trim();
      if (nextStoreId !== ownedStoreId) {
        await this.ensureWriteStoreOwnership(nextStoreId, 'patch_admin_product_target_store');
      }
    }
    const patches: string[] = [];
    const values: unknown[] = [];
    let n = 1;
    if (input.storeId !== undefined) {
      patches.push(`store_id = $${n++}::uuid`);
      values.push(input.storeId.trim());
    }
    if (input.subCategoryId !== undefined) {
      patches.push(`sub_category_id = $${n++}::uuid`);
      values.push(input.subCategoryId?.trim() || null);
    }
    if (input.name !== undefined) {
      patches.push(`name = $${n++}`);
      values.push(input.name.trim());
    }
    if (input.description !== undefined) {
      patches.push(`description = $${n++}`);
      values.push(input.description.trim());
    }
    if (input.price !== undefined) {
      patches.push(`price = $${n++}`);
      values.push(Number(input.price));
    }
    if (input.image !== undefined) {
      patches.push(`image = $${n++}`);
      values.push(input.image);
    }
    if (input.stock !== undefined) {
      patches.push(`stock = $${n++}`);
      values.push(Number(input.stock));
    }
    if (input.isActive !== undefined) {
      patches.push(`is_active = $${n++}`);
      values.push(input.isActive);
    }
    if (patches.length === 0) throw new ForbiddenException('no_fields');
    values.push(id.trim());
    const r = await this.pool.query(`UPDATE products SET ${patches.join(', ')} WHERE id = $${n}::uuid`, values);
    if ((r.rowCount ?? 0) === 0) throw new ForbiddenException('not_found');
    this.logSensitiveAudit('UPDATE_PRODUCT', 'product', id.trim());
    return { ok: true as const };
  }

  async deleteAdminProduct(id: string): Promise<{ ok: true }> {
    await this.ensureEnhancedSchema();
    await this.resolveOwnedStoreIdForProduct(id, 'delete_admin_product');
    const r = await this.pool.query(`DELETE FROM products WHERE id = $1::uuid`, [id.trim()]);
    if ((r.rowCount ?? 0) === 0) throw new ForbiddenException('not_found');
    this.logSensitiveAudit('DELETE_PRODUCT', 'product', id.trim());
    return { ok: true as const };
  }

  async bulkUpdateStock(items: Array<{ id: string; stock: number }>): Promise<{ ok: true }> {
    await this.ensureEnhancedSchema();
    for (const item of items) {
      await this.resolveOwnedStoreIdForProduct(item.id, 'bulk_update_stock');
      await this.pool.query(`UPDATE products SET stock = $2 WHERE id = $1::uuid`, [item.id.trim(), Number(item.stock)]);
      this.logSensitiveAudit('UPDATE_PRODUCT_STOCK', 'product', item.id.trim());
    }
    return { ok: true as const };
  }
}
