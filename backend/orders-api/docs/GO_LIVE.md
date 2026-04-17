# Go-live & scaling plan — orders-api

This document describes a **phased launch** (Jordan & Egypt first), **traffic rollout**, **rollback**, **scaling**, and **post-launch monitoring**. It aligns with:

- **Mobile app** feature flags: `lib/core/config/backend_orders_config.dart` (`USE_BACKEND_ORDERS_*`, `BACKEND_ORDERS_BASE_URL`, rollout percentages).
- **API** env flags: `orders-pg-config.ts` (`ORDERS_PG_STRICT_MODE`, `ORDERS_FIRESTORE_FALLBACK`), multi-region (`ENABLE_MULTI_REGION`, …), load balancing (`docs/GLOBAL_ROUTING.md`).

---

## Phase 1 — Internal testing

| Goal | Team-only validation before any external users. |
|------|--------------------------------------------------|
| **Access** | Staging Cloud Run URL or **restricted hostname** (LB + IP allowlist, VPN, or internal-only DNS). |
| **App** | Point **`BACKEND_ORDERS_BASE_URL`** at staging; enable **`USE_BACKEND_ORDERS`** / **`USE_BACKEND_ORDERS_READ`** / **`USE_BACKEND_ORDERS_WRITE`** via `dart-define` or CI builds for internal testers only. |
| **API** | Secrets on staging; **`GET /health`** and **`GET /internal/ops/*`** (with internal key) green. |
| **Exit** | Orders flow E2E, outbox metrics sane, no critical alerts. |

---

## Phase 2 — Soft launch (5–10% traffic)

| Goal | Limited real users (invite, beta group, or **rollout percent**). |
|------|------------------------------------------------------------------|

**Mobile (gradual backend usage)**

- Set **`backendOrdersReadRolloutPercent`** / **`backendOrdersWriteRolloutPercent`** in `BackendOrdersConfig` to **`5`–`10`** (requires a small **code change** per release, or use remote-config pattern described in the same file comment).
- Alternatively keep percent at **100** but enable backend only for a **subset of builds** (beta track) so only beta users get the dart-defines.

**Monitor (minimum)**

| Signal | Where |
|--------|--------|
| Error rate | Cloud Run / LB 5xx ratio |
| Latency | p95 latency (provider metrics) |
| DLQ / terminal failures | `GET /internal/ops/dashboard/summary` → `metrics.dlqCount`, `failedInWindow`, `successFailureRatio` |
| Outbox backlog | Same + `global-health.outbox` |

**Exit criteria**: No sustained alert storms; DLQ stable; latency within SLO (`docs/SLO.md`).

---

## Phase 3 — Regional launch (Egypt & Jordan)

| Goal | Confirm one country first, then the second (product / ops preference). |
|------|------------------------------------------------------------------------|

**Routing**

- Ensure **`x-country`** (or Firebase claims + `ENABLE_MULTI_REGION`) matches expectations for JO vs EG (`orders-api` routing layer).
- Global HTTPS LB + regional Cloud Run: **`docs/GLOBAL_ROUTING.md`**.

**Order of countries**

- Either **Egypt first** or **Jordan first** — deploy the same revision; shift traffic or ramp **client rollout** per region using **beta tracks** or **feature flags** per store/country if you extend config.

**Exit**: Both regions healthy on **`global-health.multiRegion`**; no single-region backlog explosion.

---

## Phase 4 — Full launch

- **Open traffic**: rollout **100%** on read/write percentages; production **`BACKEND_ORDERS_BASE_URL`** for all users.
- **Remove** staging-only restrictions (IP allowlist, etc.).
- **Keep** monitoring and on-call per `docs/RUNBOOK.md`.

---

## Traffic rollout strategy

### Client-side (Flutter)

| Mechanism | Purpose |
|-----------|---------|
| **`USE_BACKEND_ORDERS`**, **`USE_BACKEND_ORDERS_READ`**, **`USE_BACKEND_ORDERS_WRITE`** | Enable hybrid paths (`dart-define` or build flavors). |
| **`backendOrdersReadRolloutPercent`** / **`backendOrdersWriteRolloutPercent`** | Hash-stable **per-user** fraction (1–100) — gradual exposure without new backend APIs. |
| **`BACKEND_ORDERS_BASE_URL`** | Production API base URL (HTTPS). |

**Revert quickly**: ship a build with flags **off** or percent **0**; users fall back to **Firebase-only** flows for reads/writes as implemented in `FirebaseOrdersRepository`.

### Server-side (orders-api)

| Mechanism | Purpose |
|-----------|---------|
| **`ORDERS_PG_STRICT_MODE`** | When **1**, failed PG writes return **503** — safer for “no silent drops”; when **0**, degraded behavior per `OrdersService` (see rollback). |
| **`ORDERS_FIRESTORE_FALLBACK=1`** | **Read** fallback to Firestore for get/list when PG misses (emergency / migration). |
| **`ENABLE_MULTI_REGION`**, per-region DB URLs | Regional data path; tune with `docs/MONITORING.md`. |

Rollout is **orthogonal** to Cloud Run revisions: prefer **traffic split** (e.g. 90/10 revision) only if you use multiple revisions; otherwise client flags + env toggles are the main levers.

---

## Rollback plan

### If error rate spikes (client / API)

1. **Mobile**: set **`USE_BACKEND_ORDERS_READ=false`** / **`USE_BACKEND_ORDERS_WRITE=false`** (or lower rollout %) — **disable backend reads/writes**; users stay on **Firebase** for those paths.
2. **API**: if needed, increase **Firestore read fallback**: **`ORDERS_FIRESTORE_FALLBACK=1`** (read path only; understand consistency implications — `docs/MONITORING.md`).

### If DB issues

1. **Relax strict mode**: unset or set **`ORDERS_PG_STRICT_MODE=0`** so the API does not fail closed on PG errors where the code path allows legacy behavior (see `OrdersService.create`).
2. **Scale / fix** DB (connections, CPU, storage); verify **`GET /health`** and **`global-health.database.primary`**.

### If a region fails

1. **LB / DNS**: drain or fail over using **`docs/GLOBAL_ROUTING.md`** (global IP, backend health).
2. **App routing**: **`MultiRegionStrategyService`** / failover when **`MULTI_REGION_STRATEGY_ENABLED=1`** (see infra docs).

### If you must rollback the container

- Redeploy **previous Cloud Run revision** or image tag; keep env and secrets unchanged if possible.

---

## Scaling strategy

### Cloud Run

- **Concurrency**: tune per instance (default 80); lower if memory-bound, raise for I/O-bound.
- **Min instances**: reduce cold starts for latency-sensitive paths (cost tradeoff).
- **Max instances**: cap to protect **downstream** Postgres and **Redis** (connection limits).
- **CPU allocation**: CPU always allocated vs request-based — follow GCP guidance for NestJS + pg.

### Database

- **Connection pools**: `ORDERS_PG_POOL_MAX`, `EVENT_OUTBOX_PG_POOL_MAX`, etc. — total instances × pool ≤ **Postgres max_connections** (reserve for admin/migrations).
- **Read replicas**: when enabled, align with `DataRoutingService` / `DbRouterService`.

### Redis

- **Memory/eviction**: size for **cache + rate limit + locks**; monitor **Redis** in `global-health`.

### Algolia / search

- **Quota** and **index** capacity; **`GET /search/products`** load follows Algolia limits.

---

## Post-launch monitoring

| Window | Cadence | Focus |
|--------|---------|--------|
| **First 24h** | Check **every hour** | Error rate, p95 latency, `summary` DLQ + alerts, `global-health` DB/Redis/outbox |
| **First week** | **Daily** | SLO review (`docs/SLO.md`), cost, incident log, any backlog trends |

Use **`docs/MONITORING.md`**, **`scripts/test-alerts.sh`**, and **`docs/RUNBOOK.md`** for procedures.

---

## Related docs

- `docs/LAUNCH_CHECKLIST.md` — pre-flight checklist.
- `docs/SLO.md`, `docs/MONITORING.md`, `docs/RUNBOOK.md`
- `docs/SECRETS.md`, `docs/CLOUD_RUN.md`, `docs/GLOBAL_ROUTING.md`
- `docs/CHAOS_TESTING.md` — resilience validation (non-prod or gated).
- `scripts/load-test.sh` — light stress smoke test.
