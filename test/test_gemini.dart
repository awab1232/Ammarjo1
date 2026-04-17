// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

const String _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
const String _model = 'gemini-1.5-flash';

String _extractText(Map<String, dynamic> decoded) {
  final candidates = decoded['candidates'];
  if (candidates is! List || candidates.isEmpty) return '';
  final first = candidates.first;
  if (first is! Map<String, dynamic>) return '';
  final content = first['content'];
  if (content is! Map<String, dynamic>) return '';
  final parts = content['parts'];
  if (parts is! List || parts.isEmpty) return '';
  final part0 = parts.first;
  if (part0 is! Map<String, dynamic>) return '';
  return (part0['text']?.toString() ?? '').trim();
}

void main() {
  test(
    'Gemini direct HTTP POST prints response',
    () async {
      if (_geminiApiKey.trim().isEmpty) {
        fail(
          'GEMINI_API_KEY is missing. Run:\n'
          'flutter test test/test_gemini.dart --dart-define=GEMINI_API_KEY=YOUR_KEY',
        );
      }

      const prompt = 'ردّ بجملة واحدة قصيرة بالعربية: ما اسمك وما تقدّم؟';
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_geminiApiKey',
      );

      final body = jsonEncode(<String, dynamic>{
        'contents': <Map<String, dynamic>>[
          <String, dynamic>{
            'parts': <Map<String, dynamic>>[
              <String, dynamic>{'text': prompt},
            ],
          },
        ],
        'generationConfig': <String, dynamic>{
          'temperature': 0.4,
          'maxOutputTokens': 120,
        },
      });

      print('');
      print('--- Sending Gemini HTTP POST ---');
      print(prompt);
      print('---');

      final response = await http
          .post(
            uri,
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'User-Agent': 'AmmarJo-Test/1.0',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        print('HTTP ${response.statusCode}');
        print(response.body);
        fail('Gemini API failed with status ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final text = _extractText(decoded);

      print('--- Gemini Response ---');
      print(text);
      print('--- End Response ---');
      print('');

      expect(text, isNotEmpty, reason: 'Expected non-empty Gemini response text.');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
