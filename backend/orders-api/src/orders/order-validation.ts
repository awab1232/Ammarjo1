import type { CartItemLike } from './order-rules';
import { normalizeCustomerEmail, resolveOrderStoreId } from './order-rules';

/** JOD amounts use 3 decimals in the app — keep a small tolerance. */
const AMOUNT_EPS = 0.001;

function near(a: number, b: number): boolean {
  return Math.abs(a - b) < AMOUNT_EPS;
}

function num(v: unknown): number | null {
  if (v == null) return null;
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

export interface ShadowValidationResult {
  ok: boolean;
  mismatches: string[];
}

/**
 * Recomputes totals and identity fields from `items` and compares to the incoming payload.
 * Does not throw — used for monitoring parity with Firebase (source of truth).
 */
export function validateShadowOrderPayload(
  body: Record<string, unknown>,
  firebaseUid: string,
): ShadowValidationResult {
  const mismatches: string[] = [];
  const items = body.items;
  if (!Array.isArray(items) || items.length === 0) {
    return { ok: false, mismatches: ['items must be a non-empty array'] };
  }

  // --- userId (customerUid must match token when present) ---
  const uidIn = body.customerUid != null ? String(body.customerUid).trim() : '';
  if (uidIn && uidIn !== firebaseUid) {
    mismatches.push(`userId: customerUid "${uidIn}" !== token uid "${firebaseUid}"`);
  }

  // --- storeId ---
  let resolvedStore = 'ammarjo';
  try {
    resolvedStore = resolveOrderStoreId(items as CartItemLike[]);
  } catch {
    mismatches.push('multi_store_order_not_allowed');
    resolvedStore = '';
  }
  const declaredStore =
    body.storeId != null && String(body.storeId).trim().length > 0
      ? String(body.storeId).trim()
      : '';
  if (declaredStore && declaredStore !== resolvedStore) {
    mismatches.push(
      `storeId: declared "${declaredStore}" !== cart-derived "${resolvedStore}"`,
    );
  }

  // --- item quantities & subtotal from lines ---
  let computedSubtotal = 0;
  for (let i = 0; i < items.length; i++) {
    const row = items[i];
    if (!row || typeof row !== 'object') {
      mismatches.push(`items[${i}]: invalid row`);
      continue;
    }
    const o = row as Record<string, unknown>;
    const qty = num(o.quantity);
    const price = num(o.price);
    if (qty == null || !Number.isInteger(qty) || qty < 1) {
      mismatches.push(`items[${i}]: quantity must be a positive integer (got ${String(o.quantity)})`);
    }
    if (price == null || price < 0) {
      mismatches.push(`items[${i}]: invalid price`);
    }
    if (qty != null && price != null && Number.isFinite(qty) && Number.isFinite(price)) {
      computedSubtotal += price * qty;
    }
  }

  const subIn = num(body.subtotalNumeric);
  if (subIn != null && !near(computedSubtotal, subIn)) {
    mismatches.push(
      `subtotalNumeric: payload ${subIn} !== recomputed ${computedSubtotal.toFixed(4)}`,
    );
  }

  const shipIn = num(body.shippingNumeric) ?? 0;
  const totalIn = num(body.totalNumeric);
  const recomputedTotal = computedSubtotal + shipIn;
  if (totalIn != null && !near(recomputedTotal, totalIn)) {
    mismatches.push(
      `totalNumeric: payload ${totalIn} !== recomputed (subtotal+shipping) ${recomputedTotal.toFixed(4)}`,
    );
  }

  // Cross-check declared subtotal + shipping vs total when all present
  if (subIn != null && totalIn != null) {
    const sum = subIn + shipIn;
    if (!near(sum, totalIn)) {
      mismatches.push(
        `totalNumeric: ${totalIn} !== subtotalNumeric+shippingNumeric (${sum.toFixed(4)})`,
      );
    }
  }

  const emailIn = body.customerEmail != null ? String(body.customerEmail) : '';
  if (emailIn.trim()) {
    const norm = normalizeCustomerEmail(emailIn);
    if (norm !== emailIn) {
      mismatches.push(
        `customerEmail: payload should match OrderService.normalizeCustomerEmail (expected "${norm}")`,
      );
    }
  }

  return { ok: mismatches.length === 0, mismatches };
}
