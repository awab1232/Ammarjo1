export type EventOutboxStatus = 'pending' | 'processing' | 'processed' | 'failed';

export type EventOutboxSourceService = 'orders' | 'catalog' | 'system';

/** Optional metadata for durable enqueue (trace + correlation). */
export type EventOutboxEmitMeta = {
  traceId?: string;
  sourceService?: EventOutboxSourceService;
  correlationId?: string;
  /** Target region for routing (multi-region mode); defaults to EVENT_OUTBOX_REGION. */
  targetRegion?: string;
  /** Optional dedupe key; requires multi-region migration + unique index. */
  idempotencyKey?: string;
  /** Optional identity hints (also merged as payload._identity when tenant context exists). */
  tenantId?: string;
  activeRole?: string;
  requestTraceId?: string;
};

export type EventOutboxRow = {
  event_id: string;
  event_type: string;
  entity_id: string;
  payload: Record<string, unknown>;
  status: EventOutboxStatus;
  retry_count: number;
  created_at: Date;
  emitted_at: Date | null;
  processed_at: Date | null;
  failed_at: Date | null;
  picked_by_worker_at: Date | null;
  next_attempt_at: Date;
  processing_started_at: Date | null;
  trace_id: string | null;
  source_service: string | null;
  correlation_id: string | null;
  region: string | null;
  processing_region: string | null;
  idempotency_key: string | null;
};

export type EventOutboxDashboardStats = {
  statusBreakdown: Record<string, number>;
  retryDistribution: Array<{ retry_count: number; count: number }>;
  recentFailures: EventOutboxRowSummary[];
};

export type EventOutboxRowSummary = {
  event_id: string;
  event_type: string;
  entity_id: string;
  status: EventOutboxStatus;
  retry_count: number;
  created_at: string;
  emitted_at: string | null;
  picked_by_worker_at: string | null;
  processed_at: string | null;
  failed_at: string | null;
  trace_id: string | null;
  source_service: string | null;
  correlation_id: string | null;
  last_error: string | null;
  region: string | null;
  processing_region: string | null;
};
