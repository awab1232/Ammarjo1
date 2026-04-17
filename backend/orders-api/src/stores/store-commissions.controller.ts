import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { StoreCommissionsService } from './store-commissions.service';

@Controller('stores/:storeId/commissions')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 120 } })
export class StoreCommissionsController {
  constructor(private readonly commissions: StoreCommissionsService) {}

  @Get()
  @RequirePermissions('orders.read')
  snapshot(@Param('storeId') storeId: string) {
    return this.commissions.getSnapshot(storeId);
  }

  @Post('pay')
  @RequirePermissions('orders.write')
  pay(@Param('storeId') storeId: string, @Body() body: { amount?: number }) {
    const amount = Number(body?.amount ?? 0);
    return this.commissions.pay(storeId, amount);
  }
}
