import { Body, Controller, Delete, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { ProductsService } from './products.service';

@Controller('stores/:storeId/products')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 180 } })
export class ProductsController {
  constructor(private readonly products: ProductsService) {}

  @Get()
  @RequirePermissions('orders.read')
  list(@Param('storeId') storeId: string) {
    return this.products.list(storeId);
  }

  @Post()
  @RequirePermissions('products.manage')
  create(
    @Param('storeId') storeId: string,
    @Body()
    body: {
      categoryId?: string;
      name: string;
      price: number;
      images?: string[];
      stock?: number;
      hasVariants?: boolean;
      variants?: Array<{
        sku?: string;
        price: number;
        stock: number;
        isDefault?: boolean;
        options: Array<{ optionType: 'color' | 'size' | 'weight' | 'dimension'; optionValue: string }>;
      }>;
    },
  ) {
    return this.products.create(storeId, body);
  }

  @Patch(':productId')
  @RequirePermissions('products.manage')
  patch(
    @Param('storeId') storeId: string,
    @Param('productId') productId: string,
    @Body()
    body: {
      categoryId?: string;
      name?: string;
      price?: number;
      images?: string[];
      stock?: number;
      hasVariants?: boolean;
      variants?: Array<{
        sku?: string;
        price: number;
        stock: number;
        isDefault?: boolean;
        options: Array<{ optionType: 'color' | 'size' | 'weight' | 'dimension'; optionValue: string }>;
      }>;
    },
  ) {
    return this.products.patch(storeId, productId, body);
  }

  @Delete(':productId')
  @RequirePermissions('products.manage')
  delete(@Param('storeId') storeId: string, @Param('productId') productId: string) {
    return this.products.delete(storeId, productId);
  }
}

@Controller('products')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 180 } })
export class ProductsMutateController {
  constructor(private readonly products: ProductsService) {}

  @Patch(':id')
  @RequirePermissions('products.manage')
  patch(
    @Param('id') id: string,
    @Body()
    body: {
      categoryId?: string;
      name?: string;
      price?: number;
      images?: string[];
      stock?: number;
      hasVariants?: boolean;
      variants?: Array<{
        sku?: string;
        price: number;
        stock: number;
        isDefault?: boolean;
        options: Array<{ optionType: 'color' | 'size' | 'weight' | 'dimension'; optionValue: string }>;
      }>;
    },
  ) {
    return this.products.patchById(id, body);
  }

  @Delete(':id')
  @RequirePermissions('products.manage')
  delete(@Param('id') id: string) {
    return this.products.deleteById(id);
  }

  @Post()
  @RequirePermissions('products.manage')
  createByAdmin(
    @Body()
    body: {
      storeId: string;
      subCategoryId?: string | null;
      name: string;
      description?: string;
      price?: number;
      image?: string | null;
      stock?: number;
      isActive?: boolean;
    },
  ) {
    return this.products.createAdminProduct(body);
  }

  @Patch('bulk-stock')
  @RequirePermissions('products.manage')
  bulkStock(@Body() body: { items?: Array<{ id: string; stock: number }> }) {
    return this.products.bulkUpdateStock(body.items ?? []);
  }
}

@Controller('products')
@ApiPolicy({ auth: false, tenant: 'optional', rateLimit: { rpm: 180 } })
export class ProductsFilterPublicController {
  constructor(private readonly products: ProductsService) {}

  @Get()
  async listPublic(
    @Query('subCategoryId') subCategoryId?: string,
    @Query('storeId') storeId?: string,
    @Query('sectionId') sectionId?: string,
    @Query('search') search?: string,
    @Query('minPrice') minPrice?: string,
    @Query('maxPrice') maxPrice?: string,
    @Query('limit') limit?: string,
    @Query('offset') offset?: string,
  ) {
    try {
      if (subCategoryId || storeId || sectionId || search || minPrice || maxPrice || limit || offset) {
        const out = await this.products.filterProducts({
          subCategoryId,
          storeId,
          sectionId,
          search,
          minPrice: minPrice != null ? Number(minPrice) : undefined,
          maxPrice: maxPrice != null ? Number(maxPrice) : undefined,
          limit: limit != null ? Number(limit) : undefined,
          offset: offset != null ? Number(offset) : undefined,
        });
        return Array.isArray(out.items) ? out.items : [];
      }
      const data = await this.products.listPublic(200);
      return Array.isArray(data.items) ? data.items : [];
    } catch {
      return [];
    }
  }

  @Get(':id')
  async getById(@Param('id') id: string) {
    try {
      return await this.products.getPublicById(id);
    } catch {
      return [];
    }
  }

  @Get('filter')
  async filter(
    @Query('subCategoryId') subCategoryId?: string,
    @Query('storeId') storeId?: string,
    @Query('sectionId') sectionId?: string,
    @Query('search') search?: string,
    @Query('minPrice') minPrice?: string,
    @Query('maxPrice') maxPrice?: string,
    @Query('limit') limit?: string,
    @Query('offset') offset?: string,
  ) {
    try {
      const out = await this.products.filterProducts({
        subCategoryId,
        storeId,
        sectionId,
        search,
        minPrice: minPrice != null ? Number(minPrice) : undefined,
        maxPrice: maxPrice != null ? Number(maxPrice) : undefined,
        limit: limit != null ? Number(limit) : undefined,
        offset: offset != null ? Number(offset) : undefined,
      });
      return { items: Array.isArray(out.items) ? out.items : [], total: Number(out.total) || 0 };
    } catch {
      return { items: [], total: 0 };
    }
  }
}
