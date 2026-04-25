import { Body, Controller, Delete, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { RoleGuard } from '../identity/role.guard';
import { Roles } from '../identity/roles.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { BannersService } from './banners.service';

@Controller('banners')
@UseGuards(TenantContextGuard, ApiPolicyGuard)
@ApiPolicy({ auth: false, tenant: 'optional', rateLimit: { rpm: 300 } })
export class BannersController {
  constructor(private readonly banners: BannersService) {}

  @Get()
  list(@Query('all') all?: string) {
    return this.banners.list(all === '1' || all?.toLowerCase() === 'true');
  }

  @Post()
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard, RoleGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 120 } })
  @RequirePermissions('stores.manage')
  @Roles('admin', 'system_internal')
  create(
    @Body()
    body: { imageUrl?: string; title?: string; link?: string | null; order?: number; isActive?: boolean },
  ) {
    return this.banners.create(body);
  }

  @Patch(':id')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard, RoleGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 120 } })
  @RequirePermissions('stores.manage')
  @Roles('admin', 'system_internal')
  patch(
    @Param('id') id: string,
    @Body()
    body: { imageUrl?: string; title?: string; link?: string | null; order?: number; isActive?: boolean },
  ) {
    return this.banners.patch(id, body);
  }

  @Delete(':id')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard, RoleGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 120 } })
  @RequirePermissions('stores.manage')
  @Roles('admin', 'system_internal')
  remove(@Param('id') id: string) {
    return this.banners.remove(id);
  }
}
