import { Controller, Get, ParseIntPipe, Query, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { AdminAnalyticsService } from './admin.analytics.service';
import { AdminOnlyGuard } from './admin-only.guard';

@Controller('admin')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard, AdminOnlyGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 60 } })
export class AdminController {
  constructor(private readonly admin: AdminAnalyticsService) {}

  @Get('overview')
  overview() {
    return this.admin.overview();
  }

  @Get('kpis')
  kpis() {
    return this.admin.kpis();
  }

  @Get('activity-feed')
  activityFeed(@Query('limit', new ParseIntPipe({ optional: true })) limit?: number) {
    return this.admin.activityFeed(limit ?? 50);
  }
}

