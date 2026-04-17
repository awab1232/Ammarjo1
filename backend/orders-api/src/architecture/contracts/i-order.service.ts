import type { DomainId } from '../domain-id';

/**
 * Orders domain facade — cross-domain callers must use this (or events), not OrdersPgService directly.
 */
export interface IOrderService {
  readonly domainId: DomainId;
  isOrderStorageConfigured(): boolean;
  /** Health / readiness without exposing PG types. */
  pingOrderStorage(): Promise<{ ok: boolean; error?: string }>;
}
