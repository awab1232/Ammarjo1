import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../features/store/domain/models.dart';
import 'email_service.dart';
import '../firebase/users_repository.dart';
import 'backend_orders_client.dart';

/// Ã™â€¦Ã˜ÂµÃ˜Â§Ã˜Â¯Ã™â€šÃ˜Â© Firebase + Ã™â€¦Ã˜Â²Ã˜Â§Ã™â€¦Ã™â€ Ã˜Â© Ã™Ë†Ã˜Â«Ã™Å Ã™â€šÃ˜Â© `users/{uid}` Ã™â€¦Ã˜Â¹ [UsersRepository].
abstract final class AuthService {
  AuthService._();

  static FirebaseAuth get _auth => FirebaseAuth.instance;

  static User? get currentUser => _auth.currentUser;

  static String? get currentUid => _auth.currentUser?.uid;

  static Stream<User?> authStateChanges() => _auth.authStateChanges();

  static Stream<User?> userChanges() => _auth.userChanges();

  static Future<void> signOut() => _auth.signOut();

  /// Ã™Å Ã˜Â­Ã˜Â¯Ã™â€˜Ã˜Â« `users/{uid}` Ã™â€¦Ã™â€  [CustomerProfile] Ã™â€žÃ™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜Â¬Ã™â€˜Ã™â€ž Ã˜Â­Ã˜Â§Ã™â€žÃ™Å Ã˜Â§Ã™â€¹.
  static Future<void> syncUserDocumentFromProfile(CustomerProfile profile) async {
    if (Firebase.apps.isEmpty) return;
    if (_auth.currentUser == null) return;
    await UsersRepository.syncUserDocument(profile);
  }

  /// Ã™Å Ã˜Â²Ã™Å Ã˜Â¯ Ã™â€ Ã™â€šÃ˜Â§Ã˜Â· Ã˜Â§Ã™â€žÃ™Ë†Ã™â€žÃ˜Â§Ã˜Â¡ Ã™â€žÃ™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã˜Â¯Ã˜Â¯ (Ã˜Â·Ã™â€žÃ˜Â¨Ã˜Â§Ã˜Âª Ã™â€¦Ã™Æ’Ã˜ÂªÃ™â€¦Ã™â€žÃ˜Â©Ã˜Å’ Ã˜Â¥Ã™â€žÃ˜Â®).
  static Future<void> incrementLoyaltyPoints(String uid, int amount) async {
    if (Firebase.apps.isEmpty) return;
    await UsersRepository.incrementPoints(uid, amount);
  }

  /// Ã™Å Ã˜Â¬Ã™â€žÃ˜Â¨ Ã™â€¦Ã™â€žÃ™Â Ã˜Â§Ã™â€žÃ˜Â¹Ã™â€¦Ã™Å Ã™â€ž Ã™â€¦Ã™â€  `users/{uid}`.
  static Future<CustomerProfile?> fetchCustomerProfile(String uid) async {
    if (Firebase.apps.isEmpty) throw StateError('NULL_RESPONSE');
    return UsersRepository.fetchProfileDocument(uid);
  }

  static Future<UserCredential> signInWithCredential(AuthCredential credential) =>
      _auth.signInWithCredential(credential);

  static Future<void> reloadCurrentUser() async {
    await _auth.currentUser?.reload();
  }

  static Future<void> sendPasswordResetEmail(String email) async {
    final target = email.trim();
    if (target.isEmpty) return;
    await _auth.sendPasswordResetEmail(email: target);
    try {
      await EmailService.instance.sendPasswordReset(
        target,
        'Ã˜ÂªÃ™â€¦ Ã˜Â¥Ã˜Â±Ã˜Â³Ã˜Â§Ã™â€ž Ã˜Â±Ã˜Â§Ã˜Â¨Ã˜Â· Ã˜Â¥Ã˜Â¹Ã˜Â§Ã˜Â¯Ã˜Â© Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â¹Ã™Å Ã™Å Ã™â€  Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â³Ã™â€¦Ã™Å  Ã™â€¦Ã™â€  Firebase Ã˜Â¥Ã™â€žÃ™â€° Ã˜Â¨Ã˜Â±Ã™Å Ã˜Â¯Ã™Æ’.',
      );
    } on Object {
      debugPrint('AuthService.sendPasswordResetEmail email notification failed');
    }
  }

  static Future<Map<String, dynamic>?> getCurrentUserWithRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('NULL_RESPONSE');
    try {
      final me = await BackendOrdersClient.instance.fetchAuthMe();
      if (me == null) throw StateError('NULL_RESPONSE');
      return <String, dynamic>{
        'uid': me.userId,
        'email': me.email,
        'role': me.role,
        'storeId': me.storeId,
        'storeType': me.storeType,
      };
    } on Object {
      debugPrint('Error fetching user role');
      throw StateError('NULL_RESPONSE');
    }
  }
}

