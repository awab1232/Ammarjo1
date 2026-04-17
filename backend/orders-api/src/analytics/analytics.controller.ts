import { Controller, Get, Param, ParseIntPipe, Query, UseGuards } from '@nestjs/common';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { InternalApiKeyGuard } from '../search/internal-api-key.guard';
import { AnalyticsService } from './analytics.service';

@Controller('internal/analytics')
@UseGuards(TenantContextGuard, ApiPolicyGuard, InternalApiKeyGuard)
@ApiPolicy({ auth: false, tenant: 'none' })
export class AnalyticsController {
  constructor(private readonly analytics: AnalyticsService) {}

  @Get('summary')
  summary() {
    return this.analytics.getSummary();
  }

  /** Alias for dashboards — same payload as [summary]. */
  @Get('dashboard')
  dashboard() {
    return this.analytics.getSummary();
  }

  @Get('store/:storeId')
  storeSummary(@Param('storeId') storeId: string) {
    return this.analytics.getStoreSummary(storeId);
  }

  @Get('timeline')
  timeline(@Query('days', new ParseIntPipe({ optional: true })) days?: number) {
    return this.analytics.getTimeline(days ?? 7);
  }

  @Get('top-technicians')
  topTechnicians(@Query('limit', new ParseIntPipe({ optional: true })) limit?: number) {
    return this.analytics.getTopTechnicians(limit ?? 10);
  }

  @Get('slow-requests')
  slowRequests(@Query('limit', new ParseIntPipe({ optional: true })) limit?: number) {
    return this.analytics.getSlowRequests(limit ?? 50);
  }
}

