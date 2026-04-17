import 'dart:io';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_orders_client.dart';

/// Manages a persistent device UUID and registers sessions with the backend.
final class DeviceSessionService {
  DeviceSessionService._();
  static final DeviceSessionService instance = DeviceSessionService._();

  static const _kDeviceIdKey = 'ammarjo_device_id';

  /// Returns (or creates) a stable device UUID stored in SharedPreferences.
  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kDeviceIdKey);
    if (stored != null && stored.length == 36) return stored;
    final id = _generateUuid();
    await prefs.setString(_kDeviceIdKey, id);
    return id;
  }

  String _generateUuid() {
    final rng = Random.secure();
    String hex(int count) =>
        List.generate(count, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return '${hex(4)}-${hex(2)}-4${hex(1).substring(1)}${hex(1)}-'
        '${(8 + rng.nextInt(4)).toRadixString(16)}${hex(1)}-${hex(6)}';
  }

  String _deviceOs() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  String _deviceName() {
    if (kIsWeb) return 'Web Browser';
    if (Platform.isAndroid) return 'Android Device';
    if (Platform.isIOS) return 'iPhone / iPad';
    if (Platform.isWindows) return 'Windows PC';
    if (Platform.isMacOS) return 'Mac';
    return 'Unknown Device';
  }

  /// Registers the current device session with the backend.
  /// Silent — never throws (best-effort telemetry).
  Future<void> registerSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final deviceId = await getOrCreateDeviceId();
      final info = await PackageInfo.fromPlatform();

      await BackendOrdersClient.instance.postAuthSession(
        deviceId: deviceId,
        deviceName: _deviceName(),
        deviceOs: _deviceOs(),
        appVersion: '${info.version}+${info.buildNumber}',
      );
    } on Object catch (e) {
      debugPrint('DeviceSessionService: registerSession failed: $e');
    }
  }
}
