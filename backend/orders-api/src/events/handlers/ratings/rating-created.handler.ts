import { Injectable, Logger } from '@nestjs/common';
import { DomainEventNames } from '../../domain-event-names';
import { DomainEventEmitterService } from '../../domain-event-emitter.service';
import type { DomainEventEnvelope } from '../../domain-event.types';
import { NotificationsService } from '../../../notifications/notifications.service';

type RatingCreatedPayload = {
  targetId?: unknown;
  targetType?: unknown;
  targetUserId?: unknown;
  [k: string]: unknown;
};

function asText(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const s = v.trim();
  return s.length > 0 ? s : null;
}

@Injectable()
export class RatingCreatedHandler {
  private readonly logger = new Logger(RatingCreatedHandler.name);

  constructor(
    private readonly emitter: DomainEventEmitterService,
    private readonly notifications: NotificationsService,
  ) {}

  register(): void {
    this.emitter.subscribe(DomainEventNames.RATING_CREATED, (env: DomainEventEnvelope) => {
      this.onRatingCreated(env as DomainEventEnvelope<RatingCreatedPayload>);
    });
  }

  private onRatingCreated(env: DomainEventEnvelope<RatingCreatedPayload>): void {
    const targetId = asText(env.payload?.targetId);
    const targetType = asText(env.payload?.targetType);
    const targetUserId = asText(env.payload?.targetUserId);
    if (!targetId || !targetType || !targetUserId) return;
    this.notifications.notifyRatingReceived({ targetId, targetType, targetUserId });
    if (process.env.DEBUG_EVENTS?.trim() === '1') {
      this.logger.debug(JSON.stringify({ kind: 'rating_created_notification_debug', payload: env.payload }));
    }
  }
}

