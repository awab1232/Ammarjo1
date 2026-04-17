import { Type } from 'class-transformer';
import { IsNotEmpty, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

export const ServiceRequestStatuses = [
  'pending',
  'assigned',
  'in_progress',
  'completed',
  'cancelled',
] as const;

export type ServiceRequestStatus = (typeof ServiceRequestStatuses)[number];

export type ServiceRequestRecord = {
  id: string;
  customerId: string;
  technicianId: string | null;
  conversationId: string;
  status: ServiceRequestStatus;
  description: string;
  title: string;
  categoryId: string;
  imageUrl: string | null;
  notes: string;
  chatId: string | null;
  technicianEmail: string | null;
  earningsAmount: number;
  createdAt: string;
  updatedAt: string;
};

export class CreateServiceRequestDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(200)
  conversationId!: string;

  @IsString()
  @IsOptional()
  @MaxLength(20_000)
  description?: string;

  @IsString()
  @IsOptional()
  @MaxLength(2048)
  imageUrl?: string;

  @IsString()
  @IsOptional()
  @MaxLength(500)
  title?: string;

  @IsString()
  @IsOptional()
  @MaxLength(120)
  categoryId?: string;

  @IsString()
  @IsOptional()
  @MaxLength(5000)
  notes?: string;
}

export class AssignServiceRequestDto {
  @IsString()
  @IsNotEmpty()
  technicianId!: string;
}

export class ServiceRequestIdParamDto {
  @Type(() => String)
  @IsUUID()
  id!: string;
}

export class AttachChatDto {
  @IsString()
  @IsNotEmpty()
  chatId!: string;
}

