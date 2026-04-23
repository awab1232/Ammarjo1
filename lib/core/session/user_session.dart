import 'package:shared_preferences/shared_preferences.dart';

import '../services/backend_user_client.dart';

class UserSession {
  UserSession._();

  static const String _kAuthToken = 'auth_token';

  static Map<String, dynamic>? user;
  static bool isLoggedIn = false;
  static String? authToken;
  static String get currentUid {
    final u = user;
    if (u == null) return '';
    final firebaseUid = (u['firebaseUid'] ?? u['uid'] ?? '').toString().trim();
    if (firebaseUid.isNotEmpty) return firebaseUid;
    return '';
  }

  static String get currentEmail => (user?['email'] ?? '').toString().trim();
  static String get currentPhone => (user?['phone'] ?? '').toString().trim();
  static String get currentDisplayName =>
      (user?['fullName'] ?? user?['displayName'] ?? user?['name'] ?? '').toString().trim();

  static void setUser(Map<String, dynamic> u) {
    user = Map<String, dynamic>.from(u);
    isLoggedIn = true;
  }

  static Future<void> setAuthToken(String token) async {
    final t = token.trim();
    if (t.isEmpty) return;
    authToken = t;
    isLoggedIn = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAuthToken, t);
  }

  static Future<void> clear() async {
    user = null;
    isLoggedIn = false;
    authToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAuthToken);
  }

  static Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString(_kAuthToken) ?? '').trim();
    if (token.isEmpty) {
      await clear();
      return;
    }
    authToken = token;
    isLoggedIn = true;
    try {
      final profile = await BackendUserClient.getMe();
      if (profile != null) {
        setUser(profile);
      } else {
        await clear();
      }
    } on Object {
      await clear();
    }
  }
}

