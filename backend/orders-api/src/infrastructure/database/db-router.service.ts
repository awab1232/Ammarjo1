import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { databaseReadReplicaUrl, isDbReadRoutingEnabled } from './db-router.config';

/**
 * Primary + optional read replica pools for orders-style workloads.
 * When DB_READ_ROUTING_ENABLED is off, [isActive] is false (callers use legacy pools).
 *
 * Security: logs use error messages only — never log connection URLs or env values.
 */
@Injectable()
export class DbRouterService implements OnModuleDestroy {
  private readonly logger = new Logger(DbRouterService.name);
  private primaryPool: Pool | null = null;
  private replicaPool: Pool | null = null;

  constructor() {
    if (!isDbReadRoutingEnabled()) {
      return;
    }
    const url = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
    if (!url) {
      return;
    }
    try {
      this.primaryPool = new Pool({
        connectionString: url,
        max: Number(process.env.ORDERS_PG_POOL_MAX || 10),
        idleTimeoutMillis: 30_000,
      });
      // Ensure every pooled connection speaks UTF-8 so Arabic text is stored/read without mojibake.
      this.primaryPool.on('connect', (c) => {
        void c.query("SET client_encoding TO 'UTF8'").catch(() => undefined);
      });
    } catch (e) {
      this.logger.warn(`[DbRouter] primary pool init failed: ${e instanceof Error ? e.message : String(e)}`);
      this.primaryPool = null;
    }
    const replicaUrl = databaseReadReplicaUrl();
    if (replicaUrl) {
      try {
        this.replicaPool = new Pool({
          connectionString: replicaUrl,
          max: Number(process.env.DB_READ_REPLICA_POOL_MAX || 8),
          idleTimeoutMillis: 30_000,
        });
        this.replicaPool.on('connect', (c) => {
          void c.query("SET client_encoding TO 'UTF8'").catch(() => undefined);
        });
      } catch (e) {
        this.logger.warn(`[DbRouter] replica pool init failed: ${e instanceof Error ? e.message : String(e)}`);
        this.replicaPool = null;
      }
    }
  }

  isActive(): boolean {
    return isDbReadRoutingEnabled() && this.primaryPool != null;
  }

  async onModuleDestroy(): Promise<void> {
    if (this.replicaPool) {
      await this.replicaPool.end();
      this.replicaPool = null;
    }
    if (this.primaryPool) {
      await this.primaryPool.end();
      this.primaryPool = null;
    }
  }

  async getWriteClient(): Promise<PoolClient | null> {
    if (!this.primaryPool) {
      return null;
    }
    try {
      return await this.primaryPool.connect();
    } catch (e) {
      this.logger.warn(`[DbRouter] primary connect failed: ${e instanceof Error ? e.message : String(e)}`);
      return null;
    }
  }

  /** Prefer replica when routing enabled and replica pool exists; never throws — falls back to primary. */
  async getReadClient(): Promise<PoolClient | null> {
    if (!this.primaryPool) {
      return null;
    }
    if (this.replicaPool) {
      try {
        return await this.replicaPool.connect();
      } catch (e) {
        this.logger.warn(`[DbRouter] replica read failed, using primary: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
    return this.getWriteClient();
  }

  async pingPrimary(): Promise<{ ok: boolean; error?: string }> {
    if (!this.primaryPool) {
      return { ok: false, error: 'not_configured' };
    }
    const c = await this.getWriteClient();
    if (!c) {
      return { ok: false, error: 'connect_failed' };
    }
    try {
      await c.query('SELECT 1');
      return { ok: true };
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) };
    } finally {
      c.release();
    }
  }

  async pingReplica(): Promise<{ ok: boolean; skipped?: boolean; error?: string }> {
    if (!isDbReadRoutingEnabled() || !this.replicaPool) {
      return { ok: false, skipped: true, error: 'replica_not_configured' };
    }
    try {
      const c = await this.replicaPool.connect();
      try {
        await c.query('SELECT 1');
        return { ok: true };
      } finally {
        c.release();
      }
    } catch (e) {
      return {
        ok: false,
        error: e instanceof Error ? e.message : String(e),
      };
    }
  }
}
