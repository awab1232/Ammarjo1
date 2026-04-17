import type { CartItemLike } from './order-rules';
import { resolveOrderStoreId } from './order-rules';

function num(v: unknown): number | null {
  if (v == null) return null;
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

/**
 * Same recomputation rules as Flutter `OrderService` line totals (subtotal from items).
 */
export interface OrderComputed {
  subtotalNumeric: number;
  shippingNumeric: number;
  /** `subtotalNumeric + shippingNumeric` — comparable to stored `totalNumeric`. */
  totalNumericFromLines: number;
  itemCount: number;
  resolvedStoreId: string;
}

export function computeOrderServiceFields(order: Record<string, unknown>): OrderComputed {
  const rawItems = order.items;
  const items = Array.isArray(rawItems) ? rawItems : [];
  let subtotal = 0;
  for (const row of items) {
    if (!row || typeof row !== 'object') continue;
    const o = row as Record<string, unknown>;
    const price = num(o.price);
    const qty = num(o.quantity);
    if (price != null && qty != null && Number.isFinite(price) && Number.isFinite(qty)) {
      subtotal += price * qty;
    }
  }
  const shipping = num(order.shippingNumeric) ?? 0;
  return {
    subtotalNumeric: subtotal,
    shippingNumeric: shipping,
    totalNumericFromLines: subtotal + shipping,
    itemCount: items.length,
    resolvedStoreId: resolveOrderStoreId(items as CartItemLike[]),
  };
}
