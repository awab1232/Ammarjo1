import { Injectable } from '@nestjs/common';

/**
 * Cross-cutting infra counters (Redis ops, cache, locks) merged into ops dashboards.
 * Lives in infrastructure to avoid circular imports with EventsCore.
 */
@Injectable()
export class InfraTelemetryService {
  private redisOps = 0;
  private cacheHits = 0;
  private cacheMisses = 0;
  private lockContentions = 0;

  recordRedisOp(count = 1): void {
    this.redisOps += count;
  }

  recordCacheHit(): void {
    this.cacheHits++;
  }

  recordCacheMiss(): void {
    this.cacheMisses++;
  }

  recordLockContention(): void {
    this.lockContentions++;
  }

  getDistributedInfraSnapshot(): {
    redis_ops_count: number;
    cache_hit_ratio: number | null;
    lock_contention_count: number;
  } {
    const total = this.cacheHits + this.cacheMisses;
    return {
      redis_ops_count: this.redisOps,
      cache_hit_ratio: total > 0 ? Math.round((this.cacheHits / total) * 10_000) / 10_000 : null,
      lock_contention_count: this.lockContentions,
    };
  }
}
