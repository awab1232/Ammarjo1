import { BadRequestException, ForbiddenException, Injectable, Logger, Optional } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Pool } from 'pg';
import { TenantContextService } from '../identity/tenant-context.service';
import type {
  ProductVariantOptionRecord,
  ProductVariantOptionType,
  ProductVariantRecord,
} from './stores.types';

type VariantOptionInput = {
  optionType: ProductVariantOptionType;
  optionValue: string;
};

type VariantWriteInput = {
  sku?: string;
  price: number;
  stock: number;
  isDefault?: boolean;
  options: VariantOptionInput[];
};

@Injectable()
export class ProductVariantsService {
  private readonly logger = new Logger(ProductVariantsService.name);
  private readonly pool: Pool;

  constructor(@Optional() private readonly tenant?: TenantContextService) {
    const connectionString = process.env.DATABASE_URL?.trim();
    if (!connectionString) {
      this.logger.error(
        'DATABASE_URL missing — ProductVariantsService DB queries will fail at runtime until env is set.',
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

  private validateVariantInput(input: VariantWriteInput): void {
    if (!Number.isFinite(Number(input.price))) {
      throw new BadRequestException('Variant price is required');
    }
    if (!Number.isFinite(Number(input.stock))) {
      throw new BadRequestException('Variant stock is required');
    }
    if (!Array.isArray(input.options) || input.options.length === 0) {
      throw new BadRequestException('Variant must include at least one option');
    }
    for (const option of input.options) {
      if (!option.optionType || !option.optionValue?.trim()) {
        throw new BadRequestException('Variant option_type and option_value are required');
      }
      if (!['color', 'size', 'weight', 'dimension'].includes(option.optionType)) {
        throw new BadRequestException('Invalid variant option_type');
      }
    }
  }

  private logVariantEvent(kind: 'variant_created' | 'variant_updated' | 'variant_deleted', data: Record<string, unknown>): void {
    this.logger.log(JSON.stringify({ kind, ...data }));
  }

  private async assertStoreOwnerAccessByProductId(productId: string, action: string): Promise<void> {
    const { userId, role, isPrivileged } = this.actor();
    if (isPrivileged) return;
    const q = await this.pool.query(
      `SELECT s.owner_id, s.status
       FROM products p
       JOIN stores s ON s.id = p.store_id
       WHERE p.id = $1::uuid
       LIMIT 1`,
      [productId.trim()],
    );
    if (q.rows.length === 0) throw new BadRequestException('Product not found');
    const ownerId = String((q.rows[0] as Record<string, unknown>).owner_id ?? '');
    const status = String((q.rows[0] as Record<string, unknown>).status ?? '');
    if (role === 'store_owner') {
      if (!userId || ownerId !== userId) throw new ForbiddenException('Access denied');
      return;
    }
    if (status !== 'approved') throw new ForbiddenException('Access denied');
    if (!userId) throw new ForbiddenException('Access denied');
    if (action !== 'read') throw new ForbiddenException('Access denied');
  }

  private async assertWholesaleOwnerAccessByProductId(productId: string): Promise<void> {
    const { userId, role, isPrivileged } = this.actor();
    if (isPrivileged) return;
    const q = await this.pool.query(
      `SELECT w.owner_id
       FROM wholesale_products p
       JOIN wholesalers w ON w.id = p.wholesaler_id
       WHERE p.id = $1::uuid
       LIMIT 1`,
      [productId.trim()],
    );
    if (q.rows.length === 0) throw new BadRequestException('Wholesale product not found');
    const isWholesaleStoreOwner = role === 'store_owner' && String(this.tenant?.getSnapshot().storeType ?? '').trim().toLowerCase() === 'wholesale';
    if ((!isWholesaleStoreOwner && role !== 'wholesaler_owner') || !userId || String((q.rows[0] as Record<string, unknown>).owner_id ?? '') !== userId) {
      throw new ForbiddenException('Access denied');
    }
  }

  async listByProduct(productId: string): Promise<{ items: ProductVariantRecord[] }> {
    await this.assertStoreOwnerAccessByProductId(productId, 'read');
    const variantsQ = await this.pool.query(
      `SELECT id, product_id, wholesale_product_id, sku, price, stock, is_default, created_at
       FROM product_variants
       WHERE product_id = $1::uuid
       ORDER BY is_default DESC, created_at ASC`,
      [productId.trim()],
    );
    const variantIds = variantsQ.rows.map((row) => String((row as Record<string, unknown>).id));
    let optionsByVariant = new Map<string, ProductVariantOptionRecord[]>();
    if (variantIds.length > 0) {
      const optionsQ = await this.pool.query(
        `SELECT id, variant_id, option_type, option_value
         FROM product_variant_options
         WHERE variant_id::text = ANY($1::text[])
         ORDER BY id ASC`,
        [variantIds],
      );
      optionsByVariant = new Map<string, ProductVariantOptionRecord[]>();
      for (const row of optionsQ.rows) {
        const r = row as Record<string, unknown>;
        const variantId = String(r.variant_id);
        const item: ProductVariantOptionRecord = {
          id: String(r.id),
          variantId,
          optionType: String(r.option_type) as ProductVariantOptionType,
          optionValue: String(r.option_value ?? ''),
        };
        const existing = optionsByVariant.get(variantId) ?? [];
        existing.push(item);
        optionsByVariant.set(variantId, existing);
      }
    }
    return {
      items: variantsQ.rows.map((row) => {
        const r = row as Record<string, unknown>;
        const id = String(r.id);
        return {
          id,
          productId: r.product_id != null ? String(r.product_id) : null,
          wholesaleProductId: r.wholesale_product_id != null ? String(r.wholesale_product_id) : null,
          sku: r.sku != null ? String(r.sku) : null,
          price: Number(r.price ?? 0),
          stock: Number(r.stock ?? 0),
          isDefault: Boolean(r.is_default),
          createdAt: new Date(String(r.created_at)).toISOString(),
          options: optionsByVariant.get(id) ?? [],
        } as ProductVariantRecord;
      }),
    };
  }

  async listByWholesaleProduct(productId: string): Promise<{ items: ProductVariantRecord[] }> {
    await this.assertWholesaleOwnerAccessByProductId(productId);
    const variantsQ = await this.pool.query(
      `SELECT id, product_id, wholesale_product_id, sku, price, stock, is_default, created_at
       FROM product_variants
       WHERE wholesale_product_id = $1::uuid
       ORDER BY is_default DESC, created_at ASC`,
      [productId.trim()],
    );
    const variantIds = variantsQ.rows.map((row) => String((row as Record<string, unknown>).id));
    let optionsByVariant = new Map<string, ProductVariantOptionRecord[]>();
    if (variantIds.length > 0) {
      const optionsQ = await this.pool.query(
        `SELECT id, variant_id, option_type, option_value
         FROM product_variant_options
         WHERE variant_id::text = ANY($1::text[])
         ORDER BY id ASC`,
        [variantIds],
      );
      for (const row of optionsQ.rows) {
        const r = row as Record<string, unknown>;
        const variantId = String(r.variant_id);
        const item: ProductVariantOptionRecord = {
          id: String(r.id),
          variantId,
          optionType: String(r.option_type) as ProductVariantOptionType,
          optionValue: String(r.option_value ?? ''),
        };
        const existing = optionsByVariant.get(variantId) ?? [];
        existing.push(item);
        optionsByVariant.set(variantId, existing);
      }
    }
    return {
      items: variantsQ.rows.map((row) => {
        const r = row as Record<string, unknown>;
        const id = String(r.id);
        return {
          id,
          productId: r.product_id != null ? String(r.product_id) : null,
          wholesaleProductId: r.wholesale_product_id != null ? String(r.wholesale_product_id) : null,
          sku: r.sku != null ? String(r.sku) : null,
          price: Number(r.price ?? 0),
          stock: Number(r.stock ?? 0),
          isDefault: Boolean(r.is_default),
          createdAt: new Date(String(r.created_at)).toISOString(),
          options: optionsByVariant.get(id) ?? [],
        } as ProductVariantRecord;
      }),
    };
  }

  async createForProduct(productId: string, input: VariantWriteInput): Promise<ProductVariantRecord> {
    await this.assertStoreOwnerAccessByProductId(productId, 'create');
    this.validateVariantInput(input);
    const variantId = randomUUID();
    await this.pool.query('BEGIN');
    try {
      if (input.isDefault) {
        await this.pool.query(`UPDATE product_variants SET is_default = false WHERE product_id = $1::uuid`, [
          productId.trim(),
        ]);
      }
      await this.pool.query(
        `INSERT INTO product_variants (id, product_id, sku, price, stock, is_default, created_at)
         VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6, NOW())`,
        [
          variantId,
          productId.trim(),
          input.sku?.trim() || null,
          Number(input.price),
          Number(input.stock),
          Boolean(input.isDefault),
        ],
      );
      for (const opt of input.options) {
        await this.pool.query(
          `INSERT INTO product_variant_options (id, variant_id, option_type, option_value)
           VALUES ($1::uuid, $2::uuid, $3, $4)`,
          [randomUUID(), variantId, opt.optionType, opt.optionValue.trim()],
        );
      }
      await this.pool.query(`UPDATE products SET has_variants = true WHERE id = $1::uuid`, [productId.trim()]);
      await this.pool.query('COMMIT');
    } catch (e) {
      await this.pool.query('ROLLBACK');
      throw e;
    }
    const listed = await this.listByProduct(productId);
    const row = listed.items.find((x) => x.id === variantId);
    if (!row) throw new BadRequestException('Failed to create variant');
    this.logVariantEvent('variant_created', { variantId, productId: productId.trim(), scope: 'store' });
    return row;
  }

  async createForWholesaleProduct(productId: string, input: VariantWriteInput): Promise<ProductVariantRecord> {
    await this.assertWholesaleOwnerAccessByProductId(productId);
    this.validateVariantInput(input);
    const variantId = randomUUID();
    await this.pool.query('BEGIN');
    try {
      if (input.isDefault) {
        await this.pool.query(`UPDATE product_variants SET is_default = false WHERE wholesale_product_id = $1::uuid`, [
          productId.trim(),
        ]);
      }
      await this.pool.query(
        `INSERT INTO product_variants (id, wholesale_product_id, sku, price, stock, is_default, created_at)
         VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6, NOW())`,
        [
          variantId,
          productId.trim(),
          input.sku?.trim() || null,
          Number(input.price),
          Number(input.stock),
          Boolean(input.isDefault),
        ],
      );
      for (const opt of input.options) {
        await this.pool.query(
          `INSERT INTO product_variant_options (id, variant_id, option_type, option_value)
           VALUES ($1::uuid, $2::uuid, $3, $4)`,
          [randomUUID(), variantId, opt.optionType, opt.optionValue.trim()],
        );
      }
      await this.pool.query(`UPDATE wholesale_products SET has_variants = true WHERE id = $1::uuid`, [productId.trim()]);
      await this.pool.query('COMMIT');
    } catch (e) {
      await this.pool.query('ROLLBACK');
      throw e;
    }
    const listed = await this.listByWholesaleProduct(productId);
    const row = listed.items.find((x) => x.id === variantId);
    if (!row) throw new BadRequestException('Failed to create variant');
    this.logVariantEvent('variant_created', {
      variantId,
      wholesaleProductId: productId.trim(),
      scope: 'wholesale',
    });
    return row;
  }

  async patchVariant(variantId: string, input: Partial<VariantWriteInput>): Promise<ProductVariantRecord> {
    const q = await this.pool.query(
      `SELECT product_id, wholesale_product_id FROM product_variants WHERE id = $1::uuid LIMIT 1`,
      [variantId.trim()],
    );
    if (q.rows.length === 0) throw new BadRequestException('Variant not found');
    const target = q.rows[0] as Record<string, unknown>;
    const productId = target.product_id != null ? String(target.product_id) : '';
    const wholesaleProductId = target.wholesale_product_id != null ? String(target.wholesale_product_id) : '';
    if (productId) {
      await this.assertStoreOwnerAccessByProductId(productId, 'update');
    } else if (wholesaleProductId) {
      await this.assertWholesaleOwnerAccessByProductId(wholesaleProductId);
    } else {
      throw new BadRequestException('Variant target is invalid');
    }
    if (input.options != null) {
      if (!Array.isArray(input.options) || input.options.length === 0) {
        throw new BadRequestException('Variant options cannot be empty');
      }
      for (const option of input.options) {
        if (!option.optionType || !option.optionValue?.trim()) {
          throw new BadRequestException('Variant option_type and option_value are required');
        }
      }
    }
    await this.pool.query('BEGIN');
    try {
      if (input.isDefault === true) {
        await this.pool.query(`UPDATE product_variants SET is_default = false WHERE product_id = $1::uuid`, [productId]);
      }
      await this.pool.query(
        `UPDATE product_variants
         SET sku = COALESCE($2, sku),
             price = COALESCE($3, price),
             stock = COALESCE($4, stock),
             is_default = COALESCE($5, is_default)
         WHERE id = $1::uuid`,
        [
          variantId.trim(),
          input.sku?.trim() ?? null,
          input.price != null ? Number(input.price) : null,
          input.stock != null ? Number(input.stock) : null,
          input.isDefault != null ? Boolean(input.isDefault) : null,
        ],
      );
      if (input.options != null) {
        await this.pool.query(`DELETE FROM product_variant_options WHERE variant_id = $1::uuid`, [variantId.trim()]);
        for (const option of input.options) {
          await this.pool.query(
            `INSERT INTO product_variant_options (id, variant_id, option_type, option_value)
             VALUES ($1::uuid, $2::uuid, $3, $4)`,
            [randomUUID(), variantId.trim(), option.optionType, option.optionValue.trim()],
          );
        }
      }
      await this.pool.query('COMMIT');
    } catch (e) {
      await this.pool.query('ROLLBACK');
      throw e;
    }
    const listed = productId
      ? await this.listByProduct(productId)
      : await this.listByWholesaleProduct(wholesaleProductId);
    const row = listed.items.find((x) => x.id === variantId.trim());
    if (!row) throw new BadRequestException('Variant not found');
    this.logVariantEvent('variant_updated', {
      variantId: variantId.trim(),
      productId: productId || null,
      wholesaleProductId: wholesaleProductId || null,
    });
    return row;
  }

  async deleteVariant(variantId: string): Promise<{ deleted: true }> {
    const q = await this.pool.query(
      `SELECT product_id, wholesale_product_id FROM product_variants WHERE id = $1::uuid LIMIT 1`,
      [variantId.trim()],
    );
    if (q.rows.length === 0) return { deleted: true };
    const target = q.rows[0] as Record<string, unknown>;
    const productId = target.product_id != null ? String(target.product_id) : '';
    const wholesaleProductId = target.wholesale_product_id != null ? String(target.wholesale_product_id) : '';
    if (productId) {
      await this.assertStoreOwnerAccessByProductId(productId, 'delete');
    } else if (wholesaleProductId) {
      await this.assertWholesaleOwnerAccessByProductId(wholesaleProductId);
    } else {
      throw new BadRequestException('Variant target is invalid');
    }
    const variantIdTrimmed = variantId.trim();
    await this.pool.query(`DELETE FROM product_variants WHERE id = $1::uuid`, [variantIdTrimmed]);
    if (productId) {
      const leftQ = await this.pool.query(`SELECT 1 FROM product_variants WHERE product_id = $1::uuid LIMIT 1`, [productId]);
      if (leftQ.rows.length === 0) {
        await this.pool.query(`UPDATE products SET has_variants = false WHERE id = $1::uuid`, [productId]);
      }
    }
    if (wholesaleProductId) {
      const leftQ = await this.pool.query(
        `SELECT 1 FROM product_variants WHERE wholesale_product_id = $1::uuid LIMIT 1`,
        [wholesaleProductId],
      );
      if (leftQ.rows.length === 0) {
        await this.pool.query(`UPDATE wholesale_products SET has_variants = false WHERE id = $1::uuid`, [wholesaleProductId]);
      }
    }
    this.logVariantEvent('variant_deleted', {
      variantId: variantIdTrimmed,
      productId: productId || null,
      wholesaleProductId: wholesaleProductId || null,
    });
    return { deleted: true };
  }
}
