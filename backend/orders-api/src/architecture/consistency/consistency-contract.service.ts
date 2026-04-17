import { Injectable, Logger } from '@nestjs/common';

export type ConsistencyDomain = 'orders' | 'search' | 'cache' | 'firebase';

/** Canonical storage / role labels used in policies and logs. */
export type TruthSource = 'postgres' | 'algolia' | 'redis' | 'mirror';

const SOURCE_OF_TRUTH: Record<ConsistencyDomain, TruthSource> = {
  orders: 'postgres',
  search: 'algolia',
  cache: 'redis',
  firebase: 'mirror',
};

function norm(s: string): string {
  return s.trim().toLowerCase();
}

/**
 * Central source-of-truth map for distributed data (orders, search, cache, Firebase mirror).
 * Additive — callers opt in via {@link ConsistencyPolicyService} and env flags.
 */
@Injectable()
export class ConsistencyContractService {
  private readonly logger = new Logger(ConsistencyContractService.name);

  getSourceOfTruth(domain: ConsistencyDomain): TruthSource {
    return SOURCE_OF_TRUTH[domain];
  }

  /** True if `source` is the authoritative store for business truth for this domain. */
  isAuthoritative(domain: ConsistencyDomain, source: string): boolean {
    const s = norm(source);
    switch (domain) {
      case 'orders':
        return s === 'postgres' || s === 'pg';
      case 'search':
        return s === 'algolia';
      case 'cache':
        return s === 'redis';
      case 'firebase':
        return s === 'mirror' || s === 'firestore' || s === 'firebase';
      default:
        return false;
    }
  }

  /**
   * Allowed read path for the domain (includes documented fallbacks, e.g. Firestore legacy reads for orders).
   */
  shouldReadFrom(domain: ConsistencyDomain, source: string): boolean {
    const s = norm(source);
    switch (domain) {
      case 'orders':
        return s === 'postgres' || s === 'pg' || s === 'firestore' || s === 'firebase';
      case 'search':
        return s === 'algolia';
      case 'cache':
        return (
          s === 'redis' ||
          s === 'postgres' ||
          s === 'pg' ||
          s === 'application' ||
          s === 'origin'
        );
      case 'firebase':
        return s === 'firestore' || s === 'firebase' || s === 'mirror';
      default:
        return false;
    }
  }

  /**
   * Allowed write target for the domain from the backend’s perspective.
   * Orders: PostgreSQL only; Firebase/Firestore is client mirror, not API primary write.
   */
  shouldWriteTo(domain: ConsistencyDomain, source: string): boolean {
    const s = norm(source);
    switch (domain) {
      case 'orders':
        return s === 'postgres' || s === 'pg';
      case 'search':
        return s === 'algolia';
      case 'cache':
        return s === 'redis';
      case 'firebase':
        return s === 'firestore' || s === 'firebase';
      default:
        return false;
    }
  }

  warnInvalidCombination(domain: ConsistencyDomain, message: string): void {
    this.logger.warn(`[ConsistencyContract] ${domain}: ${message}`);
  }
}
