import { Injectable } from '@nestjs/common';
import { DomainEventNames } from '../domain-event-names';
import { DomainEventEmitterService } from '../domain-event-emitter.service';
import type { DomainEventEnvelope } from '../domain-event.types';

const ALL: Array<(typeof DomainEventNames)[keyof typeof DomainEventNames]> = [
  DomainEventNames.ORDER_CREATED,
  DomainEventNames.ORDER_UPDATED,
  DomainEventNames.PRODUCT_CREATED,
  DomainEventNames.PRODUCT_UPDATED,
  DomainEventNames.STOCK_UPDATED,
];

/**
 * Reserved for future analytics / data warehouse / external webhooks (no-op).
 */
@Injectable()
export class AnalyticsPlaceholderHandler {
  constructor(private readonly emitter: DomainEventEmitterService) {}

  register(): void {
    for (const name of ALL) {
      this.emitter.subscribe(name, (env: DomainEventEnvelope) => {
        void env;
        /* Future: forward to warehouse, Amplitude, etc. */
      });
    }
  }
}
