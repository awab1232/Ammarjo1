/**
 * Logical domains for strangler / future service extraction.
 * `search` includes catalog + Algolia product concerns in this monolith layout.
 */
export enum DomainId {
  Orders = 'orders',
  Search = 'search',
  Events = 'events',
  Identity = 'identity',
  Gateway = 'gateway',
  Platform = 'platform',
}

export type DomainKey = DomainId | 'unknown';
