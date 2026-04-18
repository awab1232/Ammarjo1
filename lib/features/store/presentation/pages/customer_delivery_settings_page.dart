import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/jordan_regions.dart';
import '../../../../core/data/repositories/user_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../domain/saved_checkout_info.dart';
import '../store_controller.dart';

/// تعديل بيانات التوصيل المحفوظة محلياً (هاتف، عنوان، مدينة).
class CustomerDeliverySettingsPage extends StatefulWidget {
  const CustomerDeliverySettingsPage({super.key});

  @override
  State<CustomerDeliverySettingsPage> createState() => _CustomerDeliverySettingsPageState();
}

class _CustomerDeliverySettingsPageState extends State<CustomerDeliverySettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _country;
  String? _selectedCity;
  bool _loading = true;
  bool _geoBusy = false;
  String? _locationText;

  @override
  void initState() {
    super.initState();
    _firstName = TextEditingController();
    _lastName = TextEditingController();
    _email = TextEditingController();
    _phone = TextEditingController();
    _address = TextEditingController();
    _country = TextEditingController(text: 'JO');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final store = context.read<StoreController>();
      final saved = await store.getSavedCheckoutInfo();
      final p = store.profile;
      if (saved != null) {
        _firstName.text = saved.firstName;
        _lastName.text = saved.lastName;
        _email.text = saved.email;
        _phone.text = saved.phone;
        _address.text = saved.address1;
        _selectedCity = matchJordanRegion(saved.city);
        _country.text = saved.country.isNotEmpty ? saved.country : 'JO';
      }
      if (p != null) {
        if (_email.text.trim().isEmpty) _email.text = p.email;
        if (_firstName.text.trim().isEmpty && (p.fullName ?? '').trim().isNotEmpty) {
          final parts = p.fullName!.trim().split(RegExp(r'\s+'));
          if (parts.isNotEmpty) _firstName.text = parts.first;
          if (parts.length > 1) _lastName.text = parts.sublist(1).join(' ');
        }
        if (_selectedCity == null && p.city != null && p.city!.trim().isNotEmpty) {
          _selectedCity = matchJordanRegion(p.city);
        }
      }
      if (mounted) {
        setState(() => _loading = false);
      }
    });
    _loadSavedGeo();
  }

  Future<void> _loadSavedGeo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await BackendUserRepository.instance.fetchUserDocument(uid);
    final lat = doc?['deliveryLat'];
    final lng = doc?['deliveryLng'];
    if (lat is num && lng is num && mounted) {
      setState(() {
        _locationText = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      });
    }
  }

  Future<void> _pickLocationOnMap() async {
    setState(() => _geoBusy = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('يرجى تفعيل خدمة الموقع.', style: GoogleFonts.tajawal())),
          );
        }
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم رفض إذن الموقع.', style: GoogleFonts.tajawal())),
          );
        }
        return;
      }
      if (perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'إذن الموقع مرفوض بشكل دائم. فعّله من إعدادات المتصفح.',
                style: GoogleFonts.tajawal(),
              ),
            ),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError('انتهت مهلة تحديد الموقع'),
      );
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('سجّل الدخول لحفظ الموقع.', style: GoogleFonts.tajawal())),
          );
        }
        return;
      }
      final locStr = '${pos.latitude}, ${pos.longitude}';
      await BackendUserRepository.instance.updateUserFields(uid, {
        'deliveryLat': pos.latitude,
        'deliveryLng': pos.longitude,
        'deliveryLocation': locStr,
      });
      if (mounted) {
        setState(() {
          _locationText = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تحديد موقعك', style: GoogleFonts.tajawal()),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحديد الموقع. حاول مرة أخرى.', style: GoogleFonts.tajawal()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _geoBusy = false);
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _country.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            leading: const AppBarBackButton(),
            title: Text('تعديل مكان التوصيل', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'تُستخدم هذه البيانات تلقائياً عند إتمام الطلب. لا تُرسل إلى الخادم إلا عند تأكيد الطلب.',
                        style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: _geoBusy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.map_outlined, color: Colors.white),
                        label: Text('تحديد موقعي على الخريطة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B00),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        ),
                        onPressed: _geoBusy ? null : _pickLocationOnMap,
                      ),
                      if (_locationText != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'آخر إحداثيات محفوظة: $_locationText',
                          textAlign: TextAlign.right,
                          style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _tf(_firstName, 'الاسم الأول'),
                      _tf(_lastName, 'اسم العائلة'),
                      _tf(_email, 'البريد (اختياري)', required: false, email: true),
                      _tf(_phone, 'رقم الجوال'),
                      _tf(_address, 'العنوان التفصيلي'),
                      _cityDropdown(),
                      _tf(_country, 'رمز الدولة'),
                      const SizedBox(height: 20),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () async {
                          if (!(_formKey.currentState?.validate() ?? false)) return;
                          final store = context.read<StoreController>();
                          await store.saveDeliveryInfo(
                            SavedCheckoutInfo(
                              firstName: _firstName.text.trim(),
                              lastName: _lastName.text.trim(),
                              email: _email.text.trim(),
                              phone: _phone.text.trim(),
                              address1: _address.text.trim(),
                              city: (_selectedCity ?? '').trim(),
                              country: _country.text.trim().isNotEmpty ? _country.text.trim() : 'JO',
                            ),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تم الحفظ.', style: GoogleFonts.tajawal())),
                          );
                          Navigator.of(context).pop();
                        },
                        child: Text('حفظ', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _cityDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: _selectedCity,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'المحافظة / المدينة',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.white,
        ),
        hint: Text('اختر المحافظة', style: GoogleFonts.tajawal()),
        items: kJordanRegions
            .map(
              (r) => DropdownMenuItem<String>(
                value: r,
                child: Text(r, textAlign: TextAlign.right, style: GoogleFonts.tajawal()),
              ),
            )
            .toList(),
        onChanged: (v) => setState(() => _selectedCity = v),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
      ),
    );
  }

  Widget _tf(TextEditingController c, String label, {bool required = true, bool email = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        textDirection: TextDirection.rtl,
        keyboardType: email ? TextInputType.emailAddress : TextInputType.text,
        validator: (v) {
          if (!required) {
            if (email && v != null && v.trim().isNotEmpty) {
              final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
              return ok ? null : 'صيغة بريد غير صحيحة';
            }
            return null;
          }
          if (v == null || v.trim().isEmpty) return 'مطلوب';
          if (email) {
            final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
            return ok ? null : 'صيغة بريد غير صحيحة';
          }
          return null;
        },
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }
}
