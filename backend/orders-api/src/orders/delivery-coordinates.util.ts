import type { UsersService } from '../users/users.service';

function num(v: unknown): number | null {
  if (v == null) return null;
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function pickCoords(obj: unknown): { lat: number; lng: number } | null {
  if (obj == null || typeof obj !== 'object' || Array.isArray(obj)) {
    return null;
  }
  const o = obj as Record<string, unknown>;
  const lat = num(o.lat ?? o.latitude ?? o.deliveryLat);
  const lng = num(o.lng ?? o.longitude ?? o.deliveryLng ?? o.lon);
  if (lat == null || lng == null) {
    return null;
  }
  return { lat, lng };
}

/**
 * Resolves delivery coordinates for routing: explicit fields, nested billing/shipping, then user profile.
 */
export async function resolveDeliveryCoordinates(
  body: Record<string, unknown>,
  firebaseUid: string,
  users: UsersService,
): Promise<{ lat: number; lng: number } | null> {
  const topLat = num(body.deliveryLat);
  const topLng = num(body.deliveryLng);
  if (topLat != null && topLng != null) {
    return { lat: topLat, lng: topLng };
  }

  const billing = pickCoords(body.billing);
  if (billing) {
    return billing;
  }

  const ship = pickCoords(body['shippingAddress']);
  if (ship) {
    return ship;
  }

  const addr = pickCoords(body['address']);
  if (addr) {
    return addr;
  }

  const geo = pickCoords(body['geo']);
  if (geo) {
    return geo;
  }

  return users.getLastKnownCoords(firebaseUid);
}
