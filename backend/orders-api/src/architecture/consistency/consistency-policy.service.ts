import { Injectable, Logger } from '@nestjs/common';
import {
  ConsistencyContractService,
  type ConsistencyDomain,
} from './consistency-contract.service';
import { isConsistencyDebugEnabled, shouldLogConsistencyViolations } from './consistency.config';

export type ReadStrategy = {
  primary: string;
  fallback?: string;
};

export type WriteStrategy = {
  primary: string;
  mirror?: string[];
};

/**
 * Read/write routing hints derived from the consistency contract (for logs and future hardening).
 */
@Injectable()
export class ConsistencyPolicyService {
  private readonly logger = new Logger(ConsistencyPolicyService.name);

  constructor(private readonly contract: ConsistencyContractService) {}

  resolveReadStrategy(domain: ConsistencyDomain, _context?: Record<string, unknown>): ReadStrategy {
    switch (domain) {
      case 'orders':
        return { primary: 'postgres', fallback: 'firebase' };
      case 'search':
        return { primary: 'algolia' };
      case 'cache':
        return { primary: 'redis', fallback: 'postgres' };
      case 'firebase':
        return { primary: 'mirror', fallback: 'postgres' };
      default:
        return { primary: 'unknown' };
    }
  }

  resolveWriteStrategy(domain: ConsistencyDomain): WriteStrategy {
    switch (domain) {
      case 'orders':
        return { primary: 'postgres', mirror: ['firebase'] };
      case 'search':
        return { primary: 'algolia' };
      case 'cache':
        return { primary: 'redis' };
      case 'firebase':
        return { primary: 'mirror' };
      default:
        return { primary: 'unknown' };
    }
  }

  /** Log when a read is served from a non-authoritative source (e.g. Firestore fallback). */
  logNonAuthoritativeRead(domain: ConsistencyDomain, source: string, operation: string): void {
    if (!shouldLogConsistencyViolations()) {
      return;
    }
    if (this.contract.isAuthoritative(domain, source)) {
      return;
    }
    if (!this.contract.shouldReadFrom(domain, source)) {
      this.logger.warn(
        `[Consistency] invalid read path: domain=${domain} source=${source} op=${operation}`,
      );
      return;
    }
    if (isConsistencyDebugEnabled()) {
      this.logger.warn(
        `[Consistency] read from non-authoritative source: domain=${domain} source=${source} op=${operation}`,
      );
    }
  }

  /** Log when a write targets something other than the policy primary (mirror/async OK — log for visibility). */
  logNonPrimaryWrite(domain: ConsistencyDomain, source: string, operation: string): void {
    if (!shouldLogConsistencyViolations()) {
      return;
    }
    const w = this.resolveWriteStrategy(domain);
    const primary = w.primary.toLowerCase();
    const s = source.trim().toLowerCase();
    if (s === primary || s === 'pg' && primary === 'postgres') {
      return;
    }
    const mirrored = (w.mirror ?? []).some((m) => m.toLowerCase() === s);
    if (mirrored) {
      if (isConsistencyDebugEnabled()) {
        this.logger.warn(
          `[Consistency] mirror write (expected for ${domain}): source=${source} op=${operation}`,
        );
      }
      return;
    }
    this.logger.warn(
      `[Consistency] write to non-primary source: domain=${domain} source=${source} op=${operation}`,
    );
  }

  /** Orders API: persisted writes must go to PostgreSQL. */
  validateOrdersWriteTargetsPostgres(pgWriteOccurred: boolean, operation: string): void {
    if (!shouldLogConsistencyViolations()) {
      return;
    }
    if (pgWriteOccurred) {
      return;
    }
    this.logger.warn(
      `[Consistency] orders write did not persist to postgres (contract expects postgres primary) op=${operation}`,
    );
  }

  /** Product search reads must use Algolia as primary (contract). Debug visibility only. */
  logSearchReadAuthoritative(operation: string): void {
    if (!isConsistencyDebugEnabled()) {
      return;
    }
    if (!this.contract.shouldReadFrom('search', 'algolia')) {
      this.logger.warn(`[Consistency] search read path violates contract op=${operation}`);
      return;
    }
    this.logger.debug(`[Consistency] search read via algolia (authoritative) op=${operation}`);
  }

  /** On cache miss, document policy fallback (Redis → application/postgres truth). */
  logCacheMiss(keyHint: string): void {
    if (!isConsistencyDebugEnabled()) {
      return;
    }
    const st = this.resolveReadStrategy('cache');
    this.logger.warn(
      `[Consistency] cache miss; reload should use policy fallback=${st.fallback ?? 'n/a'} key=${keyHint.slice(0, 200)}`,
    );
  }
}
