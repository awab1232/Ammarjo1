import { Body, Controller, Delete, Get, Param, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsInt, IsNotEmpty, IsNumber, IsOptional, IsString, Min } from 'class-validator';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { FirebaseAuthGuard, type RequestWithFirebase } from '../auth/firebase-auth.guard';
import { CartService } from './cart.service';

class AddCartItemDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  productId!: number;

  @IsOptional()
  @IsString()
  variantId?: string | null;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  quantity!: number;

  @IsString()
  @IsNotEmpty()
  priceSnapshot!: string;

  @IsOptional()
  @IsString()
  productName?: string;

  @IsOptional()
  @IsString()
  imageUrl?: string | null;

  @IsOptional()
  @IsString()
  storeId?: string;

  @IsOptional()
  @IsString()
  storeName?: string;
}

class PatchCartItemDto {
  @Type(() => Number)
  @IsNumber()
  @Min(1)
  quantity!: number;
}

@Controller('cart')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 240 } })
export class CartController {
  constructor(private readonly cart: CartService) {}

  @Get()
  @RequirePermissions('orders.read')
  list(@Req() req: RequestWithFirebase) {
    return this.cart.list(req.firebaseUid!);
  }

  @Post('items')
  @RequirePermissions('orders.write')
  add(@Req() req: RequestWithFirebase, @Body() body: AddCartItemDto) {
    return this.cart.addItem(req.firebaseUid!, body);
  }

  @Patch('items/:id')
  @RequirePermissions('orders.write')
  patch(@Req() req: RequestWithFirebase, @Param('id') id: string, @Body() body: PatchCartItemDto) {
    return this.cart.patchItem(req.firebaseUid!, id, body);
  }

  @Delete('items/:id')
  @RequirePermissions('orders.write')
  remove(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.cart.removeItem(req.firebaseUid!, id);
  }

  @Delete()
  @RequirePermissions('orders.write')
  clear(@Req() req: RequestWithFirebase) {
    return this.cart.clear(req.firebaseUid!);
  }
}
