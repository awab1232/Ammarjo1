import {
  BadRequestException,
  Body,
  Controller,
  Get,
  HttpException,
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
import type { StoredOrder, UserOrdersListResponse } from './order-types';

/** Normalizes list payloads so GET /orders never yields a non-object body without `items`. */
function asUserOrdersListEnvelope(value: unknown): UserOrdersListResponse {
  if (Array.isArray(value)) {
    return {
      items: value.filter((e) => e != null && typeof e === 'object') as StoredOrder[],
      nextCursor: null,
      hasMore: false,
      useFirestoreFallback: false,
    };
  }
  if (value == null || typeof value !== 'object') {
    return {
      items: [],
      nextCursor: null,
      hasMore: false,
      useFirestoreFallback: false,
    };
  }
  const obj = value as Record<string, unknown>;
  const raw = obj['items'];
  const items = Array.isArray(raw) ? (raw.filter((e) => e != null && typeof e === 'object') as StoredOrder[]) : [];
  const nc = obj['nextCursor'];
  const nextCursor =
    nc == null || (typeof nc === 'string' && nc.trim() === '') ? null : String(nc).trim();
  return {
    items,
    nextCursor,
    hasMore: Boolean(obj['hasMore']),
    useFirestoreFallback: Boolean(obj['useFirestoreFallback']),
  };
}
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
    try {
      const raw = await this.orders.listForUser(uid, uid, {
        cursor,
        limit: Number.isFinite(limit) ? limit : undefined,
      });
      return asUserOrdersListEnvelope(raw);
    } catch (e) {
      if (e instanceof BadRequestException) {
        throw e;
      }
      if (e instanceof HttpException) {
        const st = e.getStatus();
        if (st >= 400 && st < 500) {
          throw e;
        }
      }
      logOrderError(e, { userId: uid });
      this.metrics.recordError();
      return {
        items: [],
        nextCursor: null,
        hasMore: false,
        useFirestoreFallback: false,
      };
    }
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

    const emptyEnvelope = (): UserOrdersListResponse => ({
      items: [],
      nextCursor: null,
      hasMore: false,
      useFirestoreFallback: false,
    });

    try {
      if (this.cache.isCacheActive()) {
        const cacheKey = `orders:user:${id}:page:${cursor ?? ''}:l:${limitRaw ?? ''}:leg:${listOpts.legacyFormat ? '1' : '0'}`;
        const hit = await this.cache.getJson<unknown>(cacheKey);
        if (hit != null) {
          if (listOpts.legacyFormat) {
            if (Array.isArray(hit)) {
              return hit as StoredOrder[];
            }
            logOrderError(new Error('orders_list_cache_expected_array'), { userId: id });
            return [];
          }
          return asUserOrdersListEnvelope(hit);
        }
        const fresh = await this.orders.listForUser(id, req.firebaseUid!, listOpts);
        if (listOpts.legacyFormat) {
          const legacyOut = Array.isArray(fresh) ? fresh : [];
          await this.cache.setJson(cacheKey, legacyOut, responseCacheTtlSeconds());
          return legacyOut;
        }
        const envelope = asUserOrdersListEnvelope(fresh);
        await this.cache.setJson(cacheKey, envelope, responseCacheTtlSeconds());
        return envelope;
      }

      const fresh = await this.orders.listForUser(id, req.firebaseUid!, listOpts);
      if (listOpts.legacyFormat) {
        return Array.isArray(fresh) ? fresh : [];
      }
      return asUserOrdersListEnvelope(fresh);
    } catch (e) {
      if (e instanceof BadRequestException) {
        throw e;
      }
      if (e instanceof HttpException) {
        const st = e.getStatus();
        if (st >= 400 && st < 500) {
          throw e;
        }
      }
      logOrderError(e, { userId: id });
      this.metrics.recordError();
      if (listOpts.legacyFormat) {
        return [];
      }
      return emptyEnvelope();
    }
  }
}
