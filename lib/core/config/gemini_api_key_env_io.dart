import 'dart:io' show Platform;

/// Reads `GEMINI_API_KEY` from the process environment (Android, iOS, desktop).
String? geminiKeyFromPlatformEnv() {
  final v = Platform.environment['GEMINI_API_KEY']?.trim();
  if (v == null || v.isEmpty) return null;
  return v;
}
