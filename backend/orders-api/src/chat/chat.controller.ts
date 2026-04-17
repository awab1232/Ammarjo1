import { Controller, Get, ParseIntPipe, Query, UseGuards } from '@nestjs/common';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { InternalApiKeyGuard } from '../search/internal-api-key.guard';
import { ChatService } from './chat.service';

@Controller('internal/chat')
@UseGuards(TenantContextGuard, ApiPolicyGuard, InternalApiKeyGuard)
@ApiPolicy({ auth: false, tenant: 'none', rateLimit: { rpm: 120 } })
export class ChatController {
  constructor(private readonly chat: ChatService) {}

  @Get('control-plane')
  controlPlane(@Query('limit', new ParseIntPipe({ optional: true })) limit?: number) {
    return this.chat.getOverview(limit ?? 50);
  }
}

