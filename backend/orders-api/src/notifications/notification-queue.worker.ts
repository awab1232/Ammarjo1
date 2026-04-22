import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { FcmClientService } from './fcm-client.service';
import { NotificationDevicesService } from './notification-devices.service';
import { NotificationQueueService } from './notification-queue.service';
import type { NotificationPayload } from './notifications.types';

@Injectable()
export class NotificationQueueWorker implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(NotificationQueueWorker.name);
  private timer: ReturnType<typeof setInterval> | null = null;
  private running = false;
  private readonly enabled = (process.env.NOTIFICATIONS_QUEUE_ENABLED ?? 'true').trim() !== '0';
  private readonly pollMs = Number(process.env.NOTIFICATIONS_QUEUE_POLL_MS ?? 2500);

  constructor(
    private readonly queue: NotificationQueueService,
    private readonly devices: NotificationDevicesService,
    private readonly fcm: FcmClientService,
  ) {}

  onModuleInit(): void {
    if (!this.enabled) {
      this.logger.log('NOTIFICATIONS_QUEUE_ENABLED=0 — queue worker disabled');
      return;
    }
    this.timer = setInterval(() => {
      void this.tick();
    }, this.pollMs);
    this.logger.log(JSON.stringify({ kind: 'notification_queue_worker_started', pollMs: this.pollMs }));
    void this.tick();
  }

  onModuleDestroy(): void {
    if (this.timer != null) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  private async tick(): Promise<void> {
    if (this.running) return;
    this.running = true;
    try {
      const rows = await this.queue.reservePending(50);
      this.logger.log(JSON.stringify({ kind: 'notification_queue_tick_reserved', count: rows.length }));
      for (const row of rows) {
        await this.deliverOne(row).catch((e) => {
          const msg = e instanceof Error ? e.message : String(e);
          this.logger.warn(JSON.stringify({ kind: 'notification_queue_deliver_failed', queueId: row.id, error: msg }));
        });
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.logger.warn(JSON.stringify({ kind: 'notification_queue_tick_failed', error: msg }));
    } finally {
      this.running = false;
    }
  }

  private async deliverOne(row: {
    id: string;
    userId: string;
    title: string;
    body: string;
    data: Record<string, string>;
  }): Promise<void> {
    const payload: NotificationPayload = {
      title: row.title,
      body: row.body,
      data: row.data,
    };
    const tokens = await this.devices.listActiveTokensByUser(row.userId);
    if (tokens.length === 0) {
      await this.queue.markAttemptFailed(row.id, 'no_device_tokens');
      this.logger.warn(JSON.stringify({ kind: 'notification_attempt_no_tokens', notificationId: row.id, userId: row.userId }));
      return;
    }

    const result = await this.fcm.sendToMultiple([row.userId], tokens, payload);
    if (result.success) {
      await this.queue.markSent(row.id);
      this.logger.log(
        JSON.stringify({
          kind: 'notification_sent',
          notificationId: row.id,
          userId: row.userId,
          tokensTried: tokens.length,
          successCount: result.successCount,
          failureCount: result.failureCount,
        }),
      );
      for (const bad of result.invalidTokens) {
        await this.devices.pruneInvalidToken(bad);
      }
      return;
    }

    for (const bad of result.invalidTokens) {
      await this.devices.pruneInvalidToken(bad);
    }
    const message = result.errorMessage || 'fcm_send_failed';
    await this.queue.markAttemptFailed(row.id, message);
    this.logger.warn(
      JSON.stringify({
        kind: 'notification_failed',
        notificationId: row.id,
        userId: row.userId,
        error: message,
      }),
    );
  }
}
