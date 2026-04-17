import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/firebase/user_notifications_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../store/presentation/store_controller.dart';
import '../../data/wholesale_repository.dart';

/// Ù†Ù…ÙˆØ°Ø¬ Ø§Ù†Ø¶Ù…Ø§Ù… ÙƒØªØ§Ø¬Ø± Ø¬Ù…Ù„Ø© â€” ÙŠÙØ®Ø²Ù‘ÙŽÙ† ÙÙŠ `wholesaler_requests`.
class WholesaleApplyPage extends StatefulWidget {
  const WholesaleApplyPage({super.key});

  @override
  State<WholesaleApplyPage> createState() => _WholesaleApplyPageState();
}

class _WholesaleApplyPageState extends State<WholesaleApplyPage> {
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
    'Ø¹Ù…Ø§Ù†',
    'Ø§Ù„Ø²Ø±Ù‚Ø§Ø¡',
    'Ø¥Ø±Ø¨Ø¯',
    'Ø§Ù„Ø¹Ù‚Ø¨Ø©',
    'Ø§Ù„Ù…ÙØ±Ù‚',
    'Ø¬Ø±Ø´',
    'Ø¹Ø¬Ù„ÙˆÙ†',
    'Ø§Ù„Ø³Ù„Ø·',
    'Ù…Ø§Ø¯Ø¨Ø§',
    'Ø§Ù„ÙƒØ±Ùƒ',
    'Ø§Ù„Ø·ÙÙŠÙ„Ø©',
    'Ù…Ø¹Ø§Ù†',
    'Ø§Ù„Ø£Ø±Ø¯Ù† ÙƒØ§Ù…Ù„Ø©',
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
      return 'Ø§Ù„Ø£Ø±Ø¯Ù† ÙƒØ§Ù…Ù„Ø©';
    }
    return _selectedCities.where((e) => e != 'all').join('ØŒ ');
  }

  List<String> _citiesPayload() {
    if (_selectedCities.isEmpty) return <String>[];
    if (_selectedCities.length == 1 && _selectedCities.first == 'all') {
      return <String>['all'];
    }
    return List<String>.from(_selectedCities);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Ø§Ù†Ø¶Ù… ÙƒØªØ§Ø¬Ø± Ø¬Ù…Ù„Ø©', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, color: Colors.white)),
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
            Text('ØªÙ… Ø¥Ø±Ø³Ø§Ù„ Ø·Ù„Ø¨Ùƒ Ø¨Ù†Ø¬Ø§Ø­!', style: GoogleFonts.tajawal(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(
              'Ø³ÙŠØªÙ… Ù…Ø±Ø§Ø¬Ø¹Ø© Ø·Ù„Ø¨Ùƒ Ù…Ù† Ù‚Ø¨Ù„ ÙØ±ÙŠÙ‚ Ø¹Ù…Ø§Ø±Ø¬Ùˆ ÙˆØ§Ù„Ø±Ø¯ Ø¹Ù„ÙŠÙƒ Ø®Ù„Ø§Ù„ 24 Ø³Ø§Ø¹Ø©.\n\n'
              'Ø¨Ø¹Ø¯ Ø§Ù„Ù…ÙˆØ§ÙÙ‚Ø© Ø³ØªØ¬Ø¯ Â«Ù„ÙˆØ­Ø© ØªØ­ÙƒÙ… Ø§Ù„Ø¬Ù…Ù„Ø©Â» ÙÙŠ Ù‚Ø§Ø¦Ù…ØªÙƒ Ø§Ù„Ø¬Ø§Ù†Ø¨ÙŠØ©.',
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
              child: Text('Ø§Ù„Ø¹ÙˆØ¯Ø©', style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.w700)),
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
                  'Ø§Ù†Ø¶Ù… ÙƒØªØ§Ø¬Ø± Ø¬Ù…Ù„Ø© ÙÙŠ Ø¹Ù…Ø§Ø±Ø¬Ùˆ',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'ÙˆØµÙ‘Ù„ Ù…Ù†ØªØ¬Ø§ØªÙƒ Ù„Ø£ØµØ­Ø§Ø¨ Ø§Ù„Ù…ØªØ§Ø¬Ø± ÙÙŠ ÙƒÙ„ Ø§Ù„Ø£Ø±Ø¯Ù†',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(child: _benefit(Icons.people_outline, 'ÙˆØµÙˆÙ„ Ù„Ø¢Ù„Ø§Ù Ø§Ù„Ù…ØªØ§Ø¬Ø±')),
                Expanded(child: _benefit(Icons.trending_up, 'Ø²ÙŠØ§Ø¯Ø© Ù…Ø¨ÙŠØ¹Ø§ØªÙƒ')),
                Expanded(child: _benefit(Icons.security_outlined, 'Ù…Ø¯ÙÙˆØ¹Ø§Øª Ø¢Ù…Ù†Ø©')),
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
                    'Ù…Ø¹Ù„ÙˆÙ…Ø§Øª Ø§Ù„Ø·Ù„Ø¨',
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primaryOrange),
                  ),
                  const SizedBox(height: 16),
                  _buildField(_storeNameCtrl, 'Ø§Ø³Ù… Ø§Ù„Ù…ØªØ¬Ø± *', Icons.store_outlined),
                  _buildField(_phoneCtrl, 'Ø±Ù‚Ù… Ø§Ù„Ù‡Ø§ØªÙ *', Icons.phone_outlined, type: TextInputType.phone),
                  _buildField(_emailCtrl, 'Ø§Ù„Ø¨Ø±ÙŠØ¯ Ø§Ù„Ø¥Ù„ÙƒØªØ±ÙˆÙ†ÙŠ *', Icons.email_outlined, type: TextInputType.emailAddress),
                  _buildField(_descCtrl, 'ÙˆØµÙ Ù†Ø´Ø§Ø·Ùƒ Ø§Ù„ØªØ¬Ø§Ø±ÙŠ *', Icons.description_outlined, maxLines: 3),
                  const SizedBox(height: 16),
                  Text('Ø§Ù„Ù…Ù†Ø§Ø·Ù‚ Ø§Ù„ØªÙŠ ØªØ¹Ù…Ù„ ÙÙŠÙ‡Ø§ *', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _cities.map((city) {
                      final selected = city == 'Ø§Ù„Ø£Ø±Ø¯Ù† ÙƒØ§Ù…Ù„Ø©'
                          ? (_selectedCities.length == 1 && _selectedCities.first == 'all')
                          : _selectedCities.contains(city);
                      return GestureDetector(
                        onTap: () => setState(() {
                          if (city == 'Ø§Ù„Ø£Ø±Ø¯Ù† ÙƒØ§Ù…Ù„Ø©') {
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
                      child: Text('ÙŠØ±Ø¬Ù‰ Ø§Ø®ØªÙŠØ§Ø± Ù…Ù†Ø·Ù‚Ø© ÙˆØ§Ø­Ø¯Ø© Ø¹Ù„Ù‰ Ø§Ù„Ø£Ù‚Ù„',
                          style: GoogleFonts.tajawal(color: Colors.red, fontSize: 12)),
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
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text('Ø¥Ø±Ø³Ø§Ù„ Ø§Ù„Ø·Ù„Ø¨',
                              style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'Ø³ÙŠØªÙ… Ù…Ø±Ø§Ø¬Ø¹Ø© Ø·Ù„Ø¨Ùƒ Ø®Ù„Ø§Ù„ 24 Ø³Ø§Ø¹Ø©',
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
          style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey[700]),
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
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Ù‡Ø°Ø§ Ø§Ù„Ø­Ù‚Ù„ Ù…Ø·Ù„ÙˆØ¨' : null,
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
      if (user == null) throw StateError('ÙŠØ¬Ø¨ ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„ Ø£ÙˆÙ„Ø§Ù‹');

      final profile = context.read<StoreController>().profile;
      final fn = profile?.fullName?.trim();
      final nameHint = (fn != null && fn.isNotEmpty) ? fn : _storeNameCtrl.text.trim();

      await WholesaleRepository.instance.submitWholesalerJoinRequest(
        applicantId: user.uid,
        applicantEmail: _emailCtrl.text.trim(),
        applicantPhone: _phoneCtrl.text.trim(),
        wholesalerName: _storeNameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        category: 'Ø¹Ø§Ù…',
        city: _citySummaryForFirestore(),
        cities: _citiesPayload(),
      );

      await UserNotificationsRepository.sendNotificationToAdmin(
        title: 'Ø·Ù„Ø¨ Ø§Ù†Ø¶Ù…Ø§Ù… ØªØ§Ø¬Ø± Ø¬Ù…Ù„Ø© Ø¬Ø¯ÙŠØ¯',
        body: '$nameHint ÙŠØ·Ù„Ø¨ Ø§Ù„Ø§Ù†Ø¶Ù…Ø§Ù… ÙƒØªØ§Ø¬Ø± Ø¬Ù…Ù„Ø©',
        type: 'wholesale_request',
      );

      if (!mounted) return;
      setState(() => _submitted = true);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ØªØ¹Ø°Ø± Ø¥Ø±Ø³Ø§Ù„ Ø§Ù„Ø·Ù„Ø¨ Ø­Ø§Ù„ÙŠØ§Ù‹. Ø­Ø§ÙˆÙ„ Ù…Ø±Ø© Ø£Ø®Ø±Ù‰.',
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

