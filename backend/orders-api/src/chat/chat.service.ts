import { Injectable, Logger, Optional, ServiceUnavailableException } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { DbRouterService } from '../infrastructure/database/db-router.service';

type ChatControlSnapshot = {
  conversationId: string;
  messageSent: number;
  messageRead: number;
  conversationCreated: number;
  lastEventAt: string | null;
};

@Injectable()
export class ChatService {
  private readonly logger = new Logger(ChatService.name);
  private readonly pool: Pool | null;

  constructor(@Optional() private readonly dbRouter?: DbRouterService) {
    if (this.dbRouter?.isActive()) {
      this.pool = null;
      return;
    }
    const url = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
    this.pool = url
      ? new Pool({
          connectionString: url,
          max: Number(process.env.CHAT_CONTROL_PG_POOL_MAX || 4),
          idleTimeoutMillis: 30_000,
        })
      : null;
  }

  private async getReadClient(): Promise<PoolClient> {
    if (this.dbRouter?.isActive()) {
      const c = await this.dbRouter.getReadClient();
      if (!c) throw new ServiceUnavailableException('chat control read client unavailable');
      return c;
    }
    if (!this.pool) throw new ServiceUnavailableException('chat control database not configured');
    return this.pool.connect();
  }

  private async withReadClient<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const c = await this.getReadClient();
    try {
      return await fn(c);
    } finally {
      c.release();
    }
  }

  private assertControlPlaneOnly(operation: string): void {
    if (operation.includes('message_persist') || operation.includes('message_write')) {
      const msg =
        'CHAT ARCHITECTURE LOCKED: message persistence must remain in Firebase realtime layer';
      this.logger.warn(msg);
      throw new Error(msg);
    }
  }

  async getOverview(limit = 50): Promise<{ conversations: ChatControlSnapshot[] }> {
    this.assertControlPlaneOnly('metadata_read');
    const lim = Math.min(Math.max(1, limit), 200);
    return this.withReadClient(async (client) => {
      const q = await client.query(
        `SELECT
           entity_id::text AS conversation_id,
           COUNT(*) FILTER (WHERE event_type = 'message.sent')::int AS message_sent,
           COUNT(*) FILTER (WHERE event_type = 'message.read')::int AS message_read,
           COUNT(*) FILTER (WHERE event_type = 'conversation.created')::int AS conversation_created,
           MAX(created_at) AS last_event_at
         FROM event_outbox
         WHERE event_type IN ('message.sent', 'message.read', 'conversation.created')
         GROUP BY entity_id
         ORDER BY MAX(created_at) DESC
         LIMIT $1`,
        [lim],
      );
      return {
        conversations: q.rows.map((row) => ({
          conversationId: String(row.conversation_id ?? ''),
          messageSent: Number(row.message_sent ?? 0),
          messageRead: Number(row.message_read ?? 0),
          conversationCreated: Number(row.conversation_created ?? 0),
          lastEventAt: row.last_event_at != null ? new Date(String(row.last_event_at)).toISOString() : null,
        })),
      };
    });
  }

  attemptMessagePersistence(): never {
    this.assertControlPlaneOnly('message_persist_attempt');
    throw new Error('unreachable');
  }
}

