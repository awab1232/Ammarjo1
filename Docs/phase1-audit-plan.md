# Phase 1 — Firestore data audit & migration plan

**Status:** Code-driven inventory (Flutter `lib/` + `FirestoreService`).  
**Principle:** No big-bang migration; stabilize, abstract, then cut over incrementally.

---

## 1. Firestore collections mapping

| Path / pattern | Purpose (current app) | Primary writers |
|----------------|------------------------|-----------------|
| **`products`** | Global marketplace catalog (`wooId`, stock, categories) | Admin import, `FirebaseOrdersRepository` (stock in transaction), catalog repos |
| **`product_categories`** | Category tree / display | Admin / catalog |
| **`home_banners`**, **`marketplace_banners`**, **`technician_banners`** | Marketing slides | Admin banner tools |
| **`stores`** | Approved store profiles, owner, city, category | `StoresRepository`, admin |
| **`stores/{storeId}/products`** | Per-store shelf (isolated from global `products`) | Store owner UI, seeders |
| **`stores/{storeId}/categories`**, **`offers`**, **`orders`** | Store taxonomy, promos, store-facing orders | Store owner, order flows |
| **`orders`** | Canonical order documents for app-created orders | `FirebaseOrdersRepository` |
| **`users/{uid}`** | Profile, wallet, loyalty, role hints | `UsersRepository`, admin, wallet flows |
| **`users/{uid}/orders`** | Denormalized “My orders” view | `CustomerOpsRepository`, sync from root `orders` |
| **`users/{uid}/favorites`** | Favorites subcollection | `UsersRepository` |
| **`wholesalers`**, **`wholesalers/{id}/products`**, **`categories`** | Wholesale vertical | `WholesaleRepository`, admin |
| **`wholesale_orders`**, **`wholesale_commissions`** | Wholesale order & commission ledger | Wholesale flows |
| **`wholesaler_requests`** | Onboarding pipeline | Admin wholesale UI |
| **`firebase_uid_by_email`** | Email → Firebase UID resolution (chat / lookup) | Admin, `UnifiedChatRepository` |
| **`unified_chats/{id}/messages`** | Unified chat threads + messages | `UnifiedChatRepository`, `chat_service` |
| **`support_chats`**, **`messages`** (support) | Support channel | `support_chat_repository` |
| **`technicians`**, **`technicians/{id}/ratings`** | Maintenance marketplace | Maintenance UI, admin |
| **`technician_requests`**, **`service_requests`**, **`technician_notifications`** | Technician pipeline & jobs | Admin, maintenance |
| **`tech_specialties`** | Dropdown source for technician signup | Profile UI |
| **`tenders`**, **`tenders/{id}/offers`** | Tendering | `tender_repository` |
| **`commissions/{storeId}/orders`**, **`tenders`**, **`payments`** | Commission accounting | Admin commissions UI, tenders |
| **`transactions`** | Wallet / P2P style movements | `CustomerOpsRepository` |
| **`reports`** | User reports / moderation queue | Admin reports |
| **`store_requests`** | Store applications | `StoresRepository`, admin |
| **`store_categories`** (demo seeder) | Demo taxonomy | Dev seeder only |
| **`coupons`**, **`coupon_usage`**, **`promotions`**, **`promotion_usage`** | Checkout discounts | `FirebaseOrdersRepository` (transaction) |
| **`migration_hub/status`** | Migration hub counters / flags | Admin migration UI, catalog purge |

---

## 2. Classification per collection

Legend: **KEEP** (long-term acceptable in Firebase for realtime/chat), **MIGRATE LATER** (move to API + relational DB as SSOT), **REMOVE LATER** (replace with backend-derived view or delete after cutover), **DUPLICATED** (same entity stored in more than one path).

| Collection / pattern | Classification | Notes |
|---------------------|----------------|-------|
| `unified_chats`, `messages` (under chats), support chat trees | **KEEP** | Matches target end-state (realtime messaging). |
| `technician_notifications`, FCM-driven local listeners | **KEEP** / edge **MIGRATE LATER** | In-app notification fanout may move to backend + FCM topics later. |
| `products`, `product_categories` | **MIGRATE LATER** | Business catalog; target SSOT: backend `/products` with pagination & cache. |
| `stores`, `stores/*/products`, `stores/*/orders`, … | **MIGRATE LATER** | Store domain; unify under store/product APIs. |
| `orders`, `users/*/orders`, `stores/*/orders` | **DUPLICATED** + **MIGRATE LATER** | Same order represented in root + user mirror + store mirror; risk of drift until one write pipeline. |
| `users` (profile, wallet, loyalty) | **MIGRATE LATER** (profile subset) | Auth stays Firebase; profile/wallet/loyalty should sync from backend eventually. |
| `wholesalers/*`, `wholesale_orders` | **MIGRATE LATER** | Same platform rules as retail catalog/orders. |
| `transactions`, `commissions/*`, `reports` | **MIGRATE LATER** | Financial and ops data belong under server authority + RBAC. |
| `firebase_uid_by_email` | **REMOVE LATER** | Replace with secure server index or Callable lookup post-migration. |
| `migration_hub/status` | **REMOVE LATER** | Temporary operational document. |

---

## 3. Data ownership rules (future single source of truth)

| Entity | Future SSOT | Identity / auth | Notes |
|--------|-------------|-----------------|-------|
| **User identity** | Firebase Auth (`uid`, providers) | Firebase Auth | Backend verifies ID tokens; issues **JWT** for API calls. |
| **User profile & wallet** | Backend (e.g. PostgreSQL) via `/users/me` | Linked by `uid` | Firestore profile becomes read replica or removed after migration. |
| **Product catalog (global)** | Backend `/products` | Service role / seller roles | Firestore `products` retired for business reads/writes. |
| **Store & shelf** | Backend `/stores`, `/stores/{id}/products` | Owner/admin RBAC | Aligns store subcollections into relational model or document API under one service. |
| **Order** | Backend `/orders` (idempotent create) | Customer + store + admin RBAC | **One** write path; mirrors only for realtime UI if needed, or CQRS read models. |
| **Chat** | Firestore (or switch to RTDB/other) | Token + rules | Stays out of relational SSOT per product direction. |
| **Wholesale** | Backend domain same as retail | Role `wholesaler` | Same API layering pattern. |

---

## 4. Risk analysis

| Risk | Description | Mitigation |
|------|-------------|------------|
| **Duplicate orders** | Same logical order written to `orders`, `users/{uid}/orders`, and `stores/{id}/orders`; retries or partial failures can desync IDs or status. | Single **idempotent** `POST /orders` with **client idempotency key**; transactional outbox; UI reads consolidated API; deprecate multi-write client paths incrementally. |
| **Stock inconsistency** | Global `products` stock decremented in Firestore transaction while store shelves may use separate stock concepts. | Unify inventory model in backend; reserve stock at checkout; optional compensating actions; audit logs. |
| **RBAC complexity** | Roles implied in `users.role`, admin UIs, and store ownership; rules may not match server enforcement. | Central **role + permission** model on backend; deny-by-default; Firebase Auth **only** for identity; map custom claims minimally, validate every request server-side. |
| **Chat lookup leakage** | `firebase_uid_by_email` and similar maps expose mapping if rules are wrong. | Tighten rules; move resolution to backend; rate-limit. |
| **Performance at 100k+ users** | Unbounded queries, full collection scans, large client caches. | **Pagination** everywhere; cursor-based lists; composite indexes documented; CDN for media; read replicas / cache (e.g. Redis) behind API. |
| **Migration downtime** | Big-bang import would freeze releases. | **Parallel run**: new API optional behind feature flag; dual-write or read-through only after validation. |

---

## 5. Migration classification report (summary)

- **Immediate (Phase 1–2):** Document reality; introduce **repository interfaces** so UI stops calling `FirebaseFirestore` directly; keep behavior identical.
- **Phase 3:** Deploy stateless backend (JWT after Firebase ID token verification); **no** mandatory cutover.
- **Phase 4+:** Move **writes** for orders/products/users to API in waves; keep Firestore for chat/realtime until explicitly replaced; remove duplicate mirrors last.

---

## 6. Clean separation strategy

1. **Presentation** — Widgets/screens depend on **repository interfaces** (or `Provider` of repositories), never on `FirebaseFirestore`.
2. **Data** — `Firebase*` repository implementations encapsulate Firestore today; **HTTP** implementations can be swapped later without UI changes.
3. **Domain** — Models remain in feature/domain layers; mapping from DTO → domain happens in data layer.
4. **Cross-cutting** — `FirestoreService` remains a **path helper** for low-level Firestore access only inside data implementations (to be deleted when Firestore is no longer used for business data).

---

## 7. Next steps checklist

- [x] Phase 1 audit artifact (this document).
- [ ] Phase 2: complete removal of direct Firestore usage from all `presentation/` widgets (incremental PRs). **Started:** `ProductRepository`, `OrderRepository`, `UserRepository`, `StoreRepository` live under `lib/core/data/repositories/` with Firebase implementations; `Provider` registration in `lib/main.dart`; sample migrations: `stores_home_page.dart`, `profile_page.dart`, `app_drawer.dart`.
- [ ] Phase 3: backend service skeleton + health check + token verification middleware (see `backend/README.md`).
- [ ] Phase 4: order idempotency keys + pagination contract for list endpoints.
