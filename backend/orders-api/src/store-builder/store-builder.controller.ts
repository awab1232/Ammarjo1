import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { StoreBuilderService } from './store-builder.service';
import {
  BootstrapStoreBuilderDto,
  CreateStoreCategoryDto,
  ReorderStoreCategoriesDto,
  SetStoreBuilderModeDto,
  StoreBuilderCategoryParamDto,
  StoreBuilderStoreIdParamDto,
  StoreSuggestionRequestDto,
  UpdateStoreCategoryDto,
} from './store-builder.types';

@Controller()
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 180 } })
export class StoreBuilderController {
  constructor(private readonly storeBuilder: StoreBuilderService) {}

  @Post('store-builder/bootstrap')
  @RequirePermissions('stores.manage')
  bootstrap(@Body() body: BootstrapStoreBuilderDto) {
    return this.storeBuilder.bootstrap(body);
  }

  @Get('store-builder/:storeId')
  @RequirePermissions('stores.manage')
  getOne(@Param() params: StoreBuilderStoreIdParamDto) {
    return this.storeBuilder.getStoreBuilder(params.storeId);
  }

  @Post('store-builder/:storeId/mode')
  @RequirePermissions('stores.manage')
  setMode(@Param() params: StoreBuilderStoreIdParamDto, @Body() body: SetStoreBuilderModeDto) {
    return this.storeBuilder.setMode(params.storeId, body);
  }

  @Post('store-builder/:storeId/categories')
  @RequirePermissions('stores.manage')
  addCategory(@Param() params: StoreBuilderStoreIdParamDto, @Body() body: CreateStoreCategoryDto) {
    return this.storeBuilder.addCategory(params.storeId, body);
  }

  @Patch('store-builder/:storeId/categories/:categoryId')
  @RequirePermissions('stores.manage')
  updateCategory(@Param() params: StoreBuilderCategoryParamDto, @Body() body: UpdateStoreCategoryDto) {
    return this.storeBuilder.updateCategory(params.storeId, params.categoryId, body);
  }

  @Delete('store-builder/:storeId/categories/:categoryId')
  @RequirePermissions('stores.manage')
  deleteCategory(@Param() params: StoreBuilderCategoryParamDto) {
    return this.storeBuilder.deleteCategory(params.storeId, params.categoryId);
  }

  @Post('store-builder/:storeId/categories/reorder')
  @RequirePermissions('stores.manage')
  reorder(@Param() params: StoreBuilderStoreIdParamDto, @Body() body: ReorderStoreCategoriesDto) {
    return this.storeBuilder.reorderCategories(params.storeId, body);
  }

  @Post('ai/store/suggestions')
  @RequirePermissions('stores.manage')
  suggestions(@Body() body: StoreSuggestionRequestDto) {
    return this.storeBuilder.suggest(body);
  }
}

