import { Injectable, Logger } from '@nestjs/common';

export class CircuitOpenError extends Error {
  constructor(readonly key: string) {
    super(`circuit_open:${key}`);
    this.name = 'CircuitOpenError';
  }
}

type Entry = {
  state: 'CLOSED' | 'OPEN' | 'HALF_OPEN';
  failures: number;
  openedAt: number;
};

export type CircuitBreakerOptions = {
  failureThreshold?: number;
  openMs?: number;
};

const DEFAULTS: Required<CircuitBreakerOptions> = {
  failureThreshold: 5,
  openMs: 30_000,
};

/**
 * Per-key circuit breaker for optional use (db / redis / external). Not applied globally.
 */
@Injectable()
export class CircuitBreakerService {
  private readonly logger = new Logger(CircuitBreakerService.name);
  private readonly circuits = new Map<string, Entry>();

  async call<T>(key: string, fn: () => Promise<T>, options?: CircuitBreakerOptions): Promise<T> {
    const o = { ...DEFAULTS, ...options };
    let ent = this.circuits.get(key);
    if (!ent) {
      ent = { state: 'CLOSED', failures: 0, openedAt: 0 };
      this.circuits.set(key, ent);
    }
    const now = Date.now();

    if (ent.state === 'OPEN') {
      if (now - ent.openedAt < o.openMs) {
        throw new CircuitOpenError(key);
      }
      ent.state = 'HALF_OPEN';
    }

    try {
      const r = await fn();
      ent.state = 'CLOSED';
      ent.failures = 0;
      return r;
    } catch (e) {
      ent.failures += 1;
      if (ent.state === 'HALF_OPEN' || ent.failures >= o.failureThreshold) {
        ent.state = 'OPEN';
        ent.openedAt = now;
      }
      this.logger.debug(
        `[CircuitBreaker] ${key} failure ${ent.failures}: ${e instanceof Error ? e.message : String(e)}`,
      );
      throw e;
    }
  }

  reset(key: string): void {
    this.circuits.delete(key);
  }
}
