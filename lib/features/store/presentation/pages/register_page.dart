import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../admin/data/admin_notification_repository.dart';
import '../../../../core/routing/role_home_resolver.dart';
import '../../../../core/data/repositories/user_repository.dart';
import '../../../../core/constants/jordan_cities.dart';
import '../../../../core/firebase/phone_auth_service.dart';
import '../../../../core/services/phone_password_auth_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/jordan_phone.dart';
import '../../../../core/widgets/app_bar_back_button.dart';

enum _RegistrationStep { profile, otp }

/// إنشاء حساب جديد — رقم الهاتف + رمز OTP (مطلوب) والبريد الإلكتروني اختياري.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController(); // optional
  final _phoneLocal = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _otpFocus = FocusNode();

  String _selectedCity = kJordanCities.first;
  _RegistrationStep _step = _RegistrationStep.profile;
  bool _submitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  String? _verificationId;
  int? _resendToken;
  Timer? _resendTimer;
  int _resendCountdown = 0;

  static const int _resendCooldownSeconds = 60;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phoneLocal.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _otpCtrl.dispose();
    _otpFocus.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  // ─── Countdown ────────────────────────────────────────────────────────────

  void _startResendCountdown() {
    _resendCountdown = _resendCooldownSeconds;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendCountdown--;
        if (_resendCountdown <= 0) t.cancel();
      });
    });
  }

  // ─── Step 1: validate profile + send OTP ──────────────────────────────────

  Future<void> _onSendOtp({bool resend = false}) async {
    if (!resend && !(_formKey.currentState?.validate() ?? false)) return;
    if (Firebase.apps.isEmpty) {
      setState(() => _error = 'خطأ في تهيئة Firebase.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final phone = '+962${_phoneLocal.text.trim()}';
      final result = await PhoneAuthService.startVerification(
        phone,
        forceResendingToken: resend ? _resendToken : null,
      );
      if (!mounted) return;
      if (result.verificationId == PhoneAuthService.autoVerifiedSentinel) {
        // Android auto-verification — skip OTP step
        await _saveProfileAndNavigate();
        return;
      }
      setState(() {
        _verificationId = result.verificationId;
        _resendToken = result.resendToken;
        _step = _RegistrationStep.otp;
        _submitting = false;
      });
      _startResendCountdown();
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _otpFocus.requestFocus();
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = PhoneAuthService.userFacingMessage(e);
        _submitting = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'حدث خطأ غير متوقع: $e';
        _submitting = false;
      });
    }
  }

  // ─── Step 2: verify OTP + save profile ────────────────────────────────────

  Future<void> _onVerifyOtp() async {
    final vid = _verificationId;
    if (vid == null) {
      setState(() => _error = 'أرسل الرمز أولاً');
      return;
    }
    final code = _otpCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'أدخل الرمز المكوّن من 6 أرقام');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await PhoneAuthService.signInWithSmsCode(verificationId: vid, smsCode: code);
      if (!mounted) return;
      await _saveProfileAndNavigate();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = PhoneAuthService.userFacingMessage(e);
        _submitting = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'حدث خطأ: $e';
        _submitting = false;
      });
    }
  }

  // ─── Save profile to backend ───────────────────────────────────────────────

  Future<void> _saveProfileAndNavigate() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _error = 'تعذر الحصول على معلومات المستخدم.';
        _submitting = false;
      });
      return;
    }
    final uid = user.uid;
    final fn = _firstName.text.trim();
    final ln = _lastName.text.trim();
    final fullName = '$fn $ln'.trim();
    final email = _email.text.trim();
    final phone = '+962${_phoneLocal.text.trim()}';

    final profileData = <String, dynamic>{
      'uid': uid,
      'firstName': fn,
      'lastName': ln,
      'fullName': fullName,
      'name': fullName,
      'phone': phone,
      'role': 'customer',
      'city': _selectedCity,
      'country': 'JO',
      'loyaltyPoints': 0,
      'fcmToken': '',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    // Email is optional — only include if provided
    if (email.isNotEmpty) {
      profileData['email'] = email;
    }

    try {
      await BackendUserRepository.instance.setInitialRegistrationDocument(uid, profileData);

      await AdminNotificationRepository.addNotification(
        message: 'مستخدم جديد: $fullName — $phone',
        type: 'new_user',
      );
    } on Object {
      // Non-fatal: profile save failed but Firebase auth succeeded — continue
    }

    // Attach phone + bcrypt(password) to the backend user row so future logins
    // can use phone + password (OTP is only used here to verify ownership).
    String? postCreateWarning;
    try {
      await PhonePasswordAuthService.setPasswordForCurrentUser(
        phone: phone,
        password: _password.text,
      );
    } on PhonePasswordAuthException catch (e) {
      postCreateWarning = 'تم إنشاء الحساب، لكن تعذر حفظ كلمة المرور الآن: ${e.messageAr}';
    } on Object {
      postCreateWarning = 'تم إنشاء الحساب، لكن تعذر حفظ كلمة المرور الآن. يمكنك المتابعة وإعادة تعيينها لاحقاً.';
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم إنشاء الحساب بنجاح 🎉', style: GoogleFonts.tajawal())),
    );
    if (postCreateWarning != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(postCreateWarning, style: GoogleFonts.tajawal())),
      );
    }

    final Widget home = await resolveHomeForSignedInUser(user);
    if (!mounted) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: (_) => home),
      (route) => false,
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: _step == _RegistrationStep.otp
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded),
                onPressed: _submitting
                    ? null
                    : () => setState(() {
                          _step = _RegistrationStep.profile;
                          _otpCtrl.clear();
                          _error = null;
                          _resendTimer?.cancel();
                          _resendCountdown = 0;
                        }),
              )
            : (Navigator.of(context).canPop() ? const AppBarBackButton() : null),
        title: Text(
          _step == _RegistrationStep.profile ? 'إنشاء حساب' : 'رمز التحقق',
          style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.heading,
      ),
      body: _step == _RegistrationStep.profile ? _buildProfileStep() : _buildOtpStep(),
    );
  }

  // ─── Step 1 UI ────────────────────────────────────────────────────────────

  Widget _buildProfileStep() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          // Header
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.person_add_rounded, size: 44, color: AppColors.orange),
                const SizedBox(height: 8),
                Text(
                  'أنشئ حسابك برقم هاتفك',
                  style: GoogleFonts.tajawal(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'رقم الهاتف مطلوب — البريد الإلكتروني اختياري',
                  style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // First name
          TextFormField(
            controller: _firstName,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              labelText: 'الاسم الأول *',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
          ),
          const SizedBox(height: 10),

          // Last name
          TextFormField(
            controller: _lastName,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              labelText: 'اسم العائلة *',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
          ),
          const SizedBox(height: 10),

          // Phone — required
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.orangeLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text('+962', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, color: AppColors.orange)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _phoneLocal,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(9),
                    ],
                    decoration: InputDecoration(
                      hintText: '7XXXXXXXX',
                      labelText: 'رقم الجوال *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'مطلوب';
                      if (!isValidJordanMobileLocal(v)) return 'رقم أردني صحيح (9 أرقام تبدأ بـ 7)';
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Email — optional
          TextFormField(
            controller: _email,
            textAlign: TextAlign.right,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'البريد الإلكتروني (اختياري)',
              hintText: 'example@email.com',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
              suffixIcon: const Icon(Icons.mail_outline_rounded, color: AppColors.textSecondary),
            ),
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) return null; // optional — allow empty
              final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
              return ok ? null : 'صيغة بريد غير صحيحة';
            },
          ),
          const SizedBox(height: 10),

          // Password — required
          TextFormField(
            controller: _password,
            textAlign: TextAlign.right,
            obscureText: _obscurePassword,
            enabled: !_submitting,
            decoration: InputDecoration(
              labelText: 'كلمة المرور *',
              hintText: '6 أحرف على الأقل',
              prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.orange),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppColors.textSecondary,
                ),
                onPressed: _submitting
                    ? null
                    : () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
            validator: (v) {
              final t = v ?? '';
              if (t.isEmpty) return 'مطلوب';
              if (t.length < 6) return '6 أحرف على الأقل';
              if (t.length > 128) return 'كلمة المرور طويلة جداً';
              return null;
            },
          ),
          const SizedBox(height: 10),

          // Confirm password
          TextFormField(
            controller: _confirmPassword,
            textAlign: TextAlign.right,
            obscureText: _obscureConfirm,
            enabled: !_submitting,
            decoration: InputDecoration(
              labelText: 'تأكيد كلمة المرور *',
              prefixIcon: const Icon(Icons.lock_rounded, color: AppColors.orange),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppColors.textSecondary,
                ),
                onPressed: _submitting
                    ? null
                    : () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
            validator: (v) {
              if ((v ?? '').isEmpty) return 'مطلوب';
              if (v != _password.text) return 'كلمتا المرور غير متطابقتين';
              return null;
            },
          ),
          const SizedBox(height: 10),

          // City
          DropdownButtonFormField<String>(
            value: _selectedCity,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'المدينة *',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
            items: kJordanCities
                .map(
                  (c) => DropdownMenuItem<String>(
                    value: c,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(c, style: GoogleFonts.tajawal()),
                    ),
                  ),
                )
                .toList(),
            onChanged: _submitting ? null : (v) { if (v != null) setState(() => _selectedCity = v); },
            validator: (v) => (v == null || v.isEmpty) ? 'اختر المدينة' : null,
          ),
          const SizedBox(height: 20),

          // Error banner
          if (_error != null) _errorBanner(_error!),

          // Submit — send OTP
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _submitting ? null : () => _onSendOtp(),
            icon: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(
              'إرسال رمز التحقق',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Step 2 UI ────────────────────────────────────────────────────────────

  Widget _buildOtpStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Icon(Icons.sms_rounded, size: 52, color: AppColors.orange),
                const SizedBox(height: 12),
                Text(
                  'تم إرسال رمز التحقق',
                  style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.navy),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'أُرسل رمز مكوّن من 6 أرقام إلى\n+962${_phoneLocal.text.trim()}',
                  style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          Text(
            'رمز التحقق',
            textAlign: TextAlign.right,
            style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),

          TextFormField(
            controller: _otpCtrl,
            focusNode: _otpFocus,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.tajawal(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 10, color: AppColors.navy),
            onChanged: (v) {
              if (v.length == 6) _onVerifyOtp();
            },
            decoration: InputDecoration(
              counterText: '',
              hintText: '• • • • • •',
              hintStyle: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 22, letterSpacing: 6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.orange, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.orange, width: 2),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            ),
          ),
          const SizedBox(height: 16),

          if (_error != null) _errorBanner(_error!),

          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _submitting ? null : _onVerifyOtp,
            child: _submitting
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('تحقق وأنشئ الحساب', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          const SizedBox(height: 16),

          // Resend / change number
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => setState(() {
                          _step = _RegistrationStep.profile;
                          _otpCtrl.clear();
                          _error = null;
                          _resendTimer?.cancel();
                          _resendCountdown = 0;
                        }),
                child: Text('تغيير الرقم', style: GoogleFonts.tajawal(color: AppColors.navy, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              if (_resendCountdown > 0)
                Text(
                  'إعادة الإرسال بعد $_resendCountdownث',
                  style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 13),
                )
              else
                TextButton(
                  onPressed: _submitting ? null : () => _onSendOtp(resend: true),
                  child: Text(
                    'إعادة إرسال الرمز',
                    style: GoogleFonts.tajawal(color: AppColors.orange, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Shared widgets ───────────────────────────────────────────────────────

  Widget _errorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Text(
        message,
        textAlign: TextAlign.right,
        style: GoogleFonts.tajawal(color: Colors.red.shade800, fontSize: 13, height: 1.4),
      ),
    );
  }
}
