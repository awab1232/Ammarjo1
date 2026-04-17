import { Module } from '@nestjs/common';
import { InternalApiKeyGuard } from '../search/internal-api-key.guard';
import { ChatController } from './chat.controller';
import { ChatService } from './chat.service';

/**
 * CHAT ARCHITECTURE LOCKED
 * Firebase handles realtime messaging
 * Backend is control plane only
 */
@Module({
  controllers: [ChatController],
  providers: [ChatService, InternalApiKeyGuard],
})
export class ChatModule {}

