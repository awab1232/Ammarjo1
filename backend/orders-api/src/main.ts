import './security/firestore-killer.marker';
import './build-version';
import { NestFactory } from '@nestjs/core';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import * as Sentry from '@sentry/node';
import { AppModule } from './app.module';
import { enforceProductionSafetyOrThrow, logProductionEnvWarnings } from './config/env.validation';
import { SentryExceptionFilter } from './common/sentry-exception.filter';

function initSentry(): void {
  const dsn = process.env.SENTRY_DSN?.trim();
  if (!dsn) {
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
  console.log('[BUILD-CHECK] New build is running');
  const dbUrl = process.env.DATABASE_URL || '';
  const safeUrl = dbUrl.replace(/:(.*?)@/, ':****@');
  console.log('[DB-CONNECTION]', safeUrl);
  // Deployment invariant: the server MUST always reach `app.listen()` so
  // platform healthchecks (Railway / Docker / k8s) can reach `/health`. Env
  // validation failures are surfaced as loud warnings, not a fatal throw —
  // operators see the issue in logs and fix it, while the container stays up
  // long enough for healthchecks + restart policies to behave sanely.
  try {
    enforceProductionSafetyOrThrow();
  } catch (e) {
    console.error(
      '[bootstrap] FATAL env validation failed — continuing to listen so /health responds. Fix env and redeploy:',
      e instanceof Error ? e.message : String(e),
    );
  }
  try {
    logProductionEnvWarnings();
  } catch {
    /* warnings must never block boot */
  }
  initSentry();

  let app: INestApplication;
  try {
    app = await NestFactory.create(AppModule, { abortOnError: false });
  } catch (e) {
    console.error(
      '[bootstrap] FATAL NestFactory.create failed — exiting with code 1 so the platform restarts the container:',
      e instanceof Error ? e.stack ?? e.message : String(e),
    );
    process.exit(1);
  }
  app.use((req: { method: string; originalUrl?: string; path?: string; firebaseUid?: string }, res: { on: (event: string, cb: () => void) => void; statusCode: number; setHeader: (name: string, value: string) => void; getHeader: (name: string) => unknown }, next: () => void) => {
    // Ensure UTF-8 JSON responses so Arabic text is rendered correctly.
    if (!res.getHeader('Content-Type')) {
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
    }
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
  // Flutter Web + browsers: `origin: '*'` cannot be combined with `credentials: true` (CORS spec).
  // `origin: true` echoes the request `Origin` so cross-origin XHR/fetch works with Authorization.
  app.enableCors({
    origin: true,
    methods: ['GET', 'HEAD', 'PUT', 'PATCH', 'POST', 'DELETE', 'OPTIONS'],
    credentials: true,
    allowedHeaders: ['Content-Type', 'Authorization', 'Accept', 'Accept-Language', 'x-internal-api-key'],
  });
  const globalPrefix = process.env.GLOBAL_PREFIX?.trim() || process.env.API_PREFIX?.trim();
  if (globalPrefix) {
    app.setGlobalPrefix(globalPrefix);
    console.log('Global prefix:', globalPrefix);
  }
  // Railway (and most PaaS platforms) inject PORT at runtime.
  const port = Number(process.env.PORT) || 3000;
  await app.listen(port, '0.0.0.0');
  console.log("Server running on port", port);
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
