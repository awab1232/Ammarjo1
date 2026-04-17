import { Injectable, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';

export type InboxRow = {
  id: string;
  userId: string;
  title: string;
  body: string;
  type: string;
  read: boolean;
  referenceId: string | null;
  createdAt: string;
};

@Injectable()
export class NotificationInboxService {
  private readonly pool: Pool | null;

  constructor() {
    const url = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
    this.pool = url
      ? new Pool({
          connectionString: url,
          max: Number(process.env.NOTIFICATIONS_INBOX_PG_POOL_MAX || 6),
          idleTimeoutMillis: 30_000,
        })
      : null;
  }

  private requireDb(): Pool {
    if (!this.pool) throw new ServiceUnavailableException('notifications database not configured');
    return this.pool;
  }

  private async withClient<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.requireDb().connect();
    try {
      return await fn(client);
    } finally {
      client.release();
    }
  }

  private mapRow(row: Record<string, unknown>): InboxRow {
    return {
      id: String(row.id),
      userId: String(row.user_id),
      title: String(row.title ?? ''),
      body: String(row.body ?? ''),
      type: String(row.type ?? 'general'),
      read: row.read === true,
      referenceId: row.reference_id != null ? String(row.reference_id) : null,
      createdAt: new Date(String(row.created_at)).toISOString(),
    };
  }

  async list(
    userId: string,
    limit = 50,
    offset = 0,
  ): Promise<{ items: InboxRow[]; total: number }> {
    const uid = userId.trim();
    if (!uid) return { items: [], total: 0 };
    const lim = Math.min(Math.max(1, limit), 100);
    const off = Math.max(0, offset);
    return this.withClient(async (client) => {
      const c = await client.query(`SELECT COUNT(*)::int AS n FROM user_notifications WHERE user_id = $1`, [uid]);
      const total = Number(c.rows[0]?.['n'] ?? 0);
      const q = await client.query(
        `SELECT id, user_id, title, body, type, read, reference_id, created_at
         FROM user_notifications
         WHERE user_id = $1
         ORDER BY created_at DESC
         LIMIT $2 OFFSET $3`,
        [uid, lim, off],
      );
      const rows = q.rows as Record<string, unknown>[];
      return { items: rows.map((r) => this.mapRow(r)), total };
    });
  }

  async markRead(userId: string, id: string): Promise<{ ok: true }> {
    const uid = userId.trim();
    const nid = id.trim();
    if (!uid || !nid) throw new NotFoundException();
    return this.withClient(async (client) => {
      const r = await client.query(
        `UPDATE user_notifications SET read = true WHERE id = $1::uuid AND user_id = $2`,
        [nid, uid],
      );
      if (r.rowCount === 0) throw new NotFoundException();
      return { ok: true as const };
    });
  }

  async insertRecord(input: {
    userId: string;
    title: string;
    body: string;
    type: string;
    referenceId?: string | null;
    metadata?: Record<string, unknown> | null;
  }): Promise<{ id: string }> {
    const uid = input.userId.trim();
    if (!uid) throw new ServiceUnavailableException('target user required');
    return this.withClient(async (client) => {
      const ins = await client.query(
        `INSERT INTO user_notifications (user_id, title, body, type, reference_id, metadata)
         VALUES ($1, $2, $3, $4, $5, $6::jsonb)
         RETURNING id`,
        [
          uid,
          input.title,
          input.body,
          input.type,
          input.referenceId ?? null,
          JSON.stringify(input.metadata ?? {}),
        ],
      );
      const row = ins.rows[0];
      if (!row) throw new ServiceUnavailableException('notification insert failed');
      return { id: String(row['id']) };
    });
  }
}
