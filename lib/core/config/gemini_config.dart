import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'gemini_api_config.dart';
import 'gemini_api_key_env.dart' if (dart.library.io) 'gemini_api_key_env_io.dart';

/// إعدادات Gemini عبر **Firebase AI Logic** (`firebase_ai`) — المفتاح من [FirebaseOptions.apiKey] بعد تهيئة Firebase.
///
/// لمفتاح تجريبي من شاشة المساعد يُفضّل مسار HTTP في [gemini_ai_service] / المحادثة لأن الـ SDK مرتبط بمشروع Firebase.
class GeminiConfig {
  /// نموذج Flash مستقر.
  static const String kGeminiModel = 'gemini-1.5-flash';

  /// نموذج جاهز للاستخدام (بعد `Firebase.initializeApp`).
  static GenerativeModel createModel() {
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase غير مهيأ');
    }
    final ai = FirebaseAI.googleAI(app: Firebase.app());
    return ai.generativeModel(
      model: kGeminiModel,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        topK: 40,
        topP: 0.95,
        maxOutputTokens: 2048,
      ),
      safetySettings: [
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.medium, null),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.medium, null),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// توافق مع بقية التطبيق: مفتاح مؤقت من شاشة مساعد AI يتقدّم على الملف.
// ---------------------------------------------------------------------------

String? geminiApiKeyRuntimeOverride;

void setGeminiApiKeyRuntimeOverride(String? value) {
  final t = value?.trim();
  geminiApiKeyRuntimeOverride = (t == null || t.isEmpty) ? null : t;
}

const String kGeminiMissingKeyUserMessage =
    'لم يتم تكوين مفتاح Gemini. مرّر --dart-define=GEMINI_API_KEY، أو فعّل مفتاح API في Firebase، أو أدخل مفتاحاً من شاشة مساعد AI.';

String? _startupResolvedKey;

bool _looksLikeGoogleBrowserApiKey(String raw) {
  final t = raw.trim();
  return t.length >= 35 && t.startsWith('AIza');
}

// مفاتيح معروفة بأنها مسرّبة/مرفوضة ويجب عدم استخدامها حتى لو جاءت من runtime أو dart-define.
const Set<String> _blockedGeminiKeys = <String>{
  'AIzaSyAoidnJwqUtFe6TAQoodkUJPwuhEUhgJDI',
};

bool _isBlockedGeminiKey(String key) => _blockedGeminiKeys.contains(key.trim());

/// يحدد المفتاح الفعّال: define → بيئة العملية.
///
/// ملاحظة: مفتاح `Firebase.app().options.apiKey` غالباً مفتاح Firebase/Web وليس
/// مفتاح Gemini المفعّل على Generative Language API، لذلك لا نعتمده تلقائياً هنا.
String _computeEffectiveGeminiKey() {
  final fromDefine = kGeminiApiKeyFromConfig.trim();
  final fromOs = geminiKeyFromPlatformEnv()?.trim() ?? '';
  final fromFallback = kGeminiFallbackApiKey.trim();
  for (final candidate in [fromDefine, fromOs, fromFallback]) {
    if (candidate.isNotEmpty &&
        _looksLikeGoogleBrowserApiKey(candidate) &&
        !_isBlockedGeminiKey(candidate)) {
      return candidate;
    }
  }
  return '';
}

/// يُستدعى مرة بعد [Firebase.initializeApp] في [main] — يعيد قراءة المسارات ويحدّث [_startupResolvedKey].
/// استدعِ [clearGeminiGenerativeModelCache] بعدها من `gemini_ai_service`.
void refreshGeminiApiKeyAtStartup() {
  _startupResolvedKey = _computeEffectiveGeminiKey();
  if (kDebugMode) {
    final k = _startupResolvedKey ?? '';
    final label = k.isEmpty
        ? '(empty)'
        : (k.length <= 8 ? '***' : '${k.substring(0, 4)}...${k.substring(k.length - 4)}');
    debugPrint('[Gemini] refreshGeminiApiKeyAtStartup: effective key $label');
  }
}

/// المفتاح الفعّال لمسار **HTTP** والتحقق: أولوية للمفتاح من الشاشة، ثم نتيجة [refreshGeminiApiKeyAtStartup]، ثم حساب فوري.
String get kGeminiApiKey {
  final runtime = geminiApiKeyRuntimeOverride?.trim();
  if (runtime != null &&
      runtime.isNotEmpty &&
      _looksLikeGoogleBrowserApiKey(runtime) &&
      !_isBlockedGeminiKey(runtime)) {
    return runtime;
  }
  if (_startupResolvedKey != null && _startupResolvedKey!.isNotEmpty) {
    return _startupResolvedKey!;
  }
  return _computeEffectiveGeminiKey();
}

String get kGeminiModel => GeminiConfig.kGeminiModel;

/// `true` عندما يكون المفتاح من الشاشة — نستخدم طلبات HTTP حتى يطابق مفتاح Firebase للـ SDK.
bool get useGeminiHttpDueToRuntimeKey =>
    geminiApiKeyRuntimeOverride != null &&
    geminiApiKeyRuntimeOverride!.trim().isNotEmpty &&
    !_isBlockedGeminiKey(geminiApiKeyRuntimeOverride!);

bool get isGeminiConfigured {
  final runtime = geminiApiKeyRuntimeOverride?.trim();
  if (runtime != null && runtime.isNotEmpty) return true;
  return kGeminiApiKey.trim().isNotEmpty;
}
