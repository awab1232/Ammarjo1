# Launch checklist — orders-api

Use this before pointing **production** traffic at a new revision or enabling **full** client rollout. Copy into a ticket and check off.

---

## Configuration & secrets

- [ ] **Secrets** configured (Secret Manager or env): `DATABASE_URL`, `SEARCH_INTERNAL_API_KEY`, Redis/Algolia as needed — see `docs/SECRETS.md`
- [ ] **`BACKEND_ORDERS_BASE_URL`** set for **production** mobile builds (correct HTTPS host)
- [ ] **Firebase / GCP** credentials valid for token verification and Firestore fallback paths

---

## Health & connectivity

- [ ] **`GET /health`** returns `ok: true` and expected PostgreSQL fields
- [ ] **`GET /internal/ops/global-health`** (with `x-internal-api-key`) returns acceptable DB/Redis/outbox snapshot
- [ ] **Optional**: regional URLs for multi-region deployments verified

---

## Alerts & monitoring

- [ ] **`EVENT_ALERT_*`** webhooks configured (or `EVENT_ALERT_ENABLED=0` consciously if no outbound alerts)
- [ ] **Smoke**: `scripts/test-alerts.sh` against production URL (read-only sections)
- [ ] **Dashboards**: Cloud Monitoring (or equivalent) for latency, errors, instance count

---

## Resilience (recommended)

- [ ] **Chaos / failover** exercises completed in **staging** — `docs/CHAOS_TESTING.md`
- [ ] **Rollback** understood by on-call — `docs/GO_LIVE.md` rollback section

---

## Load (optional)

- [ ] **`scripts/load-test.sh`** run against staging (or production off-peak with low `N` / `CONCURRENCY`)
- [ ] **k6 / Locust** full test planned separately if required

---

## Client rollout

- [ ] **Backend orders** flags: rollout **percent** or **beta track** decided (`backend_orders_config.dart`)
- [ ] **Phased go-live** plan acknowledged — `docs/GO_LIVE.md`

---

## Sign-off

- [ ] **Owner** name / date: _______________
- [ ] **Rollback owner** (who can revert flags + revision): _______________
