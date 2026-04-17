import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../store_controller.dart';
import 'phone_otp_login_page.dart';
import 'register_page.dart';

/// تسجيل دخول موحّد عبر رقم الهاتف + OTP فقط.
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
                'تسجيل الدخول متاح فقط عبر رقم الهاتف ورمز التحقق (OTP).',
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

            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.navy,
                side: const BorderSide(color: AppColors.navy, width: 1.2),
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
              icon: const Icon(Icons.phone_android_outlined),
              label: Text(
                'الدخول برمز التحقق (OTP)',
                style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
            const SizedBox(height: 16),

            TextButton(
              onPressed: store.isLoading
                  ? null
                  : () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(builder: (_) => const RegisterPage()),
                      );
                    },
              child: Text(
                'ليس لديك حساب؟ إنشاء حساب',
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(color: AppColors.orange, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
    );
  }
}
