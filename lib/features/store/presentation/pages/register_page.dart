import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/routing/role_home_resolver.dart';
import '../../../../core/services/backend_user_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import 'login_page.dart';

/// إنشاء حساب جديد — بريد إلكتروني + كلمة مرور فقط.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _submitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submitRegistration() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _email.text.trim();
    final password = _password.text;
    final firstName = _firstName.text.trim();
    final lastName = _lastName.text.trim();
    final fullName = '$firstName $lastName'.trim();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await cred.user?.updateDisplayName(fullName);
      if (cred.user != null) {
        await BackendUserClient.instance.postUserRegistration(
          firebaseUid: cred.user!.uid,
          email: email,
        );
      }
      if (!mounted) return;
      final home = await resolveHomeForSignedInUser(cred.user ?? FirebaseAuth.instance.currentUser!);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => home),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = e.message ?? 'تعذر إنشاء الحساب.';
      });
    } on Object {
      setState(() {
        _error = 'تعذر إنشاء الحساب حالياً.';
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: Navigator.of(context).canPop() ? const AppBarBackButton() : null,
        title: Text('تسجيل حساب', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.heading,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            TextFormField(
              controller: _firstName,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                labelText: 'الاسم الأول',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _lastName,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                labelText: 'اسم العائلة',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _email,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.emailAddress,
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
            const SizedBox(height: 10),
            TextFormField(
              controller: _password,
              textAlign: TextAlign.right,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'كلمة المرور',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) => (v != null && v.length >= 6) ? null : '6 أحرف على الأقل',
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _confirmPassword,
              textAlign: TextAlign.right,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: 'تأكيد كلمة المرور',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (v) => (v == _password.text) ? null : 'كلمتا المرور غير متطابقتين',
            ),
            const SizedBox(height: 14),
            if (_error != null) _errorBanner(_error!),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _submitting ? null : _submitRegistration,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text('تسجيل حساب', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _submitting
                  ? null
                  : () {
                      Navigator.of(context).pushReplacement<void>(
                        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
                      );
                    },
              child: Text('لديك حساب؟ تسجيل دخول', style: GoogleFonts.tajawal()),
            ),
          ],
        ),
      ),
    );
  }

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
