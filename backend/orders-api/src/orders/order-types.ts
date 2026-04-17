import type { OrderComputed } from './order-computed';
import type { ShadowValidationResult } from './order-validation';

export type StoredOrder = Record<string, unknown> & {
  orderId: string;
  customerUid?: string;
  customerEmail: string;
  storeId: string;
  items: unknown[];
};

export type CreateOrderResult = {
  order: StoredOrder;
  validation: ShadowValidationResult;
  storageCheck: { ok: boolean; reasons: string[] };
};

export type OrderGetResponse = {
  order: StoredOrder;
  computed: OrderComputed;
};

/** GET /users/:id/orders — cursor-paginated; use `?legacy=1` for a raw array (deprecated). */
export type UserOrdersListResponse = {
  items: StoredOrder[];
  nextCursor: string | null;
  hasMore: boolean;
  /** Always false — PostgreSQL is the only order store for API reads. */
  useFirestoreFallback: boolean;
};
