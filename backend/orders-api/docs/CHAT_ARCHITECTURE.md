# Chat Architecture (Phase 6)

## Separation of concerns

- **Firebase (source of truth for chat messages)**:
  - Realtime transport and persistence for messages/conversation documents.
  - Read/write path for message content and delivery state in chat clients.
- **orders-api backend (control + intelligence layer only)**:
  - Conversation control plane metadata views (`/internal/chat/control-plane`).
  - Policy/permissions enforcement through existing gateway + tenant guards.
  - Event-driven intelligence: notifications, analytics, audit logs.
  - Service-request linkage when `conversation.created` is `technician_customer`.

## Event bridge flow

1. Firebase chat lifecycle emits chat events in Cloud Functions.
2. Bridge sends event payloads to `POST /internal/chat/events` (chat-event-bridge).
3. `ChatEventBridgeService` dispatches domain events through `DomainEventEmitterService` + outbox.
4. Outbox worker delivers subscribed handlers:
   - `message.sent`
   - `message.read`
   - `conversation.created`
5. Handlers trigger:
   - Notification hooks / push trigger services
   - Analytics counters
   - Structured audit logging
   - Service-request autocreate (technician flow)

## Explicit non-goals (to avoid duplication)

- Backend does **not** persist chat message bodies.
- Backend does **not** implement websocket/message transport.
- Backend does **not** mirror Firebase messages into Postgres tables.

This keeps Firebase as the realtime data plane and orders-api as the control/intelligence plane.

