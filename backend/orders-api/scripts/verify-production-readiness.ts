import { Client } from 'pg';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { buildPgClientConfig } from '../src/infrastructure/database/pg-ssl';

type Check = {
  name: string;
  ok: boolean;
  reason?: string;
};

function truthyEnv(name: string): boolean {
  const v = process.env[name]?.trim().toLowerCase();
  return v === '1' || v === 'true';
}

function logJson(kind: string, payload: Record<string, unknown>): void {
  console.log(JSON.stringify({ kind, ...payload }));
}

function loadStagingEnvIfPresent(): void {
  const p = resolve(process.cwd(), '.env.staging');
  if (!existsSync(p)) return;
  const raw = readFileSync(p, 'utf8');
  for (const line of raw.split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const idx = t.indexOf('=');
    if (idx <= 0) continue;
    const k = t.slice(0, idx).trim();
    let v = t.slice(idx + 1).trim();
    if (
      (v.startsWith('"') && v.endsWith('"')) ||
      (v.startsWith("'") && v.endsWith("'"))
    ) {
      v = v.slice(1, -1).trim();
    }
    if (!process.env[k]) process.env[k] = v;
  }
}

async function verifyDb(): Promise<Check> {
  const connectionString = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
  if (!connectionString) {
    return { name: 'database_connection', ok: false, reason: 'DATABASE_URL/ORDERS_DATABASE_URL missing' };
  }
  const client = new Client(buildPgClientConfig(connectionString));
  try {
    await client.connect();
    await client.query('SELECT 1');
    return { name: 'database_connection', ok: true };
  } catch (e) {
    return {
      name: 'database_connection',
      ok: false,
      reason: e instanceof Error ? e.message : String(e),
    };
  } finally {
    await client.end().catch(() => undefined);
  }
}

async function verifyOutboxWorker(): Promise<Check> {
  const degraded = truthyEnv('EVENT_OUTBOX_WORKER_DEGRADED');
  if (degraded) {
    return { name: 'outbox_worker_not_degraded', ok: false, reason: 'EVENT_OUTBOX_WORKER_DEGRADED=true' };
  }
  // Runtime liveness can also be observed by poll logs/metrics in deployment.
  return { name: 'outbox_worker_not_degraded', ok: true };
}

async function main(): Promise<void> {
  loadStagingEnvIfPresent();
  const checks: Check[] = [];
  checks.push(await verifyDb());
  checks.push(await verifyOutboxWorker());
  checks.push({
    name: 'rbac_enabled',
    ok: truthyEnv('RBAC_ENABLED'),
    reason: truthyEnv('RBAC_ENABLED') ? undefined : 'RBAC_ENABLED must be true',
  });
  checks.push({
    name: 'tenant_enforcement_enabled',
    ok: truthyEnv('TENANT_ENFORCEMENT_ENABLED'),
    reason: truthyEnv('TENANT_ENFORCEMENT_ENABLED') ? undefined : 'TENANT_ENFORCEMENT_ENABLED must be true',
  });
  checks.push({
    name: 'api_gateway_enforcement_enabled',
    ok: truthyEnv('ENABLE_API_GATEWAY_ENFORCEMENT'),
    reason: truthyEnv('ENABLE_API_GATEWAY_ENFORCEMENT')
      ? undefined
      : 'ENABLE_API_GATEWAY_ENFORCEMENT must be true',
  });

  const failed = checks.filter((c) => !c.ok);
  if (failed.length > 0) {
    logJson('production_readiness_failed', {
      checks,
      failedCount: failed.length,
      failed,
    });
    process.exit(1);
  }

  logJson('production_readiness_verified', {
    checks,
    failedCount: 0,
  });
}

void main();
