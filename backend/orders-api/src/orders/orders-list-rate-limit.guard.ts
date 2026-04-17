import {
  CanActivate,
  ExecutionContext,
  HttpException,
  HttpStatus,
  Injectable,
} from '@nestjs/common';

/**
 * Simple per-UID sliding window for GET /users/:id/orders.
 * Set ORDERS_LIST_RATE_LIMIT_PER_MIN=0 or negative to disable.
 *
 * Note: in-memory only — use Redis-backed limits for multi-instance if needed.
 */
@Injectable()
export class OrdersListRateLimitGuard implements CanActivate {
  private readonly buckets = new Map<string, { count: number; reset: number }>();

  canActivate(context: ExecutionContext): boolean {
    const raw = process.env.ORDERS_LIST_RATE_LIMIT_PER_MIN?.trim();
    const lim = raw != null && raw !== '' ? Number.parseInt(raw, 10) : 120;
    if (!Number.isFinite(lim) || lim <= 0) {
      return true;
    }

    const req = context.switchToHttp().getRequest<{ firebaseUid?: string }>();
    const uid = req.firebaseUid;
    if (!uid) {
      return true;
    }

    const now = Date.now();
    const windowMs = 60_000;
    let b = this.buckets.get(uid);
    if (!b || now >= b.reset) {
      b = { count: 0, reset: now + windowMs };
      this.buckets.set(uid, b);
    }
    b.count += 1;
    if (b.count > lim) {
      throw new HttpException('Rate limit exceeded', HttpStatus.TOO_MANY_REQUESTS);
    }

    if (this.buckets.size > 50_000) {
      for (const [k, v] of this.buckets) {
        if (now >= v.reset + windowMs) {
          this.buckets.delete(k);
        }
      }
    }
    return true;
  }
}
