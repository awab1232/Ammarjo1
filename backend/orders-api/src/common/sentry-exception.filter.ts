import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import * as Sentry from '@sentry/node';

function sanitizeObject(value: unknown): unknown {
  if (value == null) return value;
  if (Array.isArray(value)) return value.map((v) => sanitizeObject(v));
  if (typeof value !== 'object') return value;
  const blocked = new Set([
    'password',
    'passwd',
    'token',
    'authorization',
    'accessToken',
    'refreshToken',
    'idToken',
    'apiKey',
    'secret',
  ]);
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
    if (blocked.has(k)) {
      out[k] = '[REDACTED]';
      continue;
    }
    out[k] = sanitizeObject(v);
  }
  return out;
}

@Catch()
export class SentryExceptionFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const req = ctx.getRequest<Request & { firebaseUid?: string }>();
    const res = ctx.getResponse<Response>();

    try {
      Sentry.withScope((scope) => {
        scope.setTag('layer', 'nestjs_exception_filter');
        scope.setContext('request', {
          method: req?.method,
          path: req?.path,
          body: sanitizeObject(req?.body),
        });
        if (req?.firebaseUid) {
          scope.setUser({ id: req.firebaseUid });
        }
        Sentry.captureException(exception);
      });
    } catch (e) {
      console.error(
        JSON.stringify({
          kind: 'sentry_capture_failed',
          error: e instanceof Error ? e.message : String(e),
        }),
      );
    }

    if (exception instanceof HttpException) {
      res.status(exception.getStatus()).json(exception.getResponse());
      return;
    }
    res.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
      statusCode: HttpStatus.INTERNAL_SERVER_ERROR,
      message: 'Internal server error',
    });
  }
}

