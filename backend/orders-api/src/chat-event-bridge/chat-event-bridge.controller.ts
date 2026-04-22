import { Body, Controller, HttpCode, HttpStatus, Post, Req, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard, type RequestWithFirebase } from '../auth/firebase-auth.guard';
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

@Controller('chat/events')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 600 } })
export class ChatEventsPublicController {
  constructor(private readonly bridge: ChatEventBridgeService) {}

  @Post('message-sent')
  @HttpCode(HttpStatus.ACCEPTED)
  messageSent(@Req() req: RequestWithFirebase, @Body() body: ChatMessageSentDto) {
    const senderId = (body.senderId ?? '').trim() || (req.firebaseUid ?? '').trim();
    const receiverId = (body.receiverId ?? body.targetUserId ?? '').trim();
    const conversationId = body.conversationId?.trim() ?? '';
    const messageId = body.messageId?.trim() ?? '';
    const messagePreview = body.messagePreview?.trim() ?? '';
    if (!senderId || !receiverId || !conversationId || !messageId || !messagePreview) {
      return this.bridge.rejectInvalidMessageSent({
        senderId,
        receiverId,
        conversationId,
        messageId,
        messagePreview,
      });
    }
    return this.bridge.messageSent({
      ...body,
      senderId,
      targetUserId: receiverId,
      receiverId,
      messageId,
      messagePreview,
    });
  }
}

