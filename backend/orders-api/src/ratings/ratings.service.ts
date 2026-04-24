import {
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  Optional,
  ServiceUnavailableException,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Pool, type PoolClient } from 'pg';
import { DomainEventEmitterService } from '../events/domain-event-emitter.service';
import { DomainEventNames } from '../events/domain-event-names';
import { TenantContextService } from '../identity/tenant-context.service';
import type { CreateReviewDto, RatingAggregate, RatingReview, RatingTargetType } from './ratings.types';

@Injectable()
export class RatingsService {
  private readonly pool: Pool | null;
  private schemaReady = false;
  private readonly reviewColumns =
    'id, target_type, target_id, reviewer_id, reviewer_name, rating, review_text, delivery_speed, product_quality, service_request_id, order_id, created_at';
  private readonly aggregateColumns =
    'target_type, target_id, avg_rating, total_reviews, updated_at';

  constructor(
    private readonly events: DomainEventEmitterService,
    @Optional() private readonly tenant?: TenantContextService,
  ) {
    const url = process.env.DATABASE_URL?.trim();
    this.pool = url
      ? new Pool({
          connectionString: url,
          max: Number(process.env.RATINGS_PG_POOL_MAX || 6),
          idleTimeoutMillis: 30_000,
        })
      : null;
  }

  private requireDb(): Pool {
    if (!this.pool) throw new ServiceUnavailableException('ratings database not configured');
    return this.pool;
  }

  private actorIdOrThrow(): string {
    const uid = this.tenant?.getSnapshot?.()?.uid?.trim();
    if (!uid) throw new ForbiddenException('Authenticated actor is required');
    return uid;
  }

  private async withClient<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.requireDb().connect();
    try {
      await this.ensureSchema(client);
      return await fn(client);
    } finally {
      client.release();
    }
  }

  private async ensureSchema(client: PoolClient): Promise<void> {
    if (this.schemaReady) return;
    await client.query(`
      CREATE TABLE IF NOT EXISTS ratings_reviews (
        id uuid PRIMARY KEY,
        target_type text NOT NULL,
        target_id text NOT NULL,
        reviewer_id text NOT NULL,
        reviewer_name text,
        rating int NOT NULL CHECK (rating >= 1 AND rating <= 5),
        review_text text,
        delivery_speed int CHECK (delivery_speed IS NULL OR (delivery_speed >= 1 AND delivery_speed <= 5)),
        product_quality int CHECK (product_quality IS NULL OR (product_quality >= 1 AND product_quality <= 5)),
        service_request_id uuid,
        order_id text,
        created_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE TABLE IF NOT EXISTS ratings_aggregates (
        target_type text NOT NULL,
        target_id text NOT NULL,
        avg_rating numeric(4,2) NOT NULL DEFAULT 0,
        total_reviews int NOT NULL DEFAULT 0,
        updated_at timestamptz NOT NULL DEFAULT now(),
        PRIMARY KEY (target_type, target_id)
      );
      CREATE UNIQUE INDEX IF NOT EXISTS idx_ratings_unique_by_order_target
        ON ratings_reviews (reviewer_id, order_id, target_type, target_id)
        WHERE order_id IS NOT NULL;
    `);
    this.schemaReady = true;
  }

  private mapReview(row: Record<string, unknown>): RatingReview {
    return {
      id: String(row.id),
      targetType: String(row.target_type) as RatingTargetType,
      targetId: String(row.target_id),
      reviewerId: String(row.reviewer_id),
      reviewerName: row.reviewer_name != null ? String(row.reviewer_name) : null,
      rating: Number(row.rating),
      reviewText: row.review_text != null ? String(row.review_text) : null,
      deliverySpeed: row.delivery_speed != null ? Number(row.delivery_speed) : null,
      productQuality: row.product_quality != null ? Number(row.product_quality) : null,
      serviceRequestId: row.service_request_id != null ? String(row.service_request_id) : null,
      orderId: row.order_id != null ? String(row.order_id) : null,
      createdAt: (() => {
        const t = row.created_at != null ? new Date(String(row.created_at)) : new Date(0);
        return Number.isNaN(t.getTime()) ? new Date(0).toISOString() : t.toISOString();
      })(),
    };
  }

  private mapAggregate(row: Record<string, unknown>): RatingAggregate {
    const u = row.updated_at != null ? new Date(String(row.updated_at)) : new Date(0);
    return {
      targetType: String(row.target_type) as RatingTargetType,
      targetId: String(row.target_id),
      avgRating: Number(row.avg_rating ?? 0),
      totalReviews: Number(row.total_reviews ?? 0),
      updatedAt: Number.isNaN(u.getTime()) ? new Date(0).toISOString() : u.toISOString(),
    };
  }

  private assertTargetType(targetType: string): asserts targetType is RatingTargetType {
    if (targetType !== 'technician' && targetType !== 'store' && targetType !== 'home_store' && targetType !== 'product' && targetType !== 'order') {
      throw new ForbiddenException('unsupported rating target_type');
    }
  }

  private async validateOrderBasedReview(
    client: PoolClient,
    input: CreateReviewDto,
    reviewerId: string,
    targetId: string,
  ): Promise<void> {
    const oid = input.orderId?.trim() ?? '';
    const orderSql =
      oid.length > 0
        ? `SELECT order_id, user_id, store_id_uuid, status, payload
           FROM orders
           WHERE order_id = $1
           LIMIT 1`
        : `SELECT order_id, user_id, store_id_uuid, status, payload
           FROM orders
           WHERE user_id = $1
             AND status IN ('delivered','completed')
           ORDER BY created_at DESC
           LIMIT 50`;
    const oq = await client.query(orderSql, [oid.length > 0 ? oid : reviewerId]);
    if (oq.rows.length === 0) throw new NotFoundException('order not found');
    if (input.targetType === 'order' && oid !== targetId) {
      throw new ForbiddenException('order review targetId must match orderId');
    }
    let matched = false;
    for (const o of oq.rows as Record<string, unknown>[]) {
      if (String(o.user_id ?? '').trim() !== reviewerId) continue;
      const st = String(o.status ?? '').trim().toLowerCase();
      if (st !== 'delivered' && st !== 'completed') continue;
      if (input.targetType === 'order') {
        if (String(o.order_id ?? '').trim() === targetId) {
          matched = true;
          break;
        }
        continue;
      }
      if (input.targetType === 'store' || input.targetType === 'home_store') {
        const storeIdUuid = String(o.store_id_uuid ?? '').trim();
        if (!storeIdUuid) {
          throw new ServiceUnavailableException('order row missing store_id_uuid');
        }
        if (storeIdUuid === targetId) {
          matched = true;
          break;
        }
        continue;
      }
      if (input.targetType === 'product') {
        const payload = o.payload;
        const rawItems = payload && typeof payload === 'object' ? (payload as Record<string, unknown>).items : null;
        const items = Array.isArray(rawItems) ? rawItems : [];
        const found = items.some((it) => {
          if (it == null || typeof it !== 'object') return false;
          const row = it as Record<string, unknown>;
          const pid = String(row.productId ?? row.id ?? '').trim();
          return pid === targetId;
        });
        if (found) {
          matched = true;
          break;
        }
      }
    }
    if (!matched) throw new ForbiddenException('rating requires completed purchase');
  }

  async createReview(input: CreateReviewDto): Promise<RatingReview> {
    const reviewerId = this.actorIdOrThrow();
    const targetId = input.targetId.trim();
    const normalizedRating = Number(input.rating);
    if (!Number.isInteger(normalizedRating) || normalizedRating < 1 || normalizedRating > 5) {
      throw new ForbiddenException('rating must be an integer between 1 and 5');
    }
    const reviewText = input.reviewText?.trim() || null;
    const serviceRequestId = input.serviceRequestId?.trim() || null;
    const orderId = input.orderId?.trim() || null;
    const deliverySpeed = input.deliverySpeed != null ? Number(input.deliverySpeed) : null;
    const productQuality = input.productQuality != null ? Number(input.productQuality) : null;
    return this.withClient(async (client) => {
      await client.query('BEGIN');
      try {
        if (serviceRequestId) {
          const sr = await client.query(
            `SELECT id, customer_id, technician_id, status
             FROM service_requests
             WHERE id = $1::uuid
             LIMIT 1`,
            [serviceRequestId],
          );
          if (sr.rows.length === 0) throw new NotFoundException('service request not found');
          const r = sr.rows[0] as Record<string, unknown>;
          if (String(r.customer_id) !== reviewerId) {
            throw new ForbiddenException('reviewer must be the service request customer');
          }
          if (String(r.status) !== 'completed') {
            throw new ForbiddenException('service request must be completed before review');
          }
          if (input.targetType === 'technician' && String(r.technician_id ?? '') !== targetId) {
            throw new ForbiddenException('technician review target must match completed service request');
          }
        }
        if (input.targetType === 'product' || input.targetType === 'store' || input.targetType === 'home_store' || input.targetType === 'order') {
          await this.validateOrderBasedReview(client, input, reviewerId, targetId);
        }

        const duplicate = await client.query(
          `SELECT 1 FROM ratings_reviews
           WHERE reviewer_id = $1
             AND (
               (service_request_id IS NOT NULL AND service_request_id = $2::uuid)
               OR (target_type = $4 AND target_id = $5)
               OR (order_id IS NOT NULL AND order_id = $3 AND target_type = $4 AND target_id = $5)
             )
           LIMIT 1`,
          [reviewerId, serviceRequestId, orderId, input.targetType, targetId],
        );
        if (duplicate.rows.length > 0) {
          throw new ConflictException('duplicate review for this order/target');
        }

        const uq = await client.query(
          `SELECT email, profile_json->>'name' AS prof_name
           FROM users WHERE firebase_uid = $1 LIMIT 1`,
          [reviewerId],
        );
        const reviewerName =
          uq.rows.length > 0
            ? String(
                (uq.rows[0] as Record<string, unknown>).prof_name ?? (uq.rows[0] as Record<string, unknown>).email ?? '',
              ) || null
            : null;

        const id = randomUUID();
        const inserted = await client.query(
          `INSERT INTO ratings_reviews (
             id, target_type, target_id, reviewer_id, reviewer_name, rating, review_text, delivery_speed, product_quality, service_request_id, order_id, created_at
           ) VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, $8, $9, $10::uuid, $11, NOW())
           RETURNING ${this.reviewColumns}`,
          [id, input.targetType, targetId, reviewerId, reviewerName, normalizedRating, reviewText, deliverySpeed, productQuality, serviceRequestId, orderId],
        );

        const agg = await client.query(
          `SELECT AVG(rating)::numeric(4,2) AS avg_rating, COUNT(*)::int AS total_reviews
           FROM ratings_reviews
           WHERE target_type = $1 AND target_id = $2`,
          [input.targetType, targetId],
        );
        const avg = Number(agg.rows[0]?.avg_rating ?? 0);
        const total = Number(agg.rows[0]?.total_reviews ?? 0);
        await client.query(
          `INSERT INTO ratings_aggregates (target_type, target_id, avg_rating, total_reviews, updated_at)
           VALUES ($1, $2, $3, $4, NOW())
           ON CONFLICT (target_type, target_id)
           DO UPDATE SET avg_rating = EXCLUDED.avg_rating, total_reviews = EXCLUDED.total_reviews, updated_at = NOW()`,
          [input.targetType, targetId, avg, total],
        );

        const review = this.mapReview(inserted.rows[0] as Record<string, unknown>);
        await this.events.enqueueInTransaction(client, DomainEventNames.RATING_CREATED, review.id, {
          ratingId: review.id,
          targetType: review.targetType,
          targetId: review.targetId,
          targetUserId: review.targetId,
          reviewerId: review.reviewerId,
          rating: review.rating,
          serviceRequestId: review.serviceRequestId,
          orderId: review.orderId,
        });
        await client.query('COMMIT');
        return review;
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      }
    });
  }

  async getReviewsByTarget(targetType: RatingTargetType, targetId: string): Promise<RatingReview[]> {
    this.actorIdOrThrow();
    this.assertTargetType(targetType);
    try {
      return await this.withClient(async (client) => {
        const rows = await client.query(
          `SELECT ${this.reviewColumns} FROM ratings_reviews
           WHERE target_type = $1 AND target_id = $2
           ORDER BY created_at DESC
           LIMIT 200`,
          [targetType, targetId.trim()],
        );
        return rows.rows.map((x) => this.mapReview(x as Record<string, unknown>));
      });
    } catch {
      // Read-path fallback: avoid surfacing 5xx to clients when ratings tables/schema are unavailable.
      return [];
    }
  }

  async getAggregate(targetType: RatingTargetType, targetId: string): Promise<RatingAggregate> {
    this.actorIdOrThrow();
    this.assertTargetType(targetType);
    try {
      return await this.withClient(async (client) => {
        const r = await client.query(
          `SELECT ${this.aggregateColumns} FROM ratings_aggregates
           WHERE target_type = $1 AND target_id = $2
           LIMIT 1`,
          [targetType, targetId.trim()],
        );
        if (r.rows.length === 0) {
          return {
            targetType,
            targetId: targetId.trim(),
            avgRating: 0,
            totalReviews: 0,
            updatedAt: new Date(0).toISOString(),
          };
        }
        return this.mapAggregate(r.rows[0] as Record<string, unknown>);
      });
    } catch {
      // Read-path fallback: return empty aggregate instead of 5xx.
      return {
        targetType,
        targetId: targetId.trim(),
        avgRating: 0,
        totalReviews: 0,
        updatedAt: new Date(0).toISOString(),
      };
    }
  }
}

