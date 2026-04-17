import type { GatewayPolicyDecision } from './gateway-request.types';

/** `none` = do not enforce tenant scope (internal/service routes). */
export type TenantPolicyScope = 'none' | 'optional' | 'required';

export type ApiPolicyMetadata = {
  /** If true, policy engine expects auth for tenant-scoped rules (informational + enforcement when gateway on). */
  auth?: boolean;
  /** Permissions required when gateway enforcement evaluates policy (mirrors RBAC; optional duplicate). */
  permissions?: string[];
  tenant?: TenantPolicyScope;
  rateLimit?: { rpm: number };
};

export type PolicyEngineResult = {
  decision: GatewayPolicyDecision;
  reason?: string;
  evaluatedPermissions: string[];
  skipped: boolean;
};
