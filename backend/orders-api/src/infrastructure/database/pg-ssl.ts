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

function normalizeConnectionString(connectionString: string): string {
  const raw = connectionString.trim();
  if (!raw) return raw;
  try {
    const u = new URL(raw);
    // Prevent pg/pg-connection-string SSL mode params from overriding explicit
    // `{ ssl: { rejectUnauthorized: false } }` in code.
    u.searchParams.delete('sslmode');
    u.searchParams.delete('sslcert');
    u.searchParams.delete('sslkey');
    u.searchParams.delete('sslrootcert');
    u.searchParams.delete('sslcrl');
    u.searchParams.delete('requiressl');
    return u.toString();
  } catch {
    return raw;
  }
}

export function buildPgPoolConfig(
  connectionString: string,
  overrides: Omit<PoolConfig, 'connectionString' | 'ssl'> = {},
): PoolConfig {
  const normalized = normalizeConnectionString(connectionString);
  const base: PoolConfig = {
    connectionString: normalized,
    ...overrides,
  };
  if (!shouldEnableSsl(normalized)) {
    return base;
  }
  logSslEnabled();
  return {
    ...base,
    ssl: { rejectUnauthorized: false },
  };
}

export function buildPgClientConfig(connectionString: string): ClientConfig {
  const normalized = normalizeConnectionString(connectionString);
  if (!shouldEnableSsl(normalized)) {
    return { connectionString: normalized };
  }
  logSslEnabled();
  return {
    connectionString: normalized,
    ssl: { rejectUnauthorized: false },
  };
}

