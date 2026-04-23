import {
  type CanActivate,
  type ExecutionContext,
  ForbiddenException,
  HttpException,
  HttpStatus,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { EventOutboxTracingService } from '../events/event-outbox-tracing.service';
import { normalizeOtelTraceId } from '../events/event-outbox-tracing.ids';
import {
  getGatewayContext,
  getTenantContext,
  patchGatewayContext,
} from '../identity/tenant-context.storage';
import { apiGatewayDefaultRpm } from './api-gateway.config';
import { API_POLICY_METADATA_KEY } from './api-policy.constants';
import type { ApiPolicyMetadata } from './api-policy.types';
import { ApiPolicyEngineService } from './api-policy-engine.service';
import { ApiRateLimitService } from './api-rate-limit.service';
import { assertWholesaleStoreTypeAccess } from '../identity/tenant-access';

@Injectable()
export class ApiPolicyGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly engine: ApiPolicyEngineService,
    private readonly rateLimit: ApiRateLimitService,
    private readonly tracing: EventOutboxTracingService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest<Request>();
    // CORS preflight must not hit auth / permission policy (no Bearer on OPTIONS).
    if (req.method === 'OPTIONS') {
      return true;
    }
    if (req.path.includes('/wholesale')) {
      assertWholesaleStoreTypeAccess();
    }
    const handler = context.getHandler();
    const controller = context.getClass();
    const policy = this.reflector.getAllAndOverride<ApiPolicyMetadata>(API_POLICY_METADATA_KEY, [
      handler,
      controller,
    ]);

    const route = `${req.method} ${req.route?.path ?? req.path}`;
    const t0 = process.hrtime.bigint();

    const result = this.engine.evaluate(policy, req, route);

    patchGatewayContext({
      policyDecision: result.decision,
      policyReason: result.reason,
    });

    if (result.decision === 'deny') {
      const t1 = process.hrtime.bigint();
      this.emitGatewaySpan(t0, t1, policy, result, route, result.decision);
      const reason = result.reason ?? 'policy_deny';
      if (reason === 'auth_required' || reason === 'missing_permission:unauthenticated') {
        throw new UnauthorizedException(reason);
      }
      throw new ForbiddenException(reason);
    }

    if (policy?.rateLimit) {
      const rpm = policy.rateLimit.rpm > 0 ? policy.rateLimit.rpm : apiGatewayDefaultRpm();
      const key = this.rateLimitKey(req);
      if (!(await this.rateLimit.tryConsume(key, rpm))) {
        patchGatewayContext({ policyDecision: 'rate_limited', policyReason: 'rpm_exceeded' });
        const t1 = process.hrtime.bigint();
        this.emitGatewaySpan(t0, t1, policy, result, route, 'rate_limited');
        throw new HttpException('Rate limit exceeded', HttpStatus.TOO_MANY_REQUESTS);
      }
    }

    const tDone = process.hrtime.bigint();
    this.emitGatewaySpan(t0, tDone, policy, result, route, result.decision);
    return true;
  }

  private rateLimitKey(req: Request): string {
    const snap = getTenantContext();
    if (snap?.uid) {
      const tid = snap.tenantId ?? snap.storeId ?? snap.wholesalerId;
      if (tid) {
        return `tenant:${tid}:${snap.uid}`;
      }
      return `uid:${snap.uid}`;
    }
    const gw = getGatewayContext();
    const ip = gw?.clientIp ?? 'unknown';
    return `ip:${ip}`;
  }

  private emitGatewaySpan(
    t0: bigint,
    t1: bigint,
    policy: ApiPolicyMetadata | undefined,
    result: { decision: string; evaluatedPermissions?: string[] },
    route: string,
    outcome: string,
  ): void {
    const snap = getTenantContext();
    const gw = getGatewayContext();
    const raw = gw?.correlationId ?? '';
    const traceIdHex = normalizeOtelTraceId(raw) ?? '0'.repeat(32);
    this.tracing.recordApiGatewayRequest({
      traceIdHex,
      startNs: t0,
      endNs: t1,
      route,
      outcome,
      decision: result.decision,
      userId: snap?.uid ?? null,
      tenantId: snap?.tenantId ?? snap?.storeId ?? null,
      permissions: result.evaluatedPermissions ?? policy?.permissions ?? [],
      gatewayRegion: gw?.region ?? null,
      edgeCountry: gw?.edgeCountry ?? null,
      edgeRegion: gw?.edgeRegion ?? null,
      clientLatencyMs: gw?.clientLatencyMs ?? null,
      requestType: gw?.requestType ?? null,
      requestPriority: gw?.requestPriority ?? null,
    });
  }
}
