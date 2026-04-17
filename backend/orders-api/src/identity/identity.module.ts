import { Global, Module } from '@nestjs/common';
import { UsersModule } from '../users/users.module';
import { AccessControlService } from './access-control.service';
import { RbacGuard } from './rbac.guard';
import { TenantContextGuard } from './tenant-context.guard';
import { TenantContextService } from './tenant-context.service';

@Global()
@Module({
  imports: [UsersModule],
  providers: [TenantContextService, TenantContextGuard, RbacGuard, AccessControlService],
  exports: [TenantContextService, RbacGuard, TenantContextGuard, AccessControlService],
})
export class IdentityModule {}
