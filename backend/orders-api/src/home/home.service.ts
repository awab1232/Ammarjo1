import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';

@Injectable()
export class HomeService {
  private readonly pool: Pool | null;
  private tableReady = false;

  constructor() {
    const url = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
    this.pool = url
      ? new Pool({
          connectionString: url,
          max: Number(process.env.HOME_PG_POOL_MAX || 8),
          idleTimeoutMillis: 30_000,
        })
      : null;
  }

  private requireDb(): Pool {
    if (!this.pool) throw new ServiceUnavailableException('home database not configured');
    return this.pool;
  }

  private async withClient<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.requireDb().connect();
    try {
      await this.ensureTable(client);
      return await fn(client);
    } finally {
      client.release();
    }
  }

  private async ensureTable(client: PoolClient): Promise<void> {
    if (this.tableReady) return;
    await client.query(`
      CREATE TABLE IF NOT EXISTS home_sections (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name TEXT NOT NULL,
        image TEXT,
        type TEXT NOT NULL,
        is_active BOOLEAN DEFAULT TRUE,
        sort_order INT DEFAULT 0,
        created_at TIMESTAMP DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_home_sections_active_sort ON home_sections (is_active, sort_order, created_at);
      ALTER TABLE home_sections ADD COLUMN IF NOT EXISTS store_type_id uuid;
      CREATE INDEX IF NOT EXISTS idx_home_sections_store_type ON home_sections (store_type_id, is_active, sort_order, created_at);
      CREATE TABLE IF NOT EXISTS sub_categories (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        home_section_id UUID REFERENCES home_sections(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        image TEXT,
        sort_order INT DEFAULT 0,
        is_active BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMP DEFAULT NOW()
      );
      CREATE TABLE IF NOT EXISTS system_versions (
        key text PRIMARY KEY,
        version bigint NOT NULL DEFAULT 1,
        updated_at timestamptz NOT NULL DEFAULT now()
      );
      INSERT INTO system_versions (key, version) VALUES ('home_sections_version', 1)
      ON CONFLICT (key) DO NOTHING;
      CREATE INDEX IF NOT EXISTS idx_sub_categories_section_active_sort
        ON sub_categories (home_section_id, is_active, sort_order, created_at);
    `);
    this.tableReady = true;
  }

  async getSections(storeTypeId?: string): Promise<{ data: unknown[]; items: unknown[]; version: number }> {
    return this.withClient(async (client) => {
      const sid = storeTypeId?.trim() ?? '';
      const q = sid.length === 0
          ? await client.query(
              `SELECT id::text, name, image, type, store_type_id::text AS "storeTypeId",
                      is_active AS "isActive", sort_order AS "sortOrder", created_at AS "createdAt"
               FROM home_sections
               WHERE is_active = TRUE
               ORDER BY sort_order ASC, created_at ASC`,
            )
          : await client.query(
              `SELECT id::text, name, image, type, store_type_id::text AS "storeTypeId",
                      is_active AS "isActive", sort_order AS "sortOrder", created_at AS "createdAt"
               FROM home_sections
               WHERE is_active = TRUE AND store_type_id = $1::uuid
               ORDER BY sort_order ASC, created_at ASC`,
              [sid],
            );
      const vq = await client.query(
        `SELECT version FROM system_versions WHERE key = 'home_sections_version' LIMIT 1`,
      );
      const version = Number(vq.rows[0]?.['version'] ?? 1);
      return { data: q.rows, items: q.rows, version };
    });
  }

  async getSubCategories(sectionId: string): Promise<{ data: unknown[]; items: unknown[]; version: number }> {
    const sid = sectionId.trim();
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id::text, home_section_id::text AS "home_section_id", name, image,
                sort_order AS "sortOrder", is_active AS "isActive", created_at AS "createdAt"
         FROM sub_categories
         WHERE home_section_id = $1::uuid
           AND is_active = TRUE
         ORDER BY sort_order ASC, created_at ASC`,
        [sid],
      );
      const vq = await client.query(
        `SELECT version FROM system_versions WHERE key = 'home_sections_version' LIMIT 1`,
      );
      const version = Number(vq.rows[0]?.['version'] ?? 1);
      return { data: q.rows, items: q.rows, version };
    });
  }
}
