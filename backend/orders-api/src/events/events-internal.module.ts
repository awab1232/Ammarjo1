import { Module } from '@nestjs/common';
import { InternalApiKeyGuard } from '../search/internal-api-key.guard';
import { EventsCoreModule } from './events-core.module';
import { EventsInternalController } from './events-internal.controller';

@Module({
  imports: [EventsCoreModule],
  controllers: [EventsInternalController],
  providers: [InternalApiKeyGuard],
})
export class EventsInternalModule {}
