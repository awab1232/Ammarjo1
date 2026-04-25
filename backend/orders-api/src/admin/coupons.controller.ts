import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { RbacGuard } from '../identity/rbac.guard';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { AdminRestService } from './admin-rest.service';

class ValidateCouponBody {
  code?: string;
  storeId?: string;
  orderTotal?: number;
}

@Controller('coupons')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 120 } })
export class CouponsController {
  constructor(private readonly adminRest: AdminRestService) {}

  @Post('validate')
  @RequirePermissions('orders.read')
  validate(@Body() body: ValidateCouponBody) {
    return this.adminRest.validateCouponForCheckout({
      code: body.code ?? '',
      storeId: body.storeId,
      orderTotal: Number(body.orderTotal ?? 0),
    });
  }
}
