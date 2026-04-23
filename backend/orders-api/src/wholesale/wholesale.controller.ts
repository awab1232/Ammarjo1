import { Body, Controller, Delete, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import {
  CreateWholesaleOrderDto,
  WholesaleCategoryWriteDto,
  WholesaleJoinRequestDto,
  WholesaleProductWriteDto,
  WholesaleStorePatchDto,
  UpdateWholesaleOrderStatusDto,
} from './wholesale.types';
import { WholesaleService } from './wholesale.service';

@Controller('wholesale')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 180 } })
export class WholesaleController {
  constructor(private readonly wholesale: WholesaleService) {}

  @Get('stores')
  @RequirePermissions('orders.read')
  stores(@Query('limit') limit?: string, @Query('cursor') cursor?: string) {
    return this.wholesale.listStores(Number(limit ?? 30), cursor);
  }

  @Get('products')
  @RequirePermissions('orders.read')
  products(
    @Query('storeId') storeId?: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.wholesale.listProducts({
      storeId,
      limit: Number(limit ?? 30),
      cursor,
    });
  }

  @Get('products/:id')
  @RequirePermissions('orders.read')
  product(@Param('id') id: string) {
    return this.wholesale.getProductById(id);
  }

  @Get('products/:id/variants')
  @RequirePermissions('orders.read')
  productVariants(@Param('id') id: string) {
    return this.wholesale.listProductVariants(id);
  }

  @Post('products/:id/variants')
  @RequirePermissions('products.manage')
  addProductVariant(
    @Param('id') id: string,
    @Body()
    body: {
      sku?: string;
      price: number;
      stock: number;
      isDefault?: boolean;
      options: Array<{ optionType: 'color' | 'size' | 'weight' | 'dimension'; optionValue: string }>;
    },
  ) {
    return this.wholesale.createProductVariant(id, body);
  }

  @Patch('variants/:variantId')
  @RequirePermissions('products.manage')
  patchVariant(
    @Param('variantId') variantId: string,
    @Body()
    body: {
      sku?: string;
      price?: number;
      stock?: number;
      isDefault?: boolean;
      options?: Array<{ optionType: 'color' | 'size' | 'weight' | 'dimension'; optionValue: string }>;
    },
  ) {
    return this.wholesale.patchVariant(variantId, body);
  }

  @Delete('variants/:variantId')
  @RequirePermissions('products.manage')
  deleteVariant(@Param('variantId') variantId: string) {
    return this.wholesale.deleteVariant(variantId);
  }

  @Post('orders')
  @RequirePermissions('orders.write')
  createOrder(@Body() body: CreateWholesaleOrderDto) {
    return this.wholesale.createOrder(body);
  }

  @Get('orders')
  @RequirePermissions('orders.read')
  orders(
    @Query('storeId') storeId?: string,
    @Query('wholesalerId') wholesalerId?: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.wholesale.listOrders({
      storeId,
      wholesalerId,
      limit: Number(limit ?? 30),
      cursor,
    });
  }

  @Patch('orders/:id/status')
  @RequirePermissions('orders.write')
  updateOrderStatus(@Param('id') id: string, @Body() body: UpdateWholesaleOrderStatusDto) {
    return this.wholesale.updateOrderStatus(id, body);
  }

  @Post('join-requests')
  @RequirePermissions('orders.read')
  joinRequest(@Body() body: WholesaleJoinRequestDto) {
    return this.wholesale.submitJoinRequest(body);
  }

  @Post('products')
  @RequirePermissions('products.manage')
  createProduct(@Body() body: WholesaleProductWriteDto) {
    return this.wholesale.createProduct(body);
  }

  @Patch('products/:id')
  @RequirePermissions('products.manage')
  patchProduct(@Param('id') id: string, @Body() body: WholesaleProductWriteDto) {
    return this.wholesale.updateProduct(id, body);
  }

  @Delete('products/:id')
  @RequirePermissions('products.manage')
  deleteProduct(@Param('id') id: string) {
    return this.wholesale.deleteProduct(id);
  }

  @Post('categories')
  @RequirePermissions('products.manage')
  createCategory(@Body() body: WholesaleCategoryWriteDto) {
    return this.wholesale.createCategory(body);
  }

  @Patch('categories/:id')
  @RequirePermissions('products.manage')
  patchCategory(@Param('id') id: string, @Body() body: WholesaleCategoryWriteDto) {
    return this.wholesale.updateCategory(id, body);
  }

  @Delete('categories/:id')
  @RequirePermissions('products.manage')
  deleteCategory(@Param('id') id: string) {
    return this.wholesale.deleteCategory(id);
  }

  @Patch('stores/:id')
  @RequirePermissions('stores.manage')
  patchStore(@Param('id') id: string, @Body() body: WholesaleStorePatchDto) {
    return this.wholesale.patchStore(id, body);
  }
}
