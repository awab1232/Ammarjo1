# Backend URL Setup

## Production (default in app)

Release builds use **`https://api.ammarjo.org`** from `BackendOrdersConfig.defaultBaseUrl` unless you pass a non-local `BACKEND_ORDERS_BASE_URL`.

Optional explicit production build:

```bash
flutter build apk --release --dart-define=BACKEND_ORDERS_BASE_URL=https://api.ammarjo.org
```

## Local development (debug)

```bash
flutter run --dart-define=BACKEND_ORDERS_BASE_URL=http://localhost:3000
```

## Android emulator (host machine API)

If you omit `BACKEND_ORDERS_BASE_URL` in **debug**, the app defaults to `http://10.0.2.2:3000`. You can still override:

```bash
flutter run --dart-define=BACKEND_ORDERS_BASE_URL=http://10.0.2.2:3000
```
