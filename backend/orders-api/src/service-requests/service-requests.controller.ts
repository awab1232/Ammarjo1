import { Body, Controller, Get, Param, ParseIntPipe, Post, Query, Req, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard, type RequestWithFirebase } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import {
  AssignServiceRequestDto,
  AttachChatDto,
  CreateServiceRequestDto,
  ServiceRequestIdParamDto,
} from './service-requests.types';
import { ServiceRequestsService } from './service-requests.service';

@Controller('service-requests')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 180 } })
export class ServiceRequestsController {
  constructor(private readonly serviceRequests: ServiceRequestsService) {}

  @Get()
  @RequirePermissions('orders.read')
  list(
    @Query('customerId') customerId?: string,
    @Query('technicianId') technicianId?: string,
    @Query('status') status?: string,
    @Query('limit', new ParseIntPipe({ optional: true })) limit?: number,
    @Query('cursor') cursor?: string,
  ) {
    return this.serviceRequests.listRequests({
      customerId,
      technicianId,
      status,
      limit: limit ?? 20,
      cursor,
    });
  }

  @Post()
  @RequirePermissions('orders.write')
  create(@Req() req: RequestWithFirebase, @Body() body: CreateServiceRequestDto) {
    return this.serviceRequests.createRequest({
      conversationId: body.conversationId,
      description: body.description,
      imageUrl: body.imageUrl,
      title: body.title,
      categoryId: body.categoryId,
      notes: body.notes,
      customerId: req.firebaseUid,
    });
  }

  @Get('earnings')
  @RequirePermissions('orders.read')
  earnings(@Query('technicianEmail') technicianEmail?: string) {
    return this.serviceRequests.getEarnings(technicianEmail?.trim() || '');
  }

  @Get(':id')
  @RequirePermissions('orders.read')
  getOne(@Param() params: ServiceRequestIdParamDto) {
    return this.serviceRequests.getById(params.id);
  }

  @Post(':id/assign')
  @RequirePermissions('orders.read')
  assign(@Param() params: ServiceRequestIdParamDto, @Body() body: AssignServiceRequestDto) {
    return this.serviceRequests.assignTechnician(params.id, body.technicianId);
  }

  @Post(':id/start')
  @RequirePermissions('orders.write')
  start(@Param() params: ServiceRequestIdParamDto) {
    return this.serviceRequests.startRequest(params.id);
  }

  @Post(':id/complete')
  @RequirePermissions('orders.write')
  complete(@Param() params: ServiceRequestIdParamDto) {
    return this.serviceRequests.completeRequest(params.id);
  }

  @Post(':id/cancel')
  @RequirePermissions('orders.write')
  cancel(@Param() params: ServiceRequestIdParamDto) {
    return this.serviceRequests.cancelRequest(params.id);
  }

  @Post(':id/attach-chat')
  @RequirePermissions('orders.write')
  attachChat(@Param() params: ServiceRequestIdParamDto, @Body() body: AttachChatDto) {
    return this.serviceRequests.attachChat(params.id, body.chatId);
  }
}

