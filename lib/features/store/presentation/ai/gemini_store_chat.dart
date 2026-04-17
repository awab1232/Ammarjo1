import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/config/gemini_config.dart';
import '../../../../core/config/gemini_connection_validation.dart';
import '../../../../core/services/gemini_ai_service.dart';
import '../store_controller.dart';

/// Ã˜Â³Ã™Å Ã˜Â§Ã™â€š Ã˜Â§Ã™â€žÃ™â€¦Ã˜ÂªÃ˜Â¬Ã˜Â± (Ã™â€¦Ã˜Â®Ã˜ÂªÃ˜ÂµÃ˜Â±) Ã™â€žÃ˜Â¥Ã˜Â±Ã˜Â³Ã˜Â§Ã™â€žÃ™â€¡ Ã˜Â¥Ã™â€žÃ™â€° Gemini Ã™â€¦Ã˜Â¹ Ã˜Â³Ã˜Â¤Ã˜Â§Ã™â€ž Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦.
/// Ã™Å Ã™ÂÃ˜Â¨Ã™â€ Ã™â€° Ã™â€¦Ã™â€  [StoreController] Ã˜Â¨Ã˜Â¹Ã˜Â¯ Ã˜ÂªÃ˜Â­Ã™â€¦Ã™Å Ã™â€ž Ã˜Â§Ã™â€žÃ™Æ’Ã˜ÂªÃ˜Â§Ã™â€žÃ™Ë†Ã˜Â¬ Ã™â€¦Ã™â€  **Firestore** (`products` / `product_categories`).
String buildCompactStoreContext(StoreController store) {
  final buf = StringBuffer();
  buf.writeln('Ã™â€¦Ã˜ÂªÃ˜Â¬Ã˜Â± AmmarJo Ã¢â‚¬â€ AmmarJo Construction Materials (Ã™â€¦Ã™Ë†Ã˜Â§Ã˜Â¯ Ã˜Â¨Ã™â€ Ã˜Â§Ã˜Â¡ Ã™Ë†Ã˜ÂªÃ˜Â´Ã™Å Ã™Å Ã˜Â¯): Ã™â€¦Ã™Ë†Ã˜Â§Ã˜Â¯ Ã˜Â¬Ã˜Â§Ã™ÂÃ˜Â©Ã˜Å’ Ã˜Â³Ã˜Â¨Ã˜Â§Ã™Æ’Ã˜Â©Ã˜Å’ Ã˜Â¯Ã™â€¡Ã˜Â§Ã™â€ Ã˜Â§Ã˜ÂªÃ˜Å’ Ã™Æ’Ã™â€¡Ã˜Â±Ã˜Â¨Ã˜Â§Ã˜Â¡ Ã™â€¦Ã™â€ Ã˜Â²Ã™â€žÃ™Å Ã˜Â©Ã˜Å’ Ã˜Â£Ã˜Â¯Ã™Ë†Ã˜Â§Ã˜Âª Ã™Å Ã˜Â¯Ã™Ë†Ã™Å Ã˜Â© Ã™Ë†Ã™Æ’Ã™â€¡Ã˜Â±Ã˜Â¨Ã˜Â§Ã˜Â¦Ã™Å Ã˜Â©Ã˜Å’ Ã™â€¦Ã˜Â¹Ã˜Â¯Ã˜Â§Ã˜Âª Ã™Ë†Ã˜Â³Ã™â€žÃ˜Â§Ã™â€¦Ã˜Â©Ã˜Å’ Ã˜ÂªÃ™Ë†Ã˜Â±Ã™Å Ã˜Â¯ Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ˜Â£Ã˜Â±Ã˜Â¯Ã™â€ . Ã˜Â±Ã™Æ’Ã™â€˜Ã˜Â² Ã˜Â¥Ã˜Â¬Ã˜Â§Ã˜Â¨Ã˜Â§Ã˜ÂªÃ™Æ’ Ã˜Â¹Ã™â€žÃ™â€° Ã™â€¡Ã˜Â°Ã™â€¡ Ã˜Â§Ã™â€žÃ™ÂÃ˜Â¦Ã˜Â§Ã˜Âª Ã™ÂÃ™â€šÃ˜Â·.');
  buf.writeln('Ã˜Â§Ã™â€žÃ˜Â¹Ã™â€¦Ã™â€žÃ˜Â©: ${store.currency.code} (${store.currency.symbol})');
  if (store.categoriesForHomePage.isNotEmpty) {
    buf.writeln('Ã˜Â£Ã™â€šÃ˜Â³Ã˜Â§Ã™â€¦ Ã˜Â§Ã™â€žÃ™â€¦Ã˜ÂªÃ˜Â¬Ã˜Â±: ${store.categoriesForHomePage.map((c) => c.name).take(40).join('Ã˜Å’ ')}');
  }
  if (store.products.isNotEmpty) {
    final lines = store.products.take(50).map((p) {
      final price = store.formatPrice(p.price);
      return 'Ã¢â‚¬Â¢ ${p.name} Ã¢â‚¬â€ $price';
    });
    buf.writeln('Ã˜Â¹Ã™Å Ã™â€˜Ã™â€ Ã˜Â© Ã™â€¦Ã™â€  Ã˜Â§Ã™â€žÃ™â€¦Ã™â€ Ã˜ÂªÃ˜Â¬Ã˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ™â€¦Ã˜ÂªÃ™Ë†Ã™ÂÃ˜Â±Ã˜Â©:');
    buf.writeln(lines.join('\n'));
  } else {
    buf.writeln('Ã™â€žÃ˜Â§ Ã˜ÂªÃ˜ÂªÃ™Ë†Ã™ÂÃ˜Â± Ã™â€šÃ˜Â§Ã˜Â¦Ã™â€¦Ã˜Â© Ã™â€¦Ã™â€ Ã˜ÂªÃ˜Â¬Ã˜Â§Ã˜Âª Ã™â€¦Ã˜Â­Ã™â€¦Ã™â€˜Ã™â€žÃ˜Â© Ã˜Â­Ã˜Â§Ã™â€žÃ™Å Ã˜Â§Ã™â€¹Ã˜â€º Ã˜Â£Ã˜Â¬Ã˜Â¨ Ã˜Â¨Ã˜Â´Ã™Æ’Ã™â€ž Ã˜Â¹Ã˜Â§Ã™â€¦ Ã™Ë†Ã™ÂÃ™â€š Ã˜ÂªÃ˜Â®Ã˜ÂµÃ˜Âµ Ã˜Â§Ã™â€žÃ™â€¦Ã˜ÂªÃ˜Â¬Ã˜Â±.');
  }
  return buf.toString();
}

/// Ã˜Â±Ã˜Â¯Ã™â€˜ Ã™â€¦Ã˜Â³Ã˜Â§Ã˜Â¹Ã˜Â¯ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â© Ã˜Â¨Ã˜Â§Ã™â€žÃ˜Â¹Ã˜Â±Ã˜Â¨Ã™Å Ã˜Â© Ã˜Â§Ã˜Â¹Ã˜ÂªÃ™â€¦Ã˜Â§Ã˜Â¯Ã˜Â§Ã™â€¹ Ã˜Â¹Ã™â€žÃ™â€° Ã˜Â³Ã™Å Ã˜Â§Ã™â€š Ã˜Â§Ã™â€žÃ™â€¦Ã˜ÂªÃ˜Â¬Ã˜Â± Ã™Ë† [appContext] Ã˜Â§Ã™â€žÃ˜Â§Ã˜Â®Ã˜ÂªÃ™Å Ã˜Â§Ã˜Â±Ã™Å  Ã™â€¦Ã™â€  Firestore.
Future<String> chatWithStoreAssistant({
  required String userMessage,
  required String storeContext,
  String appContext = '',
}) async {
  if (!isGeminiConfigured) {
    return geminiMissingKeyUserMessage;
  }

  // Ã™â€žÃ˜Â§ Ã™â€ Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ systemInstruction Ã¢â‚¬â€ Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â¹Ã™â€žÃ™Å Ã™â€¦Ã˜Â§Ã˜Âª Ã™Ë†Ã˜Â§Ã™â€žÃ˜Â³Ã™Å Ã˜Â§Ã™â€š Ã™ÂÃ™Å  Ã˜Â£Ã™Ë†Ã™â€ž Ã˜Â±Ã˜Â³Ã˜Â§Ã™â€žÃ˜Â© Ã™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ ([Content.text]).
  final prompt = StringBuffer()
    ..writeln(kGeminiSystemPrompt)
    ..writeln(kGeminiChatMarkerSuffix)
    ..writeln('[Ã˜Â³Ã™Å Ã˜Â§Ã™â€š Ã˜Â§Ã™â€žÃ™â€¦Ã˜ÂªÃ˜Â¬Ã˜Â±]')
    ..writeln(storeContext);
  if (appContext.trim().isNotEmpty) {
    prompt.writeln('[Ã˜Â¨Ã™Å Ã˜Â§Ã™â€ Ã˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â·Ã˜Â¨Ã™Å Ã™â€š Ã™â€¦Ã™â€  Firestore]');
    prompt.writeln(appContext.trim());
  }
  prompt
    ..writeln('--- Ã˜Â³Ã˜Â¤Ã˜Â§Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â¹Ã™â€¦Ã™Å Ã™â€ž ---')
    ..writeln(userMessage);

  try {
    if (useGeminiHttpDueToRuntimeKey) {
      final viaHttp = await generateGeminiViaHttp(prompt: prompt.toString());
      final tHttp = viaHttp.trim();
      if (tHttp.isEmpty) {
        return 'Ã™â€žÃ™â€¦ Ã˜Â£Ã˜ÂªÃ™â€¦Ã™Æ’Ã™â€  Ã™â€¦Ã™â€  Ã˜Â¥Ã™â€ Ã˜Â´Ã˜Â§Ã˜Â¡ Ã˜Â±Ã˜Â¯. Ã˜Â­Ã˜Â§Ã™Ë†Ã™â€ž Ã˜ÂµÃ™Å Ã˜Â§Ã˜ÂºÃ˜Â© Ã˜Â§Ã™â€žÃ˜Â³Ã˜Â¤Ã˜Â§Ã™â€ž Ã˜Â¨Ã˜Â·Ã˜Â±Ã™Å Ã™â€šÃ˜Â© Ã˜Â£Ã˜Â®Ã˜Â±Ã™â€°.';
      }
      return tHttp;
    }
    final model = createGeminiGenerativeModel();
    final response = await model.generateContent([Content.text(prompt.toString())]);
    final t = response.text?.trim();
    if (t == null || t.isEmpty) {
      return 'Ã™â€žÃ™â€¦ Ã˜Â£Ã˜ÂªÃ™â€¦Ã™Æ’Ã™â€  Ã™â€¦Ã™â€  Ã˜Â¥Ã™â€ Ã˜Â´Ã˜Â§Ã˜Â¡ Ã˜Â±Ã˜Â¯. Ã˜Â­Ã˜Â§Ã™Ë†Ã™â€ž Ã˜ÂµÃ™Å Ã˜Â§Ã˜ÂºÃ˜Â© Ã˜Â§Ã™â€žÃ˜Â³Ã˜Â¤Ã˜Â§Ã™â€ž Ã˜Â¨Ã˜Â·Ã˜Â±Ã™Å Ã™â€šÃ˜Â© Ã˜Â£Ã˜Â®Ã˜Â±Ã™â€°.';
    }
    return t;
  } on Object {
    if (kDebugMode) {
      debugPrint('[Gemini] chatWithStoreAssistant failed: unexpected error');
      debugPrint('$StackTrace.current');
    }
    try {
      if (kDebugMode) {
        debugPrint('[Gemini] Falling back to direct HTTP request...');
      }
      final fallback = await generateGeminiViaHttp(prompt: prompt.toString());
      if (fallback.trim().isNotEmpty) {
        return fallback.trim();
      }
    } on Object {
      if (kDebugMode) {
        debugPrint('[Gemini] HTTP fallback failed: unexpected error');
        debugPrint('$StackTrace.current');
      }
    }
    return 'Ã˜ÂªÃ˜Â¹Ã˜Â°Ã™â€˜Ã˜Â± Ã˜Â§Ã™â€žÃ˜Â§Ã˜ÂªÃ˜ÂµÃ˜Â§Ã™â€ž Ã˜Â¨Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜Â§Ã˜Â¹Ã˜Â¯. Ã˜ÂªÃ˜Â£Ã™Æ’Ã˜Â¯ Ã™â€¦Ã™â€  Ã˜Â§Ã™â€žÃ˜Â¥Ã™â€ Ã˜ÂªÃ˜Â±Ã™â€ Ã˜Âª Ã™Ë†Ã˜ÂµÃ˜Â­Ã˜Â© Ã™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­ Gemini Ã˜Â«Ã™â€¦ Ã˜Â­Ã˜Â§Ã™Ë†Ã™â€ž Ã™â€¦Ã˜Â¬Ã˜Â¯Ã˜Â¯Ã˜Â§Ã™â€¹.';
  }
}

