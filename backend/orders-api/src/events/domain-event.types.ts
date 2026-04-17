import type { DomainEventName } from './domain-event-names';

/**
 * W3C traceparent-compatible ids derived from outbox `trace_id` + `event_id` (no extra DB columns).
 * Use `outboxTrace.traceparent` on downstream HTTP as `traceparent` header when tracing is enabled.
 */
export type OutboxTraceContext = {
  traceId: string;
  spanId: string;
  traceparent: string;
};

export type DomainEventEnvelope<T = Record<string, unknown>> = {
  name: DomainEventName;
  /** Primary id for the entity (orderId, productId as string, etc.). */
  entityId: string;
  ts: string;
  payload: T;
  /** Present when EVENT_OUTBOX_TRACING=1 and trace is sampled (for cross-service propagation). */
  outboxTrace?: OutboxTraceContext;
};

export type OrderEventPayload = {
  userId?: string;
  storeId?: string;
  writeSource?: string;
};

export type ProductEventPayload = {
  storeId: string;
  productId: number;
  stockStatus?: string;
};

export type StockEventPayload = {
  productId: number;
  storeId: string;
  stockStatus: string;
};
