import { Injectable, Optional, ServiceUnavailableException } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { DbRouterService } from '../infrastructure/database/db-router.service';

@Injectable()
export class AdminAnalyticsService {
  private readonly pool: Pool | null;

  constructor(@Optional() private readonly dbRouter?: DbRouterService) {
    if (this.dbRouter?.isActive()) {
      this.pool = null;
      return;
    }
    const url = process.env.DATABASE_URL?.trim();
    this.pool = url
      ? new Pool({
          connectionString: url,
          max: Number(process.env.ADMIN_ANALYTICS_PG_POOL_MAX || 6),
          idleTimeoutMillis: 30_000,
        })
      : null;
  }

  private async getReadClient(): Promise<PoolClient> {
    if (this.dbRouter?.isActive()) {
      const c = await this.dbRouter.getReadClient();
      if (!c) throw new ServiceUnavailableException('admin analytics read client unavailable');
      return c;
    }
    if (!this.pool) throw new ServiceUnavailableException('admin analytics database not configured');
    return this.pool.connect();
  }

  private async withReadClient<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.getReadClient();
    try {
      return await fn(client);
    } finally {
      client.release();
    }
  }

  overview() {
    return this.withReadClient(async (client) => {
      const q = await client.query(
        `SELECT
           (SELECT COUNT(*)::int FROM orders) AS orders_count,
           (SELECT COUNT(*)::int FROM service_requests) AS service_requests_count,
           (SELECT COUNT(*)::int FROM ratings_reviews) AS ratings_count,
           (SELECT COUNT(*)::int FROM wholesale_orders) AS wholesale_orders_count,
           (SELECT COUNT(*)::int FROM event_outbox WHERE status = 'failed') AS dlq_count,
           (SELECT COUNT(*)::int FROM event_outbox WHERE status = 'pending' AND next_attempt_at <= NOW()) AS outbox_lag`,
      );
      const row = q.rows[0] ?? {};
      return {
        ordersCount: Number(row.orders_count ?? 0),
        serviceRequestsCount: Number(row.service_requests_count ?? 0),
        ratingsCount: Number(row.ratings_count ?? 0),
        wholesaleOrdersCount: Number(row.wholesale_orders_count ?? 0),
        dlqCount: Number(row.dlq_count ?? 0),
        eventOutboxLag: Number(row.outbox_lag ?? 0),
      };
    });
  }

  kpis() {
    return this.withReadClient(async (client) => {
      const q = await client.query(
        `SELECT
           (SELECT COALESCE(AVG(avg_rating), 0)::numeric(10,4) FROM ratings_aggregates WHERE target_type = 'technician') AS avg_technician_rating,
           (SELECT COUNT(*)::int FROM service_requests WHERE status = 'completed') AS completed_service_requests,
           (SELECT COUNT(*)::int FROM wholesale_orders WHERE created_at >= NOW() - interval '24 hours') AS wholesale_activity_24h,
           (SELECT COALESCE(AVG(EXTRACT(EPOCH FROM (NOW() - next_attempt_at))), 0)::numeric(12,2)
              FROM event_outbox WHERE status = 'pending' AND next_attempt_at <= NOW()) AS avg_outbox_delay_seconds`,
      );
      const row = q.rows[0] ?? {};
      return {
        avgTechnicianRating: Number(row.avg_technician_rating ?? 0),
        completedServiceRequests: Number(row.completed_service_requests ?? 0),
        wholesaleActivity24h: Number(row.wholesale_activity_24h ?? 0),
        avgOutboxDelaySeconds: Number(row.avg_outbox_delay_seconds ?? 0),
      };
    });
  }

  activityFeed(limit = 50) {
    const lim = Math.min(Math.max(1, limit), 200);
    return this.withReadClient(async (client) => {
      const q = await client.query(
        `SELECT
           event_id::text AS id,
           event_type,
           entity_id,
           status,
           created_at
         FROM event_outbox
         ORDER BY created_at DESC
         LIMIT $1`,
        [lim],
      );
      return q.rows.map((row) => ({
        id: String(row.id),
        eventType: String(row.event_type ?? ''),
        entityId: String(row.entity_id ?? ''),
        status: String(row.status ?? ''),
        createdAt: new Date(String(row.created_at)).toISOString(),
      }));
    });
  }
}

