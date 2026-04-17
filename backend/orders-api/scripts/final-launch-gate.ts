import { Client } from 'pg';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

type GateResult = {
  systemHealthScore: number;
  criticalFailures: string[];
  warnings: string[];
};

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

async function dbReachable(): Promise<boolean> {
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

function printResult(result: GateResult): void {
  console.log(
    JSON.stringify({
      kind: 'final_launch_gate_result',
      ...result,
    }),
  );
}

async function main(): Promise<void> {
  loadStagingEnvIfPresent();
  const criticalFailures: string[] = [];
  const warnings: string[] = [];
  let score = 100;

  if (!truthyEnv('RBAC_ENABLED')) {
    criticalFailures.push('RBAC_ENABLED is not true');
    score -= 20;
  }
  if (!truthyEnv('TENANT_ENFORCEMENT_ENABLED')) {
    criticalFailures.push('TENANT_ENFORCEMENT_ENABLED is not true');
    score -= 20;
  }
  if (!truthyEnv('ENABLE_API_GATEWAY_ENFORCEMENT')) {
    criticalFailures.push('ENABLE_API_GATEWAY_ENFORCEMENT is not true');
    score -= 15;
  }
  if (!process.env.SEARCH_INTERNAL_API_KEY?.trim()) {
    criticalFailures.push('SEARCH_INTERNAL_API_KEY is missing');
    score -= 15;
  }
  if (truthyEnv('EVENT_OUTBOX_WORKER_DEGRADED')) {
    criticalFailures.push('EVENT_OUTBOX_WORKER_DEGRADED is true');
    score -= 15;
  }

  const hasDb = await dbReachable();
  if (!hasDb) {
    criticalFailures.push('Database is not reachable');
    score -= 20;
  }

  const flutterBaseUrl = process.env.BACKEND_ORDERS_BASE_URL?.trim();
  if (!flutterBaseUrl) {
    criticalFailures.push('BACKEND_ORDERS_BASE_URL is missing for Flutter integration');
    score -= 20;
  }

  if (!truthyEnv('USE_BACKEND_STORE_READS')) {
    warnings.push('USE_BACKEND_STORE_READS is not true');
    score -= 5;
  }
  if (!truthyEnv('USE_BACKEND_PRODUCTS_READS')) {
    warnings.push('USE_BACKEND_PRODUCTS_READS is not true');
    score -= 5;
  }

  if (score < 0) score = 0;

  const result: GateResult = {
    systemHealthScore: score,
    criticalFailures,
    warnings,
  };
  printResult(result);

  if (criticalFailures.length > 0 || score < 90) {
    console.log('❌ DEPLOYMENT BLOCKED');
    process.exit(1);
  }

  console.log('🚀 SYSTEM READY FOR PRODUCTION DEPLOYMENT');
}

void main();
