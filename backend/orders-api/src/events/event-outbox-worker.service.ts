import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { DistributedLockService } from '../infrastructure/locks/distributed-lock.service';
import { EventOutboxAlertService } from './event-outbox-alert.service';
import { EventOutboxOpsMetricsService } from './event-outbox-ops-metrics.service';
import { DomainEventEmitterService } from './domain-event-emitter.service';
import { defaultRegionId } from '../infrastructure/region/region.config';
import {
  computeWorkerBatchSize,
  eventOutboxAdaptiveBatchEnabled,
  eventOutboxAdaptiveUseDepthQuery,
  eventOutboxPollIntervalMs,
  isEventOutboxEnabled,
  isEventOutboxRegionRoutingEnabled,
  isOutboxWorkerDistributedLockEnabled,
} from './event-outbox-config';
import {
  eventOutboxRegionId,
  eventOutboxRegionKillSwitch,
  eventOutboxWorkerDegraded,
} from './event-outbox-mr.config';
import { EventOutboxChaosService } from './event-outbox-chaos.service';
import { EventOutboxTracingService } from './event-outbox-tracing.service';
import { EventOutboxService } from './event-outbox.service';

@Injectable()
export class EventOutboxWorker implements OnModuleInit, OnModuleDestroy {
  private interval: ReturnType<typeof setInterval> | null = null;

  constructor(
    private readonly outbox: EventOutboxService,
    private readonly emitter: DomainEventEmitterService,
    private readonly alerts: EventOutboxAlertService,
    private readonly opsMetrics: EventOutboxOpsMetricsService,
    private readonly chaos: EventOutboxChaosService,
    private readonly tracing: EventOutboxTracingService,
    private readonly distributedLock: DistributedLockService,
  ) {}

  onModuleInit(): void {
    if (!isEventOutboxEnabled() || !this.outbox.isReady()) {
      return;
    }
    const pollMs = eventOutboxPollIntervalMs();
    const tick = (): void => {
      void this.runTick();
    };
    this.interval = setInterval(tick, pollMs);
    setImmediate(tick);
  }

  onModuleDestroy(): void {
    if (this.interval != null) {
      clearInterval(this.interval);
      this.interval = null;
    }
  }

  private async runTick(): Promise<void> {
    if (isOutboxWorkerDistributedLockEnabled()) {
      const r = await this.distributedLock.withLock('outbox-worker-tick', 5000, () => this.runTickBody());
      if (r === null) {
        return;
      }
      return;
    }
    await this.runTickBody();
  }

  private async runTickBody(): Promise<void> {
    if (eventOutboxRegionKillSwitch()) {
      return;
    }
    if (this.chaos.isEngineEnabled()) {
      if (this.chaos.shouldSimulateRegionKillTick()) {
        return;
      }
      await this.chaos.maybeAwaitWorkerDbLatency();
    }
    const recoveredLocal = await this.outbox.recoverStaleProcessing();
    const recoveredForeign = await this.outbox.recoverForeignRegionStale();
    await this.outbox.pruneDeadLetterOverflow();
    const recovered = recoveredLocal + recoveredForeign;
    let depth = 0;
    if (eventOutboxAdaptiveBatchEnabled() && eventOutboxAdaptiveUseDepthQuery()) {
      depth = await this.outbox.countEligiblePendingApprox();
    }
    const batchSize = computeWorkerBatchSize(depth);
    const rows = eventOutboxWorkerDegraded()
      ? []
      : await this.outbox.claimPendingBatch(batchSize);
    let processed = 0;
    const deadLetterEventIds: string[] = [];
    const workerRegion = eventOutboxRegionId() ?? defaultRegionId();

    for (const row of rows) {
      if (isEventOutboxRegionRoutingEnabled()) {
        if (row.processing_region != null && row.processing_region !== workerRegion) {
          continue;
        }
      }
      try {
        this.tracing.onOutboxClaim(row);
        this.emitter.deliverOutboxRow(row);
        if (this.chaos.isEngineEnabled() && this.chaos.shouldSimulateWorkerCrashAfterDeliver()) {
          this.chaos.recordSimulatedWorkerCrashDrop();
          continue;
        }
        await this.outbox.markProcessed(row.event_id);
        processed++;
      } catch (e) {
        const r = await this.outbox.failProcessing(row.event_id, e);
        if (r === 'dead_letter') {
          deadLetterEventIds.push(row.event_id);
        }
      }
    }
    let dlqTotal: number | null = null;
    if (this.chaos.isEngineEnabled()) {
      dlqTotal = await this.outbox.countTerminalFailed();
    }
    this.chaos.recordAfterWorkerTick({
      recovered,
      claimed: rows.length,
      processed,
      depth,
      batchSize,
      dlqTotal,
    });
    this.opsMetrics.recordWorkerTick({
      recovered,
      claimed: rows.length,
      processed,
    });
    this.alerts.afterWorkerTick({
      recovered,
      claimed: rows.length,
      processed,
      deadLetterEventIds,
    });
  }
}
