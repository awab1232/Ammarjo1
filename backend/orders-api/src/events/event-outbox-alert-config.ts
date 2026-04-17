/** Set to `0` to disable outbound alert delivery (checks still skipped). */
export function isEventAlertingEnabled(): boolean {
  return process.env.EVENT_ALERT_ENABLED?.trim() !== '0';
}

export function eventAlertWebhookUrl(): string | undefined {
  const u = process.env.EVENT_ALERT_WEBHOOK_URL?.trim();
  return u || undefined;
}

export function eventAlertSlackWebhook(): string | undefined {
  const u = process.env.EVENT_ALERT_SLACK_WEBHOOK?.trim();
  return u || undefined;
}

/** Optional generic HTTP endpoint (e.g. email provider API); receives same JSON as webhook. */
export function eventAlertEmailUrl(): string | undefined {
  const u = process.env.EVENT_ALERT_EMAIL_URL?.trim();
  return u || undefined;
}

/** Count of rows entering `failed` in the sliding window before alerting. */
export function eventAlertFailureThreshold(): number {
  const n = Number.parseInt(process.env.EVENT_ALERT_FAILURE_THRESHOLD?.trim() ?? '5', 10);
  return Number.isFinite(n) && n >= 1 ? n : 5;
}

/** Sliding window for failure-rate and related counts (ms). */
export function eventAlertWindowMs(): number {
  const n = Number.parseInt(process.env.EVENT_ALERT_WINDOW_MS?.trim() ?? '900000', 10);
  return Number.isFinite(n) && n >= 60_000 ? n : 900_000;
}

/** Minimum retry_count to count toward retry-explosion. */
export function eventAlertRetryExplosionMin(): number {
  const n = Number.parseInt(process.env.EVENT_ALERT_RETRY_EXPLOSION_MIN?.trim() ?? '5', 10);
  return Number.isFinite(n) && n >= 1 ? n : 5;
}

/** Alert when this many rows have retry_count >= explosion min. */
export function eventAlertRetryExplosionThreshold(): number {
  const n = Number.parseInt(process.env.EVENT_ALERT_RETRY_EXPLOSION_THRESHOLD?.trim() ?? '10', 10);
  return Number.isFinite(n) && n >= 1 ? n : 10;
}

/** No successful worker progress for this long while backlog exists (ms). */
export function eventAlertStuckMs(): number {
  const n = Number.parseInt(process.env.EVENT_ALERT_STUCK_MS?.trim() ?? '600000', 10);
  return Number.isFinite(n) && n >= 60_000 ? n : 600_000;
}

/** Minimum backlog (pending+processing) to consider stuck. */
export function eventAlertStuckMinBacklog(): number {
  const n = Number.parseInt(process.env.EVENT_ALERT_STUCK_MIN_BACKLOG?.trim() ?? '1', 10);
  return Number.isFinite(n) && n >= 1 ? n : 1;
}

/** Alert when total dead-letter count increases by at least this vs last check. */
export function eventAlertDeadLetterDelta(): number {
  const n = Number.parseInt(process.env.EVENT_ALERT_DEAD_LETTER_DELTA?.trim() ?? '1', 10);
  return Number.isFinite(n) && n >= 1 ? n : 1;
}

/** Minimum ms between two alerts with the same dedupe key. */
export function eventAlertMinIntervalMs(): number {
  const n = Number.parseInt(process.env.EVENT_ALERT_MIN_INTERVAL_MS?.trim() ?? '120000', 10);
  return Number.isFinite(n) && n >= 10_000 ? n : 120_000;
}

export function hasEventAlertDestinations(): boolean {
  return Boolean(
    eventAlertWebhookUrl() || eventAlertSlackWebhook() || eventAlertEmailUrl(),
  );
}
