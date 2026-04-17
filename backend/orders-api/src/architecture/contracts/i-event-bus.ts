import type { DomainEventName } from '../../events/domain-event-names';
import type { EventOutboxEmitMeta } from '../../events/event-outbox.types';
import type { DomainId } from '../domain-id';

/** Cross-domain integration must prefer the event bus + outbox. */
export interface IEventBus {
  readonly domainId: DomainId;
  dispatch(
    name: DomainEventName,
    entityId: string,
    payload: Record<string, unknown>,
    meta?: EventOutboxEmitMeta,
  ): void;
}
