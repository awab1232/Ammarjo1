import { Module } from '@nestjs/common';
import { MatchingModule } from '../matching/matching.module';
import { InternalApiKeyGuard } from '../search/internal-api-key.guard';
import { AnalyticsController } from './analytics.controller';
import { AnalyticsService } from './analytics.service';

@Module({
  imports: [MatchingModule],
  controllers: [AnalyticsController],
  providers: [AnalyticsService, InternalApiKeyGuard],
})
export class AnalyticsModule {}

