import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/admin_repository.dart';

class AdminBannerManagerSection extends StatefulWidget {
  const AdminBannerManagerSection({super.key});

  @override
  State<AdminBannerManagerSection> createState() => _AdminBannerManagerSectionState();
}

class _AdminBannerManagerSectionState extends State<AdminBannerManagerSection> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = List<Map<String, dynamic>>.empty(growable: false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final st = await AdminRepository.instance.fetchBanners();
    if (!mounted) return;
    switch (st) {
      case FeatureSuccess(:final data):
        setState(() {
          _items = List<Map<String, dynamic>>.from(data)
            ..sort((a, b) => (a['order'] as num? ?? 0).compareTo((b['order'] as num? ?? 0)));
          _loading = false;
        });
      case FeatureFailure(:final message):
        setState(() {
          _error = message;
          _loading = false;
        });
      default:
        setState(() {
          _error = 'تعذر التحميل';
          _loading = false;
        });
    }
  }

  Future<String?> _pickAndUploadImage(String bannerId) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1280);
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final ref = FirebaseStorage.instance.ref().child('banners/$bannerId.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<void> _openEditor({Map<String, dynamic>? item}) async {
    final titleCtrl = TextEditingController(text: item?['title']?.toString() ?? '');
    final linkCtrl = TextEditingController(text: item?['link']?.toString() ?? '');
    final imageCtrl = TextEditingController(text: item?['imageUrl']?.toString() ?? '');
    final orderCtrl = TextEditingController(text: '${(item?['order'] as num?)?.toInt() ?? _items.length}');
    var saving = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModal) => AlertDialog(
            title: Text(item == null ? 'إضافة بنر' : 'تعديل بنر', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: titleCtrl, decoration: InputDecoration(labelText: 'العنوان', labelStyle: GoogleFonts.tajawal())),
                  const SizedBox(height: 8),
                  TextField(controller: linkCtrl, decoration: InputDecoration(labelText: 'الرابط', labelStyle: GoogleFonts.tajawal())),
                  const SizedBox(height: 8),
                  TextField(controller: imageCtrl, decoration: InputDecoration(labelText: 'رابط الصورة', labelStyle: GoogleFonts.tajawal())),
                  const SizedBox(height: 8),
                  TextField(
                    controller: orderCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'الترتيب', labelStyle: GoogleFonts.tajawal()),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            setModal(() => saving = true);
                            final id = item?['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
                            final url = await _pickAndUploadImage(id);
                            if (url != null) imageCtrl.text = url;
                            setModal(() => saving = false);
                          },
                    icon: const Icon(Icons.upload_file_rounded),
                    label: Text('رفع صورة', style: GoogleFonts.tajawal()),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء', style: GoogleFonts.tajawal())),
              FilledButton(
                onPressed: saving ? null : () => Navigator.pop(ctx, true),
                child: Text('حفظ', style: GoogleFonts.tajawal()),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) return;
    final order = int.tryParse(orderCtrl.text.trim()) ?? 0;
    if (item == null) {
      final st = await AdminRepository.instance.createBanner(
        imageUrl: imageCtrl.text.trim(),
        title: titleCtrl.text.trim(),
        link: linkCtrl.text.trim().isEmpty ? null : linkCtrl.text.trim(),
        order: order,
      );
      if (st case FeatureFailure(:final message)) {
        _toast(message);
        return;
      }
    } else {
      final st = await AdminRepository.instance.updateBanner(
        item['id']?.toString() ?? '',
        imageUrl: imageCtrl.text.trim(),
        title: titleCtrl.text.trim(),
        link: linkCtrl.text.trim(),
        order: order,
      );
      if (st case FeatureFailure(:final message)) {
        _toast(message);
        return;
      }
    }
    await _load();
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final st = await AdminRepository.instance.deleteBanner(item['id']?.toString() ?? '');
    if (st case FeatureFailure(:final message)) {
      _toast(message);
      return;
    }
    await _load();
  }

  Future<void> _move(Map<String, dynamic> item, int delta) async {
    final current = (item['order'] as num?)?.toInt() ?? 0;
    await AdminRepository.instance.updateBanner(item['id']?.toString() ?? '', order: current + delta);
    await _load();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: GoogleFonts.tajawal())));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('إدارة البنرات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18)),
            ),
            FilledButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: Text('إضافة', style: GoogleFonts.tajawal()),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_error != null)
          Text(_error!, style: GoogleFonts.tajawal(color: Colors.red.shade700))
        else if (_items.isEmpty)
          Text('لا يوجد بنرات حالياً', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
        ..._items.map((item) {
          final imageUrl = item['imageUrl']?.toString() ?? '';
          return Card(
            margin: const EdgeInsets.only(top: 12),
            child: ListTile(
              leading: imageUrl.isEmpty
                  ? const Icon(Icons.image_not_supported_outlined)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(imageUrl, width: 56, height: 56, fit: BoxFit.cover),
                    ),
              title: Text(item['title']?.toString() ?? 'بدون عنوان', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
              subtitle: Text('الترتيب: ${item['order'] ?? 0}', style: GoogleFonts.tajawal()),
              trailing: Wrap(
                spacing: 2,
                children: [
                  IconButton(onPressed: () => _move(item, -1), icon: const Icon(Icons.arrow_upward_rounded)),
                  IconButton(onPressed: () => _move(item, 1), icon: const Icon(Icons.arrow_downward_rounded)),
                  IconButton(onPressed: () => _openEditor(item: item), icon: const Icon(Icons.edit_outlined)),
                  IconButton(onPressed: () => _deleteItem(item), icon: const Icon(Icons.delete_outline, color: Colors.red)),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
