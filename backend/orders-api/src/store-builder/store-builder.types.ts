import { Type } from 'class-transformer';
import {
  IsArray,
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  IsUUID,
  ValidateNested,
} from 'class-validator';

export const StoreBuilderModes = ['AI', 'MANUAL'] as const;
export type StoreBuilderMode = (typeof StoreBuilderModes)[number];

export const StoreBuilderTypes = ['construction_store', 'home_store', 'wholesale_store'] as const;
export type StoreBuilderStoreType = (typeof StoreBuilderTypes)[number];

export class BootstrapStoreBuilderDto {
  @IsString()
  @IsNotEmpty()
  storeId!: string;

  @IsString()
  @IsOptional()
  ownerId?: string;

  @IsString()
  @IsOptional()
  @IsIn(StoreBuilderTypes)
  storeType?: StoreBuilderStoreType;
}

export class SetStoreBuilderModeDto {
  @IsString()
  @IsIn(StoreBuilderModes)
  mode!: StoreBuilderMode;
}

export class CreateStoreCategoryDto {
  @IsString()
  @IsNotEmpty()
  name!: string;

  @IsString()
  @IsOptional()
  imageUrl?: string;

  @IsUUID()
  @IsOptional()
  parentId?: string;
}

export class UpdateStoreCategoryDto {
  @IsString()
  @IsOptional()
  name?: string;

  @IsString()
  @IsOptional()
  imageUrl?: string;
}

export class ReorderStoreCategoryItemDto {
  @IsUUID()
  id!: string;

  @Type(() => Number)
  sortOrder!: number;
}

export class ReorderStoreCategoriesDto {
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => ReorderStoreCategoryItemDto)
  items!: ReorderStoreCategoryItemDto[];
}

export class StoreBuilderStoreIdParamDto {
  @IsString()
  @IsNotEmpty()
  storeId!: string;
}

export class StoreBuilderCategoryParamDto extends StoreBuilderStoreIdParamDto {
  @IsUUID()
  categoryId!: string;
}

export class StoreSuggestionRequestDto {
  @IsString()
  @IsNotEmpty()
  storeId!: string;
}

