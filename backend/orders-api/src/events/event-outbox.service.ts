import { Injectable, OnModuleDestroy, Optional } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Pool, type PoolClient } from 'pg';
import { MultiRegionStrategyService } from '../infrastructure/region/multi-region-strategy.service';
import { isMultiRegionStrategyEnabled } from '../infrastructure/region/region-strategy.config';
import { DataRoutingService } from '../infrastructure/routing/data-routing.service';
import type { DomainEventName } from './domain-event-names';
import {
  eventOutboxBatchSize,
  eventOutboxDlqPruneBatchSize,
  eventOutboxDlqRetainMaxRows,
  eventOutboxMaxRetries,
  eventOutboxStaleProcessingMs,
  isEventOutboxEnabled,
  opsTimelineDayBucketAfterHours,
} from './event-outbox-config';
import {
  eventOutboxForeignRegionStaleMs,
  eventOutboxMultiRegionEnabled,
  eventOutboxReadReplicaPoolMax,
  eventOutboxReadReplicaUrl,
  eventOutboxRegionId,
} from './event-outbox-mr.config';
import type {
  EventOutboxDashboardStats,
  EventOutboxEmitMeta,
  EventOutboxRow,
  EventOutboxRowSummary,
} from './event-outbox.types';
import { safeErrorMessage } from '../config/safe-log';
import { EventOutboxChaosService } from './event-outbox-chaos.service';
import { EventOutboxTracingService } from './event-outbox-tracing.service';

function backoffMs(retryCount: number): number {
  const base = 1000;
  const cap = 300_000;
  const exp = base * Math.pow(2, Math.min(retryCount, 18));
  return Math.min(cap, Math.floor(exp));
}

function parseDate(v: unknown): Date | null {
  if (v == null) return null;
  if (v instanceof Date) return v;
  return new Date(String(v));
}

function mapRow(r: Record<string, unknown>): EventOutboxRow {
  return {
    event_id: String(r.event_id),
    event_type: String(r.event_type),
    entity_id: String(r.entity_id),
    payload:
      r.payload != null && typeof r.payload === 'object' && !Array.isArray(r.payload)
        ? (r.payload as Record<string, unknown>)
        : {},
    status: r.status as EventOutboxRow['status'],
    retry_count: Number(r.retry_count) || 0,
    created_at: parseDate(r.created_at) ?? new Date(),
    emitted_at: parseDate(r.emitted_at),
    processed_at: parseDate(r.processed_at),
    failed_at: parseDate(r.failed_at),
    picked_by_worker_at: parseDate(r.picked_by_worker_at),
    next_attempt_at: parseDate(r.next_attempt_at) ?? new Date(),
    processing_started_at: parseDate(r.processing_started_at),
    trace_id: r.trace_id != null ? String(r.trace_id) : null,
    source_service: r.source_service != null ? String(r.source_service) : null,
    correlation_id: r.correlation_id != null ? String(r.correlation_id) : null,
    region: r.region != null ? String(r.region) : null,
    processing_region: r.processing_region != null ? String(r.processing_region) : null,
    idempotency_key: r.idempotency_key != null ? String(r.idempotency_key) : null,
  };
}

const OUTBOX_COLUMNS =
  'event_id, event_type, entity_id, payload, status, retry_count, created_at, emitted_at, processed_at, failed_at, picked_by_worker_at, next_attempt_at, processing_started_at, trace_id, source_service, correlation_id, region, processing_region, idempotency_key';

function rowToSummary(row: EventOutboxRow): EventOutboxRowSummary {
  const lastErr = row.payload['_outbox_last_error'];
  return {
    event_id: row.event_id,
    event_type: row.event_type,
    entity_id: row.entity_id,
    status: row.status,
    retry_count: row.retry_count,
    created_at: row.created_at.toISOString(),
    emitted_at: row.emitted_at?.toISOString() ?? null,
    picked_by_worker_at: row.picked_by_worker_at?.toISOString() ?? null,
    processed_at: row.processed_at?.toISOString() ?? null,
    failed_at: row.failed_at?.toISOString() ?? null,
    trace_id: row.trace_id,
    source_service: row.source_service,
    correlation_id: row.correlation_id,
    last_error: typeof lastErr === 'string' ? lastErr : lastErr != null ? String(lastErr) : null,
    region: row.region,
    processing_region: row.processing_region,
  };
}

@Injectable()
export class EventOutboxService implements OnModuleDestroy {
  private pool: Pool | null = null;
  private replicaPool: Pool | null = null;
  private outboxTableAvailable = true;

  constructor(
    @Optional() private readonly chaos?: EventOutboxChaosService,
    @Optional() private readonly tracing?: EventOutboxTracingService,
    @Optional() private readonly dataRouting?: DataRoutingService,
    @Optional() private readonly strategy?: MultiRegionStrategyService,
  ) {
    if (!isEventOutboxEnabled()) {
      return;
    }
    const url = process.env.DATABASE_URL?.trim();
    if (!url) {
      return;
    }
    try {
      this.pool = new Pool({
        connectionString: url,
        max: Number(process.env.EVENT_OUTBOX_PG_POOL_MAX || 5),
        idleTimeoutMillis: 30_000,
      });
    } catch (e) {
      // Security: never log DATABASE_URL or connection strings.
      console.error('[EventOutboxService] pool init failed:', safeErrorMessage(e));
      this.pool = null;
    }
    const replicaUrl = eventOutboxReadReplicaUrl();
    if (replicaUrl) {
      try {
        this.replicaPool = new Pool({
          connectionString: replicaUrl,
          max: eventOutboxReadReplicaPoolMax(),
          idleTimeoutMillis: 30_000,
        });
      } catch (e) {
        console.error('[EventOutboxService] read replica pool init failed:', safeErrorMessage(e));
        this.replicaPool = null;
      }
    }
  }

  isReady(): boolean {
    return this.pool != null && this.outboxTableAvailable;
  }

  async onModuleDestroy(): Promise<void> {
    if (this.replicaPool) {
      await this.replicaPool.end();
      this.replicaPool = null;
    }
    if (this.pool) {
      await this.pool.end();
      this.pool = null;
    }
  }

  private async getClient(): Promise<PoolClient | null> {
    if (!this.pool || !this.outboxTableAvailable) return null;
    return this.pool.connect();
  }

  /** Read-only queries (dashboard); prefers read replica, falls back to primary. */
  /**
   * Worker / region column for multi-region outbox: strategy write region (jo|eg) when enabled,
   * else EVENT_OUTBOX_REGION.
   */
  private effectiveOutboxLocalRegion(): string | null {
    if (eventOutboxMultiRegionEnabled() && isMultiRegionStrategyEnabled() && this.strategy) {
      const w = this.strategy.resolveWriteRegion();
      return w === 'JO' ? 'jo' : 'eg';
    }
    return eventOutboxRegionId();
  }

  private async getReadClient(): Promise<PoolClient | null> {
    if (!this.outboxTableAvailable) {
      return null;
    }
    if (this.chaos?.isEngineEnabled() && this.chaos.shouldForcePrimaryReads()) {
      await this.chaos.maybeAwaitReplicaPartitionLatency();
      return this.getClient();
    }
    if (this.replicaPool) {
      try {
        return await this.replicaPool.connect();
      } catch (e) {
        console.warn('[EventOutboxService] read replica unavailable, using primary:', e);
      }
    }
    return this.getClient();
  }

  private isMissingOutboxTableError(e: unknown): boolean {
    const err = e as { code?: string } | null;
    return err?.code === '42P01';
  }

  private handleOutboxQueryError(operation: string, e: unknown): void {
    if (this.isMissingOutboxTableError(e)) {
      if (this.outboxTableAvailable) {
        this.outboxTableAvailable = false;
        console.error(
          `[EventOutboxService] ${operation} failed: relation "event_outbox" does not exist. ` +
            'Disabling outbox runtime until restart/migrations are applied.',
        );
      }
      return;
    }
    console.error(`[EventOutboxService] ${operation} failed:`, e);
  }

  /**
   * Persist a domain event. Returns the row (status pending) or null if outbox unavailable.
   */
  async insertPending(
    eventType: DomainEventName,
    entityId: string,
    payload: Record<string, unknown>,
    meta?: EventOutboxEmitMeta,
  ): Promise<EventOutboxRow | null> {
    const client = await this.getClient();
    if (!client) return null;
    try {
      return await this.insertPendingWithClient(client, eventType, entityId, payload, meta);
    } finally {
      client.release();
    }
  }

  /**
   * Persist using an existing transaction client, so domain row + outbox row can commit atomically.
   */
  async insertPendingWithClient(
    client: PoolClient,
    eventType: DomainEventName,
    entityId: string,
    payload: Record<string, unknown>,
    meta?: EventOutboxEmitMeta,
  ): Promise<EventOutboxRow | null> {
    const traceId = meta?.traceId?.trim() || randomUUID();
    const sourceService = meta?.sourceService?.trim() || 'system';
    const correlationId = meta?.correlationId?.trim() || entityId;
    const routedRegion = this.dataRouting?.resolveEventOutboxRegion() ?? null;
    const strategySlug =
      eventOutboxMultiRegionEnabled() && isMultiRegionStrategyEnabled() && this.strategy
        ? this.strategy.resolveWriteRegion() === 'JO'
          ? 'jo'
          : 'eg'
        : null;
    const regionDefault =
      meta?.targetRegion?.trim() || strategySlug || routedRegion || eventOutboxRegionId() || null;
    const idemp = meta?.idempotencyKey?.trim() || null;
    try {
      if (eventOutboxMultiRegionEnabled()) {
        const r = await client.query(
          `INSERT INTO event_outbox (
            event_type, entity_id, payload, status, retry_count, created_at, next_attempt_at, emitted_at,
            trace_id, source_service, correlation_id, region, idempotency_key
          ) VALUES ($1, $2, $3::jsonb, 'pending', 0, NOW(), NOW(), NOW(), $4, $5, $6, $7, $8)
          RETURNING *`,
          [
            eventType,
            entityId,
            JSON.stringify(payload),
            traceId,
            sourceService,
            correlationId,
            regionDefault,
            idemp,
          ],
        );
        const row = r.rows[0];
        if (!row) {
          return null;
        }
        const mapped = mapRow(row as Record<string, unknown>);
        this.tracing?.onOutboxEmit(mapped);
        return mapped;
      }
      const r = await client.query(
        `INSERT INTO event_outbox (
          event_type, entity_id, payload, status, retry_count, created_at, next_attempt_at, emitted_at,
          trace_id, source_service, correlation_id
        ) VALUES ($1, $2, $3::jsonb, 'pending', 0, NOW(), NOW(), NOW(), $4, $5, $6)
        RETURNING *`,
        [eventType, entityId, JSON.stringify(payload), traceId, sourceService, correlationId],
      );
      const row = r.rows[0];
      if (!row) {
        return null;
      }
      const mapped = mapRow(row as Record<string, unknown>);
      this.tracing?.onOutboxEmit(mapped);
      return mapped;
    } catch (e: unknown) {
      const err = e as { code?: string };
      if (err.code === '23505' && idemp && eventOutboxMultiRegionEnabled()) {
        const ex = await client.query(`SELECT ${OUTBOX_COLUMNS} FROM event_outbox WHERE idempotency_key = $1 LIMIT 1`, [
          idemp,
        ]);
        const existing = ex.rows[0];
        if (existing) {
          this.chaos?.recordIdempotencyReplay();
          return mapRow(existing as Record<string, unknown>);
        }
      }
      console.error('[EventOutboxService] insertPending failed:', e);
      return null;
    }
  }

  /** Re-queue stale processing rows (crashed worker / long handler). */
  async recoverStaleProcessing(): Promise<number> {
    const client = await this.getClient();
    if (!client) return 0;
    const staleMs = eventOutboxStaleProcessingMs();
    const cutoff = new Date(Date.now() - staleMs);
    const local = this.effectiveOutboxLocalRegion();
    try {
      const setRegion = eventOutboxMultiRegionEnabled()
        ? `, processing_region = NULL`
        : '';
      if (eventOutboxMultiRegionEnabled() && local) {
        const r = await client.query(
          `UPDATE event_outbox
           SET status = 'pending',
               processing_started_at = NULL,
               picked_by_worker_at = NULL
               ${setRegion}
           WHERE status = 'processing'
             AND processing_started_at IS NOT NULL
             AND processing_started_at < $1
             AND (processing_region IS NULL OR processing_region = $2::text)`,
          [cutoff, local],
        );
        return r.rowCount ?? 0;
      }
      const r = await client.query(
        `UPDATE event_outbox
         SET status = 'pending',
             processing_started_at = NULL,
             picked_by_worker_at = NULL
             ${setRegion}
         WHERE status = 'processing'
           AND processing_started_at IS NOT NULL
           AND processing_started_at < $1`,
        [cutoff],
      );
      return r.rowCount ?? 0;
    } catch (e) {
      this.handleOutboxQueryError('recoverStaleProcessing', e);
      return 0;
    } finally {
      client.release();
    }
  }

  /**
   * Failover: rows stuck in `processing` claimed by another region (or unknown) beyond stale threshold.
   * Lets the local region re-claim after DR / network partition.
   */
  async recoverForeignRegionStale(): Promise<number> {
    if (!eventOutboxMultiRegionEnabled()) {
      return 0;
    }
    const client = await this.getClient();
    if (!client) return 0;
    const local = this.effectiveOutboxLocalRegion();
    if (!local) {
      return 0;
    }
    const staleMs = eventOutboxForeignRegionStaleMs();
    const cutoff = new Date(Date.now() - staleMs);
    try {
      const r = await client.query(
        `UPDATE event_outbox
         SET status = 'pending',
             processing_started_at = NULL,
             picked_by_worker_at = NULL,
             processing_region = NULL
         WHERE status = 'processing'
           AND processing_started_at IS NOT NULL
           AND processing_started_at < $1
           AND processing_region IS NOT NULL
           AND processing_region <> $2::text`,
        [cutoff, local],
      );
      return r.rowCount ?? 0;
    } catch (e) {
      this.handleOutboxQueryError('recoverForeignRegionStale', e);
      return 0;
    } finally {
      client.release();
    }
  }

  async claimPendingBatch(limit = eventOutboxBatchSize()): Promise<EventOutboxRow[]> {
    const client = await this.getClient();
    if (!client) return [];
    const lim = Math.min(Math.max(1, limit), 500);
    const local = this.effectiveOutboxLocalRegion();
    try {
      if (eventOutboxMultiRegionEnabled() && local) {
        const r = await client.query(
          `WITH c AS (
             SELECT event_id FROM event_outbox
             WHERE status = 'pending'
               AND next_attempt_at <= NOW()
               AND (region IS NULL OR region = $2::text)
             ORDER BY next_attempt_at ASC, created_at ASC
             LIMIT $1
             FOR UPDATE SKIP LOCKED
           )
           UPDATE event_outbox AS e
           SET status = 'processing',
               processing_started_at = NOW(),
               picked_by_worker_at = NOW(),
               processing_region = $2::text
           FROM c
           WHERE e.event_id = c.event_id
           RETURNING e.*`,
          [lim, local],
        );
        return r.rows.map((row) => mapRow(row as Record<string, unknown>));
      }
      const r = await client.query(
        `WITH c AS (
           SELECT event_id FROM event_outbox
           WHERE status = 'pending'
             AND next_attempt_at <= NOW()
           ORDER BY next_attempt_at ASC, created_at ASC
           LIMIT $1
           FOR UPDATE SKIP LOCKED
         )
         UPDATE event_outbox AS e
         SET status = 'processing',
             processing_started_at = NOW(),
             picked_by_worker_at = NOW()
         FROM c
         WHERE e.event_id = c.event_id
         RETURNING e.*`,
        [lim],
      );
      return r.rows.map((row) => mapRow(row as Record<string, unknown>));
    } catch (e) {
      this.handleOutboxQueryError('claimPendingBatch', e);
      return [];
    } finally {
      client.release();
    }
  }

  /**
   * Cheap eligible backlog estimate for adaptive batch sizing (read-only).
   * Multiple workers each run this; SKIP LOCKED still prevents double-claim.
   */
  async countEligiblePendingApprox(): Promise<number> {
    const client = await this.getClient();
    if (!client) return 0;
    const local = this.effectiveOutboxLocalRegion();
    try {
      if (eventOutboxMultiRegionEnabled() && local) {
        const r = await client.query<{ c: string }>(
          `SELECT COUNT(*)::text AS c FROM event_outbox
           WHERE status = 'pending' AND next_attempt_at <= NOW()
             AND (region IS NULL OR region = $1::text)`,
          [local],
        );
        return Number.parseInt(r.rows[0]?.c ?? '0', 10) || 0;
      }
      const r = await client.query<{ c: string }>(
        `SELECT COUNT(*)::text AS c FROM event_outbox
         WHERE status = 'pending' AND next_attempt_at <= NOW()`,
      );
      return Number.parseInt(r.rows[0]?.c ?? '0', 10) || 0;
    } catch (e) {
      this.handleOutboxQueryError('countEligiblePendingApprox', e);
      return 0;
    } finally {
      client.release();
    }
  }

  async markProcessed(eventId: string): Promise<boolean> {
    const client = await this.getClient();
    if (!client) return false;
    try {
      const clearPr = eventOutboxMultiRegionEnabled() ? `, processing_region = NULL` : '';
      const r = await client.query(
        `UPDATE event_outbox
         SET status = 'processed',
             processed_at = NOW(),
             processing_started_at = NULL,
             failed_at = NULL
             ${clearPr}
         WHERE event_id = $1::uuid AND status = 'processing'`,
        [eventId],
      );
      return (r.rowCount ?? 0) > 0;
    } catch (e) {
      console.error('[EventOutboxService] markProcessed failed:', e);
      return false;
    } finally {
      client.release();
    }
  }

  /**
   * After a failed delivery: retry with backoff or dead-letter.
   * Idempotent: only updates rows still in `processing` with matching event_id.
   */
  async failProcessing(eventId: string, err: unknown): Promise<'dead_letter' | 'requeued' | 'noop'> {
    const client = await this.getClient();
    if (!client) return 'noop';
    const max = eventOutboxMaxRetries();
    const clearPr = eventOutboxMultiRegionEnabled() ? `, processing_region = NULL` : '';
    try {
      const cur = await client.query(
        `SELECT retry_count, trace_id::text AS trace_id FROM event_outbox WHERE event_id = $1::uuid AND status = 'processing'`,
        [eventId],
      );
      const retryCount = Number(cur.rows[0]?.retry_count) || 0;
      const traceIdForDlq =
        cur.rows[0]?.trace_id != null ? String(cur.rows[0].trace_id as string) : null;
      const nextRetry = retryCount + 1;
      const msg = err instanceof Error ? err.message : String(err);
      if (nextRetry >= max) {
        const u = await client.query(
          `UPDATE event_outbox
           SET status = 'failed',
               failed_at = NOW(),
               processed_at = NULL,
               processing_started_at = NULL,
               picked_by_worker_at = NULL
               ${clearPr},
               payload = jsonb_set(payload, '{_outbox_last_error}', to_jsonb($2::text), true)
           WHERE event_id = $1::uuid AND status = 'processing'`,
          [eventId, msg.slice(0, 2000)],
        );
        if ((u.rowCount ?? 0) === 0) {
          return 'noop';
        }
        this.tracing?.onOutboxDlq(eventId, traceIdForDlq, msg.slice(0, 2000));
        console.error(`[EventOutboxService] event ${eventId} marked failed after ${retryCount} retries:`, err);
        return 'dead_letter';
      }
      const delay = backoffMs(retryCount);
      const u = await client.query(
        `UPDATE event_outbox
         SET status = 'pending',
             retry_count = $2,
             next_attempt_at = NOW() + ($3::int * interval '1 millisecond'),
             processing_started_at = NULL,
             picked_by_worker_at = NULL
             ${clearPr},
             payload = jsonb_set(payload, '{_outbox_last_error}', to_jsonb($4::text), true)
         WHERE event_id = $1::uuid AND status = 'processing'`,
        [eventId, nextRetry, delay, msg.slice(0, 2000)],
      );
      return (u.rowCount ?? 0) > 0 ? 'requeued' : 'noop';
    } catch (e) {
      console.error('[EventOutboxService] failProcessing failed:', e);
      return 'noop';
    } finally {
      client.release();
    }
  }

  /** Metrics for alerting (sliding window + backlog). */
  async getAlertMetrics(
    windowStart: Date,
    highRetryMin: number,
  ): Promise<{
    failedInWindow: number;
    totalFailed: number;
    highRetryBacklog: number;
    eligiblePending: number;
    processing: number;
  } | null> {
    const client = await this.getReadClient();
    if (!client) return null;
    const local = this.effectiveOutboxLocalRegion();
    try {
      const r =
        eventOutboxMultiRegionEnabled() && local
          ? await client.query(
              `SELECT
                 (SELECT COUNT(*)::int FROM event_outbox WHERE status = 'failed' AND failed_at >= $1) AS failed_in_window,
                 (SELECT COUNT(*)::int FROM event_outbox WHERE status = 'failed') AS total_failed,
                 (SELECT COUNT(*)::int FROM event_outbox
                    WHERE status IN ('pending', 'processing') AND retry_count >= $2
                      AND (region IS NULL OR region = $3::text)) AS high_retry,
                 (SELECT COUNT(*)::int FROM event_outbox
                    WHERE status = 'pending' AND next_attempt_at <= NOW()
                      AND (region IS NULL OR region = $3::text)) AS eligible,
                 (SELECT COUNT(*)::int FROM event_outbox
                    WHERE status = 'processing'
                      AND (processing_region IS NULL OR processing_region = $3::text)) AS processing`,
              [windowStart, highRetryMin, local],
            )
          : await client.query(
              `SELECT
                 (SELECT COUNT(*)::int FROM event_outbox WHERE status = 'failed' AND failed_at >= $1) AS failed_in_window,
                 (SELECT COUNT(*)::int FROM event_outbox WHERE status = 'failed') AS total_failed,
                 (SELECT COUNT(*)::int FROM event_outbox WHERE status IN ('pending', 'processing') AND retry_count >= $2) AS high_retry,
                 (SELECT COUNT(*)::int FROM event_outbox WHERE status = 'pending' AND next_attempt_at <= NOW()) AS eligible,
                 (SELECT COUNT(*)::int FROM event_outbox WHERE status = 'processing') AS processing`,
              [windowStart, highRetryMin],
            );
      const row = r.rows[0] as Record<string, unknown> | undefined;
      if (!row) return null;
      return {
        failedInWindow: Number(row.failed_in_window) || 0,
        totalFailed: Number(row.total_failed) || 0,
        highRetryBacklog: Number(row.high_retry) || 0,
        eligiblePending: Number(row.eligible) || 0,
        processing: Number(row.processing) || 0,
      };
    } catch (e) {
      console.error('[EventOutboxService] getAlertMetrics failed:', e);
      return null;
    } finally {
      client.release();
    }
  }

  async claimOnePendingById(eventId: string): Promise<EventOutboxRow | null> {
    const client = await this.getClient();
    if (!client) return null;
    const local = this.effectiveOutboxLocalRegion();
    try {
      if (eventOutboxMultiRegionEnabled() && local) {
        const r = await client.query(
          `UPDATE event_outbox
           SET status = 'processing',
               processing_started_at = NOW(),
               picked_by_worker_at = NOW(),
               processing_region = $2::text
           WHERE event_id = $1::uuid
             AND status = 'pending'
             AND (region IS NULL OR region = $2::text)
           RETURNING *`,
          [eventId, local],
        );
        const row = r.rows[0];
        return row ? mapRow(row as Record<string, unknown>) : null;
      }
      const r = await client.query(
        `UPDATE event_outbox
         SET status = 'processing',
             processing_started_at = NOW(),
             picked_by_worker_at = NOW()
         WHERE event_id = $1::uuid
           AND status = 'pending'
         RETURNING *`,
        [eventId],
      );
      const row = r.rows[0];
      return row ? mapRow(row as Record<string, unknown>) : null;
    } catch (e) {
      console.error('[EventOutboxService] claimOnePendingById failed:', e);
      return null;
    } finally {
      client.release();
    }
  }

  async listPendingForAdmin(limit = 100): Promise<EventOutboxRowSummary[]> {
    const client = await this.getReadClient();
    if (!client) return [];
    const lim = Math.min(Math.max(1, limit), 500);
    try {
      const r = await client.query(
        `SELECT ${OUTBOX_COLUMNS} FROM event_outbox
         WHERE status IN ('pending', 'processing')
         ORDER BY created_at ASC
         LIMIT $1`,
        [lim],
      );
      return r.rows.map((row) => rowToSummary(mapRow(row as Record<string, unknown>)));
    } catch (e) {
      console.error('[EventOutboxService] listPendingForAdmin failed:', e);
      return [];
    } finally {
      client.release();
    }
  }

  async getDashboardStats(): Promise<EventOutboxDashboardStats> {
    const client = await this.getReadClient();
    if (!client) {
      return {
        statusBreakdown: {},
        retryDistribution: [],
        recentFailures: [],
      };
    }
    try {
      const statusR = await client.query(
        `SELECT status::text AS s, COUNT(*)::text AS c FROM event_outbox GROUP BY status`,
      );
      const statusBreakdown: Record<string, number> = {};
      for (const row of statusR.rows) {
        statusBreakdown[String(row.s)] = Number.parseInt(String(row.c), 10) || 0;
      }

      const retryR = await client.query(
        `SELECT retry_count::text AS r, COUNT(*)::text AS c
         FROM event_outbox
         WHERE status IN ('pending', 'processing', 'failed')
         GROUP BY retry_count
         ORDER BY retry_count ASC`,
      );
      const retryDistribution = retryR.rows.map((row) => ({
        retry_count: Number.parseInt(String(row.r), 10) || 0,
        count: Number.parseInt(String(row.c), 10) || 0,
      }));

      const failR = await client.query(
        `SELECT ${OUTBOX_COLUMNS} FROM event_outbox
         WHERE status = 'failed'
         ORDER BY failed_at DESC NULLS LAST, created_at DESC
         LIMIT 25`,
      );
      const recentFailures = failR.rows.map((row) =>
        rowToSummary(mapRow(row as Record<string, unknown>)),
      );

      return { statusBreakdown, retryDistribution, recentFailures };
    } catch (e) {
      console.error('[EventOutboxService] getDashboardStats failed:', e);
      return {
        statusBreakdown: {},
        retryDistribution: [],
        recentFailures: [],
      };
    } finally {
      client.release();
    }
  }

  /** Manual retry: failed → pending (worker delivers). Resets retry budget. */
  async retryFailedById(eventId: string): Promise<{ ok: boolean; reason?: string }> {
    const client = await this.getClient();
    if (!client) return { ok: false, reason: 'outbox_not_configured' };
    const clearPr = eventOutboxMultiRegionEnabled() ? `, processing_region = NULL` : '';
    try {
      const r = await client.query(
        `UPDATE event_outbox
         SET status = 'pending',
             retry_count = 0,
             next_attempt_at = NOW(),
             failed_at = NULL,
             processed_at = NULL,
             processing_started_at = NULL,
             picked_by_worker_at = NULL
             ${clearPr},
             payload = payload - '_outbox_last_error'
         WHERE event_id = $1::uuid AND status = 'failed'
         RETURNING event_id`,
        [eventId],
      );
      if ((r.rowCount ?? 0) === 0) {
        return { ok: false, reason: 'not_found_or_not_failed' };
      }
      return { ok: true };
    } catch (e) {
      console.error('[EventOutboxService] retryFailedById failed:', e);
      return { ok: false, reason: 'db_error' };
    } finally {
      client.release();
    }
  }

  async retryAllFailed(): Promise<{ updated: number }> {
    const client = await this.getClient();
    if (!client) return { updated: 0 };
    const clearPr = eventOutboxMultiRegionEnabled() ? `, processing_region = NULL` : '';
    try {
      const r = await client.query(
        `UPDATE event_outbox
         SET status = 'pending',
             retry_count = 0,
             next_attempt_at = NOW(),
             failed_at = NULL,
             processed_at = NULL,
             processing_started_at = NULL,
             picked_by_worker_at = NULL
             ${clearPr},
             payload = payload - '_outbox_last_error'
         WHERE status = 'failed'`,
      );
      return { updated: r.rowCount ?? 0 };
    } catch (e) {
      console.error('[EventOutboxService] retryAllFailed failed:', e);
      return { updated: 0 };
    } finally {
      client.release();
    }
  }

  /** Read-only ops aggregates for dashboard (no locks on hot paths). */
  async getOpsSummary(hoursBack: number): Promise<{
    emitted: number;
    processed: number;
    failedTerminal: number;
    dlqCount: number;
    retryDistribution: Array<{ retry_count: number; count: number }>;
  } | null> {
    const client = await this.getReadClient();
    if (!client) return null;
    const h = Math.min(Math.max(1, hoursBack), 168);
    const interval = `${h} hours`;
    try {
      const r = await client.query(
        `SELECT
           (SELECT COUNT(*)::int FROM event_outbox
             WHERE COALESCE(emitted_at, created_at) >= NOW() - $1::interval) AS emitted,
           (SELECT COUNT(*)::int FROM event_outbox
             WHERE processed_at IS NOT NULL AND processed_at >= NOW() - $1::interval) AS processed,
           (SELECT COUNT(*)::int FROM event_outbox
             WHERE failed_at IS NOT NULL AND failed_at >= NOW() - $1::interval) AS failed_terminal,
           (SELECT COUNT(*)::int FROM event_outbox WHERE status = 'failed') AS dlq`,
        [interval],
      );
      const row = r.rows[0] as Record<string, unknown> | undefined;
      if (!row) return null;

      const retryR = await client.query(
        `SELECT retry_count::text AS r, COUNT(*)::text AS c
         FROM event_outbox
         WHERE status IN ('pending', 'processing', 'failed')
         GROUP BY retry_count
         ORDER BY retry_count ASC`,
      );
      const retryDistribution = retryR.rows.map((x) => ({
        retry_count: Number.parseInt(String(x.r), 10) || 0,
        count: Number.parseInt(String(x.c), 10) || 0,
      }));

      return {
        emitted: Number(row.emitted) || 0,
        processed: Number(row.processed) || 0,
        failedTerminal: Number(row.failed_terminal) || 0,
        dlqCount: Number(row.dlq) || 0,
        retryDistribution,
      };
    } catch (e) {
      console.error('[EventOutboxService] getOpsSummary failed:', e);
      return null;
    } finally {
      client.release();
    }
  }

  /**
   * Event-flow counts for timeline charts (emitted / worker pick / processed / failed).
   * Uses **daily** buckets when hoursBack > [opsTimelineDayBucketAfterHours] to limit aggregation cost.
   */
  async getOpsTimeline(hoursBack: number): Promise<
    | {
        bucketMinutes: number;
        bucketMode: 'hour' | 'day';
        buckets: Array<{
          bucket: string;
          emitted: number;
          processing: number;
          processed: number;
          failed: number;
        }>;
      }
    | null
  > {
    const client = await this.getReadClient();
    if (!client) return null;
    const h = Math.min(Math.max(1, hoursBack), 168);
    const interval = `${h} hours`;
    const dayMode = h > opsTimelineDayBucketAfterHours();
    const unit = dayMode ? 'day' : 'hour';
    const bucketMinutes = dayMode ? 1440 : 60;
    try {
      const [emitted, processing, processed, failed] = await Promise.all([
        client.query(
          `SELECT date_trunc('${unit}', COALESCE(emitted_at, created_at)) AS b, COUNT(*)::int AS n
           FROM event_outbox
           WHERE COALESCE(emitted_at, created_at) >= NOW() - $1::interval
           GROUP BY 1 ORDER BY 1`,
          [interval],
        ),
        client.query(
          `SELECT date_trunc('${unit}', picked_by_worker_at) AS b, COUNT(*)::int AS n
           FROM event_outbox
           WHERE picked_by_worker_at IS NOT NULL AND picked_by_worker_at >= NOW() - $1::interval
           GROUP BY 1 ORDER BY 1`,
          [interval],
        ),
        client.query(
          `SELECT date_trunc('${unit}', processed_at) AS b, COUNT(*)::int AS n
           FROM event_outbox
           WHERE processed_at IS NOT NULL AND processed_at >= NOW() - $1::interval
           GROUP BY 1 ORDER BY 1`,
          [interval],
        ),
        client.query(
          `SELECT date_trunc('${unit}', failed_at) AS b, COUNT(*)::int AS n
           FROM event_outbox
           WHERE failed_at IS NOT NULL AND failed_at >= NOW() - $1::interval
           GROUP BY 1 ORDER BY 1`,
          [interval],
        ),
      ]);

      const key = (v: unknown): string => {
        const d = v instanceof Date ? v : new Date(String(v));
        return d.toISOString();
      };

      const merged = new Map<
        string,
        { emitted: number; processing: number; processed: number; failed: number }
      >();

      const add = (
        rows: { rows: Array<{ b: unknown; n: unknown }> },
        field: 'emitted' | 'processing' | 'processed' | 'failed',
      ): void => {
        for (const row of rows.rows) {
          const k = key(row.b);
          const cur = merged.get(k) ?? {
            emitted: 0,
            processing: 0,
            processed: 0,
            failed: 0,
          };
          cur[field] = Number(row.n) || 0;
          merged.set(k, cur);
        }
      };

      add(emitted, 'emitted');
      add(processing, 'processing');
      add(processed, 'processed');
      add(failed, 'failed');

      const buckets = [...merged.entries()]
        .sort((a, b) => a[0].localeCompare(b[0]))
        .map(([bucket, v]) => ({ bucket, ...v }));

      return {
        bucketMinutes,
        bucketMode: dayMode ? 'day' : 'hour',
        buckets,
      };
    } catch (e) {
      console.error('[EventOutboxService] getOpsTimeline failed:', e);
      return null;
    } finally {
      client.release();
    }
  }

  /** Terminal failed rows (DLQ). Read path; uses replica when configured unless chaos forces primary. */
  async countTerminalFailed(): Promise<number | null> {
    const client = await this.getReadClient();
    if (!client) return null;
    try {
      const r = await client.query<{ c: string }>(
        `SELECT COUNT(*)::text AS c FROM event_outbox WHERE status = 'failed'`,
      );
      return Number.parseInt(r.rows[0]?.c ?? '0', 10) || 0;
    } catch (e) {
      console.error('[EventOutboxService] countTerminalFailed failed:', e);
      return null;
    } finally {
      client.release();
    }
  }

  /**
   * Bounded DLQ retention: prune oldest failed rows when table exceeds configured cap.
   * Safe no-op when disabled.
   */
  async pruneDeadLetterOverflow(): Promise<number> {
    const retainMax = eventOutboxDlqRetainMaxRows();
    if (retainMax <= 0) {
      return 0;
    }
    const client = await this.getClient();
    if (!client) return 0;
    try {
      const countQ = await client.query<{ c: string }>(
        `SELECT COUNT(*)::text AS c FROM event_outbox WHERE status = 'failed'`,
      );
      const total = Number.parseInt(countQ.rows[0]?.c ?? '0', 10) || 0;
      if (total <= retainMax) {
        return 0;
      }
      const overflow = total - retainMax;
      const pruneLimit = Math.min(overflow, eventOutboxDlqPruneBatchSize());
      const del = await client.query(
        `DELETE FROM event_outbox
         WHERE event_id IN (
           SELECT event_id
           FROM event_outbox
           WHERE status = 'failed'
           ORDER BY failed_at ASC NULLS FIRST, created_at ASC
           LIMIT $1
         )`,
        [pruneLimit],
      );
      return del.rowCount ?? 0;
    } catch (e) {
      this.handleOutboxQueryError('pruneDeadLetterOverflow', e);
      return 0;
    } finally {
      client.release();
    }
  }

  /**
   * Approximate backlog per `region` for chaos / ops (eligible pending + processing).
   * Returns empty if the `region` column is missing or query fails.
   */
  async getLagByRegion(): Promise<
    Array<{ region_key: string; eligible_pending: number; processing: number }>
  > {
    const client = await this.getReadClient();
    if (!client) return [];
    try {
      const r = await client.query<{
        region_key: string;
        eligible_pending: string;
        processing: string;
      }>(
        `SELECT COALESCE(NULLIF(TRIM(region::text), ''), '_unset') AS region_key,
                COUNT(*) FILTER (
                  WHERE status = 'pending' AND next_attempt_at <= NOW()
                )::text AS eligible_pending,
                COUNT(*) FILTER (WHERE status = 'processing')::text AS processing
         FROM event_outbox
         GROUP BY 1
         ORDER BY 1`,
      );
      return r.rows.map((row) => ({
        region_key: String(row.region_key),
        eligible_pending: Number.parseInt(String(row.eligible_pending), 10) || 0,
        processing: Number.parseInt(String(row.processing), 10) || 0,
      }));
    } catch (e) {
      console.error('[EventOutboxService] getLagByRegion failed:', e);
      return [];
    } finally {
      client.release();
    }
  }
}
