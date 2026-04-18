import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/config/gemini_config.dart';
import '../../../../core/config/gemini_connection_validation.dart';
import '../../../../core/services/gemini_ai_service.dart';

/// تحليل صورة المنتج عبر Gemini (بصري).
Future<String?> analyzeImageWithAI(Uint8List imageBytes, {String mimeType = 'image/jpeg'}) async {
  if (!isGeminiConfigured) {
    throw StateError(geminiMissingKeyUserMessage);
  }

  const prompt = '''
أنت خبير في مواد البناء والتشييد والسباكة والدهانات والكهرباء المنزلية وأدوات الورش لمتجر AmmarJo — متجر مواد بناء في الأردن. حلّل الصورة: إن وُجد عطل أو تلف أو تسريب واضح، صفّه؛ وإلا صف القطعة المرئية.

أجب بالعربية فقط. أرجع كائن JSON واحد بدون markdown، بالمفاتيح:
- "identified_item_ar": اسم مختصر للقطعة أو العطل بالعربية
- "store_category_ar": أنسب تصنيف من أقسام المتجر بالعربية
- "recommended_technician_category_ar": أنسب فئة فني من: سباكة، كهرباء، دهانات، بناء، تركيب بلاط، تكييف — أو "غير مطلوب" إن كان مجرد منتج سليم بدون عطل

مثال عطل: {"identified_item_ar":"تسريب من وصلة ماء","store_category_ar":"الأدوات الصحية","recommended_technician_category_ar":"سباكة"}
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
  } on Object catch (e, st) {
    if (kDebugMode) {
      debugPrint('[Gemini] analyzeImageWithAI failed: $e');
      debugPrint('$st');
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
    } on Object catch (e2, st2) {
      if (kDebugMode) {
        debugPrint('[Gemini] HTTP image fallback failed: $e2');
        debugPrint('$st2');
      }
    }
    rethrow;
  }
}
