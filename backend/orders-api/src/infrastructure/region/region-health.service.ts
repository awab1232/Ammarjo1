import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { Pool } from 'pg';
import { buildPgPoolConfig } from '../database/pg-ssl';

export type RegionHealthMap = {
  JO: boolean;
  EG: boolean;
};

/**
 * Per-country PostgreSQL reachability (JO / EG checks over the same DATABASE_URL). If URL is not configured, that side is
 * treated as healthy (no data → safe default).
 */
@Injectable()
export class RegionHealthService implements OnModuleDestroy {
  private readonly logger = new Logger(RegionHealthService.name);
  private joPool: Pool | null = null;
  private egPool: Pool | null = null;

  constructor() {
    const jo = process.env.DATABASE_URL?.trim();
    const eg = process.env.DATABASE_URL?.trim();
    if (jo) {
      try {
        this.joPool = new Pool(
          buildPgPoolConfig(jo, {
            max: 1,
            idleTimeoutMillis: 10_000,
          }),
        );
      } catch (e) {
        this.logger.warn(`[RegionHealth] JO pool init: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
    if (eg) {
      try {
        this.egPool = new Pool(
          buildPgPoolConfig(eg, {
            max: 1,
            idleTimeoutMillis: 10_000,
          }),
        );
      } catch (e) {
        this.logger.warn(`[RegionHealth] EG pool init: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
  }

  async onModuleDestroy(): Promise<void> {
    if (this.joPool) {
      await this.joPool.end().catch(() => undefined);
      this.joPool = null;
    }
    if (this.egPool) {
      await this.egPool.end().catch(() => undefined);
      this.egPool = null;
    }
  }

  /** Missing URL for a side → true (assume healthy; avoid blocking routing). */
  async getRegionHealth(): Promise<RegionHealthMap> {
    const JO = this.joPool == null ? true : await this.pingPool(this.joPool, 'JO');
    const EG = this.egPool == null ? true : await this.pingPool(this.egPool, 'EG');
    return { JO, EG };
  }

  private async pingPool(pool: Pool, label: string): Promise<boolean> {
    try {
      const c = await pool.connect();
      try {
        await c.query('SELECT 1');
        return true;
      } finally {
        c.release();
      }
    } catch (e) {
      this.logger.debug(`[RegionHealth] ${label} ping failed: ${e instanceof Error ? e.message : String(e)}`);
      return false;
    }
  }
}
