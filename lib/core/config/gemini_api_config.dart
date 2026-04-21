/// إعداد مفتاح Google AI (Gemini).
///
/// الأولوية في التطبيق: `--dart-define=GEMINI_API_KEY` → متغير بيئة العملية.
/// لا نستخدم مفتاح fallback ثابت داخل الكود لتفادي مفاتيح مسرّبة.
const String kGeminiApiKeyFromConfig = String.fromEnvironment('GEMINI_API_KEY');

/// معطّل عمداً. استخدم `--dart-define=GEMINI_API_KEY` أو متغير البيئة.
const String kGeminiFallbackApiKey = '';
