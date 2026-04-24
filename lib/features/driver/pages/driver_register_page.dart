import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/services/backend_orders_client.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../store/presentation/pages/login_page.dart';
import '../../store/presentation/store_controller.dart';

/// تسجيل طلب انضمام كسائق — رفع صورة ثم `POST /drivers/request`.
class DriverRegisterPage extends StatefulWidget {
  const DriverRegisterPage({super.key});

  @override
  State<DriverRegisterPage> createState() => _DriverRegisterPageState();
}

class _DriverRegisterPageState extends State<DriverRegisterPage> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  Uint8List? _imageBytes;
  String _imageName = 'id.jpg';
  bool _submitting = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, maxWidth: 2000, imageQuality: 88);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageName = x.name.isNotEmpty ? x.name : 'id.jpg';
      _error = null;
    });
  }

  Future<String?> _uploadImage(User user) async {
    final bytes = _imageBytes;
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final api = await BackendOrdersClient.instance.postUploadIdentityImage(bytes: bytes, fileName: _imageName);
      final url = api?['url']?.toString();
      if (url != null && url.isNotEmpty) return url;
    } on Object {
      // fallback Firebase Storage
    }
    final safe = _imageName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    return StorageService.uploadBytes(
      path: 'driver_requests/${user.uid}/$safe',
      bytes: bytes,
    );
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'يجب تسجيل الدخول أولاً');
      return;
    }
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'أدخل الاسم الكامل');
      return;
    }
    if (phone.length < 8) {
      setState(() => _error = 'أدخل رقم هاتف صالح');
      return;
    }
    if (_imageBytes == null) {
      setState(() => _error = 'ارفع صورة الهوية');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final imageUrl = await _uploadImage(user);
      if (imageUrl == null || imageUrl.isEmpty) {
        if (mounted) {
          setState(() => _error = 'تعذر رفع صورة الهوية');
        }
        return;
      }
      await BackendOrdersClient.instance.postDriverOnboardingRequest(
        fullName: name,
        phone: phone,
        identityImageUrl: imageUrl,
      );
      if (mounted) setState(() => _done = true);
    } on Object {
      if (mounted) {
        setState(() => _error = 'تعذر إرسال الطلب. تحقق من الاتصال أو أن لديك صلاحية orders.write.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: Text('تسجيل كسائق', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
      ),
      body: user == null
          ? _buildNeedLogin(context)
          : _done
              ? _buildDone()
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'املأ البيانات وارفع صورة الهوية. سيتم مراجعة طلبك من الإدارة.',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.tajawal(height: 1.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _nameCtrl,
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        labelText: 'الاسم الكامل',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        labelText: 'رقم الهاتف',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickImage,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(_imageBytes == null ? 'رفع صورة الهوية' : 'تغيير الصورة', style: GoogleFonts.tajawal()),
                    ),
                    if (_imageBytes != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'تم اختيار صورة (${_imageBytes!.length} بايت)',
                          style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!, style: GoogleFonts.tajawal(color: Colors.red.shade800)),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _submitting
                          ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text('تسجيل كسائق', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
    );
  }

  Widget _buildNeedLogin(BuildContext context) {
    final store = context.watch<StoreController>();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('يجب تسجيل الدخول قبل إرسال الطلب.', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: store.isLoading
              ? null
              : () {
                  Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => const LoginPage()));
                },
          child: Text('تسجيل الدخول', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _buildDone() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, color: AppColors.orange, size: 56),
            const SizedBox(height: 16),
            Text(
              'تم إرسال الطلب، سيتم مراجعته',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              'ستصلك لوحة السائق بعد الموافقة من الإدارة.',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop<void>(),
              child: Text('حسناً', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
