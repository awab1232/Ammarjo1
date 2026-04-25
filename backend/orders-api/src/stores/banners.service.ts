import { Injectable, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Pool } from 'pg';

type BannerRow = {
  id: string;
  image_url: string;
  title: string;
  link_url: string | null;
  display_order: number;
  is_active: boolean;
  created_at: Date;
  updated_at: Date;
};

@Injectable()
export class BannersService {
  private readonly pool: Pool;
  private schemaReady = false;

  constructor() {
    const connectionString = process.env.DATABASE_URL?.trim();
    this.pool = new Pool({ connectionString });
  }

  private async ensureSchema(): Promise<void> {
    if (this.schemaReady) return;
    await this.pool.query(`
      CREATE TABLE IF NOT EXISTS banners (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        image_url TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        link_url TEXT,
        display_order INT NOT NULL DEFAULT 0,
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_banners_active_order
        ON banners (is_active, display_order, created_at DESC);
    `);
    this.schemaReady = true;
  }

  private map(row: BannerRow): Record<string, unknown> {
    return {
      id: row.id,
      imageUrl: row.image_url,
      title: row.title,
      link: row.link_url ?? '',
      order: Number(row.display_order ?? 0),
      isActive: row.is_active === true,
      createdAt: row.created_at?.toISOString?.() ?? null,
      updatedAt: row.updated_at?.toISOString?.() ?? null,
    };
  }

  async list(includeInactive = false): Promise<{ items: Record<string, unknown>[] }> {
    await this.ensureSchema();
    const q = includeInactive
      ? await this.pool.query<BannerRow>(
          `SELECT * FROM banners ORDER BY display_order ASC, created_at ASC`,
        )
      : await this.pool.query<BannerRow>(
          `SELECT * FROM banners WHERE is_active = TRUE ORDER BY display_order ASC, created_at ASC`,
        );
    return { items: q.rows.map((row) => this.map(row)) };
  }

  async create(body: {
    imageUrl?: string;
    title?: string;
    link?: string | null;
    order?: number;
    isActive?: boolean;
  }): Promise<Record<string, unknown>> {
    await this.ensureSchema();
    const id = randomUUID();
    const r = await this.pool.query<BannerRow>(
      `INSERT INTO banners (id, image_url, title, link_url, display_order, is_active)
       VALUES ($1::uuid, $2, $3, $4, $5, $6)
       RETURNING *`,
      [
        id,
        (body.imageUrl ?? '').trim(),
        (body.title ?? '').trim(),
        (body.link ?? '').trim() || null,
        Number(body.order ?? 0),
        body.isActive !== false,
      ],
    );
    return this.map(r.rows[0]);
  }

  async patch(
    id: string,
    body: {
      imageUrl?: string;
      title?: string;
      link?: string | null;
      order?: number;
      isActive?: boolean;
    },
  ): Promise<Record<string, unknown>> {
    await this.ensureSchema();
    const sets: string[] = [];
    const vals: unknown[] = [];
    let n = 1;
    if (body.imageUrl !== undefined) {
      sets.push(`image_url = $${n++}`);
      vals.push(body.imageUrl.trim());
    }
    if (body.title !== undefined) {
      sets.push(`title = $${n++}`);
      vals.push(body.title.trim());
    }
    if (body.link !== undefined) {
      sets.push(`link_url = $${n++}`);
      vals.push(body.link?.trim() || null);
    }
    if (body.order !== undefined) {
      sets.push(`display_order = $${n++}`);
      vals.push(Number(body.order));
    }
    if (body.isActive !== undefined) {
      sets.push(`is_active = $${n++}`);
      vals.push(body.isActive);
    }
    if (sets.length === 0) {
      const q = await this.pool.query<BannerRow>(`SELECT * FROM banners WHERE id = $1::uuid LIMIT 1`, [id.trim()]);
      if (q.rows.length === 0) throw new NotFoundException('banner_not_found');
      return this.map(q.rows[0]);
    }
    sets.push(`updated_at = NOW()`);
    vals.push(id.trim());
    const q = await this.pool.query<BannerRow>(
      `UPDATE banners SET ${sets.join(', ')} WHERE id = $${n}::uuid RETURNING *`,
      vals,
    );
    if (q.rows.length === 0) throw new NotFoundException('banner_not_found');
    return this.map(q.rows[0]);
  }

  async remove(id: string): Promise<{ ok: true }> {
    await this.ensureSchema();
    const q = await this.pool.query(`DELETE FROM banners WHERE id = $1::uuid`, [id.trim()]);
    if (q.rowCount === 0) throw new NotFoundException('banner_not_found');
    return { ok: true as const };
  }
}
