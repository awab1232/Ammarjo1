/// إعداد مفتاح Google AI (Gemini).
///
/// الأولوية في التطبيق: `--dart-define=GEMINI_API_KEY` → متغير بيئة العملية.
/// يمكن استخدام fallback ثابت عند الحاجة التشغيلية.
const String kGeminiApiKeyFromConfig = String.fromEnvironment('GEMINI_API_KEY');

/// مفتاح fallback داخل التطبيق.
const String kGeminiFallbackApiKey = 'AIzaSyDvcgiTyyoGfo7r1YHLOzKgQIxwONlgd2A';
