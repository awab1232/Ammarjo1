import { IsISO8601, IsNotEmpty, IsObject, IsOptional, IsString } from 'class-validator';

class BaseChatEventDto {
  @IsString()
  @IsNotEmpty()
  conversationId!: string;

  @IsOptional()
  @IsString()
  senderId?: string;

  @IsOptional()
  @IsString()
  tenantId?: string;

  @IsOptional()
  @IsISO8601()
  occurredAt?: string;

  @IsOptional()
  @IsObject()
  meta?: Record<string, unknown>;
}

export class ChatMessageSentDto extends BaseChatEventDto {
  @IsOptional()
  @IsString()
  targetUserId?: string;

  @IsOptional()
  @IsString()
  type?: string;
}

export class ChatConversationCreatedDto extends BaseChatEventDto {}

export class ChatMessageReadDto extends BaseChatEventDto {
  @IsOptional()
  @IsString()
  readerId?: string;
}
