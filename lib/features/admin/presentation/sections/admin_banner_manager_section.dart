import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../data/admin_repository.dart';
import '../../../../core/theme/app_colors.dart';

/// تعديل السلايدر العلوي (3 صور)، العروض، والبانر السفلي — يُحفظ في PostgreSQL (`home_cms`).
class AdminBannerManagerSection extends StatefulWidget {
  const AdminBannerManagerSection({super.key});

  @override
  State<AdminBannerManagerSection> createState() => _AdminBannerManagerSectionState();
}

class _AdminBannerManagerSectionState extends State<AdminBannerManagerSection> {
  final List<TextEditingController> _slideImg = List.generate(3, (_) => TextEditingController());
  final List<TextEditingController> _slideTitle = List.generate(3, (_) => TextEditingController());
  final List<TextEditingController> _offerTitle = List.generate(3, (_) => TextEditingController());
  final List<TextEditingController> _offerSub = List.generate(3, (_) => TextEditingController());
  final List<TextEditingController> _offerImg = List.generate(3, (_) => TextEditingController());
  final TextEditingController _bottomImg = TextEditingController();
  final TextEditingController _bottomTitle = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _slideImg) {
      c.dispose();
    }
    for (final c in _slideTitle) {
      c.dispose();
    }
    for (final c in _offerTitle) {
      c.dispose();
    }
    for (final c in _offerSub) {
      c.dispose();
    }
    for (final c in _offerImg) {
      c.dispose();
    }
    _bottomImg.dispose();
    _bottomTitle.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final st = await AdminRepository.instance.fetchHomeCms();
    if (!mounted) return;
    switch (st) {
      case FeatureSuccess(:final data):
        _applyFromMap(data);
        setState(() => _loading = false);
      case FeatureFailure(:final message):
        setState(() {
          _loading = false;
          _error = message;
        });
      default:
        setState(() {
          _loading = false;
          _error = 'تعذر التحميل';
        });
    }
  }

  void _applyFromMap(Map<String, dynamic> data) {
    final slides = data['primarySlider'];
    if (slides is List) {
      for (var i = 0; i < 3; i++) {
        if (i < slides.length && slides[i] is Map) {
          final m = Map<String, dynamic>.from(slides[i] as Map);
          _slideImg[i].text = (m['imageUrl'] ?? m['image'] ?? '').toString();
          _slideTitle[i].text = (m['title'] ?? '').toString();
        }
      }
    }
    final offers = data['offers'];
    if (offers is List) {
      for (var i = 0; i < 3; i++) {
        if (i < offers.length && offers[i] is Map) {
          final m = Map<String, dynamic>.from(offers[i] as Map);
          _offerTitle[i].text = (m['title'] ?? '').toString();
          _offerSub[i].text = (m['subtitle'] ?? '').toString();
          _offerImg[i].text = (m['imageUrl'] ?? m['image'] ?? '').toString();
        }
      }
    }
    final bottom = data['bottomBanner'];
    if (bottom is Map) {
      final m = Map<String, dynamic>.from(bottom);
      _bottomImg.text = (m['imageUrl'] ?? m['image'] ?? '').toString();
      _bottomTitle.text = (m['title'] ?? '').toString();
    }
  }

  List<Map<String, dynamic>> _buildSlides() {
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < 3; i++) {
      final imageUrl = _slideImg[i].text.trim();
      final title = _slideTitle[i].text.trim();
      if (imageUrl.isEmpty) continue;
      out.add({
        'id': 's${i + 1}',
        'imageUrl': imageUrl,
        'title': title,
      });
    }
    return out;
  }

  List<Map<String, dynamic>> _buildOffers() {
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < 3; i++) {
      final imageUrl = _offerImg[i].text.trim();
      final title = _offerTitle[i].text.trim();
      if (imageUrl.isEmpty) continue;
      final row = <String, dynamic>{
        'id': 'o${i + 1}',
        'imageUrl': imageUrl,
        'title': title.isEmpty ? 'عرض' : title,
      };
      final sub = _offerSub[i].text.trim();
      if (sub.isNotEmpty) row['subtitle'] = sub;
      out.add(row);
    }
    return out;
  }

  Map<String, dynamic>? _buildBottom() {
    final imageUrl = _bottomImg.text.trim();
    if (imageUrl.isEmpty) return null;
    return {
      'id': 'b1',
      'imageUrl': imageUrl,
      'title': _bottomTitle.text.trim(),
    };
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'primarySlider': _buildSlides(),
      'offers': _buildOffers(),
      'bottomBanner': _buildBottom(),
    };
    final st = await AdminRepository.instance.patchHomeCms(body);
    if (!mounted) return;
    switch (st) {
      case FeatureSuccess():
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم الحفظ', style: GoogleFonts.tajawal())),
        );
      case FeatureFailure(:final message):
        setState(() {
          _saving = false;
          _error = message;
        });
      default:
        setState(() {
          _saving = false;
          _error = 'فشل الحفظ';
        });
    }
  }

  Widget _field(String label, TextEditingController c, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.tajawal(),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('الصفحة الرئيسية — البنرات والعروض', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 8),
        Text(
          'يُعرض المحتوى للعملاء عبر واجهات GET /home/cms و GET /banners. أقسام المتاجر (كروت) تُدار من تبويب «الأقسام الرئيسية» داخل المتاجر.',
          style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.45, fontSize: 13),
          textAlign: TextAlign.right,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: GoogleFonts.tajawal(color: Colors.red.shade800)),
        ],
        const SizedBox(height: 20),
        Text('السلايدر العلوي (3 صور)', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        for (var i = 0; i < 3; i++) ...[
          Text('شريحة ${i + 1}', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
          _field('رابط الصورة', _slideImg[i], maxLines: 2),
          _field('العنوان', _slideTitle[i]),
          const Divider(height: 24),
        ],
        Text('قسم العروض', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        for (var i = 0; i < 3; i++) ...[
          Text('عرض ${i + 1}', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
          _field('العنوان', _offerTitle[i]),
          _field('وصف قصير (اختياري)', _offerSub[i]),
          _field('رابط الصورة', _offerImg[i], maxLines: 2),
          const Divider(height: 24),
        ],
        Text('البانر السفلي', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        _field('رابط الصورة', _bottomImg, maxLines: 2),
        _field('النص على الصورة', _bottomTitle),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded),
          label: Text('حفظ', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange, padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _saving ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('إعادة التحميل من الخادم', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
