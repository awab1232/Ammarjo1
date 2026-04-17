import { Injectable } from '@nestjs/common';
import { AlgoliaProductsService } from '../../search/algolia-products.service';
import { CatalogPgService } from '../../search/catalog-pg.service';
import { DomainEventNames } from '../domain-event-names';
import { DomainEventEmitterService } from '../domain-event-emitter.service';
import type { DomainEventEnvelope } from '../domain-event.types';
import type { ProductEventPayload } from '../domain-event.types';

/**
 * Keeps Algolia in sync with PostgreSQL catalog via domain events (decoupled from HTTP).
 */
@Injectable()
export class AlgoliaProductEventHandler {
  constructor(
    private readonly emitter: DomainEventEmitterService,
    private readonly algolia: AlgoliaProductsService,
    private readonly catalog: CatalogPgService,
  ) {}

  register(): void {
    const h = (env: DomainEventEnvelope<ProductEventPayload>) => {
      void this.syncFromEnvelope(env);
    };
    this.emitter.subscribe(DomainEventNames.PRODUCT_CREATED, h);
    this.emitter.subscribe(DomainEventNames.PRODUCT_UPDATED, h);
  }

  private async syncFromEnvelope(env: DomainEventEnvelope<ProductEventPayload>): Promise<void> {
    try {
      if (!this.algolia.isConfigured() || !this.catalog.isEnabled()) {
        return;
      }
      const id = Number.parseInt(env.entityId, 10);
      if (!Number.isFinite(id)) {
        return;
      }
      const row = await this.catalog.findById(id);
      if (row) {
        await this.algolia.saveObjectFromRow(row);
      }
    } catch (e) {
      console.error('[AlgoliaProductEventHandler] sync failed:', e);
    }
  }
}
