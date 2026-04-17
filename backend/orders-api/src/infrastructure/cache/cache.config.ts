/** Response cache for safe GET acceleration. Default off. */
export function isResponseCacheEnabled(): boolean {
  return process.env.CACHE_ENABLED?.trim() === '1';
}

/** TTL clamped to 30–120 seconds per product guidance. */
export function responseCacheTtlSeconds(): number {
  const raw = process.env.CACHE_TTL_SECONDS?.trim();
  const n = raw != null && raw !== '' ? Number.parseInt(raw, 10) : 60;
  if (!Number.isFinite(n)) {
    return 60;
  }
  return Math.min(120, Math.max(30, n));
}
