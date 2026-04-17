import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsIn,
  IsInt,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

/** Validated cart line — extra keys are preserved when the controller passes the raw body through. */
export class OrderCartItemDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(128)
  productId!: string;

  @IsInt()
  @Min(1)
  @Type(() => Number)
  quantity!: number;

  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  price?: number;

  @IsOptional()
  @IsString()
  @MaxLength(128)
  storeId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(128)
  variantId?: string;
}

export class CreateOrderDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(128)
  orderId!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(320)
  customerEmail!: string;

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => OrderCartItemDto)
  items!: OrderCartItemDto[];

  @IsOptional()
  @IsString()
  @MaxLength(64)
  storeId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(128)
  customerUid?: string;

  @IsOptional()
  @IsIn(['backend', 'firebase'])
  writeSource?: 'backend' | 'firebase';

  @IsOptional()
  @IsString()
  @MaxLength(128)
  firebaseOrderId?: string;

  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  subtotalNumeric?: number;

  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  shippingNumeric?: number;

  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  totalNumeric?: number;

  @IsOptional()
  @IsString()
  @MaxLength(8)
  currency?: string;
}
