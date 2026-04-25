import { createHash } from 'node:crypto';
import { Controller, Get, Query, ServiceUnavailableException, UseGuards } from '@nestjs/common';
import { Pool } from 'pg';
import { buildPgPoolConfig } from '../infrastructure/database/pg-ssl';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { resolveSearchStoreIdForTenant } from '../identity/tenant-access';
import { CacheService } from '../infrastructure/cache/cache.service';
import { responseCacheTtlSeconds } from '../infrastructure/cache/cache.config';
import { AlgoliaProductsService } from './algolia-products.service';

let _catalogSearchPool: Pool | null | undefined;
function catalogSearchPool(): Pool | null {
  if (_catalogSearchPool === undefined) {
    const url = process.env.DATABASE_URL?.trim();
    _catalogSearchPool = url
      ? new Pool(
          buildPgPoolConfig(url, {
            max: 2,
            idleTimeoutMillis: 30_000,
          }),
        )
      : null;
  }
  return _catalogSearchPool;
}

/**
 * Public product search backed by Algolia (PostgreSQL remains source of truth for catalog rows).
 */
@Controller()
export class SearchController {
  constructor(
    private readonly algolia: AlgoliaProductsService,
    private readonly cache: CacheService,
  ) {}

  @Get('search/products')
  @UseGuards(TenantContextGuard, ApiPolicyGuard)
  @ApiPolicy({ auth: false, tenant: 'optional', rateLimit: { rpm: 600 } })
  async searchProducts(
    @Query('q') q?: string,
    @Query('page') pageRaw?: string,
    @Query('hitsPerPage') hitsPerPageRaw?: string,
    @Query('storeId') storeId?: string,
    @Query('category') category?: string,
    @Query('minPrice') minPriceRaw?: string,
    @Query('maxPrice') maxPriceRaw?: string,
    @Query('sort') sort?: string,
  ) {
    const page = Math.max(0, Number.parseInt(pageRaw ?? '0', 10) || 0);
    const hitsPerPage = Math.min(100, Math.max(1, Number.parseInt(hitsPerPageRaw ?? '20', 10) || 20));

    let categoryIds: number[] | undefined;
    if (category != null && String(category).trim() !== '') {
      categoryIds = String(category)
        .split(',')
        .map((s) => Number.parseInt(s.trim(), 10))
        .filter((n) => Number.isFinite(n));
      if (categoryIds.length === 0) {
        categoryIds = undefined;
      }
    }

    const minPrice =
      minPriceRaw != null && minPriceRaw !== '' ? Number.parseFloat(minPriceRaw) : undefined;
    const maxPrice =
      maxPriceRaw != null && maxPriceRaw !== '' ? Number.parseFloat(maxPriceRaw) : undefined;

    const sortNorm = sort?.trim().toLowerCase();
    let sortParam: string | undefined;
    if (sortNorm === 'price' || sortNorm === 'price_asc') {
      sortParam = 'price_asc';
    } else if (sortNorm === 'price_desc') {
      sortParam = 'price_desc';
    } else {
      sortParam = undefined;
    }

    const scopedStoreId = resolveSearchStoreIdForTenant(storeId);

    if (!this.algolia.isConfigured()) {
      return this.searchProductsPostgresFallback({
        q: q?.trim() ?? '',
        page,
        hitsPerPage,
        storeId: scopedStoreId,
      });
    }

    let cacheKey: string | null = null;
    if (this.cache.isCacheActive()) {
      const stable = {
        q: q?.trim() ?? '',
        page,
        hitsPerPage,
        storeId: scopedStoreId,
        categoryIds: categoryIds ?? [],
        minPrice: minPrice != null && Number.isFinite(minPrice) ? minPrice : null,
        maxPrice: maxPrice != null && Number.isFinite(maxPrice) ? maxPrice : null,
        sort: sortParam ?? null,
      };
      cacheKey = `search:${createHash('sha256').update(JSON.stringify(stable)).digest('hex').slice(0, 32)}`;
      const hit = await this.cache.getJson<Record<string, unknown>>(cacheKey);
      if (hit != null) {
        return hit;
      }
    }

    const result = await this.algolia.searchProducts({
      query: q?.trim() ?? '',
      page,
      hitsPerPage,
      storeId: scopedStoreId,
      categoryIds,
      minPrice: minPrice != null && Number.isFinite(minPrice) ? minPrice : undefined,
      maxPrice: maxPrice != null && Number.isFinite(maxPrice) ? maxPrice : undefined,
      sort: sortParam,
    });

    const body = {
      engine: 'algolia' as const,
      index: this.algolia.indexNameForSort(sortParam),
      ...((result as object) ?? {}),
    };

    if (cacheKey != null) {
      await this.cache.setJson(cacheKey, body, responseCacheTtlSeconds());
    }

    return body;
  }

  @Get('search/stores')
  @UseGuards(TenantContextGuard, ApiPolicyGuard)
  @ApiPolicy({ auth: false, tenant: 'optional', rateLimit: { rpm: 600 } })
  async searchStores(
    @Query('q') q?: string,
    @Query('page') pageRaw?: string,
    @Query('hitsPerPage') hitsPerPageRaw?: string,
    @Query('category') category?: string,
    @Query('city') city?: string,
  ) {
    if (!this.algolia.isConfigured()) {
      throw new ServiceUnavailableException(
        'Store search is not configured (set ALGOLIA_APP_ID and API keys)',
      );
    }

    const page = Math.max(0, Number.parseInt(pageRaw ?? '0', 10) || 0);
    const hitsPerPage = Math.min(100, Math.max(1, Number.parseInt(hitsPerPageRaw ?? '20', 10) || 20));

    let cacheKey: string | null = null;
    if (this.cache.isCacheActive()) {
      const stable = {
        q: q?.trim() ?? '',
        page,
        hitsPerPage,
        category: category?.trim() ?? '',
        city: city?.trim() ?? '',
      };
      cacheKey = `search:stores:${createHash('sha256').update(JSON.stringify(stable)).digest('hex').slice(0, 32)}`;
      const hit = await this.cache.getJson<Record<string, unknown>>(cacheKey);
      if (hit != null) {
        return hit;
      }
    }

    const result = await this.algolia.searchStores({
      query: q?.trim() ?? '',
      page,
      hitsPerPage,
      category: category?.trim(),
      city: city?.trim(),
    });

    const body = {
      engine: 'algolia' as const,
      index: this.algolia.storesIndexName(),
      ...((result as object) ?? {}),
    };

    if (cacheKey != null) {
      await this.cache.setJson(cacheKey, body, responseCacheTtlSeconds());
    }

    return body;
  }

  @Get('search')
  @UseGuards(TenantContextGuard, ApiPolicyGuard)
  @ApiPolicy({ auth: false, tenant: 'optional', rateLimit: { rpm: 600 } })
  async searchUnified(
    @Query('q') q?: string,
    @Query('filters') filters?: string,
  ) {
    const category = filters?.trim() || undefined;
    return this.searchProducts(q, '0', '20', undefined, category, undefined, undefined, undefined);
  }

  private async searchProductsPostgresFallback(params: {
    q: string;
    page: number;
    hitsPerPage: number;
    storeId: string | undefined;
  }): Promise<Record<string, unknown>> {
    const pool = catalogSearchPool();
    if (!pool) {
      throw new ServiceUnavailableException('Product search: database not configured for catalog fallback');
    }
    const q = params.q.trim();
    const limit = Math.min(100, Math.max(1, params.hitsPerPage));
    const offset = params.page * limit;
    const storeFilter = params.storeId?.trim() || null;
    if (q.length === 0) {
      return { engine: 'postgres' as const, hits: [], nbHits: 0, page: params.page, nbPages: 0 };
    }
    const r = await pool.query<{
      product_id: string | number;
      store_id: string;
      name: string;
      description: string | null;
      price_numeric: string | number | null;
      image_url: string | null;
      stock_status: string | null;
    }>(
      `SELECT product_id, store_id::text AS store_id, name, description,
              price_numeric, image_url, stock_status
         FROM catalog_products
        WHERE stock_status IS DISTINCT FROM 'outofstock'
          AND (
            name ILIKE ('%' || $1::text || '%')
            OR COALESCE(description, '') ILIKE ('%' || $1::text || '%')
          )
          AND ($2::text IS NULL OR btrim($2) = '' OR store_id::text = $2)
        ORDER BY updated_at DESC NULLS LAST
        LIMIT $3 OFFSET $4`,
      [q, storeFilter, limit, offset],
    );
    const rows = r.rows;
    const hits = rows.map((row) => ({
      objectID: String(row.product_id),
      productId: typeof row.product_id === 'number' ? row.product_id : Number.parseInt(String(row.product_id), 10),
      storeId: row.store_id,
      name: row.name,
      description: row.description ?? '',
      price_numeric:
        row.price_numeric != null ? Number.parseFloat(String(row.price_numeric)) : 0,
      stockStatus: row.stock_status || 'instock',
      imageUrl: row.image_url,
    }));
    return {
      engine: 'postgres' as const,
      hits,
      nbHits: hits.length,
      page: params.page,
      nbPages: hits.length < limit ? params.page : params.page + 1,
    };
  }
}
