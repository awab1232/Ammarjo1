import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiPolicy } from '../../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../../gateway/api-policy.guard';
import { TenantContextGuard } from '../../identity/tenant-context.guard';
import { InternalApiKeyGuard } from '../../search/internal-api-key.guard';
import { GlobalSystemHealthService } from './global-system-health.service';
import { ProductionReadinessService } from './production-readiness.service';

/**
 * Read-only aggregated infra snapshot (region, Redis, DB, outbox, cache).
 */
@Controller('internal/ops')
@UseGuards(TenantContextGuard, ApiPolicyGuard, InternalApiKeyGuard)
@ApiPolicy({ auth: false, tenant: 'none', rateLimit: { rpm: 60 } })
export class GlobalHealthController {
  constructor(
    private readonly health: GlobalSystemHealthService,
    private readonly readiness: ProductionReadinessService,
  ) {}

  @Get('global-health')
  async globalHealth() {
    const snapshot = await this.health.getSnapshot();
    if (process.env.PRODUCTION_READINESS_ENFORCEMENT?.trim() === '1') {
      const processingBacklog = snapshot.outbox.lagByDomain.reduce((acc, x) => acc + x.processing, 0);
      this.readiness.assertProductionReady({
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
    }
    return snapshot;
  }
}
