import type { ClientConfig, PoolConfig } from 'pg';

let logged = false;

function logSslEnabled(): void {
  if (logged) return;
  logged = true;
  console.log('DB SSL CONFIG ENABLED');
}

function shouldEnableSsl(connectionString: string): boolean {
  if (process.env.PG_SSL_DISABLE?.trim() === '1') {
    return false;
  }
  try {
    const u = new URL(connectionString);
    const host = u.hostname.trim().toLowerCase();
    if (host === 'localhost' || host === '127.0.0.1' || host === '::1') {
      return false;
    }
  } catch {
    // If URL parsing fails, fail closed to SSL enabled.
    return true;
  }
  return true;
}

export function buildPgPoolConfig(
  connectionString: string,
  overrides: Omit<PoolConfig, 'connectionString' | 'ssl'> = {},
): PoolConfig {
  const base: PoolConfig = {
    connectionString,
    ...overrides,
  };
  if (!shouldEnableSsl(connectionString)) {
    return base;
  }
  logSslEnabled();
  return {
    ...base,
    ssl: { rejectUnauthorized: false },
  };
}

export function buildPgClientConfig(connectionString: string): ClientConfig {
  if (!shouldEnableSsl(connectionString)) {
    return { connectionString };
  }
  logSslEnabled();
  return {
    connectionString,
    ssl: { rejectUnauthorized: false },
  };
}

