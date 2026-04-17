import { Injectable, Optional } from '@nestjs/common';
import { EventEmitter } from 'events';
import { performance } from 'node:perf_hooks';
import type { PoolClient } from 'pg';
import type { IEventBus } from '../architecture/contracts/i-event-bus';
import { DomainId } from '../architecture/domain-id';
import type { DomainEventName } from './domain-event-names';
import { isDomainEventName } from './domain-event-names';
import { logDomainEventEmitted } from './domain-event-logger';
import { isDebugEventsEnabled, isEventOutboxEnabled } from './event-outbox-config';
import type { DomainEventEnvelope } from './domain-event.types';
import { TenantContextService } from '../identity/tenant-context.service';
import { EventOutboxTracingService } from './event-outbox-tracing.service';
import { EventOutboxService } from './event-outbox.service';
import type { EventOutboxEmitMeta, EventOutboxRow } from './event-outbox.types';

export type DomainEventListener<T extends Record<string, unknown> = Record<string, unknown>> = (
  envelope: DomainEventEnvelope<T>,
) => void | Promise<void>;

function stripOutboxMeta(payload: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(payload)) {
    if (k.startsWith('_outbox_')) continue;
    out[k] = v;
  }
  return out;
}

/**
 * In-process event bus (no Kafka). With PostgreSQL outbox enabled, events are persisted
 * before delivery; a worker dispatches pending rows (emitAsync stays non-blocking for API).
 */
@Injectable()
export class DomainEventEmitterService implements IEventBus {
  readonly domainId = DomainId.Events;

  private readonly bus = new EventEmitter();

  constructor(
    private readonly outbox: EventOutboxService,
    @Optional() private readonly tracing?: EventOutboxTracingService,
    @Optional() private readonly tenant?: TenantContextService,
  ) {
    this.bus.setMaxListeners(64);
  }

  private shouldUseOutbox(): boolean {
    return isEventOutboxEnabled() && this.outbox.isReady();
  }

  subscribe<T extends Record<string, unknown> = Record<string, unknown>>(
    name: DomainEventName,
    listener: DomainEventListener<T>,
  ): void {
    this.bus.on(name, listener);
  }

  emitSync<T extends Record<string, unknown> = Record<string, unknown>>(
    name: DomainEventName,
    entityId: string,
    payload: T,
    meta?: EventOutboxEmitMeta,
  ): void {
    if (this.shouldUseOutbox()) {
      void this.persistThenDeliverSync(name, entityId, payload, meta);
      return;
    }
    const env = this.wrap(name, entityId, payload);
    logDomainEventEmitted(env);
    this.bus.emit(name, env);
  }

  emitAsync<T extends Record<string, unknown> = Record<string, unknown>>(
    name: DomainEventName,
    entityId: string,
    payload: T,
    meta?: EventOutboxEmitMeta,
  ): void {
    if (this.shouldUseOutbox()) {
      void this.persistAsyncOnly(name, entityId, payload, meta);
      return;
    }
    const env = this.wrap(name, entityId, payload);
    logDomainEventEmitted(env);
    setImmediate(() => {
      try {
        this.bus.emit(name, env);
      } catch (e) {
        console.error('[DomainEventEmitter] emit failed:', e);
      }
    });
  }

  dispatch<T extends Record<string, unknown> = Record<string, unknown>>(
    name: DomainEventName,
    entityId: string,
    payload: T,
    meta?: EventOutboxEmitMeta,
  ): void {
    const sync = process.env.DOMAIN_EVENTS_SYNC?.trim() === '1';
    if (sync) {
      this.emitSync(name, entityId, payload, meta);
    } else {
      this.emitAsync(name, entityId, payload, meta);
    }
  }

  /**
   * Transaction-safe outbox enqueue: call this before COMMIT with the same DB client.
   * Delivery happens asynchronously by worker after commit.
   */
  async enqueueInTransaction<T extends Record<string, unknown> = Record<string, unknown>>(
    client: PoolClient,
    name: DomainEventName,
    entityId: string,
    payload: T,
    meta?: EventOutboxEmitMeta,
  ): Promise<void> {
    const merged = this.mergeIdentityPayload(payload);
    if (!this.shouldUseOutbox()) {
      // Legacy fallback path when outbox is unavailable.
      const env = this.wrap(name, entityId, merged);
      logDomainEventEmitted(env);
      this.bus.emit(name, env);
      return;
    }
    await this.outbox.insertPendingWithClient(client, name, entityId, merged, meta);
  }

  /**
   * Deliver a claimed outbox row to subscribers (idempotent per event_id via DB status).
   * Public for [EventOutboxWorker].
   */
  deliverOutboxRow(row: EventOutboxRow): void {
    if (!isDomainEventName(row.event_type)) {
      throw new Error(`[DomainEventEmitter] unknown event_type: ${row.event_type}`);
    }
    const name = row.event_type;
    const payload = stripOutboxMeta(row.payload) as Record<string, unknown>;
    const env = this.wrap(name, row.entity_id, payload);
    env.ts = row.created_at.toISOString();
    const ot = this.tracing?.buildHandlerTraceContext(row);
    if (ot) {
      env.outboxTrace = ot;
    }
    logDomainEventEmitted(env);

    const run = (): void => {
      const t0 = performance.now();
      try {
        this.bus.emit(name, env);
      } finally {
        const handlerSyncMs = Math.round((performance.now() - t0) * 1000) / 1000;
        if (isDebugEventsEnabled()) {
          const line = JSON.stringify({
            kind: 'domain_event_debug',
            event_id: row.event_id,
            trace_id: row.trace_id,
            source_service: row.source_service,
            correlation_id: row.correlation_id,
            event: row.event_type,
            handlerSyncMs,
            payload: row.payload,
          });
          console.log(line);
        }
      }
    };
    if (this.tracing) {
      this.tracing.runHandlerSpan(row, run);
    } else {
      run();
    }
  }

  private mergeIdentityPayload<T extends Record<string, unknown>>(payload: T): T & Record<string, unknown> {
    const snap = this.tenant?.getSnapshot();
    if (!snap?.uid) {
      return payload;
    }
    return {
      ...payload,
      _identity: {
        tenantId: snap.tenantId,
        activeRole: snap.activeRole,
        requestTraceId: snap.requestTraceId,
        uid: snap.uid,
      },
    };
  }

  private async persistAsyncOnly<T extends Record<string, unknown>>(
    name: DomainEventName,
    entityId: string,
    payload: T,
    meta?: EventOutboxEmitMeta,
  ): Promise<void> {
    const merged = this.mergeIdentityPayload(payload);
    const row = await this.outbox.insertPending(name, entityId, merged, meta);
    if (!row) {
      const env = this.wrap(name, entityId, merged);
      logDomainEventEmitted(env);
      setImmediate(() => {
        try {
          this.bus.emit(name, env);
        } catch (e) {
          console.error('[DomainEventEmitter] emit failed:', e);
        }
      });
    }
  }

  private async persistThenDeliverSync<T extends Record<string, unknown>>(
    name: DomainEventName,
    entityId: string,
    payload: T,
    meta?: EventOutboxEmitMeta,
  ): Promise<void> {
    const merged = this.mergeIdentityPayload(payload);
    const row = await this.outbox.insertPending(name, entityId, merged, meta);
    if (!row) {
      const env = this.wrap(name, entityId, merged);
      logDomainEventEmitted(env);
      this.bus.emit(name, env);
      return;
    }
    const claimed = await this.outbox.claimOnePendingById(row.event_id);
    if (!claimed) {
      return;
    }
    try {
      this.deliverOutboxRow(claimed);
      await this.outbox.markProcessed(claimed.event_id);
    } catch (e) {
      await this.outbox.failProcessing(claimed.event_id, e);
    }
  }

  private wrap<T extends Record<string, unknown>>(
    name: DomainEventName,
    entityId: string,
    payload: T,
  ): DomainEventEnvelope<T> {
    return {
      name,
      entityId: String(entityId),
      ts: new Date().toISOString(),
      payload,
    };
  }
}
