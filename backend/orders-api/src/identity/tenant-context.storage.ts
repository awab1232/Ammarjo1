import { AsyncLocalStorage } from 'node:async_hooks';
import {
  emptyGatewayRequestContext,
  type GatewayRequestContext,
} from '../gateway/gateway-request.types';
import { emptyTenantContextSnapshot, type TenantContextSnapshot } from './tenant-context.types';

type Store = { snapshot: TenantContextSnapshot; gateway: GatewayRequestContext };

const als = new AsyncLocalStorage<Store>();

export function runWithTenantContext<T>(fn: () => T): T {
  return als.run(
    { snapshot: emptyTenantContextSnapshot(), gateway: emptyGatewayRequestContext() },
    fn,
  );
}

export function getTenantContext(): TenantContextSnapshot | undefined {
  return als.getStore()?.snapshot;
}

export function setTenantContextSnapshot(snapshot: TenantContextSnapshot): void {
  const s = als.getStore();
  if (s) {
    s.snapshot = snapshot;
  }
}

export function getGatewayContext(): GatewayRequestContext | undefined {
  return als.getStore()?.gateway;
}

export function patchGatewayContext(patch: Partial<GatewayRequestContext>): void {
  const s = als.getStore();
  if (s) {
    Object.assign(s.gateway, patch);
  }
}
