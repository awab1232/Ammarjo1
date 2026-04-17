import { Injectable } from '@nestjs/common';
import { RedisClientService } from '../infrastructure/redis/redis-client.service';
import { isRedisInfrastructureEnabled } from '../infrastructure/redis/redis.config';

type Bucket = { windowStart: number; count: number };

/**
 * Fixed-window per-minute counters. In-memory by default; when REDIS_ENABLED=1 and Redis is ready,
 * uses Redis INCR + EXPIRE (shared across instances). Failures fall back to in-memory.
 */
@Injectable()
export class ApiRateLimitService {
  private readonly buckets = new Map<string, Bucket>();
  private readonly windowMs = 60_000;
  private readonly redisNamespace = process.env.RATE_LIMIT_NAMESPACE?.trim() || 'gateway';

  constructor(private readonly redis: RedisClientService) {}

  /** Maps internal keys to Redis-friendly names (user / tenant+user / ip). */
  private normalizeRedisRateKey(key: string): string {
    if (key.startsWith('uid:')) {
      return `user:${key.slice(4)}`;
    }
    if (key.startsWith('tenant:')) {
      const parts = key.split(':');
      if (parts.length >= 3) {
        return `tenant:${parts[1]}:user:${parts[2]}`;
      }
    }
    if (key.startsWith('ip:')) {
      return key;
    }
    return key;
  }

  /** Returns true if allowed, false if rate limited. */
  async tryConsume(key: string, rpm: number): Promise<boolean> {
    const maxPerWindow = Math.max(1, Math.floor(rpm));

    if (isRedisInfrastructureEnabled() && this.redis.isReady()) {
      try {
        const rk = `ratelimit:${this.redisNamespace}:${this.normalizeRedisRateKey(key)}`;
        const n = await this.redis.incr(rk);
        if (n == null) {
          return this.tryConsumeMemory(key, maxPerWindow);
        }
        if (n === 1) {
          await this.redis.expire(rk, Math.ceil(this.windowMs / 1000));
        }
        return n <= maxPerWindow;
      } catch {
        return this.tryConsumeMemory(key, maxPerWindow);
      }
    }

    return this.tryConsumeMemory(key, maxPerWindow);
  }

  private tryConsumeMemory(key: string, maxPerWindow: number): boolean {
    const now = Date.now();
    if (this.buckets.size > 20_000) {
      for (const [k, v] of this.buckets) {
        if (now - v.windowStart >= this.windowMs) {
          this.buckets.delete(k);
        }
      }
    }
    const b = this.buckets.get(key);
    if (b == null || now - b.windowStart >= this.windowMs) {
      this.buckets.set(key, { windowStart: now, count: 1 });
      return true;
    }
    if (b.count >= maxPerWindow) {
      return false;
    }
    b.count += 1;
    return true;
  }
}
