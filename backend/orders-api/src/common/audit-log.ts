import * as Sentry from '@sentry/node';

/** Attach audit context to Sentry (no extra stdout). */
export function auditSentryBreadcrumb(
  kind: string,
  payload: Record<string, unknown>,
  level: 'info' | 'warning' = 'info',
): void {
  try {
    Sentry.addBreadcrumb({
      category: 'audit',
      message: kind,
      level,
      data: payload,
    });
  } catch {
    /* Sentry optional */
  }
}

/**
 * Single-line JSON audit logs (stdout) + Sentry breadcrumbs for critical production signals.
 * Never log secrets, tokens, or raw Authorization headers.
 */
export function logAuditJson(
  kind:
    | 'order_created'
    | 'order_status_updated'
    | 'login_attempt'
    | 'admin_action'
    | 'audit',
  payload: Record<string, unknown>,
): void {
  const line = JSON.stringify({
    ts: new Date().toISOString(),
    kind,
    ...payload,
  });
  if (kind === 'login_attempt' || kind === 'admin_action') {
    console.warn(line);
  } else {
    console.log(line);
  }
  auditSentryBreadcrumb(kind, payload, kind === 'login_attempt' ? 'warning' : 'info');
}
