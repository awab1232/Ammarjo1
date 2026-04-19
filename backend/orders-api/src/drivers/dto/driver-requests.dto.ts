import { Type } from 'class-transformer';
import { IsIn, IsNotEmpty, IsNumber, IsOptional, IsString, IsUUID, Max, Min } from 'class-validator';

/** POST /drivers/request — onboarding application (camelCase body). */
export class CreateDriverApplicationDto {
  @IsString()
  @IsNotEmpty()
  fullName!: string;

  @IsString()
  @IsNotEmpty()
  phone!: string;

  @IsString()
  @IsNotEmpty()
  identityImageUrl!: string;
}

export class RegisterDriverDto {
  @IsOptional()
  @IsString()
  name?: string;

  @IsOptional()
  @IsString()
  phone?: string;
}

export class DriverLocationDto {
  @Type(() => Number)
  @IsNumber()
  @Min(-90)
  @Max(90)
  lat!: number;

  @Type(() => Number)
  @IsNumber()
  @Min(-180)
  @Max(180)
  lng!: number;
}

const DRIVER_STATUSES = ['online', 'offline', 'busy'] as const;

export class DriverStatusDto {
  @IsIn(DRIVER_STATUSES)
  status!: (typeof DRIVER_STATUSES)[number];
}

export class OrderIdBodyDto {
  @IsString()
  @IsNotEmpty()
  orderId!: string;
}

export class ManualAssignDriverDto {
  @IsUUID('4')
  driverId!: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(-90)
  @Max(90)
  deliveryLat?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(-180)
  @Max(180)
  deliveryLng?: number;
}
