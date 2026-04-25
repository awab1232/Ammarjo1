import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../../core/config/backend_orders_config.dart';

/// Backend-backed email -> Firebase UID lookup.
abstract final class FirebaseUidResolver {
  static String _normEmail(String email) => email.trim().toLowerCase();

  /// Resolves a Firebase UID from backend `/auth/resolve-uid`.
  static Future<String> resolveUidByEmail(String email) async {
    final key = _normEmail(email);
    if (key.isEmpty) return '';
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return '';
      final token = await user.getIdToken();
      final base = BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
      final uri = Uri.parse('$base/auth/resolve-uid?email=${Uri.encodeComponent(key)}');
      final response = await http.get(
        uri,
        headers: <String, String>{'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) return '';
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final uid = decoded['firebase_uid']?.toString().trim() ?? '';
        return uid;
      }
    } on Object catch (e) {
      debugPrint('[UidResolver] failed: $e');
    }
    return '';
  }
}
