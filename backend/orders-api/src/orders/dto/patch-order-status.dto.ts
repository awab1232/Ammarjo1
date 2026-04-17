import { Transform } from 'class-transformer';
import { IsIn, IsNotEmpty, IsString, MaxLength } from 'class-validator';

const STATUSES = [
  'pending',
  'processing',
  'shipped',
  'delivered',
  'cancelled',
  'completed',
] as const;

export class PatchOrderStatusDto {
  @Transform(({ value }) => (typeof value === 'string' ? value.trim().toLowerCase() : value))
  @IsString()
  @IsNotEmpty()
  @MaxLength(64)
  @IsIn([...STATUSES])
  status!: string;
}
