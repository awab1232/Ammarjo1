import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/firebase/account_password_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';

/// Ã˜ÂªÃ˜ÂºÃ™Å Ã™Å Ã˜Â± Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â±Ã™Ë†Ã˜Â± Ã˜Â¨Ã˜Â¹Ã˜Â¯ Ã˜Â¥Ã˜Â¹Ã˜Â§Ã˜Â¯Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜ÂµÃ˜Â§Ã˜Â¯Ã™â€šÃ˜Â©Ã˜â€º Ã˜Â£Ã™Ë† Ã˜ÂªÃ˜Â¹Ã™Å Ã™Å Ã™â€ Ã™â€¡Ã˜Â§ Ã™â€žÃ˜Â£Ã™Ë†Ã™â€ž Ã™â€¦Ã˜Â±Ã˜Â© Ã™â€žÃ˜Â­Ã˜Â³Ã˜Â§Ã˜Â¨ Ã˜Â§Ã™â€žÃ™â€¡Ã˜Â§Ã˜ÂªÃ™Â Ã™ÂÃ™â€šÃ˜Â·.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _newPass = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;

  @override
  void dispose() {
    _current.dispose();
    _newPass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final user = FirebaseAuth.instance.currentUser;
    final hasPassword = AccountPasswordService.userHasPasswordLinked(user);

    setState(() => _loading = true);
    try {
      if (hasPassword) {
        await AccountPasswordService.changePassword(
          currentPassword: _current.text,
          newPassword: _newPass.text,
        );
      } else {
        await AccountPasswordService.linkInitialPassword(
          newPassword: _newPass.text,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(hasPassword ? 'Ã˜ÂªÃ™â€¦ Ã˜ÂªÃ˜Â­Ã˜Â¯Ã™Å Ã˜Â« Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â±Ã™Ë†Ã˜Â±.' : 'Ã˜ÂªÃ™â€¦ Ã˜ÂªÃ˜Â¹Ã™Å Ã™Å Ã™â€  Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â±Ã™Ë†Ã˜Â± Ã˜Â¨Ã™â€ Ã˜Â¬Ã˜Â§Ã˜Â­.', style: GoogleFonts.tajawal())),
      );
      Navigator.of(context).pop();
    } on FirebaseAuthException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تغيير كلمة المرور.', textAlign: TextAlign.right, style: GoogleFonts.tajawal()),
        ),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('unexpected error', textAlign: TextAlign.right, style: GoogleFonts.tajawal())),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final hasPassword = AccountPasswordService.userHasPasswordLinked(user);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: const AppBarBackButton(),
        title: Text('Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â±Ã™Ë†Ã˜Â±', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                hasPassword
                    ? 'Ã˜Â£Ã˜Â¯Ã˜Â®Ã™â€ž Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â±Ã™Ë†Ã˜Â± Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ™Å Ã˜Â© Ã˜Â«Ã™â€¦ Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â±Ã™Ë†Ã˜Â± Ã˜Â§Ã™â€žÃ˜Â¬Ã˜Â¯Ã™Å Ã˜Â¯Ã˜Â©.'
                    : 'Ã˜Â­Ã˜Â³Ã˜Â§Ã˜Â¨Ã™Æ’ Ã™â€¦Ã˜Â³Ã˜Â¬Ã™â€˜Ã™â€ž Ã˜Â¨Ã˜Â±Ã™â€šÃ™â€¦ Ã˜Â§Ã™â€žÃ™â€¡Ã˜Â§Ã˜ÂªÃ™Â Ã™ÂÃ™â€šÃ˜Â·. Ã™Å Ã™â€¦Ã™Æ’Ã™â€ Ã™Æ’ Ã˜ÂªÃ˜Â¹Ã™Å Ã™Å Ã™â€  Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã™â€¦Ã˜Â±Ã™Ë†Ã˜Â± Ã˜Â§Ã™â€žÃ˜Â¢Ã™â€  Ã™â€žÃ˜Â§Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã˜Â§Ã™â€¦Ã™â€¡Ã˜Â§ Ã™â€¦Ã˜Â¹ Ã˜ÂªÃ˜Â³Ã˜Â¬Ã™Å Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â¯Ã˜Â®Ã™Ë†Ã™â€ž Ã™â€žÃ˜Â§Ã˜Â­Ã™â€šÃ˜Â§Ã™â€¹ (Ã™Å Ã™ÂÃ˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Ã™â€¦Ã˜Â¹Ã˜Â±Ã™â€˜Ã™Â Ã™â€¡Ã˜Â§Ã˜ÂªÃ™ÂÃ™Æ’ Ã˜Â¯Ã˜Â§Ã˜Â®Ã™â€žÃ™Å Ã˜Â§Ã™â€¹).',
                textAlign: TextAlign.right,
                style: GoogleFonts.tajawal(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 20),
              if (hasPassword) ...[
                TextFormField(
                  controller: _current,
                  obscureText: _obscureCurrent,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    labelText: 'Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â±Ã™Ë†Ã˜Â± Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ™Å Ã˜Â©',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                    suffixIcon: IconButton(
                      icon: Icon(_obscureCurrent ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 6) ? 'Ã˜Â£Ã˜Â¯Ã˜Â®Ã™â€ž Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â±Ã™Ë†Ã˜Â± Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ™Å Ã˜Â©' : null,
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(
                controller: _newPass,
                obscureText: _obscureNew,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  labelText: hasPassword ? 'Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â±Ã™Ë†Ã˜Â± Ã˜Â§Ã™â€žÃ˜Â¬Ã˜Â¯Ã™Å Ã˜Â¯Ã˜Â©' : 'Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â±Ã™Ë†Ã˜Â±',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                validator: (v) => (v == null || v.length < 6) ? '6 Ã˜Â£Ã˜Â­Ã˜Â±Ã™Â Ã˜Â¹Ã™â€žÃ™â€° Ã˜Â§Ã™â€žÃ˜Â£Ã™â€šÃ™â€ž' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirm,
                obscureText: _obscureConfirm,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  labelText: 'Ã˜ÂªÃ˜Â£Ã™Æ’Ã™Å Ã˜Â¯ Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â±Ã™Ë†Ã˜Â±',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) => v != _newPass.text ? 'Ã˜ÂºÃ™Å Ã˜Â± Ã™â€¦Ã˜ÂªÃ˜Â·Ã˜Â§Ã˜Â¨Ã™â€šÃ˜Â©' : null,
              ),
              const SizedBox(height: 28),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(hasPassword ? 'Ã˜Â­Ã™ÂÃ˜Â¸ Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â±Ã™Ë†Ã˜Â±' : 'Ã˜ÂªÃ˜Â¹Ã™Å Ã™Å Ã™â€  Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â±Ã™Ë†Ã˜Â±', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


