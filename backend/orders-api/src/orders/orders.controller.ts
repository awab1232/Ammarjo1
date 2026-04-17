import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Patch,
  Param,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { FirebaseAuthGuard, type RequestWithFirebase } from '../auth/firebase-auth.guard';
import { CacheService } from '../infrastructure/cache/cache.service';
import { responseCacheTtlSeconds } from '../infrastructure/cache/cache.config';
import { logOrderError } from './order-logger';
import { OrderMetricsService } from './order-metrics.service';
import { OrdersListRateLimitGuard } from './orders-list-rate-limit.guard';
import type { UserOrdersListResponse } from './order-types';
import { CreateOrderDto } from './dto/create-order.dto';
import { PatchOrderStatusDto } from './dto/patch-order-status.dto';
import { OrdersService } from './orders.service';

@Controller()
export class OrdersController {
  constructor(
    private readonly orders: OrdersService,
    private readonly metrics: OrderMetricsService,
    private readonly cache: CacheService,
  ) {}

  /** Store owner dashboard — lists orders for a store from PostgreSQL. */
  @Get('stores/:storeId/orders')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard, OrdersListRateLimitGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 120 } })
  @RequirePermissions('orders.read')
  async listForStore(
    @Req() req: RequestWithFirebase,
    @Param('storeId') storeId: string,
    @Query('cursor') cursor?: string,
    @Query('limit') limitRaw?: string,
  ): Promise<UserOrdersListResponse> {
    const uid = req.firebaseUid!;
    const limit =
      limitRaw != null && limitRaw.trim() !== '' ? Number.parseInt(limitRaw, 10) : undefined;
    return this.orders.listForStore(storeId, uid, {
      cursor,
      limit: Number.isFinite(limit) ? limit : undefined,
    });
  }

  @Get('stores/:storeId/analytics')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 240 } })
  @RequirePermissions('orders.read')
  async analyticsForStore(@Req() req: RequestWithFirebase, @Param('storeId') storeId: string) {
    const page = await this.orders.listForStore(storeId, req.firebaseUid!, { limit: 200 });
    const items = page.items;
    const totalOrders = items.length;
    const delivered = items.filter((o) => String((o as Record<string, unknown>)['status'] ?? '').toLowerCase() === 'delivered').length;
    const revenue = items.reduce((acc, row) => {
      const v = Number((row as Record<string, unknown>)['totalNumeric'] ?? 0);
      return acc + (Number.isFinite(v) ? v : 0);
    }, 0);
    return {
      totalOrders,
      deliveredOrders: delivered,
      openOrders: totalOrders - delivered,
      revenue,
    };
  }

  @Post('orders')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 60 } })
  @RequirePermissions('orders.write')
  async create(@Req() req: RequestWithFirebase, @Body() rawBody: unknown) {
    if (rawBody == null || typeof rawBody !== 'object' || Array.isArray(rawBody)) {
      throw new BadRequestException('Body must be a JSON object');
    }
    const dto = plainToInstance(CreateOrderDto, rawBody, { enableImplicitConversion: true });
    const errors = await validate(dto);
    if (errors.length > 0) {
      throw new BadRequestException(errors);
    }
    const uid = req.firebaseUid!;
    try {
      const { order, validation, storageCheck } = await this.orders.create(
        rawBody as Record<string, unknown>,
        uid,
      );
      return {
        id: order.orderId,
        order,
        validation,
        storageCheck,
      };
    } catch (e) {
      logOrderError(e, { userId: uid });
      this.metrics.recordError();
      throw e;
    }
  }

  @Get('orders/:id')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 240 } })
  @RequirePermissions('orders.read')
  async getOne(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.orders.getByIdWithComputed(id, req.firebaseUid!);
  }

  @Get('orders')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard, OrdersListRateLimitGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 120 } })
  @RequirePermissions('orders.read')
  async listMine(
    @Req() req: RequestWithFirebase,
    @Query('cursor') cursor?: string,
    @Query('limit') limitRaw?: string,
  ) {
    const uid = req.firebaseUid!;
    const limit =
      limitRaw != null && limitRaw.trim() !== '' ? Number.parseInt(limitRaw, 10) : undefined;
    return this.orders.listForUser(uid, uid, {
      cursor,
      limit: Number.isFinite(limit) ? limit : undefined,
    });
  }

  @Patch('orders/:id/status')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 90 } })
  @RequirePermissions('orders.write')
  async patchStatus(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Body() body: PatchOrderStatusDto,
  ) {
    return this.orders.updateStatus(id, body.status, req.firebaseUid!);
  }

  @Get('users/:id/orders')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard, OrdersListRateLimitGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 240 } })
  @RequirePermissions('orders.read')
  async listForUser(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Query('cursor') cursor?: string,
    @Query('limit') limitRaw?: string,
    @Query('legacy') legacy?: string,
  ) {
    const limit =
      limitRaw != null && limitRaw.trim() !== '' ? Number.parseInt(limitRaw, 10) : undefined;
    const listOpts = {
      cursor,
      limit: Number.isFinite(limit) ? limit : undefined,
      legacyFormat: legacy === '1' || legacy === 'true',
    };

    if (this.cache.isCacheActive()) {
      const cacheKey = `orders:user:${id}:page:${cursor ?? ''}:l:${limitRaw ?? ''}:leg:${listOpts.legacyFormat ? '1' : '0'}`;
      const hit = await this.cache.getJson<UserOrdersListResponse>(cacheKey);
      if (hit != null) {
        return hit;
      }
      const fresh = await this.orders.listForUser(id, req.firebaseUid!, listOpts);
      await this.cache.setJson(cacheKey, fresh, responseCacheTtlSeconds());
      return fresh;
    }

    return this.orders.listForUser(id, req.firebaseUid!, listOpts);
  }
}
