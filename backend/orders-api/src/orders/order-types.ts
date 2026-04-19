import type { OrderComputed } from './order-computed';
import type { ShadowValidationResult } from './order-validation';

export type StoredOrder = Record<string, unknown> & {
  orderId: string;
  customerUid?: string;
  customerEmail: string;
  storeId: string;
  items: unknown[];
  /** Set when migration 031+ applied; mirrored from orders.driver_id / delivery_* columns. */
  driverId?: string | null;
  deliveryStatus?: string;
  deliveryLat?: number | null;
  deliveryLng?: number | null;
  etaMinutes?: number | null;
  assignedAt?: string | null;
  /** When driver marked en route (`on_the_way`). */
  onTheWayAt?: string | null;
  /** When order was marked delivered. */
  deliveredAt?: string | null;
  /** Order row `created_at` (ISO) for timeline «تم الطلب». */
  createdAt?: string | null;
  /** From drivers join when driver_id set. */
  driverName?: string | null;
  driverPhone?: string | null;
  /** When deliveryStatus === no_driver_found — manual POST /orders/:id/retry-assignment. */
  canRetry?: boolean;
  retryRemaining?: number;
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
