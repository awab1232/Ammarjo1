import * as Sentry from '@sentry/node';

import { auditSentryBreadcrumb } from '../common/audit-log';

/**
 * Deferred logging so request handlers return quickly (stdout work off the hot path).
 */
export type OrderLogEvent =
  | {
      kind: 'order_created';
      userId: string;
      orderId: string;
      validationOk: boolean;
      mismatchCount: number;
      storageCheckOk: boolean;
    }
  | {
      kind: 'validation_detail';
      userId: string;
      orderId: string;
      mismatches: string[];
    }
  | {
      kind: 'error';
      userId?: string;
      orderId?: string;
      message: string;
      stack?: string;
    }
  | {
      kind: 'order_write';
      userId: string;
      orderId: string;
      writeSource: 'backend' | 'firebase';
      /** Firebase mirror runs on the client after this POST when writeSource is backend */
      mirrorStatus: 'client_async';
    }
  | {
      kind: 'order_status_updated';
      orderId: string;
      status: string;
      firebaseUid: string;
    };

function emit(line: string): void {
  setImmediate(() => {
    try {
      console.log(`[orders-api] ${line}`);
    } catch {
      /* ignore */
    }
  });
}

export function logOrderEvent(event: OrderLogEvent): void {
  const ts = new Date().toISOString();
  const base = { ts, ...event };
  emit(JSON.stringify(base));
  if (event.kind === 'order_created') {
    auditSentryBreadcrumb('order_created', {
      userId: event.userId,
      orderId: event.orderId,
      validationOk: event.validationOk,
      mismatchCount: event.mismatchCount,
      storageCheckOk: event.storageCheckOk,
    });
  } else if (event.kind === 'order_status_updated') {
    auditSentryBreadcrumb('order_status_updated', {
      orderId: event.orderId,
      status: event.status,
      firebaseUid: event.firebaseUid,
    });
  }
}

export function logOrderError(err: unknown, ctx?: { userId?: string; orderId?: string }): void {
  const ts = new Date().toISOString();
  const message = err instanceof Error ? err.message : String(err);
  const stack = err instanceof Error ? err.stack : undefined;
  emit(
    JSON.stringify({
      ts,
      kind: 'error',
      userId: ctx?.userId,
      orderId: ctx?.orderId,
      message,
      stack,
    }),
  );
  try {
    Sentry.captureException(err instanceof Error ? err : new Error(message), {
      tags: { domain: 'orders' },
      extra: { userId: ctx?.userId, orderId: ctx?.orderId },
    });
  } catch {
    /* optional */
  }
}
