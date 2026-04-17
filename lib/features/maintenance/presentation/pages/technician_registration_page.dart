import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/jordan_cities.dart';
import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../store/presentation/store_controller.dart';
import '../../data/technicians_repository.dart';
import '../../domain/maintenance_models.dart';
import '../maintenance_controller.dart';

class TechnicianRegistrationPage extends StatefulWidget {
  const TechnicianRegistrationPage({super.key});

  @override
  State<TechnicianRegistrationPage> createState() => _TechnicianRegistrationPageState();
}

class _TechnicianRegistrationPageState extends State<TechnicianRegistrationPage> {
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

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _city;
  String? _specialtyValue;
  String? _specialtyLabel;
  final Set<String> _selectedSpecIds = {};
  late final Future<FeatureState<List<MaintenanceServiceCategory>>> _specialtiesFuture;

  @override
  void initState() {
    super.initState();
    _specialtiesFuture = TechniciansRepository.instance.fetchTechSpecialties();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final store = context.read<StoreController>();
    final maint = context.read<MaintenanceController>();
    final email = store.profile?.email.trim() ?? '';
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('سجّل الدخول أولاً للتسجيل كفني.', style: GoogleFonts.tajawal())),
      );
      return;
    }
    final specsState = await _specialtiesFuture;
    final specs = switch (specsState) {
      FeatureSuccess(:final data) => data,
      _ => <MaintenanceServiceCategory>[],
    };
    if (!mounted) return;
    if (specs.isNotEmpty) {
        if (_selectedSpecIds.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('اختر تخصصاً واحداً على الأقل.', style: GoogleFonts.tajawal())),
          );
          return;
        }
        final ordered = specs.where((d) => _selectedSpecIds.contains(d.id)).toList();
        final primaryLabel = ordered.first.labelAr.trim().isEmpty ? ordered.first.id : ordered.first.labelAr.trim();
        var catId = MaintenanceServiceCategory.idForLabel(primaryLabel);
        if (catId.isEmpty) catId = ordered.first.id;
        await maint.registerTechnicianProfile(
          email: email,
          fullName: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          city: _city!,
          specialtyIds: ordered.map((d) => d.id).toList(),
          categoryId: catId,
          primarySpecialtyLabel: primaryLabel,
          experienceDescription: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إرسال طلب الانضمام، بانتظار موافقة الإدارة.', style: GoogleFonts.tajawal())),
        );
        Navigator.pop(context);
        return;
    }

    final specVal = _specialtyValue;
    if (specVal == null || specVal.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('اختر التخصص / القسم.', style: GoogleFonts.tajawal())),
      );
      return;
    }
    final specLabel = (_specialtyLabel ?? (specVal.startsWith('def:') ? specVal.substring(4) : specVal)).trim();
    final catId = specVal.startsWith('def:')
        ? MaintenanceServiceCategory.idForLabel(specLabel)
        : specVal;

    await maint.registerTechnicianProfile(
      email: email,
      fullName: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      city: _city!,
      specialtyIds: specVal.startsWith('def:') ? <String>[catId] : <String>[specVal],
      categoryId: catId,
      primarySpecialtyLabel: specLabel,
      experienceDescription: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم إرسال طلب الانضمام، بانتظار موافقة الإدارة.', style: GoogleFonts.tajawal())),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: const AppBarBackButton(),
        title: Text('انضم كفني', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'سجّل خدماتك ليتم توجيه طلبات العملاء إليك مباشرة.',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _nameCtrl,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                labelText: 'الاسم الكامل *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'رقم الهاتف *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'رقم الهاتف مطلوب';
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _city,
              decoration: InputDecoration(
                labelText: 'المدينة *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: kJordanCities
                  .map((c) => DropdownMenuItem<String>(value: c, child: Text(c, style: GoogleFonts.tajawal())))
                  .toList(),
              onChanged: (v) => setState(() => _city = v),
              validator: (v) => (v == null || v.isEmpty) ? 'المدينة مطلوبة' : null,
            ),
            const SizedBox(height: 12),
            FutureBuilder<FeatureState<List<MaintenanceServiceCategory>>>(
                future: _specialtiesFuture,
                builder: (context, snap) {
                  final specs = switch (snap.data) {
                    FeatureSuccess(:final data) => data,
                    _ => <MaintenanceServiceCategory>[],
                  };
                  if (specs.isEmpty) {
                    final defaults = _defaultSpecialtyLabels
                        .map((e) => DropdownMenuItem<String>(value: 'def:$e', child: Text(e, style: GoogleFonts.tajawal())))
                        .toList();
                    return DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _specialtyValue,
                      decoration: InputDecoration(
                        labelText: 'التخصص / القسم *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: defaults,
                      onChanged: (v) => setState(() {
                        _specialtyValue = v;
                        _specialtyLabel = v != null && v.startsWith('def:') ? v.substring(4) : v;
                      }),
                      validator: (v) => (v == null || v.isEmpty) ? 'يرجى اختيار التخصص' : null,
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'التخصصات * (اختر واحداً أو أكثر)',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: specs.map((d) {
                          final id = d.id;
                          final name = d.labelAr;
                          final sel = _selectedSpecIds.contains(id);
                          return FilterChip(
                            label: Text(name, style: GoogleFonts.tajawal()),
                            selected: sel,
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  _selectedSpecIds.add(id);
                                } else {
                                  _selectedSpecIds.remove(id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              textAlign: TextAlign.right,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'وصف خبرتك (اختياري)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.work_rounded),
              label: Text('تسجيل كفني', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}
