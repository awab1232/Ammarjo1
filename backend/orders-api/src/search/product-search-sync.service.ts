import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { DomainEventNames } from '../events/domain-event-names';
import { DomainEventEmitterService } from '../events/domain-event-emitter.service';
import { AlgoliaProductsService } from './algolia-products.service';
import { CatalogPgService } from './catalog-pg.service';
import type { CatalogProductRow } from './product-search.types';

@Injectable()
export class ProductSearchSyncService {
  constructor(
    private readonly catalog: CatalogPgService,
    private readonly algolia: AlgoliaProductsService,
    private readonly events: DomainEventEmitterService,
  ) {}

  /** Batch sync all rows from PostgreSQL to Algolia (idempotent). */
  async fullReindexFromPostgres(): Promise<{ indexed: number; totalPg: number }> {
    if ((process.env.ALGOLIA_ENABLED ?? 'false').trim().toLowerCase() !== 'true') {
      return { indexed: 0, totalPg: 0 };
    }
    if (!this.catalog.isEnabled()) {
      return { indexed: 0, totalPg: 0 };
    }
    if (!this.algolia.isConfigured()) {
      throw new Error('Algolia is not configured');
    }
    const totalPg = await this.catalog.count();
    let indexed = 0;
    const batch = 500;
    for (let offset = 0; offset < totalPg; offset += batch) {
      const rows = await this.catalog.findAllForSync(batch, offset);
      if (rows.length === 0) break;
      const records = rows.map((r) => this.algolia.rowToRecord(r));
      await this.algolia.saveObjects(records);
      indexed += rows.length;
    }
    if (process.env.ALGOLIA_CONFIGURE_INDEX_SETTINGS === '1') {
      await this.algolia.configureIndexSettings();
    }
    return { indexed, totalPg };
  }

  /**
   * Upsert PostgreSQL, emit catalog events (Algolia sync via [AlgoliaProductEventHandler]).
   */
  async upsertProduct(row: CatalogProductRow): Promise<void> {
    if ((process.env.ALGOLIA_ENABLED ?? 'false').trim().toLowerCase() !== 'true') {
      return;
    }
    if (!this.catalog.isEnabled()) {
      throw new Error('PostgreSQL catalog is not configured');
    }
    if (!this.algolia.isConfigured()) {
      throw new Error('Algolia is not configured');
    }
    const op = await this.catalog.upsertReturningOp(row);
    const eventTraceId = randomUUID();
    const correlationId = String(row.product_id);
    const eventMeta = {
      traceId: eventTraceId,
      sourceService: 'catalog' as const,
      correlationId,
    };
    const productPayload = {
      storeId: row.store_id,
      productId: row.product_id,
      stockStatus: row.stock_status,
    };
    if (op === 'insert') {
      this.events.dispatch(DomainEventNames.PRODUCT_CREATED, String(row.product_id), productPayload, eventMeta);
    } else {
      this.events.dispatch(DomainEventNames.PRODUCT_UPDATED, String(row.product_id), productPayload, eventMeta);
    }
    this.events.dispatch(
      DomainEventNames.STOCK_UPDATED,
      String(row.product_id),
      {
        productId: row.product_id,
        storeId: row.store_id,
        stockStatus: row.stock_status || 'instock',
      },
      eventMeta,
    );
  }
}
