import type { DomainEventEnvelope } from './domain-event.types';

/** One JSON line per event (structured logging). */
export function logDomainEventEmitted(env: DomainEventEnvelope): void {
  const line = JSON.stringify({
    kind: 'domain_event',
    event: env.name,
    entityId: env.entityId,
    ts: env.ts,
    payloadKeys: env.payload != null && typeof env.payload === 'object' ? Object.keys(env.payload as object) : [],
  });
  console.log(line);
}
