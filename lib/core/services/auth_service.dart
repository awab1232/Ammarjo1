import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../features/store/domain/models.dart';
import 'email_service.dart';
import '../firebase/users_repository.dart';
import 'backend_orders_client.dart';

/// ?????? Firebase + ?????? ????? `users/{uid}` ?? [UsersRepository].
abstract final class AuthService {
  AuthService._();

  static FirebaseAuth get _auth => FirebaseAuth.instance;

  static User? get currentUser => _auth.currentUser;

  static String? get currentUid => _auth.currentUser?.uid;

  static Stream<User?> authStateChanges() => _auth.authStateChanges();

  static Stream<User?> userChanges() => _auth.userChanges();

  static Future<void> signOut() => _auth.signOut();

  /// ????? `users/{uid}` ?? [CustomerProfile] ???????? ??????.
  static Future<void> syncUserDocumentFromProfile(CustomerProfile profile) async {
    if (Firebase.apps.isEmpty) return;
    if (_auth.currentUser == null) return;
    await UsersRepository.syncUserDocument(profile);
  }

  /// ???? ???? ?????? ???????? ??????.
  static Future<void> incrementLoyaltyPoints(String uid, int amount) async {
    if (Firebase.apps.isEmpty) return;
    await UsersRepository.incrementPoints(uid, amount);
  }

  /// ???? ??? ?????? ?? `users/{uid}`.
  static Future<CustomerProfile?> fetchCustomerProfile(String uid) async {
    if (Firebase.apps.isEmpty) return null;
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
        '?? ????? ???? ????? ????? ???? ?????? ?? Firebase ??? ????? ??????????.',
      );
    } on Object {
      debugPrint('AuthService.sendPasswordResetEmail email notification failed');
    }
  }

  static Future<Map<String, dynamic>?> getCurrentUserWithRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final me = await BackendOrdersClient.instance.fetchAuthMe();
      if (me == null) return null;
      return <String, dynamic>{
        'uid': me.userId,
        'email': me.email,
        'role': me.role,
        'storeId': me.storeId,
        'storeType': me.storeType,
      };
    } on Object {
      debugPrint('Error fetching user role');
      return null;
    }
  }
}

