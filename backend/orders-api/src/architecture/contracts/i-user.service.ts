import type { TenantContextSnapshot } from '../../identity/tenant-context.types';
import type { DomainId } from '../domain-id';

/** Identity / tenant context facade. */
export interface IUserService {
  readonly domainId: DomainId;
  getSnapshot(): TenantContextSnapshot;
}
