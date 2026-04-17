import { Injectable, Logger } from '@nestjs/common';
import { DomainEventNames } from '../../domain-event-names';
import { DomainEventEmitterService } from '../../domain-event-emitter.service';
import type { DomainEventEnvelope } from '../../domain-event.types';
import { NotificationsService } from '../../../notifications/notifications.service';

type ServiceRequestEventPayload = {
  requestId?: unknown;
  technicianId?: unknown;
  customerId?: unknown;
  [k: string]: unknown;
};

function asText(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const s = v.trim();
  return s.length > 0 ? s : null;
}

@Injectable()
export class ServiceRequestNotificationHandler {
  private readonly logger = new Logger(ServiceRequestNotificationHandler.name);

  constructor(
    private readonly emitter: DomainEventEmitterService,
    private readonly notifications: NotificationsService,
  ) {}

  register(): void {
    this.emitter.subscribe(DomainEventNames.SERVICE_REQUEST_ASSIGNED, (env: DomainEventEnvelope) => {
      this.onAssigned(env as DomainEventEnvelope<ServiceRequestEventPayload>);
    });
    this.emitter.subscribe(DomainEventNames.SERVICE_REQUEST_COMPLETED, (env: DomainEventEnvelope) => {
      this.onCompleted(env as DomainEventEnvelope<ServiceRequestEventPayload>);
    });
  }

  private onAssigned(env: DomainEventEnvelope<ServiceRequestEventPayload>): void {
    const requestId = asText(env.payload?.requestId) ?? env.entityId;
    const technicianId = asText(env.payload?.technicianId);
    if (!technicianId) return;
    this.notifications.notifyServiceAssigned({ requestId, technicianId });
    if (process.env.DEBUG_EVENTS?.trim() === '1') {
      this.logger.debug(JSON.stringify({ kind: 'service_request_assigned_notification_debug', payload: env.payload }));
    }
  }

  private onCompleted(env: DomainEventEnvelope<ServiceRequestEventPayload>): void {
    const requestId = asText(env.payload?.requestId) ?? env.entityId;
    const customerId = asText(env.payload?.customerId);
    if (!customerId) return;
    this.notifications.notifyServiceCompleted({ requestId, customerId });
    if (process.env.DEBUG_EVENTS?.trim() === '1') {
      this.logger.debug(
        JSON.stringify({ kind: 'service_request_completed_notification_debug', payload: env.payload }),
      );
    }
  }
}

