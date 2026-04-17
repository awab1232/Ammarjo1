export type StoreRecord = {
  id: string;
  ownerId: string;
  tenantId: string | null;
  name: string;
  description: string;
  category: string;
  status: string;
  isFeatured: boolean;
  isBoosted: boolean;
  boostExpiresAt: string | null;
  storeType: string;
  hasActivePromotions: boolean;
  hasDiscountedProducts: boolean;
  freeDelivery: boolean;
  storeTypeId: string | null;
  storeTypeKey: string | null;
  imageUrl: string;
  logoUrl: string;
  createdAt: string;
};

export type StoreCategoryRecord = {
  id: string;
  storeId: string;
  name: string;
  orderIndex: number;
  createdAt: string;
};

export type StoreProductRecord = {
  id: string;
  storeId: string;
  categoryId: string | null;
  name: string;
  description: string;
  price: number;
  hasVariants: boolean;
  images: string[];
  stock: number;
  createdAt: string;
};

export type ProductVariantOptionType = 'color' | 'size' | 'weight' | 'dimension';

export type ProductVariantOptionRecord = {
  id: string;
  variantId: string;
  optionType: ProductVariantOptionType;
  optionValue: string;
};

export type ProductVariantRecord = {
  id: string;
  productId: string | null;
  wholesaleProductId: string | null;
  sku: string | null;
  price: number;
  stock: number;
  isDefault: boolean;
  createdAt: string;
  options: ProductVariantOptionRecord[];
};
