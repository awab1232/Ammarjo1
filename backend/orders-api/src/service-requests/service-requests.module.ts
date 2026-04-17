import { Module } from '@nestjs/common';
import { EventsCoreModule } from '../events/events-core.module';
import { MatchingModule } from '../matching/matching.module';
import { ServiceRequestsController } from './service-requests.controller';
import { ServiceRequestsService } from './service-requests.service';

@Module({
  imports: [EventsCoreModule, MatchingModule],
  controllers: [ServiceRequestsController],
  providers: [ServiceRequestsService],
  exports: [ServiceRequestsService],
})
export class ServiceRequestsModule {}

