import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { AppModule } from '../src/app.module';
import { StoreBuilderModule } from '../src/store-builder/store-builder.module';
import { ServiceRequestsModule } from '../src/service-requests/service-requests.module';
import { RatingsModule } from '../src/ratings/ratings.module';
import { WholesaleModule } from '../src/wholesale/wholesale.module';
import { EventsCoreModule } from '../src/events/events-core.module';

function logJson(kind: string, payload: Record<string, unknown>): void {
  console.log(JSON.stringify({ kind, ...payload }));
}

function parseEnvFile(path: string): Record<string, string> {
  const out: Record<string, string> = {};
  const raw = readFileSync(path, 'utf8');
  for (const line of raw.split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const idx = t.indexOf('=');
    if (idx <= 0) continue;
    const k = t.slice(0, idx).trim();
    const v = t.slice(idx + 1).trim();
    out[k] = v;
  }
  return out;
}

function loadStagingEnv(): void {
  const envPath = resolve(process.cwd(), '.env.staging');
  if (!existsSync(envPath)) {
    throw new Error(`Missing staging env file: ${envPath}`);
  }
  const parsed = parseEnvFile(envPath);
  for (const [k, v] of Object.entries(parsed)) {
    if (!process.env[k]) process.env[k] = v;
  }
}

function requiredEnvOrThrow(keys: string[]): void {
  const missing = keys.filter((k) => !(process.env[k]?.trim()));
  if (missing.length > 0) {
    throw new Error(`Missing required staging env vars: ${missing.join(', ')}`);
  }
}

async function main(): Promise<void> {
  loadStagingEnv();
  requiredEnvOrThrow([
    'DATABASE_URL',
    'RBAC_ENABLED',
    'TENANT_ENFORCEMENT_ENABLED',
    'ENABLE_API_GATEWAY_ENFORCEMENT',
    'SEARCH_INTERNAL_API_KEY',
  ]);

  logJson('staging_bootstrap_starting', {
    nodeEnv: process.env.NODE_ENV ?? 'unset',
  });

  if ((process.env.EVENT_OUTBOX_WORKER_DEGRADED ?? '').trim().toLowerCase() === 'true') {
    logJson('staging_outbox_blocked', { reason: 'EVENT_OUTBOX_WORKER_DEGRADED=true' });
    process.exit(1);
  } else {
    logJson('staging_outbox_active', {});
  }

  const app = await NestFactory.create(AppModule);
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: false,
      transform: true,
    }),
  );
  app.enableCors({ origin: true });

  const loadedModules: string[] = [];
  app.select(AppModule);
  loadedModules.push('AppModule');
  app.select(StoreBuilderModule);
  loadedModules.push('StoreBuilderModule');
  app.select(ServiceRequestsModule);
  loadedModules.push('ServiceRequestsModule');
  app.select(RatingsModule);
  loadedModules.push('RatingsModule');
  app.select(WholesaleModule);
  loadedModules.push('WholesaleModule');
  app.select(EventsCoreModule);
  loadedModules.push('EventsModule');

  const port = Number(process.env.PORT) || 8080;
  await app.listen(port, '0.0.0.0');
  logJson('staging_bootstrap_completed', {
    port,
    loadedModules,
  });
}

void main();
