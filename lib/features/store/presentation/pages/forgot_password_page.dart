import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import 'login_page.dart';

/// استعادة كلمة المرور بالبريد الإلكتروني فقط.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _email.text.trim();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم إرسال رابط إعادة تعيين كلمة المرور إلى بريدك الإلكتروني.',
            style: GoogleFonts.tajawal(),
          ),
        ),
      );
      Navigator.of(context).pushReplacement<void>(
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'تعذر إرسال رابط إعادة التعيين.');
    } on Object catch (e) {
      setState(() => _error = 'تعذر إرسال رابط إعادة التعيين: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
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
        title: Text('نسيت كلمة المرور', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.heading,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Form(
      key: _formKey,
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
              'أدخل البريد الإلكتروني المرتبط بحسابك لإرسال رابط إعادة تعيين كلمة المرور.',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(fontSize: 14, height: 1.5, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              labelText: 'البريد الإلكتروني',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) return 'مطلوب';
              return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'صيغة بريد غير صحيحة';
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
            onPressed: _submitting ? null : _sendResetLink,
            child: _submitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text('إرسال رابط إعادة التعيين', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
