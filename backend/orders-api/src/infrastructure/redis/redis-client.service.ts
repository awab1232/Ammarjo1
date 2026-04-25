import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import Redis from 'ioredis';
import { InfraTelemetryService } from '../infra-telemetry.service';
import { getRedisUrl, isRedisInfrastructureEnabled } from './redis.config';

/**
 * Optional Redis client. When disabled or misconfigured, all methods are null-safe no-ops
 * (reads return null, writes resolve without throwing) so requests never fail on Redis.
 */
@Injectable()
export class RedisClientService implements OnModuleDestroy, OnModuleInit {
  private readonly logger = new Logger(RedisClientService.name);
  private client: Redis | null = null;

  constructor(private readonly telemetry: InfraTelemetryService) {}

  onModuleInit(): void {
    console.log('[Redis] REDIS_URL value present:', !!process.env.REDIS_URL);
    console.log('[Redis] Attempting connection...');
    this.ensureClient();
  }

  /** True when REDIS_ENABLED=1, URL set, and connection attempted successfully. */
  isReady(): boolean {
    return this.client != null && this.client.status === 'ready';
  }

  onModuleDestroy(): void {
    if (this.client) {
      void this.client.quit().catch(() => undefined);
      this.client = null;
    }
  }

  private ensureClient(): Redis | null {
    if (!isRedisInfrastructureEnabled()) {
      return null;
    }
    if (this.client != null) {
      return this.client;
    }
    const url = getRedisUrl();
    if (!url) {
      return null;
    }
    try {
      const c = new Redis(url, {
        maxRetriesPerRequest: 2,
        enableReadyCheck: true,
        lazyConnect: true,
      });
      c.on('error', (err) => {
        this.logger.warn(`[Redis] ${err.message}`);
      });
      void c.connect().catch((err) => {
        this.logger.warn(`[Redis] connect failed: ${err instanceof Error ? err.message : String(err)}`);
        console.error('[Redis] Full error:', JSON.stringify(err));
      });
      this.client = c;
      return c;
    } catch (e) {
      this.logger.warn(`[Redis] init failed: ${e instanceof Error ? e.message : String(e)}`);
      console.error('[Redis] Full error:', JSON.stringify(e));
      return null;
    }
  }

  async get(key: string): Promise<string | null> {
    const c = this.ensureClient();
    if (!c) return null;
    try {
      this.telemetry.recordRedisOp(1);
      const v = await c.get(key);
      return v;
    } catch (e) {
      this.logger.debug(`[Redis] get ${key}: ${e instanceof Error ? e.message : String(e)}`);
      return null;
    }
  }

  async set(key: string, value: string, ttlSeconds?: number): Promise<boolean> {
    const c = this.ensureClient();
    if (!c) return false;
    try {
      this.telemetry.recordRedisOp(1);
      if (ttlSeconds != null && ttlSeconds > 0) {
        await c.set(key, value, 'EX', ttlSeconds);
      } else {
        await c.set(key, value);
      }
      return true;
    } catch (e) {
      this.logger.debug(`[Redis] set ${key}: ${e instanceof Error ? e.message : String(e)}`);
      return false;
    }
  }

  async del(key: string): Promise<boolean> {
    const c = this.ensureClient();
    if (!c) return false;
    try {
      this.telemetry.recordRedisOp(1);
      await c.del(key);
      return true;
    } catch (e) {
      this.logger.debug(`[Redis] del ${key}: ${e instanceof Error ? e.message : String(e)}`);
      return false;
    }
  }

  async hget(key: string, field: string): Promise<string | null> {
    const c = this.ensureClient();
    if (!c) return null;
    try {
      this.telemetry.recordRedisOp(1);
      const v = await c.hget(key, field);
      return v ?? null;
    } catch (e) {
      this.logger.debug(`[Redis] hget ${key}: ${e instanceof Error ? e.message : String(e)}`);
      return null;
    }
  }

  async hset(key: string, field: string, value: string): Promise<boolean> {
    const c = this.ensureClient();
    if (!c) return false;
    try {
      this.telemetry.recordRedisOp(1);
      await c.hset(key, field, value);
      return true;
    } catch (e) {
      this.logger.debug(`[Redis] hset ${key}: ${e instanceof Error ? e.message : String(e)}`);
      return false;
    }
  }

  async incr(key: string): Promise<number | null> {
    const c = this.ensureClient();
    if (!c) return null;
    try {
      this.telemetry.recordRedisOp(1);
      return await c.incr(key);
    } catch (e) {
      this.logger.debug(`[Redis] incr ${key}: ${e instanceof Error ? e.message : String(e)}`);
      return null;
    }
  }

  async expire(key: string, seconds: number): Promise<boolean> {
    const c = this.ensureClient();
    if (!c) return false;
    try {
      this.telemetry.recordRedisOp(1);
      const r = await c.expire(key, seconds);
      return r === 1;
    } catch (e) {
      this.logger.debug(`[Redis] expire ${key}: ${e instanceof Error ? e.message : String(e)}`);
      return false;
    }
  }

  /**
   * SET key value NX PX ttlMs — returns token if lock acquired, null otherwise.
   */
  async setNxPx(key: string, value: string, ttlMs: number): Promise<boolean> {
    const c = this.ensureClient();
    if (!c) return false;
    try {
      this.telemetry.recordRedisOp(1);
      const r = await c.set(key, value, 'PX', ttlMs, 'NX');
      return r === 'OK';
    } catch (e) {
      this.logger.debug(`[Redis] setNxPx ${key}: ${e instanceof Error ? e.message : String(e)}`);
      return false;
    }
  }

  async eval(script: string, numKeys: number, ...args: (string | Buffer)[]): Promise<unknown> {
    const c = this.ensureClient();
    if (!c) return null;
    try {
      this.telemetry.recordRedisOp(1);
      return await c.eval(script, numKeys, ...args);
    } catch (e) {
      this.logger.debug(`[Redis] eval: ${e instanceof Error ? e.message : String(e)}`);
      return null;
    }
  }
}
