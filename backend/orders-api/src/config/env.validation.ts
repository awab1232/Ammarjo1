import { isEventOutboxEnabled } from '../events/event-outbox-config';
import { eventOutboxWorkerDegraded } from '../events/event-outbox-mr.config';

/**
 * Production env sanity checks.
 * Security-critical checks are fail-fast.
 */
export function logProductionEnvWarnings(): void {
  if (process.env.NODE_ENV !== 'production') {
    return;
  }

  const missing: string[] = [];

  const hasDb = !!process.env.DATABASE_URL?.trim();
  if (!hasDb) {
    missing.push('DATABASE_URL');
  }

  if (!process.env.SEARCH_INTERNAL_API_KEY?.trim() && !process.env.INTERNAL_API_KEY?.trim()) {
    missing.push('SEARCH_INTERNAL_API_KEY or INTERNAL_API_KEY');
  }
  if (missing.length === 0) {
    return;
  }

  console.warn(
    `[EnvValidation] Production is missing recommended configuration: ${missing.join(', ')}. ` +
      'Internal and ops routes may be unavailable or misconfigured until set.',
  );
}

function mustBeBooleanEnv(key: string, failures: string[]): void {
  const value = process.env[key]?.trim().toLowerCase();
  if (value == null || value === '') {
    process.env[key] = 'false';
    return;
  }
  if (value !== 'true' && value !== 'false') {
    failures.push(`${key} must be 'true' or 'false'`);
  }
}

export function enforceProductionSafetyOrThrow(): void {
  if (process.env.NODE_ENV !== 'production') {
    return;
  }

  const failures: string[] = [];
  const hasDb = !!process.env.DATABASE_URL?.trim();

  if (!process.env.SEARCH_INTERNAL_API_KEY?.trim() && !process.env.INTERNAL_API_KEY?.trim()) {
    failures.push('SEARCH_INTERNAL_API_KEY or INTERNAL_API_KEY is required in production');
  }
  if (!hasDb) {
    failures.push('DATABASE_URL is required in production');
  }
  mustBeBooleanEnv('USE_BACKEND_STORE_READS', failures);
  mustBeBooleanEnv('USE_BACKEND_PRODUCTS_READS', failures);
  mustBeBooleanEnv('USE_BACKEND_OWNER_WRITES', failures);
  if (isEventOutboxEnabled() && !hasDb) {
    failures.push('Outbox enabled but no database connection configured');
  }
  if (isEventOutboxEnabled() && eventOutboxWorkerDegraded()) {
    failures.push('EVENT_OUTBOX_WORKER_DEGRADED must be false in production');
  }

  if (failures.length === 0) {
    return;
  }

  const message = `[EnvValidationFatal] ${failures.join(' | ')}`;
  if (process.env.ENFORCE_PRODUCTION_ENV_VALIDATION?.trim() === '1') {
    throw new Error(message);
  }

  console.warn(`${message} (non-fatal during boot; set ENFORCE_PRODUCTION_ENV_VALIDATION=1 to fail fast)`);
}
