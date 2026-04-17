# Installation Guide

This document helps developers set up and run the Ammar Store Flutter app from source.

## Requirements

- Flutter SDK compatible with the project `sdk: ^3.10.8`
- Dart SDK compatible with Flutter
- Android Studio or VS Code with Flutter support
- Xcode and CocoaPods for iOS development on macOS
- Internet connection for dependency installation
- A valid Ammar Store GraphQL endpoint
- A valid Ammar Storefront key

## Before You Start

Make sure Flutter is installed and working:

```sh
flutter doctor
```

If Flutter is not set up correctly, refer to:

- <https://docs.flutter.dev/get-started/install>
- <https://developer.android.com/studio>

## Project Setup

### 1. Open the project

Clone or extract the source code, then open the project folder in your IDE.

### 2. Install dependencies

Run the following command from the project root:

```sh
flutter pub get
```

`flutter clean` is optional and only needed if you are fixing a broken local build.

### 3. Configure the Ammar Store server

Open `lib/core/constants/api_constants.dart` and update:

```dart
const String Ammar StoreEndpoint = 'YOUR_Ammar Store_ENDPOINT_HERE';
const String storefrontKey = 'YOUR_STOREFRONT_KEY_HERE';
const String companyName = 'Your Company Name';
```

### 4. Run the app

Start an emulator or connect a physical device, then run:

```sh
flutter run
```

## Android Notes

- App name: `android/app/src/main/AndroidManifest.xml`
- App icon: `android/app/src/main/res/mipmap-*/`
- Firebase config for push notifications: `android/app/google-services.json`

## iOS Setup

If you are running the app on iOS, use macOS and complete these steps:

```sh
cd ios
pod install
```

Then open:

- `ios/Runner.xcworkspace`

After that, run the project from Xcode or with Flutter.

## Important Notes

- This project does not require `build_runner` or Retrofit generation as part of the normal setup flow.
- If push notifications are needed, replace the dummy Firebase config files with your own project files.
- Splash image is loaded from `assets/images/splash.png`.

## Setup Complete

Once dependencies are installed and `api_constants.dart` is configured, the app is ready to run.

