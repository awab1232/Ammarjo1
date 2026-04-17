import { Body, Controller, Post, Req, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import type { RequestWithFirebase } from '../auth/firebase-auth.guard';
import { StoreRequestsService } from './store-requests.service';

@Controller('store-requests')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 30 } })
export class StoreRequestsController {
  constructor(private readonly requests: StoreRequestsService) {}

  @Post()
  @RequirePermissions('orders.read')
  submit(@Req() req: RequestWithFirebase, @Body() body: Record<string, unknown>) {
    const kind = String(body['kind'] ?? '').trim().toLowerCase();
    if (kind === 'technician_request') {
      return this.requests.submitTechnicianRequest(body, req.firebaseUid!);
    }
    return this.requests.submitStoreRequest(body, req.firebaseUid!);
  }
}
