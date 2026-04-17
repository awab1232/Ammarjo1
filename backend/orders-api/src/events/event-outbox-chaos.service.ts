import { Injectable } from '@nestjs/common';
import {
  eventOutboxChaosDbLatencyMs,
  eventOutboxChaosDlqSpikeMinDelta,
  eventOutboxChaosEngineEnabled,
  eventOutboxChaosRegionKill,
  eventOutboxChaosReplicaPartition,
  eventOutboxChaosReplicaPartitionLatencyMs,
  eventOutboxChaosRunId,
  eventOutboxChaosWorkerCrashProbability,
  getEventOutboxChaosModeSummary,
} from './event-outbox-chaos.config';

const MAX_RECOVERY_SAMPLES = 200;
const MAX_DLQ_SPIKE_EVENTS = 100;

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

function percentile(sorted: number[], p: number): number | undefined {
  if (sorted.length === 0) {
    return undefined;
  }
  const idx = Math.min(sorted.length - 1, Math.max(0, Math.ceil(p * sorted.length) - 1));
  return sorted[idx];
}

/**
 * In-process chaos coordination: simulation flags are **env-only**; never mutates outbox rows
 * except by exercising normal worker paths (e.g. intentional omission of markProcessed to mimic crash).
 */
@Injectable()
export class EventOutboxChaosService {
  private runStartedAt: number | null = null;
  private lastDlqTotal: number | null = null;
  private crashSimulatedAt: number | null = null;

  private recoveryTimeMsSamples: number[] = [];
  private dlqSpikeEvents: Array<{ at: string; delta: number; total: number }> = [];

  private idempotencyReplayHits = 0;
  private simulatedWorkerCrashDrops = 0;
  /** Cycles where eligible depth suggested work but claim returned zero (SKIP LOCKED / contention). */
  private skipLockContentionCycles = 0;

  constructor() {
    if (eventOutboxChaosEngineEnabled()) {
      this.runStartedAt = Date.now();
    }
  }

  isEngineEnabled(): boolean {
    return eventOutboxChaosEngineEnabled();
  }

  shouldForcePrimaryReads(): boolean {
    return eventOutboxChaosReplicaPartition();
  }

  async maybeAwaitReplicaPartitionLatency(): Promise<void> {
    const ms = eventOutboxChaosReplicaPartitionLatencyMs();
    if (ms > 0) {
      await sleep(ms);
    }
  }

  /** Region-down: skip entire tick — no recovery, no claims (safe; no row corruption). */
  shouldSimulateRegionKillTick(): boolean {
    return eventOutboxChaosRegionKill();
  }

  async maybeAwaitWorkerDbLatency(): Promise<void> {
    const ms = eventOutboxChaosDbLatencyMs();
    if (ms > 0) {
      await sleep(ms);
    }
  }

  /**
   * Simulate worker crash after handler success: caller should skip markProcessed when true.
   * Uses per-tick RNG so probability is stable within bounds.
   */
  shouldSimulateWorkerCrashAfterDeliver(): boolean {
    const p = eventOutboxChaosWorkerCrashProbability();
    if (p <= 0) {
      return false;
    }
    return Math.random() < p;
  }

  recordIdempotencyReplay(): void {
    if (!eventOutboxChaosEngineEnabled()) {
      return;
    }
    this.idempotencyReplayHits++;
  }

  recordSimulatedWorkerCrashDrop(): void {
    this.simulatedWorkerCrashDrops++;
    this.crashSimulatedAt = Date.now();
  }

  /**
   * After each worker tick: recovery-time samples, DLQ spikes, SKIP LOCKED health.
   */
  recordAfterWorkerTick(ctx: {
    recovered: number;
    claimed: number;
    processed: number;
    depth: number;
    batchSize: number;
    dlqTotal: number | null;
  }): void {
    if (!eventOutboxChaosEngineEnabled()) {
      return;
    }

    const { recovered, claimed, depth, batchSize, dlqTotal } = ctx;

    if (recovered > 0 && this.crashSimulatedAt != null) {
      const dt = Date.now() - this.crashSimulatedAt;
      if (dt >= 0 && Number.isFinite(dt)) {
        this.recoveryTimeMsSamples.push(dt);
        while (this.recoveryTimeMsSamples.length > MAX_RECOVERY_SAMPLES) {
          this.recoveryTimeMsSamples.shift();
        }
      }
      this.crashSimulatedAt = null;
    }

    if (dlqTotal != null) {
      if (this.lastDlqTotal != null) {
        const delta = dlqTotal - this.lastDlqTotal;
        const minD = eventOutboxChaosDlqSpikeMinDelta();
        if (delta >= minD) {
          this.dlqSpikeEvents.push({
            at: new Date().toISOString(),
            delta,
            total: dlqTotal,
          });
          while (this.dlqSpikeEvents.length > MAX_DLQ_SPIKE_EVENTS) {
            this.dlqSpikeEvents.shift();
          }
        }
      }
      this.lastDlqTotal = dlqTotal;
    }

    if (batchSize > 0 && depth > 0 && claimed === 0) {
      this.skipLockContentionCycles++;
    }
  }

  getReportSnapshot(extra: {
    lagByRegion: Array<{
      region_key: string;
      eligible_pending: number;
      processing: number;
    }>;
  }): {
    ok: boolean;
    chaosActive: boolean;
    runId: string | null;
    runStartedAt: string | null;
    modes: ReturnType<typeof getEventOutboxChaosModeSummary>;
    observability: {
      recoveryTimeMs: { samples: number[]; p50: number | null; max: number | null };
      dlqSpikes: typeof this.dlqSpikeEvents;
      lagByRegion: typeof extra.lagByRegion;
    };
    validation: {
      idempotencyReplayHits: number;
      simulatedWorkerCrashDrops: number;
      skipLockContentionCycles: number;
      notes: string[];
    };
    guardrails: {
      nodeEnv: string;
      productionChaosAllowed: boolean;
    };
  } {
    const active = eventOutboxChaosEngineEnabled();
    const samples = [...this.recoveryTimeMsSamples].sort((a, b) => a - b);
    const modes = getEventOutboxChaosModeSummary();
    const nodeEnv = process.env.NODE_ENV?.trim() || 'development';
    const productionChaosAllowed = process.env.EVENT_OUTBOX_CHAOS_ALLOW_PRODUCTION?.trim() === '1';

    const notes: string[] = [
      'SKIP LOCKED: claims may return fewer rows than batch under contention; zero rows with depth>0 increments skipLockContentionCycles.',
      'Worker crash simulation omits markProcessed after successful delivery; stale recovery requeues — handlers should stay idempotent.',
      'Chaos never writes ad-hoc SQL; only normal outbox operations run.',
    ];

    return {
      ok: true,
      chaosActive: active,
      runId: eventOutboxChaosRunId(),
      runStartedAt: this.runStartedAt != null ? new Date(this.runStartedAt).toISOString() : null,
      modes,
      observability: {
        recoveryTimeMs: {
          samples: [...this.recoveryTimeMsSamples],
          p50: percentile(samples, 0.5) ?? null,
          max: samples.length ? samples[samples.length - 1] : null,
        },
        dlqSpikes: [...this.dlqSpikeEvents],
        lagByRegion: extra.lagByRegion,
      },
      validation: {
        idempotencyReplayHits: this.idempotencyReplayHits,
        simulatedWorkerCrashDrops: this.simulatedWorkerCrashDrops,
        skipLockContentionCycles: this.skipLockContentionCycles,
        notes,
      },
      guardrails: {
        nodeEnv,
        productionChaosAllowed,
      },
    };
  }
}
