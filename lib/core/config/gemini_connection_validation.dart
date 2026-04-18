import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'gemini_config.dart';
import '../services/gemini_ai_service.dart';

/// سبب فشل [validateGeminiConnection] — لعرض رسائل مناسبة في الواجهة أو السجلات التشخيصية.
enum GeminiValidationFailureKind {
  missingKey,
  network,
  invalidKey,
  timeout,
  blockedOrSafety,
  unsupportedLocation,
  serverError,
  emptyResponse,
  unknown,
}

/// نتيجة التحقق من اتصال Gemini (Firebase AI Logic + النموذج من [GeminiConfig.kGeminiModel]).
class GeminiConnectionValidationResult {
  const GeminiConnectionValidationResult._({
    required this.isSuccess,
    this.userMessage,
    this.kind,
  });

  final bool isSuccess;
  final String? userMessage;
  final GeminiValidationFailureKind? kind;

  factory GeminiConnectionValidationResult.success() =>
      const GeminiConnectionValidationResult._(isSuccess: true);

  factory GeminiConnectionValidationResult.failure(
    String userMessage,
    GeminiValidationFailureKind kind,
  ) =>
      GeminiConnectionValidationResult._(
        isSuccess: false,
        userMessage: userMessage,
        kind: kind,
      );
}

void _validateDevLog(String message) {
  if (kDebugMode) {
    debugPrint('[Gemini validate] $message');
  }
}

/// يتحقق من المفتاح والشبكة عبر طلب توليد نصي قصير جداً ([createGeminiGenerativeModel] أو HTTP عند غياب Firebase).
///
/// لا يُسجّل المفتاح في الإنتاج؛ التفاصيل التقنية تظهر في [kDebugMode] فقط.
Future<GeminiConnectionValidationResult> validateGeminiConnection() async {
  if (!isGeminiConfigured) {
    return GeminiConnectionValidationResult.failure(
      kGeminiMissingKeyUserMessage,
      GeminiValidationFailureKind.missingKey,
    );
  }

  if (Firebase.apps.isEmpty || useGeminiHttpDueToRuntimeKey) {
    try {
      await validateGeminiApiAccess();
      return GeminiConnectionValidationResult.success();
    } on GeminiServiceException {
      return GeminiConnectionValidationResult.failure(
        'تعذّر التحقق من اتصال Gemini.',
        GeminiValidationFailureKind.network,
      );
    } on Object {
      _validateDevLog('validateGeminiApiAccess failed');
      return GeminiConnectionValidationResult.failure(
        'تعذّر التحقق من اتصال المساعد الذكي.',
        GeminiValidationFailureKind.unknown,
      );
    }
  }

  try {
    final model = createGeminiGenerativeModel();
    final response = await model
        .generateContent([
          Content.text('رد بكلمة واحدة بالعربية فقط: جاهز'),
        ])
        .timeout(const Duration(seconds: 25));

    String? t;
    try {
      t = response.text?.trim();
    } on FirebaseAIException catch (e) {
      _validateDevLog('FirebaseAIException on response.text');
      final low = e.toString().toLowerCase();
      if (low.contains('blocked')) {
        return GeminiConnectionValidationResult.failure(
          'تم رفض الرد بسبب سياسات المحتوى. للتحقق من الاتصال، جرّب إعدادات شبكة أو مفتاحاً صالحاً.',
          GeminiValidationFailureKind.blockedOrSafety,
        );
      }
      return GeminiConnectionValidationResult.failure(
        'تعذّر قراءة رد النموذج. تحقق من المفتاح والشبكة.',
        GeminiValidationFailureKind.unknown,
      );
    }

    if (t != null && t.isNotEmpty) {
      return GeminiConnectionValidationResult.success();
    }

    return GeminiConnectionValidationResult.failure(
      'لم يُرجع النموذج نصاً. قد يكون الحساب محدوداً أو الخدمة مشغولة.',
      GeminiValidationFailureKind.emptyResponse,
    );
  } on InvalidApiKey {
    _validateDevLog('InvalidApiKey');
    return GeminiConnectionValidationResult.failure(
      'مفتاح Gemini غير صالح أو غير مفعّل. راجع المفتاح في Google AI Studio وفعّل Generative Language API.',
      GeminiValidationFailureKind.invalidKey,
    );
  } on UnsupportedUserLocation {
    _validateDevLog('UnsupportedUserLocation');
    return GeminiConnectionValidationResult.failure(
      'الموقع الجغرافي الحالي غير مدعوم لهذه الواجهة. راجع سياسة Google أو جرّب شبكة أخرى.',
      GeminiValidationFailureKind.unsupportedLocation,
    );
  } on ServerException {
    _validateDevLog('ServerException');
    return GeminiConnectionValidationResult.failure(
      'خطأ من خادم Gemini. حاول لاحقاً.',
      GeminiValidationFailureKind.serverError,
    );
  } on TimeoutException {
    _validateDevLog('TimeoutException');
    return GeminiConnectionValidationResult.failure(
      'انتهت مهلة الاتصال بـ Gemini. تحقق من الشبكة وحاول مرة أخرى.',
      GeminiValidationFailureKind.timeout,
    );
  } on FirebaseAIException catch (e) {
    _validateDevLog('FirebaseAIException');
    final low = e.toString().toLowerCase();
    if (low.contains('api key') ||
        low.contains('permission') ||
        low.contains('401') ||
        low.contains('403') ||
        low.contains('invalid')) {
      return GeminiConnectionValidationResult.failure(
        'مفتاح Gemini غير صحيح أو غير مصرّح به.',
        GeminiValidationFailureKind.invalidKey,
      );
    }
    return GeminiConnectionValidationResult.failure(
      'فشل التحقق. حاول مرة أخرى.',
      GeminiValidationFailureKind.unknown,
    );
  } on Object catch (e) {
    _validateDevLog('unexpected');
    final s = e.toString().toLowerCase();
    if (s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('network') ||
        s.contains('network is unreachable') ||
        s.contains('clientexception') ||
        s.contains('connection refused') ||
        s.contains('connection reset')) {
      return GeminiConnectionValidationResult.failure(
        'لا يوجد اتصال بالإنترنت أو تعذّر الوصول إلى خوادم Google.',
        GeminiValidationFailureKind.network,
      );
    }
    if (s.contains('401') ||
        s.contains('403') ||
        s.contains('api key invalid') ||
        s.contains('api_key_invalid')) {
      return GeminiConnectionValidationResult.failure(
        'مفتاح Gemini غير صالح أو مرفوض.',
        GeminiValidationFailureKind.invalidKey,
      );
    }
    return GeminiConnectionValidationResult.failure(
      'تعذّر التحقق من اتصال المساعد الذكي. حاول لاحقاً.',
      GeminiValidationFailureKind.unknown,
    );
  }
}

/// ما يعرضه المساعد عند عدم ضبط المفتاح (مركز في ملف واحد).
String get geminiMissingKeyUserMessage => kGeminiMissingKeyUserMessage;
