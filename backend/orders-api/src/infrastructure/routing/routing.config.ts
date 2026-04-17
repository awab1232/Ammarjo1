export type NormalizedCountryCode = 'JO' | 'EG' | 'UNKNOWN';

/**
 * Multi-country data routing (Jordan + Egypt rollout). Off by default — no behavior change.
 */
export function isMultiRegionRoutingEnabled(): boolean {
  return process.env.ENABLE_MULTI_REGION?.trim() === '1';
}

/** ISO-style default when no header/claim (product: Jordan first). */
export function defaultCountryCode(): 'JO' | 'EG' {
  const r = process.env.DEFAULT_REGION?.trim().toUpperCase();
  if (r === 'EG' || r === 'EGY' || r === 'EGYPT') {
    return 'EG';
  }
  return 'JO';
}

export function normalizeCountryCode(raw: string | undefined | null): NormalizedCountryCode {
  const u = raw?.trim().toUpperCase();
  if (!u) {
    return 'UNKNOWN';
  }
  if (u === 'JO' || u === 'JOR' || u === 'JORDAN') {
    return 'JO';
  }
  if (u === 'EG' || u === 'EGY' || u === 'EGYPT') {
    return 'EG';
  }
  return 'UNKNOWN';
}
