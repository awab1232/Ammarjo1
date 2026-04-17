/** Row in PostgreSQL `catalog_products` and Algolia object shape. */
export type CatalogProductRow = {
  product_id: number;
  store_id: string;
  name: string;
  description: string;
  price_numeric: string | number;
  currency: string;
  category_ids: number[];
  image_url: string | null;
  stock_status: string;
  searchable_text: string | null;
  updated_at?: Date;
};

/** Algolia record (objectID = String(product_id)). */
export type AlgoliaProductRecord = {
  objectID: string;
  productId: number;
  storeId: string;
  name: string;
  description: string;
  /** Facets / filters */
  price_numeric: number;
  currency: string;
  categoryIds: number[];
  imageUrl: string | null;
  stockStatus: string;
  /** Optional extra text for retrieval / ranking */
  searchableText?: string;
};
