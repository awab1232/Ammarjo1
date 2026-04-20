// ignore_for_file: lines_longer_than_80_chars
//
// تكوين Firebase لكل منصة.
//
// **الويب (Chrome):** [web] مُحدَّث من تكوين تطبيق Web في Firebase Console.
//
// للمزامنة التلقائية (يُفضّل):
//   1. ثبّت Firebase CLI: https://firebase.google.com/docs/cli
//   2. نفّذ: `firebase login`
//   3. من مجلد المشروع: `dart pub global activate flutterfire_cli`
//   4. `dart pub global run flutterfire_cli:flutterfire configure`
//      واختر المشروع `ammarjo-app` والمنصات web + android.
//
// أو يدوياً: Firebase Console → Project settings → Your apps → تطبيق Web →
// انسخ `apiKey` و `appId` و `authDomain` (و `measurementId` إن وُجد) إلى [web] أدناه.
//
// **نطاقات الويب:** Authentication → Settings → Authorized domains — أضف نطاقات التطوير التي يعتمدها Firebase (مثل نطاق الـ dev المحلي) عند الحاجة.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] لـ AmmarJo (Android package: **com.ammarjo.store**).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  /// من `android/app/google-services.json` — يجب أن يطابق تطبيق Android المسجّل بـ **com.ammarjo.store** في Console.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: String.fromEnvironment(
      'FIREBASE_ANDROID_API_KEY',
      defaultValue: 'AIzaSyDLYZqh47ydAmOD5ZvUawzpz2beGXnKUT0',
    ),
    appId: '1:238624284053:android:7e47faad48b87a241b2a9c',
    messagingSenderId: '238624284053',
    projectId: 'ammarjo-app',
    storageBucket: 'ammarjo-app.firebasestorage.app',
  );

  /// iOS — يفضّل تمرير القيم عبر dart-define لكل بيئة:
  /// `FIREBASE_IOS_API_KEY`, `FIREBASE_IOS_APP_ID`, `FIREBASE_IOS_BUNDLE_ID`.
  /// لا نحتفظ placeholder ثابت هنا حتى لا يُنشر إعداد غير صحيح.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_IOS_API_KEY', defaultValue: ''),
    appId: String.fromEnvironment('FIREBASE_IOS_APP_ID', defaultValue: ''),
    messagingSenderId: '238624284053',
    projectId: 'ammarjo-app',
    storageBucket: 'ammarjo-app.firebasestorage.app',
    iosBundleId: String.fromEnvironment(
      'FIREBASE_IOS_BUNDLE_ID',
      defaultValue: 'com.ammarjo.store',
    ),
  );

  /// **Web** — من `firebaseConfig` في Firebase Console (تطبيق الويب).
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAATU6ELv9lKVzVifo1QyTgo02RCuTYDDQ',
    appId: '1:238624284053:web:a056aafa98c521731b2a9c',
    messagingSenderId: '238624284053',
    projectId: 'ammarjo-app',
    authDomain: 'ammarjo-app.firebaseapp.com',
    storageBucket: 'ammarjo-app.firebasestorage.app',
    measurementId: 'G-D3QY6XFWSL',
  );
}
