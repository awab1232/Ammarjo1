import { Injectable, Logger, Optional } from '@nestjs/common';
import { ConsistencyPolicyService } from '../architecture/consistency/consistency-policy.service';
import algoliasearch from 'algoliasearch';
import type { SearchIndex } from 'algoliasearch';
import type { AlgoliaProductRecord, CatalogProductRow } from './product-search.types';

function rowToAlgolia(r: CatalogProductRow): AlgoliaProductRecord {
  const price =
    typeof r.price_numeric === 'number'
      ? r.price_numeric
      : Number.parseFloat(String(r.price_numeric)) || 0;
  const rec: AlgoliaProductRecord = {
    objectID: String(r.product_id),
    productId: r.product_id,
    storeId: r.store_id,
    name: r.name,
    description: r.description ?? '',
    price_numeric: price,
    currency: r.currency || 'JOD',
    categoryIds: Array.isArray(r.category_ids) ? r.category_ids : [],
    imageUrl: r.image_url,
    stockStatus: r.stock_status || 'instock',
  };
  const st = r.searchable_text?.trim();
  if (st) {
    rec.searchableText = st;
  }
  return rec;
}

@Injectable()
export class AlgoliaProductsService {
  private readonly logger = new Logger(AlgoliaProductsService.name);
  private client: ReturnType<typeof algoliasearch> | null = null;
  private readonly enabled: boolean;
  private readonly appId: string | null;
  private readonly searchKey: string | null;
  private readonly adminKey: string | null;

  constructor(@Optional() private readonly consistencyPolicy?: ConsistencyPolicyService) {
    this.enabled = (process.env.ALGOLIA_ENABLED ?? 'false').trim().toLowerCase() === 'true';
    this.appId = process.env.ALGOLIA_APP_ID?.trim() || null;
    this.searchKey = process.env.ALGOLIA_SEARCH_KEY?.trim() || process.env.ALGOLIA_SEARCH_API_KEY?.trim() || null;
    this.adminKey =
      process.env.ALGOLIA_API_KEY?.trim() ||
      process.env.ALGOLIA_WRITE_API_KEY?.trim() ||
      process.env.ALGOLIA_ADMIN_API_KEY?.trim() ||
      null;
    if (!this.enabled) {
      this.logger.log('Algolia disabled - skipping sync');
      return;
    }
    if (!this.appId || !this.adminKey) {
      throw new Error('ALGOLIA_ENABLED=true but ALGOLIA_APP_ID/ALGOLIA_API_KEY are missing');
    }
    if (this.appId && this.adminKey) {
      try {
        this.client = algoliasearch(this.appId, this.adminKey);
      } catch (e) {
        console.error('[AlgoliaProductsService] client init failed:', e);
        this.client = null;
      }
    }
  }

  isConfigured(): boolean {
    return this.enabled && this.client != null;
  }

  /** Search-only client (browser-safe key) — optional for server-side search using search key. */
  private searchClient(): ReturnType<typeof algoliasearch> | null {
    if (!this.appId) return null;
    const key = this.searchKey || this.adminKey;
    if (!key) return null;
    try {
      return algoliasearch(this.appId, key);
    } catch {
      return null;
    }
  }

  indexName(): string {
    return (
      process.env.ALGOLIA_INDEX_PRODUCTS?.trim() ||
      process.env.ALGOLIA_PRODUCTS_INDEX?.trim() ||
      process.env.ALGOLIA_INDEX_NAME?.trim() ||
      'ammarjo'
    );
  }

  indexNameForSort(sort: string | undefined): string {
    const base = this.indexName();
    if (sort === 'price_asc') {
      return process.env.ALGOLIA_PRODUCTS_INDEX_PRICE_ASC?.trim() || base;
    }
    if (sort === 'price_desc') {
      return process.env.ALGOLIA_PRODUCTS_INDEX_PRICE_DESC?.trim() || base;
    }
    return base;
  }

  storesIndexName(): string {
    const explicit =
      process.env.ALGOLIA_INDEX_STORES?.trim() ||
      process.env.ALGOLIA_STORES_INDEX?.trim();
    if (explicit) return explicit;
    const base = process.env.ALGOLIA_INDEX_NAME?.trim();
    if (base) return `${base}_stores`;
    return 'ammarjo_stores';
  }

  private initIndex(name: string): SearchIndex | null {
    const c = this.searchClient();
    if (!c) return null;
    return c.initIndex(name);
  }

  async configureIndexSettings(): Promise<void> {
    if (!this.client) return;
    const index = this.client.initIndex(this.indexName());
    await index.setSettings({
      searchableAttributes: ['name', 'description', 'searchableText'],
      attributesForFaceting: ['filterOnly(storeId)', 'filterOnly(categoryIds)'],
      attributesToRetrieve: [
        'objectID',
        'productId',
        'storeId',
        'name',
        'description',
        'price_numeric',
        'currency',
        'categoryIds',
        'imageUrl',
        'stockStatus',
        'searchableText',
      ],
    });
  }

  async saveObjects(records: AlgoliaProductRecord[]): Promise<void> {
    if (!this.client || records.length === 0) return;
    const index = this.client.initIndex(this.indexName());
    const chunks = 1000;
    for (let i = 0; i < records.length; i += chunks) {
      const part = records.slice(i, i + chunks);
      await index.saveObjects(part);
    }
  }

  async saveObjectFromRow(row: CatalogProductRow): Promise<void> {
    await this.saveObjects([rowToAlgolia(row)]);
  }

  async deleteObject(productId: number): Promise<void> {
    if (!this.client) return;
    const index = this.client.initIndex(this.indexName());
    await index.deleteObject(String(productId));
  }

  rowToRecord(row: CatalogProductRow): AlgoliaProductRecord {
    return rowToAlgolia(row);
  }

  async searchProducts(params: {
    query: string;
    page: number;
    hitsPerPage: number;
    storeId?: string;
    categoryIds?: number[];
    minPrice?: number;
    maxPrice?: number;
    sort?: string;
  }): Promise<unknown> {
    const indexName = this.indexNameForSort(params.sort);
    const index = this.initIndex(indexName);
    if (!index) {
      throw new Error('Algolia is disabled or not configured');
    }

    this.consistencyPolicy?.logSearchReadAuthoritative('AlgoliaProductsService.searchProducts');

    const facetFilters: string[][] = [];
    if (params.storeId) {
      facetFilters.push([`storeId:${params.storeId}`]);
    }
    if (params.categoryIds && params.categoryIds.length > 0) {
      facetFilters.push(params.categoryIds.map((id) => `categoryIds:${id}`));
    }

    const numericFilters: string[] = [];
    if (params.minPrice != null && Number.isFinite(params.minPrice)) {
      numericFilters.push(`price_numeric>=${params.minPrice}`);
    }
    if (params.maxPrice != null && Number.isFinite(params.maxPrice)) {
      numericFilters.push(`price_numeric<=${params.maxPrice}`);
    }

    const res = await index.search(params.query || '', {
      page: params.page,
      hitsPerPage: Math.min(Math.max(1, params.hitsPerPage), 100),
      facetFilters: facetFilters.length > 0 ? facetFilters : undefined,
      numericFilters: numericFilters.length > 0 ? numericFilters : undefined,
    });
    return res;
  }

  async searchStores(params: {
    query: string;
    page: number;
    hitsPerPage: number;
    category?: string;
    city?: string;
  }): Promise<unknown> {
    const index = this.initIndex(this.storesIndexName());
    if (!index) {
      throw new Error('Algolia is disabled or not configured');
    }

    const facetFilters: string[][] = [];
    if (params.category?.trim()) {
      facetFilters.push([`category:${params.category.trim()}`]);
    }
    if (params.city?.trim()) {
      facetFilters.push([`city:${params.city.trim()}`]);
    }

    const res = await index.search(params.query || '', {
      page: params.page,
      hitsPerPage: Math.min(Math.max(1, params.hitsPerPage), 100),
      facetFilters: facetFilters.length > 0 ? facetFilters : undefined,
    });
    return res;
  }
}
