import { BadRequestException, ForbiddenException, Injectable, Logger, Optional } from '@nestjs/common';
import { Pool } from 'pg';
import { TenantContextService } from '../identity/tenant-context.service';

const COMMISSION_RATE = 0.1;

export type CommissionOrderRow = {
  orderId: string;
  orderTotal: number;
  commissionAmount: number;
  /** النسبة الفعلية المطبّقة وقت التسجيل (0–100). */
  commissionPercent: number;
  recordedAt: string;
};

@Injectable()
export class StoreCommissionsService {
  private readonly logger = new Logger(StoreCommissionsService.name);
  private readonly pool: Pool;
  private commissionSchemaReady = false;

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

  private async ensureCommissionSchema(
    client: { query: (sql: string, params?: unknown[]) => Promise<{ rows: unknown[] }> },
  ): Promise<void> {
    if (this.commissionSchemaReady) return;
    await client.query(`
      ALTER TABLE stores ADD COLUMN IF NOT EXISTS commission_percent numeric(12,4) NOT NULL DEFAULT 0;
      ALTER TABLE store_commission_orders ADD COLUMN IF NOT EXISTS commission_percent numeric(12,4) NOT NULL DEFAULT 0;
      CREATE TABLE IF NOT EXISTS store_commission_ledger_entry (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        store_id uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
        order_id text NOT NULL,
        amount numeric(18,4) NOT NULL,
        commission_percent numeric(12,4) NOT NULL DEFAULT 0,
        created_at timestamptz NOT NULL DEFAULT now(),
        UNIQUE (store_id, order_id)
      );
      CREATE INDEX IF NOT EXISTS idx_store_commission_ledger_entry_store_created
        ON store_commission_ledger_entry (store_id, created_at DESC);
    `);
    this.commissionSchemaReady = true;
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
    await this.ensureCommissionSchema(client);
    let rate = COMMISSION_RATE;
    const settingsQ = await client.query(`SELECT payload FROM admin_settings WHERE key = 'platform' LIMIT 1`);
    const payload = (settingsQ.rows[0] as Record<string, unknown> | undefined)?.payload;
    const settings =
      payload && typeof payload === 'object' ? (payload as Record<string, unknown>) : ({} as Record<string, unknown>);
    rate = this.normalizeCommissionRate(settings['globalCommissionPercent'], rate);

    const storeQ = await client.query(
      `SELECT store_type_key, category, COALESCE(commission_percent, 0)::float AS commission_percent
       FROM stores WHERE id = $1::uuid LIMIT 1`,
      [storeId.trim()],
    );
    if (storeQ.rows.length == 0) return rate;
    const storeRow = storeQ.rows[0] as Record<string, unknown>;
    const storePct = Number(storeRow.commission_percent ?? 0);
    if (Number.isFinite(storePct) && storePct > 0) {
      const clamped = Math.min(100, Math.max(0, storePct));
      return clamped / 100;
    }
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
   * عند إنشاء الطلب: تسجيل نسبة/مبلغ عمولة متوقع (لا يكتب في ledgers — ذلك عند التسليم فقط).
   */
  async logCommissionPreviewAtOrderCreate(storeId: string, orderTotalHint: number): Promise<void> {
    const sid = storeId.trim();
    if (!sid || orderTotalHint <= 0) return;
    const client = await this.pool.connect();
    try {
      const rate = await this.resolveDynamicCommissionRate(client, sid);
      const commissionPreview = Math.round(orderTotalHint * rate * 10000) / 10000;
      const pctApplied = Math.round(rate * 10000) / 100;
      this.logger.log(
        JSON.stringify({
          kind: 'order_commission_preview_at_create',
          storeId: sid,
          effectiveRate: rate,
          commissionPercentApplied: pctApplied,
          orderTotalHint,
          commissionPreview,
        }),
      );
    } catch (e) {
      this.logger.warn(`logCommissionPreviewAtOrderCreate: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      client.release();
    }
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
      const percentApplied = Math.round(rate * 10000) / 100;
      const ins = await client.query(
        `INSERT INTO store_commission_orders (store_id, order_id, order_total, commission_amount, commission_percent)
         VALUES ($1::uuid, $2, $3, $4, $5)
         ON CONFLICT (store_id, order_id) DO NOTHING
         RETURNING id`,
        [sid, oid, orderTotal, commissionAmount, percentApplied],
      );
      if (ins.rows.length > 0) {
        await client.query(
          `INSERT INTO store_commission_ledger_entry (store_id, order_id, amount, commission_percent)
           VALUES ($1::uuid, $2, $3, $4)
           ON CONFLICT (store_id, order_id) DO NOTHING`,
          [sid, oid, commissionAmount, percentApplied],
        );
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
    await this.ensureCommissionSchema(this.pool);
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
      `SELECT order_id, order_total, commission_amount, COALESCE(commission_percent, 0)::float AS commission_percent, recorded_at
       FROM store_commission_orders WHERE store_id = $1::uuid ORDER BY recorded_at DESC LIMIT 500`,
      [sid],
    );
    const orders: CommissionOrderRow[] = ordersQ.rows.map((row) => {
      const r = row as Record<string, unknown>;
      return {
        orderId: String(r.order_id),
        orderTotal: Number(r.order_total ?? 0),
        commissionAmount: Number(r.commission_amount ?? 0),
        commissionPercent: Number(r.commission_percent ?? 0),
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
