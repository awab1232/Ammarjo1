import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../../core/data/repositories/user_repository.dart';
import '../../../../core/firebase/chat_firebase_sync.dart';
import '../../../../core/utils/jordan_phone.dart';
import '../../../../core/firebase/users_repository.dart';
import '../../../../core/session/user_session.dart';
import '../../data/local_storage_service.dart';
import '../../domain/models.dart';

/// ملف المستخدم، الحظر الفوري، ومزامنة Firestore.
class UserController extends ChangeNotifier {
  UserController(this._local);

  final LocalStorageService _local;

  Timer? _userBannedPoll;
  bool _banEventHandled = false;

  /// يُسجَّل من [MainNavigationPage] لعرض حوار الحظر.
  Future<void> Function()? onBannedByAdmin;

  CustomerProfile? profile;

  Future<bool> isUserBannedInFirestore() async {
    if (!Firebase.apps.isNotEmpty) return false;
    final uid = UserSession.currentUid;
    if (uid.isEmpty) return false;
    try {
      return await BackendUserRepository.instance.isUserBanned(uid);
    } on Object {
      return false;
    }
  }

  void cancelBannedSubscription() {
    _userBannedPoll?.cancel();
    _userBannedPoll = null;
    _banEventHandled = false;
  }

  /// Poll `banned` on `users/{uid}` (no Firestore snapshot stream in app layer).
  void attachUserBannedListener(String uid) {
    cancelBannedSubscription();
    if (!Firebase.apps.isNotEmpty || uid.isEmpty) return;
    Future<void> tick() async {
      final banned = await BackendUserRepository.instance.isUserBanned(uid);
      if (banned) {
        if (!_banEventHandled) {
          _banEventHandled = true;
          final fn = onBannedByAdmin;
          if (fn != null) {
            unawaited(fn());
          }
        }
      } else {
        _banEventHandled = false;
      }
    }

    unawaited(tick());
    _userBannedPoll = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(tick()));
  }

  Future<void> syncLocalProfileWithFirebaseSession() async {
    final uid = UserSession.currentUid;
    if (uid.isEmpty) return;

    final authEmail = UserSession.currentEmail;
    if (authEmail.isNotEmpty && !authEmail.endsWith('@phone.ammarjo.app')) {
      final saved = await _local.getProfile();
      final pts = await _local.loyaltyPointsForEmail(authEmail);
      final remote = await UsersRepository.fetchProfileDocument(uid);
      if (remote != null) {
        profile = remote.copyWith(
          loyaltyPoints: pts,
          token: saved?.token,
          fullName: remote.fullName?.trim().isNotEmpty == true ? remote.fullName : saved?.fullName,
          firstName: remote.firstName?.trim().isNotEmpty == true ? remote.firstName : saved?.firstName,
          lastName: remote.lastName?.trim().isNotEmpty == true ? remote.lastName : saved?.lastName,
          phoneLocal: remote.phoneLocal?.trim().isNotEmpty == true ? remote.phoneLocal : saved?.phoneLocal,
          addressLine: remote.addressLine?.trim().isNotEmpty == true ? remote.addressLine : saved?.addressLine,
          city: remote.city?.trim().isNotEmpty == true ? remote.city : saved?.city,
          country: remote.country?.trim().isNotEmpty == true ? remote.country : saved?.country,
          contactEmail: remote.contactEmail?.trim().isNotEmpty == true ? remote.contactEmail : saved?.contactEmail,
        );
      } else {
        profile = CustomerProfile(
          email: authEmail,
          token: saved?.token,
          fullName: saved?.fullName,
          loyaltyPoints: pts,
          firstName: saved?.firstName,
          lastName: saved?.lastName,
          phoneLocal: saved?.phoneLocal,
          addressLine: saved?.addressLine,
          city: saved?.city,
          country: saved?.country ?? 'JO',
        );
      }
      await _local.saveProfile(profile!);
      await syncChatFirebaseIdentity(profile);
      notifyListeners();
      attachUserBannedListener(uid);
      return;
    }

    var uname = normalizeJordanPhoneForUsername(UserSession.currentPhone);
    if (uname.isEmpty || !uname.startsWith('962')) {
      uname = '';
    }
    if (uname.isEmpty) {
      uname = _jordanUsernameFromSyntheticEmail(authEmail) ?? '';
    }
    if (uname.isEmpty) return;
    final email = syntheticEmailForPhone(uname);
    final saved = await _local.getProfile();
    final pts = await _local.loyaltyPointsForEmail(email);
    final remote = await UsersRepository.fetchProfileDocument(uid);
    if (remote != null) {
      profile = remote.copyWith(
        loyaltyPoints: pts,
        token: saved?.token,
        fullName: remote.fullName?.trim().isNotEmpty == true ? remote.fullName : saved?.fullName,
        firstName: remote.firstName?.trim().isNotEmpty == true ? remote.firstName : saved?.firstName,
        lastName: remote.lastName?.trim().isNotEmpty == true ? remote.lastName : saved?.lastName,
        phoneLocal: remote.phoneLocal?.trim().isNotEmpty == true ? remote.phoneLocal : saved?.phoneLocal,
        addressLine: remote.addressLine?.trim().isNotEmpty == true ? remote.addressLine : saved?.addressLine,
        city: remote.city?.trim().isNotEmpty == true ? remote.city : saved?.city,
        country: remote.country?.trim().isNotEmpty == true ? remote.country : saved?.country,
        contactEmail: remote.contactEmail?.trim().isNotEmpty == true ? remote.contactEmail : saved?.contactEmail,
      );
    } else {
      profile = CustomerProfile(
        email: email,
        token: saved?.token,
        fullName: saved?.fullName,
        loyaltyPoints: pts,
        firstName: saved?.firstName,
        lastName: saved?.lastName,
        phoneLocal: saved?.phoneLocal,
        addressLine: saved?.addressLine,
        city: saved?.city,
        country: saved?.country,
      );
    }
    await _local.saveProfile(profile!);
    await syncChatFirebaseIdentity(profile);
    attachUserBannedListener(uid);
    notifyListeners();
  }

  Future<void> loadProfileFromUserData(Map<String, dynamic>? data) async {
    final remote = UsersRepository.customerProfileFromUserDocData(data);
    if (remote == null) return;
    final saved = await _local.getProfile();
    final pts = await _local.loyaltyPointsForEmail(remote.email);
    profile = remote.copyWith(
      loyaltyPoints: pts,
      token: saved?.token,
      fullName: remote.fullName?.trim().isNotEmpty == true ? remote.fullName : saved?.fullName,
      firstName: remote.firstName?.trim().isNotEmpty == true ? remote.firstName : saved?.firstName,
      lastName: remote.lastName?.trim().isNotEmpty == true ? remote.lastName : saved?.lastName,
      phoneLocal: remote.phoneLocal?.trim().isNotEmpty == true ? remote.phoneLocal : saved?.phoneLocal,
      addressLine: remote.addressLine?.trim().isNotEmpty == true ? remote.addressLine : saved?.addressLine,
      city: remote.city?.trim().isNotEmpty == true ? remote.city : saved?.city,
      country: remote.country?.trim().isNotEmpty == true ? remote.country : saved?.country,
      contactEmail: remote.contactEmail?.trim().isNotEmpty == true ? remote.contactEmail : saved?.contactEmail,
    );
    await _local.saveProfile(profile!);
    await syncChatFirebaseIdentity(profile);
    notifyListeners();
  }

  String? _jordanUsernameFromSyntheticEmail(String? email) {
    if (email == null || !email.endsWith('@phone.ammarjo.app')) return null;
    final id = email.split('@').first.trim();
    if (id.length >= 12 && id.startsWith('962')) return id;
    return null;
  }

  Future<void> clearSessionProfile() async {
    cancelBannedSubscription();
    if (Firebase.apps.isNotEmpty) {
      try {
        await FirebaseAuth.instance.signOut();
      } on Object {
        return;
      }
    }
    profile = null;
    await _local.clearProfile();
    notifyListeners();
  }

  @override
  void dispose() {
    cancelBannedSubscription();
    super.dispose();
  }
}
