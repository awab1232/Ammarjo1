import { Injectable, Logger, Optional } from '@nestjs/common';
import { ConsistencyPolicyService } from '../../architecture/consistency/consistency-policy.service';
import { InfraTelemetryService } from '../infra-telemetry.service';
import { DataRoutingService } from '../routing/data-routing.service';
import { RedisClientService } from '../redis/redis-client.service';
import { isRedisInfrastructureEnabled } from '../redis/redis.config';
import { isResponseCacheEnabled, responseCacheTtlSeconds } from './cache.config';

type MemEntry = { value: string; expiresAt: number };

const CACHE_KEY_PREFIX = 'httpcache:';

/**
 * Optional HTTP response cache: Redis when enabled, else in-memory Map with TTL.
 * When CACHE_ENABLED is off, all operations are no-ops / misses (no behavior change vs uncached).
 */
@Injectable()
export class CacheService {
  private readonly logger = new Logger(CacheService.name);
  private readonly memory = new Map<string, MemEntry>();

  constructor(
    private readonly redis: RedisClientService,
    private readonly telemetry: InfraTelemetryService,
    private readonly dataRouting: DataRoutingService,
    @Optional() private readonly consistencyPolicy?: ConsistencyPolicyService,
  ) {}

  isCacheActive(): boolean {
    return isResponseCacheEnabled();
  }

  async getJson<T>(key: string): Promise<T | null> {
    if (!isResponseCacheEnabled()) {
      return null;
    }
    const fullKey = CACHE_KEY_PREFIX + this.dataRouting.resolveCacheNamespace() + key;
    try {
      if (isRedisInfrastructureEnabled() && this.redis.isReady()) {
        const raw = await this.redis.get(fullKey);
        if (raw == null) {
          this.telemetry.recordCacheMiss();
          return null;
        }
        this.telemetry.recordCacheHit();
        return JSON.parse(raw) as T;
      }
      const mem = this.memory.get(fullKey);
      if (mem == null || Date.now() >= mem.expiresAt) {
        if (mem) {
          this.memory.delete(fullKey);
        }
        this.telemetry.recordCacheMiss();
        this.consistencyPolicy?.logCacheMiss(fullKey);
        return null;
      }
      this.telemetry.recordCacheHit();
      return JSON.parse(mem.value) as T;
    } catch (e) {
      this.logger.debug(`[Cache] get ${key}: ${e instanceof Error ? e.message : String(e)}`);
      this.telemetry.recordCacheMiss();
      this.consistencyPolicy?.logCacheMiss(CACHE_KEY_PREFIX + this.dataRouting.resolveCacheNamespace() + key);
      return null;
    }
  }

  async setJson(key: string, value: unknown, ttlSec?: number): Promise<void> {
    if (!isResponseCacheEnabled()) {
      return;
    }
    const ttl = ttlSec ?? responseCacheTtlSeconds();
    const fullKey = CACHE_KEY_PREFIX + this.dataRouting.resolveCacheNamespace() + key;
    const payload = JSON.stringify(value);
    try {
      if (isRedisInfrastructureEnabled() && this.redis.isReady()) {
        await this.redis.set(fullKey, payload, ttl);
        return;
      }
      this.memory.set(fullKey, { value: payload, expiresAt: Date.now() + ttl * 1000 });
      this.pruneMemoryIfLarge();
    } catch (e) {
      this.logger.debug(`[Cache] set ${key}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  async del(key: string): Promise<void> {
    if (!isResponseCacheEnabled()) {
      return;
    }
    const fullKey = CACHE_KEY_PREFIX + this.dataRouting.resolveCacheNamespace() + key;
    try {
      if (isRedisInfrastructureEnabled() && this.redis.isReady()) {
        await this.redis.del(fullKey);
      }
      this.memory.delete(fullKey);
    } catch (e) {
      this.logger.debug(`[Cache] del ${key}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  private pruneMemoryIfLarge(): void {
    if (this.memory.size <= 5000) {
      return;
    }
    const now = Date.now();
    for (const [k, v] of this.memory) {
      if (now >= v.expiresAt) {
        this.memory.delete(k);
      }
    }
  }
}
