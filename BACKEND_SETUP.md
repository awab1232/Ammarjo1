# Backend URL Setup
## Local development:
flutter run --dart-define=BACKEND_ORDERS_BASE_URL=http://localhost:3000

## Android emulator (localhost = 10.0.2.2):
flutter run --dart-define=BACKEND_ORDERS_BASE_URL=http://10.0.2.2:3000

## Production:
flutter run --dart-define=BACKEND_ORDERS_BASE_URL=https://your-cloud-run-url.run.app
