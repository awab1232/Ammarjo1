/**
 * Chaos / resilience testing for the Event Outbox (additive; **off by default**).
 *
 * Enable only in controlled environments:
 *   EVENT_OUTBOX_CHAOS=1
 *
 * Production requires an explicit second flag (still avoid on live traffic):
 *   EVENT_OUTBOX_CHAOS_ALLOW_PRODUCTION=1
 */

export function eventOutboxChaosEngineEnabled(): boolean {
  if (process.env.EVENT_OUTBOX_CHAOS?.trim() !== '1') {
    return false;
  }
  const nodeEnv = process.env.NODE_ENV?.trim().toLowerCase() || 'development';
  if (nodeEnv === 'production' && process.env.EVENT_OUTBOX_CHAOS_ALLOW_PRODUCTION?.trim() !== '1') {
    return false;
  }
  return true;
}

/** Simulate total regional outage: worker performs no DB work for the tick (no claims, no recovery). */
export function eventOutboxChaosRegionKill(): boolean {
  return eventOutboxChaosEngineEnabled() && process.env.EVENT_OUTBOX_CHAOS_REGION_KILL?.trim() === '1';
}

/**
 * After successful handler delivery, randomly omit `markProcessed` to simulate crash mid-flight.
 * Rows remain `processing` until stale recovery — validates SKIP LOCKED + recovery paths.
 * Probability in [0, 1].
 */
export function eventOutboxChaosWorkerCrashProbability(): number {
  if (!eventOutboxChaosEngineEnabled()) {
    return 0;
  }
  const raw = process.env.EVENT_OUTBOX_CHAOS_WORKER_CRASH_PROBABILITY?.trim();
  const n = raw != null ? Number.parseFloat(raw) : 0;
  return Number.isFinite(n) && n >= 0 && n <= 1 ? n : 0;
}

/** Artificial delay before worker DB operations (primary path). Capped to avoid accidental outages. */
export function eventOutboxChaosDbLatencyMs(): number {
  if (!eventOutboxChaosEngineEnabled()) {
    return 0;
  }
  const raw = process.env.EVENT_OUTBOX_CHAOS_DB_LATENCY_MS?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 0;
  return Number.isFinite(n) && n >= 0 && n <= 60_000 ? n : 0;
}

/** Treat read replica as unreachable: dashboard reads use primary + optional extra delay (partition). */
export function eventOutboxChaosReplicaPartition(): boolean {
  return (
    eventOutboxChaosEngineEnabled() && process.env.EVENT_OUTBOX_CHAOS_REPLICA_PARTITION?.trim() === '1'
  );
}

export function eventOutboxChaosReplicaPartitionLatencyMs(): number {
  if (!eventOutboxChaosReplicaPartition()) {
    return 0;
  }
  const raw = process.env.EVENT_OUTBOX_CHAOS_REPLICA_PARTITION_LATENCY_MS?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 0;
  return Number.isFinite(n) && n >= 0 && n <= 30_000 ? n : 0;
}

export function eventOutboxChaosRunId(): string | null {
  if (!eventOutboxChaosEngineEnabled()) {
    return null;
  }
  const r = process.env.EVENT_OUTBOX_CHAOS_RUN_ID?.trim();
  return r || null;
}

/** Minimum absolute increase in terminal `failed` count to record a DLQ “spike” sample. */
export function eventOutboxChaosDlqSpikeMinDelta(): number {
  if (!eventOutboxChaosEngineEnabled()) {
    return Number.POSITIVE_INFINITY;
  }
  const raw = process.env.EVENT_OUTBOX_CHAOS_DLQ_SPIKE_MIN?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 5;
  return Number.isFinite(n) && n >= 1 ? n : 5;
}

export function getEventOutboxChaosModeSummary(): {
  engineEnabled: boolean;
  regionKill: boolean;
  workerCrashProbability: number;
  dbLatencyMs: number;
  replicaPartition: boolean;
  replicaPartitionLatencyMs: number;
  runId: string | null;
} {
  return {
    engineEnabled: eventOutboxChaosEngineEnabled(),
    regionKill: eventOutboxChaosRegionKill(),
    workerCrashProbability: eventOutboxChaosWorkerCrashProbability(),
    dbLatencyMs: eventOutboxChaosDbLatencyMs(),
    replicaPartition: eventOutboxChaosReplicaPartition(),
    replicaPartitionLatencyMs: eventOutboxChaosReplicaPartitionLatencyMs(),
    runId: eventOutboxChaosRunId(),
  };
}
