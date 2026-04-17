import { Injectable } from '@nestjs/common';
import type { Request } from 'express';
import { roleHasPermission, type AppRole } from '../identity/rbac-roles.config';
import { getTenantContext } from '../identity/tenant-context.storage';
import type { ApiPolicyMetadata } from './api-policy.types';
import type { PolicyEngineResult } from './api-policy.types';

@Injectable()
export class ApiPolicyEngineService {
  /**
   * Evaluate declarative @ApiPolicy metadata (always enforced when policy is present).
   */
  evaluate(
    policy: ApiPolicyMetadata | undefined,
    req: Request,
    routePath: string,
  ): PolicyEngineResult {
    const evaluatedPermissions = policy?.permissions ?? [];
    if (policy == null) {
      return {
        decision: 'pass_through',
        evaluatedPermissions,
        skipped: true,
      };
    }

    const snap = getTenantContext();
    const hasBearer =
      typeof req.headers.authorization === 'string' && req.headers.authorization.startsWith('Bearer ');

    if (policy.auth && !snap?.uid && !hasBearer) {
      return {
        decision: 'deny',
        reason: 'auth_required',
        evaluatedPermissions,
        skipped: false,
      };
    }

    if (policy.tenant === 'required') {
      const tid = snap?.tenantId ?? snap?.storeId ?? snap?.wholesalerId;
      if (!tid && snap?.uid) {
        return {
          decision: 'deny',
          reason: 'tenant_required',
          evaluatedPermissions,
          skipped: false,
        };
      }
    }

    if (evaluatedPermissions.length > 0 && snap?.uid) {
      const role = snap.activeRole as AppRole;
      for (const p of evaluatedPermissions) {
        if (!roleHasPermission(role, p)) {
          return {
            decision: 'deny',
            reason: `missing_permission:${p}`,
            evaluatedPermissions,
            skipped: false,
          };
        }
      }
    } else if (evaluatedPermissions.length > 0 && !snap?.uid) {
      return {
        decision: 'deny',
        reason: 'missing_permission:unauthenticated',
        evaluatedPermissions,
        skipped: false,
      };
    }

    void routePath;
    return {
      decision: 'allow',
      evaluatedPermissions,
      skipped: false,
    };
  }
}
