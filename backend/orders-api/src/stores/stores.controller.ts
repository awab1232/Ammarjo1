import { Body, Controller, Delete, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { StoresService } from './stores.service';

@Controller('stores')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 180 } })
export class StoresController {
  constructor(private readonly stores: StoresService) {}

  @Get()
  @RequirePermissions('orders.read')
  list(@Query('limit') limit?: string) {
    return this.stores.list(Number(limit ?? 50));
  }

  @Get(':id')
  @RequirePermissions('orders.read')
  byId(@Param('id') id: string) {
    return this.stores.byId(id);
  }

  @Post()
  @RequirePermissions('stores.manage')
  create(@Body() body: { ownerId: string; tenantId?: string; name: string; description?: string; category?: string; storeType?: string }) {
    return this.stores.create(body);
  }

  @Patch(':id')
  @RequirePermissions('stores.manage')
  patch(
    @Param('id') id: string,
    @Body() body: { name?: string; description?: string; category?: string; status?: string; storeType?: string },
  ) {
    return this.stores.patch(id, body);
  }

  @Delete(':id')
  @RequirePermissions('stores.manage')
  delete(@Param('id') id: string) {
    return this.stores.delete(id);
  }

  @Post(':id/boost-requests')
  @RequirePermissions('stores.manage')
  createBoostRequest(
    @Param('id') storeId: string,
    @Body() body: { boostType?: string; durationDays?: number },
  ) {
    return this.stores.createBoostRequest(storeId, {
      boostType: body.boostType ?? '',
      durationDays: Number(body.durationDays ?? 0),
    });
  }

  @Get(':id/boost-requests')
  @RequirePermissions('stores.manage')
  listBoostRequests(@Param('id') storeId: string) {
    return this.stores.listMyBoostRequests(storeId);
  }
}

@Controller('stores')
@ApiPolicy({ auth: false, tenant: 'optional', rateLimit: { rpm: 180 } })
export class StoresPublicController {
  constructor(private readonly stores: StoresService) {}

  @Get('store-types')
  storeTypes() {
    return this.stores.listStoreTypesPublic();
  }

  @Get('by-subcategory/:id')
  bySubCategory(@Param('id') id: string) {
    return this.stores.bySubCategory(id);
  }
}
