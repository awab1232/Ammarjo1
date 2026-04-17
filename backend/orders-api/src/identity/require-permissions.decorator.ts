import { SetMetadata } from '@nestjs/common';
import { PERMISSIONS_METADATA_KEY } from './rbac.constants';

/** Require all listed permissions (AND). RBAC is always enforced. */
export const RequirePermissions = (...permissions: string[]) =>
  SetMetadata(PERMISSIONS_METADATA_KEY, permissions);
