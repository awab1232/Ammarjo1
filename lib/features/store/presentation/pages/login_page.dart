import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../store_controller.dart';
import 'forgot_password_page.dart';
import 'register_page.dart';

/// شاشة بوابة تسجيل الدخول بالبريد الإلكتروني وكلمة المرور فقط.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

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
              'استخدم البريد الإلكتروني وكلمة المرور لتسجيل الدخول.',
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
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'البريد الإلكتروني',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) async {
              if (store.isLoading) return;
              final ok = await context.read<StoreController>().signInWithEmailPassword(
                    _emailCtrl.text.trim(),
                    _passwordCtrl.text,
                  );
              if (!context.mounted) return;
              if (ok) Navigator.of(context).pop();
            },
            decoration: InputDecoration(
              labelText: 'كلمة المرور',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),

          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: store.isLoading
                ? null
                : () async {
                    final ok = await context.read<StoreController>().signInWithEmailPassword(
                          _emailCtrl.text.trim(),
                          _passwordCtrl.text,
                        );
                    if (!context.mounted) return;
                    if (ok) Navigator.of(context).pop();
                  },
            icon: const Icon(Icons.email_outlined),
            label: Text(
              'تسجيل دخول',
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
              'ليس لديك حساب؟ تسجيل حساب',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: AppColors.orange, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
