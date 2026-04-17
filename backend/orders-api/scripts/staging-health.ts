import { Client } from 'pg';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function truthyEnv(name: string): boolean {
  const v = process.env[name]?.trim().toLowerCase();
  return v === '1' || v === 'true';
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
    const v = t.slice(idx + 1).trim();
    if (!process.env[k]) process.env[k] = v;
  }
}

async function dbHealthy(): Promise<boolean> {
  const connectionString = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
  if (!connectionString) return false;
  const client = new Client({ connectionString });
  try {
    await client.connect();
    await client.query('SELECT 1');
    return true;
  } catch {
    return false;
  } finally {
    await client.end().catch(() => undefined);
  }
}

async function apiHealthy(baseUrlRaw?: string): Promise<boolean> {
  const base = (baseUrlRaw?.trim() || 'http://localhost:8080').replace(/\/+$/, '');
  try {
    const r = await fetch(`${base}/health`);
    return r.status >= 200 && r.status < 500;
  } catch {
    return false;
  }
}

async function main(): Promise<void> {
  loadStagingEnvIfPresent();
  let score = 100;
  const failures: string[] = [];
  const warnings: string[] = [];

  const db = await dbHealthy();
  if (!db) {
    failures.push('DB health failed');
    score -= 30;
  }

  const api = await apiHealthy(process.env.BASE_URL);
  if (!api) {
    failures.push('API health failed');
    score -= 25;
  }

  const outboxActive = !truthyEnv('EVENT_OUTBOX_WORKER_DEGRADED');
  if (!outboxActive) {
    failures.push('Outbox health failed (worker degraded)');
    score -= 20;
  }

  if (!truthyEnv('RBAC_ENABLED')) {
    failures.push('RBAC not active');
    score -= 15;
  }
  if (!truthyEnv('TENANT_ENFORCEMENT_ENABLED')) {
    failures.push('Tenant enforcement not active');
    score -= 15;
  }
  if (!truthyEnv('ENABLE_API_GATEWAY_ENFORCEMENT')) {
    warnings.push('API gateway enforcement disabled');
    score -= 5;
  }

  if (score < 0) score = 0;
  console.log(
    JSON.stringify({
      kind: 'staging_health',
      dbHealth: db,
      apiHealth: api,
      outboxHealth: outboxActive,
      rbacActive: truthyEnv('RBAC_ENABLED'),
      tenantEnforcementActive: truthyEnv('TENANT_ENFORCEMENT_ENABLED'),
      stagingScore: score,
      failures,
      warnings,
    }),
  );

  if (score < 90) {
    console.log('❌ STAGING NOT READY');
    process.exit(1);
  }
  console.log('🚀 STAGING READY');
}

void main();
