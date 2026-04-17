import { Injectable, Optional } from '@nestjs/common';
import type { Request } from 'express';
import { GlobalRegionContextService } from '../../architecture/global-region-context.service';
import { getGatewayContext, patchGatewayContext } from '../../identity/tenant-context.storage';
import { MultiRegionStrategyService } from '../region/multi-region-strategy.service';
import { normalizeCountryCode } from '../routing/routing.config';

export type NormalizedEdgeContext = {
  country: 'JO' | 'EG' | 'UNKNOWN';
  edgeRegion?: string;
  clientLatencyMs?: number;
};

function firstHeader(req: Request, name: string): string | undefined {
  const v = req.headers[name.toLowerCase()];
  if (Array.isArray(v)) {
    return v[0]?.trim();
  }
  return typeof v === 'string' ? v.trim() : undefined;
}

/**
 * Captures CDN / edge signals (Cloudflare, custom proxies) for future geo routing.
 * Does not perform redirects or external calls.
 */
@Injectable()
export class EdgeContextService {
  constructor(
    private readonly globalRegion: GlobalRegionContextService,
    @Optional() private readonly strategy?: MultiRegionStrategyService,
  ) {}

  /**
   * Parse headers into a normalized snapshot (safe without ALS).
   */
  extractFromRequest(req: Request): NormalizedEdgeContext {
    const cf = firstHeader(req, 'cf-ipcountry');
    const geo = firstHeader(req, 'x-geo-country');
    const explicit = firstHeader(req, 'x-country');
    let country: 'JO' | 'EG' | 'UNKNOWN' = 'UNKNOWN';
    for (const raw of [explicit, cf, geo]) {
      if (raw == null || raw === '') {
        continue;
      }
      const n = normalizeCountryCode(raw);
      if (n === 'JO' || n === 'EG') {
        country = n;
        break;
      }
    }

    const edgeRegion = firstHeader(req, 'x-edge-region');
    const latRaw = firstHeader(req, 'x-client-latency');
    let clientLatencyMs: number | undefined;
    if (latRaw != null && latRaw !== '') {
      const n = Number.parseFloat(latRaw);
      if (Number.isFinite(n)) {
        clientLatencyMs = n;
      }
    }

    return {
      country,
      ...(edgeRegion ? { edgeRegion } : {}),
      ...(clientLatencyMs != null ? { clientLatencyMs } : {}),
    };
  }

  /**
   * Store edge metadata in gateway ALS + global region snapshot (additive).
   */
  applyFromRequest(req: Request): void {
    const parsed = this.extractFromRequest(req);
    const xf = firstHeader(req, 'x-forwarded-for');
    const forwardedFor = xf ? xf.split(',')[0]?.trim() : undefined;

    const knownCountry =
      parsed.country === 'JO' || parsed.country === 'EG' ? parsed.country : undefined;

    patchGatewayContext({
      ...(knownCountry ? { edgeCountry: knownCountry } : {}),
      ...(parsed.edgeRegion != null ? { edgeRegion: parsed.edgeRegion } : {}),
      ...(parsed.clientLatencyMs != null ? { clientLatencyMs: parsed.clientLatencyMs } : {}),
      ...(forwardedFor ? { edgeForwardedFor: forwardedFor } : {}),
    });

    this.globalRegion.patch({
      edge: {
        country: parsed.country,
        ...(parsed.edgeRegion != null ? { region: parsed.edgeRegion } : {}),
        ...(parsed.clientLatencyMs != null ? { clientLatencyMs: parsed.clientLatencyMs } : {}),
      },
    });
  }

  /** Latest edge context from ALS (after applyFromRequest). */
  getEdgeContext(): NormalizedEdgeContext {
    const gw = getGatewayContext();
    if (!gw) {
      return { country: 'UNKNOWN' };
    }
    const c = gw.edgeCountry;
    const country: NormalizedEdgeContext['country'] =
      c === 'JO' || c === 'EG' ? c : 'UNKNOWN';
    return {
      country,
      ...(gw.edgeRegion != null && gw.edgeRegion !== '' ? { edgeRegion: gw.edgeRegion } : {}),
      ...(gw.clientLatencyMs != null && Number.isFinite(gw.clientLatencyMs)
        ? { clientLatencyMs: gw.clientLatencyMs }
        : {}),
    };
  }

  /**
   * Logical region slug for routing hints: jo | eg when country known, else primary from strategy.
   */
  getPreferredRegion(): 'jo' | 'eg' {
    const gw = getGatewayContext();
    if (gw?.edgeCountry === 'JO') {
      return 'jo';
    }
    if (gw?.edgeCountry === 'EG') {
      return 'eg';
    }
    const p = this.strategy?.getPrimaryRegion() ?? 'JO';
    return p === 'EG' ? 'eg' : 'jo';
  }

  /** ISO-style code for data routing (matches MultiRegionStrategyService). */
  getPreferredRegionCode(): 'JO' | 'EG' {
    const gw = getGatewayContext();
    if (gw?.edgeCountry === 'JO' || gw?.edgeCountry === 'EG') {
      return gw.edgeCountry;
    }
    return this.strategy?.getPrimaryRegion() ?? 'JO';
  }

  /**
   * When latency-sensitive reads should prefer edge geo: only if edge country is explicitly known.
   * Otherwise callers should use existing ALS country + strategy logic.
   */
  getLatencySensitiveReadHint(): 'JO' | 'EG' | null {
    const gw = getGatewayContext();
    if (!gw?.latencySensitive) {
      return null;
    }
    if (gw.edgeCountry === 'JO' || gw.edgeCountry === 'EG') {
      return gw.edgeCountry;
    }
    return null;
  }
}
