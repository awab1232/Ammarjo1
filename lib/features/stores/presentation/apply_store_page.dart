import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase, FirebaseException;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/contracts/feature_state.dart';
import '../../../core/constants/jordan_cities.dart';
import '../../../core/firebase/users_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_bar_back_button.dart';
import '../../store/domain/models.dart';
import '../../store/presentation/store_controller.dart';
import '../data/stores_repository.dart';
import '../data/store_types_repository.dart';
import '../domain/store_type_model.dart';

/// نموذج طلب فتح متجر — يُكتب في `store_requests`.
class ApplyStorePage extends StatefulWidget {
  const ApplyStorePage({super.key, this.lockedCategory});

  /// عند تعيينه يُثبَّت حقل `category` (مثل متاجر الأدوات المنزلية).
  final String? lockedCategory;

  @override
  State<ApplyStorePage> createState() => _ApplyStorePageState();
}

class _ApplyStorePageState extends State<ApplyStorePage> {
  static const _jordanWideLabel = 'الأردن كاملة';

  final _formKey = GlobalKey<FormState>();
  final _storeName = TextEditingController();
  final _phone = TextEditingController();
  final _description = TextEditingController();
  String? _selectedStoreTypeId;
  List<StoreTypeModel> _storeTypes = const <StoreTypeModel>[];
  String _businessStoreType = 'retail';
  /// `city` | `all_jordan`
  String _sellScope = 'city';
  String? _primaryCity;
  bool _saving = false;

  List<String> get _cityDropdownItems =>
      kJordanCities.where((c) => c != _jordanWideLabel).toList();

  @override
  void initState() {
    super.initState();
    _loadStoreTypes();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillFromProfile());
  }

  Future<void> _loadStoreTypes() async {
    final state = await StoreTypesRepository.instance.fetchActiveStoreTypes();
    if (!mounted) return;
    switch (state) {
      case FeatureSuccess(:final data):
        setState(() {
          _storeTypes = data;
          _selectedStoreTypeId = data.isNotEmpty ? data.first.id : null;
        });
      case FeatureFailure():
      case FeatureMissingBackend():
      case FeatureAdminNotWired():
      case FeatureAdminMissingEndpoint():
      case FeatureCriticalPublicDataFailure():
        break;
    }
  }

  Future<void> _prefillFromProfile() async {
    if (!mounted) return;
    final store = context.read<StoreController>();
    CustomerProfile? profile = store.profile;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (profile == null && uid != null && Firebase.apps.isNotEmpty) {
      profile = await UsersRepository.fetchProfileDocument(uid);
    }
    if (!mounted) return;
    final local = profile?.phoneLocal?.trim();
    if (local != null && local.isNotEmpty) {
      _phone.text = local.startsWith('0') ? local : '0$local';
    } else {
      final authPhone = FirebaseAuth.instance.currentUser?.phoneNumber?.trim();
      if (authPhone != null && authPhone.isNotEmpty) {
        _phone.text = authPhone;
      }
    }
    final pc = profile?.city?.trim();
    if (pc != null && pc.isNotEmpty && _cityDropdownItems.contains(pc)) {
      _primaryCity = pc;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _storeName.dispose();
    _phone.dispose();
    _description.dispose();
    super.dispose();
  }

  String _applicantName(CustomerProfile? profile) {
    if (profile == null) return '';
    final n = profile.fullName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return profile.displayName;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_sellScope == 'city') {
      final c = _primaryCity?.trim() ?? '';
      if (c.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('اختر المدينة.', style: GoogleFonts.tajawal())),
        );
        return;
      }
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('سجّل الدخول أولاً.', style: GoogleFonts.tajawal())),
      );
      return;
    }
    if (!Firebase.apps.isNotEmpty) return;

    final store = context.read<StoreController>();
    CustomerProfile? profile = store.profile;
    if (profile == null && Firebase.apps.isNotEmpty) {
      profile = await UsersRepository.fetchProfileDocument(uid);
    }

    setState(() => _saving = true);
    try {
      final citiesList = _sellScope == 'all_jordan'
          ? <String>['all']
          : <String>[_primaryCity!.trim()];
      final applyState = await StoresRepository.instance.applyForStore({
        'applicantId': uid,
        'applicantName': _applicantName(profile),
        'applicantEmail': (profile?.email ?? FirebaseAuth.instance.currentUser?.email ?? '').trim().toLowerCase(),
        'storeName': _storeName.text.trim(),
        'phone': _phone.text.trim(),
        'storeTypeId': _selectedStoreTypeId,
        'storeType': _businessStoreType,
        'sellScope': _sellScope,
        'city': _sellScope == 'city' ? _primaryCity!.trim() : '',
        'cities': citiesList,
        'description': _description.text.trim(),
      });
      if (!mounted) return;
      switch (applyState) {
        case FeatureSuccess():
          break;
        case FeatureMissingBackend(:final featureName):
        case FeatureAdminNotWired(:final featureName):
        case FeatureAdminMissingEndpoint(:final featureName):
        case FeatureCriticalPublicDataFailure(:final featureName):
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تعذّر إرسال الطلب حالياً. ($featureName)',
                style: GoogleFonts.tajawal(),
              ),
            ),
          );
          setState(() => _saving = false);
          return;
        case FeatureFailure(:final message):
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message, style: GoogleFonts.tajawal())),
          );
          setState(() => _saving = false);
          return;
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text('تم', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
          content: Text(
            'تم إرسال طلبك بنجاح! سيتم مراجعة طلبك\nوالرد عليك قريباً',
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(height: 1.4),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF6B00)),
              onPressed: () {
                Navigator.of(ctx).pop();
              },
              child: Text('حسناً', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on FirebaseException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الإرسال', style: GoogleFonts.tajawal())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const AppBarBackButton(),
        title: Text('انضم كصاحب متجر', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _storeName,
              textAlign: TextAlign.right,
              decoration: InputDecoration(labelText: 'اسم المتجر *', labelStyle: GoogleFonts.tajawal()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textAlign: TextAlign.right,
              decoration: InputDecoration(labelText: 'الهاتف *', labelStyle: GoogleFonts.tajawal()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 12),
            Text('التصنيف *', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
                value: _selectedStoreTypeId, // ignore: deprecated_member_use
                isExpanded: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelStyle: GoogleFonts.tajawal(),
                ),
                items: _storeTypes
                    .map(
                      (type) => DropdownMenuItem(
                        value: type.id,
                        child: Text(type.name, style: GoogleFonts.tajawal(), textAlign: TextAlign.right),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedStoreTypeId = v),
                validator: (v) => (v == null || v.isEmpty) ? 'مطلوب' : null,
              ),
            const SizedBox(height: 16),
            Text('نوع المتجر التجاري *', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment<String>(
                  value: 'retail',
                  label: Text('متجر تجزئة', style: GoogleFonts.tajawal()),
                ),
                ButtonSegment<String>(
                  value: 'wholesale',
                  label: Text('متجر جملة', style: GoogleFonts.tajawal()),
                ),
              ],
              selected: {_businessStoreType},
              onSelectionChanged: (Set<String> next) {
                if (next.isEmpty) return;
                setState(() => _businessStoreType = next.first);
              },
              showSelectedIcon: false,
            ),
            const SizedBox(height: 16),
            Text('نطاق البيع *', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment<String>(
                  value: 'city',
                  label: Text('مدينتي فقط', style: GoogleFonts.tajawal(), textAlign: TextAlign.right),
                ),
                ButtonSegment<String>(
                  value: 'all_jordan',
                  label: Text('كل الأردن', style: GoogleFonts.tajawal(), textAlign: TextAlign.right),
                ),
              ],
              selected: {_sellScope},
              onSelectionChanged: (Set<String> next) {
                if (next.isEmpty) return;
                setState(() => _sellScope = next.first);
              },
              showSelectedIcon: false,
            ),
            if (_sellScope == 'city') ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _primaryCity != null && _cityDropdownItems.contains(_primaryCity) ? _primaryCity : null, // ignore: deprecated_member_use
                isExpanded: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'المدينة *',
                  labelStyle: GoogleFonts.tajawal(),
                ),
                hint: Text('اختر المدينة', style: GoogleFonts.tajawal()),
                items: _cityDropdownItems
                    .map(
                      (c) => DropdownMenuItem<String>(
                        value: c,
                        child: Text(c, style: GoogleFonts.tajawal(), textAlign: TextAlign.right),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _primaryCity = v),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'سيتم عرض متجرك لجميع المحافظات.',
                  style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                  textAlign: TextAlign.right,
                ),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              minLines: 4,
              maxLines: 8,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                labelText: 'وصف المتجر *',
                alignLabelWithHint: true,
                labelStyle: GoogleFonts.tajawal(),
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'مطلوب';
                if (t.length < 20) return 'الوصف يجب أن لا يقل عن 20 حرفاً';
                return null;
              },
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B00),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text('إرسال الطلب', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
