import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { appendFile } from 'node:fs';
import { createHash } from 'node:crypto';
import {
  eventOutboxTracingExportBatchSize,
  eventOutboxTracingExportFlushMs,
  eventOutboxTracingJsonFilePath,
  eventOutboxTracingJsonStdoutEnabled,
  eventOutboxTracingOtlpHttpEndpoint,
  eventOutboxTracingQueueMax,
  eventOutboxTracingSampleRate,
  eventOutboxTracingScopeName,
  eventOutboxTracingServiceName,
  isEventOutboxTracingEnabled,
} from './event-outbox-tracing.config';
import {
  deriveSpanIdHex,
  hexToOtlpBase64,
  normalizeOtelTraceId,
  spanChainForRow,
  traceparentV00,
} from './event-outbox-tracing.ids';
import type { OutboxTraceContext } from './domain-event.types';
import type { EventOutboxRow } from './event-outbox.types';

type AttrKV = { key: string; value: { stringValue?: string; intValue?: string; boolValue?: boolean } };

type OtlpSpanJson = {
  traceId: string;
  spanId: string;
  parentSpanId?: string;
  name: string;
  kind: number;
  startTimeUnixNano: string;
  endTimeUnixNano: string;
  attributes: AttrKV[];
};

function shouldSampleTraceId(traceIdHex: string): boolean {
  if (!isEventOutboxTracingEnabled()) {
    return false;
  }
  const rate = eventOutboxTracingSampleRate();
  if (rate >= 1) {
    return true;
  }
  if (rate <= 0) {
    return false;
  }
  const h = createHash('sha256').update(traceIdHex).digest();
  const v = h.readUInt32BE(0) / 0xffffffff;
  return v < rate;
}

function attrString(key: string, v: string): AttrKV {
  return { key, value: { stringValue: v } };
}

function attrInt(key: string, v: number): AttrKV {
  return { key, value: { intValue: String(Math.trunc(v)) } };
}

function attrBool(key: string, v: boolean): AttrKV {
  return { key, value: { boolValue: v } };
}

@Injectable()
export class EventOutboxTracingService implements OnModuleDestroy {
  private readonly queue: OtlpSpanJson[] = [];
  private flushTimer: ReturnType<typeof setTimeout> | null = null;
  private flushing = false;
  private readonly apiGatewayDurationsMs: number[] = [];

  private hasAnyExporter(): boolean {
    return (
      eventOutboxTracingJsonStdoutEnabled() ||
      Boolean(eventOutboxTracingJsonFilePath()) ||
      Boolean(eventOutboxTracingOtlpHttpEndpoint())
    );
  }

  /** Span export (OTLP / NDJSON) — separate from trace context propagation on the envelope. */
  private shouldRecordSpans(): boolean {
    return isEventOutboxTracingEnabled() && this.hasAnyExporter();
  }

  private enqueue(span: OtlpSpanJson): void {
    const max = eventOutboxTracingQueueMax();
    if (this.queue.length >= max) {
      this.queue.splice(0, Math.floor(max * 0.1));
    }
    this.queue.push(span);
    this.scheduleFlush();
  }

  private scheduleFlush(): void {
    if (this.flushTimer != null) {
      return;
    }
    this.flushTimer = setTimeout(() => {
      this.flushTimer = null;
      void this.flush();
    }, eventOutboxTracingExportFlushMs());
  }

  private async flush(): Promise<void> {
    if (this.flushing || this.queue.length === 0) {
      return;
    }
    this.flushing = true;
    try {
      const batch = eventOutboxTracingExportBatchSize();
      while (this.queue.length > 0) {
        const chunk = this.queue.splice(0, batch);
        await this.exportChunk(chunk);
      }
    } finally {
      this.flushing = false;
      if (this.queue.length > 0) {
        this.scheduleFlush();
      }
    }
  }

  private async exportChunk(spans: OtlpSpanJson[]): Promise<void> {
    const jsonPath = eventOutboxTracingJsonFilePath();
    if (eventOutboxTracingJsonStdoutEnabled()) {
      for (const s of spans) {
        const line = JSON.stringify({
          ...this.spanToPlain(s),
          resource: { 'service.name': eventOutboxTracingServiceName() },
        });
        process.stdout.write(`${line}\n`);
      }
    }
    if (jsonPath) {
      const block = spans.map((s) => JSON.stringify(this.spanToPlain(s))).join('\n') + '\n';
      await new Promise<void>((resolve, reject) => {
        appendFile(jsonPath, block, (err) => (err ? reject(err) : resolve()));
      }).catch((e) => console.error('[EventOutboxTracing] json file write failed:', e));
    }
    const otlpBase = eventOutboxTracingOtlpHttpEndpoint();
    if (otlpBase && spans.length > 0) {
      const url = `${otlpBase.replace(/\/$/, '')}/v1/traces`;
      const body = this.buildOtlpBody(spans);
      try {
        const res = await fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body),
        });
        if (!res.ok) {
          console.error('[EventOutboxTracing] OTLP export failed:', res.status, await res.text());
        }
      } catch (e) {
        console.error('[EventOutboxTracing] OTLP export error:', e);
      }
    }
  }

  private spanToPlain(s: OtlpSpanJson): Record<string, unknown> {
    const attrs: Record<string, unknown> = {};
    for (const a of s.attributes) {
      if (a.value.stringValue != null) {
        attrs[a.key] = a.value.stringValue;
      } else if (a.value.intValue != null) {
        attrs[a.key] = Number.parseInt(a.value.intValue, 10);
      } else if (a.value.boolValue != null) {
        attrs[a.key] = a.value.boolValue;
      }
    }
    return {
      name: s.name,
      traceId: Buffer.from(s.traceId, 'base64').toString('hex'),
      spanId: Buffer.from(s.spanId, 'base64').toString('hex'),
      parentSpanId:
        s.parentSpanId != null ? Buffer.from(s.parentSpanId, 'base64').toString('hex') : null,
      startTimeUnixNano: s.startTimeUnixNano,
      endTimeUnixNano: s.endTimeUnixNano,
      attributes: attrs,
    };
  }

  private buildOtlpBody(spans: OtlpSpanJson[]): Record<string, unknown> {
    const service = eventOutboxTracingServiceName();
    const scope = eventOutboxTracingScopeName();
    return {
      resourceSpans: [
        {
          resource: {
            attributes: [{ key: 'service.name', value: { stringValue: service } }],
          },
          scopeSpans: [
            {
              scope: { name: scope, version: '1.0.0' },
              spans,
            },
          ],
        },
      ],
    };
  }

  private toOtlpSpan(
    traceIdHex: string,
    spanIdHex: string,
    parentSpanIdHex: string | null,
    name: string,
    startNs: bigint,
    endNs: bigint,
    extraAttrs: AttrKV[],
  ): OtlpSpanJson {
    return {
      traceId: hexToOtlpBase64(traceIdHex),
      spanId: hexToOtlpBase64(spanIdHex),
      parentSpanId: parentSpanIdHex != null ? hexToOtlpBase64(parentSpanIdHex) : undefined,
      name,
      kind: 1,
      startTimeUnixNano: String(startNs),
      endTimeUnixNano: String(endNs),
      attributes: extraAttrs,
    };
  }

  private baseAttrs(row: EventOutboxRow): AttrKV[] {
    const a: AttrKV[] = [
      attrString('event_outbox.event_id', row.event_id),
      attrString('event_outbox.event_type', row.event_type),
      attrString('event_outbox.entity_id', row.entity_id),
    ];
    if (row.source_service) {
      a.push(attrString('event_outbox.source_service', row.source_service));
    }
    if (row.correlation_id) {
      a.push(attrString('event_outbox.correlation_id', row.correlation_id));
    }
    if (row.region) {
      a.push(attrString('event_outbox.region', row.region));
    }
    const id = row.payload['_identity'];
    if (id != null && typeof id === 'object' && !Array.isArray(id)) {
      const o = id as Record<string, unknown>;
      if (typeof o.tenantId === 'string') {
        a.push(attrString('tenant.id', o.tenantId));
      }
      if (typeof o.activeRole === 'string') {
        a.push(attrString('tenant.active_role', o.activeRole));
      }
      if (typeof o.uid === 'string') {
        a.push(attrString('tenant.uid', o.uid));
      }
    }
    return a;
  }

  /** After successful INSERT into outbox (not idempotent replay). */
  onOutboxEmit(row: EventOutboxRow): void {
    if (!this.shouldRecordSpans()) {
      return;
    }
    const traceIdHex = normalizeOtelTraceId(row.trace_id);
    if (traceIdHex == null || !shouldSampleTraceId(traceIdHex)) {
      return;
    }
    const chain = spanChainForRow(traceIdHex, row.event_id);
    const now = BigInt(Date.now() * 1_000_000);
    const span = this.toOtlpSpan(traceIdHex, chain.emit, null, 'event_outbox.emit', now, now, [
      ...this.baseAttrs(row),
      attrString('event_outbox.phase', 'emit'),
    ]);
    this.enqueue(span);
  }

  /** Worker claimed row (before handler). */
  onOutboxClaim(row: EventOutboxRow): void {
    if (!this.shouldRecordSpans()) {
      return;
    }
    const traceIdHex = normalizeOtelTraceId(row.trace_id);
    if (traceIdHex == null || !shouldSampleTraceId(traceIdHex)) {
      return;
    }
    const chain = spanChainForRow(traceIdHex, row.event_id);
    const now = BigInt(Date.now() * 1_000_000);
    const span = this.toOtlpSpan(traceIdHex, chain.claim, chain.emit, 'event_outbox.worker.claim', now, now, [
      ...this.baseAttrs(row),
      attrString('event_outbox.phase', 'claim'),
    ]);
    this.enqueue(span);
  }

  /**
   * Wrap synchronous handler dispatch; records duration. Does not duplicate trace_id storage — uses row fields only.
   */
  runHandlerSpan(row: EventOutboxRow, dispatch: () => void): void {
    if (!isEventOutboxTracingEnabled()) {
      dispatch();
      return;
    }
    if (!this.shouldRecordSpans()) {
      dispatch();
      return;
    }
    const traceIdHex = normalizeOtelTraceId(row.trace_id);
    if (traceIdHex == null || !shouldSampleTraceId(traceIdHex)) {
      dispatch();
      return;
    }
    const chain = spanChainForRow(traceIdHex, row.event_id);
    const t0 = process.hrtime.bigint();
    try {
      dispatch();
    } finally {
      const t1 = process.hrtime.bigint();
      const span = this.toOtlpSpan(
        traceIdHex,
        chain.handler,
        chain.claim,
        'event_outbox.handler.dispatch',
        t0,
        t1,
        [
          ...this.baseAttrs(row),
          attrString('event_outbox.phase', 'handler'),
          attrInt('event_outbox.handler.duration_ns', Number(t1 - t0)),
        ],
      );
      this.enqueue(span);
    }
  }

  /** Terminal DLQ (failed after max retries). */
  onOutboxDlq(eventId: string, traceIdRaw: string | null, errorMessage: string): void {
    if (!this.shouldRecordSpans()) {
      return;
    }
    const traceIdHex = normalizeOtelTraceId(traceIdRaw);
    if (traceIdHex == null || !shouldSampleTraceId(traceIdHex)) {
      return;
    }
    const chain = spanChainForRow(traceIdHex, eventId);
    const now = BigInt(Date.now() * 1_000_000);
    const span = this.toOtlpSpan(traceIdHex, chain.dlq, chain.handler, 'event_outbox.dlq', now, now, [
      attrString('event_outbox.event_id', eventId),
      attrString('event_outbox.phase', 'dlq'),
      attrBool('event_outbox.dlq', true),
      attrString('error.message', errorMessage.slice(0, 2000)),
    ]);
    this.enqueue(span);
  }

  /**
   * HTTP API gateway / policy guard span (same export pipeline as outbox spans).
   */
  recordApiGatewayRequest(input: {
    traceIdHex: string;
    startNs: bigint;
    endNs: bigint;
    route: string;
    outcome: string;
    decision: string;
    userId: string | null;
    tenantId: string | null;
    permissions: string[];
    gatewayRegion?: string | null;
    edgeCountry?: string | null;
    edgeRegion?: string | null;
    clientLatencyMs?: number | null;
    requestType?: string | null;
    requestPriority?: string | null;
  }): void {
    const durationMs = Number(input.endNs - input.startNs) / 1_000_000;
    this.apiGatewayDurationsMs.push(Math.max(0, durationMs));
    if (this.apiGatewayDurationsMs.length > 2000) {
      this.apiGatewayDurationsMs.splice(0, this.apiGatewayDurationsMs.length - 2000);
    }
    if (!this.shouldRecordSpans()) {
      return;
    }
    const tid = normalizeOtelTraceId(input.traceIdHex);
    if (tid == null || !shouldSampleTraceId(tid)) {
      return;
    }
    const spanId = deriveSpanIdHex(`${tid}|api_gateway|${input.route}|${input.outcome}`);
    const perms = input.permissions.join(',');
    const span = this.toOtlpSpan(tid, spanId, null, 'api_gateway.request', input.startNs, input.endNs, [
      attrString('gateway.route', input.route.slice(0, 500)),
      attrString('gateway.outcome', input.outcome),
      attrString('gateway.policy_decision', input.decision),
      attrString('gateway.permissions_evaluated', perms.slice(0, 2000)),
      ...(input.userId ? [attrString('user.id', input.userId)] : []),
      ...(input.tenantId ? [attrString('tenant.id', input.tenantId)] : []),
      ...(input.gatewayRegion != null && input.gatewayRegion !== ''
        ? [attrString('gateway.region', input.gatewayRegion.slice(0, 64))]
        : []),
      ...(input.edgeCountry != null && input.edgeCountry !== ''
        ? [attrString('edge.country', input.edgeCountry.slice(0, 8))]
        : []),
      ...(input.edgeRegion != null && input.edgeRegion !== ''
        ? [attrString('edge.region', input.edgeRegion.slice(0, 128))]
        : []),
      ...(input.clientLatencyMs != null && Number.isFinite(input.clientLatencyMs)
        ? [attrInt('edge.client_latency_ms', Math.round(input.clientLatencyMs))]
        : []),
      ...(input.requestType != null && input.requestType !== ''
        ? [attrString('request.type', input.requestType.slice(0, 32))]
        : []),
      ...(input.requestPriority != null && input.requestPriority !== ''
        ? [attrString('request.priority', input.requestPriority.slice(0, 16))]
        : []),
    ]);
    this.enqueue(span);
  }

  getApiGatewayLatencyBreakdown(): {
    samples: number;
    p50Ms: number | null;
    p95Ms: number | null;
    avgMs: number | null;
    maxMs: number | null;
  } {
    if (this.apiGatewayDurationsMs.length === 0) {
      return { samples: 0, p50Ms: null, p95Ms: null, avgMs: null, maxMs: null };
    }
    const sorted = [...this.apiGatewayDurationsMs].sort((a, b) => a - b);
    const at = (p: number): number => {
      const idx = Math.min(sorted.length - 1, Math.max(0, Math.floor((sorted.length - 1) * p)));
      return sorted[idx];
    };
    const sum = sorted.reduce((acc, n) => acc + n, 0);
    return {
      samples: sorted.length,
      p50Ms: Math.round(at(0.5) * 100) / 100,
      p95Ms: Math.round(at(0.95) * 100) / 100,
      avgMs: Math.round((sum / sorted.length) * 100) / 100,
      maxMs: Math.round(sorted[sorted.length - 1] * 100) / 100,
    };
  }

  buildHandlerTraceContext(row: EventOutboxRow): OutboxTraceContext | null {
    if (!isEventOutboxTracingEnabled()) {
      return null;
    }
    const traceIdHex = normalizeOtelTraceId(row.trace_id);
    if (traceIdHex == null || !shouldSampleTraceId(traceIdHex)) {
      return null;
    }
    const chain = spanChainForRow(traceIdHex, row.event_id);
    return {
      traceId: traceIdHex,
      spanId: chain.handler,
      traceparent: traceparentV00(traceIdHex, chain.handler, true),
    };
  }

  async onModuleDestroy(): Promise<void> {
    if (this.flushTimer != null) {
      clearTimeout(this.flushTimer);
      this.flushTimer = null;
    }
    await this.flush();
  }
}
