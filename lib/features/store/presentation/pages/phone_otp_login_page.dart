import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/routing/role_home_resolver.dart';
import '../../../../core/services/phone_password_auth_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/jordan_phone.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../admin/presentation/pages/admin_dashboard_screen.dart';
import '../../../maintenance/presentation/pages/technician_dashboard_page.dart';
import '../../../store_owner/presentation/store_owner_dashboard.dart';
import 'main_navigation_page.dart';
import 'register_page.dart';

/// تسجيل الدخول برقم الهاتف + كلمة المرور.
/// OTP أصبح مخصّصاً للتسجيل الجديد فقط (في [RegisterPage]).
///
/// (اسم الملف محفوظ للحفاظ على التوافق مع الواردات الحالية، ولكن المحتوى
/// تحوّل إلى نموذج phone + password.)
class PhoneOtpLoginPage extends StatefulWidget {
  const PhoneOtpLoginPage({super.key});

  @override
  State<PhoneOtpLoginPage> createState() => _PhoneOtpLoginPageState();
}

class _PhoneOtpLoginPageState extends State<PhoneOtpLoginPage> {
  // ─── State ───────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final local = _phoneCtrl.text.trim();
    final e164 = '+962$local';
    final password = _passwordCtrl.text;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // ignore: avoid_print
      print('🔥 LOGIN BUTTON PRESSED');
      // ignore: avoid_print
      print('🔥 PHONE: $e164');
      await PhonePasswordAuthService.signInWithPhonePassword(
        phone: e164,
        password: password,
      );
      if (!mounted) return;
      await _navigateAfterLogin();
    } on PhonePasswordAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.messageAr;
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

  Future<void> _navigateAfterLogin() async {
    final role = PhonePasswordAuthService.lastRole?.toLowerCase().trim() ?? '';
    // ignore: avoid_print
    print('🔥 USER ROLE: ${role.isEmpty ? 'customer' : role}');
    if (!mounted) return;
    if (role == 'admin' || role == 'system_internal') {
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const AdminDashboardScreen()),
        (_) => false,
      );
      return;
    }
    if (role == 'store_owner') {
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const StoreOwnerDashboard()),
        (_) => false,
      );
      return;
    }
    if (role == 'technician') {
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const TechnicianDashboardPage()),
        (_) => false,
      );
      return;
    }
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

  void _goToRegister() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const RegisterPage()),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const AppBarBackButton(),
        title: Text(
          'تسجيل الدخول',
          style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.heading,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header card
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.lock_rounded, size: 56, color: AppColors.orange),
                      const SizedBox(height: 12),
                      Text(
                        'أهلاً بعودتك',
                        style: GoogleFonts.tajawal(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'أدخل رقم هاتفك وكلمة المرور للدخول إلى حسابك',
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

                // Phone field
                Text(
                  'رقم الهاتف',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 8),
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
                        child: Text(
                          '+962',
                          style: GoogleFonts.tajawal(
                            fontWeight: FontWeight.w700,
                            color: AppColors.orange,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _phoneCtrl,
                          focusNode: _phoneFocus,
                          keyboardType: TextInputType.phone,
                          style: GoogleFonts.tajawal(fontSize: 16),
                          enabled: !_loading,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(9),
                          ],
                          decoration: InputDecoration(
                            hintText: '7XXXXXXXX',
                            hintStyle: GoogleFonts.tajawal(color: AppColors.textSecondary),
                            prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.orange),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          ),
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.isEmpty) return 'مطلوب';
                            if (!isValidJordanMobileLocal(t)) {
                              return 'رقم أردني صحيح (9 أرقام تبدأ بـ 7)';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Password field
                Text(
                  'كلمة المرور',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordCtrl,
                  focusNode: _passwordFocus,
                  textAlign: TextAlign.right,
                  obscureText: _obscurePassword,
                  enabled: !_loading,
                  style: GoogleFonts.tajawal(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    hintStyle: GoogleFonts.tajawal(color: AppColors.textSecondary),
                    prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.orange),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: _loading
                          ? null
                          : () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  validator: (v) {
                    final t = v ?? '';
                    if (t.isEmpty) return 'مطلوب';
                    if (t.length < 6) return '6 أحرف على الأقل';
                    return null;
                  },
                  onFieldSubmitted: (_) => _loading ? null : _submit(),
                ),

                const SizedBox(height: 16),

                // Error banner
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
                      style: GoogleFonts.tajawal(
                        color: Colors.red.shade800,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),

                // Primary action
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          'تسجيل الدخول',
                          style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                ),

                const SizedBox(height: 16),

                // Register link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'لا تملك حساباً؟',
                      style: GoogleFonts.tajawal(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    TextButton(
                      onPressed: _loading ? null : _goToRegister,
                      child: Text(
                        'أنشئ حساباً جديداً',
                        style: GoogleFonts.tajawal(
                          color: AppColors.orange,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
