import type { DomainId } from '../domain-id';

/** Catalog / product read surface (search module hosts PG catalog in this repo). */
export interface IProductService {
  readonly domainId: DomainId;
  isCatalogEnabled(): boolean;
}
