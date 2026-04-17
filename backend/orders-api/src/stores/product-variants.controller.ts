import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { ProductVariantsService } from './product-variants.service';
import type { ProductVariantOptionType } from './stores.types';

@Controller()
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 180 } })
export class ProductVariantsController {
  constructor(private readonly variants: ProductVariantsService) {}

  @Post('products/:id/variants')
  @RequirePermissions('products.manage')
  create(
    @Param('id') productId: string,
    @Body()
    body: {
      sku?: string;
      price: number;
      stock: number;
      isDefault?: boolean;
      options: Array<{ optionType: ProductVariantOptionType; optionValue: string }>;
    },
  ) {
    return this.variants.createForProduct(productId, body);
  }

  @Get('products/:id/variants')
  @RequirePermissions('orders.read')
  list(@Param('id') productId: string) {
    return this.variants.listByProduct(productId);
  }

  @Patch('variants/:variantId')
  @RequirePermissions('products.manage')
  patch(
    @Param('variantId') variantId: string,
    @Body()
    body: {
      sku?: string;
      price?: number;
      stock?: number;
      isDefault?: boolean;
      options?: Array<{ optionType: ProductVariantOptionType; optionValue: string }>;
    },
  ) {
    return this.variants.patchVariant(variantId, body);
  }

  @Delete('variants/:variantId')
  @RequirePermissions('products.manage')
  delete(@Param('variantId') variantId: string) {
    return this.variants.deleteVariant(variantId);
  }
}
