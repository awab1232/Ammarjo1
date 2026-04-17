import { Injectable, Logger } from '@nestjs/common';
import algoliasearch from 'algoliasearch';
import type { SearchClient, SearchIndex } from 'algoliasearch';

type AlgoliaStoreObject = {
  objectID: string;
  id: string;
  name: string;
  description?: string;
  storeType?: string;
  createdAt?: string;
};

type AlgoliaProductObject = {
  objectID: string;
  id: string;
  name: string;
  description?: string;
  storeId?: string;
  categoryId?: string;
  price?: number;
  createdAt?: string;
};

type AlgoliaCategoryObject = {
  objectID: string;
  id: string;
  name: string;
  storeId?: string;
  createdAt?: string;
};

@Injectable()
export class AlgoliaSyncService {
  private readonly logger = new Logger(AlgoliaSyncService.name);
  private readonly client: SearchClient | null;
  private readonly productsIndex: SearchIndex | null;
  private readonly storesIndex: SearchIndex | null;
  private readonly categoriesIndex: SearchIndex | null;

  constructor() {
    const enabled = (process.env.ALGOLIA_ENABLED ?? 'false').trim().toLowerCase() === 'true';
    const appId = process.env.ALGOLIA_APP_ID?.trim() || '';
    const apiKey = process.env.ALGOLIA_API_KEY?.trim() || '';
    const productsIndexName = process.env.ALGOLIA_INDEX_PRODUCTS?.trim() || 'ammarjo_products';
    const storesIndexName = process.env.ALGOLIA_INDEX_STORES?.trim() || 'ammarjo_stores';
    const categoriesIndexName =
      process.env.ALGOLIA_INDEX_CATEGORIES?.trim() || `${storesIndexName}_categories`;

    if (!enabled || !appId || !apiKey) {
      this.client = null;
      this.productsIndex = null;
      this.storesIndex = null;
      this.categoriesIndex = null;
      return;
    }

    try {
      this.client = algoliasearch(appId, apiKey);
      this.productsIndex = this.client.initIndex(productsIndexName);
      this.storesIndex = this.client.initIndex(storesIndexName);
      this.categoriesIndex = this.client.initIndex(categoriesIndexName);
    } catch {
      this.client = null;
      this.productsIndex = null;
      this.storesIndex = null;
      this.categoriesIndex = null;
    }
  }

  private isReady(): boolean {
    return this.client != null && this.productsIndex != null && this.storesIndex != null && this.categoriesIndex != null;
  }

  private logSyncFailure(entityType: 'store' | 'product' | 'category', entityId: string, error: unknown): void {
    this.logger.error(
      JSON.stringify({
        kind: 'algolia_sync_failed',
        entityType,
        entityId,
        error: error instanceof Error ? error.message : String(error),
      }),
    );
  }

  async syncStore(store: {
    id: string;
    name: string;
    description?: string;
    category?: string;
    createdAt?: string;
  }): Promise<void> {
    if (!this.isReady() || this.storesIndex == null) return;
    const object: AlgoliaStoreObject = {
      objectID: store.id,
      id: store.id,
      name: store.name,
      description: store.description || '',
      storeType: store.category || '',
      createdAt: store.createdAt,
    };
    await this.storesIndex.saveObject(object);
  }

  async syncProduct(product: {
    id: string;
    name: string;
    description?: string;
    storeId?: string | null;
    categoryId?: string | null;
    price?: number;
    createdAt?: string;
  }): Promise<void> {
    if (!this.isReady() || this.productsIndex == null) return;
    const object: AlgoliaProductObject = {
      objectID: product.id,
      id: product.id,
      name: product.name,
      description: product.description || '',
      storeId: product.storeId || undefined,
      categoryId: product.categoryId || undefined,
      price: product.price,
      createdAt: product.createdAt,
    };
    await this.productsIndex.saveObject(object);
  }

  async syncCategory(category: {
    id: string;
    name: string;
    storeId?: string | null;
    createdAt?: string;
  }): Promise<void> {
    if (!this.isReady() || this.categoriesIndex == null) return;
    const object: AlgoliaCategoryObject = {
      objectID: category.id,
      id: category.id,
      name: category.name,
      storeId: category.storeId || undefined,
      createdAt: category.createdAt,
    };
    await this.categoriesIndex.saveObject(object);
  }

  async deleteStore(id: string): Promise<void> {
    if (!this.isReady() || this.storesIndex == null) return;
    await this.storesIndex.deleteObject(id);
  }

  async deleteProduct(id: string): Promise<void> {
    if (!this.isReady() || this.productsIndex == null) return;
    await this.productsIndex.deleteObject(id);
  }

  async deleteCategory(id: string): Promise<void> {
    if (!this.isReady() || this.categoriesIndex == null) return;
    await this.categoriesIndex.deleteObject(id);
  }

  async safeSyncStore(store: {
    id: string;
    name: string;
    description?: string;
    category?: string;
    createdAt?: string;
  }): Promise<void> {
    try {
      await this.syncStore(store);
    } catch (error) {
      this.logSyncFailure('store', store.id, error);
    }
  }

  async safeSyncProduct(product: {
    id: string;
    name: string;
    description?: string;
    storeId?: string | null;
    categoryId?: string | null;
    price?: number;
    createdAt?: string;
  }): Promise<void> {
    try {
      await this.syncProduct(product);
    } catch (error) {
      this.logSyncFailure('product', product.id, error);
    }
  }

  async safeSyncCategory(category: {
    id: string;
    name: string;
    storeId?: string | null;
    createdAt?: string;
  }): Promise<void> {
    try {
      await this.syncCategory(category);
    } catch (error) {
      this.logSyncFailure('category', category.id, error);
    }
  }

  async safeDeleteStore(id: string): Promise<void> {
    try {
      await this.deleteStore(id);
    } catch (error) {
      this.logSyncFailure('store', id, error);
    }
  }

  async safeDeleteProduct(id: string): Promise<void> {
    try {
      await this.deleteProduct(id);
    } catch (error) {
      this.logSyncFailure('product', id, error);
    }
  }

  async safeDeleteCategory(id: string): Promise<void> {
    try {
      await this.deleteCategory(id);
    } catch (error) {
      this.logSyncFailure('category', id, error);
    }
  }
}
