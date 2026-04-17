import { Injectable, Optional } from '@nestjs/common';
import type { InfraTelemetryService } from '../infrastructure/infra-telemetry.service';
import { opsMetricsMaxSamples } from './event-outbox-config';

export type WorkerTickSample = {
  t: number;
  recovered: number;
  claimed: number;
  processed: number;
};

/**
 * In-process worker metrics (no DB writes). Bounded memory; rolling totals for dashboards.
 */
@Injectable()
export class EventOutboxOpsMetricsService {
  constructor(@Optional() private readonly infraTelemetry?: InfraTelemetryService) {}

  private readonly samples: WorkerTickSample[] = [];
  private totalProcessed = 0;
  private totalClaimed = 0;
  private totalRecovered = 0;
  private tickCount = 0;

  recordWorkerTick(sample: Omit<WorkerTickSample, 't'>): void {
    const maxSamples = opsMetricsMaxSamples();
    this.tickCount++;
    this.totalProcessed += sample.processed;
    this.totalClaimed += sample.claimed;
    this.totalRecovered += sample.recovered;
    this.samples.push({ t: Date.now(), ...sample });
    while (this.samples.length > maxSamples) {
      this.samples.shift();
    }
  }

  /** O(1) counters since process start (lightweight; resets on deploy). */
  getRollingCounters(): {
    ticks: number;
    totalProcessed: number;
    totalClaimed: number;
    totalRecoveredStale: number;
    redis_ops_count?: number;
    cache_hit_ratio?: number | null;
    lock_contention_count?: number;
  } {
    const base = {
      ticks: this.tickCount,
      totalProcessed: this.totalProcessed,
      totalClaimed: this.totalClaimed,
      totalRecoveredStale: this.totalRecovered,
    };
    const extra = this.infraTelemetry?.getDistributedInfraSnapshot();
    return extra ? { ...base, ...extra } : base;
  }

  /** Estimated events/min processed from recent samples (last ~5 minutes). */
  getThroughputEstimate(): {
    eventsPerMinute: number;
    samplesInWindow: number;
    lastTickAt: string | null;
  } {
    const now = Date.now();
    const windowMs = 5 * 60 * 1000;
    let totalProcessed = 0;
    let count = 0;
    for (const s of this.samples) {
      if (now - s.t <= windowMs) {
        totalProcessed += s.processed;
        count++;
      }
    }
    const last = this.samples[this.samples.length - 1];
    const minutes = windowMs / 60_000;
    const eventsPerMinute = minutes > 0 ? totalProcessed / minutes : 0;
    return {
      eventsPerMinute: Math.round(eventsPerMinute * 100) / 100,
      samplesInWindow: count,
      lastTickAt: last != null ? new Date(last.t).toISOString() : null,
    };
  }
}
