/**
 * Event Outbox distributed tracing (additive; **disabled by default**).
 * OpenTelemetry-compatible span shape for OTLP JSON + optional NDJSON export.
 */

export function isEventOutboxTracingEnabled(): boolean {
  return process.env.EVENT_OUTBOX_TRACING?.trim() === '1';
}

/** Per-trace sampling: same trace id always gets the same decision (deterministic). */
export function eventOutboxTracingSampleRate(): number {
  const raw = process.env.EVENT_OUTBOX_TRACING_SAMPLE_RATE?.trim();
  const n = raw != null ? Number.parseFloat(raw) : 1;
  return Number.isFinite(n) && n >= 0 && n <= 1 ? n : 1;
}

export function eventOutboxTracingServiceName(): string {
  return process.env.EVENT_OUTBOX_TRACING_SERVICE_NAME?.trim() || 'orders-api';
}

export function eventOutboxTracingScopeName(): string {
  return process.env.EVENT_OUTBOX_TRACING_SCOPE_NAME?.trim() || 'event-outbox';
}

/** NDJSON lines to stdout (one JSON object per line). */
export function eventOutboxTracingJsonStdoutEnabled(): boolean {
  return isEventOutboxTracingEnabled() && process.env.EVENT_OUTBOX_TRACING_JSON_STDOUT?.trim() === '1';
}

/** Append-only NDJSON file (optional). */
export function eventOutboxTracingJsonFilePath(): string | undefined {
  if (!isEventOutboxTracingEnabled()) {
    return undefined;
  }
  const p = process.env.EVENT_OUTBOX_TRACING_JSON_FILE?.trim();
  return p || undefined;
}

/** OTLP HTTP endpoint base, e.g. http://localhost:4318 — POST /v1/traces */
export function eventOutboxTracingOtlpHttpEndpoint(): string | undefined {
  if (!isEventOutboxTracingEnabled()) {
    return undefined;
  }
  const u = process.env.EVENT_OUTBOX_TRACING_OTLP_HTTP_ENDPOINT?.trim();
  return u || undefined;
}

export function eventOutboxTracingExportBatchSize(): number {
  const raw = process.env.EVENT_OUTBOX_TRACING_EXPORT_BATCH_SIZE?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 64;
  return Number.isFinite(n) && n >= 1 && n <= 512 ? n : 64;
}

export function eventOutboxTracingExportFlushMs(): number {
  const raw = process.env.EVENT_OUTBOX_TRACING_EXPORT_FLUSH_MS?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 100;
  return Number.isFinite(n) && n >= 20 && n <= 5000 ? n : 100;
}

export function eventOutboxTracingQueueMax(): number {
  const raw = process.env.EVENT_OUTBOX_TRACING_QUEUE_MAX?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 10_000;
  return Number.isFinite(n) && n >= 100 && n <= 500_000 ? n : 10_000;
}
