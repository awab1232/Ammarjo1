import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:ammar_store/core/session/user_session.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../store/presentation/store_controller.dart';
import '../../../stores/data/store_types_repository.dart';
import '../../../stores/domain/store_type_model.dart';
import '../../data/tender_repository.dart';
import 'tender_offers_screen.dart';

/// شاشة إنشاء مناقصة (اطلب تسعيرة بالصورة).
/// يتم جلب «أنواع المتاجر» ديناميكياً من الخلفية (retail / wholesale / ... إلخ بلا ترميز).
class TenderRequestScreen extends StatefulWidget {
  const TenderRequestScreen({super.key});

  @override
  State<TenderRequestScreen> createState() => _TenderRequestScreenState();
}

class _TenderRequestScreenState extends State<TenderRequestScreen> {
  Uint8List? _imageBytes;
  StoreTypeModel? _selectedStoreType;
  final TextEditingController _descController = TextEditingController();
  bool _isLoading = false;

  bool _loadingTypes = true;
  List<StoreTypeModel> _storeTypes = const <StoreTypeModel>[];
  String? _storeTypesError;

  @override
  void initState() {
    super.initState();
    _loadStoreTypes();
  }

  Future<void> _loadStoreTypes() async {
    setState(() {
      _loadingTypes = true;
      _storeTypesError = null;
    });
    try {
      final state = await StoreTypesRepository.instance.fetchActiveStoreTypes();
      if (!mounted) return;
      if (state is FeatureSuccess<List<StoreTypeModel>>) {
        final list = List<StoreTypeModel>.from(state.data)
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
        setState(() {
          _storeTypes = list.where((t) => t.isActive).toList();
          _loadingTypes = false;
        });
      } else {
        setState(() {
          _storeTypesError = 'تعذر تحميل أنواع المتاجر. جرّب مجدداً لاحقاً.';
          _loadingTypes = false;
        });
      }
    } on Object {
      if (!mounted) return;
      setState(() {
        _storeTypesError = 'تعذر تحميل أنواع المتاجر. جرّب مجدداً لاحقاً.';
        _loadingTypes = false;
      });
    }
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.tajawal()),
        backgroundColor: Colors.red.shade800,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'اطلب تسعيرة بالصورة',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: const Color(0xFFFF6B00),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('صورة الطلب *', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _imageBytes != null ? const Color(0xFFFF6B00) : Colors.grey.shade300,
                      width: 2,
                    ),
                  ),
                  child: _imageBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.memory(_imageBytes!, fit: BoxFit.cover, width: double.infinity),
                        )
                      : Center(
                          child: Text('اضغط لرفع صورة', style: GoogleFonts.tajawal(color: Colors.grey[600])),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'نوع المتجر (القسم) *',
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              _buildStoreTypeField(),
              const SizedBox(height: 24),
              Text(
                'وصف الطلب (اختياري)',
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descController,
                maxLines: 3,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                style: GoogleFonts.tajawal(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B00)),
                  onPressed: (_isLoading || _loadingTypes) ? null : _submitTender,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          'إرسال المناقصة',
                          style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStoreTypeField() {
    if (_loadingTypes) {
      return Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF6B00)),
            ),
            const SizedBox(width: 12),
            Text('جاري تحميل أنواع المتاجر...', style: GoogleFonts.tajawal()),
          ],
        ),
      );
    }
    if (_storeTypesError != null || _storeTypes.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _storeTypesError ?? 'لا توجد أنواع متاجر مفعلة حالياً',
            style: GoogleFonts.tajawal(color: Colors.red.shade700),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loadStoreTypes,
            icon: const Icon(Icons.refresh),
            label: Text('إعادة المحاولة', style: GoogleFonts.tajawal()),
          ),
        ],
      );
    }
    return DropdownButtonFormField<StoreTypeModel>(
      initialValue: _selectedStoreType,
      isExpanded: true,
      decoration: const InputDecoration(border: OutlineInputBorder()),
      items: _storeTypes
          .map(
            (t) => DropdownMenuItem<StoreTypeModel>(
              value: t,
              child: Text(t.name, style: GoogleFonts.tajawal()),
            ),
          )
          .toList(),
      onChanged: (val) => setState(() => _selectedStoreType = val),
      hint: Text('اختر نوع المتجر', style: GoogleFonts.tajawal(color: Colors.grey.shade600)),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => _imageBytes = bytes);
  }

  Future<void> _submitTender() async {
    if (_imageBytes == null) {
      _showError('يرجى رفع صورة الطلب');
      return;
    }
    final type = _selectedStoreType;
    if (type == null) {
      _showError('يرجى اختيار نوع المتجر');
      return;
    }

    if (!UserSession.isLoggedIn) {
      _showError('يرجى تسجيل الدخول أولاً');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final profile = context.read<StoreController>().profile;
      final city = profile?.city?.trim().isNotEmpty == true
          ? profile!.city!.trim()
          : (profile?.addressLine?.trim().isNotEmpty == true ? profile!.addressLine!.trim() : 'عمّان');
      final userName = profile?.displayName ??
          (UserSession.currentEmail.isNotEmpty ? UserSession.currentEmail : 'مستخدم');

      final tenderId = await TenderRepository.instance.createTender(
        imageBytes: _imageBytes!,
        category: type.name,
        description: _descController.text.trim(),
        city: city,
        userName: userName,
        storeTypeId: type.id,
        storeTypeKey: type.key,
        storeTypeName: type.name,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => TenderOffersScreen(tenderId: tenderId)),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إرسال مناقصتك بنجاح', style: GoogleFonts.tajawal()),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } on StateError catch (e) {
      final msg = e.message.toString().trim();
      _showError(msg.isNotEmpty ? msg : 'تعذر إرسال المناقصة حالياً.');
    } on Object {
      debugPrint('Tender submission failed.');
      _showError('خطأ غير متوقع. تحقق من الاتصال وحاول لاحقاً.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

Widget buildTenderFab(BuildContext context) {
  return FloatingActionButton.extended(
    heroTag: 'fab_stores_tender_request',
    backgroundColor: const Color(0xFFFF6B00),
    icon: const Icon(Icons.camera_alt_outlined, color: Colors.white),
    label: Text(
      'اطلب تسعيرة بالصورة',
      style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.bold),
    ),
    onPressed: () {
      if (!UserSession.isLoggedIn) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('يرجى تسجيل الدخول أولاً', style: GoogleFonts.tajawal()),
          ),
        );
        return;
      }
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TenderRequestScreen()));
    },
  );
}
