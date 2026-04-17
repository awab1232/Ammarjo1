export function isRedisInfrastructureEnabled(): boolean {
  const disabled = (process.env.REDIS_ENABLED ?? '').trim().toLowerCase();
  if (disabled === '0' || disabled === 'false') {
    return false;
  }
  return !!getRedisUrl();
}

export function getRedisUrl(): string | undefined {
  const u = process.env.REDIS_URL?.trim();
  return u || undefined;
}
