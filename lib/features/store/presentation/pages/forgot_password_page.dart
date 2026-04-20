import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/firebase/phone_auth_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/utils/jordan_phone.dart';
import '../store_controller.dart';

/// نسيت كلمة المرور: هاتف → OTP → تعيين كلمة مرور جديدة (Firebase Auth + مزامنة الملف من Firestore).
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneLocal = TextEditingController();
  final _otp = TextEditingController();
  final _newPass = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _phoneLocal.dispose();
    _otp.dispose();
    _newPass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _sendOtp(StoreController store) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await store.sendPhoneVerificationCode(
      _phoneLocal.text.trim(),
      forgotPassword: true,
    );
    if (!mounted) return;
    if (ok) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إرسال رمز التحقق.', style: GoogleFonts.tajawal())),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.errorMessage ?? 'تعذر الإرسال', textAlign: TextAlign.right)),
      );
    }
  }

  Future<void> _submit(StoreController store) async {
    final vid = store.phoneVerificationId;
    if (vid == null) return;

    if (vid != PhoneAuthService.autoVerifiedSentinel && _otp.text.trim().length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('أدخل رمز التحقق.', style: GoogleFonts.tajawal())),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    final okVerify = vid == PhoneAuthService.autoVerifiedSentinel
        ? await store.verifyPhoneCode('', isRegistration: false, skipProfileFinalize: true)
        : await store.verifyPhoneCode(_otp.text.trim(), isRegistration: false, skipProfileFinalize: true);

    if (!mounted) return;
    if (!okVerify) {
      messenger.showSnackBar(
        SnackBar(content: Text(store.errorMessage ?? 'فشل التحقق', textAlign: TextAlign.right)),
      );
      return;
    }

    final ok = await store.finishForgotPasswordWithNewPassword(_newPass.text);
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(
        SnackBar(content: Text('تم تحديث كلمة المرور. يمكنك المتابعة.', style: GoogleFonts.tajawal())),
      );
      nav.pop();
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(store.errorMessage ?? 'تعذر التحديث', textAlign: TextAlign.right)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreController>();
    final awaiting = store.phoneVerificationId != null;
    final autoVerified = store.phoneVerificationId == PhoneAuthService.autoVerifiedSentinel;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: Navigator.of(context).canPop() ? const AppBarBackButton() : null,
        title: Text('نسيت كلمة المرور', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              awaiting
                  ? (autoVerified
                      ? 'تم التحقق تلقائياً. اختر كلمة مرور جديدة.'
                      : 'أدخل رمز SMS ثم كلمة المرور الجديدة.')
                  : 'أدخل رقم جوالك المسجّل لإرسال رمز التحقق وإعادة تعيين كلمة المرور.',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),
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
                      enabled: !awaiting,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                      decoration: InputDecoration(
                        hintText: '7XXXXXXXX',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'أدخل رقم الهاتف';
                        if (!isValidJordanMobileLocal(v)) return 'رقم أردني صحيح';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (awaiting && !autoVerified) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _otp,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(letterSpacing: 4, fontSize: 20),
                decoration: InputDecoration(
                  labelText: 'رمز التحقق',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ],
            if (awaiting) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _newPass,
                obscureText: true,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور الجديدة',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (v) => (v == null || v.length < 6) ? '6 أحرف على الأقل' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  labelText: 'تأكيد كلمة المرور',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (v) => v != _newPass.text ? 'غير متطابقة' : null,
              ),
            ],
            const SizedBox(height: 24),
            if (!awaiting)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: store.isLoading ? null : () => _sendOtp(store),
                child: store.isLoading
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('إرسال رمز التحقق', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
              )
            else
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: store.isLoading ? null : () => _submit(store),
                child: store.isLoading
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('حفظ كلمة المرور الجديدة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
              ),
            if (awaiting)
              TextButton(
                onPressed: store.isLoading
                    ? null
                    : () {
                        store.clearPhoneVerificationState();
                        setState(() {});
                      },
                child: Text('إلغاء', style: GoogleFonts.tajawal()),
              ),
          ],
        ),
      ),
    );
  }
}
