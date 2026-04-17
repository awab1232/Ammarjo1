import { BadRequestException, Body, Controller, Post, UseGuards } from '@nestjs/common';
import { InternalApiKeyGuard } from './internal-api-key.guard';
import { ProductSearchSyncService } from './product-search-sync.service';
import type { CatalogProductRow } from './product-search.types';

function parseBody(body: Record<string, unknown>): CatalogProductRow {
  const productId = Number(body.product_id ?? body.productId);
  if (!Number.isFinite(productId)) {
    throw new BadRequestException('product_id is required');
  }
  const priceRaw = body.price_numeric ?? body.priceNumeric ?? 0;
  const priceNum =
    typeof priceRaw === 'number' ? priceRaw : Number.parseFloat(String(priceRaw));
  const categoryRaw = body.category_ids ?? body.categoryIds;
  const category_ids: number[] = [];
  if (Array.isArray(categoryRaw)) {
    for (const e of categoryRaw) {
      const n = typeof e === 'number' ? e : Number.parseInt(String(e), 10);
      if (Number.isFinite(n)) {
        category_ids.push(n);
      }
    }
  }
  return {
    product_id: productId,
    store_id: String(body.store_id ?? body.storeId ?? 'ammarjo'),
    name: String(body.name ?? ''),
    description: String(body.description ?? ''),
    price_numeric: Number.isFinite(priceNum) ? priceNum : 0,
    currency: String(body.currency ?? 'JOD'),
    category_ids,
    image_url: body.image_url != null ? String(body.image_url) : body.imageUrl != null ? String(body.imageUrl) : null,
    stock_status: String(body.stock_status ?? body.stockStatus ?? 'instock'),
    searchable_text:
      body.searchable_text != null
        ? String(body.searchable_text)
        : body.searchableText != null
          ? String(body.searchableText)
          : null,
  };
}

/**
 * Internal: bulk reindex and single-record upsert (workers, ETL, admin).
 */
@Controller()
export class SearchInternalController {
  constructor(private readonly sync: ProductSearchSyncService) {}

  @Post('internal/search/reindex')
  @UseGuards(InternalApiKeyGuard)
  async reindex() {
    const out = await this.sync.fullReindexFromPostgres();
    return { ok: true, ...out };
  }

  @Post('internal/search/products')
  @UseGuards(InternalApiKeyGuard)
  async upsertProduct(@Body() body: Record<string, unknown>) {
    const row = parseBody(body);
    await this.sync.upsertProduct(row);
    return { ok: true, productId: row.product_id };
  }
}
