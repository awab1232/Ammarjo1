import { Injectable } from '@nestjs/common';
import type { IUserService } from '../architecture/contracts/i-user.service';
import { DomainId } from '../architecture/domain-id';
import { emptyTenantContextSnapshot, type TenantContextSnapshot } from './tenant-context.types';
import { getTenantContext } from './tenant-context.storage';

@Injectable()
export class TenantContextService implements IUserService {
  readonly domainId = DomainId.Identity;

  /** Safe snapshot (never null). */
  getSnapshot(): TenantContextSnapshot {
    return getTenantContext() ?? emptyTenantContextSnapshot();
  }
}
