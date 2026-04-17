import { isMultiRegionRoutingEnabled } from '../routing/routing.config';

export function isMultiRegionStrategyEnabled(): boolean {
  return process.env.MULTI_REGION_STRATEGY_ENABLED?.trim() === '1';
}

/** Product primary (Jordan unless overridden). */
export function primaryRegionFromEnv(): 'JO' | 'EG' {
  const r = process.env.PRIMARY_REGION?.trim().toUpperCase();
  if (r === 'EG' || r === 'EGY') {
    return 'EG';
  }
  return 'JO';
}

/** Strategy layer only applies when global multi-region data routing is on. */
export function isStrategyRoutingActive(): boolean {
  return isMultiRegionRoutingEnabled() && isMultiRegionStrategyEnabled();
}
