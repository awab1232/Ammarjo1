import { Body, Controller, HttpCode, HttpStatus, Post, UseGuards } from '@nestjs/common';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { InternalApiKeyGuard } from '../search/internal-api-key.guard';
import { ChatConversationCreatedDto, ChatMessageReadDto, ChatMessageSentDto } from './chat-event-bridge.dto';
import { ChatEventBridgeService } from './chat-event-bridge.service';

@Controller('internal/chat-events')
@UseGuards(TenantContextGuard, ApiPolicyGuard, InternalApiKeyGuard)
@ApiPolicy({ auth: false, tenant: 'optional', rateLimit: { rpm: 600 } })
export class ChatEventBridgeController {
  constructor(private readonly bridge: ChatEventBridgeService) {}

  @Post('message-sent')
  @HttpCode(HttpStatus.ACCEPTED)
  messageSent(@Body() body: ChatMessageSentDto) {
    return this.bridge.messageSent(body);
  }

  @Post('conversation-created')
  @HttpCode(HttpStatus.ACCEPTED)
  conversationCreated(@Body() body: ChatConversationCreatedDto) {
    return this.bridge.conversationCreated(body);
  }

  @Post('message-read')
  @HttpCode(HttpStatus.ACCEPTED)
  messageRead(@Body() body: ChatMessageReadDto) {
    return this.bridge.messageRead(body);
  }
}

