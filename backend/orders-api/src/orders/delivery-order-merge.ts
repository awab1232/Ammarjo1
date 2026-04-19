import type { StoredOrder } from './order-types';

/** Matches DriversService.retryAssignment manual cap. */
export const ORDER_DELIVERY_MANUAL_RETRY_MAX = 3;

/** Max automatic re-assignments after no_driver_found (separate from manual retries). */
export const ORDER_DELIVERY_AUTO_RETRY_MAX = 2;

function num(v: unknown): number | null {
  if (v == null) return null;
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function intish(v: unknown): number | null {
  if (v == null) return null;
  if (typeof v === 'number' && Number.isFinite(v)) return Math.trunc(v);
  const n = Number.parseInt(String(v), 10);
  return Number.isFinite(n) ? n : null;
}

export type OrderDeliveryJoinRow = {
  driver_id: string | null;
  delivery_status: string | null;
  delivery_lat: string | null;
  delivery_lng: string | null;
  eta_minutes: string | null;
  assigned_at: Date | null;
  /** From `orders.created_at` when selected (single/list reads). */
  created_at?: Date | null;
  delivery_on_the_way_at?: Date | null;
  delivery_delivered_at?: Date | null;
  driver_name: string | null;
  driver_phone: string | null;
  delivery_manual_retries: string | number | null;
};

/**
 * Overlays PostgreSQL delivery + driver columns onto the JSON payload (list + single order reads).
 */
export function mergeStoredOrderWithDeliveryColumns(
  payload: unknown,
  row: OrderDeliveryJoinRow,
): StoredOrder {
  if (payload == null || typeof payload !== 'object' || Array.isArray(payload)) {
    throw new Error('mergeStoredOrderWithDeliveryColumns: invalid payload');
  }
  const base = payload as Record<string, unknown>;
  const eta = intish(row.eta_minutes);
  const manual = intish(row.delivery_manual_retries) ?? 0;
  const st = row.delivery_status ?? '';

  const merged: StoredOrder = {
    ...(base as StoredOrder),
    driverId: row.driver_id ?? (base['driverId'] as string | undefined),
    deliveryStatus: row.delivery_status ?? (base['deliveryStatus'] as string | undefined),
    deliveryLat: num(row.delivery_lat) ?? (base['deliveryLat'] as number | undefined),
    deliveryLng: num(row.delivery_lng) ?? (base['deliveryLng'] as number | undefined),
    etaMinutes: eta ?? (base['etaMinutes'] as number | undefined),
    assignedAt:
      row.assigned_at != null
        ? row.assigned_at.toISOString()
        : (base['assignedAt'] as string | undefined),
    onTheWayAt:
      row.delivery_on_the_way_at != null
        ? row.delivery_on_the_way_at.toISOString()
        : (base['onTheWayAt'] as string | undefined),
    deliveredAt:
      row.delivery_delivered_at != null
        ? row.delivery_delivered_at.toISOString()
        : (base['deliveredAt'] as string | undefined),
    createdAt:
      row.created_at != null
        ? row.created_at.toISOString()
        : (base['createdAt'] as string | undefined),
    driverName: row.driver_id != null ? row.driver_name ?? null : null,
    driverPhone: row.driver_id != null ? row.driver_phone ?? null : null,
  };

  if (st === 'no_driver_found') {
    merged.canRetry = manual < ORDER_DELIVERY_MANUAL_RETRY_MAX;
    merged.retryRemaining = Math.max(0, ORDER_DELIVERY_MANUAL_RETRY_MAX - manual);
  } else {
    delete merged.canRetry;
    delete merged.retryRemaining;
  }

  return merged;
}
