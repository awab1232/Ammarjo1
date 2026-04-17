import { Global, Module } from '@nestjs/common';
import { ConsistencyContractService } from '../architecture/consistency/consistency-contract.service';
import { ConsistencyPolicyService } from '../architecture/consistency/consistency-policy.service';
import { GlobalRegionContextService } from '../architecture/global-region-context.service';
import { CacheService } from './cache/cache.service';
import { EdgeContextService } from './edge/edge-context.service';
import { RequestClassificationService } from './edge/request-classification.service';
import { DbRouterService } from './database/db-router.service';
import { InfraTelemetryService } from './infra-telemetry.service';
import { DistributedLockService } from './locks/distributed-lock.service';
import { DataRoutingService } from './routing/data-routing.service';
import { MultiRegionStrategyService } from './region/multi-region-strategy.service';
import { RegionHealthService } from './region/region-health.service';
import { RegionService } from './region/region.service';
import { RedisClientService } from './redis/redis-client.service';
import { CircuitBreakerService } from './resilience/circuit-breaker.service';
import { RetryPolicyService } from './resilience/retry-policy.service';
import { TenantRegionService } from './tenant/tenant-region.service';
import { DatabaseIntegrityService } from './database/database-integrity.service';

@Global()
@Module({
  providers: [
    DatabaseIntegrityService,
    InfraTelemetryService,
    RedisClientService,
    DistributedLockService,
    CacheService,
    DbRouterService,
    TenantRegionService,
    RegionService,
    CircuitBreakerService,
    RetryPolicyService,
    GlobalRegionContextService,
    ConsistencyContractService,
    ConsistencyPolicyService,
    RegionHealthService,
    MultiRegionStrategyService,
    EdgeContextService,
    RequestClassificationService,
    DataRoutingService,
  ],
  exports: [
    InfraTelemetryService,
    RedisClientService,
    DistributedLockService,
    CacheService,
    DbRouterService,
    TenantRegionService,
    RegionService,
    CircuitBreakerService,
    RetryPolicyService,
    GlobalRegionContextService,
    ConsistencyContractService,
    ConsistencyPolicyService,
    RegionHealthService,
    MultiRegionStrategyService,
    EdgeContextService,
    RequestClassificationService,
    DataRoutingService,
  ],
})
export class InfrastructureModule {}
