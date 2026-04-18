import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/firebase/user_notifications_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/home_page_shimmers.dart';
import '../../../store/presentation/store_controller.dart';
import '../../data/wholesale_repository.dart';

/// نموذج انضمام كتاجر جملة — يُخزَّن في `wholesaler_requests`.
class WholesaleApplyPage extends StatefulWidget {
  const WholesaleApplyPage({super.key});

  @override
  State<WholesaleApplyPage> createState() => _WholesaleApplyPageState();
}

class _WholesaleApplyPageState extends State<WholesaleApplyPage> {
  static const String _allJordanLabel = 'الأردن كاملة';

  final _formKey = GlobalKey<FormState>();
  final _storeNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  List<String> _selectedCities = <String>[];
  bool _isLoading = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final u = FirebaseAuth.instance.currentUser?.email?.trim();
    if (u != null && u.isNotEmpty) {
      _emailCtrl.text = u;
    }
  }

  static const List<String> _cities = <String>[
    'عمان',
    'الزرقاء',
    'إربد',
    'العقبة',
    'المفرق',
    'جرش',
    'عجلون',
    'السلط',
    'مادبا',
    'الكرك',
    'الطفيلة',
    'معان',
    _allJordanLabel,
  ];

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  String _citySummaryForFirestore() {
    if (_selectedCities.isEmpty) return '';
    if (_selectedCities.length == 1 && _selectedCities.first == 'all') {
      return _allJordanLabel;
    }
    return _selectedCities.where((e) => e != 'all').join('، ');
  }

  List<String> _citiesPayload() {
    if (_selectedCities.isEmpty) return List<String>.empty();
    if (_selectedCities.length == 1 && _selectedCities.first == 'all') {
      return <String>['all'];
    }
    return List<String>.from(_selectedCities);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('انضم كتاجر جملة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, color: Colors.white)),
        backgroundColor: const Color(0xFFFF6B00),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _submitted ? _buildSuccessState() : _buildForm(),
    );
  }

  Widget _buildSuccessState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
              child: const Icon(Icons.check_circle, color: Colors.green, size: 60),
            ),
            const SizedBox(height: 24),
            Text('تم إرسال طلبك بنجاح!', style: GoogleFonts.tajawal(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(
              'ستتم مراجعة طلبك من قبل فريق عمّارجو، والرد عليك خلال 24 ساعة.\n\n'
              'بعد الموافقة ستجد «لوحة تحكم الجملة» في قائمتك الجانبية.',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: Colors.grey[600], height: 1.6),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B00),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(200, 48),
              ),
              onPressed: () => Navigator.pop(context),
              child: Text('العودة', style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFFFF6B00), Color(0xFFE65100)]),
            ),
            child: Column(
              children: [
                const Icon(Icons.store_mall_directory, color: Colors.white, size: 48),
                const SizedBox(height: 12),
                Text(
                  'انضم كتاجر جملة في عمّارجو',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'وصّل منتجاتك لأصحاب المتاجر في كل الأردن',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _benefit(Icons.people_outline, 'وصول لآلاف المتاجر')),
                Expanded(child: _benefit(Icons.trending_up, 'زيادة مبيعاتك')),
                Expanded(child: _benefit(Icons.security_outlined, 'مدفوعات آمنة')),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'معلومات الطلب',
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primaryOrange),
                  ),
                  const SizedBox(height: 16),
                  _buildField(_storeNameCtrl, 'اسم المتجر *', Icons.store_outlined),
                  _buildField(_phoneCtrl, 'رقم الهاتف *', Icons.phone_outlined, type: TextInputType.phone),
                  _buildField(_emailCtrl, 'البريد الإلكتروني *', Icons.email_outlined, type: TextInputType.emailAddress),
                  _buildField(_descCtrl, 'وصف نشاطك التجاري *', Icons.description_outlined, maxLines: 3),
                  const SizedBox(height: 16),
                  Text('المناطق التي تعمل فيها *', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: _cities.map((city) {
                      final selected = city == _allJordanLabel
                          ? (_selectedCities.length == 1 && _selectedCities.first == 'all')
                          : _selectedCities.contains(city);
                      return GestureDetector(
                        onTap: () => setState(() {
                          if (city == _allJordanLabel) {
                            _selectedCities = <String>['all'];
                          } else {
                            if (selected) {
                              _selectedCities.remove(city);
                            } else {
                              _selectedCities.remove('all');
                              if (!_selectedCities.contains(city)) {
                                _selectedCities.add(city);
                              }
                            }
                          }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFFFF6B00) : Colors.grey[100],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: selected ? const Color(0xFFFF6B00) : Colors.grey[300]!),
                          ),
                          child: Text(
                            city,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.tajawal(
                              color: selected ? Colors.white : Colors.black87,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (_selectedCities.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'يرجى اختيار منطقة واحدة على الأقل',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.tajawal(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B00),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _isLoading ? null : _submitApplication,
                      child: _isLoading
                          ? const InlineLightButtonShimmer(size: 26)
                          : Text(
                              'إرسال الطلب',
                              style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'ستتم مراجعة طلبك خلال 24 ساعة',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _benefit(IconData icon, String text) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFFFF6B00), size: 28),
        const SizedBox(height: 4),
        Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey[700], height: 1.25),
        ),
      ],
    );
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType type = TextInputType.text,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: type,
        textAlign: TextAlign.right,
        style: GoogleFonts.tajawal(),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.tajawal(),
          prefixIcon: Icon(icon, color: const Color(0xFFFF6B00)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFF6B00)),
          ),
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
      ),
    );
  }

  Future<void> _submitApplication() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCities.isEmpty) {
      setState(() {});
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('يجب تسجيل الدخول أولاً');

      final profile = context.read<StoreController>().profile;
      final fn = profile?.fullName?.trim();
      final nameHint = (fn != null && fn.isNotEmpty) ? fn : _storeNameCtrl.text.trim();

      await WholesaleRepository.instance.submitWholesalerJoinRequest(
        applicantId: user.uid,
        applicantEmail: _emailCtrl.text.trim(),
        applicantPhone: _phoneCtrl.text.trim(),
        wholesalerName: _storeNameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        category: 'عام',
        city: _citySummaryForFirestore(),
        cities: _citiesPayload(),
      );

      await UserNotificationsRepository.sendNotificationToAdmin(
        title: 'طلب انضمام تاجر جملة جديد',
        body: '$nameHint يطلب الانضمام كتاجر جملة',
        type: 'wholesale_request',
      );

      if (!mounted) return;
      setState(() => _submitted = true);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر إرسال الطلب حالياً. حاول مرة أخرى.',
            style: GoogleFonts.tajawal(),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
