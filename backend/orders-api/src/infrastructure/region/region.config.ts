/**
 * Region routing is opt-in. When REGION_ROUTING_ENABLED is not "1", the runtime uses a static
 * default region and skips header/tenant routing logic.
 */
export function isRegionRoutingEnabled(): boolean {
  return process.env.REGION_ROUTING_ENABLED?.trim() === '1';
}

/** Canonical region id for this process (deployment). */
export function defaultRegionId(): string {
  const r =
    process.env.DEFAULT_REGION?.trim() ||
    process.env.REGION?.trim() ||
    process.env.EVENT_OUTBOX_REGION?.trim();
  return r || 'eu-west-1';
}
