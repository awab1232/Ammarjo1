import { IsArray, IsInt, IsNotEmpty, IsNumber, IsOptional, IsString, Min, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';

export type WholesaleStore = {
  id: string;
  ownerId: string;
  name: string;
  logo: string;
  coverImage: string;
  description: string;
  category: string;
  city: string;
  phone: string;
  email: string;
  status: string;
  commission: number;
  deliveryDays: number | null;
  deliveryFee: number | null;
  createdAt: string;
};

export type WholesalePriceRule = {
  minQty: number;
  maxQty: number | null;
  price: number;
};

export type WholesaleProduct = {
  id: string;
  wholesalerId: string;
  productCode: string;
  name: string;
  imageUrl: string;
  unit: string;
  categoryId: string | null;
  stock: number;
  hasVariants?: boolean;
  quantityPrices: WholesalePriceRule[];
};

export type WholesaleOrder = {
  id: string;
  wholesalerId: string;
  storeId: string;
  storeOwnerId: string;
  storeName: string;
  subtotal: number;
  commission: number;
  netAmount: number;
  status: string;
  items: Array<Record<string, unknown>>;
  createdAt: string;
};

export class WholesaleOrderItemDto {
  @IsString()
  @IsNotEmpty()
  productId!: string;

  @IsOptional()
  @IsString()
  variantId?: string;

  @IsString()
  @IsNotEmpty()
  name!: string;

  @IsNumber()
  @Min(0)
  unitPrice!: number;

  @IsInt()
  @Min(1)
  quantity!: number;

  @IsNumber()
  @Min(0)
  total!: number;
}

export class CreateWholesaleOrderDto {
  @IsString()
  @IsNotEmpty()
  wholesalerId!: string;

  @IsString()
  @IsNotEmpty()
  storeId!: string;

  @IsString()
  @IsNotEmpty()
  storeName!: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => WholesaleOrderItemDto)
  items!: WholesaleOrderItemDto[];

  @IsOptional()
  @IsNumber()
  @Min(0)
  commissionRate?: number;
}

export class UpdateWholesaleOrderStatusDto {
  @IsString()
  @IsNotEmpty()
  status!: string;
}

export class WholesaleJoinRequestDto {
  @IsString()
  @IsNotEmpty()
  applicantId!: string;

  @IsString()
  @IsNotEmpty()
  applicantEmail!: string;

  @IsString()
  @IsNotEmpty()
  applicantPhone!: string;

  @IsString()
  @IsNotEmpty()
  wholesalerName!: string;

  @IsString()
  @IsOptional()
  description?: string;

  @IsString()
  @IsOptional()
  category?: string;

  @IsString()
  @IsOptional()
  city?: string;

  @IsArray()
  @IsOptional()
  cities?: string[];
}

export class WholesaleProductWriteDto {
  @IsString()
  @IsNotEmpty()
  storeId!: string;

  @IsString()
  @IsNotEmpty()
  name!: string;

  @IsString()
  @IsOptional()
  imageUrl?: string;

  @IsString()
  @IsOptional()
  unit?: string;

  @IsOptional()
  @IsInt()
  stock?: number;

  @IsString()
  @IsOptional()
  categoryId?: string;

  @IsArray()
  @IsOptional()
  quantityPrices?: WholesalePriceRule[];

  @IsOptional()
  hasVariants?: boolean;

  @IsArray()
  @IsOptional()
  variants?: Array<{
    sku?: string;
    price: number;
    stock: number;
    isDefault?: boolean;
    options: Array<{ optionType: 'color' | 'size' | 'weight' | 'dimension'; optionValue: string }>;
  }>;
}

export class WholesaleCategoryWriteDto {
  @IsString()
  @IsNotEmpty()
  storeId!: string;

  @IsString()
  @IsNotEmpty()
  name!: string;

  @IsOptional()
  @IsInt()
  order?: number;
}

export class WholesaleStorePatchDto {
  @IsOptional()
  @IsString()
  name?: string;

  @IsOptional()
  @IsString()
  logo?: string;

  @IsOptional()
  @IsString()
  coverImage?: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsString()
  category?: string;

  @IsOptional()
  @IsString()
  city?: string;

  @IsOptional()
  @IsString()
  phone?: string;

  @IsOptional()
  @IsString()
  email?: string;

  @IsOptional()
  @IsString()
  status?: string;
}
