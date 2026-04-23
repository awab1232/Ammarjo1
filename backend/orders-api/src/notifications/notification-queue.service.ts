import { Injectable, Logger } from '@nestjs/common';
import { OrdersPgService } from '../orders/orders-pg.service';
import type { NotificationPayload } from './notifications.types';

export type QueueRow = {
  id: string;
  userId: string;
  title: string;
  body: string;
  data: Record<string, string>;
  retryCount: number;
  maxRetries: number;
  eventId: string | null;
};

@Injectable()
export class NotificationQueueService {
  private readonly logger = new Logger(NotificationQueueService.name);
  private schemaEnsured = false;
  private schemaEnsureInFlight: Promise<void> | null = null;

  constructor(private readonly pg: OrdersPgService) {
    console.log('QUEUE DB USING DATABASE_URL');
  }

  private async ensureSchema(): Promise<void> {
    if (this.schemaEnsured) return;
    if (this.schemaEnsureInFlight) {
      return this.schemaEnsureInFlight;
    }
    // If withWriteClient has no client yet, the old .then() path incorrectly set schemaEnsured=true
    // without running DDL, so the worker later SELECTs a missing table (relation does not exist).
    this.schemaEnsureInFlight = (async () => {
      const out = await this.pg.withWriteClient(async (c) => {
        await c.query(`
          DO $$
          BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_queue_status') THEN
              CREATE TYPE notification_queue_status AS ENUM ('pending', 'sent', 'failed');
            END IF;
          END$$;
        `);
        await c.query(`
          CREATE TABLE IF NOT EXISTS notifications_queue (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id TEXT NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            data JSONB,
            status notification_queue_status NOT NULL DEFAULT 'pending',
            retry_count INT NOT NULL DEFAULT 0,
            max_retries INT NOT NULL DEFAULT 3,
            event_id TEXT,
            inbox_notification_id UUID,
            last_attempt_at TIMESTAMPTZ,
            last_error TEXT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
          );
        `);
        await c.query(`
          CREATE INDEX IF NOT EXISTS idx_notifications_queue_status_created
          ON notifications_queue (status, created_at ASC);
        `);
        await c.query(`
          CREATE INDEX IF NOT EXISTS idx_notifications_queue_user_status
          ON notifications_queue (user_id, status);
        `);
        await c.query(`
          CREATE UNIQUE INDEX IF NOT EXISTS uq_notifications_queue_user_event_id
          ON notifications_queue (user_id, event_id)
          WHERE event_id IS NOT NULL;
        `);
        return true;
      });
      if (out == null) {
        const msg =
          'notifications_queue: no PostgreSQL write client (set DATABASE_URL, or run migration 036_notifications_queue_and_devices.sql)';
        this.logger.warn(msg);
        throw new Error(msg);
      }
      this.schemaEnsured = true;
    })()
      .catch((e) => {
        const reason = e instanceof Error ? e.message : String(e);
        this.logger.warn(`notifications_queue schema ensure failed: ${reason}`);
        throw e;
      })
      .finally(() => {
        this.schemaEnsureInFlight = null;
      });
    return this.schemaEnsureInFlight;
  }

  async enqueue(params: {
    userId: string;
    payload: NotificationPayload;
    eventId?: string;
    inboxNotificationId?: string;
  }): Promise<{ queued: boolean; queueId?: string; skippedReason?: string }> {
    await this.ensureSchema();
    const userId = params.userId.trim();
    const title = params.payload.title.trim();
    const body = params.payload.body.trim();
    const eventId = params.eventId?.trim() || null;
    if (!userId || !title || !body) {
      return { queued: false, skippedReason: 'invalid_payload' };
    }

    const data = params.payload.data ?? {};
    const out = await this.pg.withWriteClient(async (c) => {
      const r = await c.query<{ id: string }>(
        `INSERT INTO notifications_queue (
           user_id, title, body, data, status, retry_count, max_retries, event_id, inbox_notification_id
         ) VALUES ($1, $2, $3, $4::jsonb, 'pending', 0, 3, $5, $6::uuid)
         ON CONFLICT (user_id, event_id) WHERE event_id IS NOT NULL
         DO NOTHING
         RETURNING id`,
        [
          userId,
          title,
          body,
          JSON.stringify(data),
          eventId,
          params.inboxNotificationId?.trim() || null,
        ],
      );
      return r.rows[0]?.id ?? null;
    });

    if (!out) {
      if (eventId != null) {
        this.logger.debug(JSON.stringify({ kind: 'notification_queue_deduplicated', userId, eventId }));
        return { queued: false, skippedReason: 'duplicate_event_id' };
      }
      return { queued: false, skippedReason: 'enqueue_failed' };
    }
    return { queued: true, queueId: out };
  }

  async reservePending(limit: number): Promise<QueueRow[]> {
    await this.ensureSchema();
    const lim = Math.max(1, Math.min(limit, 100));
    const rows =
      (await this.pg.withWriteClient(async (c) => {
        const r = await c.query<{
          id: string;
          user_id: string;
          title: string;
          body: string;
          data: Record<string, string> | null;
          retry_count: number | string;
          max_retries: number | string;
          event_id: string | null;
        }>(
          `SELECT id, user_id, title, body, data, retry_count, max_retries, event_id
           FROM notifications_queue
           WHERE status = 'pending'
           ORDER BY created_at ASC
           LIMIT $1`,
          [lim],
        );
        return r.rows;
      })) ?? [];

    return rows.map((r) => ({
      id: String(r.id),
      userId: String(r.user_id),
      title: String(r.title),
      body: String(r.body),
      data: normalizeData(r.data),
      retryCount: intish(r.retry_count),
      maxRetries: intish(r.max_retries) || 3,
      eventId: r.event_id != null ? String(r.event_id) : null,
    }));
  }

  async markSent(id: string): Promise<void> {
    await this.ensureSchema();
    await this.pg.withWriteClient(async (c) => {
      await c.query(
        `UPDATE notifications_queue
         SET status = 'sent',
             last_attempt_at = NOW(),
             updated_at = NOW(),
             last_error = NULL
         WHERE id = $1::uuid`,
        [id],
      );
      return true;
    });
  }

  async markAttemptFailed(id: string, errorMessage: string): Promise<void> {
    await this.ensureSchema();
    const message = errorMessage.trim().slice(0, 400) || 'unknown_error';
    await this.pg.withWriteClient(async (c) => {
      await c.query(
        `UPDATE notifications_queue
         SET retry_count = retry_count + 1,
             last_attempt_at = NOW(),
             updated_at = NOW(),
             status = CASE WHEN retry_count + 1 >= max_retries THEN 'failed' ELSE 'pending' END,
             last_error = $2
         WHERE id = $1::uuid`,
        [id, message],
      );
      return true;
    });
  }
}

function normalizeData(input: Record<string, string> | null): Record<string, string> {
  if (input == null || typeof input !== 'object') return {};
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(input)) {
    const key = String(k).trim();
    if (!key) continue;
    out[key] = String(v ?? '');
  }
  return out;
}

function intish(v: unknown): number {
  if (typeof v === 'number' && Number.isFinite(v)) return Math.trunc(v);
  const n = Number.parseInt(String(v ?? '0'), 10);
  return Number.isFinite(n) ? n : 0;
}
