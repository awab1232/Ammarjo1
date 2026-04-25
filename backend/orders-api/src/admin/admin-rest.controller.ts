import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RoleGuard } from '../identity/role.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { Roles } from '../identity/roles.decorator';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { FirebaseAuthGuard, type RequestWithFirebase } from '../auth/firebase-auth.guard';
import { AdminOnlyGuard } from './admin-only.guard';
import { AdminRestService } from './admin-rest.service';
import { SessionsService } from '../auth/sessions.service';

class PatchUserBody {
  role?: string;
  banned?: boolean;
  bannedReason?: string | null;
  walletBalance?: number;
}

class PatchStatusBody {
  status?: string;
}

class PatchStoreFeaturesBody {
  isFeatured?: boolean;
  isBoosted?: boolean;
  boostExpiresAt?: string | null;
}

class PatchStoreCommissionBody {
  /** 0–100 */
  commissionPercent?: number;
  /** توافق مع عملاء أرسلوا `commission` سابقاً */
  commission?: number;
}

class PatchBoostRequestBody {
  status?: string;
}

class PatchProductBoostBody {
  isBoosted?: boolean;
  isTrending?: boolean;
}

class PatchRatingBody {
  reviewText?: string;
}

class CreateCouponBody {
  code?: string;
  name?: string;
  status?: string;
  payload?: Record<string, unknown>;
}

class PatchCouponBody {
  code?: string;
  name?: string;
  status?: string;
  payload?: Record<string, unknown>;
}

class CreatePromotionBody {
  name?: string;
  promoType?: string;
  status?: string;
  payload?: Record<string, unknown>;
}

class PatchPromotionBody {
  name?: string;
  promoType?: string;
  status?: string;
  payload?: Record<string, unknown>;
}

class CreateStoreTypeBody {
  name?: string;
  key?: string;
  icon?: string | null;
  image?: string | null;
  displayOrder?: number;
  isActive?: boolean;
}

class PatchStoreTypeBody {
  name?: string;
  key?: string;
  icon?: string | null;
  image?: string | null;
  displayOrder?: number;
  isActive?: boolean;
}

class CreateHomeSectionBody {
  name?: string;
  image?: string | null;
  type?: string;
  storeTypeId?: string | null;
  isActive?: boolean;
  sortOrder?: number;
}

class PatchHomeSectionBody {
  name?: string;
  image?: string | null;
  type?: string;
  storeTypeId?: string | null;
  isActive?: boolean;
  sortOrder?: number;
}

/** JSON arrays / object for home page marketing (`GET /home/cms`). */
class PatchHomeCmsBody {
  primarySlider?: unknown;
  offers?: unknown;
  bottomBanner?: unknown;
}

class BroadcastNotificationBody {
  title?: string;
  body?: string;
  targetRole?: string;
  data?: Record<string, unknown>;
}

class CreateSubCategoryBody {
  homeSectionId?: string;
  name?: string;
  image?: string | null;
  sortOrder?: number;
  isActive?: boolean;
}

class PatchSubCategoryBody {
  homeSectionId?: string;
  name?: string;
  image?: string | null;
  sortOrder?: number;
  isActive?: boolean;
}

@Controller('admin/rest')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard, RoleGuard, AdminOnlyGuard)
@Roles('admin', 'system_internal')
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 60 } })
export class AdminRestController {
  constructor(
    private readonly admin: AdminRestService,
    private readonly sessions: SessionsService,
  ) {}

  @Get('users')
  @RequirePermissions('stores.manage')
  listUsers(
    @Req() req: RequestWithFirebase,
    @Query('limit', new ParseIntPipe({ optional: true })) limit?: number,
    @Query('offset', new ParseIntPipe({ optional: true })) offset?: number,
  ) {
    return this.admin.listUsers(req.firebaseUid!, limit ?? 50, offset ?? 0);
  }

  @Get('users/:id')
  @RequirePermissions('stores.manage')
  getUser(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.admin.getUser(req.firebaseUid!, id);
  }

  @Patch('users/:id')
  @RequirePermissions('stores.manage')
  patchUser(@Req() req: RequestWithFirebase, @Param('id') id: string, @Body() body: PatchUserBody) {
    return this.admin.patchUser(req.firebaseUid!, id, {
      role: body.role,
      banned: body.banned,
      bannedReason: body.bannedReason,
      walletBalance: body.walletBalance,
    });
  }

  @Delete('users/:id')
  @RequirePermissions('stores.manage')
  deleteUser(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.admin.deleteUser(req.firebaseUid!, id);
  }

  @Get('stores')
  @RequirePermissions('stores.manage')
  listStores(
    @Req() req: RequestWithFirebase,
    @Query('limit', new ParseIntPipe({ optional: true })) limit?: number,
    @Query('offset', new ParseIntPipe({ optional: true })) offset?: number,
  ) {
    return this.admin.listStores(req.firebaseUid!, limit ?? 50, offset ?? 0);
  }

  @Patch('stores/:id/status')
  @RequirePermissions('stores.manage')
  patchStoreStatus(@Req() req: RequestWithFirebase, @Param('id') id: string, @Body() body: PatchStatusBody) {
    return this.admin.patchStoreStatus(req.firebaseUid!, id, body.status ?? '');
  }

  @Patch('stores/:id/features')
  @RequirePermissions('stores.manage')
  patchStoreFeatures(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Body() body: PatchStoreFeaturesBody,
  ) {
    return this.admin.patchStoreFeatures(req.firebaseUid!, id, {
      isFeatured: body.isFeatured,
      isBoosted: body.isBoosted,
      boostExpiresAt: body.boostExpiresAt,
    });
  }

  @Patch('stores/:id/commission')
  @RequirePermissions('stores.manage')
  patchStoreCommission(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Body() body: PatchStoreCommissionBody,
  ) {
    const raw = body.commissionPercent ?? body.commission;
    if (raw === undefined || raw === null) {
      throw new BadRequestException('commissionPercent is required');
    }
    return this.admin.patchStoreCommissionPercent(req.firebaseUid!, id, Number(raw));
  }

  @Get('stores/:id/commission')
  @RequirePermissions('stores.manage')
  getStoreCommission(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.admin.getStoreCommissionReport(req.firebaseUid!, id);
  }

  @Get('boost-requests')
  @RequirePermissions('stores.manage')
  boostRequests(@Req() req: RequestWithFirebase, @Query('status') status?: string) {
    return this.admin.listBoostRequests(req.firebaseUid!, status ?? 'all');
  }

  @Patch('boost-requests/:id')
  @RequirePermissions('stores.manage')
  patchBoostRequestStatus(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Body() body: PatchBoostRequestBody,
  ) {
    const status = (body.status ?? '').trim().toLowerCase();
    if (status !== 'approved' && status !== 'rejected') {
      throw new BadRequestException('invalid_status');
    }
    return this.admin.patchBoostRequestStatus(req.firebaseUid!, id, status as 'approved' | 'rejected');
  }

  @Get('technicians')
  @RequirePermissions('stores.manage')
  listTechnicians(@Req() req: RequestWithFirebase) {
    return this.admin.listTechnicians(req.firebaseUid!);
  }

  @Patch('technicians/:id/status')
  @RequirePermissions('stores.manage')
  patchTechnicianStatus(@Req() req: RequestWithFirebase, @Param('id') id: string, @Body() body: PatchStatusBody) {
    return this.admin.patchTechnicianStatus(req.firebaseUid!, id, body.status ?? '');
  }

  @Patch('technicians/:id/profile')
  @RequirePermissions('stores.manage')
  patchTechnicianProfile(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Body()
    body: {
      displayName?: string;
      email?: string;
      phone?: string;
      city?: string;
      category?: string;
      specialties?: string[];
      cities?: string[];
      status?: string;
    },
  ) {
    return this.admin.patchTechnicianProfile(req.firebaseUid!, id, body);
  }

  @Get('orders')
  @RequirePermissions('stores.manage')
  listOrders(
    @Req() req: RequestWithFirebase,
    @Query('limit', new ParseIntPipe({ optional: true })) limit?: number,
    @Query('offset', new ParseIntPipe({ optional: true })) offset?: number,
    @Query('deliveryStatus') deliveryStatus?: string,
    @Query('driverId') driverId?: string,
    @Query('dateFrom') dateFrom?: string,
    @Query('dateTo') dateTo?: string,
    @Query('search') search?: string,
  ) {
    return this.admin.listOrders(req.firebaseUid!, limit ?? 50, offset ?? 0, {
      deliveryStatus: deliveryStatus?.trim(),
      driverId: driverId?.trim(),
      dateFrom: dateFrom?.trim(),
      dateTo: dateTo?.trim(),
      search: search?.trim(),
    });
  }

  @Post('orders/:id/retry-assignment')
  @RequirePermissions('stores.manage')
  adminRetryDelivery(@Req() req: RequestWithFirebase, @Param('id') orderId: string) {
    return this.admin.adminRetryDeliveryAssignment(req.firebaseUid!, orderId);
  }

  @Get('audit-logs')
  @RequirePermissions('stores.manage')
  auditLogs(
    @Req() req: RequestWithFirebase,
    @Query('limit', new ParseIntPipe({ optional: true })) limit?: number,
    @Query('offset', new ParseIntPipe({ optional: true })) offset?: number,
  ) {
    return this.admin.listAuditLogs(req.firebaseUid!, limit ?? 50, offset ?? 0);
  }

  @Get('migration-status')
  @RequirePermissions('stores.manage')
  migrationStatus(@Req() req: RequestWithFirebase) {
    return this.admin.getMigrationStatus(req.firebaseUid!);
  }

  @Patch('migration-status')
  @RequirePermissions('stores.manage')
  patchMigrationStatus(@Req() req: RequestWithFirebase, @Body() body: { payload: Record<string, unknown> }) {
    return this.admin.patchMigrationStatus(req.firebaseUid!, body.payload ?? {});
  }

  @Get('technician-join-requests')
  @RequirePermissions('stores.manage')
  technicianJoinRequests(@Req() req: RequestWithFirebase) {
    return this.admin.listTechnicianJoinRequests(req.firebaseUid!);
  }

  @Patch('technician-join-requests/:id')
  @RequirePermissions('stores.manage')
  patchTechnicianJoinRequest(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Body() body: { status: string; rejectionReason?: string | null; reviewedBy?: string | null },
  ) {
    return this.admin.patchTechnicianJoinRequest(req.firebaseUid!, id, body);
  }

  @Get('driver-requests')
  @RequirePermissions('stores.manage')
  listDriverRequests(@Req() req: RequestWithFirebase) {
    return this.admin.listDriverRequests(req.firebaseUid!);
  }

  @Post('driver-requests/:id/approve')
  @RequirePermissions('stores.manage')
  approveDriverRequest(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.admin.approveDriverRequest(req.firebaseUid!, id);
  }

  @Post('driver-requests/:id/reject')
  @RequirePermissions('stores.manage')
  rejectDriverRequest(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.admin.rejectDriverRequest(req.firebaseUid!, id);
  }

  @Get('reports')
  @RequirePermissions('stores.manage')
  reports(@Req() req: RequestWithFirebase) {
    return this.admin.listReports(req.firebaseUid!);
  }

  @Patch('reports/:id')
  @RequirePermissions('stores.manage')
  patchReport(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Body() body: { status?: string; subject?: string; bodyText?: string },
  ) {
    return this.admin.patchReport(req.firebaseUid!, id, body);
  }

  @Get('system/logs')
  @RequirePermissions('stores.manage')
  logs(@Req() req: RequestWithFirebase, @Query('limit', new ParseIntPipe({ optional: true })) limit?: number) {
    return this.admin.systemLogs(req.firebaseUid!, limit ?? 100);
  }

  @Get('analytics/overview')
  @RequirePermissions('stores.manage')
  analyticsOverview(@Req() req: RequestWithFirebase) {
    return this.admin.analyticsOverview(req.firebaseUid!);
  }

  @Get('analytics/finance')
  @RequirePermissions('stores.manage')
  analyticsFinance(@Req() req: RequestWithFirebase) {
    return this.admin.analyticsFinance(req.firebaseUid!);
  }

  @Get('analytics/activity')
  @RequirePermissions('stores.manage')
  analyticsActivity(@Req() req: RequestWithFirebase) {
    return this.admin.analyticsActivity(req.firebaseUid!);
  }

  @Get('coupons')
  @RequirePermissions('stores.manage')
  coupons(
    @Req() req: RequestWithFirebase,
    @Query('limit', new ParseIntPipe({ optional: true })) limit?: number,
    @Query('offset', new ParseIntPipe({ optional: true })) offset?: number,
  ) {
    return this.admin.listCoupons(req.firebaseUid!, limit ?? 50, offset ?? 0);
  }

  @Post('coupons')
  @RequirePermissions('dlq.manage')
  createCoupon(@Req() req: RequestWithFirebase, @Body() body: CreateCouponBody) {
    return this.admin.createCoupon(req.firebaseUid!, {
      code: body.code ?? '',
      name: body.name,
      status: body.status,
      payload: body.payload,
    });
  }

  @Patch('coupons/:id')
  @RequirePermissions('dlq.manage')
  patchCoupon(@Req() req: RequestWithFirebase, @Param('id') id: string, @Body() body: PatchCouponBody) {
    return this.admin.patchCoupon(req.firebaseUid!, id, body);
  }

  @Delete('coupons/:id')
  @RequirePermissions('dlq.manage')
  deleteCoupon(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.admin.deleteCoupon(req.firebaseUid!, id);
  }

  @Get('promotions')
  @RequirePermissions('stores.manage')
  promotions(
    @Req() req: RequestWithFirebase,
    @Query('limit', new ParseIntPipe({ optional: true })) limit?: number,
    @Query('offset', new ParseIntPipe({ optional: true })) offset?: number,
  ) {
    return this.admin.listPromotions(req.firebaseUid!, limit ?? 50, offset ?? 0);
  }

  @Post('promotions')
  @RequirePermissions('dlq.manage')
  createPromotion(@Req() req: RequestWithFirebase, @Body() body: CreatePromotionBody) {
    return this.admin.createPromotion(req.firebaseUid!, {
      name: body.name ?? '',
      promoType: body.promoType,
      status: body.status,
      payload: body.payload,
    });
  }

  @Patch('promotions/:id')
  @RequirePermissions('dlq.manage')
  patchPromotion(@Req() req: RequestWithFirebase, @Param('id') id: string, @Body() body: PatchPromotionBody) {
    return this.admin.patchPromotion(req.firebaseUid!, id, body);
  }

  @Delete('promotions/:id')
  @RequirePermissions('dlq.manage')
  deletePromotion(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.admin.deletePromotion(req.firebaseUid!, id);
  }

  @Get('home-sections')
  @RequirePermissions('stores.manage')
  homeSections(@Req() req: RequestWithFirebase) {
    return this.admin.listHomeSections(req.firebaseUid!);
  }

  @Get('home-cms')
  @RequirePermissions('stores.manage')
  homeCms(@Req() req: RequestWithFirebase) {
    return this.admin.getHomeCms(req.firebaseUid!);
  }

  @Patch('home-cms')
  @RequirePermissions('stores.manage')
  patchHomeCms(@Req() req: RequestWithFirebase, @Body() body: PatchHomeCmsBody) {
    return this.admin.patchHomeCms(req.firebaseUid!, {
      primarySlider: body.primarySlider,
      offers: body.offers,
      bottomBanner: body.bottomBanner,
    });
  }

  @Get('store-types')
  @RequirePermissions('stores.manage')
  storeTypes(@Req() req: RequestWithFirebase) {
    return this.admin.listStoreTypes(req.firebaseUid!);
  }

  @Post('store-types')
  @RequirePermissions('stores.manage')
  createStoreType(@Req() req: RequestWithFirebase, @Body() body: CreateStoreTypeBody) {
    return this.admin.createStoreType(req.firebaseUid!, {
      name: body.name ?? '',
      key: body.key ?? '',
      icon: body.icon,
      image: body.image,
      displayOrder: body.displayOrder,
      isActive: body.isActive,
    });
  }

  @Patch('store-types/:id')
  @RequirePermissions('stores.manage')
  patchStoreType(@Req() req: RequestWithFirebase, @Param('id') id: string, @Body() body: PatchStoreTypeBody) {
    return this.admin.patchStoreType(req.firebaseUid!, id, {
      name: body.name,
      key: body.key,
      icon: body.icon,
      image: body.image,
      displayOrder: body.displayOrder,
      isActive: body.isActive,
    });
  }

  @Delete('store-types/:id')
  @RequirePermissions('stores.manage')
  deleteStoreType(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.admin.deleteStoreType(req.firebaseUid!, id);
  }

  @Post('home-sections')
  @RequirePermissions('stores.manage')
  createHomeSection(@Req() req: RequestWithFirebase, @Body() body: CreateHomeSectionBody) {
    return this.admin.createHomeSection(req.firebaseUid!, {
      name: body.name ?? '',
      image: body.image,
      type: body.type ?? '',
      storeTypeId: body.storeTypeId,
      isActive: body.isActive,
      sortOrder: body.sortOrder,
    });
  }

  @Patch('home-sections/:id')
  @RequirePermissions('stores.manage')
  patchHomeSection(@Req() req: RequestWithFirebase, @Param('id') id: string, @Body() body: PatchHomeSectionBody) {
    return this.admin.patchHomeSection(req.firebaseUid!, id, {
      name: body.name,
      image: body.image,
      type: body.type,
      storeTypeId: body.storeTypeId,
      isActive: body.isActive,
      sortOrder: body.sortOrder,
    });
  }

  @Delete('home-sections/:id')
  @RequirePermissions('stores.manage')
  deleteHomeSection(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.admin.deleteHomeSection(req.firebaseUid!, id);
  }

  @Get('sub-categories')
  @RequirePermissions('stores.manage')
  subCategories(@Req() req: RequestWithFirebase, @Query('sectionId') sectionId?: string) {
    return this.admin.listSubCategories(req.firebaseUid!, sectionId ?? '');
  }

  @Post('sub-categories')
  @RequirePermissions('stores.manage')
  createSubCategory(@Req() req: RequestWithFirebase, @Body() body: CreateSubCategoryBody) {
    return this.admin.createSubCategory(req.firebaseUid!, {
      homeSectionId: body.homeSectionId ?? '',
      name: body.name ?? '',
      image: body.image,
      sortOrder: body.sortOrder,
      isActive: body.isActive,
    });
  }

  @Patch('sub-categories/:id')
  @RequirePermissions('stores.manage')
  patchSubCategory(@Req() req: RequestWithFirebase, @Param('id') id: string, @Body() body: PatchSubCategoryBody) {
    return this.admin.patchSubCategory(req.firebaseUid!, id, {
      homeSectionId: body.homeSectionId,
      name: body.name,
      image: body.image,
      sortOrder: body.sortOrder,
      isActive: body.isActive,
    });
  }

  @Delete('sub-categories/:id')
  @RequirePermissions('stores.manage')
  deleteSubCategory(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.admin.deleteSubCategory(req.firebaseUid!, id);
  }

  @Get('tenders')
  @RequirePermissions('stores.manage')
  tenders(@Req() req: RequestWithFirebase) {
    return this.admin.listTenders(req.firebaseUid!);
  }

  @Patch('tenders/:id')
  @RequirePermissions('stores.manage')
  patchTender(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Body() body: { status?: string; title?: string; payload?: Record<string, unknown> },
  ) {
    return this.admin.patchTender(req.firebaseUid!, id, body);
  }

  @Get('support/tickets')
  @RequirePermissions('stores.manage')
  supportTickets(@Req() req: RequestWithFirebase) {
    return this.admin.listSupportTickets(req.firebaseUid!);
  }

  @Patch('support/tickets/:id')
  @RequirePermissions('stores.manage')
  patchSupportTicket(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Body() body: { status?: string; subject?: string; payload?: Record<string, unknown> },
  ) {
    return this.admin.patchSupportTicket(req.firebaseUid!, id, body);
  }

  @Get('wholesalers')
  @RequirePermissions('stores.manage')
  wholesalers(@Req() req: RequestWithFirebase) {
    return this.admin.listWholesalers(req.firebaseUid!);
  }

  @Patch('wholesalers/:id')
  @RequirePermissions('stores.manage')
  patchWholesaler(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Body() body: { status?: string; name?: string; category?: string; city?: string; commission?: number },
  ) {
    return this.admin.patchWholesaler(req.firebaseUid!, id, body);
  }

  @Get('categories')
  @RequirePermissions('stores.manage')
  categories(@Req() req: RequestWithFirebase, @Query('kind') kind?: string) {
    return this.admin.listCategories(req.firebaseUid!, kind ?? 'all');
  }

  @Post('categories')
  @RequirePermissions('stores.manage')
  createCategory(
    @Req() req: RequestWithFirebase,
    @Body() body: { name?: string; kind?: string; status?: string; payload?: Record<string, unknown> },
  ) {
    return this.admin.createCategory(req.firebaseUid!, {
      name: body.name ?? '',
      kind: body.kind,
      status: body.status,
      payload: body.payload,
    });
  }

  @Patch('categories/:id')
  @RequirePermissions('stores.manage')
  patchCategory(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Body() body: { name?: string; kind?: string; status?: string; payload?: Record<string, unknown> },
  ) {
    return this.admin.patchCategory(req.firebaseUid!, id, body);
  }

  @Patch('categories/:id/commission')
  @RequirePermissions('stores.manage')
  patchCategoryCommission(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Body() body: { commissionPercent?: number },
  ) {
    const raw = body.commissionPercent;
    if (raw === undefined || raw === null) {
      throw new BadRequestException('commissionPercent is required');
    }
    return this.admin.patchCategoryCommissionPercent(req.firebaseUid!, id, Number(raw));
  }

  @Delete('categories/:id')
  @RequirePermissions('stores.manage')
  deleteCategory(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.admin.deleteCategory(req.firebaseUid!, id);
  }

  @Post('notifications/broadcast')
  @RequirePermissions('stores.manage')
  broadcastNotifications(@Req() req: RequestWithFirebase, @Body() body: BroadcastNotificationBody) {
    return this.admin.broadcastNotification(req.firebaseUid!, {
      title: body.title ?? '',
      body: body.body ?? '',
      targetRole: body.targetRole ?? null,
      data: body.data,
    });
  }

  @Get('settings')
  @RequirePermissions('stores.manage')
  settings(@Req() req: RequestWithFirebase) {
    return this.admin.getSettings(req.firebaseUid!);
  }

  @Patch('settings')
  @RequirePermissions('stores.manage')
  patchSettings(@Req() req: RequestWithFirebase, @Body() body: { payload: Record<string, unknown> }) {
    return this.admin.patchSettings(req.firebaseUid!, body.payload ?? {});
  }

  @Patch('products/:id/boost')
  @RequirePermissions('products.manage')
  patchProductBoost(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Body() body: PatchProductBoostBody,
  ) {
    return this.admin.patchProductBoost(req.firebaseUid!, id, {
      isBoosted: body.isBoosted,
      isTrending: body.isTrending,
    });
  }

  @Get('ratings')
  @RequirePermissions('stores.manage')
  ratings(
    @Req() req: RequestWithFirebase,
    @Query('targetType') targetType?: string,
    @Query('limit', new ParseIntPipe({ optional: true })) limit?: number,
    @Query('offset', new ParseIntPipe({ optional: true })) offset?: number,
  ) {
    return this.admin.listRatings(req.firebaseUid!, targetType ?? 'all', limit ?? 50, offset ?? 0);
  }

  @Patch('ratings/:id')
  @RequirePermissions('stores.manage')
  patchRating(@Req() req: RequestWithFirebase, @Param('id') id: string, @Body() body: PatchRatingBody) {
    return this.admin.patchRating(req.firebaseUid!, id, { reviewText: body.reviewText });
  }

  @Delete('ratings/:id')
  @RequirePermissions('stores.manage')
  deleteRating(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.admin.deleteRating(req.firebaseUid!, id);
  }

  // ─── Sessions (device tracking) ─────────────────────────────────────────

  @Get('sessions')
  @RequirePermissions('stores.manage')
  listSessions(
    @Query('limit', new ParseIntPipe({ optional: true })) limit?: number,
    @Query('offset', new ParseIntPipe({ optional: true })) offset?: number,
  ) {
    return this.sessions.listAll(limit ?? 50, offset ?? 0);
  }

  @Get('sessions/user/:uid')
  @RequirePermissions('stores.manage')
  listUserSessions(@Param('uid') uid: string) {
    return this.sessions.listForUser(uid);
  }

  @Delete('sessions/:id')
  @RequirePermissions('stores.manage')
  deleteSession(@Param('id') id: string) {
    return this.sessions.deleteSession(id);
  }

  @Delete('sessions/user/:uid')
  @RequirePermissions('stores.manage')
  deleteAllUserSessions(@Param('uid') uid: string) {
    return this.sessions.deleteAllForUser(uid);
  }

}
