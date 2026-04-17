/// مفتاح Google AI (Gemini) — المصدر الوحيد للقيمة الاحتياطية (لا تكرّرها في ملفات أخرى).
///
/// الأولوية في التطبيق: `--dart-define=GEMINI_API_KEY` → متغير بيئة العملية → مفتاح Firebase في `google-services` → [kGeminiFallbackApiKey].
const String kGeminiApiKeyFromConfig = String.fromEnvironment('GEMINI_API_KEY');

/// يُستخدم عندما تكون القيم الأخرى فارغة أو غير صالحة كمفتاح واجهة Google (انظر [refreshGeminiApiKeyAtStartup]).
const String kGeminiFallbackApiKey = 'AIzaSyAoidnJwqUtFe6TAQoodkUJPwuhEUhgJDI';
