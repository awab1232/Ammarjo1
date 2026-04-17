import { randomBytes } from 'node:crypto';
import { Injectable, Logger } from '@nestjs/common';
import { InfraTelemetryService } from '../infra-telemetry.service';
import { RedisClientService } from '../redis/redis-client.service';
import { isRedisInfrastructureEnabled } from '../redis/redis.config';

const RELEASE_LUA = `
if redis.call("get", KEYS[1]) == ARGV[1] then
  return redis.call("del", KEYS[1])
else
  return 0
end
`;

/**
 * Distributed locks: Redis SET NX PX when enabled (multi-instance safe), else in-process
 * promise chain per key (single-node serialization).
 */
@Injectable()
export class DistributedLockService {
  private readonly logger = new Logger(DistributedLockService.name);
  private readonly memChains = new Map<string, Promise<unknown>>();

  constructor(
    private readonly redis: RedisClientService,
    private readonly telemetry: InfraTelemetryService,
  ) {}

  async acquireLock(key: string, ttlMs: number): Promise<string | null> {
    const lockKey = `lock:${key}`;
    if (isRedisInfrastructureEnabled() && this.redis.isReady()) {
      const token = randomBytes(16).toString('hex');
      try {
        const ok = await this.redis.setNxPx(lockKey, token, ttlMs);
        if (!ok) {
          this.telemetry.recordLockContention();
          return null;
        }
        return token;
      } catch (e) {
        this.logger.debug(`[Lock] acquire: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
    return this.acquireMemoryFallback(key, ttlMs);
  }

  async releaseLock(key: string, token: string): Promise<void> {
    const lockKey = `lock:${key}`;
    if (isRedisInfrastructureEnabled() && this.redis.isReady()) {
      try {
        await this.redis.eval(RELEASE_LUA, 1, lockKey, token);
      } catch (e) {
        this.logger.debug(`[Lock] release: ${e instanceof Error ? e.message : String(e)}`);
      }
      return;
    }
    const cur = this.memHolders.get(key);
    if (cur?.token === token) {
      this.memHolders.delete(key);
    }
  }

  /**
   * Redis: returns null if lock not acquired (another instance holds it).
   * In-memory: always runs fn (serialized per key); returns null only if inner fn throws? No — returns T.
   */
  async withLock<T>(key: string, ttlMs: number, fn: () => Promise<T>): Promise<T | null> {
    if (isRedisInfrastructureEnabled() && this.redis.isReady()) {
      const lockKey = `lock:${key}`;
      const token = randomBytes(16).toString('hex');
      try {
        const ok = await this.redis.setNxPx(lockKey, token, ttlMs);
        if (!ok) {
          this.telemetry.recordLockContention();
          return null;
        }
        try {
          return await fn();
        } finally {
          try {
            await this.redis.eval(RELEASE_LUA, 1, lockKey, token);
          } catch (e) {
            this.logger.debug(`[Lock] withLock release: ${e instanceof Error ? e.message : String(e)}`);
          }
        }
      } catch (e) {
        this.logger.debug(`[Lock] withLock redis: ${e instanceof Error ? e.message : String(e)}`);
        return this.withMemoryExclusive(key, fn);
      }
    }
    return this.withMemoryExclusive(key, fn);
  }

  private memHolders = new Map<string, { token: string; until: number }>();

  private acquireMemoryFallback(key: string, ttlMs: number): string | null {
    const now = Date.now();
    const cur = this.memHolders.get(key);
    if (cur && now < cur.until) {
      this.telemetry.recordLockContention();
      return null;
    }
    const token = randomBytes(8).toString('hex');
    this.memHolders.set(key, { token, until: now + ttlMs });
    return token;
  }

  private async withMemoryExclusive<T>(key: string, fn: () => Promise<T>): Promise<T> {
    const prev = this.memChains.get(key) ?? Promise.resolve();
    let release!: () => void;
    const done = new Promise<void>((r) => {
      release = r;
    });
    const tail = prev.then(() => done);
    this.memChains.set(key, tail);
    await prev;
    try {
      return await fn();
    } finally {
      release();
    }
  }
}
