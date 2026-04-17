import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/gemini_config.dart';
import '../../../../core/services/gemini_ai_service.dart';
import '../../../../core/theme/app_colors.dart';
import 'ai_chat_tab.dart';
import 'ai_vision_tab.dart';

/// Ã™â€¦Ã˜Â³Ã˜Â§Ã˜Â¹Ã˜Â¯ AmmarJo Ã¢â‚¬â€ Ã™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â© Ã™â€ Ã˜ÂµÃ™Å Ã˜Â© + Ã˜ÂªÃ˜Â­Ã™â€žÃ™Å Ã™â€ž Ã˜ÂµÃ™Ë†Ã˜Â±Ã˜Â© (Gemini).
///
/// Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â¹Ã™â€žÃ™Å Ã™â€¦Ã˜Â§Ã˜Âª (`kGeminiSystemPrompt`) Ã™Ë†Ã˜Â¬Ã™â€žÃ˜Â¨ Ã˜Â³Ã™Å Ã˜Â§Ã™â€š Firestore (`getAppContextForAiMessage`) Ã™ÂÃ™Å 
/// `lib/core/services/gemini_ai_service.dart`Ã˜â€º Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â© Ã˜Â§Ã™â€žÃ™â€ Ã˜ÂµÃ™Å Ã˜Â© Ã™ÂÃ™Å  `ai_chat_tab.dart`.
/// Ã˜ÂªÃ™â€¡Ã™Å Ã˜Â¦Ã˜Â© `GenerativeModel` (Ã˜Â¹Ã˜Â¨Ã˜Â± Ã˜Â­Ã˜Â²Ã™â€¦Ã˜Â© `firebase_ai` / Firebase AI Logic) Ã˜ÂªÃ˜ÂªÃ™â€¦ Ã™ÂÃ™Å  `gemini_store_chat.dart`
/// Ã™Ë† `gemini_image_analyze.dart`Ã˜â€º Ã˜Â§Ã™â€žÃ˜Â¥Ã˜Â¹Ã˜Â¯Ã˜Â§Ã˜Â¯Ã˜Â§Ã˜Âª Ã™ÂÃ™Å  [GeminiConfig] (`gemini_config.dart`).
class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key, this.onBookMaintenance, this.onOpenQuantityCalculator});

  /// Ã˜Â§Ã™â€žÃ˜Â§Ã™â€ Ã˜ÂªÃ™â€šÃ˜Â§Ã™â€ž Ã™â€žÃ˜ÂªÃ˜Â¨Ã™Ë†Ã™Å Ã˜Â¨ Ã˜Â§Ã™â€žÃ˜ÂµÃ™Å Ã˜Â§Ã™â€ Ã˜Â© (Ã˜Â­Ã˜Â¬Ã˜Â² Ã™ÂÃ™â€ Ã™Å ).
  final VoidCallback? onBookMaintenance;

  /// Ã™ÂÃ˜ÂªÃ˜Â­ Ã˜Â­Ã˜Â§Ã˜Â³Ã˜Â¨Ã˜Â© Ã˜Â§Ã™â€žÃ™Æ’Ã™â€¦Ã™Å Ã˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ˜Â°Ã™Æ’Ã™Å Ã˜Â©.
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
      SnackBar(content: Text(k.isEmpty ? 'Ã˜ÂªÃ™â€¦ Ã™â€¦Ã˜Â³Ã˜Â­ Ã˜Â§Ã™â€žÃ™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â¤Ã™â€šÃ˜Âª.' : 'Ã˜ÂªÃ™â€¦ Ã˜Â­Ã™ÂÃ˜Â¸ Ã˜Â§Ã™â€žÃ™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­ Ã™â€žÃ™â€¡Ã˜Â°Ã™â€¡ Ã˜Â§Ã™â€žÃ˜Â¬Ã™â€žÃ˜Â³Ã˜Â©.', style: GoogleFonts.tajawal())),
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
        _connectionMessage = 'Ã˜ÂªÃ™â€¦ Ã˜Â§Ã™â€žÃ˜Â§Ã˜ÂªÃ˜ÂµÃ˜Â§Ã™â€ž Ã˜Â¨Ã˜Â®Ã˜Â¯Ã™â€¦Ã˜Â© Gemini Ã˜Â¨Ã™â€ Ã˜Â¬Ã˜Â§Ã˜Â­.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ã¢Å“â€¦ Ã˜Â§Ã˜ÂªÃ˜ÂµÃ˜Â§Ã™â€ž Gemini Ã™Å Ã˜Â¹Ã™â€¦Ã™â€ž Ã˜Â¨Ã˜Â´Ã™Æ’Ã™â€ž Ã˜ÂµÃ˜Â­Ã™Å Ã˜Â­.', style: GoogleFonts.tajawal())),
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
    } on Object {
      if (kDebugMode) {
        debugPrint('AI assistant test: unexpected error');
        debugPrint('$StackTrace.current');
      }
      if (!mounted) return;
      const msg = 'Ã˜Â­Ã˜Â¯Ã˜Â« Ã˜Â®Ã˜Â·Ã˜Â£ Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ˜Â§Ã˜ÂªÃ˜ÂµÃ˜Â§Ã™â€ž Ã˜Â¨Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜Â§Ã˜Â¹Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â°Ã™Æ’Ã™Å . Ã˜ÂªÃ˜Â£Ã™Æ’Ã˜Â¯ Ã™â€¦Ã™â€  Ã˜Â§Ã˜ÂªÃ˜ÂµÃ˜Â§Ã™â€žÃ™Æ’ Ã˜Â¨Ã˜Â§Ã™â€žÃ˜Â¥Ã™â€ Ã˜ÂªÃ˜Â±Ã™â€ Ã˜Âª.';
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
            'Ã™â€¦Ã˜Â³Ã˜Â§Ã˜Â¹Ã˜Â¯ AmmarJo',
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
              Tab(icon: Icon(Icons.chat_bubble_rounded), text: 'Ã™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â©'),
              Tab(icon: Icon(Icons.photo_camera_rounded), text: 'Ã˜ÂµÃ™Ë†Ã˜Â±Ã˜Â©'),
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
                          labelText: 'Ã™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­ API (Ã™â€¦Ã˜Â¤Ã™â€šÃ˜Âª Ã˜Â¹Ã™â€žÃ™â€° Ã™â€¡Ã˜Â°Ã˜Â§ Ã˜Â§Ã™â€žÃ˜Â¬Ã™â€¡Ã˜Â§Ã˜Â²)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                        style: GoogleFonts.tajawal(),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _applyApiKey,
                        style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
                        child: Text('Ã˜Â­Ã™ÂÃ˜Â¸ Ã™Ë†Ã˜Â§Ã™â€žÃ™â€¦Ã˜ÂªÃ˜Â§Ã˜Â¨Ã˜Â¹Ã˜Â©', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
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
                        label: Text('Ã˜Â§Ã˜Â®Ã˜ÂªÃ˜Â¨Ã˜Â§Ã˜Â± Ã˜Â§Ã™â€žÃ˜Â§Ã˜ÂªÃ˜ÂµÃ˜Â§Ã™â€ž Ã˜Â¨Ã™â‚¬ Gemini', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                      ),
                      if (_connectionMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _connectionMessage!,
                          textAlign: TextAlign.right,
                          style: GoogleFonts.tajawal(
                            fontSize: 12,
                            color: _connectionMessage!.contains('Ã˜Â¨Ã™â€ Ã˜Â¬Ã˜Â§Ã˜Â­') ? Colors.green.shade700 : Colors.red.shade700,
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


