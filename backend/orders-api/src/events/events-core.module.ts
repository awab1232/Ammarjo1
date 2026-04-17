import { Global, Module } from '@nestjs/common';
import { InfrastructureModule } from '../infrastructure/infrastructure.module';
import { EventOutboxAlertService } from './event-outbox-alert.service';
import { EventOutboxChaosService } from './event-outbox-chaos.service';
import { EventOutboxTracingService } from './event-outbox-tracing.service';
import { DomainEventEmitterService } from './domain-event-emitter.service';
import { EventOutboxOpsMetricsService } from './event-outbox-ops-metrics.service';
import { EventOutboxService } from './event-outbox.service';
import { EventOutboxWorker } from './event-outbox-worker.service';

@Global()
@Module({
  imports: [InfrastructureModule],
  providers: [
    EventOutboxChaosService,
    EventOutboxTracingService,
    EventOutboxService,
    EventOutboxAlertService,
    EventOutboxOpsMetricsService,
    DomainEventEmitterService,
    EventOutboxWorker,
  ],
  exports: [
    EventOutboxChaosService,
    EventOutboxTracingService,
    EventOutboxService,
    EventOutboxAlertService,
    EventOutboxOpsMetricsService,
    DomainEventEmitterService,
  ],
})
export class EventsCoreModule {}
