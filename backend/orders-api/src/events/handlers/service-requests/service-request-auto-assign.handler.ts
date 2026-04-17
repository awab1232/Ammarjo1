import { Injectable, Logger } from '@nestjs/common';
import { DomainEventNames } from '../../domain-event-names';
import { DomainEventEmitterService } from '../../domain-event-emitter.service';
import type { DomainEventEnvelope } from '../../domain-event.types';
import { ServiceRequestsService } from '../../../service-requests/service-requests.service';

type ServiceRequestCreatedPayload = {
  requestId?: unknown;
  [k: string]: unknown;
};

function asText(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const s = v.trim();
  return s.length > 0 ? s : null;
}

@Injectable()
export class ServiceRequestAutoAssignHandler {
  private readonly logger = new Logger(ServiceRequestAutoAssignHandler.name);

  constructor(
    private readonly emitter: DomainEventEmitterService,
    private readonly serviceRequests: ServiceRequestsService,
  ) {}

  register(): void {
    this.emitter.subscribe(DomainEventNames.SERVICE_REQUEST_CREATED, (env: DomainEventEnvelope) => {
      void this.onCreated(env as DomainEventEnvelope<ServiceRequestCreatedPayload>);
    });
  }

  private async onCreated(env: DomainEventEnvelope<ServiceRequestCreatedPayload>): Promise<void> {
    if (process.env.AUTO_ASSIGN_TECHNICIAN?.trim() !== '1') return;
    const requestId = asText(env.payload?.requestId) ?? asText(env.entityId);
    if (!requestId) return;
    try {
      await this.serviceRequests.autoAssignTechnician(requestId);
    } catch (e) {
      this.logger.warn(
        JSON.stringify({
          kind: 'service_request_auto_assign_failed',
          requestId,
          reason: e instanceof Error ? e.message : String(e),
        }),
      );
    }
  }
}

