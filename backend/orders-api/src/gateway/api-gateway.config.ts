/**
 * API gateway policy + rate limits are always enforced in code (no env bypass).
 * @deprecated Kept for compatibility; always true.
 */
export function isApiGatewayEnforcementEnabled(): boolean {
  return true;
}

/** Default RPM when @ApiPolicy omits rateLimit (gateway enforcement on). */
export function apiGatewayDefaultRpm(): number {
  const raw = process.env.API_GATEWAY_DEFAULT_RPM?.trim();
  const n = raw != null ? Number.parseInt(raw, 10) : 600;
  return Number.isFinite(n) && n >= 10 && n <= 100_000 ? n : 600;
}
