import {
  Body,
  Controller,
  Delete,
  ForbiddenException,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { FirebaseAuthGuard, type RequestWithFirebase } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RoleGuard } from '../identity/role.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { Roles } from '../identity/roles.decorator';
import { getTenantContext } from '../identity/tenant-context.storage';
import { TendersService } from './tenders.service';

interface CreateTenderBody {
  category?: string;
  description?: string;
  city?: string;
  userName?: string;
  storeTypeId?: string;
  storeTypeKey?: string;
  storeTypeName?: string;
  imageBase64?: string;
  imageUrl?: string;
}

interface SubmitOfferBody {
  storeId?: string;
  storeName?: string;
  storeOwnerUid?: string;
  price?: number;
  note?: string;
}

interface PatchOfferBody {
  status?: string;
}

interface PatchTenderBody {
  status?: string;
}

/**
 * Customer-facing tenders routes (mirrors the Flutter `BackendTenderClient`).
 * Guarded by Firebase auth + tenant + RBAC using the shared `orders.*` permissions.
 */
@Controller('tenders')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 180 } })
export class TendersController {
  constructor(private readonly tenders: TendersService) {}

  private requireActorUid(req: RequestWithFirebase): string {
    const uid = String(req.firebaseUid ?? '').trim();
    if (!uid) throw new ForbiddenException('forbidden');
    return uid;
  }

  private isAdminActor(): boolean {
    const role = String(getTenantContext()?.activeRole ?? '').trim().toLowerCase();
    return role === 'admin' || role === 'system_internal';
  }

  @Post()
  @RequirePermissions('orders.write')
  create(@Req() req: RequestWithFirebase, @Body() body: CreateTenderBody) {
    return this.tenders.create({
      customerUid: req.firebaseUid ?? '',
      category: body.category ?? '',
      description: body.description ?? '',
      city: body.city ?? '',
      userName: body.userName ?? '',
      storeTypeId: body.storeTypeId ?? null,
      storeTypeKey: body.storeTypeKey ?? null,
      storeTypeName: body.storeTypeName ?? null,
      imageBase64: body.imageBase64 ?? null,
      imageUrl: body.imageUrl ?? null,
    });
  }

  @Get('mine')
  @RequirePermissions('orders.read')
  mine(@Req() req: RequestWithFirebase, @Query('limit') limit?: string) {
    return this.tenders.listMine(req.firebaseUid ?? '', Number(limit ?? 50));
  }

  /**
   * Open feed for store owners to browse tenders targeted at their store type.
   * Clients pass the store's own `storeTypeId` (or `storeTypeKey`) and optional city.
   */
  @Get('open')
  @RequirePermissions('orders.read')
  @UseGuards(RoleGuard)
  @Roles('store_owner', 'admin')
  open(
    @Req() req: RequestWithFirebase,
    @Query('storeTypeId') storeTypeId?: string,
    @Query('storeTypeKey') storeTypeKey?: string,
    @Query('city') city?: string,
    @Query('limit') limit?: string,
  ) {
    return this.tenders.listOpenForStore({
      actorUid: req.firebaseUid ?? '',
      storeTypeId,
      storeTypeKey,
      city,
      limit: limit ? Number(limit) : undefined,
    });
  }

  @Get(':id')
  @RequirePermissions('orders.read')
  getOne(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.tenders.getById(id, this.requireActorUid(req), this.isAdminActor());
  }

  @Get(':id/offers')
  @RequirePermissions('orders.read')
  offers(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.tenders.listOffers(id, this.requireActorUid(req), this.isAdminActor());
  }

  @Post(':id/offers')
  @RequirePermissions('orders.write')
  @UseGuards(RoleGuard)
  @Roles('store_owner', 'admin')
  submitOffer(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Body() body: SubmitOfferBody,
  ) {
    return this.tenders.submitOffer({
      actorUid: req.firebaseUid ?? '',
      tenderId: id,
      storeId: body.storeId ?? '',
      storeName: body.storeName ?? '',
      price: Number(body.price ?? 0),
      note: body.note ?? '',
    });
  }

  @Patch(':id/offers/:offerId')
  @RequirePermissions('orders.write')
  patchOffer(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Param('offerId') offerId: string,
    @Body() body: PatchOfferBody,
  ) {
    return this.tenders.patchOffer(req.firebaseUid ?? '', id, offerId, body);
  }

  @Patch(':id')
  @RequirePermissions('orders.write')
  patch(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Body() body: PatchTenderBody,
  ) {
    return this.tenders.patchTenderStatus(req.firebaseUid ?? '', id, body);
  }

  @Delete(':id')
  @RequirePermissions('orders.write')
  remove(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.tenders.deleteTender(req.firebaseUid ?? '', id);
  }
}
