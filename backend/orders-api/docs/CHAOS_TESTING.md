# Chaos testing & failover validation — orders-api

This guide documents **controlled failure injection** for the **event outbox** using the built-in **`EventOutboxChaosService`** (`event-outbox-chaos.config.ts`). Chaos is **env-only**, **reversible** (restart without chaos flags), and **does not add ad-hoc SQL** — it only exercises normal worker and read paths.

---

## Safety & guardrails

| Rule | Detail |
|------|--------|
| **Master switch** | Chaos logic runs only when **`EVENT_OUTBOX_CHAOS=1`**. If unset or `0`, all simulations are off. |
| **Production** | If **`NODE_ENV=production`**, the engine stays **disabled** unless **`EVENT_OUTBOX_CHAOS_ALLOW_PRODUCTION=1`** is also set. **Do not** enable production chaos on live customer traffic without a dedicated runbook and blast-radius review. |
| **No permanent corruption** | Simulations avoid arbitrary row mutation; “worker crash” omits `markProcessed` so rows become **`processing`** until **stale recovery** — the normal reconciliation path. |
| **Reversibility** | Stop the process, clear chaos env vars, restart — behavior returns to baseline. |

---

## Environment flags (reference)

| Variable | Purpose |
|----------|---------|
| `EVENT_OUTBOX_CHAOS` | **`1`** enables the chaos engine (subject to production guard above). |
| `EVENT_OUTBOX_CHAOS_ALLOW_PRODUCTION` | **`1`** required with `NODE_ENV=production` or chaos stays off. |
| `EVENT_OUTBOX_CHAOS_RUN_ID` | Optional label for the run (appears in **chaos report**). |
| `EVENT_OUTBOX_CHAOS_REGION_KILL` | **`1`** — worker **skips entire tick** (no claims/recovery): simulates region-level unavailability. |
| `EVENT_OUTBOX_CHAOS_WORKER_CRASH_PROBABILITY` | **`0`–`1`** — after handler success, randomly **omit `markProcessed`** (crash mid-flight). |
| `EVENT_OUTBOX_CHAOS_DB_LATENCY_MS` | **`0`–`60000`** — artificial delay (ms) before worker DB work. |
| `EVENT_OUTBOX_CHAOS_REPLICA_PARTITION` | **`1`** — treat replica as partitioned: **read path uses primary** (+ optional delay below). |
| `EVENT_OUTBOX_CHAOS_REPLICA_PARTITION_LATENCY_MS` | **`0`–`30000`** — extra delay when replica partition mode is on (read path). |
| `EVENT_OUTBOX_CHAOS_DLQ_SPIKE_MIN` | Minimum **absolute** increase in terminal `failed` count to count as a **DLQ spike** sample (default `5` if unset). |

Caps and behavior are enforced in **`event-outbox-chaos.config.ts`**.

---

## Scenarios

### 1. Region kill

| | |
|--|--|
| **Enable** | `EVENT_OUTBOX_CHAOS=1` and `EVENT_OUTBOX_CHAOS_REGION_KILL=1` |
| **Behavior** | Worker tick performs **no** DB work for that cycle (no claims, no recovery). |
| **Expected** | Backlog may grow; no spurious `processed` rows; system recovers when flag is removed. |
| **Success criteria** | No duplicate processing of truth data beyond normal outbox semantics; after disabling kill, worker drains backlog; **chaos report** shows mode `regionKill: true` while active. |

### 2. Worker crash simulation

| | |
|--|--|
| **Enable** | `EVENT_OUTBOX_CHAOS=1` and e.g. `EVENT_OUTBOX_CHAOS_WORKER_CRASH_PROBABILITY=0.2` |
| **Behavior** | After successful delivery, **sometimes** skips `markProcessed` → row stays **`processing`** until stale recovery. |
| **Expected** | **Idempotent** handlers; retries / recovery clear `processing`; **idempotency replay** may increment in report. |
| **Success criteria** | `simulatedWorkerCrashDrops` > 0 under load; **recovery time** samples present in **chaos report**; eventual `processed` or controlled `failed` per policy. |

### 3. DB latency injection

| | |
|--|--|
| **Enable** | `EVENT_OUTBOX_CHAOS=1` and e.g. `EVENT_OUTBOX_CHAOS_DB_LATENCY_MS=100` |
| **Behavior** | **Sleep** before worker DB operations (capped at 60s). |
| **Expected** | Slower ticks; higher **lag** possible; no structural data corruption. |
| **Success criteria** | Throughput drops predictably; removing latency restores prior **events/min**; alerts may fire if thresholds configured. |

### 4. Replica partition

| | |
|--|--|
| **Enable** | `EVENT_OUTBOX_CHAOS=1`, `EVENT_OUTBOX_CHAOS_REPLICA_PARTITION=1`, optional `EVENT_OUTBOX_CHAOS_REPLICA_PARTITION_LATENCY_MS` |
| **Behavior** | Read paths that would use replica **force primary** + optional partition delay (outbox read client). |
| **Expected** | Dashboard / ops reads still succeed via primary; higher read latency possible. |
| **Success criteria** | No reliance on replica for correctness; **global-health** / summary still load when DB up. |

### 5. DLQ spike (observability)

| | |
|--|--|
| **Enable** | Chaos engine on; optional `EVENT_OUTBOX_CHAOS_DLQ_SPIKE_MIN` to tune sensitivity. |
| **Behavior** | **Does not** inject failures by itself — terminal **`failed`** growth (from real processing or crash/retry policy) is **recorded** when delta ≥ threshold. |
| **Expected** | **chaos report** includes `dlqSpikes` when DLQ grows sharply. |
| **Success criteria** | Spikes visible in report and/or **summary** `dlqCount`; aligns with **events-timeline** `failed` buckets. |

---

## Validation checklist

After a chaos run (staging / dedicated environment):

- [ ] **Orders still created** — API order writes unaffected by chaos (chaos targets **outbox worker** paths, not order HTTP handlers directly); verify business flows still pass.
- [ ] **No data loss** — Outbox rows transition through **pending → processing → processed** (or **failed** per policy); no unexplained row deletion.
- [ ] **DLQ eventually stable** — `dlqCount` and **failed** series either flatten or match expected failure policy after recovery.
- [ ] **Stuck jobs recover** — `processing` rows from crash simulation move back via stale recovery; **chaos report** `recoveryTimeMs` reflects that.
- [ ] **Alerts** — If `EVENT_ALERT_*` is configured, confirm alert paths fire under stress (optional; may be noisy).

---

## Dashboard verification (authenticated internal API)

All routes below require **`SEARCH_INTERNAL_API_KEY`** set on the server and header **`x-internal-api-key: <same value>`**.

| Endpoint | Use |
|----------|-----|
| `GET /internal/ops/dashboard/summary` | KPIs: emitted/processed/failed, **dlqCount**, retry distribution, throughput, **active alerts**. |
| `GET /internal/ops/dashboard/events-timeline` | Hourly buckets: enqueue / processing / processed / **failed**. |
| `GET /internal/ops/global-health` | Aggregated infra: DB, Redis, outbox **lag by region**, cache. |
| `GET /internal/ops/dashboard/chaos-report` | **Chaos run snapshot**: modes, recovery samples, **DLQ spikes**, **lagByRegion**, idempotency / simulated crash counts, guardrails. |

### What to monitor

| Signal | Where |
|--------|--------|
| **Failed rate** | `summary.metrics` / `successFailureRatio`; timeline `failed` series |
| **Retry spikes** | `summary.metrics.retryDistribution` |
| **Lag by region** | `global-health.outbox.lagByRegion` or `chaos-report.observability.lagByRegion` |
| **DLQ count** | `summary.metrics.dlqCount`; **chaos report** `observability.dlqSpikes` |

---

## Running chaos locally or in CI

Use **`scripts/run-chaos.sh`** (see script header). It sets **`EVENT_OUTBOX_CHAOS=1`** and optional scenario flags; override any variable before invocation.

```bash
cd backend/orders-api
./scripts/run-chaos.sh --region-kill
# or
EVENT_OUTBOX_CHAOS_WORKER_CRASH_PROBABILITY=0.15 ./scripts/run-chaos.sh
```

Export report JSON:

```bash
./scripts/export-chaos-report.sh
```

---

## Related docs

- `docs/SECRETS.md` — internal API key for dashboard routes.
- `src/events/event-outbox-chaos.config.ts` — authoritative flag definitions.
