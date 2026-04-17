/**
 * Multi-region / large-scale deployment flags (additive; off by default).
 * Enable EVENT_OUTBOX_MULTI_REGION=1 after applying database/event_outbox_multi_region_migration.sql
 */

export function eventOutboxMultiRegionEnabled(): boolean {
  return process.env.EVENT_OUTBOX_MULTI_REGION?.trim() === '1';
}

/** Logical region id for this process (e.g. us-east-1, eu-west-1). */
export function eventOutboxRegionId(): string | null {
  const r = process.env.EVENT_OUTBOX_REGION?.trim();
  return r || null;
}

/** Stop all worker activity in this process (claims + recovery). */
export function eventOutboxRegionKillSwitch(): boolean {
  return process.env.EVENT_OUTBOX_REGION_DISABLED?.trim() === '1';
}

/** Do not claim new work; still run stale recovery / foreign-region failover (read-heavy safe). */
export function eventOutboxWorkerDegraded(): boolean {
  return process.env.EVENT_OUTBOX_WORKER_DEGRADED?.trim() === '1';
}

/**
 * Re-queue rows stuck in `processing` owned by another region after this age (failover).
 * Default 15 minutes; should exceed normal handler time but allow DR takeover.
 */
export function eventOutboxForeignRegionStaleMs(): number {
  const raw = process.env.EVENT_OUTBOX_FOREIGN_REGION_STALE_MS?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 900_000;
  return Number.isFinite(n) && n >= 120_000 ? n : 900_000;
}

/** Optional read replica URL for dashboard-style queries (falls back to primary on error). */
export function eventOutboxReadReplicaUrl(): string | undefined {
  const u =
    process.env.DATABASE_READ_REPLICA_URL?.trim() ||
    process.env.ORDERS_DATABASE_READ_REPLICA_URL?.trim();
  return u || undefined;
}

export function eventOutboxReadReplicaPoolMax(): number {
  const n = Number.parseInt(process.env.EVENT_OUTBOX_REPLICA_POOL_MAX?.trim() ?? '5', 10);
  return Number.isFinite(n) && n >= 1 && n <= 50 ? n : 5;
}

/** Exposed to ops API for runbooks. */
export function getEventOutboxDeploymentInfo(): {
  multiRegionMode: boolean;
  regionId: string | null;
  regionKillSwitch: boolean;
  workerDegraded: boolean;
  readReplicaConfigured: boolean;
  eventIdStrategy: string;
  idempotencySupported: boolean;
} {
  return {
    multiRegionMode: eventOutboxMultiRegionEnabled(),
    regionId: eventOutboxRegionId(),
    regionKillSwitch: eventOutboxRegionKillSwitch(),
    workerDegraded: eventOutboxWorkerDegraded(),
    readReplicaConfigured: Boolean(eventOutboxReadReplicaUrl()),
    eventIdStrategy: 'uuid_v4_gen_random_uuid',
    idempotencySupported: eventOutboxMultiRegionEnabled(),
  };
}
