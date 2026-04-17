import { Injectable, Optional } from '@nestjs/common';
import {
  type GlobalCountryCode,
  getGlobalRegionContext,
} from '../../architecture/global-region-context.service';
import { EdgeContextService } from '../edge/edge-context.service';
import { MultiRegionStrategyService } from '../region/multi-region-strategy.service';
import { isMultiRegionStrategyEnabled } from '../region/region-strategy.config';
import { isMultiRegionRoutingEnabled } from './routing.config';

export type DatabaseRoutingKey = 'primary_pg_jo' | 'primary_pg_eg' | 'primary';

export type ReadReplicaRoutingKey = 'replica_jo' | 'replica_eg' | 'primary';

/**
 * Centralized logical routing for DB, cache namespace, outbox region, and future Algolia.
 * When ENABLE_MULTI_REGION is off, all methods return backward-compatible defaults.
 * When MULTI_REGION_STRATEGY_ENABLED=1, write/read pools follow failover + health.
 */
@Injectable()
export class DataRoutingService {
  constructor(
    @Optional() private readonly strategy?: MultiRegionStrategyService,
    @Optional() private readonly edgeContext?: EdgeContextService,
  ) {}

  resolveDatabase(): DatabaseRoutingKey {
    if (!isMultiRegionRoutingEnabled()) {
      return 'primary';
    }
    if (isMultiRegionStrategyEnabled() && this.strategy) {
      const w = this.strategy.resolveWriteRegion();
      return w === 'JO' ? 'primary_pg_jo' : 'primary_pg_eg';
    }
    const c = getGlobalRegionContext().country;
    if (c === 'JO') {
      return 'primary_pg_jo';
    }
    if (c === 'EG') {
      return 'primary_pg_eg';
    }
    return 'primary';
  }

  resolveReadReplica(): ReadReplicaRoutingKey {
    if (!isMultiRegionRoutingEnabled()) {
      return 'primary';
    }
    if (isMultiRegionStrategyEnabled() && this.strategy) {
      let narrow: 'JO' | 'EG' | null;
      const edgeHint = this.edgeContext?.getLatencySensitiveReadHint();
      if (edgeHint != null) {
        narrow = edgeHint;
      } else {
        const hint = getGlobalRegionContext().country;
        narrow = hint === 'JO' || hint === 'EG' ? hint : null;
      }
      const r = this.strategy.resolveReadRegion(narrow);
      if (r === null) {
        return this.resolveReadReplicaFromAls();
      }
      return r === 'JO' ? 'replica_jo' : 'replica_eg';
    }
    return this.resolveReadReplicaFromAls();
  }

  private resolveReadReplicaFromAls(): ReadReplicaRoutingKey {
    const c = getGlobalRegionContext().country;
    if (c === 'JO') {
      return 'replica_jo';
    }
    if (c === 'EG') {
      return 'replica_eg';
    }
    return 'primary';
  }

  /**
   * Cache key segment (empty when multi-region off). Example enabled: `cache:jo:` → keys like `httpcache:cache:jo:...`
   */
  resolveCacheNamespace(): string {
    if (!isMultiRegionRoutingEnabled()) {
      return '';
    }
    const c: GlobalCountryCode = getGlobalRegionContext().country;
    if (c === 'JO') {
      return 'cache:jo:';
    }
    if (c === 'EG') {
      return 'cache:eg:';
    }
    return '';
  }

  /** Outbox `region` column / routing hint (lowercase slug). */
  resolveEventOutboxRegion(): string | null {
    if (!isMultiRegionRoutingEnabled()) {
      return null;
    }
    const c = getGlobalRegionContext().country;
    if (c === 'JO') {
      return 'jo';
    }
    if (c === 'EG') {
      return 'eg';
    }
    return null;
  }

  /** Future: per-country Algolia index; today returns env index name unchanged. */
  resolveAlgoliaIndex(): string | null {
    return process.env.ALGOLIA_INDEX_NAME?.trim() || null;
  }
}
