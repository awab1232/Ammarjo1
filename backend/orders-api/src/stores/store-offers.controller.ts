import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { StoreOffersService } from './store-offers.service';

@Controller('stores/:storeId/offers')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 120 } })
export class StoreOffersController {
  constructor(private readonly offers: StoreOffersService) {}

  @Get()
  @RequirePermissions('orders.read')
  list(@Param('storeId') storeId: string) {
    return this.offers.list(storeId);
  }

  @Post()
  @RequirePermissions('products.manage')
  create(
    @Param('storeId') storeId: string,
    @Body()
    body: {
      title: string;
      description?: string;
      discountPercent: number;
      validUntil?: string;
      imageUrl?: string;
    },
  ) {
    return this.offers.create(storeId, body);
  }
}

@Controller('offers')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 120 } })
export class StoreOffersMutateController {
  constructor(private readonly offers: StoreOffersService) {}

  @Patch(':id')
  @RequirePermissions('products.manage')
  patch(
    @Param('id') id: string,
    @Body()
    body: {
      title?: string;
      description?: string;
      discountPercent?: number;
      validUntil?: string | null;
      imageUrl?: string;
    },
  ) {
    return this.offers.patch(id, body);
  }

  @Delete(':id')
  @RequirePermissions('products.manage')
  delete(@Param('id') id: string) {
    return this.offers.delete(id);
  }
}
