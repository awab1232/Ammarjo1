# Operations runbook — orders-api

Short **playbooks** for common production issues. Adjust for your deployment (Cloud Run regions, load balancer, secrets). Internal API calls need **`SEARCH_INTERNAL_API_KEY`** and header **`x-internal-api-key`**.

---

## If the database fails

1. **Confirm** — `GET /health` (PostgreSQL `ok` / `error`), `GET /internal/ops/global-health` → `database.primary`.
2. **Check** — Secret Manager / env **`DATABASE_URL`** (or regional URLs), network egress, Cloud SQL / instance status.
3. **Mitigate** — Scale to zero not recommended if you need recovery; fix credentials or connectivity first.
4. **Orders API** — Order writes may fail closed in strict PG mode; clients should see **503** / errors per `orders.service` behavior.
5. **Outbox** — Worker cannot progress without DB; expect backlog growth; **no data loss** in outbox table if DB returns after transient outage.

---

## If the DLQ grows (terminal `failed` rows)

1. **Measure** — `GET /internal/ops/dashboard/summary` → `metrics.dlqCount`, `failedInWindow`; `events-timeline` **failed** series.
2. **Inspect** — `GET /internal/events/dashboard` (status counts, recent dead-letter rows).
3. **Triage** — Identify handler / poison messages from `payload` / logs (no PII in logs).
4. **Replay** — After fix, `POST /internal/events/retry/:eventId` or `POST /internal/events/retry-all-failed` (use with care; ensures idempotent handlers).
5. **Alerts** — `EVENT_ALERT_*` envs control webhook thresholds; see `SECRETS.md`.

---

## If API latency spikes

1. **Confirm** — Cloud Run / LB **p95 latency** vs baseline (provider metrics).
2. **In-app** — `GET /internal/ops/global-health`: DB ping latency, Redis, outbox backlog.
3. **Causes** — Cold starts, DB connection pool exhaustion, slow queries, N+1 patterns, external calls (Algolia, webhooks).
4. **Mitigate** — Increase **min instances**, tune pool sizes (`ORDERS_PG_POOL_MAX`, etc.), scale concurrency, cache hot paths (`CACHE_*` envs).

---

## If a region fails (multi-region)

1. **Detect** — `GET /internal/ops/global-health` → `multiRegion.regionHealth`, outbox `lagByRegion`; load balancer health if applicable.
2. **Routing** — `MultiRegionStrategyService` / failover (when enabled) may shift write/read paths; see deployment docs.
3. **Mitigate** — Drain or disable traffic to unhealthy region at **LB**; verify **Secret Manager** and DB URLs per region.
4. **Data** — Single-writer semantics per product rules; do not split brain without runbook for Postgres.

---

## Dashboard quick reference

| Goal | Endpoint |
|------|----------|
| One-page health | `GET /internal/ops/global-health` |
| Outbox KPIs + alerts | `GET /internal/ops/dashboard/summary` |
| Trends | `GET /internal/ops/dashboard/events-timeline` |
| Alert audit trail | `GET /internal/ops/dashboard/alerts-history` |
| Chaos (non-prod or gated) | `GET /internal/ops/dashboard/chaos-report` |

---

## Related docs

- `docs/MONITORING.md` — metric meanings.
- `docs/SLO.md` — SLO mapping.
- `docs/SECRETS.md` — keys and webhooks.
- `docs/GLOBAL_ROUTING.md` — regional LB.
