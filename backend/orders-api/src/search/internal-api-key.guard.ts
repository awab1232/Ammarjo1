import { CanActivate, ExecutionContext, ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';

/**
 * Protects **only** `/internal/*` routes. Set INTERNAL_API_KEY or SEARCH_INTERNAL_API_KEY.
 */
@Injectable()
export class InternalApiKeyGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest<{
      headers?: Record<string, string | string[] | undefined>;
      path?: string;
      originalUrl?: string;
    }>();
    const path = (req.path ?? req.originalUrl ?? '').split('?')[0];
    if (!path.startsWith('/internal')) {
      throw new ForbiddenException('Internal API key is only valid for /internal/* routes');
    }

    const expected =
      process.env.INTERNAL_API_KEY?.trim() || process.env.SEARCH_INTERNAL_API_KEY?.trim();
    if (!expected) {
      throw new UnauthorizedException('Internal search API not configured');
    }
    // Security: never log x-internal-api-key values.
    const raw = req.headers?.['x-internal-api-key'];
    const key = Array.isArray(raw) ? raw[0] : raw;
    if (!key || key !== expected) {
      throw new UnauthorizedException('Invalid internal API key');
    }
    return true;
  }
}
