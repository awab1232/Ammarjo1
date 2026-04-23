import { Injectable, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { buildPgPoolConfig } from '../infrastructure/database/pg-ssl';

export type InboxRow = {
  id: string;
  userId: string;
  title: string;
  body: string;
  type: string;
  eventId: string | null;
  read: boolean;
  referenceId: string | null;
  createdAt: string;
};

@Injectable()
export class NotificationInboxService {
  private readonly pool: Pool | null;

  constructor() {
    const url = process.env.DATABASE_URL?.trim();
    this.pool = url
      ? new Pool(
          buildPgPoolConfig(url, {
            max: Number(process.env.NOTIFICATIONS_INBOX_PG_POOL_MAX || 6),
            idleTimeoutMillis: 30_000,
          }),
        )
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
      eventId: row.event_id != null ? String(row.event_id) : null,
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
        `SELECT id, user_id, title, body, type, event_id, read, reference_id, created_at
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
    eventId?: string | null;
    referenceId?: string | null;
    metadata?: Record<string, unknown> | null;
  }): Promise<{ id: string; deduplicated: boolean }> {
    const uid = input.userId.trim();
    if (!uid) throw new ServiceUnavailableException('target user required');
    const eventId = input.eventId?.trim() || null;
    return this.withClient(async (client) => {
      const ins = await client.query(
        `INSERT INTO user_notifications (user_id, title, body, type, event_id, reference_id, metadata)
         VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb)
         ON CONFLICT (user_id, event_id) WHERE event_id IS NOT NULL
         DO NOTHING
         RETURNING id`,
        [
          uid,
          input.title,
          input.body,
          input.type,
          eventId,
          input.referenceId ?? null,
          JSON.stringify(input.metadata ?? {}),
        ],
      );
      const row = ins.rows[0];
      if (row) {
        return { id: String(row['id']), deduplicated: false };
      }
      if (eventId != null) {
        const existing = await client.query<{ id: string }>(
          `SELECT id FROM user_notifications WHERE user_id = $1 AND event_id = $2 LIMIT 1`,
          [uid, eventId],
        );
        const existingId = existing.rows[0]?.id;
        if (existingId) {
          return { id: String(existingId), deduplicated: true };
        }
      }
      throw new ServiceUnavailableException('notification insert failed');
    });
  }

  async listSince(userId: string, sinceIso: string, limit = 50): Promise<InboxRow[]> {
    const uid = userId.trim();
    const lim = Math.min(Math.max(1, limit), 100);
    if (!uid) return [];
    const since = new Date(sinceIso);
    if (Number.isNaN(since.getTime())) return [];
    return this.withClient(async (client) => {
      const q = await client.query(
        `SELECT id, user_id, title, body, type, event_id, read, reference_id, created_at
         FROM user_notifications
         WHERE user_id = $1 AND created_at > $2::timestamptz
         ORDER BY created_at DESC
         LIMIT $3`,
        [uid, since.toISOString(), lim],
      );
      const rows = q.rows as Record<string, unknown>[];
      return rows.map((r) => this.mapRow(r));
    });
  }

  async unreadCount(userId: string): Promise<number> {
    const uid = userId.trim();
    if (!uid) return 0;
    return this.withClient(async (client) => {
      const q = await client.query<{ n: number }>(
        `SELECT COUNT(*)::int AS n FROM user_notifications WHERE user_id = $1 AND read = false`,
        [uid],
      );
      return Number(q.rows[0]?.n ?? 0);
    });
  }
}
