import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/config/gemini_config.dart';
import '../../../../core/config/gemini_connection_validation.dart';
import '../../../../core/services/gemini_ai_service.dart';

/// Ã˜ÂªÃ˜Â­Ã™â€žÃ™Å Ã™â€ž Ã˜ÂµÃ™Ë†Ã˜Â±Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã™â€ Ã˜ÂªÃ˜Â¬ Ã˜Â¹Ã˜Â¨Ã˜Â± Gemini (Ã˜Â¨Ã˜ÂµÃ˜Â±Ã™Å ).
Future<String?> analyzeImageWithAI(Uint8List imageBytes, {String mimeType = 'image/jpeg'}) async {
  if (!isGeminiConfigured) {
    throw StateError(geminiMissingKeyUserMessage);
  }

  const prompt = '''
Ã˜Â£Ã™â€ Ã˜Âª Ã˜Â®Ã˜Â¨Ã™Å Ã˜Â± Ã™ÂÃ™Å  Ã™â€¦Ã™Ë†Ã˜Â§Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â¨Ã™â€ Ã˜Â§Ã˜Â¡ Ã™Ë†Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â´Ã™Å Ã™Å Ã˜Â¯ Ã™Ë†Ã˜Â§Ã™â€žÃ˜Â³Ã˜Â¨Ã˜Â§Ã™Æ’Ã˜Â© Ã™Ë†Ã˜Â§Ã™â€žÃ˜Â¯Ã™â€¡Ã˜Â§Ã™â€ Ã˜Â§Ã˜Âª Ã™Ë†Ã˜Â§Ã™â€žÃ™Æ’Ã™â€¡Ã˜Â±Ã˜Â¨Ã˜Â§Ã˜Â¡ Ã˜Â§Ã™â€žÃ™â€¦Ã™â€ Ã˜Â²Ã™â€žÃ™Å Ã˜Â© Ã™Ë†Ã˜Â£Ã˜Â¯Ã™Ë†Ã˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ™Ë†Ã˜Â±Ã˜Â´ Ã™â€žÃ™â€¦Ã˜ÂªÃ˜Â¬Ã˜Â± AmmarJo Ã¢â‚¬â€ Ã™â€¦Ã˜ÂªÃ˜Â¬Ã˜Â± Ã™â€¦Ã™Ë†Ã˜Â§Ã˜Â¯ Ã˜Â¨Ã™â€ Ã˜Â§Ã˜Â¡ Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ˜Â£Ã˜Â±Ã˜Â¯Ã™â€ . Ã˜Â­Ã™â€žÃ™â€˜Ã™â€ž Ã˜Â§Ã™â€žÃ˜ÂµÃ™Ë†Ã˜Â±Ã˜Â©: Ã˜Â¥Ã™â€  Ã™Ë†Ã™ÂÃ˜Â¬Ã˜Â¯ Ã˜Â¹Ã˜Â·Ã™â€ž Ã˜Â£Ã™Ë† Ã˜ÂªÃ™â€žÃ™Â Ã˜Â£Ã™Ë† Ã˜ÂªÃ˜Â³Ã˜Â±Ã™Å Ã˜Â¨ Ã™Ë†Ã˜Â§Ã˜Â¶Ã˜Â­Ã˜Å’ Ã˜ÂµÃ™ÂÃ™â€˜Ã™â€¡Ã˜â€º Ã™Ë†Ã˜Â¥Ã™â€žÃ˜Â§ Ã˜ÂµÃ™ÂÃ™â€˜ Ã˜Â§Ã™â€žÃ™â€šÃ˜Â·Ã˜Â¹Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â±Ã˜Â¦Ã™Å Ã˜Â©.

Ã˜Â£Ã˜Â¬Ã˜Â¨ Ã˜Â¨Ã˜Â§Ã™â€žÃ˜Â¹Ã˜Â±Ã˜Â¨Ã™Å Ã˜Â© Ã™ÂÃ™â€šÃ˜Â·. Ã˜Â£Ã˜Â±Ã˜Â¬Ã˜Â¹ Ã™Æ’Ã˜Â§Ã˜Â¦Ã™â€  JSON Ã™Ë†Ã˜Â§Ã˜Â­Ã˜Â¯ Ã˜Â¨Ã˜Â¯Ã™Ë†Ã™â€  markdownÃ˜Å’ Ã˜Â¨Ã˜Â§Ã™â€žÃ™â€¦Ã™ÂÃ˜Â§Ã˜ÂªÃ™Å Ã˜Â­:
- "identified_item_ar": Ã˜Â§Ã˜Â³Ã™â€¦ Ã™â€¦Ã˜Â®Ã˜ÂªÃ˜ÂµÃ˜Â± Ã™â€žÃ™â€žÃ™â€šÃ˜Â·Ã˜Â¹Ã˜Â© Ã˜Â£Ã™Ë† Ã˜Â§Ã™â€žÃ˜Â¹Ã˜Â·Ã™â€ž Ã˜Â¨Ã˜Â§Ã™â€žÃ˜Â¹Ã˜Â±Ã˜Â¨Ã™Å Ã˜Â©
- "store_category_ar": Ã˜Â£Ã™â€ Ã˜Â³Ã˜Â¨ Ã˜ÂªÃ˜ÂµÃ™â€ Ã™Å Ã™Â Ã™â€¦Ã™â€  Ã˜Â£Ã™â€šÃ˜Â³Ã˜Â§Ã™â€¦ Ã˜Â§Ã™â€žÃ™â€¦Ã˜ÂªÃ˜Â¬Ã˜Â± Ã˜Â¨Ã˜Â§Ã™â€žÃ˜Â¹Ã˜Â±Ã˜Â¨Ã™Å Ã˜Â©
- "recommended_technician_category_ar": Ã˜Â£Ã™â€ Ã˜Â³Ã˜Â¨ Ã™ÂÃ˜Â¦Ã˜Â© Ã™ÂÃ™â€ Ã™Å  Ã™â€¦Ã™â€ : Ã˜Â³Ã˜Â¨Ã˜Â§Ã™Æ’Ã˜Â©Ã˜Å’ Ã™Æ’Ã™â€¡Ã˜Â±Ã˜Â¨Ã˜Â§Ã˜Â¡Ã˜Å’ Ã˜Â¯Ã™â€¡Ã˜Â§Ã™â€ Ã˜Â§Ã˜ÂªÃ˜Å’ Ã˜Â¨Ã™â€ Ã˜Â§Ã˜Â¡Ã˜Å’ Ã˜ÂªÃ˜Â±Ã™Æ’Ã™Å Ã˜Â¨ Ã˜Â¨Ã™â€žÃ˜Â§Ã˜Â·Ã˜Å’ Ã˜ÂªÃ™Æ’Ã™Å Ã™Å Ã™Â Ã¢â‚¬â€ Ã˜Â£Ã™Ë† "Ã˜ÂºÃ™Å Ã˜Â± Ã™â€¦Ã˜Â·Ã™â€žÃ™Ë†Ã˜Â¨" Ã˜Â¥Ã™â€  Ã™Æ’Ã˜Â§Ã™â€  Ã™â€¦Ã˜Â¬Ã˜Â±Ã˜Â¯ Ã™â€¦Ã™â€ Ã˜ÂªÃ˜Â¬ Ã˜Â³Ã™â€žÃ™Å Ã™â€¦ Ã˜Â¨Ã˜Â¯Ã™Ë†Ã™â€  Ã˜Â¹Ã˜Â·Ã™â€ž

Ã™â€¦Ã˜Â«Ã˜Â§Ã™â€ž Ã˜Â¹Ã˜Â·Ã™â€ž: {"identified_item_ar":"Ã˜ÂªÃ˜Â³Ã˜Â±Ã™Å Ã˜Â¨ Ã™â€¦Ã™â€  Ã™Ë†Ã˜ÂµÃ™â€žÃ˜Â© Ã™â€¦Ã˜Â§Ã˜Â¡","store_category_ar":"Ã˜Â§Ã™â€žÃ˜Â£Ã˜Â¯Ã™Ë†Ã˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ˜ÂµÃ˜Â­Ã™Å Ã˜Â©","recommended_technician_category_ar":"Ã˜Â³Ã˜Â¨Ã˜Â§Ã™Æ’Ã˜Â©"}
''';

  try {
    if (useGeminiHttpDueToRuntimeKey) {
      return generateGeminiViaHttp(
        prompt: prompt,
        imageBytes: imageBytes,
        mimeType: mimeType,
      );
    }
    if (kDebugMode) {
      debugPrint('[Gemini] analyzeImageWithAI: SDK request');
    }
    final model = createGeminiGenerativeModel();
    final response = await model.generateContent([
      Content.multi([
        TextPart(prompt),
        InlineDataPart(mimeType, imageBytes),
      ]),
    ]);
    return response.text;
  } on Object {
    if (kDebugMode) {
      debugPrint('[Gemini] analyzeImageWithAI failed: unexpected error');
      debugPrint('$StackTrace.current');
    }
    try {
      if (kDebugMode) {
        debugPrint('[Gemini] HTTP image fallback...');
      }
      final fallback = await generateGeminiViaHttp(
        prompt: prompt,
        imageBytes: imageBytes,
        mimeType: mimeType,
      );
      if (fallback.trim().isNotEmpty) return fallback.trim();
    } on Object {
      if (kDebugMode) {
        debugPrint('[Gemini] HTTP image fallback failed: unexpected error');
        debugPrint('$StackTrace.current');
      }
    }
    rethrow;
  }
}

