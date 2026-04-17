import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../core/config/gemini_config.dart';
import '../../../../core/config/gemini_connection_validation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../domain/models.dart';
import '../ai/gemini_image_analyze.dart';
import '../store_controller.dart';
import 'product_details_page.dart';

/// Ã˜ÂªÃ˜Â¨Ã™Ë†Ã™Å Ã˜Â¨ Ã˜ÂªÃ˜Â­Ã™â€žÃ™Å Ã™â€ž Ã˜Â§Ã™â€žÃ˜ÂµÃ™Ë†Ã˜Â±Ã˜Â© Ã¢â‚¬â€ Ã˜ÂªÃ˜ÂµÃ™Ë†Ã™Å Ã˜Â± Ã˜Â£Ã™Ë† Ã˜Â±Ã™ÂÃ˜Â¹ Ã˜Â«Ã™â€¦ Gemini Ã™Ë†Ã˜Â§Ã™â€šÃ˜ÂªÃ˜Â±Ã˜Â§Ã˜Â­ Ã™â€¦Ã™â€ Ã˜ÂªÃ˜Â¬Ã˜Â§Ã˜Âª + Ã™ÂÃ˜Â¦Ã˜Â© Ã™ÂÃ™â€ Ã™Å  Ã˜Â¹Ã™â€ Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â¹Ã˜Â·Ã™â€ž.
class AiVisionTab extends StatefulWidget {
  const AiVisionTab({super.key, this.onBookMaintenance});

  final VoidCallback? onBookMaintenance;

  @override
  State<AiVisionTab> createState() => _AiVisionTabState();
}

class _AiVisionTabState extends State<AiVisionTab> with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();

  XFile? _pickedFile;
  bool _analyzing = false;
  List<Product> _suggestions = <Product>[];
  late AnimationController _pulseController;

  final List<String> _thinkingSteps = <String>[];
  String? _identifiedItemAr;
  String? _categorySuggestionAr;
  String? _technicianCategoryAr;
  String? _geminiError;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _appendThinking(String line) {
    setState(() => _thinkingSteps.add(line));
  }

  String _mimeForXFile(XFile f) {
    final n = f.name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 88,
      );
      if (!mounted || file == null) return;

      setState(() {
        _pickedFile = file;
        _analyzing = true;
        _suggestions = <Product>[];
        _thinkingSteps.clear();
        _identifiedItemAr = null;
        _categorySuggestionAr = null;
        _technicianCategoryAr = null;
        _geminiError = null;
      });

      _appendThinking('Ã˜ÂªÃ™â€¦ Ã˜Â§Ã˜Â³Ã˜ÂªÃ™â€žÃ˜Â§Ã™â€¦ Ã˜Â§Ã™â€žÃ˜ÂµÃ™Ë†Ã˜Â±Ã˜Â© Ã™Ë†Ã˜Â¬Ã˜Â§Ã˜Â±Ã™Å  Ã˜ÂªÃ˜Â¬Ã™â€¡Ã™Å Ã˜Â² Ã˜Â§Ã™â€žÃ˜Â¨Ã™Å Ã˜Â§Ã™â€ Ã˜Â§Ã˜Âª...');
      await Future<void>.delayed(const Duration(milliseconds: 280));
      if (!mounted) return;

      final bytes = await file.readAsBytes();
      final mime = _mimeForXFile(file);
      _appendThinking('Ã™â€šÃ˜Â±Ã˜Â§Ã˜Â¡Ã˜Â© Ã˜Â§Ã™â€žÃ˜ÂµÃ™Ë†Ã˜Â±Ã˜Â© (${(bytes.length / 1024).toStringAsFixed(1)} Ã™Æ’.Ã˜Â¨) Ã¢â‚¬â€ Ã˜Â¬Ã˜Â§Ã˜Â±Ã™Å  Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã˜Â¶Ã™Å Ã˜Â± Ã™â€žÃ™â€žÃ˜ÂªÃ˜Â­Ã™â€žÃ™Å Ã™â€ž...');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;

      if (!isGeminiConfigured) {
        _appendThinking('Ã˜ÂªÃ™Ë†Ã™â€šÃ™Â: Ã™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­ API Ã˜ÂºÃ™Å Ã˜Â± Ã™â€¦Ã˜Â¶Ã˜Â¨Ã™Ë†Ã˜Â·.');
        setState(() {
          _geminiError = geminiMissingKeyUserMessage;
          _analyzing = false;
        });
        return;
      }

      _appendThinking('Ã˜Â¬Ã˜Â§Ã˜Â±Ã™Å  Ã˜Â¥Ã˜Â±Ã˜Â³Ã˜Â§Ã™â€ž Ã˜Â§Ã™â€žÃ˜ÂµÃ™Ë†Ã˜Â±Ã˜Â© Ã˜Â¥Ã™â€žÃ™â€° Ã™â€ Ã™â€¦Ã™Ë†Ã˜Â°Ã˜Â¬ Ã˜Â§Ã™â€žÃ˜Â°Ã™Æ’Ã˜Â§Ã˜Â¡ Ã˜Â§Ã™â€žÃ˜Â§Ã˜ÂµÃ˜Â·Ã™â€ Ã˜Â§Ã˜Â¹Ã™Å  (Gemini)...');
      String? raw;
      try {
        raw = await analyzeImageWithAI(bytes, mimeType: mime);
      } on FirebaseAIException {
        _appendThinking('Ã™ÂÃ˜Â´Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â·Ã™â€žÃ˜Â¨: unexpected error');
        setState(() {
          _geminiError = 'تعذر تحليل الصورة عبر Gemini.';
          _analyzing = false;
        });
        return;
      } on Object {
        _appendThinking('Ã˜Â­Ã˜Â¯Ã˜Â« Ã˜Â®Ã˜Â·Ã˜Â£ Ã˜Â£Ã˜Â«Ã™â€ Ã˜Â§Ã˜Â¡ Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™â€žÃ™Å Ã™â€ž.');
        setState(() {
          _geminiError = 'unexpected error';
          _analyzing = false;
        });
        return;
      }

      if (!mounted) return;
      _appendThinking('Ã˜Â¬Ã˜Â§Ã˜Â±Ã™Å  Ã˜Â§Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â±Ã˜Â§Ã˜Â¬ Ã˜Â§Ã˜Â³Ã™â€¦ Ã˜Â§Ã™â€žÃ™â€šÃ˜Â·Ã˜Â¹Ã˜Â© Ã™Ë†Ã˜Â§Ã™â€žÃ™â€šÃ˜Â³Ã™â€¦ Ã˜Â§Ã™â€žÃ™â€¦Ã™â€šÃ˜ÂªÃ˜Â±Ã˜Â­ Ã˜Â¨Ã˜Â§Ã™â€žÃ˜Â¹Ã˜Â±Ã˜Â¨Ã™Å Ã˜Â©...');
      await Future<void>.delayed(const Duration(milliseconds: 180));

      if (!mounted) return;
      final parsed = _parseGeminiJsonVision(raw);
      final store = context.read<StoreController>();

      setState(() {
        _identifiedItemAr = parsed?['identified_item_ar']?.toString().trim();
        _categorySuggestionAr = parsed?['store_category_ar']?.toString().trim();
        _technicianCategoryAr = parsed?['recommended_technician_category_ar']?.toString().trim();
        if ((_identifiedItemAr == null || _identifiedItemAr!.isEmpty) && raw != null && raw.trim().isNotEmpty) {
          _identifiedItemAr = raw.trim();
        }
        _suggestions = _buildSuggestedProducts(store);
        _analyzing = false;
      });
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(kIsWeb ? 'Ã˜ÂªÃ˜Â¹Ã˜Â°Ã˜Â± Ã˜Â§Ã˜Â®Ã˜ÂªÃ™Å Ã˜Â§Ã˜Â± Ã˜Â§Ã™â€žÃ˜ÂµÃ™Ë†Ã˜Â±Ã˜Â©. Ã˜Â¬Ã˜Â±Ã™â€˜Ã˜Â¨ Ã™â€¦Ã˜ÂªÃ˜ÂµÃ™ÂÃ˜Â­Ã˜Â§Ã™â€¹ Ã™Å Ã˜Â¯Ã˜Â¹Ã™â€¦ Ã˜Â§Ã˜Â®Ã˜ÂªÃ™Å Ã˜Â§Ã˜Â± Ã˜Â§Ã™â€žÃ™â€žÃ™ÂÃ˜Â§Ã˜Âª.' : 'حدث خطأ أثناء اختيار الصورة'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {
        _analyzing = false;
      });
    }
  }

  void _showSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt_rounded, color: AppColors.orange),
                title: const Text('Ã˜Â§Ã™â€žÃ˜ÂªÃ™â€šÃ˜Â§Ã˜Â· Ã˜ÂµÃ™Ë†Ã˜Â±Ã˜Â© Ã˜Â¨Ã˜Â§Ã™â€žÃ™Æ’Ã˜Â§Ã™â€¦Ã™Å Ã˜Â±Ã˜Â§', textAlign: TextAlign.right),
                onTap: () {
                  Navigator.pop(ctx);
                  _pick(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library_rounded, color: AppColors.orange),
                title: const Text('Ã˜Â§Ã˜Â®Ã˜ÂªÃ™Å Ã˜Â§Ã˜Â± Ã™â€¦Ã™â€  Ã™â€¦Ã˜Â¹Ã˜Â±Ã˜Â¶ Ã˜Â§Ã™â€žÃ˜ÂµÃ™Ë†Ã˜Â±', textAlign: TextAlign.right),
                onTap: () {
                  Navigator.pop(ctx);
                  _pick(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _reset() {
    setState(() {
      _pickedFile = null;
      _analyzing = false;
      _suggestions = <Product>[];
      _thinkingSteps.clear();
      _identifiedItemAr = null;
      _categorySuggestionAr = null;
      _technicianCategoryAr = null;
      _geminiError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    const maxContent = 560.0;
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPad = width > 600 ? 32.0 : 20.0;

    return ColoredBox(
      color: AppColors.orangeLight,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxContent),
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: horizontalPad, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadow,
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 44, color: AppColors.orange.withValues(alpha: 0.9)),
                      const SizedBox(height: 12),
                      Text(
                        'Ã˜ÂµÃ™Ë†Ã™â€˜Ã˜Â± Ã˜Â§Ã™â€žÃ™â€šÃ˜Â·Ã˜Â¹Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã™Æ’Ã˜Â³Ã™Ë†Ã˜Â±Ã˜Â© Ã˜Â£Ã™Ë† Ã˜Â§Ã˜Â±Ã™ÂÃ˜Â¹ Ã˜ÂµÃ™Ë†Ã˜Â±Ã˜ÂªÃ™â€¡Ã˜Â§ Ã™Ë†Ã˜Â³Ã™â€ Ã˜Â³Ã˜Â§Ã˜Â¹Ã˜Â¯Ã™Æ’ Ã™ÂÃ™Å  Ã˜Â¥Ã™Å Ã˜Â¬Ã˜Â§Ã˜Â¯ Ã˜Â¨Ã˜Â¯Ã˜Â§Ã˜Â¦Ã™â€ž Ã™â€¦Ã™â€  Ã˜Â§Ã™â€žÃ™â€¦Ã˜ÂªÃ˜Â¬Ã˜Â±.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: width > 500 ? 16 : 14,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                if (_pickedFile == null && !_analyzing) _CaptureButton(onPressed: _showSourceSheet),
                if (_pickedFile != null) ...[
                  _ImagePreview(file: _pickedFile!),
                  const SizedBox(height: 20),
                ],
                if (_analyzing || _thinkingSteps.isNotEmpty)
                  _ThinkingProcessBlock(
                    pulse: _pulseController,
                    steps: List<String>.from(_thinkingSteps),
                    busy: _analyzing,
                  ),
                if (_geminiError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      _geminiError!,
                      textAlign: TextAlign.right,
                      style: TextStyle(color: Colors.red.shade900, height: 1.35),
                    ),
                  ),
                ],
                if (!_analyzing && _identifiedItemAr != null && _identifiedItemAr!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _IdentifiedResultCard(
                    itemNameAr: _identifiedItemAr!,
                    categoryAr: _categorySuggestionAr,
                    technicianCategoryAr: _technicianCategoryAr,
                    onBookMaintenance: widget.onBookMaintenance,
                  ),
                ],
                if (!_analyzing && _suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Ã˜Â§Ã™â€šÃ˜ÂªÃ˜Â±Ã˜Â§Ã˜Â­Ã˜Â§Ã˜Âª Ã™â€šÃ˜Â¯ Ã˜ÂªÃ™â€ Ã˜Â§Ã˜Â³Ã˜Â¨Ã™Æ’',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  ..._suggestions.map((p) => _SuggestionTile(product: p)),
                ],
                if (!_analyzing && _pickedFile != null && (_suggestions.isNotEmpty || _geminiError != null)) ...[
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _reset,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.orange,
                      side: const BorderSide(color: AppColors.orange),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Ã˜ÂªÃ˜Â­Ã™â€žÃ™Å Ã™â€ž Ã˜ÂµÃ™Ë†Ã˜Â±Ã˜Â© Ã˜Â£Ã˜Â®Ã˜Â±Ã™â€°'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Map<String, dynamic>? _parseGeminiJsonVision(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  var s = raw.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', multiLine: true);
  final m = fence.firstMatch(s);
  if (m != null) {
    s = m.group(1)!.trim();
  }
  try {
    final decoded = jsonDecode(s);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
  } on Object {
    debugPrint('Failed to parse Gemini vision JSON payload.');
  }
  return null;
}

List<Product> _buildSuggestedProducts(StoreController store) {
  const keywords = <String>[
    'Ã˜Â³Ã˜Â¨Ã˜Â§Ã™Æ’Ã˜Â©',
    'Ã˜ÂµÃ™â€ Ã˜Â¨Ã™Ë†Ã˜Â±',
    'plumb',
    'pipe',
    'Ã˜Â£Ã˜Â¯Ã˜Â§Ã˜Â©',
    'Ã˜Â¹Ã˜Â¯Ã˜Â©',
    'tool',
    'wrench',
    'Ã™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­',
    'Ã˜Â®Ã˜Â±Ã˜Â·Ã™Ë†Ã™â€¦',
    'valve',
    'Ã˜Â³Ã˜Â¨Ã˜Â§Ã™Æ’',
  ];

  bool matches(Product p) {
    final n = p.name.toLowerCase();
    return keywords.any((k) => n.contains(k.toLowerCase()));
  }

  final pool = <Product>[];
  final seen = <int>{};

  void addUnique(Iterable<Product> items) {
    for (final p in items) {
      if (seen.add(p.id)) pool.add(p);
    }
  }

  addUnique(store.homePlumbing);
  addUnique(store.homeBestSellers);
  addUnique(store.products);

  final preferred = pool.where(matches).take(3).toList();
  if (preferred.length >= 3) return preferred;

  final rest = pool.where((p) => !preferred.any((x) => x.id == p.id));
  final merged = [...preferred, ...rest].take(3).toList();

  while (merged.length < 3) {
    merged.add(_mockSuggestion(merged.length));
  }
  return merged.take(3).toList();
}

Product _mockSuggestion(int index) {
  const ids = [99001, 99002, 99003];
  const names = ['Ã˜ÂµÃ™â€¦Ã˜Â§Ã™â€¦ Ã˜Â³Ã˜Â¨Ã˜Â§Ã™Æ’Ã˜Â© Ã™â€ Ã˜Â­Ã˜Â§Ã˜Â³Ã™Å ', 'Ã˜Â¹Ã˜Â¯Ã˜Â© Ã™Å Ã˜Â¯Ã™Ë†Ã™Å Ã˜Â© Ã™â€¦Ã˜ÂªÃ˜Â¹Ã˜Â¯Ã˜Â¯Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â§Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã˜Â§Ã™â€¦', 'Ã™â€¦Ã™Ë†Ã˜ÂµÃ™â€ž Ã˜Â®Ã˜Â±Ã˜Â·Ã™Ë†Ã™â€¦ Ã™â€¦Ã˜Â±Ã™â€ '];
  const prices = ['12.000', '8.500', '4.000'];
  final i = index.clamp(0, 2);
  return Product(
    id: ids[i],
    name: names[i],
    description: '',
    price: prices[i],
    images: const <String>[],
    categoryIds: const <int>[],
    tagIds: const <int>[],
  );
}

class _CaptureButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _CaptureButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = w > 480 ? 28.0 : 16.0;

    return Material(
      color: AppColors.orange,
      borderRadius: BorderRadius.circular(20),
      elevation: 4,
      shadowColor: AppColors.orange.withValues(alpha: 0.45),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.camera_enhance_rounded, color: Colors.white, size: w > 500 ? 32 : 28),
              const SizedBox(width: 14),
              Flexible(
                child: Text(
                  'Ã˜Â§Ã˜Â¶Ã˜ÂºÃ˜Â· Ã™â€žÃ˜ÂªÃ˜ÂµÃ™Ë†Ã™Å Ã˜Â± Ã˜Â§Ã™â€žÃ™â€šÃ˜Â·Ã˜Â¹Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã™Æ’Ã˜Â³Ã™Ë†Ã˜Â±Ã˜Â© Ã˜Â£Ã™Ë† Ã˜Â±Ã™ÂÃ˜Â¹ Ã˜ÂµÃ™Ë†Ã˜Â±Ã˜Â©',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: w > 500 ? 17 : 15,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final XFile file;

  const _ImagePreview({required this.file});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: FutureBuilder<Uint8List>(
          future: file.readAsBytes(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const ColoredBox(
                color: Colors.white,
                child: Center(child: Icon(Icons.broken_image_outlined, size: 48, color: AppColors.textSecondary)),
              );
            }
            if (!snap.hasData) {
              return const ColoredBox(
                color: Colors.white,
                child: Center(child: CircularProgressIndicator(color: AppColors.orange)),
              );
            }
            return Image.memory(snap.data!, fit: BoxFit.cover);
          },
        ),
      ),
    );
  }
}

class _ThinkingProcessBlock extends StatelessWidget {
  final AnimationController pulse;
  final List<String> steps;
  final bool busy;

  const _ThinkingProcessBlock({
    required this.pulse,
    required this.steps,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: pulse,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 0.92 + pulse.value * 0.08,
                    child: child,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.orangeLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.psychology_rounded, size: 32, color: AppColors.orange),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Ã™â€¦Ã˜Â³Ã˜Â§Ã˜Â± Ã˜ÂªÃ™ÂÃ™Æ’Ã™Å Ã˜Â± AmmarJo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Ã˜Â¬Ã˜Â§Ã˜Â±Ã™Å  Ã˜ÂªÃ˜Â­Ã™â€žÃ™Å Ã™â€ž Ã˜Â§Ã™â€žÃ™â€šÃ˜Â·Ã˜Â¹Ã˜Â© Ã˜Â¨Ã˜Â°Ã™Æ’Ã˜Â§Ã˜Â¡ AmmarJo...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          ...List.generate(steps.length, (i) {
            final isLast = i == steps.length - 1;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (busy && isLast)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orange),
                    )
                  else
                    Icon(Icons.check_circle_rounded, size: 22, color: Colors.green.shade600),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      steps[i],
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        color: isLast && busy ? AppColors.orange : AppColors.textSecondary,
                        fontWeight: isLast && busy ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (busy) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              borderRadius: BorderRadius.circular(4),
              color: AppColors.orange,
              backgroundColor: AppColors.orangeLight,
            ),
          ],
        ],
      ),
    );
  }
}

class _IdentifiedResultCard extends StatelessWidget {
  final String itemNameAr;
  final String? categoryAr;
  final String? technicianCategoryAr;
  final VoidCallback? onBookMaintenance;

  const _IdentifiedResultCard({
    required this.itemNameAr,
    required this.categoryAr,
    this.technicianCategoryAr,
    this.onBookMaintenance,
  });

  bool get _showTechCta {
    final t = technicianCategoryAr?.trim() ?? '';
    if (t.isEmpty) return false;
    return !t.contains('Ã˜ÂºÃ™Å Ã˜Â± Ã™â€¦Ã˜Â·Ã™â€žÃ™Ë†Ã˜Â¨') && !t.contains('Ã™â€žÃ˜Â§ Ã™Å Ã˜Â­Ã˜ÂªÃ˜Â§Ã˜Â¬');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.orangeLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Ã™â€ Ã˜ÂªÃ™Å Ã˜Â¬Ã˜Â© Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â¹Ã˜Â±Ã™Â',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.orange),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            itemNameAr,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          if (categoryAr != null && categoryAr!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Ã™â€šÃ˜Â³Ã™â€¦ Ã˜Â§Ã™â€žÃ™â€¦Ã™â€šÃ˜ÂªÃ˜Â±Ã˜Â­: $categoryAr',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.35),
            ),
          ],
          if (technicianCategoryAr != null && technicianCategoryAr!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Ã™ÂÃ˜Â¦Ã˜Â© Ã˜Â§Ã™â€žÃ™ÂÃ™â€ Ã™Å  Ã˜Â§Ã™â€žÃ™â€¦Ã™â€šÃ˜ÂªÃ˜Â±Ã˜Â­Ã˜Â©: $technicianCategoryAr',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 14, color: AppColors.navy.withValues(alpha: 0.9), height: 1.35, fontWeight: FontWeight.w600),
            ),
          ],
          if (_showTechCta && onBookMaintenance != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onBookMaintenance,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.home_repair_service_rounded, size: 20),
                label: const Text('Ã˜Â§Ã˜Â­Ã˜Â¬Ã˜Â² Ã™ÂÃ™â€ Ã™â€˜Ã™Å Ã˜Â§Ã™â€¹ Ã™â€žÃ™â€¦Ã˜Â¹Ã˜Â§Ã™â€žÃ˜Â¬Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â¹Ã˜Â·Ã™â€ž', textAlign: TextAlign.center),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final Product product;

  const _SuggestionTile({required this.product});

  @override
  Widget build(BuildContext context) {
    final store = context.read<StoreController>();
    final image = product.images.isNotEmpty ? product.images.first : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        shadowColor: AppColors.shadow,
        child: InkWell(
          onTap: () {
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => ProductDetailsPage(product: product)),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: image.isEmpty
                        ? ColoredBox(
                            color: AppColors.orangeLight,
                            child: Icon(Icons.handyman_outlined, color: AppColors.orange.withValues(alpha: 0.6), size: 32),
                          )
                        : ColoredBox(
                            color: AppColors.surfaceSecondary,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Image.network(
                                webSafeImageUrl(image),
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, height: 1.25),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        store.formatPrice(product.price),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppColors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


