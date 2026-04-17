import { IsNotEmpty, IsOptional, IsString, IsUUID, Min } from 'class-validator';

export class CreateStoreDto {
  @IsOptional()
  @IsUUID()
  id?: string;

  @IsString()
  @IsNotEmpty()
  ownerId!: string;

  @IsString()
  @IsNotEmpty()
  name!: string;

  @IsString()
  @IsNotEmpty()
  storeType!: 'construction_store' | 'home_store';

  @IsOptional()
  @IsString()
  status?: string;
}

export class CreateCategoryDto {
  @IsOptional()
  @IsUUID()
  id?: string;

  @IsUUID()
  storeId!: string;

  @IsString()
  @IsNotEmpty()
  name!: string;

  @IsOptional()
  @IsUUID()
  parentId?: string;

  @IsOptional()
  @Min(0)
  sortOrder?: number;
}

export class CreateProductDto {
  @IsOptional()
  @IsUUID()
  id?: string;

  @IsUUID()
  storeId!: string;

  @IsOptional()
  @IsUUID()
  categoryId?: string;

  @IsString()
  @IsNotEmpty()
  name!: string;

  @IsOptional()
  @IsString()
  description?: string;

  @Min(0)
  price!: number;

  @IsOptional()
  @IsString()
  imageUrl?: string;
}

