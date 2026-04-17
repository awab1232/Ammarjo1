import { Body, Controller, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { CategoryService } from './category.service';
import { ProductService } from './product.service';
import { CreateCategoryDto, CreateProductDto, CreateStoreDto } from './store-domain.types';
import { StoreService } from './store.service';

@Controller()
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 240 } })
export class CatalogReadController {
  constructor(
    private readonly storeService: StoreService,
    private readonly categories: CategoryService,
    private readonly productsService: ProductService,
  ) {}

  @Get('stores')
  @RequirePermissions('orders.read')
  stores(@Query('limit') limit?: string, @Query('cursor') cursor?: string) {
    return this.storeService.getStores(Number(limit ?? 30), cursor);
  }

  @Get('stores/:id')
  @RequirePermissions('orders.read')
  store(@Param('id') id: string) {
    return this.storeService.getStoreById(id);
  }

  @Get('stores/:id/categories')
  @RequirePermissions('orders.read')
  async storeCategories(@Param('id') id: string) {
    const items = await this.categories.getCategoriesByStore(id);
    return { items };
  }

  @Get('products')
  @RequirePermissions('orders.read')
  products(
    @Query('storeId') storeId?: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.productsService.getProductsByStore({
      storeId,
      limit: Number(limit ?? 30),
      cursor,
    });
  }

  @Post('stores')
  @RequirePermissions('stores.manage')
  createStore(@Body() body: CreateStoreDto) {
    return this.storeService.createStore(body);
  }

  @Post('categories')
  @RequirePermissions('stores.manage')
  createCategory(@Body() body: CreateCategoryDto) {
    return this.categories.createCategory(body);
  }

  @Post('products')
  @RequirePermissions('products.manage')
  createProduct(@Body() body: CreateProductDto) {
    return this.productsService.createProduct(body);
  }
}

