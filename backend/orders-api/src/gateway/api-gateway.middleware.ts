import { Injectable, type NestMiddleware } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { NextFunction, Request, Response } from 'express';
import { GlobalRegionContextService } from '../architecture/global-region-context.service';
import { EdgeContextService } from '../infrastructure/edge/edge-context.service';
import { RequestClassificationService } from '../infrastructure/edge/request-classification.service';
import { RegionService } from '../infrastructure/region/region.service';
import {
  defaultCountryCode,
  normalizeCountryCode,
} from '../infrastructure/routing/routing.config';
import { patchGatewayContext, runWithTenantContext } from '../identity/tenant-context.storage';

function firstHeader(req: Request, name: string): string | undefined {
  const v = req.headers[name.toLowerCase()];
  if (Array.isArray(v)) {
    return v[0]?.trim();
  }
  return typeof v === 'string' ? v.trim() : undefined;
}

function clientIp(req: Request): string | null {
  const xf = firstHeader(req, 'x-forwarded-for');
  if (xf) {
    const part = xf.split(',')[0]?.trim();
    return part || null;
  }
  return req.socket?.remoteAddress ?? null;
}

/**
 * First middleware in the chain: ALS + normalized tracing / correlation headers.
 * Runs before all guards and controllers.
 *
 * `use` is a closure over injected services so Express never invokes an unbound method
 * (`this` is undefined for Nest-injected middleware in some call paths).
 */
@Injectable()
export class ApiGatewayMiddleware implements NestMiddleware {
  use: NestMiddleware['use'];

  constructor(
    regions: RegionService,
    globalRegion: GlobalRegionContextService,
    edgeContext: EdgeContextService,
    requestClassification: RequestClassificationService,
  ) {
    this.use = (req: Request, res: Response, next: NextFunction): void => {
      runWithTenantContext(() => {
        const rawCountry = firstHeader(req, 'x-country');
        const normalized = rawCountry != null && rawCountry !== '' ? normalizeCountryCode(rawCountry) : null;
        const country =
          normalized == null || normalized === 'UNKNOWN' ? defaultCountryCode() : normalized;
        const regionLabel = country === 'EG' ? 'EG' : 'JO';

        return globalRegion.runWithContext(
          {
            country,
            region: regionLabel,
            tenantId: undefined,
          },
          () => {
            edgeContext.applyFromRequest(req);
            requestClassification.applyToRequest(req);

            const generated = randomUUID();
            let requestId = firstHeader(req, 'x-request-id');
            if (!requestId) {
              requestId = generated;
            }
            const traceId = firstHeader(req, 'x-trace-id');
            const traceparent = firstHeader(req, 'traceparent');
            const correlationId = requestId;

            req.headers['x-request-id'] = requestId;
            if (!req.headers['x-trace-id'] && traceId) {
              req.headers['x-trace-id'] = traceId;
            }

            res.setHeader('x-request-id', requestId);
            if (traceId) {
              res.setHeader('x-trace-id', traceId);
            }

            const resolvedRegion = regions.resolveRegionFromRequest(req);

            patchGatewayContext({
              requestId,
              correlationId,
              traceIdHeader: traceId ?? null,
              traceparent: traceparent ?? null,
              clientIp: clientIp(req),
              policyDecision: 'pass_through',
              region: resolvedRegion,
            });

            next();
          },
        );
      });
    };
  }
}
