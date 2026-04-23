import { BadRequestException, Injectable, Optional, ServiceUnavailableException } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { DbRouterService } from '../infrastructure/database/db-router.service';
import { MatchingService } from '../matching/matching.service';
import type {
  AnalyticsSlowRequest,
  AnalyticsSummary,
  AnalyticsTimelinePoint,
  AnalyticsTopTechnician,
} from './analytics.types';

@Injectable()
export class AnalyticsService {
  private readonly pool: Pool | null;

  constructor(
    @Optional() private readonly dbRouter?: DbRouterService,
    private readonly matching?: MatchingService,
  ) {
    if (this.dbRouter?.isActive()) {
      this.pool = null;
      return;
    }
    const url = process.env.DATABASE_URL?.trim();
    this.pool = url
      ? new Pool({
          connectionString: url,
          max: Number(process.env.ANALYTICS_PG_POOL_MAX || 6),
          idleTimeoutMillis: 30_000,
        })
      : null;
  }

  private async getReadClient(): Promise<PoolClient> {
    if (this.dbRouter?.isActive()) {
      const c = await this.dbRouter.getReadClient();
      if (!c) throw new ServiceUnavailableException('analytics read client unavailable');
      return c;
    }
    if (!this.pool) throw new ServiceUnavailableException('analytics database not configured');
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

  async getSummary(): Promise<AnalyticsSummary> {
    return this.withReadClient(async (client) => {
      const q = await client.query(
        `SELECT
           (SELECT COUNT(*)::int FROM orders) AS total_orders,
           (SELECT COUNT(*)::int FROM service_requests) AS total_service_requests,
           (SELECT COUNT(*)::int FROM service_requests WHERE status = 'completed') AS completed_service_requests,
           (SELECT COUNT(*)::int FROM service_requests WHERE status IN ('pending','assigned','in_progress')) AS active_service_requests,
           (SELECT COUNT(DISTINCT technician_id)::int FROM service_requests WHERE technician_id IS NOT NULL AND technician_id <> '') AS total_technicians,
           (SELECT COALESCE(AVG(rating),0)::numeric(10,4) FROM ratings_reviews WHERE target_type = 'technician') AS avg_technician_rating,
           (SELECT COUNT(*)::int FROM ratings_reviews) AS total_ratings,
           (SELECT COUNT(*)::int FROM event_outbox WHERE event_type = 'message.sent') AS total_messages`,
      );
      const row = q.rows[0] ?? {};
      return {
        totalOrders: Number(row.total_orders ?? 0),
        totalServiceRequests: Number(row.total_service_requests ?? 0),
        completedServiceRequests: Number(row.completed_service_requests ?? 0),
        activeServiceRequests: Number(row.active_service_requests ?? 0),
        totalTechnicians: Number(row.total_technicians ?? 0),
        avgTechnicianRating: Number(row.avg_technician_rating ?? 0),
        totalRatings: Number(row.total_ratings ?? 0),
        totalMessages: Number(row.total_messages ?? 0),
      };
    });
  }

  async getTimeline(days = 7): Promise<AnalyticsTimelinePoint[]> {
    const d = Math.min(Math.max(1, days), 90);
    return this.withReadClient(async (client) => {
      const q = await client.query(
        `WITH day_series AS (
           SELECT generate_series(
             date_trunc('day', NOW()) - (($1::int - 1) * interval '1 day'),
             date_trunc('day', NOW()),
             interval '1 day'
           ) AS day
         ),
         o AS (
           SELECT date_trunc('day', created_at) AS day, COUNT(*)::int AS c
           FROM orders
           WHERE created_at >= date_trunc('day', NOW()) - (($1::int - 1) * interval '1 day')
           GROUP BY 1
         ),
         sr_created AS (
           SELECT date_trunc('day', created_at) AS day, COUNT(*)::int AS c
           FROM service_requests
           WHERE created_at >= date_trunc('day', NOW()) - (($1::int - 1) * interval '1 day')
           GROUP BY 1
         ),
         sr_completed AS (
           SELECT date_trunc('day', updated_at) AS day, COUNT(*)::int AS c
           FROM service_requests
           WHERE status = 'completed'
             AND updated_at >= date_trunc('day', NOW()) - (($1::int - 1) * interval '1 day')
           GROUP BY 1
         ),
         m AS (
           SELECT date_trunc('day', created_at) AS day, COUNT(*)::int AS c
           FROM event_outbox
           WHERE event_type = 'message.sent'
             AND created_at >= date_trunc('day', NOW()) - (($1::int - 1) * interval '1 day')
           GROUP BY 1
         ),
         r AS (
           SELECT date_trunc('day', created_at) AS day, COUNT(*)::int AS c
           FROM ratings_reviews
           WHERE created_at >= date_trunc('day', NOW()) - (($1::int - 1) * interval '1 day')
           GROUP BY 1
         )
         SELECT
           ds.day::date::text AS day,
           COALESCE(o.c, 0) AS orders,
           COALESCE(sr_created.c, 0) AS service_requests_created,
           COALESCE(sr_completed.c, 0) AS service_requests_completed,
           COALESCE(m.c, 0) AS messages_sent,
           COALESCE(r.c, 0) AS ratings_created
         FROM day_series ds
         LEFT JOIN o ON o.day = ds.day
         LEFT JOIN sr_created ON sr_created.day = ds.day
         LEFT JOIN sr_completed ON sr_completed.day = ds.day
         LEFT JOIN m ON m.day = ds.day
         LEFT JOIN r ON r.day = ds.day
         ORDER BY ds.day ASC`,
        [d],
      );
      return q.rows.map((row) => ({
        day: String(row.day),
        orders: Number(row.orders ?? 0),
        serviceRequestsCreated: Number(row.service_requests_created ?? 0),
        serviceRequestsCompleted: Number(row.service_requests_completed ?? 0),
        messagesSent: Number(row.messages_sent ?? 0),
        ratingsCreated: Number(row.ratings_created ?? 0),
      }));
    });
  }

  async getTopTechnicians(limit = 10): Promise<AnalyticsTopTechnician[]> {
    const lim = Math.min(Math.max(1, limit), 50);
    return this.withReadClient(async (client) => {
      const candidatesQ = await client.query(
        `WITH t AS (
           SELECT DISTINCT technician_id AS technician_id
           FROM service_requests
           WHERE technician_id IS NOT NULL AND technician_id <> ''
           UNION
           SELECT target_id AS technician_id
           FROM ratings_aggregates
           WHERE target_type = 'technician'
         )
         SELECT technician_id
         FROM t
         ORDER BY technician_id
         LIMIT 100`,
      );
      const ids = candidatesQ.rows.map((r) => String(r.technician_id ?? '')).filter((x) => x.length > 0);
      if (ids.length === 0) return [];

      const statsQ = await client.query(
        `SELECT
           sr.technician_id,
           COUNT(*) FILTER (WHERE sr.status = 'completed')::int AS completed_jobs,
           COALESCE(ra.avg_rating, 0)::numeric(10,4) AS avg_rating
         FROM service_requests sr
         LEFT JOIN ratings_aggregates ra
           ON ra.target_type = 'technician' AND ra.target_id = sr.technician_id
         WHERE sr.technician_id = ANY($1::text[])
         GROUP BY sr.technician_id, ra.avg_rating`,
        [ids],
      );
      const statsMap = new Map<string, { completed: number; avg: number }>();
      for (const row of statsQ.rows) {
        const id = String(row.technician_id ?? '');
        statsMap.set(id, {
          completed: Number(row.completed_jobs ?? 0),
          avg: Number(row.avg_rating ?? 0),
        });
      }

      const scored = await Promise.all(
        ids.map(async (id) => {
          const score = this.matching ? await this.matching.computeTechnicianScore(id) : { score: 0 };
          const stats = statsMap.get(id) ?? { completed: 0, avg: 0 };
          return {
            technicianId: id,
            avg_rating: stats.avg,
            completed_jobs: stats.completed,
            score: Number(score.score ?? 0),
          };
        }),
      );
      return scored.sort((a, b) => b.score - a.score).slice(0, lim);
    });
  }

  async getStoreSummary(storeId: string): Promise<{
    storeId: string;
    orderCount: number;
    revenue: number;
  }> {
    const sid = storeId.trim();
    if (!sid) throw new BadRequestException('storeId required');
    return this.withReadClient(async (client) => {
      const q = await client.query(
        `SELECT COUNT(*)::int AS c, COALESCE(SUM(total_numeric), 0)::numeric AS rev
         FROM orders WHERE store_id = $1`,
        [sid],
      );
      const row = q.rows[0] ?? {};
      return {
        storeId: sid,
        orderCount: Number(row.c ?? 0),
        revenue: Number(row.rev ?? 0),
      };
    });
  }

  async getSlowRequests(limit = 50): Promise<AnalyticsSlowRequest[]> {
    const lim = Math.min(Math.max(1, limit), 200);
    return this.withReadClient(async (client) => {
      const q = await client.query(
        `SELECT
           id::text AS request_id,
           customer_id,
           technician_id,
           created_at,
           updated_at AS completed_at,
           EXTRACT(EPOCH FROM (updated_at - created_at)) / 3600.0 AS duration_hours
         FROM service_requests
         WHERE status = 'completed'
         ORDER BY duration_hours DESC NULLS LAST
         LIMIT $1`,
        [lim],
      );
      return q.rows.map((row) => ({
        requestId: String(row.request_id),
        customerId: String(row.customer_id),
        technicianId: row.technician_id != null ? String(row.technician_id) : null,
        createdAt: new Date(String(row.created_at)).toISOString(),
        completedAt: new Date(String(row.completed_at)).toISOString(),
        durationHours: Number(Number(row.duration_hours ?? 0).toFixed(2)),
      }));
    });
  }
}

