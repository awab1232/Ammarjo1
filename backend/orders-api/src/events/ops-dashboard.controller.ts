import {
  Controller,
  Get,
  HttpException,
  HttpStatus,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { InternalApiKeyGuard } from '../search/internal-api-key.guard';
import { EventOutboxAlertService } from './event-outbox-alert.service';
import { EventOutboxOpsMetricsService } from './event-outbox-ops-metrics.service';
import { EventOutboxChaosService } from './event-outbox-chaos.service';
import { EventOutboxService } from './event-outbox.service';
import { opsDashboardCacheTtlMs } from './event-outbox-config';
import { getEventOutboxDeploymentInfo } from './event-outbox-mr.config';

function parseHours(raw: string | undefined, fallback: number): number {
  if (raw == null || raw === '') {
    return fallback;
  }
  const n = Number.parseInt(String(raw), 10);
  return Number.isFinite(n) && n >= 1 && n <= 168 ? n : fallback;
}

function parseLimit(raw: string | undefined, fallback: number): number {
  if (raw == null || raw === '') {
    return fallback;
  }
  const n = Number.parseInt(String(raw), 10);
  return Number.isFinite(n) && n >= 1 && n <= 250 ? n : fallback;
}

/**
 * Read-only ops dashboard JSON for UI consumers. Cached briefly to limit DB load.
 */
@Controller('internal/ops/dashboard')
@UseGuards(TenantContextGuard, ApiPolicyGuard, InternalApiKeyGuard)
@ApiPolicy({ auth: false, tenant: 'none', rateLimit: { rpm: 120 } })
export class OpsDashboardController {
  private summaryCache: { key: string; at: number; payload: unknown } | null = null;
  private timelineCache: { key: string; at: number; payload: unknown } | null = null;
  private alertsHistoryCache: { key: string; at: number; payload: unknown } | null = null;

  constructor(
    private readonly outbox: EventOutboxService,
    private readonly alerts: EventOutboxAlertService,
    private readonly opsMetrics: EventOutboxOpsMetricsService,
    private readonly chaos: EventOutboxChaosService,
  ) {}

  private ensureOutbox(): void {
    if (!this.outbox.isReady()) {
      throw new HttpException('Event outbox not configured', HttpStatus.SERVICE_UNAVAILABLE);
    }
  }

  /** Aggregated KPIs, worker throughput, retry distribution, active alert conditions. */
  @Get('summary')
  async summary(@Query('hours') hoursRaw?: string) {
    this.ensureOutbox();
    const hours = parseHours(hoursRaw, 24);
    const cacheKey = `summary:${hours}`;
    const now = Date.now();
    const ttl = opsDashboardCacheTtlMs();
    if (
      this.summaryCache != null &&
      this.summaryCache.key === cacheKey &&
      now - this.summaryCache.at < ttl
    ) {
      return this.summaryCache.payload;
    }

    const row = await this.outbox.getOpsSummary(hours);
    if (!row) {
      throw new HttpException('Metrics unavailable', HttpStatus.SERVICE_UNAVAILABLE);
    }

    const minutes = hours * 60;
    const eventsPerMinute = minutes > 0 ? row.emitted / minutes : 0;
    const terminal = row.processed + row.failedTerminal;
    const successFailureRatio =
      terminal > 0
        ? {
            success: row.processed,
            failure: row.failedTerminal,
            rate: Math.round((row.processed / terminal) * 10_000) / 10_000,
          }
        : { success: row.processed, failure: row.failedTerminal, rate: null };

    const workerThroughput = this.opsMetrics.getThroughputEstimate();
    const rollingCounters = this.opsMetrics.getRollingCounters();
    const activeAlerts = await this.alerts.getActiveAlertConditions();

    const payload = {
      ok: true,
      generatedAt: new Date().toISOString(),
      cacheTtlMs: ttl,
      windowHours: hours,
      deployment: getEventOutboxDeploymentInfo(),
      metrics: {
        emitted: row.emitted,
        processed: row.processed,
        failedInWindow: row.failedTerminal,
        dlqCount: row.dlqCount,
        eventsPerMinute: Math.round(eventsPerMinute * 1000) / 1000,
        successFailureRatio,
        retryDistribution: row.retryDistribution,
        workerThroughput,
        rollingCounters,
      },
      alerts: {
        active: activeAlerts,
        activeCount: activeAlerts.length,
        lastAlertAt: this.alerts.getLastAlertTimestamp(),
        alertTypeBreakdown: this.alerts.getAlertTypeBreakdown(),
      },
    };

    this.summaryCache = { key: cacheKey, at: now, payload };
    return payload;
  }

  /**
   * Chaos / resilience run summary (env-gated). Safe to call anytime: when chaos is off, `chaosActive` is false.
   * Uses read path for `lagByRegion` (replica when configured).
   */
  @Get('chaos-report')
  async chaosReport() {
    this.ensureOutbox();
    const lagByRegion = await this.outbox.getLagByRegion();
    return this.chaos.getReportSnapshot({ lagByRegion });
  }

  /** Hourly buckets: emitted / worker pick (processing) / processed / failed. */
  @Get('events-timeline')
  async eventsTimeline(@Query('hours') hoursRaw?: string) {
    this.ensureOutbox();
    const hours = parseHours(hoursRaw, 48);
    const cacheKey = `timeline:${hours}`;
    const now = Date.now();
    const ttl = opsDashboardCacheTtlMs();
    if (
      this.timelineCache != null &&
      this.timelineCache.key === cacheKey &&
      now - this.timelineCache.at < ttl
    ) {
      return this.timelineCache.payload;
    }

    const timeline = await this.outbox.getOpsTimeline(hours);
    if (!timeline) {
      throw new HttpException('Timeline unavailable', HttpStatus.SERVICE_UNAVAILABLE);
    }

    const payload = {
      ok: true,
      generatedAt: new Date().toISOString(),
      cacheTtlMs: ttl,
      windowHours: hours,
      bucketMinutes: timeline.bucketMinutes,
      bucketMode: timeline.bucketMode,
      series: {
        emitted: 'enqueue (COALESCE(emitted_at, created_at))',
        processing: 'worker pick (picked_by_worker_at)',
        processed: 'processed_at',
        failed: 'failed_at',
      },
      buckets: timeline.buckets,
    };

    this.timelineCache = { key: cacheKey, at: now, payload };
    return payload;
  }

  /** In-memory alert dispatch history + active conditions (read-only). */
  @Get('alerts-history')
  async alertsHistory(@Query('limit') limitRaw?: string) {
    this.ensureOutbox();
    const limit = parseLimit(limitRaw, 100);
    const ttl = opsDashboardCacheTtlMs();
    const now = Date.now();
    const cacheKey = `alerts:${limit}`;
    if (
      this.alertsHistoryCache != null &&
      this.alertsHistoryCache.key === cacheKey &&
      now - this.alertsHistoryCache.at < ttl
    ) {
      return this.alertsHistoryCache.payload;
    }
    const activeAlerts = await this.alerts.getActiveAlertConditions();
    const payload = {
      ok: true,
      generatedAt: new Date().toISOString(),
      cacheTtlMs: ttl,
      lastAlertAt: this.alerts.getLastAlertTimestamp(),
      alertTypeBreakdown: this.alerts.getAlertTypeBreakdown(),
      activeAlerts,
      activeCount: activeAlerts.length,
      entries: this.alerts.getAlertsHistory(limit),
    };
    this.alertsHistoryCache = { key: cacheKey, at: now, payload };
    return payload;
  }
}
