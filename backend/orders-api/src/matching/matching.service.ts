import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import type { TechnicianScoreResult } from './matching.types';

@Injectable()
export class MatchingService {
  private readonly logger = new Logger(MatchingService.name);
  private readonly pool: Pool | null;

  constructor() {
    const url = process.env.DATABASE_URL?.trim();
    this.pool = url
      ? new Pool({
          connectionString: url,
          max: Number(process.env.MATCHING_PG_POOL_MAX || 6),
          idleTimeoutMillis: 30_000,
        })
      : null;
  }

  private requireDb(): Pool {
    if (!this.pool) throw new ServiceUnavailableException('matching database not configured');
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

  async computeTechnicianScore(technicianId: string): Promise<TechnicianScoreResult> {
    const techId = technicianId.trim();
    if (!techId) {
      return {
        technicianId: '',
        score: 0,
        breakdown: {
          ratingScore: 0,
          completionRateScore: 0,
          responsivenessScore: 0,
          fallbackScore: 0,
        },
      };
    }
    return this.withClient(async (client) => {
      const ratingQ = await client.query(
        `SELECT avg_rating, total_reviews
         FROM ratings_aggregates
         WHERE target_type = 'technician' AND target_id = $1
         LIMIT 1`,
        [techId],
      );
      const avgRating = Number(ratingQ.rows[0]?.avg_rating ?? 0);
      const totalReviews = Number(ratingQ.rows[0]?.total_reviews ?? 0);
      const ratingScore = Math.max(0, Math.min(40, (avgRating / 5) * 40));

      const completionQ = await client.query(
        `SELECT
           COUNT(*)::int AS total,
           COUNT(*) FILTER (WHERE status = 'completed')::int AS completed
         FROM service_requests
         WHERE technician_id = $1`,
        [techId],
      );
      const total = Number(completionQ.rows[0]?.total ?? 0);
      const completed = Number(completionQ.rows[0]?.completed ?? 0);
      const completionRate = total > 0 ? completed / total : 0;
      const completionRateScore = Math.max(0, Math.min(35, completionRate * 35));

      const responsivenessQ = await client.query(
        `SELECT COUNT(*)::int AS c
         FROM event_outbox
         WHERE event_type = 'message.sent'
           AND payload ->> 'senderId' = $1
           AND created_at >= NOW() - interval '30 days'`,
        [techId],
      );
      const sentCount = Number(responsivenessQ.rows[0]?.c ?? 0);
      const responsivenessScore = Math.max(0, Math.min(20, sentCount * 2));

      const hasAnyData = totalReviews > 0 || total > 0 || sentCount > 0;
      const fallbackScore = hasAnyData ? 0 : 5;
      const score = Number((ratingScore + completionRateScore + responsivenessScore + fallbackScore).toFixed(2));
      return {
        technicianId: techId,
        score,
        breakdown: {
          ratingScore: Number(ratingScore.toFixed(2)),
          completionRateScore: Number(completionRateScore.toFixed(2)),
          responsivenessScore: Number(responsivenessScore.toFixed(2)),
          fallbackScore,
        },
      };
    });
  }

  async getTopTechnicians(limit = 5): Promise<TechnicianScoreResult[]> {
    const lim = Math.min(Math.max(1, limit), 50);
    const technicianIds = await this.withClient(async (client) => {
      const q = await client.query(
        `SELECT DISTINCT technician_id
         FROM service_requests
         WHERE technician_id IS NOT NULL AND technician_id <> ''
         ORDER BY technician_id ASC
         LIMIT 200`,
      );
      return q.rows
        .map((r) => String(r.technician_id ?? '').trim())
        .filter((v) => v.length > 0);
    });
    const results = await Promise.all(technicianIds.map((id) => this.computeTechnicianScore(id)));
    const sorted = results.sort((a, b) => b.score - a.score).slice(0, lim);
    if (process.env.DEBUG_EVENTS?.trim() === '1') {
      this.logger.debug(
        JSON.stringify({
          kind: 'matching_top_technicians_debug',
          limit: lim,
          candidates: sorted,
        }),
      );
    }
    return sorted;
  }
}

