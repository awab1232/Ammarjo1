// يتحقق من أن مفتاح Gemini يستجيب بـ HTTP 2xx قبل بناء APK.
//
// تشغيل من جذر المشروع:
//   dart run tool/verify_gemini_api_key.dart
//
// مع مفتاح مؤقت:
//   dart run --dart-define=GEMINI_API_KEY=YOUR_KEY tool/verify_gemini_api_key.dart
//
// (على أنظمة تدعمها) يمكن تعيين متغير البيئة GEMINI_API_KEY بدلاً من dart-define.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:ammar_store/core/config/gemini_api_config.dart';

const _model = 'gemini-1.5-flash';

Future<void> main() async {
  final key = _resolveKeyForCli();
  if (key.isEmpty) {
    stderr.writeln('No usable Gemini API key (dart-define, GEMINI_API_KEY env, or fallback in gemini_api_config.dart).');
    exitCode = 1;
    return;
  }
  final uri = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$key',
  );
  stdout.writeln('Testing Generative Language API (key=${key.substring(0, 6)}…${key.substring(key.length - 4)})…');
  final response = await http
      .post(
        uri,
        headers: const <String, String>{
          'Content-Type': 'application/json',
          'User-Agent': 'AmmarJo-GeminiKeyVerify/1.0',
        },
        body: jsonEncode(<String, dynamic>{
          'contents': <Map<String, dynamic>>[
            <String, dynamic>{
              'parts': <Map<String, dynamic>>[
                <String, dynamic>{'text': 'ping'},
              ],
            },
          ],
          'generationConfig': <String, dynamic>{'maxOutputTokens': 8},
        }),
      )
      .timeout(const Duration(seconds: 45));
  stdout.writeln('HTTP ${response.statusCode}');
  if (response.body.isNotEmpty) {
    final head = response.body.length > 240 ? '${response.body.substring(0, 240)}…' : response.body;
    stdout.writeln(head);
  }
  if (response.statusCode >= 200 && response.statusCode < 300) {
    stdout.writeln('SUCCESS: API key is active (2xx).');
    exitCode = 0;
  } else {
    stderr.writeln('FAILED: expected 2xx. Enable Generative Language API and check billing/quota.');
    exitCode = 1;
  }
}

String _resolveKeyForCli() {
  const fromDefine = String.fromEnvironment('GEMINI_API_KEY');
  final fromEnv = Platform.environment['GEMINI_API_KEY']?.trim() ?? '';
  for (final raw in [fromDefine, fromEnv, kGeminiFallbackApiKey]) {
    final t = raw.trim();
    if (t.length >= 35 && t.startsWith('AIza')) return t;
  }
  return '';
}
