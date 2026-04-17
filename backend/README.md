# Parallel backend (Phase 3 — placeholder)

This folder reserves a **stateless HTTP API** that will run **alongside** Firebase during migration.

## Principles

- **No cutover by default** — the Flutter app keeps using Firebase repositories until a feature flag routes specific calls to this API.
- **Auth** — clients send **Firebase ID tokens**; the service verifies them with the Firebase Admin SDK and issues **short-lived JWTs** for API calls (see project security rules in `docs/phase1-audit-plan.md`).
- **RBAC** — all business authorization is enforced **only** on the server; the client is not trusted.

## Suggested stack (when implemented)

- Node (Express/Fastify) or NestJS on **Cloud Run** (or equivalent): horizontal scaling, stateless instances.
- PostgreSQL (or Cloud SQL) as eventual **system of record** for catalog, orders, and profiles.
- Redis (optional) for caching list endpoints and idempotency keys.

## Endpoints (future)

- `GET /health` — load balancer / uptime checks.
- `POST /v1/orders` — idempotent order creation (`Idempotency-Key` header).
- `GET /v1/products` — cursor pagination.

Implement incrementally; do **not** remove Firestore writers until each flow is validated under flag.
