# Server Configuration for Ammar Store Flutter App

## Overview

The Ammar Store Flutter app uses **GraphQL** for API communication. Server configuration is managed through constants and environment variables.

## Configuration Steps

### 1. Update API Constants

Go to `lib/core/constants/api_constants.dart` and configure the following:

```dart
/// Ammar Store GraphQL endpoint (e.g., https://your-Ammar Store-server.com/graphql)
const String Ammar StoreEndpoint = 'YOUR_Ammar Store_ENDPOINT_HERE';

/// Storefront key for Ammar Store API
/// Get this from your Ammar Store admin panel
const String storefrontKey = 'YOUR_STOREFRONT_KEY_HERE';

/// Company name (optional metadata)
const String companyName = 'Your Company Name';
```

## Configuration Details

### `Ammar StoreEndpoint`
- **Type:** String (URL)
- **Example:** `https://Ammar Store.yourdomain.com/graphql`
- **Purpose:** GraphQL endpoint URL for all API calls
- **Required:** Yes

### `storefrontKey`
- **Type:** String  
- **Purpose:** API key for identifying your storefront in Ammar Store
- **Location in Ammar Store:** Admin Panel → Settings → Channels
- **Required:** Yes

## GraphQL Client Configuration

The GraphQL client is configured in `lib/core/graphql/graphql_client.dart` with:

- **HTTP Client:** Custom `TimeoutHttpClient` with 30-second timeout for both connection and receive
- **Headers:** 
  - `Content-Type: application/json`
  - `X-STOREFRONT-KEY: {storefrontKey}`
- **Logging:** Detailed request/response logging in debug mode
- **Caching:** HiveStore for offline data persistence

## Network Configuration

### Timeouts
- **Connection Timeout:** 30 seconds
- **Receive Timeout:** 30 seconds

### Cache Management
The app uses HiveStore for caching GraphQL responses. To clear cache on logout:
```dart
await GraphQLClientProvider.clearCache();
```

## Testing Configuration

Before deploying to production:
1. Verify your Ammar Store endpoint is accessible
2. Confirm the storefront key is valid in Ammar Store admin
3. Test API connectivity from your development environment
4. Check network logs in Flutter DevTools for request/response details

