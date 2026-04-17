# Cloud Run deployment — orders-api

## Overview

- **Container**: `Dockerfile` (Node 20, multi-stage: build → `dist/` only in runtime).
- **Port**: dynamic from `PORT` (app defaults to `3000` if unset).
- **Environment**: `NODE_ENV=production` in the deploy script; add secrets and config via Cloud Run variables or Secret Manager (next phase).

## Health checks

| Endpoint | Use on Cloud Run |
|----------|------------------|
| `GET /health` | **Liveness/readiness** — no auth; safe for load balancer or uptime checks. |
| `GET /internal/ops/global-health` | **Ops snapshot** — requires `SEARCH_INTERNAL_API_KEY` to be set in the service env **and** request header `x-internal-api-key: <same value>`. Without this, the route returns `401`. |

Configure probes to use `/health` unless you also wire the internal API key into your checker.

## Regions (multi-region prep)

`scripts/deploy.sh` deploys the same image to:

- `europe-west1` — primary (EU)
- `me-central1` — Middle East

Override with a single region:

```bash
REGION=europe-west1 ./scripts/deploy.sh
```

Each region is a separate Cloud Run service URL. Global routing / load balancing is out of scope for this script.

## Secrets & configuration (placeholders)

Set these in **Cloud Run → Edit & deploy new revision → Variables & secrets** (or later **Secret Manager** references).

| Name | Purpose |
|------|---------|
| `DATABASE_URL` | PostgreSQL (or per-region URLs if using `ORDERS_DATABASE_URL_*`). |
| `REDIS_URL` | Redis for cache / locks (if enabled). |
| `ALGOLIA_APP_ID`, `ALGOLIA_*` | Algolia catalog search. |
| `SEARCH_INTERNAL_API_KEY` | Protects internal routes including `GET /internal/ops/global-health` (`x-internal-api-key`). |
| `EVENT_*` | Event outbox / workers (as used by your deployment). |
| `FIREBASE_*` / `GOOGLE_CLOUD_PROJECT` | Firebase Admin / Firestore fallback. |

**No Secret Manager wiring in repo yet** — add bindings when you move values out of plain env vars.

## Local run (no Docker)

Unchanged:

```bash
npm install
npm run build
npm run start:prod
```

## Build image locally

```bash
docker build -t orders-api:local .
docker run --rm -p 3000:3000 -e NODE_ENV=production orders-api:local
```

Then open `http://localhost:3000/health`.

## Global HTTPS endpoint (optional)

To put a **single hostname** in front of multiple regional Cloud Run services, see **`docs/GLOBAL_ROUTING.md`** (load balancer, serverless NEGs, DNS, SSL).

## Secrets (production)

See **`docs/SECRETS.md`** for Secret Manager, service account IAM, optional `USE_SECRET_MANAGER=1` on **`scripts/deploy.sh`**, and **alert webhooks**.

**Operations:** **`docs/SLO.md`**, **`docs/MONITORING.md`**, **`docs/RUNBOOK.md`**, **`docs/GO_LIVE.md`**, **`docs/LAUNCH_CHECKLIST.md`**, **`scripts/test-alerts.sh`**, **`scripts/load-test.sh`**.
