import { Injectable } from '@nestjs/common';
import {
  eventAlertDeadLetterDelta,
  eventAlertEmailUrl,
  eventAlertFailureThreshold,
  eventAlertMinIntervalMs,
  eventAlertRetryExplosionMin,
  eventAlertRetryExplosionThreshold,
  eventAlertSlackWebhook,
  eventAlertStuckMinBacklog,
  eventAlertStuckMs,
  eventAlertWebhookUrl,
  eventAlertWindowMs,
  hasEventAlertDestinations,
  isEventAlertingEnabled,
} from './event-outbox-alert-config';
import { EventOutboxService } from './event-outbox.service';

export type WorkerTickAlertContext = {
  recovered: number;
  claimed: number;
  processed: number;
  deadLetterEventIds: string[];
};

export type AlertHistoryEntry = {
  ts: string;
  kind: string;
  message: string;
  details: Record<string, unknown>;
};

export type ActiveAlertCondition = {
  id: string;
  severity: 'warning' | 'critical';
  message: string;
};

type OutboxAlertMetricsRow = {
  failedInWindow: number;
  totalFailed: number;
  highRetryBacklog: number;
  eligiblePending: number;
  processing: number;
};

const ALERT_HISTORY_MAX = 250;

/**
 * Fire-and-forget notifications to webhook / Slack / optional email HTTP endpoint.
 * Never blocks the worker or HTTP handlers.
 */
@Injectable()
export class EventOutboxAlertService {
  private lastTotalFailed: number | null = null;
  private lastProgressAt = Date.now();
  private readonly lastSentAt = new Map<string, number>();
  private readonly alertHistory: AlertHistoryEntry[] = [];

  constructor(private readonly outbox: EventOutboxService) {}

  private pushHistory(kind: string, message: string, details: Record<string, unknown>): void {
    this.alertHistory.unshift({
      ts: new Date().toISOString(),
      kind,
      message,
      details,
    });
    while (this.alertHistory.length > ALERT_HISTORY_MAX) {
      this.alertHistory.pop();
    }
  }

  /** In-memory ring buffer of dispatched alerts (ops dashboard). */
  getAlertsHistory(limit = 100): AlertHistoryEntry[] {
    const lim = Math.min(Math.max(1, limit), ALERT_HISTORY_MAX);
    return this.alertHistory.slice(0, lim);
  }

  getLastAlertTimestamp(): string | null {
    return this.alertHistory[0]?.ts ?? null;
  }

  getAlertTypeBreakdown(): Record<string, number> {
    const out: Record<string, number> = {};
    for (const e of this.alertHistory) {
      out[e.kind] = (out[e.kind] ?? 0) + 1;
    }
    return out;
  }

  /** Current threshold breaches (same logic as periodic checks; read-only). */
  async getActiveAlertConditions(): Promise<ActiveAlertCondition[]> {
    if (!this.outbox.isReady()) {
      return [];
    }
    const windowMs = eventAlertWindowMs();
    const windowStart = new Date(Date.now() - windowMs);
    const metrics = await this.outbox.getAlertMetrics(windowStart, eventAlertRetryExplosionMin());
    if (!metrics) {
      return [];
    }
    return this.buildActiveConditions(metrics, windowMs);
  }

  private buildActiveConditions(metrics: OutboxAlertMetricsRow, windowMs: number): ActiveAlertCondition[] {
    const active: ActiveAlertCondition[] = [];
    const failureThreshold = eventAlertFailureThreshold();
    if (metrics.failedInWindow >= failureThreshold) {
      active.push({
        id: 'high_dead_letter_rate',
        severity: 'warning',
        message: `${metrics.failedInWindow} failure(s) in last ${Math.round(windowMs / 60000)}m (threshold ${failureThreshold})`,
      });
    }
    const explosionMin = eventAlertRetryExplosionMin();
    const explosionTh = eventAlertRetryExplosionThreshold();
    if (metrics.highRetryBacklog >= explosionTh) {
      active.push({
        id: 'retry_explosion',
        severity: 'warning',
        message: `${metrics.highRetryBacklog} row(s) with retry_count >= ${explosionMin} (threshold ${explosionTh})`,
      });
    }
    const delta = eventAlertDeadLetterDelta();
    const prevFailed = this.lastTotalFailed;
    if (prevFailed != null && metrics.totalFailed >= prevFailed + delta) {
      active.push({
        id: 'dead_letter_growth',
        severity: 'warning',
        message: `Dead-letter total ${metrics.totalFailed} (previous snapshot ${prevFailed})`,
      });
    }
    const backlog = metrics.eligiblePending + metrics.processing;
    const stuckMs = eventAlertStuckMs();
    const minBacklog = eventAlertStuckMinBacklog();
    if (backlog >= minBacklog && Date.now() - this.lastProgressAt > stuckMs) {
      active.push({
        id: 'worker_stuck',
        severity: 'critical',
        message: `Backlog ${backlog} with no worker progress for ${Math.round(stuckMs / 60000)}m`,
      });
    }
    return active;
  }

  /** Called after each worker tick with aggregate progress. */
  afterWorkerTick(ctx: WorkerTickAlertContext): void {
    const { recovered, claimed, processed, deadLetterEventIds } = ctx;
    if (recovered > 0 || claimed > 0 || processed > 0) {
      this.lastProgressAt = Date.now();
    }
    if (!isEventAlertingEnabled() || !this.outbox.isReady() || !hasEventAlertDestinations()) {
      return;
    }
    setImmediate(() => {
      void this.runPeriodicChecks(ctx);
    });
    if (deadLetterEventIds.length > 0) {
      setImmediate(() => {
        void this.notifyDeadLettersBatch(deadLetterEventIds);
      });
    }
  }

  /** Manual retry-all (audit / ops awareness). */
  notifyRetryAllFailed(requeued: number): void {
    const outbound = isEventAlertingEnabled() && hasEventAlertDestinations();
    if (!outbound) {
      this.pushHistory('manual_retry_all', `Manual retry-all-failed: re-queued ${requeued} event(s)`, {
        requeued,
      });
    }
    if (!outbound) {
      return;
    }
    setImmediate(() => {
      void this.sendBatched(
        'manual_retry_all',
        `Manual retry-all-failed: re-queued ${requeued} event(s)`,
        { requeued },
      );
    });
  }

  /** Single-event manual retry. */
  notifyManualRetryOne(eventId: string): void {
    const outbound = isEventAlertingEnabled() && hasEventAlertDestinations();
    if (!outbound) {
      this.pushHistory('manual_retry_one', `Manual retry requested for event ${eventId}`, { eventId });
    }
    if (!outbound) {
      return;
    }
    setImmediate(() => {
      void this.sendBatched(
        'manual_retry_one',
        `Manual retry requested for event ${eventId}`,
        { eventId },
      );
    });
  }

  private async runPeriodicChecks(ctx: WorkerTickAlertContext): Promise<void> {
    const windowMs = eventAlertWindowMs();
    const windowStart = new Date(Date.now() - windowMs);
    const metrics = await this.outbox.getAlertMetrics(windowStart, eventAlertRetryExplosionMin());
    if (!metrics) {
      return;
    }

    const lines: string[] = [];
    const failureThreshold = eventAlertFailureThreshold();
    if (metrics.failedInWindow >= failureThreshold) {
      lines.push(
        `High dead-letter rate: ${metrics.failedInWindow} failure(s) in last ${Math.round(windowMs / 60000)}m (threshold ${failureThreshold})`,
      );
    }

    const explosionMin = eventAlertRetryExplosionMin();
    const explosionTh = eventAlertRetryExplosionThreshold();
    if (metrics.highRetryBacklog >= explosionTh) {
      lines.push(
        `Retry pressure: ${metrics.highRetryBacklog} row(s) with retry_count >= ${explosionMin} (threshold ${explosionTh})`,
      );
    }

    const delta = eventAlertDeadLetterDelta();
    const prevFailed = this.lastTotalFailed;
    if (prevFailed != null && metrics.totalFailed >= prevFailed + delta) {
      lines.push(
        `Dead-letter growth: total failed ${metrics.totalFailed} (was ${prevFailed}, +${metrics.totalFailed - prevFailed})`,
      );
    }
    this.lastTotalFailed = metrics.totalFailed;

    const backlog = metrics.eligiblePending + metrics.processing;
    const stuckMs = eventAlertStuckMs();
    const minBacklog = eventAlertStuckMinBacklog();
    if (backlog >= minBacklog && Date.now() - this.lastProgressAt > stuckMs) {
      lines.push(
        `Worker may be stuck: backlog ${backlog} (eligible ${metrics.eligiblePending}, processing ${metrics.processing}), no progress for ${Math.round(stuckMs / 60000)}m`,
      );
    }

    if (lines.length > 0) {
      await this.sendBatched('periodic', lines.join('\n'), {
        metrics,
        tick: ctx,
      });
    }
  }

  private async notifyDeadLettersBatch(ids: string[]): Promise<void> {
    const text =
      ids.length === 1
        ? `Event moved to dead-letter: ${ids[0]}`
        : `Events moved to dead-letter (${ids.length}): ${ids.slice(0, 15).join(', ')}${ids.length > 15 ? '…' : ''}`;
    await this.sendBatched('dead_letter', text, { eventIds: ids });
  }

  private shouldSend(key: string): boolean {
    const min = eventAlertMinIntervalMs();
    const now = Date.now();
    const last = this.lastSentAt.get(key) ?? 0;
    if (now - last < min) {
      return false;
    }
    this.lastSentAt.set(key, now);
    return true;
  }

  private async sendBatched(
    dedupeKey: string,
    text: string,
    details: Record<string, unknown>,
  ): Promise<void> {
    if (!this.shouldSend(dedupeKey)) {
      return;
    }
    this.pushHistory(dedupeKey, text, details);
    const payload = {
      source: 'orders-api-event-outbox',
      severity: 'warning' as const,
      title: 'Event outbox alert',
      message: text,
      details,
      ts: new Date().toISOString(),
    };
    await Promise.all([
      this.postJson(eventAlertWebhookUrl(), payload),
      this.postSlack(eventAlertSlackWebhook(), text),
      this.postJson(eventAlertEmailUrl(), payload),
    ]);
  }

  private async postJson(url: string | undefined, body: Record<string, unknown>): Promise<void> {
    if (!url) return;
    try {
      const ac = new AbortController();
      const t = setTimeout(() => ac.abort(), 8000);
      await fetch(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(body),
        signal: ac.signal,
      });
      clearTimeout(t);
    } catch (e) {
      console.error('[EventOutboxAlertService] webhook delivery failed:', e);
    }
  }

  private async postSlack(url: string | undefined, text: string): Promise<void> {
    if (!url) return;
    try {
      const ac = new AbortController();
      const t = setTimeout(() => ac.abort(), 8000);
      await fetch(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ text }),
        signal: ac.signal,
      });
      clearTimeout(t);
    } catch (e) {
      console.error('[EventOutboxAlertService] Slack delivery failed:', e);
    }
  }
}
