import './security/firestore-killer.marker';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import * as Sentry from '@sentry/node';
import { AppModule } from './app.module';
import { enforceProductionSafetyOrThrow, logProductionEnvWarnings } from './config/env.validation';
import { SentryExceptionFilter } from './common/sentry-exception.filter';

function initSentry(): void {
  const dsn = process.env.SENTRY_DSN?.trim();
  if (!dsn) {
    console.warn('[Sentry] WARNING: SENTRY_DSN is empty, monitoring disabled.');
    return;
  }
  const env = (process.env.NODE_ENV?.trim() || 'development').toLowerCase();
  const tracesSampleRate = env === 'production' ? 0.1 : 1.0;
  try {
    Sentry.init({
      dsn: process.env.SENTRY_DSN,
      environment: env,
      tracesSampleRate,
      beforeSend(event) {
        const req = event.request;
        if (req?.headers) {
          const headers = { ...req.headers };
          for (const key of Object.keys(headers)) {
            if (['authorization', 'cookie', 'x-api-key'].includes(key.toLowerCase())) {
              headers[key] = '[REDACTED]';
            }
          }
          event.request = { ...req, headers };
        }
        return event;
      },
    });
  } catch (e) {
    console.error(
      JSON.stringify({
        kind: 'sentry_capture_failed',
        error: e instanceof Error ? e.message : String(e),
      }),
    );
  }
}

async function bootstrap() {
  enforceProductionSafetyOrThrow();
  logProductionEnvWarnings();
  initSentry();
  const app = await NestFactory.create(AppModule);
  app.use((req: { method: string; originalUrl?: string; path?: string; firebaseUid?: string }, res: { on: (event: string, cb: () => void) => void; statusCode: number }, next: () => void) => {
    const startedAt = Date.now();
    const span = (Sentry as unknown as {
      startInactiveSpan?: (ctx: { name: string; op: string }) => { end: () => void } | undefined;
    }).startInactiveSpan?.({
      name: `${req.method} ${req.originalUrl ?? req.path ?? ''}`,
      op: 'http.server',
    });
    res.on('finish', () => {
      const durationMs = Date.now() - startedAt;
      try {
        Sentry.addBreadcrumb({
          category: 'http',
          level: 'info',
          message: `${req.method} ${req.originalUrl ?? req.path ?? ''}`,
          data: {
            method: req.method,
            path: req.originalUrl ?? req.path ?? '',
            statusCode: res.statusCode,
            durationMs,
            userId: req.firebaseUid ?? null,
          },
        });
      } catch (e) {
        console.error(
          JSON.stringify({
            kind: 'sentry_capture_failed',
            error: e instanceof Error ? e.message : String(e),
          }),
        );
      }
      try {
        span?.end();
      } catch {}
    });
    next();
  });
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: false,
      transform: true,
    }),
  );
  app.useGlobalFilters(new SentryExceptionFilter());
  app.enableCors({ origin: true });
  const port = Number(process.env.PORT) || 8080;
  await app.listen(port, '0.0.0.0');
  console.log(
    JSON.stringify({
      ts: new Date().toISOString(),
      kind: 'server_listen',
      port,
      nodeEnv: process.env.NODE_ENV ?? 'development',
    }),
  );

  process.on('unhandledRejection', (reason) => {
    try {
      Sentry.captureException(reason);
    } catch (e) {
      console.error(
        JSON.stringify({
          kind: 'sentry_capture_failed',
          error: e instanceof Error ? e.message : String(e),
        }),
      );
    }
  });
  process.on('uncaughtException', (err) => {
    try {
      Sentry.captureException(err);
    } catch (e) {
      console.error(
        JSON.stringify({
          kind: 'sentry_capture_failed',
          error: e instanceof Error ? e.message : String(e),
        }),
      );
    }
  });

  if (process.env.SENTRY_TEST_BACKEND?.trim() === '1') {
    setTimeout(() => {
      throw new Error('SENTRY_TEST_BACKEND');
    }, 1000);
  }
}

bootstrap();
