import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/config/gemini_config.dart';
import '../../../../core/config/gemini_connection_validation.dart';
import '../../../../core/services/gemini_ai_service.dart';
import '../store_controller.dart';

/// سياق المتجر (مختصر) لإرساله إلى Gemini مع سؤال المستخدم.
/// يُبنى من [StoreController] بعد تحميل الكتالوج من **Firestore** (`products` / `product_categories`).
String buildCompactStoreContext(StoreController store) {
  final buf = StringBuffer();
  buf.writeln(
    'متجر AmmarJo — AmmarJo Construction Materials (مواد بناء وتشييد): مواد جافة، سباكة، دهانات، '
    'كهرباء منزلية، أدوات يدوية وكهربائية، معدات وسلامة، توريد في الأردن. ركّز إجاباتك على هذه الفئات فقط.',
  );
  buf.writeln('العملة: ${store.currency.code} (${store.currency.symbol})');
  if (store.categoriesForHomePage.isNotEmpty) {
    buf.writeln('أقسام المتجر: ${store.categoriesForHomePage.map((c) => c.name).take(40).join('، ')}');
  }
  if (store.products.isNotEmpty) {
    final lines = store.products.take(50).map((p) {
      final price = store.formatPrice(p.price);
      return '• ${p.name} — $price';
    });
    buf.writeln('عيّنة من المنتجات المتوفرة:');
    buf.writeln(lines.join('\n'));
  } else {
    buf.writeln(
      'لا تتوفر قائمة منتجات محمّلة حالياً؛ أجب بشكل عام وفق تخصص المتجر.',
    );
  }
  return buf.toString();
}

/// ردّ مساعد المحادثة بالاعتماد على سياق المتجر و [appContext] الاختياري من Firestore.
Future<String> chatWithStoreAssistant({
  required String userMessage,
  required String storeContext,
  String appContext = '',
}) async {
  if (!isGeminiConfigured) {
    return geminiMissingKeyUserMessage;
  }

  // لا نستخدم systemInstruction — التعليمات والسياق في أول رسالة مستخدم ([Content.text]).
  final prompt = StringBuffer()
    ..writeln(kGeminiSystemPrompt)
    ..writeln(kGeminiChatMarkerSuffix)
    ..writeln('[سياق المتجر]')
    ..writeln(storeContext);
  if (appContext.trim().isNotEmpty) {
    prompt.writeln('[بيانات التطبيق من Firestore]');
    prompt.writeln(appContext.trim());
  }
  prompt
    ..writeln('--- سؤال العميل ---')
    ..writeln(userMessage);

  try {
    if (useGeminiHttpDueToRuntimeKey) {
      debugPrint('AI REQUEST SENT');
      final viaHttp = await generateGeminiViaHttp(prompt: prompt.toString());
      final tHttp = viaHttp.trim();
      if (tHttp.isEmpty) {
        return 'لم أتمكن من إنشاء رد. حاول صياغة السؤال بطريقة أخرى.';
      }
      return tHttp;
    }
    final model = createGeminiGenerativeModel();
    debugPrint('AI REQUEST SENT');
    final response = await model.generateContent([Content.text(prompt.toString())]);
    final t = response.text?.trim();
    if (t == null || t.isEmpty) {
      return 'لم أتمكن من إنشاء رد. حاول صياغة السؤال بطريقة أخرى.';
    }
    return t;
  } on Object catch (e) {
    debugPrint('FIREBASE ERROR: $e');
    if (kDebugMode) {
      debugPrint('[Gemini] chatWithStoreAssistant failed: $e');
    }
    try {
      if (kDebugMode) {
        debugPrint('[Gemini] Falling back to direct HTTP request...');
      }
      final fallback = await generateGeminiViaHttp(prompt: prompt.toString());
      if (fallback.trim().isNotEmpty) {
        return fallback.trim();
      }
    } on Object catch (e2) {
      if (kDebugMode) {
        debugPrint('[Gemini] HTTP fallback failed: $e2');
      }
    }
    return 'تعذر الاتصال بالمساعد. تأكد من الإنترنت وصحة مفتاح Gemini ثم حاول مجدداً.';
  }
}
