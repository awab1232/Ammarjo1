/**
 * Mirrors `OrderService` in the Flutter app: same store resolution and email normalization.
 * Stock/coupon rules stay in Firebase for now — this API only validates the accepted payload shape.
 */

export function normalizeCustomerEmail(email: string): string {
  return email.trim().toLowerCase();
}

export interface CartItemLike {
  storeId?: string;
  [key: string]: unknown;
}

/** Same as `OrderService.resolveOrderStoreId`. */
export function resolveOrderStoreId(items: CartItemLike[]): string {
  if (!items.length) return 'ammarjo';
  const ids = items.map((e) => String(e.storeId ?? '').trim()).filter((s) => s.length > 0);
  if (!ids.length) return 'ammarjo';
  const distinct = new Set(ids);
  if (distinct.size === 1) return ids[0];
  return ids[0];
}

export function assertOrderPayload(
  body: Record<string, unknown>,
  firebaseUid: string,
): void {
  const items = body.items;
  if (!Array.isArray(items) || items.length === 0) {
    throw new Error('items must be a non-empty array');
  }
  const resolved = resolveOrderStoreId(items as CartItemLike[]);
  const storeId = body.storeId != null ? String(body.storeId).trim() : '';
  if (storeId && storeId !== resolved) {
    throw new Error('storeId does not match cart-derived storeId');
  }
  const uid = body.customerUid != null ? String(body.customerUid).trim() : '';
  if (uid && uid !== firebaseUid) {
    throw new Error('customerUid must match authenticated user');
  }
  const email = body.customerEmail != null ? String(body.customerEmail) : '';
  if (!email.trim()) {
    throw new Error('customerEmail is required');
  }
  const orderId = body.orderId != null ? String(body.orderId).trim() : '';
  if (!orderId) {
    throw new Error('orderId is required');
  }
}
