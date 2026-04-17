import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Firestore-backed email -> Firebase UID lookup.
///
/// Lives under `features/communication/` because the architecture contract
/// (enforced by `test/contracts/firestore_scope_contract_test.dart`) restricts
/// `package:cloud_firestore` imports to this folder. Any layer that needs an
/// email -> UID lookup must depend on this resolver instead of importing
/// Firestore directly.
abstract final class FirebaseUidResolver {
  /// Canonicalise an email so it can be used as a Firestore document id in
  /// the `firebase_uid_by_email` collection.
  static String _normEmail(String email) => email.trim().toLowerCase();

  /// Resolves a Firebase UID from an email. Returns an empty string when no
  /// mapping is found so the caller can safely skip sending the notification.
  static Future<String> resolveUidByEmail(String email) async {
    final key = _normEmail(email);
    if (key.isEmpty) return '';
    final db = FirebaseFirestore.instance;
    try {
      final snap = await db.collection('firebase_uid_by_email').doc(key).get();
      final mapped = snap.data()?['uid']?.toString() ?? '';
      if (mapped.isNotEmpty) return mapped;
    } on Object catch (e) {
      debugPrint('FirebaseUidResolver.resolveUidByEmail map lookup failed: $e');
    }
    try {
      final q = await db.collection('users').where('email', isEqualTo: key).limit(1).get();
      if (q.docs.isEmpty) return '';
      final data = q.docs.first.data();
      final u = (data['uid'] as String?) ?? q.docs.first.id;
      return u;
    } on Object catch (e) {
      debugPrint('FirebaseUidResolver.resolveUidByEmail users fallback failed: $e');
      return '';
    }
  }
}
