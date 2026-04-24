import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../../core/contracts/feature_state.dart';
import '../../../../core/data/repositories/user_repository.dart';
import '../../../../core/constants/jordan_cities.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../maintenance/domain/maintenance_models.dart';
import '../../../maintenance/presentation/maintenance_controller.dart';
import '../../../../core/services/permission_service.dart';
import '../../../../core/session/backend_identity_controller.dart';
import '../../../../core/session/user_session.dart';
import '../../../maintenance/presentation/pages/technician_dashboard_page.dart';
import '../../../communication/presentation/messages_inbox_page.dart';
import '../store_controller.dart';
import '../widgets/ammarjo_loyalty_gold_card.dart';
import 'change_password_page.dart';
import 'customer_delivery_settings_page.dart';
import 'login_page.dart';
import 'register_page.dart';

String _profileContactLine(StoreController store) {
  final profile = store.profile;
  final contact = profile?.contactEmail?.trim() ?? (throw StateError('unexpected_empty_response'));
  if (contact.isNotEmpty) {
    return 'البريد: $contact';
  }
  final email = profile?.email ?? (throw StateError('unexpected_empty_response'));
  if (email.endsWith('@phone.ammarjo.app')) {
    final id = email.split('@').first;
    if (id.length >= 12 && id.startsWith('962')) {
      return 'الهاتف: +${id.substring(0, 3)} ${id.substring(3)}';
    }
  }
  return 'البريد: $email';
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<StoreController>(
      builder: (context, store, _) {
        final profile = store.profile;
        final sessionUser = UserSession.user ?? <String, dynamic>{};
        final sessionPhone = (sessionUser['phone'] ?? '').toString().trim();
        final sessionRole = (sessionUser['role'] ?? '').toString().trim();
        final loggedIn = UserSession.isLoggedIn;
        // ignore: avoid_print
        print('🔥 ACCOUNT PAGE STATE: $loggedIn');
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            centerTitle: true,
            leading: Navigator.of(context).canPop() ? const AppBarBackButton() : null,
            title: Text('حسابي', style: GoogleFonts.tajawal(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: !loggedIn
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'سجّل الدخول لمتابعة طلباتك.',
                        style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 15),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(builder: (_) => const LoginPage()),
                          );
                          await store.syncLocalProfileWithFirebaseSession();
                        },
                        child: Text('تسجيل الدخول', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.orange,
                          side: const BorderSide(color: AppColors.orange),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(builder: (_) => const RegisterPage()),
                          );
                          await store.syncLocalProfileWithFirebaseSession();
                        },
                        child: Text('إنشاء حساب', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'مرحباً ${(profile?.fullName ?? '').trim().isNotEmpty ? profile!.fullName : 'مستخدم'}',
                        style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      if (sessionPhone.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          sessionPhone,
                          style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 14),
                        ),
                      ],
                      if (sessionRole.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          sessionRole,
                          style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (profile != null)
                        Text(
                          _profileContactLine(store),
                          style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 14),
                        ),
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.navy, size: 28),
                        title: Text('الرسائل', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                        subtitle: Text('محادثات الصيانة والمتاجر', style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary)),
                        trailing: const Icon(Icons.chevron_left),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(builder: (_) => const MessagesInboxPage()),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.local_shipping_outlined, color: AppColors.navy, size: 28),
                        title: Text('عنوان التوصيل والهاتف', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                        subtitle: Text('بيانات الطلب المحفوظة', style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary)),
                        trailing: const Icon(Icons.chevron_left),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(builder: (_) => const CustomerDeliverySettingsPage()),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.lock_outline_rounded, color: AppColors.navy, size: 28),
                        title: Text('تغيير كلمة المرور', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          'تحديث كلمة المرور أو تعيينها لأول مرة (حساب الهاتف)',
                          style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary),
                        ),
                        trailing: const Icon(Icons.chevron_left),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
                        onTap: () {
                          if (!UserSession.isLoggedIn) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('انتهت الجلسة. سجّل الدخول مرة أخرى.', style: GoogleFonts.tajawal())),
                            );
                            return;
                          }
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(builder: (_) => const ChangePasswordPage()),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'نقاط الولاء',
                        style: GoogleFonts.tajawal(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      AmmarjoLoyaltyGoldCard(points: profile?.loyaltyPoints ?? 0),
                      const SizedBox(height: 24),
                      _TechnicianModeSection(
                        email: (profile?.email ?? '').trim(),
                        displayName: profile?.fullName ?? 'فني',
                      ),
                      const SizedBox(height: 28),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => store.logout(),
                        child: Text('تسجيل الخروج', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _TechnicianModeSection extends StatefulWidget {
  const _TechnicianModeSection({
    required this.email,
    required this.displayName,
  });

  final String email;
  final String displayName;

  @override
  State<_TechnicianModeSection> createState() => _TechnicianModeSectionState();
}

class _TechnicianModeSectionState extends State<_TechnicianModeSection> {
  static const List<String> _defaultSpecialtyLabels = [
    'كهرباء',
    'سباكة',
    'دهانات',
    'بلاط',
    'نجارة',
    'جبس',
    'عزل',
    'تكييف',
    'أخرى',
  ];

  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _city;
  /// معرّف وثيقة `tech_specialties` أو `def:التسمية` للقائمة الافتراضية.
  String? _specialtyValue;
  String? _specialtyLabel;

  @override
  void initState() {
    super.initState();
    _fullNameCtrl.text = widget.displayName;
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String _categoryIdForSelection(String? value, String specialtyLabel) {
    if (value == null || value.isEmpty) {
      return MaintenanceServiceCategory.idForLabel(specialtyLabel);
    }
    if (value.startsWith('def:')) {
      return MaintenanceServiceCategory.idForLabel(specialtyLabel);
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MaintenanceController>(
      builder: (context, maint, _) {
        final me = BackendIdentityController.instance.me;
        final isTechnicianApproved =
            PermissionService.normalizeRole(me?.role ?? '') == PermissionService.roleTechnician;
        return Material(
          color: AppColors.navy.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      'لإرسال طلب الانضمام كفني، املأ الحقول المطلوبة ثم فعّل الخيار أدناه.',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.tajawal(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextFormField(
                      controller: _fullNameCtrl,
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        labelText: 'الاسم الكامل *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) {
                        final t = (v ?? (throw StateError('unexpected_empty_response'))).trim();
                        return t.isEmpty ? 'الاسم الكامل مطلوب' : null;
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextFormField(
                      controller: _phoneCtrl,
                      textAlign: TextAlign.right,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'رقم الهاتف *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) {
                        final t = (v ?? (throw StateError('unexpected_empty_response'))).trim();
                        return t.isEmpty ? 'رقم الهاتف مطلوب' : null;
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Firebase.apps.isNotEmpty
                        ? FutureBuilder<FeatureState<List<Map<String, dynamic>>>>(
                            future: context.read<UserRepository>().fetchActiveTechSpecialtiesList(),
                            builder: (context, snap) {
                              final docs = switch (snap.data) {
                                FeatureSuccess(:final data) => data,
                                _ => <Map<String, dynamic>>[],
                              };
                              final items = <DropdownMenuItem<String>>[
                                if (docs.isEmpty)
                                  ..._defaultSpecialtyLabels.map(
                                    (e) => DropdownMenuItem<String>(
                                      value: 'def:$e',
                                      child: Text(e, style: GoogleFonts.tajawal()),
                                    ),
                                  )
                                else
                                  ...docs.map(
                                    (d) {
                                      final id = d['id']?.toString() ?? (throw StateError('unexpected_empty_response'));
                                      final name = d['name']?.toString().trim() ?? id;
                                      return DropdownMenuItem<String>(
                                        value: id,
                                        child: Text(name, style: GoogleFonts.tajawal()),
                                      );
                                    },
                                  ),
                              ];
                              return DropdownButtonFormField<String>(
                                // ignore: deprecated_member_use
                                value: _specialtyValue,
                                decoration: InputDecoration(
                                  labelText: 'التخصص / القسم *',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                items: items,
                                onChanged: (v) {
                                  setState(() {
                                    _specialtyValue = v;
                                    if (v == null) {
                                      _specialtyLabel = null;
                                    } else if (v.startsWith('def:')) {
                                      _specialtyLabel = v.substring(4);
                                    } else {
                                      Map<String, dynamic>? found;
                                      for (final d in docs) {
                                        if (d['id']?.toString() == v) {
                                          found = d;
                                          break;
                                        }
                                      }
                                      _specialtyLabel = found?['name']?.toString().trim() ?? v;
                                    }
                                  });
                                },
                                validator: (v) => (v == null || v.isEmpty) ? 'اختر التخصص' : null,
                              );
                            },
                          )
                        : DropdownButtonFormField<String>(
                            // ignore: deprecated_member_use
                            value: _specialtyValue,
                            decoration: InputDecoration(
                              labelText: 'التخصص / القسم *',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            items: _defaultSpecialtyLabels
                                .map((e) => DropdownMenuItem(value: 'def:$e', child: Text(e, style: GoogleFonts.tajawal())))
                                .toList(),
                            onChanged: (v) => setState(() {
                              _specialtyValue = v;
                              _specialtyLabel = v != null && v.startsWith('def:') ? v.substring(4) : v;
                            }),
                            validator: (v) => (v == null || v.isEmpty) ? 'اختر التخصص' : null,
                          ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _city,
                      decoration: InputDecoration(
                        labelText: 'المدينة *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: kJordanCities
                          .map((c) => DropdownMenuItem<String>(value: c, child: Text(c, style: GoogleFonts.tajawal())))
                          .toList(),
                      onChanged: (c) => setState(() => _city = c),
                      validator: (v) => (v == null || v.isEmpty) ? 'اختر المدينة' : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextFormField(
                      controller: _descCtrl,
                      textAlign: TextAlign.right,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'وصف خبرتك (اختياري)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    title: Text(
                      'التسجيل كفني (عمّار جو للصيانة)',
                      style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    subtitle: Text(
                      'فعّل لإرسال طلب الانضمام (بانتظار موافقة الإدارة).',
                      style: GoogleFonts.tajawal(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                    value: maint.technicianMode,
                    activeThumbColor: AppColors.orange,
                    onChanged: (v) async {
                      if (v) {
                        if (!(_formKey.currentState?.validate() ?? (throw StateError('unexpected_empty_response')))) return;
                        final city = _city;
                        final specVal = _specialtyValue;
                        if (city == null || city.isEmpty || specVal == null || specVal.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('أكمل الحقول المطلوبة.', style: GoogleFonts.tajawal())),
                          );
                          return;
                        }
                        final specLabel =
                            (_specialtyLabel ?? (throw StateError('unexpected_empty_response'))).trim();
                        if (specLabel.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('اختر التخصص / القسم.', style: GoogleFonts.tajawal())),
                          );
                          return;
                        }
                        final catId = _categoryIdForSelection(specVal, specLabel);
                        final specIds = <String>[
                          if (specVal.startsWith('def:')) catId else specVal,
                        ];
                        try {
                          await maint.registerTechnicianProfile(
                            email: widget.email,
                            fullName: _fullNameCtrl.text.trim(),
                            phone: _phoneCtrl.text.trim(),
                            city: city,
                            specialtyIds: specIds,
                            categoryId: catId,
                            primarySpecialtyLabel: specLabel,
                            experienceDescription: _descCtrl.text.trim(),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'تم إرسال طلب الانضمام، بانتظار موافقة الإدارة.',
                                style: GoogleFonts.tajawal(),
                              ),
                            ),
                          );
                        } on StateError catch (e) {
                          if (!context.mounted) return;
                          final msg = e.message.toString().trim();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                msg.isNotEmpty ? msg : 'تعذر إرسال طلب الانضمام حالياً.',
                                style: GoogleFonts.tajawal(),
                              ),
                            ),
                          );
                        } on Object {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'تعذر إرسال طلب الانضمام حالياً.',
                                style: GoogleFonts.tajawal(),
                              ),
                            ),
                          );
                        }
                      } else {
                        await maint.setTechnicianMode(false);
                      }
                    },
                  ),
                  if (isTechnicianApproved)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(builder: (_) => const TechnicianDashboardPage()),
                          );
                        },
                        icon: const Icon(Icons.dashboard_customize_rounded),
                        label: Text('فتح لوحة الفني', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'سيتم تفعيل لوحة الفني بعد موافقة الإدارة على طلبك.',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.tajawal(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
