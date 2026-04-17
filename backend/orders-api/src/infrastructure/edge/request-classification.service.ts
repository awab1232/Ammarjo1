import { Injectable } from '@nestjs/common';
import type { Request } from 'express';
import { patchGatewayContext } from '../../identity/tenant-context.storage';

export type RequestClassification = {
  type: 'read' | 'write' | 'mixed';
  priority: 'low' | 'normal' | 'high';
  latencySensitive: boolean;
};

function requestPath(req: Request): string {
  const base = req.baseUrl ?? '';
  const p = req.path ?? '';
  const combined = `${base}${p}` || '';
  if (combined) {
    return combined;
  }
  const u = req.originalUrl ?? req.url ?? '';
  return u.split('?')[0] ?? '';
}

/**
 * Lightweight HTTP classification for future edge/cache policy (no side effects except ALS patch).
 */
@Injectable()
export class RequestClassificationService {
  classify(req: Request): RequestClassification {
    const path = requestPath(req).toLowerCase();
    const method = (req.method ?? 'GET').toUpperCase();

    if (path.includes('/search')) {
      return { type: 'read', priority: 'normal', latencySensitive: true };
    }
    if (path.includes('/orders')) {
      return { type: 'write', priority: 'high', latencySensitive: false };
    }

    if (method === 'GET' || method === 'HEAD' || method === 'OPTIONS') {
      return { type: 'read', priority: 'normal', latencySensitive: false };
    }
    if (method === 'POST' || method === 'PUT' || method === 'PATCH' || method === 'DELETE') {
      return { type: 'write', priority: 'normal', latencySensitive: false };
    }

    return { type: 'mixed', priority: 'normal', latencySensitive: false };
  }

  /** Persist classification on gateway ALS for downstream services. */
  applyToRequest(req: Request): void {
    const c = this.classify(req);
    patchGatewayContext({
      requestType: c.type,
      requestPriority: c.priority,
      latencySensitive: c.latencySensitive,
    });
  }
}
