import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/routing/role_home_resolver.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../store_controller.dart';
import 'forgot_password_page.dart';
import 'main_navigation_page.dart';
import 'phone_otp_login_page.dart';
import 'register_page.dart';

/// تسجيل دخول — بالبريد الإلكتروني وكلمة المرور أو برمز OTP عبر الهاتف.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'أدخل البريد الإلكتروني';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
    return ok ? null : 'صيغة بريد غير صحيحة';
  }

  Future<void> _onLoginPressed(StoreController store) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await store.signInWithEmailPassword(
      _email.text.trim(),
      _password.text,
    );
    if (!mounted) return;
    if (ok) {
      final user = FirebaseAuth.instance.currentUser;
      final Widget home = user != null ? await resolveHomeForSignedInUser(user) : const MainNavigationPage();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => home),
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(store.errorMessage ?? 'تعذر المتابعة', textAlign: TextAlign.right, style: GoogleFonts.tajawal()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreController>();

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, _) {
        return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop() ? const AppBarBackButton() : null,
        title: Text('تسجيل الدخول', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'إذا سجّلت بـ OTP، استخدم "الدخول برمز التحقق" أدناه. البريد وكلمة المرور للحسابات المرتبطة ببريد إلكتروني فقط.',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 20),
            Text(
              'البريد الإلكتروني',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(),
              decoration: InputDecoration(
                hintText: 'example@email.com',
                hintStyle: GoogleFonts.tajawal(color: AppColors.textSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
              validator: _validateEmail,
            ),
            const SizedBox(height: 20),
            Text(
              'كلمة المرور',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _password,
              obscureText: _obscurePassword,
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(),
              decoration: InputDecoration(
                hintText: '••••••••',
                hintStyle: GoogleFonts.tajawal(color: AppColors.textSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'أدخل كلمة المرور';
                if (v.length < 6) return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                return null;
              },
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: store.isLoading
                    ? null
                    : () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(builder: (_) => const ForgotPasswordPage()),
                        );
                      },
                child: Text(
                  'نسيت كلمة المرور؟',
                  style: GoogleFonts.tajawal(color: AppColors.navy, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: store.isLoading ? null : () => _onLoginPressed(store),
              child: store.isLoading
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('دخول', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            const SizedBox(height: 16),

            // ── OTP divider ──────────────────────────────────────────────
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'أو',
                    style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 12),

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
      ),
        );
      },
    );
  }
}
