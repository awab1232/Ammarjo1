import { BadRequestException, ForbiddenException, Injectable, Logger, Optional } from '@nestjs/common';
import { Pool } from 'pg';
import { TenantContextService } from '../identity/tenant-context.service';

const COMMISSION_RATE = 0.1;

export type CommissionOrderRow = {
  orderId: string;
  orderTotal: number;
  commissionAmount: number;
  recordedAt: string;
};

@Injectable()
export class StoreCommissionsService {
  private readonly logger = new Logger(StoreCommissionsService.name);
  private readonly pool: Pool;

  constructor(@Optional() private readonly tenant?: TenantContextService) {
    const connectionString = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
    if (!connectionString) {
      this.logger.error(
        'DATABASE_URL / ORDERS_DATABASE_URL missing — StoreCommissionsService DB queries will fail at runtime until env is set.',
      );
    }
    this.pool = new Pool({ connectionString });
  }

  private actor() {
    const snap = this.tenant?.getSnapshot();
    const userId = snap?.uid?.trim() || null;
    const role = snap?.activeRole?.trim() || 'customer';
    const isPrivileged = role === 'admin' || role === 'system_internal';
    return { userId, role, isPrivileged };
  }

  private async ensureStoreOwnerOrAdmin(storeId: string, action: string): Promise<void> {
    const { userId, role, isPrivileged } = this.actor();
    if (isPrivileged) return;
    const q = await this.pool.query(`SELECT owner_id FROM stores WHERE id = $1::uuid LIMIT 1`, [storeId.trim()]);
    if (q.rows.length === 0) throw new ForbiddenException('Access denied');
    const ownerId = String((q.rows[0] as Record<string, unknown>).owner_id ?? '');
    if (role === 'store_owner' && userId && ownerId === userId) return;
    this.logger.warn(JSON.stringify({ kind: 'authorization_violation', resourceType: 'commission', action, storeId }));
    throw new ForbiddenException('Access denied');
  }

  private normalizeCommissionRate(value: unknown, fallback: number): number {
    const n = Number(value);
    if (!Number.isFinite(n) || n < 0) return fallback;
    return n > 1 ? n / 100 : n;
  }

  private async resolveDynamicCommissionRate(
    client: { query: (sql: string, params?: unknown[]) => Promise<{ rows: unknown[] }> },
    storeId: string,
  ): Promise<number> {
    let rate = COMMISSION_RATE;
    const settingsQ = await client.query(`SELECT payload FROM admin_settings WHERE key = 'platform' LIMIT 1`);
    const payload = (settingsQ.rows[0] as Record<string, unknown> | undefined)?.payload;
    const settings =
      payload && typeof payload === 'object' ? (payload as Record<string, unknown>) : ({} as Record<string, unknown>);
    rate = this.normalizeCommissionRate(settings['globalCommissionPercent'], rate);

    const storeQ = await client.query(`SELECT store_type_key, category FROM stores WHERE id = $1::uuid LIMIT 1`, [
      storeId.trim(),
    ]);
    if (storeQ.rows.length == 0) return rate;
    const storeRow = storeQ.rows[0] as Record<string, unknown>;
    const storeType = String(storeRow.store_type_key ?? '').trim().toLowerCase();
    const category = String(storeRow.category ?? '').trim().toLowerCase();

    const byType = settings['commissionByStoreType'];
    if (byType && typeof byType === 'object') {
      const map = byType as Record<string, unknown>;
      if (storeType.length > 0 && map[storeType] !== undefined) {
        rate = this.normalizeCommissionRate(map[storeType], rate);
      }
    }

    const byCategory = settings['commissionByCategory'];
    if (byCategory && typeof byCategory === 'object') {
      const map = byCategory as Record<string, unknown>;
      if (category.length > 0 && map[category] !== undefined) {
        rate = this.normalizeCommissionRate(map[category], rate);
      }
    }
    return rate;
  }

  /**
   * Idempotent: one row per (store_id, order_id). Called when order becomes delivered.
   */
  async recordCommissionOnDelivery(storeId: string, orderId: string, orderTotal: number): Promise<void> {
    const sid = storeId.trim();
    const oid = orderId.trim();
    if (!sid || !oid || orderTotal <= 0) return;
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const rate = await this.resolveDynamicCommissionRate(client, sid);
      const commissionAmount = Math.round(orderTotal * rate * 10000) / 10000;
      const ins = await client.query(
        `INSERT INTO store_commission_orders (store_id, order_id, order_total, commission_amount)
         VALUES ($1::uuid, $2, $3, $4)
         ON CONFLICT (store_id, order_id) DO NOTHING
         RETURNING id`,
        [sid, oid, orderTotal, commissionAmount],
      );
      if (ins.rows.length > 0) {
        await client.query(
          `INSERT INTO store_commission_ledger (store_id, total_commission, total_paid, balance)
           VALUES ($1::uuid, $2, 0, $2)
           ON CONFLICT (store_id) DO UPDATE SET
             total_commission = store_commission_ledger.total_commission + EXCLUDED.total_commission,
             balance = store_commission_ledger.balance + EXCLUDED.total_commission,
             updated_at = NOW()`,
          [sid, commissionAmount],
        );
      }
      await client.query('COMMIT');
    } catch (e) {
      try {
        await client.query('ROLLBACK');
      } catch {
        /* ignore */
      }
      this.logger.warn(`recordCommissionOnDelivery failed: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      client.release();
    }
  }

  async getSnapshot(storeId: string): Promise<{
    totalCommission: number;
    totalPaid: number;
    balance: number;
    orders: CommissionOrderRow[];
  }> {
    await this.ensureStoreOwnerOrAdmin(storeId, 'commissions_read');
    const sid = storeId.trim();
    const ledger = await this.pool.query(
      `SELECT total_commission, total_paid, balance FROM store_commission_ledger WHERE store_id = $1::uuid LIMIT 1`,
      [sid],
    );
    let totalCommission = 0;
    let totalPaid = 0;
    let balance = 0;
    if (ledger.rows.length > 0) {
      const r = ledger.rows[0] as Record<string, unknown>;
      totalCommission = Number(r.total_commission ?? 0);
      totalPaid = Number(r.total_paid ?? 0);
      balance = Number(r.balance ?? 0);
    }
    const ordersQ = await this.pool.query(
      `SELECT order_id, order_total, commission_amount, recorded_at
       FROM store_commission_orders WHERE store_id = $1::uuid ORDER BY recorded_at DESC LIMIT 500`,
      [sid],
    );
    const orders: CommissionOrderRow[] = ordersQ.rows.map((row) => {
      const r = row as Record<string, unknown>;
      return {
        orderId: String(r.order_id),
        orderTotal: Number(r.order_total ?? 0),
        commissionAmount: Number(r.commission_amount ?? 0),
        recordedAt: new Date(String(r.recorded_at)).toISOString(),
      };
    });
    return { totalCommission, totalPaid, balance, orders };
  }

  async pay(storeId: string, amount: number): Promise<{ totalPaid: number; balance: number }> {
    await this.ensureStoreOwnerOrAdmin(storeId, 'commissions_pay');
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new BadRequestException('amount must be positive');
    }
    const sid = storeId.trim();
    const r = await this.pool.query(
      `UPDATE store_commission_ledger SET
         total_paid = total_paid + $2,
         balance = GREATEST(0, balance - $2),
         updated_at = NOW()
       WHERE store_id = $1::uuid
       RETURNING total_paid, balance`,
      [sid, amount],
    );
    if (r.rows.length === 0) {
      throw new BadRequestException('no_commission_ledger');
    }
    const row = r.rows[0] as Record<string, unknown>;
    return { totalPaid: Number(row.total_paid ?? 0), balance: Number(row.balance ?? 0) };
  }
}
