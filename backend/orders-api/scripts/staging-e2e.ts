import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

type StepResult = {
  step: string;
  ok: boolean;
  status?: number;
  reason?: string;
};

function logStep(step: string, ok: boolean, extra: Record<string, unknown> = {}): void {
  console.log(JSON.stringify({ kind: 'staging_e2e_step', step, ok, ...extra }));
}

function baseUrl(): string {
  return (process.env.BASE_URL?.trim() || 'http://localhost:8080').replace(/\/+$/, '');
}

function loadStagingEnvIfPresent(): void {
  const p = resolve(process.cwd(), '.env.staging');
  if (!existsSync(p)) return;
  const raw = readFileSync(p, 'utf8');
  for (const line of raw.split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const idx = t.indexOf('=');
    if (idx <= 0) continue;
    const k = t.slice(0, idx).trim();
    const v = t.slice(idx + 1).trim();
    if (!process.env[k]) process.env[k] = v;
  }
}

async function callJson(
  method: string,
  path: string,
  token: string,
  body?: Record<string, unknown>,
): Promise<{ status: number; data: unknown }> {
  const res = await fetch(`${baseUrl()}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: body == null ? undefined : JSON.stringify(body),
  });
  let data: unknown = null;
  const text = await res.text();
  if (text.trim().length > 0) {
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
  }
  return { status: res.status, data };
}

async function main(): Promise<void> {
  loadStagingEnvIfPresent();
  const customerToken = process.env.CUSTOMER_TOKEN?.trim();
  const technicianToken = process.env.TECHNICIAN_TOKEN?.trim();
  const adminToken = process.env.ADMIN_TOKEN?.trim();
  const technicianId = process.env.TECHNICIAN_ID?.trim();
  const testStoreId = process.env.TEST_STORE_ID?.trim();

  if (!customerToken || !technicianToken || !adminToken || !technicianId) {
    console.log(
      JSON.stringify({
        kind: 'staging_e2e_completed',
        success: false,
        reason: 'Missing CUSTOMER_TOKEN/TECHNICIAN_TOKEN/ADMIN_TOKEN/TECHNICIAN_ID',
      }),
    );
    process.exit(1);
  }

  const steps: StepResult[] = [];
  let requestId = '';
  try {
    // 1) Create store (optional if TEST_STORE_ID provided; otherwise simulate by verifying stores API read)
    if (testStoreId) {
      steps.push({ step: 'create_store', ok: true, reason: 'Using existing TEST_STORE_ID' });
      logStep('create_store', true, { using: 'existing', storeId: testStoreId });
    } else {
      const s = await callJson('GET', '/stores', customerToken);
      const ok = s.status === 200;
      steps.push({ step: 'create_store', ok, status: s.status, reason: 'store read fallback check' });
      logStep('create_store', ok, { status: s.status });
      if (!ok) throw new Error(`create_store precheck failed status=${s.status}`);
    }

    // 2) Create service request
    const conv = `staging_e2e_${Date.now()}`;
    const create = await callJson('POST', '/service-requests', customerToken, {
      conversationId: conv,
      description: 'staging e2e request',
    });
    const created = create.data as Record<string, unknown> | null;
    requestId = String(created?.id ?? '');
    const createOk = (create.status === 200 || create.status === 201) && requestId.length > 0;
    steps.push({ step: 'create_service_request', ok: createOk, status: create.status });
    logStep('create_service_request', createOk, { status: create.status, requestId });
    if (!createOk) throw new Error(`create request failed status=${create.status}`);

    // 3) Assign technician
    const assign = await callJson('POST', `/service-requests/${requestId}/assign`, adminToken, {
      technicianId,
    });
    const assignOk = assign.status === 200 || assign.status === 201;
    steps.push({ step: 'assign_technician', ok: assignOk, status: assign.status });
    logStep('assign_technician', assignOk, { status: assign.status });
    if (!assignOk) throw new Error(`assign failed status=${assign.status}`);

    // 4) Start request
    const start = await callJson('POST', `/service-requests/${requestId}/start`, technicianToken, {});
    const startOk = start.status === 200 || start.status === 201;
    steps.push({ step: 'start_request', ok: startOk, status: start.status });
    logStep('start_request', startOk, { status: start.status });
    if (!startOk) throw new Error(`start failed status=${start.status}`);

    // 5) Complete request
    const complete = await callJson('POST', `/service-requests/${requestId}/complete`, technicianToken, {});
    const completeOk = complete.status === 200 || complete.status === 201;
    steps.push({ step: 'complete_request', ok: completeOk, status: complete.status });
    logStep('complete_request', completeOk, { status: complete.status });
    if (!completeOk) throw new Error(`complete failed status=${complete.status}`);

    // 6) Create rating
    const rating = await callJson('POST', '/ratings', customerToken, {
      targetType: 'technician',
      targetId: technicianId,
      rating: 5,
      reviewText: 'staging e2e review',
      serviceRequestId: requestId,
    });
    const ratingOk = rating.status === 200 || rating.status === 201;
    steps.push({ step: 'create_rating', ok: ratingOk, status: rating.status });
    logStep('create_rating', ratingOk, { status: rating.status });
    if (!ratingOk) throw new Error(`rating failed status=${rating.status}`);

    // 7) Fetch admin overview (internal endpoint)
    const adminOverview = await fetch(`${baseUrl()}/internal/analytics/overview`, {
      headers: { 'x-internal-api-key': process.env.SEARCH_INTERNAL_API_KEY?.trim() || '' },
    });
    const adminOk = adminOverview.status === 200;
    steps.push({ step: 'fetch_admin_overview', ok: adminOk, status: adminOverview.status });
    logStep('fetch_admin_overview', adminOk, { status: adminOverview.status });
    if (!adminOk) throw new Error(`admin overview failed status=${adminOverview.status}`);

    console.log(JSON.stringify({ kind: 'staging_e2e_completed', success: true, requestId, steps }));
  } catch (e) {
    console.log(
      JSON.stringify({
        kind: 'staging_e2e_completed',
        success: false,
        requestId,
        steps,
        reason: e instanceof Error ? e.message : String(e),
      }),
    );
    process.exit(1);
  }
}

void main();
