import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/firebase/phone_auth_service.dart';
import '../../../../core/routing/role_home_resolver.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import 'main_navigation_page.dart';

/// تسجيل الدخول برقم الهاتف (OTP عبر Firebase Phone Auth).
/// يدعم أرقام الأردن بصيغة 07XXXXXXXX أو +9627XXXXXXXX.
class PhoneOtpLoginPage extends StatefulWidget {
  const PhoneOtpLoginPage({super.key});

  @override
  State<PhoneOtpLoginPage> createState() => _PhoneOtpLoginPageState();
}

class _PhoneOtpLoginPageState extends State<PhoneOtpLoginPage> {
  // ─── State ───────────────────────────────────────────────────────────────
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _phoneFocus = FocusNode();
  final _otpFocus = FocusNode();

  bool _loading = false;
  bool _codeSent = false;
  String? _verificationId;
  int? _resendToken;
  String? _error;

  /// Countdown seconds before user can resend OTP.
  int _resendCountdown = 0;
  Timer? _resendTimer;

  static const int _resendCooldownSeconds = 60;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _phoneFocus.dispose();
    _otpFocus.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('9627') && digits.length == 12) return '+$digits';
    if (digits.startsWith('07') && digits.length == 10) return '+962${digits.substring(1)}';
    if (digits.startsWith('7') && digits.length == 9) return '+962$digits';
    return '+$digits';
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

  // ─── Actions ─────────────────────────────────────────────────────────────

  Future<void> _sendOtp({bool resend = false}) async {
    final raw = _phoneCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'أدخل رقم الهاتف');
      return;
    }
    final e164 = _normalizePhone(raw);
    if (!PhoneAuthService.isValidE164Jordan(e164)) {
      setState(() => _error = 'رقم الهاتف غير صحيح. استخدم صيغة 07XXXXXXXX');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await PhoneAuthService.startVerification(
        e164,
        forceResendingToken: resend ? _resendToken : null,
      );

      if (!mounted) return;

      if (result.verificationId == PhoneAuthService.autoVerifiedSentinel) {
        await _onAutoVerified();
        return;
      }

      setState(() {
        _verificationId = result.verificationId;
        _resendToken = result.resendToken;
        _codeSent = true;
        _loading = false;
      });
      _startResendCountdown();
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _otpFocus.requestFocus();
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = PhoneAuthService.userFacingMessage(e);
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'حدث خطأ غير متوقع: $e';
        _loading = false;
      });
    }
  }

  Future<void> _verifyOtp() async {
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
      _loading = true;
      _error = null;
    });

    try {
      await PhoneAuthService.signInWithSmsCode(verificationId: vid, smsCode: code);
      if (!mounted) return;
      await _navigateAfterLogin();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = PhoneAuthService.userFacingMessage(e);
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'حدث خطأ: $e';
        _loading = false;
      });
    }
  }

  Future<void> _onAutoVerified() async {
    if (!mounted) return;
    setState(() => _loading = true);
    await _navigateAfterLogin();
  }

  Future<void> _navigateAfterLogin() async {
    final user = FirebaseAuth.instance.currentUser;
    final Widget home =
        user != null ? await resolveHomeForSignedInUser(user) : const MainNavigationPage();
    if (!mounted) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: (_) => home),
      (_) => false,
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const AppBarBackButton(),
        title: Text('الدخول برمز التحقق', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.heading,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header illustration
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(Icons.phone_android_rounded, size: 56, color: AppColors.orange),
                  const SizedBox(height: 12),
                  Text(
                    _codeSent ? 'أدخل رمز التحقق' : 'أدخل رقم هاتفك',
                    style: GoogleFonts.tajawal(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _codeSent
                        ? 'أُرسل رمز مكوّن من 6 أرقام إلى ${_phoneCtrl.text.trim()}'
                        : 'سنرسل لك رمز تحقق عبر رسالة نصية',
                    style: GoogleFonts.tajawal(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // Phone number field (always visible)
            Text(
              'رقم الهاتف',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phoneCtrl,
              focusNode: _phoneFocus,
              keyboardType: TextInputType.phone,
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(fontSize: 16),
              enabled: !_codeSent,
              decoration: InputDecoration(
                hintText: '07XXXXXXXX',
                hintStyle: GoogleFonts.tajawal(color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.orange),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
                fillColor: _codeSent ? Colors.grey.shade100 : Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),

            const SizedBox(height: 20),

            // OTP field (shown after code sent)
            if (_codeSent) ...[
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
                style: GoogleFonts.tajawal(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 8,
                  color: AppColors.navy,
                ),
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) {
                  if (v.length == 6) _verifyOtp();
                },
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '• • • • • •',
                  hintStyle: GoogleFonts.tajawal(
                    color: AppColors.textSecondary,
                    fontSize: 22,
                    letterSpacing: 6,
                  ),
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
              const SizedBox(height: 8),
            ],

            // Error display
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _error!,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(color: Colors.red.shade800, fontSize: 13, height: 1.4),
                ),
              ),

            const SizedBox(height: 4),

            // Primary action button
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _loading
                  ? null
                  : () {
                      if (_codeSent) {
                        _verifyOtp();
                      } else {
                        _sendOtp();
                      }
                    },
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _codeSent ? 'تحقق وادخل' : 'إرسال رمز التحقق',
                      style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
            ),

            const SizedBox(height: 12),

            // Resend / Change number options
            if (_codeSent)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() {
                              _codeSent = false;
                              _otpCtrl.clear();
                              _error = null;
                              _resendCountdown = 0;
                              _resendTimer?.cancel();
                            });
                          },
                    child: Text(
                      'تغيير الرقم',
                      style: GoogleFonts.tajawal(color: AppColors.navy, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_resendCountdown > 0)
                    Text(
                      'إعادة الإرسال بعد $_resendCountdownث',
                      style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 13),
                    )
                  else
                    TextButton(
                      onPressed: _loading ? null : () => _sendOtp(resend: true),
                      child: Text(
                        'إعادة إرسال الرمز',
                        style: GoogleFonts.tajawal(
                          color: AppColors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              )
            else
              Center(
                child: Text(
                  'الرمز صالح لمدة دقيقتين فقط.',
                  style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
