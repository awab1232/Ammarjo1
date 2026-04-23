import 'package:firebase_auth/firebase_auth.dart';

import '../utils/jordan_phone.dart';
import 'phone_auth_service.dart';

/// تغيير كلمة المرور أو ربطها لأول مرة (حسابات الهاتف تستخدم بريداً تركيبياً `...@phone.ammarjo.app`).
abstract final class AccountPasswordService {
  static const String _passwordProviderId = 'password';

  /// يعتمد على [User.email] أو رقم الهاتف المرتبط بالحساب لبناء البريد التركيبي.
  static String? authEmailForCurrentUser(User? u) {
    if (u == null) return null;
    final direct = u.email?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final un = PhoneAuthService.jordanUsernameFromFirebaseUser(u);
    if (un != null && un.isNotEmpty) return syntheticEmailForPhone(un);
    return null;
  }

  /// هل مرتبط مزوّد كلمة المرور (بريد/كلمة مرور)؟
  static bool userHasPasswordLinked(User? u) {
    if (u == null) return false;
    return u.providerData.any((p) => p.providerId == _passwordProviderId);
  }

  /// Helper for UI layers to avoid reading FirebaseAuth directly.
  static bool currentUserHasPasswordLinked() {
    return userHasPasswordLinked(FirebaseAuth.instance.currentUser);
  }

  /// إعادة المصادقة بكلمة المرور الحالية ثم [User.updatePassword].
  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      throw FirebaseAuthException(code: 'no-current-user', message: 'لا يوجد مستخدم مسجّل.');
    }
    if (!userHasPasswordLinked(u)) {
      throw FirebaseAuthException(
        code: 'no-password-provider',
        message: 'لم يُربط حسابك بكلمة مرور بعد. استخدم «تعيين كلمة المرور».',
      );
    }
    final email = authEmailForCurrentUser(u);
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(code: 'no-email', message: 'تعذر تحديد بريد الحساب.');
    }
    final cred = EmailAuthProvider.credential(email: email, password: currentPassword);
    await u.reauthenticateWithCredential(cred);
    await u.updatePassword(newPassword);
  }

  /// أول ربط لكلمة المرور لحساب هاتف فقط (بدون كلمة مرور سابقة).
  static Future<void> linkInitialPassword({
    required String newPassword,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      throw FirebaseAuthException(code: 'no-current-user', message: 'لا يوجد مستخدم مسجّل.');
    }
    if (userHasPasswordLinked(u)) {
      throw FirebaseAuthException(
        code: 'password-already-linked',
        message: 'الحساب مرتبط بكلمة مرور. استخدم «تغيير كلمة المرور».',
      );
    }
    final email = authEmailForCurrentUser(u);
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'no-email',
        message: 'تعذر تحديد معرّف الحساب. تأكد من تسجيل الدخول برقم الهاتف.',
      );
    }
    final cred = EmailAuthProvider.credential(email: email, password: newPassword);
    await u.linkWithCredential(cred);
  }

  /// بعد التحقق بالهاتف (OTP) في مسار استعادة كلمة المرور: تعيين كلمة جديدة دون كلمة قديمة.
  static Future<void> setPasswordAfterPhoneOtpRecovery(String newPassword) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      throw FirebaseAuthException(code: 'no-current-user', message: 'لا يوجد مستخدم مسجّل.');
    }
    if (userHasPasswordLinked(u)) {
      await u.updatePassword(newPassword);
    } else {
      await linkInitialPassword(newPassword: newPassword);
    }
  }

  static String userFacingMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'كلمة المرور الحالية غير صحيحة.';
      case 'weak-password':
        return 'كلمة المرور الجديدة ضعيفة. استخدم 6 أحرف على الأقل.';
      case 'requires-recent-login':
        return 'انتهت صلاحية الجلسة. سجّل الخروج ثم أعد الدخول وحاول مرة أخرى.';
      case 'credential-already-in-use':
        return 'هذا البريد مستخدم بحساب آخر.';
      case 'provider-already-linked':
        return 'تم ربط كلمة المرور مسبقاً. استخدم «تغيير كلمة المرور».';
      case 'no-password-provider':
      case 'password-already-linked':
      case 'no-current-user':
      case 'no-email':
        return e.message ?? e.code;
      default:
        return e.message?.trim().isNotEmpty == true ? e.message! : 'تعذر إتمام العملية (unexpected error).';
    }
  }
}
