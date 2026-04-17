import { Injectable, Logger, Optional } from '@nestjs/common';
import { EventOutboxOpsMetricsService } from '../../events/event-outbox-ops-metrics.service';
import { EventOutboxService } from '../../events/event-outbox.service';
import { EventOutboxTracingService } from '../../events/event-outbox-tracing.service';
import { isEventOutboxEnabled } from '../../events/event-outbox-config';
import { OrdersPgService } from '../../orders/orders-pg.service';
import { InfraTelemetryService } from '../infra-telemetry.service';
import { RedisClientService } from '../redis/redis-client.service';
import { isRedisInfrastructureEnabled } from '../redis/redis.config';
import { DbRouterService } from '../database/db-router.service';
import { isDbReadRoutingEnabled } from '../database/db-router.config';
import { MultiRegionStrategyService } from '../region/multi-region-strategy.service';
import { RegionHealthService } from '../region/region-health.service';
import { isMultiRegionStrategyEnabled, primaryRegionFromEnv } from '../region/region-strategy.config';
import { RegionService } from '../region/region.service';
import { defaultRegionId, isRegionRoutingEnabled } from '../region/region.config';
import { isResponseCacheEnabled } from '../cache/cache.config';
import { ProductionReadinessService } from './production-readiness.service';

export type GlobalSystemHealthSnapshot = {
  ok: boolean;
  generatedAt: string;
  region: {
    routingEnabled: boolean;
    current: string;
    defaultRegion: string;
  };
  redis: {
    enabled: boolean;
    ready: boolean;
  };
  database: {
    readRoutingEnabled: boolean;
    primary: { ok: boolean; error?: string };
    replica: { ok: boolean; skipped?: boolean; error?: string };
    replicaLagSeconds: number | null;
  };
  outbox: {
    enabled: boolean;
    backlogEligibleApprox: number | null;
    lagByRegion: Array<{ region_key: string; eligible_pending: number; processing: number }>;
    lagByDomain: Array<{ domain: string; eligible_pending: number; processing: number }>;
    workerThroughput: {
      eventsPerMinute: number;
      samplesInWindow: number;
      lastTickAt: string | null;
    } | null;
    rollingCounters: Record<string, unknown> | null;
  };
  cache: {
    enabled: boolean;
    hitRatio: number | null;
    redisOpsCount: number;
  };
  requestLatency: {
    samples: number;
    p50Ms: number | null;
    p95Ms: number | null;
    avgMs: number | null;
    maxMs: number | null;
  };
  multiRegion: {
    primaryRegion: 'JO' | 'EG';
    failoverActive: boolean;
    failoverTarget?: 'JO' | 'EG';
    regionHealth: { JO: boolean; EG: boolean };
  };
  isProductionReady: boolean;
  criticalWarnings: string[];
  systemScore: number;
};

@Injectable()
export class GlobalSystemHealthService {
  private readonly logger = new Logger(GlobalSystemHealthService.name);
  private readonly lastSloWarningAt = new Map<string, number>();

  constructor(
    private readonly region: RegionService,
    private readonly redis: RedisClientService,
    private readonly dbRouter: DbRouterService,
    private readonly telemetry: InfraTelemetryService,
    private readonly ordersPg: OrdersPgService,
    private readonly outbox: EventOutboxService,
    private readonly opsMetrics: EventOutboxOpsMetricsService,
    private readonly tracing: EventOutboxTracingService,
    private readonly regionHealth: RegionHealthService,
    private readonly readiness: ProductionReadinessService,
    @Optional() private readonly strategy?: MultiRegionStrategyService,
  ) {}

  private shouldWarn(key: string): boolean {
    const now = Date.now();
    const last = this.lastSloWarningAt.get(key) ?? 0;
    if (now - last < 60_000) return false;
    this.lastSloWarningAt.set(key, now);
    return true;
  }

  private async getReplicaLagSeconds(): Promise<number | null> {
    if (!(isDbReadRoutingEnabled() && this.dbRouter.isActive())) {
      return null;
    }
    const c = await this.dbRouter.getReadClient();
    if (!c) return null;
    try {
      const q = await c.query<{ lag_seconds: string | null }>(
        `SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp()))::text AS lag_seconds`,
      );
      const raw = q.rows[0]?.lag_seconds;
      if (raw == null) return null;
      const n = Number(raw);
      return Number.isFinite(n) ? Math.max(0, n) : null;
    } catch {
      return null;
    } finally {
      c.release();
    }
  }

  async getSnapshot(): Promise<GlobalSystemHealthSnapshot> {
    const generatedAt = new Date().toISOString();

    const primaryPing =
      isDbReadRoutingEnabled() && this.dbRouter.isActive()
        ? await this.dbRouter.pingPrimary()
        : await this.ordersPg.ping();

    const replicaPing =
      isDbReadRoutingEnabled() && this.dbRouter.isActive()
        ? await this.dbRouter.pingReplica()
        : { ok: false as const, skipped: true as const, error: 'db_read_routing_inactive' };

    let backlog: number | null = null;
    let lagByRegion: GlobalSystemHealthSnapshot['outbox']['lagByRegion'] = [];
    let lagByDomain: GlobalSystemHealthSnapshot['outbox']['lagByDomain'] = [];
    if (isEventOutboxEnabled() && this.outbox.isReady()) {
      try {
        backlog = await this.outbox.countEligiblePendingApprox();
      } catch {
        backlog = null;
      }
      try {
        lagByRegion = await this.outbox.getLagByRegion();
      } catch {
        lagByRegion = [];
      }
      try {
        const pending = await this.outbox.listPendingForAdmin(500);
        const map = new Map<string, { eligible_pending: number; processing: number }>();
        for (const row of pending) {
          const [domain] = String(row.event_type ?? 'unknown').split('.');
          const key = domain || 'unknown';
          const cur = map.get(key) ?? { eligible_pending: 0, processing: 0 };
          if (row.status === 'pending') cur.eligible_pending++;
          if (row.status === 'processing') cur.processing++;
          map.set(key, cur);
        }
        lagByDomain = [...map.entries()].map(([domain, v]) => ({ domain, ...v }));
      } catch {
        lagByDomain = [];
      }
    }

    const infraSnap = this.telemetry.getDistributedInfraSnapshot();
    const requestLatency = this.tracing.getApiGatewayLatencyBreakdown();
    const replicaLagSeconds = await this.getReplicaLagSeconds();

    let regionHealth = { JO: true, EG: true };
    try {
      regionHealth = await this.regionHealth.getRegionHealth();
    } catch {
      regionHealth = { JO: true, EG: true };
    }

    const multiRegion: GlobalSystemHealthSnapshot['multiRegion'] =
      isMultiRegionStrategyEnabled() && this.strategy
        ? (() => {
            const st = this.strategy!.getFailoverState();
            return {
              primaryRegion: this.strategy!.getPrimaryRegion(),
              failoverActive: st.failoverActive,
              ...(st.failoverTarget != null ? { failoverTarget: st.failoverTarget } : {}),
              regionHealth,
            };
          })()
        : {
            primaryRegion: primaryRegionFromEnv(),
            failoverActive: false,
            regionHealth,
          };

    const snapshot: GlobalSystemHealthSnapshot = {
      ok: true,
      generatedAt,
      region: {
        routingEnabled: isRegionRoutingEnabled(),
        current: this.region.getCurrentRegion(),
        defaultRegion: defaultRegionId(),
      },
      redis: {
        enabled: isRedisInfrastructureEnabled(),
        ready: this.redis.isReady(),
      },
      database: {
        readRoutingEnabled: isDbReadRoutingEnabled() && this.dbRouter.isActive(),
        primary: primaryPing,
        replica: replicaPing,
        replicaLagSeconds,
      },
      outbox: {
        enabled: isEventOutboxEnabled() && this.outbox.isReady(),
        backlogEligibleApprox: backlog,
        lagByRegion,
        lagByDomain,
        workerThroughput: this.opsMetrics.getThroughputEstimate(),
        rollingCounters: this.opsMetrics.getRollingCounters(),
      },
      cache: {
        enabled: isResponseCacheEnabled(),
        hitRatio: infraSnap.cache_hit_ratio,
        redisOpsCount: infraSnap.redis_ops_count,
      },
      requestLatency,
      multiRegion,
      isProductionReady: true,
      criticalWarnings: [],
      systemScore: 100,
    };
    const processingBacklog = snapshot.outbox.lagByDomain.reduce((acc, x) => acc + x.processing, 0);
    const readiness = this.readiness.getProductionReadiness({
      dbPrimaryOk: snapshot.database.primary.ok,
      redisEnabled: snapshot.redis.enabled,
      redisReady: snapshot.redis.ready,
      cacheEnabled: snapshot.cache.enabled,
      cacheHitRatio: snapshot.cache.hitRatio,
      outboxEnabled: snapshot.outbox.enabled,
      outboxLag: snapshot.outbox.backlogEligibleApprox,
      processingBacklog,
      replicaLagSeconds: snapshot.database.replicaLagSeconds,
    });
    snapshot.isProductionReady = readiness.isProductionReady;
    snapshot.criticalWarnings = readiness.criticalWarnings;
    snapshot.systemScore = readiness.systemScore;

    const dlqThreshold = Number(process.env.SLO_DLQ_THRESHOLD || 500);
    const lagThreshold = Number(process.env.SLO_EVENT_LAG_THRESHOLD || 1000);
    const replicaLagThreshold = Number(process.env.SLO_REPLICA_LAG_SECONDS || 30);
    if ((snapshot.outbox.backlogEligibleApprox ?? 0) > lagThreshold && this.shouldWarn('event_lag_threshold')) {
      this.logger.warn(
        `SLO warning: event lag threshold exceeded (${snapshot.outbox.backlogEligibleApprox} > ${lagThreshold})`,
      );
    }
    if (processingBacklog > dlqThreshold && this.shouldWarn('dlq_threshold')) {
      this.logger.warn(`SLO warning: DLQ/processing threshold exceeded (${processingBacklog} > ${dlqThreshold})`);
    }
    if (
      snapshot.database.replicaLagSeconds != null &&
      snapshot.database.replicaLagSeconds > replicaLagThreshold &&
      this.shouldWarn('replica_lag_threshold')
    ) {
      this.logger.warn(
        `SLO warning: replica lag high (${snapshot.database.replicaLagSeconds}s > ${replicaLagThreshold}s)`,
      );
    }
    return snapshot;
  }
}
