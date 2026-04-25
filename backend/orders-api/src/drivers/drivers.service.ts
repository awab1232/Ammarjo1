import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import {
  ORDER_DELIVERY_AUTO_RETRY_MAX,
  ORDER_DELIVERY_MANUAL_RETRY_MAX,
} from '../orders/delivery-order-merge';
import { getStorage } from 'firebase-admin/storage';

import { getFirebaseApp } from '../auth/firebase-admin';
import { OrdersPgService } from '../orders/orders-pg.service';
import { NotificationsService } from '../notifications/notifications.service';
import { calculateDistanceKm } from './haversine';

/** Matches migration default + product flow. */
export const DELIVERY_STATUSES = [
  'pending',
  'assigned',
  'accepted',
  'on_the_way',
  'delivered',
  'cancelled',
  'no_driver_found',
] as const;

const MAX_AUTO_ASSIGN_ATTEMPTS = 25;
const AVG_SPEED_KMH = 40;
const ASSIGNMENT_TIMEOUT_SEC = 30;
const NO_DRIVER_AUTO_RETRY_DELAY_SEC = 60;

export type DriverRow = {
  id: string;
  name: string | null;
  phone: string | null;
  auth_uid: string | null;
  is_available: boolean;
  status: string;
  current_lat: string | null;
  current_lng: string | null;
  last_rejected_order_id: string | null;
};

type OrderDeliveryRow = {
  order_id: string;
  user_id: string;
  status: string | null;
  driver_id: string | null;
  delivery_status: string | null;
  delivery_lat: string | null;
  delivery_lng: string | null;
  delivery_assign_attempts: string | number | null;
  delivery_manual_retries: string | number | null;
  eta_minutes: string | number | null;
  assigned_at: Date | null;
};

@Injectable()
export class DriversService {
  private readonly logger = new Logger(DriversService.name);
  private driverRequestsTableReady = false;
  private deliveryColumnsReady: boolean | null = null;

  constructor(
    private readonly pg: OrdersPgService,
    private readonly notifications: NotificationsService,
  ) {}

  private async ensureDeliverySchedulerColumns(): Promise<boolean> {
    if (this.deliveryColumnsReady !== null) {
      return this.deliveryColumnsReady;
    }
    if (!this.pg.isEnabled()) {
      this.deliveryColumnsReady = false;
      return false;
    }

    const required = new Set([
      'driver_id',
      'delivery_status',
      'assigned_at',
      'no_driver_found_at',
      'delivery_auto_retry_count',
    ]);

    try {
      const names = await this.pg.withWriteClient(async (c) => {
        const r = await c.query<{ column_name: string }>(
          `SELECT column_name
           FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'orders'
             AND column_name = ANY($1::text[])`,
          [Array.from(required)],
        );
        return new Set((r.rows ?? []).map((x) => String(x.column_name).trim()));
      });

      const namesSet = names ?? new Set<string>();
      const missing = Array.from(required).filter((col) => !namesSet.has(col));
      if (missing.length > 0) {
        this.deliveryColumnsReady = false;
        this.logger.warn(
          JSON.stringify({
            kind: 'delivery_scheduler_columns_missing',
            missing,
          }),
        );
        return false;
      }

      this.deliveryColumnsReady = true;
      return true;
    } catch (e) {
      this.deliveryColumnsReady = false;
      this.logger.warn(
        JSON.stringify({
          kind: 'delivery_scheduler_columns_check_failed',
          error: e instanceof Error ? e.message : String(e),
        }),
      );
      return false;
    }
  }

  private async ensureDriverRequestsTable(): Promise<void> {
    if (this.driverRequestsTableReady) {
      return;
    }
    if (!this.pg.isEnabled()) {
      return;
    }
    await this.pg.withWriteClient(async (c) => {
      await c.query(`
        CREATE TABLE IF NOT EXISTS driver_requests (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          auth_uid TEXT NOT NULL,
          full_name TEXT NOT NULL,
          phone TEXT NOT NULL,
          identity_image_url TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
          reviewed_at TIMESTAMPTZ,
          reviewed_by TEXT,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_driver_requests_auth_created ON driver_requests (auth_uid, created_at DESC);
        CREATE UNIQUE INDEX IF NOT EXISTS uq_driver_requests_one_pending_per_auth
          ON driver_requests (auth_uid) WHERE status = 'pending';
      `);
    });
    this.driverRequestsTableReady = true;
  }

  /**
   * Public driver onboarding: submit request (requires prior Firebase sign-in; auth_uid stored server-side).
   */
  async createDriverRequest(
    authUid: string,
    input: { fullName: string; phone: string; identityImageUrl: string },
  ): Promise<{ requestId: string }> {
    if (!this.pg.isEnabled()) {
      throw new BadRequestException('Orders database not configured');
    }
    const fullName = input.fullName.trim();
    const phone = input.phone.trim();
    const identityImageUrl = input.identityImageUrl.trim();
    if (!fullName || !phone || !identityImageUrl) {
      throw new BadRequestException('fullName, phone, identityImageUrl are required');
    }
    await this.ensureDriverRequestsTable();
    const existingDriver = await this.getDriverByAuthUid(authUid);
    if (existingDriver) {
      throw new BadRequestException('already_a_driver');
    }
    try {
      const id = await this.pg.withWriteClient(async (c) => {
        const r = await c.query<{ id: string }>(
          `INSERT INTO driver_requests (auth_uid, full_name, phone, identity_image_url, status)
           VALUES ($1, $2, $3, $4, 'pending')
           RETURNING id::text`,
          [authUid.trim(), fullName, phone, identityImageUrl],
        );
        return r.rows[0]?.id ?? null;
      });
      if (!id) {
        throw new BadRequestException('Could not create request');
      }
      return { requestId: id };
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      if (msg.includes('uq_driver_requests_one_pending_per_auth') || msg.includes('duplicate key')) {
        throw new BadRequestException('pending_request_exists');
      }
      throw e;
    }
  }

  async getDriverOnboardingSnapshot(authUid: string): Promise<Record<string, unknown>> {
    const driver = await this.getDriverByAuthUid(authUid);
    if (driver) {
      return { status: 'approved' };
    }
    if (!this.pg.isEnabled()) {
      return { status: 'none' };
    }
    await this.ensureDriverRequestsTable();
    const row = await this.pg.withWriteClient(async (c) => {
      const r = await c.query<{
        id: string;
        status: string;
        full_name: string;
        phone: string;
        identity_image_url: string;
        created_at: Date;
        reviewed_at: Date | null;
      }>(
        `SELECT id::text, status, full_name, phone, identity_image_url, created_at, reviewed_at
         FROM driver_requests WHERE auth_uid = $1 ORDER BY created_at DESC LIMIT 1`,
        [authUid.trim()],
      );
      return r.rows[0] ?? null;
    });
    if (!row) {
      return { status: 'none' };
    }
    return {
      status: row.status,
      requestId: row.id,
      fullName: row.full_name,
      phone: row.phone,
      identityImageUrl: row.identity_image_url,
      createdAt: row.created_at.toISOString(),
      reviewedAt: row.reviewed_at ? row.reviewed_at.toISOString() : null,
    };
  }

  async listDriverRequestsForAdmin(): Promise<{ items: Record<string, unknown>[] }> {
    if (!this.pg.isEnabled()) {
      return { items: [] };
    }
    await this.ensureDriverRequestsTable();
    const rows =
      (await this.pg.withWriteClient(async (c) => {
        const r = await c.query(
          `SELECT id::text, auth_uid, full_name, phone, identity_image_url, status,
                  reviewed_at, reviewed_by, created_at
           FROM driver_requests
           ORDER BY created_at DESC
           LIMIT 500`,
        );
        return r.rows as Record<string, unknown>[];
      })) ?? [];
    return { items: rows };
  }

  async approveDriverRequest(requestId: string, adminUid: string): Promise<{ ok: boolean }> {
    if (!this.pg.isEnabled()) {
      throw new BadRequestException('Orders database not configured');
    }
    await this.ensureDriverRequestsTable();
    const rid = requestId.trim();
    if (!rid) {
      throw new BadRequestException('request id required');
    }
    await this.pg.withWriteClient(async (c) => {
      await c.query('BEGIN');
      try {
        const q = await c.query<{
          id: string;
          auth_uid: string;
          full_name: string;
          phone: string;
          status: string;
        }>(`SELECT id::text, auth_uid, full_name, phone, status FROM driver_requests WHERE id = $1::uuid FOR UPDATE`, [
          rid,
        ]);
        const req = q.rows[0];
        if (!req) {
          throw new NotFoundException('driver_request_not_found');
        }
        if (req.status !== 'pending') {
          throw new BadRequestException('not_pending');
        }
        const dup = await c.query(`SELECT id::text FROM drivers WHERE auth_uid = $1 LIMIT 1`, [req.auth_uid.trim()]);
        if (dup.rows.length === 0) {
          await c.query(
            `INSERT INTO drivers (name, phone, auth_uid, is_available, status)
             VALUES ($1, $2, $3, true, 'offline')`,
            [req.full_name.trim(), req.phone.trim(), req.auth_uid.trim()],
          );
        }
        await c.query(
          `UPDATE driver_requests
           SET status = 'approved', reviewed_at = NOW(), reviewed_by = $2
           WHERE id = $1::uuid`,
          [rid, adminUid.trim()],
        );
        await c.query('COMMIT');
      } catch (e) {
        await c.query('ROLLBACK');
        throw e;
      }
    });
    return { ok: true };
  }

  async rejectDriverRequest(requestId: string, adminUid: string): Promise<{ ok: boolean }> {
    if (!this.pg.isEnabled()) {
      throw new BadRequestException('Orders database not configured');
    }
    await this.ensureDriverRequestsTable();
    const rid = requestId.trim();
    if (!rid) {
      throw new BadRequestException('request id required');
    }
    const n = await this.pg.withWriteClient(async (c) => {
      const r = await c.query(
        `UPDATE driver_requests
         SET status = 'rejected', reviewed_at = NOW(), reviewed_by = $2
         WHERE id = $1::uuid AND status = 'pending'`,
        [rid, adminUid.trim()],
      );
      return r.rowCount ?? 0;
    });
    if (n === 0) {
      throw new NotFoundException('driver_request_not_found_or_not_pending');
    }
    return { ok: true };
  }

  /**
   * POST /upload — stores image in default Firebase Storage bucket; returns a long-lived signed URL.
   */
  async uploadIdentityImage(authUid: string, buffer: Buffer, mime: string): Promise<{ url: string }> {
    const safeMime = (mime || 'image/jpeg').split(';')[0].trim().toLowerCase();
    if (!safeMime.startsWith('image/')) {
      throw new BadRequestException('file must be an image');
    }
    try {
      const bucket = getStorage(getFirebaseApp()).bucket();
      const ext =
        safeMime === 'image/png' ? 'png' : safeMime === 'image/webp' ? 'webp' : safeMime === 'image/gif' ? 'gif' : 'jpg';
      const path = `driver_identity/${authUid.trim()}/${Date.now()}.${ext}`;
      const file = bucket.file(path);
      await file.save(buffer, { contentType: safeMime, resumable: false, validation: false });
      const [url] = await file.getSignedUrl({
        action: 'read',
        expires: new Date(Date.now() + 1000 * 60 * 60 * 24 * 365 * 5),
      });
      return { url };
    } catch (e) {
      this.logger.warn(
        JSON.stringify({
          kind: 'driver_upload_failed',
          error: e instanceof Error ? e.message : String(e),
        }),
      );
      throw new BadRequestException('upload_failed');
    }
  }

  async registerDriver(authUid: string, name?: string, phone?: string): Promise<{ driverId: string }> {
    if (!this.pg.isEnabled()) {
      throw new BadRequestException('Orders database not configured');
    }
    const existing = await this.getDriverByAuthUid(authUid);
    if (!existing) {
      throw new ForbiddenException({
        code: 'DRIVER_NOT_APPROVED',
        message: 'Driver profile requires admin approval before use',
      });
    }
    const out = await this.pg.withWriteClient(async (c) => {
      const r = await c.query<{ id: string }>(
        `UPDATE drivers SET
           name = CASE WHEN $2::text IS NULL THEN name ELSE $2 END,
           phone = CASE WHEN $3::text IS NULL THEN phone ELSE $3 END
         WHERE auth_uid = $1
         RETURNING id`,
        [authUid.trim(), name?.trim() || null, phone?.trim() || null],
      );
      return r.rows[0]?.id ?? null;
    });
    if (!out) {
      throw new BadRequestException('Could not update driver profile');
    }
    return { driverId: out };
  }

  async getDriverByAuthUid(authUid: string): Promise<DriverRow | null> {
    return this.pg.withWriteClient(async (c) => {
      const r = await c.query<DriverRow>(`SELECT * FROM drivers WHERE auth_uid = $1 LIMIT 1`, [
        authUid.trim(),
      ]);
      return r.rows[0] ?? null;
    });
  }

  async updateLocation(authUid: string, lat: number, lng: number): Promise<{ ok: boolean }> {
    const d = await this.getDriverByAuthUid(authUid);
    if (!d) {
      throw new NotFoundException('Driver not registered');
    }
    const ok = await this.pg.withWriteClient(async (c) => {
      await c.query(`UPDATE drivers SET current_lat = $1, current_lng = $2 WHERE id = $3`, [
        lat,
        lng,
        d.id,
      ]);
      return true;
    });
    if (!ok) {
      throw new BadRequestException('Database unavailable');
    }
    return { ok: true };
  }

  async updateDriverStatus(
    authUid: string,
    status: 'online' | 'offline' | 'busy',
  ): Promise<{ ok: boolean }> {
    const d = await this.getDriverByAuthUid(authUid);
    if (!d) {
      throw new NotFoundException('Driver not registered');
    }
    const ok = await this.pg.withWriteClient(async (c) => {
      await c.query(`UPDATE drivers SET status = $1 WHERE id = $2`, [status, d.id]);
      return true;
    });
    if (!ok) {
      throw new BadRequestException('Database unavailable');
    }
    return { ok: true };
  }

  /**
   * Nearest online + available driver with coordinates; skips rejections and busy/offline.
   */
  async findNearestDriver(order: OrderDeliveryRow): Promise<DriverRow | null> {
    const lat = num(order.delivery_lat);
    const lng = num(order.delivery_lng);
    if (lat == null || lng == null) {
      return null;
    }

    const drivers = await this.pg.withWriteClient(async (c) => {
      const r = await c.query<DriverRow>(
        `SELECT * FROM drivers
         WHERE is_available = true AND status = 'online'
           AND current_lat IS NOT NULL AND current_lng IS NOT NULL`,
      );
      return r.rows;
    });
    if (!drivers?.length) {
      return null;
    }

    const rejectedRows = await this.pg.withWriteClient(async (c) => {
      const r = await c.query<{ driver_id: string }>(
        `SELECT driver_id FROM order_driver_rejections WHERE order_id = $1`,
        [order.order_id],
      );
      return r.rows;
    });
    const rejectedSet = new Set((rejectedRows ?? []).map((x) => x.driver_id));

    let nearest: DriverRow | null = null;
    let minDistance = Infinity;
    for (const d of drivers) {
      const dLat = num(d.current_lat);
      const dLng = num(d.current_lng);
      if (dLat == null || dLng == null) {
        continue;
      }
      if (d.status === 'busy') {
        continue;
      }
      if (rejectedSet.has(d.id)) {
        continue;
      }
      if (d.last_rejected_order_id === order.order_id) {
        continue;
      }
      const dist = calculateDistanceKm(lat, lng, dLat, dLng);
      if (dist < minDistance) {
        minDistance = dist;
        nearest = d;
      }
    }
    return nearest;
  }

  async autoAssignDriver(
    orderId: string,
  ): Promise<{ success: boolean; reason?: string; driverId?: string; etaMinutes?: number; distanceKm?: number }> {
    if (!this.pg.isEnabled()) {
      return { success: false, reason: 'db_unavailable' };
    }
    const order = await this.loadOrderDeliveryRow(orderId);
    if (!order) {
      return { success: false, reason: 'order_not_found' };
    }

    const attempts = intish(order.delivery_assign_attempts) ?? 0;
    if (attempts >= MAX_AUTO_ASSIGN_ATTEMPTS) {
      await this.markNoDriverFound(order.order_id, 'max_attempts');
      return { success: false, reason: 'max_assign_attempts' };
    }

    const lat = num(order.delivery_lat);
    const lng = num(order.delivery_lng);
    if (lat == null || lng == null) {
      this.logger.warn(
        JSON.stringify({
          kind: 'auto_assign_blocked_no_coordinates',
          orderId: order.order_id,
        }),
      );
      return { success: false, reason: 'no_coordinates' };
    }

    const driver = await this.findNearestDriver(order);
    if (!driver) {
      await this.bumpAssignAttempts(order.order_id);
      const after = await this.loadOrderDeliveryRow(order.order_id);
      const cnt = intish(after?.delivery_assign_attempts) ?? 0;
      if (cnt >= MAX_AUTO_ASSIGN_ATTEMPTS) {
        await this.markNoDriverFound(order.order_id, 'no_driver');
      }
      return { success: false, reason: 'no_driver' };
    }

    const dLat = num(driver.current_lat);
    const dLng = num(driver.current_lng);
    if (dLat == null || dLng == null) {
      return { success: false, reason: 'driver_no_location' };
    }
    const distanceKm = calculateDistanceKm(lat, lng, dLat, dLng);
    const etaMinutes = Math.max(1, Math.round((distanceKm / AVG_SPEED_KMH) * 60));

    const updated = await this.pg.withWriteClient(async (c) => {
      await c.query(
        `UPDATE orders
         SET driver_id = $1,
             delivery_status = 'assigned',
             delivery_assign_attempts = delivery_assign_attempts + 1,
             eta_minutes = $2,
             assigned_at = NOW(),
             delivery_on_the_way_at = NULL,
             delivery_delivered_at = NULL,
             delivery_auto_retry_count = 0,
             no_driver_found_at = NULL,
             updated_at = NOW()
         WHERE order_id = $3`,
        [driver.id, etaMinutes, order.order_id.trim()],
      );
      return true;
    });
    if (!updated) {
      return { success: false, reason: 'db_unavailable' };
    }

    this.logger.log(
      JSON.stringify({
        kind: 'delivery_status_transition',
        orderId: order.order_id.trim(),
        to: 'assigned',
        driverId: driver.id,
      }),
    );

    if (driver.auth_uid) {
      this.notifications.notifyDriverNewOrder(driver.auth_uid, order.order_id);
    }
    void this.notifications
      .sendPushToUser(order.user_id, {
        title: 'جاري توصيل طلبك',
        body: 'تم تعيين سائق لطلبك',
        data: { orderId: order.order_id, type: 'driver_assigned' },
      })
      .catch((err: unknown) => console.error('[DriversService] notify customer failed:', err));

    return {
      success: true,
      driverId: driver.id,
      etaMinutes,
      distanceKm,
    };
  }

  /**
   * Background: unaccepted assignments older than [ASSIGNMENT_TIMEOUT_SEC].
   */
  async processStaleAssignedOrders(): Promise<void> {
    if (!this.pg.isEnabled()) {
      return;
    }
    if (!(await this.ensureDeliverySchedulerColumns())) {
      return;
    }
    const rows = await this.pg.withWriteClient(async (c) => {
      const r = await c.query<{ order_id: string; driver_id: string }>(
        `SELECT order_id, driver_id FROM orders
         WHERE delivery_status = 'assigned'
           AND assigned_at IS NOT NULL
           AND assigned_at < NOW() - ($1::int * INTERVAL '1 second')`,
        [ASSIGNMENT_TIMEOUT_SEC],
      );
      return r.rows;
    });
    if (!rows?.length) {
      return;
    }
    for (const row of rows) {
      try {
        await this.systemTimeoutReject(row.order_id, row.driver_id);
      } catch (e) {
        this.logger.warn(
          JSON.stringify({
            kind: 'assignment_timeout_processing_failed',
            orderId: row.order_id,
            error: e instanceof Error ? e.message : String(e),
          }),
        );
      }
    }
  }

  private async systemTimeoutReject(orderId: string, driverId: string): Promise<void> {
    const tx = await this.pg.runInTransaction(async (c) => {
      await c.query(
        `INSERT INTO order_driver_rejections (order_id, driver_id) VALUES ($1, $2)
         ON CONFLICT (order_id, driver_id) DO NOTHING`,
        [orderId, driverId],
      );
      await c.query(`UPDATE drivers SET last_rejected_order_id = $1, status = 'online', is_available = true WHERE id = $2`, [
        orderId,
        driverId,
      ]);
      await c.query(
        `UPDATE orders
         SET driver_id = NULL,
             delivery_status = 'pending',
             assigned_at = NULL,
             eta_minutes = NULL,
             delivery_on_the_way_at = NULL,
             delivery_delivered_at = NULL,
             updated_at = NOW()
         WHERE order_id = $1`,
        [orderId],
      );
      return true;
    });
    if (tx === null) {
      return;
    }
    await this.autoAssignDriver(orderId);
  }

  /**
   * Background: re-queue assignment after no_driver_found (60s delay, max 2 automatic attempts).
   */
  async processNoDriverAutoRetries(): Promise<void> {
    if (!this.pg.isEnabled()) {
      return;
    }
    if (!(await this.ensureDeliverySchedulerColumns())) {
      return;
    }
    const candidates = await this.pg.withWriteClient(async (c) => {
      const r = await c.query<{ order_id: string }>(
        `SELECT order_id FROM orders
         WHERE delivery_status = 'no_driver_found'
           AND no_driver_found_at IS NOT NULL
           AND no_driver_found_at <= NOW() - ($1::int * INTERVAL '1 second')
           AND delivery_auto_retry_count < $2
         ORDER BY no_driver_found_at ASC
         LIMIT 25`,
        [NO_DRIVER_AUTO_RETRY_DELAY_SEC, ORDER_DELIVERY_AUTO_RETRY_MAX],
      );
      return r.rows;
    });
    for (const row of candidates ?? []) {
      const oid = await this.pg.runInTransaction(async (c) => {
        const u = await c.query<{ order_id: string }>(
          `UPDATE orders SET
             delivery_auto_retry_count = delivery_auto_retry_count + 1,
             delivery_assign_attempts = 0,
             delivery_status = 'pending',
             delivery_on_the_way_at = NULL,
             delivery_delivered_at = NULL,
             no_driver_found_at = NULL,
             updated_at = NOW()
           WHERE order_id = $1
             AND delivery_status = 'no_driver_found'
             AND delivery_auto_retry_count < $2
           RETURNING order_id`,
          [row.order_id, ORDER_DELIVERY_AUTO_RETRY_MAX],
        );
        return u.rows[0]?.order_id ?? null;
      });
      if (!oid) {
        continue;
      }
      try {
        await this.autoAssignDriver(oid);
      } catch (e) {
        this.logger.warn(
          JSON.stringify({
            kind: 'no_driver_auto_retry_assign_failed',
            orderId: oid,
            error: e instanceof Error ? e.message : String(e),
          }),
        );
      }
    }
  }

  private async markNoDriverFound(
    orderId: string,
    reason: 'max_attempts' | 'no_driver',
  ): Promise<void> {
    const customerUid = await this.pg.withWriteClient(async (c) => {
      const r = await c.query<{ user_id: string }>(
        `UPDATE orders
         SET delivery_status = 'no_driver_found',
             driver_id = NULL,
             assigned_at = NULL,
             eta_minutes = NULL,
             delivery_on_the_way_at = NULL,
             delivery_delivered_at = NULL,
             no_driver_found_at = NOW(),
             updated_at = NOW()
         WHERE order_id = $1
         RETURNING user_id`,
        [orderId.trim()],
      );
      return r.rows[0]?.user_id ?? null;
    });
    const rid = reason === 'max_attempts' ? 'max_assign_attempts' : 'no_drivers_available';
    this.logger.warn(
      JSON.stringify({
        kind: 'delivery_no_driver_found',
        orderId: orderId.trim(),
        reason: rid,
        customerUid: customerUid ?? null,
      }),
    );
    if (customerUid) {
      this.notifications.notifyCustomerNoDriverFound(customerUid, orderId.trim());
    }
    this.notifications.notifyAdminsNoDrivers(orderId.trim(), rid);
  }

  /**
   * Customer-only: after `no_driver_found`, reset auto-assign counter and try again (capped).
   */
  async retryAssignment(
    customerFirebaseUid: string,
    orderId: string,
  ): Promise<{ success: boolean; reason?: string; driverId?: string; etaMinutes?: number }> {
    const order = await this.loadOrderDeliveryRow(orderId);
    if (!order) {
      throw new NotFoundException('Order not found');
    }
    if (order.user_id !== customerFirebaseUid.trim()) {
      throw new ForbiddenException('Not your order');
    }
    if (order.delivery_status !== 'no_driver_found') {
      throw new BadRequestException('Retry is only available when delivery_status is no_driver_found');
    }
    const manual = intish(order.delivery_manual_retries) ?? 0;
    if (manual >= ORDER_DELIVERY_MANUAL_RETRY_MAX) {
      throw new BadRequestException('Maximum manual retries reached');
    }
    const ok = await this.pg.withWriteClient(async (c) => {
      await c.query(
        `UPDATE orders
         SET delivery_assign_attempts = 0,
             delivery_status = 'pending',
             delivery_manual_retries = delivery_manual_retries + 1,
             delivery_on_the_way_at = NULL,
             delivery_delivered_at = NULL,
             no_driver_found_at = NULL,
             updated_at = NOW()
         WHERE order_id = $1 AND user_id = $2`,
        [orderId.trim(), customerFirebaseUid.trim()],
      );
      return true;
    });
    if (!ok) {
      throw new BadRequestException('Database unavailable');
    }
    return this.autoAssignDriver(orderId.trim());
  }

  private async bumpAssignAttempts(orderId: string): Promise<void> {
    await this.pg.withWriteClient(async (c) => {
      await c.query(
        `UPDATE orders SET delivery_assign_attempts = delivery_assign_attempts + 1, updated_at = NOW()
         WHERE order_id = $1`,
        [orderId.trim()],
      );
    });
  }

  async acceptOrder(authUid: string, orderId: string): Promise<{ ok: boolean }> {
    const driver = await this.requireDriver(authUid);
    const order = await this.loadOrderDeliveryRow(orderId);
    if (!order) {
      throw new NotFoundException('Order not found');
    }
    if (order.driver_id !== driver.id) {
      throw new ForbiddenException('DRIVER_ACCESS_DENIED');
    }
    if (order.delivery_status !== 'assigned') {
      throw new BadRequestException(`Invalid delivery status: ${order.delivery_status ?? 'null'}`);
    }
    const ok = await this.pg.withWriteClient(async (c) => {
      await c.query(
        `UPDATE orders SET delivery_status = 'accepted', assigned_at = NULL, updated_at = NOW() WHERE order_id = $1`,
        [order.order_id],
      );
      await c.query(`UPDATE drivers SET status = 'busy', is_available = false WHERE id = $1`, [driver.id]);
      return true;
    });
    if (!ok) {
      throw new BadRequestException('Database unavailable');
    }
    this.notifications.notifyCustomerOrderAccepted(order.user_id, order.order_id);
    return { ok: true };
  }

  async rejectOrder(authUid: string, orderId: string): Promise<{ ok: boolean; reassigned: boolean }> {
    const driver = await this.requireDriver(authUid);
    const order = await this.loadOrderDeliveryRow(orderId);
    if (!order) {
      throw new NotFoundException('Order not found');
    }
    if (order.driver_id !== driver.id) {
      throw new ForbiddenException('DRIVER_ACCESS_DENIED');
    }

    const tx = await this.pg.runInTransaction(async (c) => {
      await c.query(
        `INSERT INTO order_driver_rejections (order_id, driver_id) VALUES ($1, $2)
         ON CONFLICT (order_id, driver_id) DO NOTHING`,
        [order.order_id, driver.id],
      );
      await c.query(`UPDATE drivers SET last_rejected_order_id = $1, status = 'online', is_available = true WHERE id = $2`, [
        order.order_id,
        driver.id,
      ]);
      await c.query(
        `UPDATE orders
         SET driver_id = NULL,
             delivery_status = 'pending',
             assigned_at = NULL,
             eta_minutes = NULL,
             delivery_on_the_way_at = NULL,
             delivery_delivered_at = NULL,
             updated_at = NOW()
         WHERE order_id = $1`,
        [order.order_id],
      );
      return true;
    });
    if (tx === null) {
      throw new BadRequestException('Database unavailable');
    }

    const assign = await this.autoAssignDriver(order.order_id);
    return { ok: true, reassigned: assign.success === true };
  }

  async markOnTheWay(authUid: string, orderId: string): Promise<{ ok: boolean }> {
    const driver = await this.requireDriver(authUid);
    const order = await this.loadOrderDeliveryRow(orderId);
    if (!order) {
      throw new NotFoundException('Order not found');
    }
    if (order.driver_id !== driver.id) {
      throw new ForbiddenException('DRIVER_ACCESS_DENIED');
    }
    if (order.delivery_status !== 'accepted') {
      throw new BadRequestException('Order must be accepted before en route');
    }
    const ok = await this.pg.withWriteClient(async (c) => {
      await c.query(
        `UPDATE orders SET delivery_status = 'on_the_way', delivery_on_the_way_at = NOW(), updated_at = NOW() WHERE order_id = $1`,
        [order.order_id],
      );
      return true;
    });
    if (!ok) {
      throw new BadRequestException('Database unavailable');
    }
    this.logger.log(
      JSON.stringify({
        kind: 'delivery_status_transition',
        orderId: order.order_id.trim(),
        from: order.delivery_status,
        to: 'on_the_way',
      }),
    );
    this.notifications.notifyCustomerDriverEnRoute(order.user_id, order.order_id);
    return { ok: true };
  }

  async completeOrder(authUid: string, orderId: string): Promise<{ ok: boolean }> {
    const driver = await this.requireDriver(authUid);
    const order = await this.loadOrderDeliveryRow(orderId);
    if (!order) {
      throw new NotFoundException('Order not found');
    }
    if (order.driver_id !== driver.id) {
      throw new ForbiddenException('DRIVER_ACCESS_DENIED');
    }
    const st = order.delivery_status ?? '';
    if (st !== 'on_the_way' && st !== 'accepted') {
      throw new BadRequestException('Order must be accepted or on the way before completion');
    }
    const ok = await this.pg.withWriteClient(async (c) => {
      await c.query(
        `UPDATE orders SET delivery_status = 'delivered', delivery_delivered_at = NOW(), updated_at = NOW() WHERE order_id = $1`,
        [order.order_id],
      );
      await c.query(
        `UPDATE drivers SET status = 'online', is_available = true WHERE id = $1`,
        [driver.id],
      );
      return true;
    });
    if (!ok) {
      throw new BadRequestException('Database unavailable');
    }
    this.logger.log(
      JSON.stringify({
        kind: 'delivery_status_transition',
        orderId: order.order_id.trim(),
        from: st,
        to: 'delivered',
      }),
    );
    this.notifications.notifyCustomerOrderDelivered(order.user_id, order.order_id);
    const fullOrder = await this.pg.findPayloadById(order.order_id);
    const ship = num(
      (fullOrder as unknown as { shippingNumeric?: unknown } | null)?.shippingNumeric,
    );
    void this.recordPendingEarningOnDeliveredOrder(order.order_id, order.driver_id, ship);
    return { ok: true };
  }

  /** Manual override — sets assigned_at + ETA when coords allow distance. */
  async manualAssignOrder(
    orderId: string,
    driverId: string,
    deliveryLat?: number,
    deliveryLng?: number,
  ): Promise<{ ok: boolean }> {
    const order = await this.loadOrderDeliveryRow(orderId);
    if (!order) {
      throw new NotFoundException('Order not found');
    }
    const drv = await this.pg.withWriteClient(async (c) => {
      const r = await c.query<{ id: string; auth_uid: string | null; current_lat: string | null; current_lng: string | null }>(
        `SELECT id, auth_uid, current_lat, current_lng FROM drivers WHERE id = $1 LIMIT 1`,
        [driverId],
      );
      return r.rows[0] ?? null;
    });
    if (!drv) {
      throw new NotFoundException('Driver not found');
    }

    const lat = deliveryLat ?? num(order.delivery_lat);
    const lng = deliveryLng ?? num(order.delivery_lng);
    let etaMinutes: number | null = null;
    if (lat != null && lng != null) {
      const dLat = num(drv.current_lat);
      const dLng = num(drv.current_lng);
      if (dLat != null && dLng != null) {
        const dist = calculateDistanceKm(lat, lng, dLat, dLng);
        etaMinutes = Math.max(1, Math.round((dist / AVG_SPEED_KMH) * 60));
      }
    }

    const ok = await this.pg.withWriteClient(async (c) => {
      if (deliveryLat != null && deliveryLng != null) {
        await c.query(
          `UPDATE orders
           SET driver_id = $1,
               delivery_status = 'assigned',
               delivery_lat = $2,
               delivery_lng = $3,
               eta_minutes = $4,
               assigned_at = NOW(),
               delivery_on_the_way_at = NULL,
               delivery_delivered_at = NULL,
               delivery_auto_retry_count = 0,
               no_driver_found_at = NULL,
               updated_at = NOW()
           WHERE order_id = $5`,
          [driverId, deliveryLat, deliveryLng, etaMinutes, orderId.trim()],
        );
      } else {
        await c.query(
          `UPDATE orders
           SET driver_id = $1,
               delivery_status = 'assigned',
               eta_minutes = $2,
               assigned_at = NOW(),
               delivery_on_the_way_at = NULL,
               delivery_delivered_at = NULL,
               delivery_auto_retry_count = 0,
               no_driver_found_at = NULL,
               updated_at = NOW()
           WHERE order_id = $3`,
          [driverId, etaMinutes, orderId.trim()],
        );
      }
      return true;
    });
    if (!ok) {
      throw new BadRequestException('Database unavailable');
    }
    if (drv.auth_uid) {
      this.notifications.notifyDriverNewOrder(drv.auth_uid, orderId.trim());
    }
    return { ok: true };
  }

  private async requireDriver(authUid: string): Promise<DriverRow> {
    const d = await this.getDriverByAuthUid(authUid);
    if (!d) {
      throw new NotFoundException('Driver not registered');
    }
    return d;
  }

  async loadOrderDeliveryRow(orderId: string): Promise<OrderDeliveryRow | null> {
    return this.pg.withWriteClient(async (c) => {
      const r = await c.query<OrderDeliveryRow>(
        `SELECT order_id, user_id, status, driver_id, delivery_status, delivery_lat, delivery_lng,
                delivery_assign_attempts, delivery_manual_retries, eta_minutes, assigned_at
         FROM orders WHERE order_id = $1`,
        [orderId.trim()],
      );
      return r.rows[0] ?? null;
    });
  }

  /**
   * Online drivers with coordinates (admin reassignment picker).
   */
  async listAvailableDrivers(): Promise<Array<{ id: string; name: string | null; phone: string | null }>> {
    if (!this.pg.isEnabled()) {
      return [];
    }
    const out = await this.pg.withWriteClient(async (c) => {
      const r = await c.query<{ id: string; name: string | null; phone: string | null }>(
        `SELECT id, name, phone FROM drivers
         WHERE is_available = true
           AND status = 'online'
           AND current_lat IS NOT NULL
           AND current_lng IS NOT NULL
         ORDER BY name NULLS LAST
         LIMIT 300`,
      );
      return r.rows;
    });
    return out ?? [];
  }

  /**
   * Admin: clear assignment and re-run auto-assign (not for completed/cancelled orders).
   */
  async adminForceReassign(orderId: string): Promise<{
    success: boolean;
    reason?: string;
    driverId?: string;
    etaMinutes?: number;
  }> {
    if (!this.pg.isEnabled()) {
      return { success: false, reason: 'db_unavailable' };
    }
    const order = await this.loadOrderDeliveryRow(orderId);
    if (!order) {
      throw new NotFoundException('Order not found');
    }
    const st = (order.delivery_status ?? '').trim().toLowerCase();
    if (st === 'delivered') {
      throw new BadRequestException('Cannot reassign a delivered order');
    }
    const orderShopStatus = String(order.status ?? '')
      .trim()
      .toLowerCase();
    if (orderShopStatus === 'cancelled' || orderShopStatus === 'refunded') {
      throw new BadRequestException('Cannot reassign cancelled/refunded order');
    }

    const tx = await this.pg.runInTransaction(async (c) => {
      if (order.driver_id) {
        await c.query(
          `UPDATE drivers SET status = 'online', is_available = true WHERE id = $1`,
          [order.driver_id],
        );
      }
      await c.query(
        `UPDATE orders
         SET driver_id = NULL,
             delivery_status = 'pending',
             assigned_at = NULL,
             eta_minutes = NULL,
             delivery_on_the_way_at = NULL,
             delivery_delivered_at = NULL,
             no_driver_found_at = NULL,
             delivery_assign_attempts = 0,
             updated_at = NOW()
         WHERE order_id = $1`,
        [order.order_id],
      );
      return true;
    });
    if (tx === null) {
      throw new BadRequestException('Database unavailable');
    }
    this.logger.log(
      JSON.stringify({
        kind: 'admin_force_reassign',
        orderId: order.order_id.trim(),
      }),
    );
    return this.autoAssignDriver(order.order_id.trim());
  }

  /**
   * لوحة السائق: طلبات مُعيَّنة للقبول، طلب نشط (مقبول/في الطريق)، وسجل التسليم.
   */
  async getWorkbench(authUid: string): Promise<Record<string, unknown>> {
    const onboarding = await this.getDriverOnboardingSnapshot(authUid);
    const driver = await this.getDriverByAuthUid(authUid);
    if (!driver) {
      return {
        onboarding,
        driver: null,
        assignedOrders: [],
        activeOrder: null,
        history: [],
      };
    }
    const rows =
      (await this.pg.withWriteClient(async (c) => {
        const r = await c.query<{
          order_id: string;
          payload: unknown;
          delivery_status: string | null;
          eta_minutes: string | number | null;
          delivery_lat: string | null;
          delivery_lng: string | null;
          updated_at: Date;
        }>(
          `SELECT order_id, payload, delivery_status, eta_minutes, delivery_lat, delivery_lng, updated_at
           FROM orders
           WHERE driver_id = $1::uuid
             AND delivery_status IS NOT NULL
           ORDER BY updated_at DESC
           LIMIT 100`,
          [driver.id],
        );
        return r.rows;
      })) ?? [];

    const assignedOrders: Record<string, unknown>[] = [];
    const history: Record<string, unknown>[] = [];
    let bestActive: {
      row: {
        order_id: string;
        payload: unknown;
        delivery_status: string | null;
        eta_minutes: string | number | null;
        delivery_lat: string | null;
        delivery_lng: string | null;
        updated_at: Date;
      };
      card: Record<string, unknown>;
    } | null = null;

    for (const row of rows) {
      const ds = String(row.delivery_status ?? '').toLowerCase();
      const card = this.driverOrderCard(driver, row);
      if (ds === 'assigned') {
        assignedOrders.push(card);
      } else if (ds === 'accepted' || ds === 'on_the_way') {
        if (
          bestActive == null ||
          row.updated_at.getTime() > bestActive.row.updated_at.getTime()
        ) {
          bestActive = { row, card };
        }
      } else if (ds === 'delivered') {
        history.push(card);
      }
    }

    return {
      onboarding,
      driver: {
        id: driver.id,
        name: driver.name,
        phone: driver.phone,
        status: driver.status,
        isAvailable: driver.is_available,
      },
      assignedOrders,
      activeOrder: bestActive?.card ?? null,
      history: history.slice(0, 50),
    };
  }

  /**
   * When an order is marked [delivered], credit 80% of [shippingNumeric] to the assigned driver.
   * Uses [driver_earnings_ledger] (idempotent on [order_id]).
   */
  async recordPendingEarningOnDeliveredOrder(
    orderId: string,
    driverIdUuid: string | null | undefined,
    shippingNumeric: number | null | undefined,
  ): Promise<void> {
    const oid = orderId.trim();
    const did = driverIdUuid != null ? String(driverIdUuid).trim() : '';
    if (!oid || !did) {
      return;
    }
    const ship = num(shippingNumeric) ?? 0;
    const amount = Math.round(ship * 0.8 * 100) / 100;
    if (amount <= 0) {
      return;
    }
    try {
      await this.pg.withWriteClient(async (c) => {
        await c.query(
          `INSERT INTO driver_earnings_ledger (driver_id, order_id, amount, status)
           VALUES ($1::uuid, $2, $3, 'pending')
           ON CONFLICT (order_id) DO NOTHING`,
          [did, oid, amount],
        );
        await c.query(`UPDATE orders SET driver_earnings_amount = $2 WHERE order_id = $1`, [oid, amount]);
      });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.logger.warn(
        JSON.stringify({ kind: 'driver_earnings_ledger_insert_failed', orderId: oid, error: msg }),
      );
    }
  }

  async getDriverEarningsSummary(firebaseUid: string): Promise<{
    total: number;
    paid: number;
    pending: number;
    deliveries: number;
  }> {
    const uid = firebaseUid.trim();
    if (!uid) {
      throw new BadRequestException('missing_uid');
    }
    const row = await this.pg.withWriteClient(async (c) => {
      const r = await c.query<{
        total: string | null;
        paid: string | null;
        pending: string | null;
        deliveries: string | null;
      }>(
        `SELECT
            COALESCE(SUM(del.amount), 0)::text AS total,
            COALESCE(SUM(CASE WHEN del.status = 'paid' THEN del.amount ELSE 0 END), 0)::text AS paid,
            COALESCE(SUM(CASE WHEN del.status = 'pending' THEN del.amount ELSE 0 END), 0)::text AS pending,
            COUNT(*)::text AS deliveries
         FROM driver_earnings_ledger del
         INNER JOIN drivers d ON d.id = del.driver_id
         WHERE d.auth_uid = $1`,
        [uid],
      );
      return r.rows[0] ?? null;
    });
    if (!row) {
      return { total: 0, paid: 0, pending: 0, deliveries: 0 };
    }
    return {
      total: Number(row.total ?? 0) || 0,
      paid: Number(row.paid ?? 0) || 0,
      pending: Number(row.pending ?? 0) || 0,
      deliveries: Number(row.deliveries ?? 0) || 0,
    };
  }

  private driverOrderCard(
    driver: DriverRow,
    row: {
      order_id: string;
      payload: unknown;
      delivery_status: string | null;
      eta_minutes: string | number | null;
      delivery_lat: string | null;
      delivery_lng: string | null;
      updated_at: Date;
    },
  ): Record<string, unknown> {
    const payload =
      row.payload != null && typeof row.payload === 'object' && !Array.isArray(row.payload)
        ? (row.payload as Record<string, unknown>)
        : {};
    const fn = String(payload['firstName'] ?? '').trim();
    const ln = String(payload['lastName'] ?? '').trim();
    const customerName = `${fn} ${ln}`.trim() || String(payload['email'] ?? '—');
    const a1 = String(payload['address1'] ?? payload['address'] ?? '').trim();
    const city = String(payload['city'] ?? '').trim();
    const address = [a1, city].filter(Boolean).join('، ') || '—';
    const olat = num(row.delivery_lat);
    const olng = num(row.delivery_lng);
    const dlat = num(driver.current_lat);
    const dlng = num(driver.current_lng);
    let distanceKm: number | null = null;
    if (olat != null && olng != null && dlat != null && dlng != null) {
      distanceKm = Math.round(calculateDistanceKm(olat, olng, dlat, dlng) * 10) / 10;
    }
    const eta = intish(row.eta_minutes);
    return {
      orderId: row.order_id,
      customerName,
      address,
      etaMinutes: eta,
      deliveryStatus: row.delivery_status ?? '',
      distanceKm,
    };
  }
}

function num(v: unknown): number | null {
  if (v == null) return null;
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function intish(v: unknown): number | null {
  if (v == null) return null;
  if (typeof v === 'number' && Number.isFinite(v)) return Math.trunc(v);
  const n = Number.parseInt(String(v), 10);
  return Number.isFinite(n) ? n : null;
}
