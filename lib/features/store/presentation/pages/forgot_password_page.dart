import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/firebase/phone_auth_service.dart';
import '../../../../core/services/phone_password_auth_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/jordan_phone.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import 'phone_otp_login_page.dart';

enum _ForgotStep { phone, otp, newPassword }

/// استعادة كلمة المرور: هاتف → OTP → كلمة مرور جديدة → `POST /auth/forgot-password`.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formPhone = GlobalKey<FormState>();
  final _formOtp = GlobalKey<FormState>();
  final _formPwd = GlobalKey<FormState>();

  final _phoneLocal = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _otpFocus = FocusNode();

  _ForgotStep _step = _ForgotStep.phone;
  bool _submitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  String? _verificationId;
  int? _resendToken;
  Timer? _resendTimer;
  int _resendCountdown = 0;
  static const int _resendCooldownSeconds = 60;

  String get _phoneE164 => '+962${_phoneLocal.text.trim()}';

  @override
  void dispose() {
    _phoneLocal.dispose();
    _otpCtrl.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _otpFocus.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

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

  Future<void> _sendOtp({bool resend = false}) async {
    if (!resend && !(_formPhone.currentState?.validate() ?? false)) return;
    if (Firebase.apps.isEmpty) {
      setState(() => _error = 'خطأ في تهيئة Firebase.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await PhoneAuthService.startVerification(
        _phoneE164,
        forceResendingToken: resend ? _resendToken : null,
      );
      if (!mounted) return;
      if (result.verificationId == PhoneAuthService.autoVerifiedSentinel) {
        setState(() {
          _step = _ForgotStep.newPassword;
          _submitting = false;
        });
        return;
      }
      setState(() {
        _verificationId = result.verificationId;
        _resendToken = result.resendToken;
        _step = _ForgotStep.otp;
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
        _error = 'حدث خطأ: $e';
        _submitting = false;
      });
    }
  }

  Future<void> _verifyOtpAndGoToPassword() async {
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
      setState(() {
        _step = _ForgotStep.newPassword;
        _submitting = false;
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
        _error = 'حدث خطأ: $e';
        _submitting = false;
      });
    }
  }

  Future<void> _submitNewPassword() async {
    if (!(_formPwd.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await PhonePasswordAuthService.forgotPasswordUpdate(
        phone: _phoneE164,
        password: _password.text,
      );
      if (!mounted) return;
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تغيير كلمة المرور. سجّل الدخول بالرقم وكلمة المرور الجديدة.',
            style: GoogleFonts.tajawal(),
          ),
        ),
      );
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const PhoneOtpLoginPage()),
        (_) => false,
      );
    } on PhonePasswordAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.messageAr;
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

  Widget _errorBanner(String msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Text(
        msg,
        textAlign: TextAlign.right,
        style: GoogleFonts.tajawal(color: Colors.red.shade800, fontSize: 13, height: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const AppBarBackButton(),
        title: Text(
          _step == _ForgotStep.phone
              ? 'نسيت كلمة المرور'
              : _step == _ForgotStep.otp
                  ? 'رمز التحقق'
                  : 'كلمة مرور جديدة',
          style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.heading,
      ),
      body: switch (_step) {
        _ForgotStep.phone => _buildPhoneStep(),
        _ForgotStep.otp => _buildOtpStep(),
        _ForgotStep.newPassword => _buildPasswordStep(),
      },
    );
  }

  Widget _buildPhoneStep() {
    return Form(
      key: _formPhone,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'أدخل رقم الجوال المسجّل لدينا. سنرسل رمز تحقق لتعيين كلمة مرور جديدة.',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(fontSize: 14, height: 1.5, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 20),
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
                      labelText: 'رقم الجوال',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'مطلوب';
                      if (!isValidJordanMobileLocal(v)) return 'رقم أردني صحيح (9 أرقام تبدأ بـ 7)';
                      return null;
                    },
                  ),
                ),
              ],
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
            onPressed: _submitting ? null : () => _sendOtp(),
            child: _submitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text('إرسال رمز التحقق', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpStep() {
    return Form(
      key: _formOtp,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        children: [
          Text(
            'أُرسل رمز إلى\n$_phoneE164',
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _otpCtrl,
            focusNode: _otpFocus,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.tajawal(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 8),
            decoration: InputDecoration(
              counterText: '',
              hintText: '• • • • • •',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (v) {
              if (v.length == 6) _verifyOtpAndGoToPassword();
            },
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
            onPressed: _submitting ? null : _verifyOtpAndGoToPassword,
            child: _submitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text('متابعة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _submitting || _resendCountdown > 0
                    ? null
                    : () => _sendOtp(resend: true),
                child: Text(
                  _resendCountdown > 0 ? 'إعادة الإرسال ($_resendCountdown)' : 'إعادة إرسال الرمز',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => setState(() {
                          _step = _ForgotStep.phone;
                          _otpCtrl.clear();
                          _error = null;
                          _resendTimer?.cancel();
                          _resendCountdown = 0;
                        }),
                child: Text('تغيير الرقم', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordStep() {
    return Form(
      key: _formPwd,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        children: [
          Text(
            'اختر كلمة مرور قوية (6 أحرف على الأقل).',
            textAlign: TextAlign.right,
            style: GoogleFonts.tajawal(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _password,
            textAlign: TextAlign.right,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'كلمة المرور الجديدة',
              prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.orange),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppColors.textSecondary,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmPassword,
            textAlign: TextAlign.right,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'تأكيد كلمة المرور',
              prefixIcon: const Icon(Icons.lock_rounded, color: AppColors.orange),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppColors.textSecondary,
                ),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
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
          const SizedBox(height: 20),
          if (_error != null) _errorBanner(_error!),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _submitting ? null : _submitNewPassword,
            child: _submitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text('حفظ كلمة المرور', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
