import { Injectable } from '@nestjs/common';

export type RetryPolicyOptions = {
  maxRetries: number;
  baseDelayMs: number;
  exponential?: boolean;
  /** 0–1 fraction of delay added as random jitter. */
  jitterRatio?: number;
};

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

function jitter(delay: number, jitterRatio: number): number {
  if (jitterRatio <= 0) {
    return delay;
  }
  const j = delay * jitterRatio;
  return delay + Math.floor((Math.random() * 2 - 1) * j);
}

/**
 * Shared retry helper for optional use (outbox worker, DLQ replay, search sync).
 * Does not change any behavior until explicitly wired by callers.
 */
@Injectable()
export class RetryPolicyService {
  async executeWithRetry<T>(fn: () => Promise<T>, options: RetryPolicyOptions): Promise<T> {
    const exp = options.exponential === true;
    const jr = Math.min(1, Math.max(0, options.jitterRatio ?? 0));
    let delay = Math.max(0, options.baseDelayMs);
    const maxRetries = Math.max(0, Math.floor(options.maxRetries));
    for (let attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await fn();
      } catch (e) {
        if (attempt >= maxRetries) {
          throw e;
        }
        const wait = jitter(delay, jr);
        await sleep(wait);
        if (exp) {
          delay = Math.min(delay * 2, 120_000);
        }
      }
    }
    throw new Error('retry_policy_unreachable');
  }
}
