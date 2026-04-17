import { Global, Module } from '@nestjs/common';
import { InfrastructureModule } from '../infrastructure/infrastructure.module';
import { ApiGatewayMiddleware } from './api-gateway.middleware';
import { ApiPolicyEngineService } from './api-policy-engine.service';
import { ApiPolicyGuard } from './api-policy.guard';
import { ApiRateLimitService } from './api-rate-limit.service';

@Global()
@Module({
  imports: [InfrastructureModule],
  providers: [ApiGatewayMiddleware, ApiRateLimitService, ApiPolicyEngineService, ApiPolicyGuard],
  exports: [ApiGatewayMiddleware, ApiRateLimitService, ApiPolicyEngineService, ApiPolicyGuard],
})
export class ApiGatewayModule {}
