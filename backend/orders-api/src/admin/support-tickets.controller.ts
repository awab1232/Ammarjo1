import {
  Body,
  Controller,
  Get,
  NotFoundException,
  Param,
  Patch,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { FirebaseAuthGuard, type RequestWithFirebase } from '../auth/firebase-auth.guard';
import { AdminRestService } from './admin-rest.service';

@Controller('support/tickets')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 120 } })
export class SupportTicketsController {
  constructor(private readonly admin: AdminRestService) {}

  @Get()
  @RequirePermissions('orders.read')
  async list(@Req() req: RequestWithFirebase, @Query('id') id?: string) {
    const uid = req.firebaseUid!;
    if (id != null && id.trim() !== '') {
      const one = await this.admin.getSupportTicketForCustomer(uid, id.trim());
      if (one == null) throw new NotFoundException();
      return one;
    }
    return this.admin.listSupportTicketsForCustomer(uid);
  }

  @Post()
  @RequirePermissions('orders.write')
  create(@Req() req: RequestWithFirebase, @Body() body: { userName?: string }) {
    return this.admin.findOrCreateOpenSupportTicket(req.firebaseUid!, body?.userName ?? 'عميل');
  }

  @Patch(':id')
  @RequirePermissions('orders.write')
  patch(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Body()
    body: {
      status?: string;
      message?: { senderId?: string; senderName?: string; text?: string; createdAt?: string };
    },
  ) {
    return this.admin.patchSupportTicketForCustomer(req.firebaseUid!, id, body);
  }
}
