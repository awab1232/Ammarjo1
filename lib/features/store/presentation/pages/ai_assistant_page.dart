import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/gemini_config.dart';
import '../../../../core/services/gemini_ai_service.dart';
import '../../../../core/theme/app_colors.dart';
import 'ai_chat_tab.dart';
import 'ai_vision_tab.dart';

/// مساعد AmmarJo — محادثة نصية + تحليل صورة (Gemini).
///
/// التعليمات (`kGeminiSystemPrompt`) وجلب سياق Firestore (`getAppContextForAiMessage`) في
/// `lib/core/services/gemini_ai_service.dart`؛ المحادثة النصية في `ai_chat_tab.dart`.
/// تهيئة `GenerativeModel` (عبر حزمة `firebase_ai` / Firebase AI Logic) تتم في `gemini_store_chat.dart`
/// و`gemini_image_analyze.dart`؛ الإعدادات في [GeminiConfig] (`gemini_config.dart`).
class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key, this.onBookMaintenance, this.onOpenQuantityCalculator});

  /// الانتقال لتبويب الصيانة (حجز فني).
  final VoidCallback? onBookMaintenance;

  /// فتح حاسبة الكميات الذكية.
  final VoidCallback? onOpenQuantityCalculator;

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  static const _prefsKey = 'gemini_api_key_runtime';
  final TextEditingController _apiKeyCtrl = TextEditingController();
  bool _testingConnection = false;
  String? _connectionMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedKey();
  }

  Future<void> _loadSavedKey() async {
    final p = await SharedPreferences.getInstance();
    final k = p.getString(_prefsKey)?.trim();
    if (k != null && k.isNotEmpty) {
      setGeminiApiKeyRuntimeOverride(k);
      _apiKeyCtrl.text = k;
    }
    if (mounted) setState(() {});
  }

  Future<void> _applyApiKey() async {
    final k = _apiKeyCtrl.text.trim();
    setGeminiApiKeyRuntimeOverride(k.isEmpty ? null : k);
    clearGeminiGenerativeModelCache();
    final p = await SharedPreferences.getInstance();
    if (k.isEmpty) {
      await p.remove(_prefsKey);
    } else {
      await p.setString(_prefsKey, k);
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          k.isEmpty ? 'تم مسح المفتاح المؤقت.' : 'تم حفظ المفتاح لهذه الجلسة.',
          style: GoogleFonts.tajawal(),
        ),
      ),
    );
  }

  Future<void> _testGeminiConnection() async {
    if (_testingConnection) return;
    setState(() {
      _testingConnection = true;
      _connectionMessage = null;
    });
    try {
      await validateGeminiApiAccess();
      if (!mounted) return;
      setState(() {
        _connectionMessage = 'تم الاتصال بخدمة Gemini بنجاح.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'اتصال Gemini يعمل بشكل صحيح.',
            style: GoogleFonts.tajawal(),
          ),
        ),
      );
    } on GeminiServiceException {
      if (kDebugMode) {
        debugPrint('AI assistant test: GeminiServiceException (unexpected error)');
      }
      if (!mounted) return;
      setState(() {
        _connectionMessage = 'تعذر اختبار الاتصال بالمساعد الذكي.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر اختبار الاتصال بالمساعد الذكي.', style: GoogleFonts.tajawal())),
      );
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('AI assistant test: unexpected error: $e');
        debugPrint('$st');
      }
      if (!mounted) return;
      const msg = 'حدث خطأ في الاتصال بالمساعد الذكي. تأكد من اتصالك بالإنترنت.';
      setState(() {
        _connectionMessage = msg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg, style: GoogleFonts.tajawal())),
      );
    } finally {
      if (mounted) {
        setState(() => _testingConnection = false);
      }
    }
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configured = isGeminiConfigured;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.orangeLight,
        extendBody: false,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: AppColors.textPrimary,
          title: Text(
            'مساعد AmmarJo',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          centerTitle: true,
          bottom: TabBar(
            labelColor: AppColors.orange,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.orange,
            indicatorWeight: 3,
            labelStyle: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: GoogleFonts.tajawal(fontWeight: FontWeight.w500, fontSize: 13),
            tabs: const [
              Tab(icon: Icon(Icons.chat_bubble_rounded), text: 'محادثة'),
              Tab(icon: Icon(Icons.photo_camera_rounded), text: 'صورة'),
            ],
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!configured)
              Material(
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        kGeminiMissingKeyUserMessage,
                        style: GoogleFonts.tajawal(fontSize: 12, height: 1.35),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _apiKeyCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'مفتاح API (مؤقت على هذا الجهاز)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                        style: GoogleFonts.tajawal(),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _applyApiKey,
                        style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
                        child: Text('حفظ والمتابعة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _testingConnection ? null : _testGeminiConnection,
                        icon: _testingConnection
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.wifi_tethering_rounded),
                        label: Text('اختبار الاتصال بـ Gemini', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                      ),
                      if (_connectionMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _connectionMessage!,
                          textAlign: TextAlign.right,
                          style: GoogleFonts.tajawal(
                            fontSize: 12,
                            color: _connectionMessage!.contains('نجاح') ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  AiChatTab(
                    onBookMaintenance: widget.onBookMaintenance,
                    onOpenQuantityCalculator: widget.onOpenQuantityCalculator,
                  ),
                  AiVisionTab(onBookMaintenance: widget.onBookMaintenance),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


