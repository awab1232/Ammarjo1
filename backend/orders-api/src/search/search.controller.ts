import { createHash } from 'node:crypto';
import { Controller, Get, Query, ServiceUnavailableException, UseGuards } from '@nestjs/common';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { resolveSearchStoreIdForTenant } from '../identity/tenant-access';
import { CacheService } from '../infrastructure/cache/cache.service';
import { responseCacheTtlSeconds } from '../infrastructure/cache/cache.config';
import { AlgoliaProductsService } from './algolia-products.service';

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
    if (!this.algolia.isConfigured()) {
      throw new ServiceUnavailableException(
        'Product search is not configured (set ALGOLIA_APP_ID and API keys)',
      );
    }

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
}
