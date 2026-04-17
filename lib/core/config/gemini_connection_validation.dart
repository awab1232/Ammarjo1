import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'gemini_config.dart';
import '../services/gemini_ai_service.dart';

/// Ã˜Â³Ã˜Â¨Ã˜Â¨ Ã™ÂÃ˜Â´Ã™â€ž [validateGeminiConnection] Ã¢â‚¬â€ Ã™â€žÃ˜Â¹Ã˜Â±Ã˜Â¶ Ã˜Â±Ã˜Â³Ã˜Â§Ã˜Â¦Ã™â€ž Ã™â€¦Ã™â€ Ã˜Â§Ã˜Â³Ã˜Â¨Ã˜Â© Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ™Ë†Ã˜Â§Ã˜Â¬Ã™â€¡Ã˜Â© Ã˜Â£Ã™Ë† Ã˜Â§Ã™â€žÃ˜Â³Ã˜Â¬Ã™â€žÃ˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â´Ã˜Â®Ã™Å Ã˜ÂµÃ™Å Ã˜Â©.
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

/// Ã™â€ Ã˜ÂªÃ™Å Ã˜Â¬Ã˜Â© Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã™â€¦Ã™â€  Ã˜Â§Ã˜ÂªÃ˜ÂµÃ˜Â§Ã™â€ž Gemini (Firebase AI Logic + Ã˜Â§Ã™â€žÃ™â€ Ã™â€¦Ã™Ë†Ã˜Â°Ã˜Â¬ Ã™â€¦Ã™â€  [GeminiConfig.kGeminiModel]).
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

/// Ã™Å Ã˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã™â€¦Ã™â€  Ã˜Â§Ã™â€žÃ™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­ Ã™Ë†Ã˜Â§Ã™â€žÃ˜Â´Ã˜Â¨Ã™Æ’Ã˜Â© Ã˜Â¹Ã˜Â¨Ã˜Â± Ã˜Â·Ã™â€žÃ˜Â¨ Ã˜ÂªÃ™Ë†Ã™â€žÃ™Å Ã˜Â¯ Ã™â€ Ã˜ÂµÃ™Å  Ã™â€šÃ˜ÂµÃ™Å Ã˜Â± Ã˜Â¬Ã˜Â¯Ã˜Â§Ã™â€¹ ([createGeminiGenerativeModel] Ã˜Â£Ã™Ë† HTTP Ã˜Â¹Ã™â€ Ã˜Â¯ Ã˜ÂºÃ™Å Ã˜Â§Ã˜Â¨ Firebase).
///
/// Ã™â€žÃ˜Â§ Ã™Å Ã™ÂÃ˜Â³Ã˜Â¬Ã™â€˜Ã™Å½Ã™â€ž Ã˜Â§Ã™â€žÃ™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­ Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ˜Â¥Ã™â€ Ã˜ÂªÃ˜Â§Ã˜Â¬Ã˜â€º Ã˜Â§Ã™â€žÃ˜ÂªÃ™ÂÃ˜Â§Ã˜ÂµÃ™Å Ã™â€ž Ã˜Â§Ã™â€žÃ˜ÂªÃ™â€šÃ™â€ Ã™Å Ã˜Â© Ã˜ÂªÃ˜Â¸Ã™â€¡Ã˜Â± Ã™ÂÃ™Å  [kDebugMode] Ã™ÂÃ™â€šÃ˜Â·.
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
        'Ã˜ÂªÃ˜Â¹Ã˜Â°Ã™â€˜Ã˜Â± Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã™â€¦Ã™â€  Ã˜Â§Ã˜ÂªÃ˜ÂµÃ˜Â§Ã™â€ž Gemini.',
        GeminiValidationFailureKind.network,
      );
    } on Object {
      _validateDevLog('validateGeminiApiAccess failed');
      return GeminiConnectionValidationResult.failure(
        'Ã˜ÂªÃ˜Â¹Ã˜Â°Ã™â€˜Ã˜Â± Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã™â€¦Ã™â€  Ã˜Â§Ã˜ÂªÃ˜ÂµÃ˜Â§Ã™â€ž Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜Â§Ã˜Â¹Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â°Ã™Æ’Ã™Å .',
        GeminiValidationFailureKind.unknown,
      );
    }
  }

  try {
    final model = createGeminiGenerativeModel();
    final response = await model
        .generateContent([
          Content.text('Ã˜Â±Ã˜Â¯ Ã˜Â¨Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã™Ë†Ã˜Â§Ã˜Â­Ã˜Â¯Ã˜Â© Ã˜Â¨Ã˜Â§Ã™â€žÃ˜Â¹Ã˜Â±Ã˜Â¨Ã™Å Ã˜Â© Ã™ÂÃ™â€šÃ˜Â·: Ã˜Â¬Ã˜Â§Ã™â€¡Ã˜Â²'),
        ])
        .timeout(const Duration(seconds: 25));

    String? t;
    try {
      t = response.text?.trim();
    } on FirebaseAIException {
      _validateDevLog('FirebaseAIException on response.text');
      final low = '';
      if (low.contains('blocked')) {
        return GeminiConnectionValidationResult.failure(
          'Ã˜ÂªÃ™â€¦ Ã˜Â±Ã™ÂÃ˜Â¶ Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â¯ Ã™â€¦Ã™â€  Ã™â€šÃ™ÂÃ˜Â¨Ã™â€ž Ã˜Â³Ã™Å Ã˜Â§Ã˜Â³Ã˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã˜ÂªÃ™Ë†Ã™â€°. Ã™â€žÃ™â€žÃ˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã™â€¦Ã™â€  Ã˜Â§Ã™â€žÃ˜Â§Ã˜ÂªÃ˜ÂµÃ˜Â§Ã™â€žÃ˜Å’ Ã˜Â¬Ã˜Â±Ã™â€˜Ã˜Â¨ Ã˜Â¥Ã˜Â¹Ã˜Â¯Ã˜Â§Ã˜Â¯Ã˜Â§Ã˜Âª Ã˜Â´Ã˜Â¨Ã™Æ’Ã˜Â© Ã˜Â£Ã™Ë† Ã™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­Ã˜Â§Ã™â€¹ Ã˜ÂµÃ˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€¹.',
          GeminiValidationFailureKind.blockedOrSafety,
        );
      }
      return GeminiConnectionValidationResult.failure(
        'Ã˜ÂªÃ˜Â¹Ã˜Â°Ã™â€˜Ã˜Â± Ã™â€šÃ˜Â±Ã˜Â§Ã˜Â¡Ã˜Â© Ã˜Â±Ã˜Â¯ Ã˜Â§Ã™â€žÃ™â€ Ã™â€¦Ã™Ë†Ã˜Â°Ã˜Â¬. Ã˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã™â€¦Ã™â€  Ã˜Â§Ã™â€žÃ™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­ Ã™Ë†Ã˜Â§Ã™â€žÃ˜Â´Ã˜Â¨Ã™Æ’Ã˜Â©.',
        GeminiValidationFailureKind.unknown,
      );
    }

    if (t != null && t.isNotEmpty) {
      return GeminiConnectionValidationResult.success();
    }

    return GeminiConnectionValidationResult.failure(
      'Ã™â€žÃ™â€¦ Ã™Å Ã™ÂÃ˜Â±Ã˜Â¬Ã˜Â¹ Ã˜Â§Ã™â€žÃ™â€ Ã™â€¦Ã™Ë†Ã˜Â°Ã˜Â¬ Ã™â€ Ã˜ÂµÃ˜Â§Ã™â€¹. Ã™â€šÃ˜Â¯ Ã™Å Ã™Æ’Ã™Ë†Ã™â€  Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â³Ã˜Â§Ã˜Â¨ Ã™â€¦Ã˜Â­Ã˜Â¯Ã™Ë†Ã˜Â¯Ã˜Â§Ã™â€¹ Ã˜Â£Ã™Ë† Ã˜Â§Ã™â€žÃ˜Â®Ã˜Â¯Ã™â€¦Ã˜Â© Ã™â€¦Ã˜Â´Ã˜ÂºÃ™Ë†Ã™â€žÃ˜Â©.',
      GeminiValidationFailureKind.emptyResponse,
    );
  } on InvalidApiKey {
    _validateDevLog('InvalidApiKey');
    return GeminiConnectionValidationResult.failure(
      'Ã™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­ Gemini Ã˜ÂºÃ™Å Ã˜Â± Ã˜ÂµÃ˜Â§Ã™â€žÃ˜Â­ Ã˜Â£Ã™Ë† Ã˜ÂºÃ™Å Ã˜Â± Ã™â€¦Ã™ÂÃ˜Â¹Ã™â€˜Ã™â€ž. Ã˜Â±Ã˜Â§Ã˜Â¬Ã˜Â¹ Ã˜Â§Ã™â€žÃ™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­ Ã™ÂÃ™Å  Google AI Studio Ã™Ë†Ã™ÂÃ˜Â¹Ã™â€˜Ã™â€ž Generative Language API.',
      GeminiValidationFailureKind.invalidKey,
    );
  } on UnsupportedUserLocation {
    _validateDevLog('UnsupportedUserLocation');
    return GeminiConnectionValidationResult.failure(
      'Ã˜Â§Ã™â€žÃ™â€¦Ã™Ë†Ã™â€šÃ˜Â¹ Ã˜Â§Ã™â€žÃ˜Â¬Ã˜ÂºÃ˜Â±Ã˜Â§Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ™Å  Ã˜ÂºÃ™Å Ã˜Â± Ã™â€¦Ã˜Â¯Ã˜Â¹Ã™Ë†Ã™â€¦ Ã™â€žÃ™â€¡Ã˜Â°Ã™â€¡ Ã˜Â§Ã™â€žÃ™Ë†Ã˜Â§Ã˜Â¬Ã™â€¡Ã˜Â©. Ã˜Â±Ã˜Â§Ã˜Â¬Ã˜Â¹ Ã˜Â³Ã™Å Ã˜Â§Ã˜Â³Ã˜Â© Google Ã˜Â£Ã™Ë† Ã˜Â¬Ã˜Â±Ã™â€˜Ã˜Â¨ Ã˜Â´Ã˜Â¨Ã™Æ’Ã˜Â© Ã˜Â£Ã˜Â®Ã˜Â±Ã™â€°.',
      GeminiValidationFailureKind.unsupportedLocation,
    );
  } on ServerException {
    _validateDevLog('ServerException');
    return GeminiConnectionValidationResult.failure(
      'Ã˜Â®Ã˜Â·Ã˜Â£ Ã™â€¦Ã™â€  Ã˜Â®Ã˜Â§Ã˜Â¯Ã™â€¦ Gemini: unexpected error',
      GeminiValidationFailureKind.serverError,
    );
  } on TimeoutException {
    _validateDevLog('TimeoutException');
    return GeminiConnectionValidationResult.failure(
      'Ã˜Â§Ã™â€ Ã˜ÂªÃ™â€¡Ã˜Âª Ã™â€¦Ã™â€¡Ã™â€žÃ˜Â© Ã˜Â§Ã™â€žÃ˜Â§Ã˜ÂªÃ˜ÂµÃ˜Â§Ã™â€ž Ã˜Â¨Ã™â‚¬ Gemini. Ã˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã™â€¦Ã™â€  Ã˜Â§Ã™â€žÃ˜Â´Ã˜Â¨Ã™Æ’Ã˜Â© Ã™Ë†Ã˜Â­Ã˜Â§Ã™Ë†Ã™â€ž Ã™â€¦Ã˜Â±Ã˜Â© Ã˜Â£Ã˜Â®Ã˜Â±Ã™â€°.',
      GeminiValidationFailureKind.timeout,
    );
  } on FirebaseAIException {
    _validateDevLog('FirebaseAIException');
    final low = '';
    if (low.contains('api key') ||
        low.contains('permission') ||
        low.contains('401') ||
        low.contains('403') ||
        low.contains('invalid')) {
      return GeminiConnectionValidationResult.failure(
        'Ã™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­ Gemini Ã˜ÂºÃ™Å Ã˜Â± Ã˜ÂµÃ˜Â­Ã™Å Ã˜Â­ Ã˜Â£Ã™Ë† Ã˜ÂºÃ™Å Ã˜Â± Ã™â€¦Ã˜ÂµÃ˜Â±Ã™â€˜Ã˜Â­ Ã˜Â¨Ã™â€¡.',
        GeminiValidationFailureKind.invalidKey,
      );
    }
    return GeminiConnectionValidationResult.failure(
      'Ã™ÂÃ˜Â´Ã™â€ž Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™â€šÃ™â€š: unexpected error',
      GeminiValidationFailureKind.unknown,
    );
  } on Object {
    _validateDevLog('unexpected');
    final s = '';
    if (s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('network') ||
        s.contains('network is unreachable') ||
        s.contains('clientexception') ||
        s.contains('connection refused') ||
        s.contains('connection reset')) {
      return GeminiConnectionValidationResult.failure(
        'Ã™â€žÃ˜Â§ Ã™Å Ã™Ë†Ã˜Â¬Ã˜Â¯ Ã˜Â§Ã˜ÂªÃ˜ÂµÃ˜Â§Ã™â€ž Ã˜Â¨Ã˜Â§Ã™â€žÃ˜Â¥Ã™â€ Ã˜ÂªÃ˜Â±Ã™â€ Ã˜Âª Ã˜Â£Ã™Ë† Ã˜ÂªÃ˜Â¹Ã˜Â°Ã™â€˜Ã˜Â± Ã˜Â§Ã™â€žÃ™Ë†Ã˜ÂµÃ™Ë†Ã™â€ž Ã˜Â¥Ã™â€žÃ™â€° Ã˜Â®Ã™Ë†Ã˜Â§Ã˜Â¯Ã™â€¦ Google.',
        GeminiValidationFailureKind.network,
      );
    }
    if (s.contains('401') ||
        s.contains('403') ||
        s.contains('api key invalid') ||
        s.contains('api_key_invalid')) {
      return GeminiConnectionValidationResult.failure(
        'Ã™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­ Gemini Ã˜ÂºÃ™Å Ã˜Â± Ã˜ÂµÃ˜Â§Ã™â€žÃ˜Â­ Ã˜Â£Ã™Ë† Ã™â€¦Ã˜Â±Ã™ÂÃ™Ë†Ã˜Â¶.',
        GeminiValidationFailureKind.invalidKey,
      );
    }
    return GeminiConnectionValidationResult.failure(
      'Ã˜ÂªÃ˜Â¹Ã˜Â°Ã™â€˜Ã˜Â± Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã™â€¦Ã™â€  Ã˜Â§Ã˜ÂªÃ˜ÂµÃ˜Â§Ã™â€ž Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜Â§Ã˜Â¹Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â°Ã™Æ’Ã™Å . Ã˜Â­Ã˜Â§Ã™Ë†Ã™â€ž Ã™â€žÃ˜Â§Ã˜Â­Ã™â€šÃ˜Â§Ã™â€¹.',
      GeminiValidationFailureKind.unknown,
    );
  }
}

/// Ã™â€¦Ã˜Â§ Ã™Å Ã˜Â¹Ã˜Â±Ã˜Â¶Ã™â€¡ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜Â§Ã˜Â¹Ã˜Â¯ Ã˜Â¹Ã™â€ Ã˜Â¯ Ã˜Â¹Ã˜Â¯Ã™â€¦ Ã˜Â¶Ã˜Â¨Ã˜Â· Ã˜Â§Ã™â€žÃ™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­ (Ã™â€¦Ã˜Â±Ã™Æ’Ã˜Â² Ã™ÂÃ™Å  Ã™â€¦Ã™â€žÃ™Â Ã™Ë†Ã˜Â§Ã˜Â­Ã˜Â¯).
String get geminiMissingKeyUserMessage => kGeminiMissingKeyUserMessage;

