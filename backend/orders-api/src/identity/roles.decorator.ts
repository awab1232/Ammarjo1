import { SetMetadata } from '@nestjs/common';

export const ROLE_GUARD_KEY = 'role_guard_roles';

export function Roles(...roles: string[]) {
  return SetMetadata(ROLE_GUARD_KEY, roles.map((r) => String(r).trim().toLowerCase()).filter(Boolean));
}

