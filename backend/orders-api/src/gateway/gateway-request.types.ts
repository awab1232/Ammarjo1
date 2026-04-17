export type GatewayPolicyDecision = 'pass_through' | 'allow' | 'deny' | 'skip' | 'rate_limited';

export type GatewayRequestContext = {
  requestId: string;
  correlationId: string;
  traceIdHeader: string | null;
  traceparent: string | null;
  clientIp: string | null;
  policyDecision: GatewayPolicyDecision;
  policyReason?: string;
  /** Set when REGION_ROUTING_ENABLED=1 (see RegionService). */
  region?: string | null;
  /** From cf-ipcountry / x-geo-country when known (edge readiness). */
  edgeCountry?: 'JO' | 'EG';
  edgeRegion?: string | null;
  clientLatencyMs?: number | null;
  /** First hop of x-forwarded-for when present. */
  edgeForwardedFor?: string | null;
  requestType?: 'read' | 'write' | 'mixed';
  requestPriority?: 'low' | 'normal' | 'high';
  latencySensitive?: boolean;
};

export function emptyGatewayRequestContext(): GatewayRequestContext {
  return {
    requestId: '',
    correlationId: '',
    traceIdHeader: null,
    traceparent: null,
    clientIp: null,
    policyDecision: 'pass_through',
    region: null,
    edgeRegion: null,
    clientLatencyMs: null,
    edgeForwardedFor: null,
  };
}
