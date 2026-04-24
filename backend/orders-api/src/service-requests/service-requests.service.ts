import {
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  Optional,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Pool, type PoolClient } from 'pg';
import { DomainEventEmitterService } from '../events/domain-event-emitter.service';
import { DomainEventNames } from '../events/domain-event-names';
import { buildPgPoolConfig } from '../infrastructure/database/pg-ssl';
import { TenantContextService } from '../identity/tenant-context.service';
import { MatchingService } from '../matching/matching.service';
import type { ServiceRequestRecord, ServiceRequestStatus } from './service-requests.types';

type CreateRequestInput = {
  conversationId: string;
  description?: string;
  imageUrl?: string;
  title?: string;
  categoryId?: string;
  notes?: string;
  customerId?: string;
  technicianId?: string | null;
};

type ListRequestsInput = {
  customerId?: string;
  technicianId?: string;
  status?: string;
  limit?: number;
  cursor?: string;
};

@Injectable()
export class ServiceRequestsService {
  private readonly logger = new Logger(ServiceRequestsService.name);
  private readonly pool: Pool | null;
  private readonly serviceRequestColumns =
    'id, customer_id, technician_id, conversation_id, status, description, title, category_id, image_url, notes, chat_id, technician_email, earnings_amount, created_at, updated_at';

  constructor(
    private readonly events: DomainEventEmitterService,
    private readonly matching: MatchingService,
    @Optional() private readonly tenant?: TenantContextService,
  ) {
    const url = process.env.DATABASE_URL?.trim();
    this.pool = url
      ? new Pool({
          ...buildPgPoolConfig(url, {
            max: Number(process.env.SERVICE_REQUESTS_PG_POOL_MAX || 6),
            idleTimeoutMillis: 30_000,
          }),
        })
      : null;
  }

  private requireDb(): Pool {
    if (!this.pool) throw new ServiceUnavailableException('service_requests database not configured');
    return this.pool;
  }

  private actorIdOrThrow(): string {
    const uid = this.tenant?.getSnapshot().uid?.trim();
    if (!uid) throw new UnauthorizedException('Authentication required');
    return uid;
  }

  private actorRole(): string {
    return this.tenant?.getSnapshot().activeRole?.trim() || '';
  }

  private actorEmail(): string | null {
    const e = this.tenant?.getSnapshot().email?.trim();
    return e && e.length > 0 ? e : null;
  }

  private isAdminOrSystemRole(): boolean {
    const r = this.actorRole();
    return r === 'admin' || r === 'system_internal';
  }

  private logAccessDenied(reason: string, endpoint: string, fields: Record<string, unknown>): void {
    const snap = this.tenant?.getSnapshot();
    this.logger.warn(
      JSON.stringify({
        kind: 'authorization_violation',
        userId: snap?.uid ?? null,
        resourceId: (fields.requestId as string | undefined) ?? endpoint,
        resourceType: 'service_request',
        action: endpoint,
        reason,
        tenantId: snap?.tenantId ?? snap?.storeId ?? snap?.wholesalerId ?? null,
        endpoint,
        ...fields,
      }),
    );
  }

  /** Row technician_id may be Firebase uid or legacy email stored as id. */
  private technicianIdMatchesActor(technicianId: string | null, actorUid: string, actorEmail: string | null): boolean {
    if (technicianId == null || String(technicianId).trim() === '') return false;
    const t = String(technicianId).trim();
    if (t === actorUid) return true;
    if (actorEmail && t.toLowerCase() === actorEmail.toLowerCase()) return true;
    return false;
  }

  private listTechnicianScopeParamValid(
    technicianIdParam: string,
    actorUid: string,
    actorEmail: string | null,
  ): boolean {
    const p = technicianIdParam.trim();
    if (p === actorUid) return true;
    if (actorEmail && p.toLowerCase() === actorEmail.toLowerCase()) return true;
    return false;
  }

  private async withClient<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.requireDb().connect();
    try {
      return await fn(client);
    } finally {
      client.release();
    }
  }

  private mapRow(row: Record<string, unknown>): ServiceRequestRecord {
    return {
      id: String(row.id),
      customerId: String(row.customer_id),
      technicianId: row.technician_id != null ? String(row.technician_id) : null,
      conversationId: String(row.conversation_id),
      status: String(row.status) as ServiceRequestStatus,
      description: String(row.description ?? ''),
      title: String(row.title ?? ''),
      categoryId: String(row.category_id ?? ''),
      imageUrl: row.image_url != null ? String(row.image_url) : null,
      notes: String(row.notes ?? ''),
      chatId: row.chat_id != null ? String(row.chat_id) : null,
      technicianEmail: row.technician_email != null ? String(row.technician_email) : null,
      earningsAmount: Number(row.earnings_amount ?? 0),
      createdAt: new Date(String(row.created_at)).toISOString(),
      updatedAt: new Date(String(row.updated_at)).toISOString(),
    };
  }

  private encodeCursor(createdAtIso: string, id: string): string {
    const raw = JSON.stringify({ c: createdAtIso, id });
    return Buffer.from(raw, 'utf8').toString('base64url');
  }

  private decodeCursor(cursor: string | undefined): { createdAtIso: string; id: string } | null {
    const v = cursor?.trim();
    if (!v) return null;
    try {
      const parsed = JSON.parse(Buffer.from(v, 'base64url').toString('utf8')) as {
        c?: unknown;
        id?: unknown;
      };
      const c = typeof parsed.c === 'string' ? parsed.c.trim() : '';
      const id = typeof parsed.id === 'string' ? parsed.id.trim() : '';
      if (!c || !id) return null;
      return { createdAtIso: c, id };
    } catch {
      return null;
    }
  }

  async listRequests(input: ListRequestsInput): Promise<{ items: ServiceRequestRecord[]; nextCursor: string | null }> {
    const actorId = this.actorIdOrThrow();
    const actorEmail = this.actorEmail();
    const privileged = this.isAdminOrSystemRole();

    const customerId = input.customerId?.trim();
    const technicianId = input.technicianId?.trim();
    const status = input.status?.trim();
    const limit = Math.min(Math.max(1, Number(input.limit ?? 20) || 20), 100);
    const cursor = this.decodeCursor(input.cursor);

    if (!privileged) {
      const hasCustomer = Boolean(customerId);
      const hasTechnician = Boolean(technicianId);
      if (hasCustomer && hasTechnician) {
        this.logAccessDenied('ambiguous_list_scope', 'GET /service-requests', {
          actorId,
          customerId,
          technicianId,
        });
        throw new ForbiddenException('List scope must be either customer or technician, not both');
      }
      if (!hasCustomer && !hasTechnician) {
        this.logAccessDenied('unscoped_list', 'GET /service-requests', { actorId });
        throw new ForbiddenException('A scoped filter (customerId or technicianId) is required');
      }
      if (hasCustomer) {
        if (customerId !== actorId) {
          this.logAccessDenied('list_customer_id_mismatch', 'GET /service-requests', {
            actorId,
            customerId,
          });
          throw new ForbiddenException('Cannot list requests for another customer');
        }
      } else if (hasTechnician && technicianId) {
        if (!this.listTechnicianScopeParamValid(technicianId, actorId, actorEmail)) {
          this.logAccessDenied('list_technician_id_mismatch', 'GET /service-requests', {
            actorId,
            technicianId,
          });
          throw new ForbiddenException('Cannot list requests for another technician');
        }
      }
    }

    return this.withClient(async (client) => {
      const clauses: string[] = [];
      const params: Array<string | number> = [];
      let idx = 1;
      if (privileged) {
        if (customerId) {
          clauses.push(`customer_id = $${idx++}`);
          params.push(customerId);
        }
        if (technicianId) {
          clauses.push(`technician_id = $${idx++}`);
          params.push(technicianId);
        }
      } else if (customerId) {
        clauses.push(`customer_id = $${idx++}`);
        params.push(actorId);
      } else if (technicianId) {
        const pUid = idx++;
        const pEmail = idx++;
        clauses.push(
          `(technician_id = $${pUid} OR ($${pEmail}::text <> '' AND technician_id IS NOT NULL AND lower(trim(technician_id::text)) = lower(trim($${pEmail}::text))))`,
        );
        params.push(actorId, actorEmail ?? '');
      }
      if (status) {
        clauses.push(`status = $${idx++}`);
        params.push(status);
      }
      if (cursor) {
        clauses.push(`(created_at, id) < ($${idx++}::timestamptz, $${idx++}::uuid)`);
        params.push(cursor.createdAtIso, cursor.id);
      }
      const where = clauses.length > 0 ? `WHERE ${clauses.join(' AND ')}` : '';
      params.push(limit + 1);
      const q = await client.query(
        `SELECT ${this.serviceRequestColumns} FROM service_requests
         ${where}
         ORDER BY created_at DESC, id DESC
         LIMIT $${idx}`,
        params,
      );
      const rows = q.rows.map((r) => this.mapRow(r as Record<string, unknown>));
      const hasMore = rows.length > limit;
      const items = hasMore ? rows.slice(0, limit) : rows;
      const last = items.length > 0 ? items[items.length - 1] : null;
      const nextCursor = hasMore && last != null ? this.encodeCursor(last.createdAt, last.id) : null;
      return { items, nextCursor };
    });
  }

  async createRequest(input: CreateRequestInput): Promise<ServiceRequestRecord> {
    const actorId = this.actorIdOrThrow();
    const conversationId = input.conversationId.trim();
    if (!conversationId) throw new ForbiddenException('conversationId is required');
    const description = (input.description ?? '').trim();
    const imageUrl = (input.imageUrl ?? '').trim() || null;
    const title = (input.title ?? '').trim() || 'طلب خدمة';
    const categoryId = (input.categoryId ?? '').trim();
    const notes = (input.notes ?? '').trim();
    const customerId = (input.customerId ?? actorId).trim();
    const technicianId = input.technicianId?.trim() || null;
    return this.withClient(async (client) => {
      await client.query('BEGIN');
      try {
        const existing = await client.query(
          `SELECT ${this.serviceRequestColumns} FROM service_requests WHERE conversation_id = $1 LIMIT 1`,
          [conversationId],
        );
        if (existing.rows.length > 0) {
          await client.query('COMMIT');
          return this.mapRow(existing.rows[0] as Record<string, unknown>);
        }
        const id = randomUUID();
        const inserted = await client.query(
          `INSERT INTO service_requests (
             id, customer_id, technician_id, technician_email, conversation_id, status, description, title, category_id, image_url, notes, chat_id, earnings_amount, created_at, updated_at
           ) VALUES ($1::uuid, $2, $3, $4, $5, 'pending', $6, $7, $8, $9, $10, $11, 0, NOW(), NOW())
           RETURNING ${this.serviceRequestColumns}`,
          [
            id,
            customerId,
            technicianId,
            technicianId,
            conversationId,
            description,
            title,
            categoryId,
            imageUrl,
            notes,
            '',
          ],
        );
        await client.query(
          `INSERT INTO service_request_status_history (request_id, status, changed_by, created_at)
           VALUES ($1::uuid, 'pending', $2, NOW())`,
          [id, actorId],
        );
        const created = this.mapRow(inserted.rows[0] as Record<string, unknown>);
        await this.events.enqueueInTransaction(client, DomainEventNames.SERVICE_REQUEST_CREATED, created.id, {
          requestId: created.id,
          conversationId: created.conversationId,
          customerId: created.customerId,
          technicianId: created.technicianId,
          status: created.status,
        });
        await client.query('COMMIT');
        return created;
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      }
    });
  }

  async getById(id: string): Promise<ServiceRequestRecord> {
    const actorId = this.actorIdOrThrow();
    const actorEmail = this.actorEmail();
    return this.withClient(async (client) => {
      const r = await client.query(
        `SELECT ${this.serviceRequestColumns} FROM service_requests WHERE id = $1::uuid LIMIT 1`,
        [id.trim()],
      );
      if (r.rows.length === 0) throw new NotFoundException('Service request not found');
      const row = this.mapRow(r.rows[0] as Record<string, unknown>);
      const privileged = this.isAdminOrSystemRole();
      const isCustomer = row.customerId === actorId;
      const isTechnician = this.technicianIdMatchesActor(row.technicianId, actorId, actorEmail);
      if (!privileged && !isCustomer && !isTechnician) {
        this.logAccessDenied('get_by_id_forbidden', 'GET /service-requests/:id', {
          requestId: row.id,
          actorId,
        });
        throw new ForbiddenException('Access denied for this service request');
      }
      return row;
    });
  }

  async assignTechnician(requestId: string, technicianId: string): Promise<ServiceRequestRecord> {
    const actor = this.actorIdOrThrow();
    const role = this.actorRole();
    if (role !== 'admin' && role !== 'system_internal') {
      throw new ForbiddenException('Only admin/system_internal can assign technicians');
    }
    const tech = technicianId.trim();
    if (!tech) throw new ForbiddenException('technicianId is required');
    return this.updateStatus(requestId, 'assigned', actor, {
      technicianId: tech,
      eventName: DomainEventNames.SERVICE_REQUEST_ASSIGNED,
    });
  }

  async autoAssignTechnician(requestId: string): Promise<ServiceRequestRecord | null> {
    const top = await this.matching.getTopTechnicians(3);
    if (top.length === 0) {
      this.logger.log(
        JSON.stringify({
          kind: 'service_request_auto_assign_skipped',
          requestId,
          reason: 'no_technicians',
        }),
      );
      return null;
    }
    const chosen = top[0];
    const assigned = await this.updateStatus(requestId, 'assigned', 'system_internal', {
      technicianId: chosen.technicianId,
      eventName: DomainEventNames.SERVICE_REQUEST_ASSIGNED,
    });
    this.events.dispatch(DomainEventNames.SERVICE_REQUEST_AUTO_ASSIGNED, assigned.id, {
      requestId: assigned.id,
      technicianId: assigned.technicianId,
      score: chosen.score,
      scoreBreakdown: chosen.breakdown,
      candidates: top.slice(0, 3),
    });
    this.logger.log(
      JSON.stringify({
        kind: 'service_request_auto_assigned',
        requestId: assigned.id,
        chosenTechnician: chosen.technicianId,
        scoreBreakdown: chosen.breakdown,
        topCandidates: top.slice(0, 3),
      }),
    );
    return assigned;
  }

  async startRequest(requestId: string): Promise<ServiceRequestRecord> {
    const actor = this.actorIdOrThrow();
    return this.updateStatus(requestId, 'in_progress', actor, {
      eventName: DomainEventNames.SERVICE_REQUEST_STARTED,
    });
  }

  async completeRequest(requestId: string): Promise<ServiceRequestRecord> {
    const actor = this.actorIdOrThrow();
    return this.updateStatus(requestId, 'completed', actor, {
      eventName: DomainEventNames.SERVICE_REQUEST_COMPLETED,
    });
  }

  async cancelRequest(requestId: string): Promise<ServiceRequestRecord> {
    const actor = this.actorIdOrThrow();
    return this.updateStatus(requestId, 'cancelled', actor, {
      eventName: DomainEventNames.SERVICE_REQUEST_CANCELLED,
    });
  }

  async attachChat(requestId: string, chatId: string): Promise<ServiceRequestRecord> {
    const actor = this.actorIdOrThrow();
    const cid = chatId.trim();
    if (!cid) {
      throw new ForbiddenException('chatId is required');
    }
    return this.withClient(async (client) => {
      const current = await client.query(
        `SELECT ${this.serviceRequestColumns} FROM service_requests WHERE id = $1::uuid LIMIT 1`,
        [requestId.trim()],
      );
      if (current.rows.length === 0) throw new NotFoundException('Service request not found');
      const row = this.mapRow(current.rows[0] as Record<string, unknown>);
      const privileged = this.isAdminOrSystemRole();
      const actorEmail = this.actorEmail();
      const isCustomer = row.customerId === actor;
      const isTechnician = this.technicianIdMatchesActor(row.technicianId, actor, actorEmail);
      if (!privileged && !isCustomer && !isTechnician) {
        throw new ForbiddenException('Cannot attach chat to this service request');
      }
      const updated = await client.query(
        `UPDATE service_requests SET chat_id = $2, updated_at = NOW() WHERE id = $1::uuid RETURNING *`,
        [requestId.trim(), cid],
      );
      return this.mapRow(updated.rows[0] as Record<string, unknown>);
    });
  }

  async getEarnings(technicianEmail: string): Promise<{ total: number }> {
    const email = technicianEmail.trim();
    if (!email) return { total: 0 };
    const actor = this.actorIdOrThrow();
    const actorEmail = this.actorEmail()?.toLowerCase() ?? '';
    if (!this.isAdminOrSystemRole() && actorEmail !== email.toLowerCase()) {
      this.logAccessDenied('earnings_scope_mismatch', 'GET /service-requests/earnings', {
        actorId: actor,
        technicianEmail: email,
      });
      throw new ForbiddenException('Access denied');
    }
    return this.withClient(async (client) => {
      const q = await client.query<{ total: string | number }>(
        `SELECT SUM(earnings_amount) AS total
         FROM service_requests
         WHERE technician_email = $1 AND status = 'completed'`,
        [email],
      );
      const raw = q.rows[0]?.total ?? 0;
      return { total: Number(raw) || 0 };
    });
  }

  private async updateStatus(
    requestId: string,
    status: ServiceRequestStatus,
    actorId: string,
    opts: { technicianId?: string; eventName: (typeof DomainEventNames)[keyof typeof DomainEventNames] },
  ): Promise<ServiceRequestRecord> {
    return this.withClient(async (client) => {
      await client.query('BEGIN');
      try {
        const current = await client.query(`SELECT ${this.serviceRequestColumns} FROM service_requests WHERE id = $1::uuid LIMIT 1`, [
          requestId.trim(),
        ]);
        if (current.rows.length === 0) throw new NotFoundException('Service request not found');
        const row = current.rows[0] as Record<string, unknown>;
        const mapped = this.mapRow(row);
        const actorEmail = this.actorEmail();
        const privileged = this.isAdminOrSystemRole();
        const internalActor = actorId === 'system_internal' && status === 'assigned';
        if (!privileged && !internalActor) {
          if (!this.technicianIdMatchesActor(mapped.technicianId, actorId, actorEmail)) {
            this.logAccessDenied('update_status_forbidden', 'POST /service-requests/:id/status', {
              requestId: mapped.id,
              actorId,
              status,
            });
            throw new ForbiddenException('Only the assigned technician or an administrator can update this request');
          }
        }
        const update = await client.query(
          `UPDATE service_requests
           SET status = $2,
               technician_id = $3,
               technician_email = $4,
               updated_at = NOW()
           WHERE id = $1::uuid
           RETURNING ${this.serviceRequestColumns}`,
          [requestId.trim(), status, opts.technicianId ?? mapped.technicianId, mapped.technicianEmail],
        );
        await client.query(
          `INSERT INTO service_request_status_history (request_id, status, changed_by, created_at)
           VALUES ($1::uuid, $2, $3, NOW())`,
          [requestId.trim(), status, actorId],
        );
        const next = this.mapRow(update.rows[0] as Record<string, unknown>);
        await this.events.enqueueInTransaction(client, opts.eventName, next.id, {
          requestId: next.id,
          conversationId: next.conversationId,
          customerId: next.customerId,
          technicianId: next.technicianId,
          previousStatus: String(row.status ?? ''),
          status: next.status,
          changedBy: actorId,
        });
        await client.query('COMMIT');
        return next;
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      }
    });
  }
}

