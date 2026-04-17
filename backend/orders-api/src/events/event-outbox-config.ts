/** Outbox is on when DATABASE_URL (or ORDERS_DATABASE_URL) is set and DOMAIN_EVENTS_OUTBOX is not "0". */
export function isEventOutboxEnabled(): boolean {
  if (process.env.DOMAIN_EVENTS_OUTBOX?.trim() === '0') {
    return false;
  }
  const url = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
  return Boolean(url);
}

export function eventOutboxMaxRetries(): number {
  const raw = process.env.DOMAIN_EVENTS_OUTBOX_MAX_RETRIES?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 10;
  return Number.isFinite(n) && n >= 0 ? n : 10;
}

export function eventOutboxPollIntervalMs(): number {
  const raw = process.env.DOMAIN_EVENTS_OUTBOX_POLL_MS?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 2000;
  return Number.isFinite(n) && n >= 200 ? n : 2000;
}

export function eventOutboxStaleProcessingMs(): number {
  const raw = process.env.DOMAIN_EVENTS_OUTBOX_STALE_MS?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 900_000;
  return Number.isFinite(n) && n >= 60_000 ? n : 900_000;
}

/** Log full payload + handler sync timing for outbox delivery (verbose; dev/staging). */
export function isDebugEventsEnabled(): boolean {
  return process.env.DEBUG_EVENTS?.trim() === '1';
}

// --- Scaling (high throughput; additive; no schema changes) ---

/** Fixed batch size when adaptive batching is off (DOMAIN_EVENTS_OUTBOX_BATCH or EVENT_OUTBOX_BATCH). */
export function eventOutboxBatchSizeFixed(): number {
  const raw =
    process.env.DOMAIN_EVENTS_OUTBOX_BATCH?.trim() || process.env.EVENT_OUTBOX_BATCH?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 20;
  return Number.isFinite(n) && n >= 1 && n <= 500 ? n : 20;
}

/** @deprecated Use eventOutboxBatchSizeFixed — kept for backward compatibility. */
export function eventOutboxBatchSize(): number {
  return eventOutboxBatchSizeFixed();
}

export function eventOutboxAdaptiveBatchEnabled(): boolean {
  return process.env.EVENT_OUTBOX_ADAPTIVE_BATCH?.trim() !== '0';
}

/** Optional: skip COUNT before claim (use max batch cap only). Reduces one read per tick. */
export function eventOutboxAdaptiveUseDepthQuery(): boolean {
  return process.env.EVENT_OUTBOX_ADAPTIVE_USE_DEPTH?.trim() !== '0';
}

export function eventOutboxBatchMin(): number {
  const raw = process.env.EVENT_OUTBOX_BATCH_MIN?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 20;
  return Number.isFinite(n) && n >= 1 && n <= 500 ? n : 20;
}

export function eventOutboxBatchMax(): number {
  const rawMax = process.env.EVENT_OUTBOX_BATCH_MAX?.trim();
  if (rawMax != null) {
    const n = Number.parseInt(rawMax, 10);
    if (Number.isFinite(n) && n >= 1 && n <= 500) {
      return n;
    }
  }
  return eventOutboxBatchSizeFixed();
}

/** Fraction of eligible backlog to target per tick (capped by min/max). Default ~2%. */
export function eventOutboxAdaptiveRatio(): number {
  const raw = process.env.EVENT_OUTBOX_ADAPTIVE_RATIO?.trim();
  const n = raw != null ? Number.parseFloat(raw) : 0.02;
  return Number.isFinite(n) && n > 0 && n <= 1 ? n : 0.02;
}

/**
 * Eligible pending rows ≈ queue depth. Batch = clamp(min, max, ceil(depth * ratio)).
 * If depth query disabled, returns max.
 */
export function computeWorkerBatchSize(eligibleDepth: number): number {
  if (!eventOutboxAdaptiveBatchEnabled()) {
    return eventOutboxBatchSizeFixed();
  }
  if (!eventOutboxAdaptiveUseDepthQuery()) {
    return Math.min(500, eventOutboxBatchMax());
  }
  const min = eventOutboxBatchMin();
  const max = Math.max(min, eventOutboxBatchMax());
  const ratio = eventOutboxAdaptiveRatio();
  const scaled = Math.ceil(Math.max(0, eligibleDepth) * ratio);
  return Math.min(max, Math.max(min, scaled));
}

/** Ops dashboard: default 15s; increase under load to cut aggregation cost. */
export function opsDashboardCacheTtlMs(): number {
  const raw = process.env.OPS_DASHBOARD_CACHE_TTL_MS?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 15_000;
  return Number.isFinite(n) && n >= 1000 && n <= 600_000 ? n : 15_000;
}

/** Switch timeline to daily buckets above this window (fewer rows scanned client-side). */
export function opsTimelineDayBucketAfterHours(): number {
  const raw = process.env.OPS_TIMELINE_DAY_BUCKETS_AFTER_H?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 72;
  return Number.isFinite(n) && n >= 24 && n <= 168 ? n : 72;
}

/** Max tick samples retained for throughput estimate (memory bound). */
export function opsMetricsMaxSamples(): number {
  const raw = process.env.OPS_METRICS_MAX_SAMPLES?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 64;
  return Number.isFinite(n) && n >= 16 && n <= 300 ? n : 64;
}

/** Optional multi-instance coordination around worker tick (Redis lock). Default off. */
export function isOutboxWorkerDistributedLockEnabled(): boolean {
  return process.env.OUTBOX_WORKER_DISTRIBUTED_LOCK?.trim() === '1';
}

/** When set, skip outbox rows whose processing_region does not match this worker's region. Default off. */
export function isEventOutboxRegionRoutingEnabled(): boolean {
  return process.env.EVENT_OUTBOX_REGION_ROUTING?.trim() === '1';
}

/** Max terminal failed rows retained in DLQ table (0 => disabled). */
export function eventOutboxDlqRetainMaxRows(): number {
  const raw = process.env.EVENT_OUTBOX_DLQ_RETAIN_MAX?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 100_000;
  return Number.isFinite(n) && n >= 0 ? n : 100_000;
}

/** Max rows pruned per worker tick when retention is exceeded. */
export function eventOutboxDlqPruneBatchSize(): number {
  const raw = process.env.EVENT_OUTBOX_DLQ_PRUNE_BATCH?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 500;
  return Number.isFinite(n) && n >= 1 && n <= 20_000 ? n : 500;
}
