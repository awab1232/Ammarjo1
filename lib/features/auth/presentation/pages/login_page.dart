import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../store/presentation/pages/phone_otp_login_page.dart';
import '../../../store/presentation/pages/register_page.dart';
import '../../../store/presentation/store_controller.dart';

/// بوابة الدخول: **تسجيل جديد** (OTP) مقابل **تسجيل الدخول** (هاتف + كلمة مرور).
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
        title: Text('الدخول إلى AmmarJo', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
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
              'للمستخدمين الجدد: اختر تسجيل جديد (تحقق OTP). للحسابات الموجودة: تسجيل الدخول برقم الجوال وكلمة المرور المحفوظة على الخادم.',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(
                fontSize: 14,
                color: AppColors.textPrimary,
                height: 1.6,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: store.isLoading
                ? null
                : () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (_) => const RegisterPage()),
                    );
                  },
            icon: const Icon(Icons.person_add_rounded),
            label: Text(
              'تسجيل جديد (OTP)',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
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
              'تسجيل الدخول (رقم + كلمة المرور)',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
