import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { CategoriesService } from './categories.service';

@Controller('stores/:storeId/categories')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 180 } })
export class CategoriesController {
  constructor(private readonly categories: CategoriesService) {}

  @Get()
  @RequirePermissions('orders.read')
  list(@Param('storeId') storeId: string) {
    return this.categories.list(storeId);
  }

  @Post()
  @RequirePermissions('products.manage')
  create(@Param('storeId') storeId: string, @Body() body: { name: string; orderIndex?: number }) {
    return this.categories.create(storeId, body);
  }

  @Patch(':categoryId')
  @RequirePermissions('products.manage')
  patch(
    @Param('storeId') storeId: string,
    @Param('categoryId') categoryId: string,
    @Body() body: { name?: string; orderIndex?: number },
  ) {
    return this.categories.patch(storeId, categoryId, body);
  }

  @Delete(':categoryId')
  @RequirePermissions('products.manage')
  delete(@Param('storeId') storeId: string, @Param('categoryId') categoryId: string) {
    return this.categories.delete(storeId, categoryId);
  }
}

@Controller('categories')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 180 } })
export class CategoriesMutateController {
  constructor(private readonly categories: CategoriesService) {}

  @Get()
  @RequirePermissions('orders.read')
  listPublic() {
    return this.categories.listPublic(300);
  }

  @Patch(':categoryId')
  @RequirePermissions('products.manage')
  patch(@Param('categoryId') categoryId: string, @Body() body: { name?: string; orderIndex?: number }) {
    return this.categories.patchById(categoryId, body);
  }

  @Delete(':categoryId')
  @RequirePermissions('products.manage')
  delete(@Param('categoryId') categoryId: string) {
    return this.categories.deleteById(categoryId);
  }
}
