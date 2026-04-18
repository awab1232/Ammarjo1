import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../store_controller.dart';
import 'forgot_password_page.dart';
import 'phone_otp_login_page.dart';
import 'register_page.dart';

/// شاشة بوابة تسجيل الدخول — تسجيل الدخول عبر رقم الهاتف + كلمة المرور،
/// ورمز OTP عند إنشاء حساب جديد أو عند استعادة كلمة المرور.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreController>();
    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop() ? const AppBarBackButton() : null,
        title: Text('تسجيل الدخول', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'سجّل دخولك برقم الهاتف وكلمة المرور. رمز التحقق OTP يُستخدم عند إنشاء حساب جديد أو عند نسيان كلمة المرور.',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(
                fontSize: 14,
                color: AppColors.textPrimary,
                height: 1.6,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 18),

          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: store.isLoading
                ? null
                : () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (_) => const PhoneOtpLoginPage()),
                    );
                  },
            icon: const Icon(Icons.lock_rounded),
            label: Text(
              'الدخول برقم الهاتف وكلمة المرور',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: store.isLoading
                ? null
                : () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (_) => const ForgotPasswordPage()),
                    );
                  },
            child: Text(
              'نسيت كلمة المرور؟',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),

          TextButton(
            onPressed: store.isLoading
                ? null
                : () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (_) => const RegisterPage()),
                    );
                  },
            child: Text(
              'ليس لديك حساب؟ إنشاء حساب جديد',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: AppColors.orange, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
