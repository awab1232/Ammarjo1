import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { Pool } from 'pg';

/**
 * Production: verifies critical FK/index artifacts from sql/production-constraints.sql
 * and sql/production-hardening-indexes.sql are present. Opt out: SKIP_DB_INTEGRITY_CHECK=1
 */
@Injectable()
export class DatabaseIntegrityService implements OnModuleInit {
  private readonly logger = new Logger(DatabaseIntegrityService.name);

  async onModuleInit(): Promise<void> {
    if (process.env.NODE_ENV !== 'production') {
      return;
    }
    if (process.env.SKIP_DB_INTEGRITY_CHECK?.trim() === '1') {
      this.logger.warn('SKIP_DB_INTEGRITY_CHECK=1 — database constraint verification skipped');
      return;
    }
    const url = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
    if (!url) {
      return;
    }

    const pool = new Pool({ connectionString: url, max: 1 });
    const client = await pool.connect();
    try {
      const constraintNames = ['fk_orders_user_firebase', 'fk_products_store'] as const;
      for (const name of constraintNames) {
        const r = await client.query(`SELECT 1 FROM pg_constraint WHERE conname = $1 LIMIT 1`, [name]);
        if (r.rows.length === 0) {
          throw new Error(`[DatabaseIntegrity] Missing constraint ${name} — apply sql/production-constraints.sql`);
        }
      }
      const indexNames = ['uq_users_email_normalized', 'uq_product_variants_product_sku'] as const;
      for (const name of indexNames) {
        const r = await client.query(
          `SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = $1 LIMIT 1`,
          [name],
        );
        if (r.rows.length === 0) {
          throw new Error(
            `[DatabaseIntegrity] Missing index ${name} — apply sql/production-constraints.sql and sql/production-hardening-indexes.sql`,
          );
        }
      }
      this.logger.log('Database integrity checks passed (constraints + indexes)');
    } finally {
      client.release();
      await pool.end();
    }
  }
}
