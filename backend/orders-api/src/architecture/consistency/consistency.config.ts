/**
 * Soft consistency signals (log-only). No behavior change when enforcement is off.
 */
export function isConsistencyEnforcementEnabled(): boolean {
  return process.env.CONSISTENCY_ENFORCEMENT_ENABLED?.trim() === '1';
}

export function isConsistencyDebugEnabled(): boolean {
  return process.env.CONSISTENCY_DEBUG?.trim() === '1';
}

export function shouldLogConsistencyViolations(): boolean {
  return isConsistencyEnforcementEnabled() || isConsistencyDebugEnabled();
}
