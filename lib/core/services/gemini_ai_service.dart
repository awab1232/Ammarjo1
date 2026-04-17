import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/gemini_config.dart';
import 'backend_orders_client.dart';

/// خطأ مخصص لخدمة Gemini مع رسالة جاهزة للعرض للمستخدم.
class GeminiServiceException implements Exception {
  const GeminiServiceException(this.userMessage, {this.cause});

  final String userMessage;
  final Object? cause;

  @override
  String toString() => userMessage;
}

String _maskGeminiKey(String key) {
  final k = key.trim();
  if (k.isEmpty) return '(empty)';
  if (k.length <= 8) return '${k.substring(0, 2)}***';
  return '${k.substring(0, 4)}...${k.substring(k.length - 4)}';
}

/// سجلات تشخيصية فقط في **وضع التطوير** — لا تُطبع في الإنتاج.
void _geminiDevLog(String message) {
  if (kDebugMode) {
    debugPrint('[Gemini] $message');
  }
}

GenerativeModel? _cachedGenerativeModel;
String? _cachedGenerativeModelSignature;

String _geminiSdkCacheSignature() {
  if (Firebase.apps.isEmpty) return '';
  // يشمل المفتاح الفعّال لمسار HTTP حتى يُبطَل الكاش عند تغيير الـ fallback بعد التهيئة.
  return '${Firebase.app().options.apiKey}|$kGeminiApiKey|$kGeminiModel';
}

/// يعيد نفس مثيل [GenerativeModel] من **Firebase AI Logic** طالما لم يتغيّر تطبيق Firebase أو النموذج.
///
/// لا يُستخدم عند [useGeminiHttpDueToRuntimeKey] — استخدم [generateGeminiViaHttp] بدلاً منه.
GenerativeModel createGeminiGenerativeModel() {
  if (!isGeminiConfigured) {
    throw const GeminiServiceException(kGeminiMissingKeyUserMessage);
  }
  if (useGeminiHttpDueToRuntimeKey) {
    throw const GeminiServiceException(
      'المفتاح من شاشة المساعد يستخدم طلبات HTTP فقط. استخدم generateGeminiViaHttp.',
    );
  }
  if (Firebase.apps.isEmpty) {
    throw const GeminiServiceException(
      'Firebase غير مهيأ. لا يمكن تهيئة نموذج Gemini عبر Firebase AI.',
    );
  }
  final sig = _geminiSdkCacheSignature();
  if (_cachedGenerativeModel != null && _cachedGenerativeModelSignature == sig) {
    return _cachedGenerativeModel!;
  }
  try {
    final model = GeminiConfig.createModel();
    _cachedGenerativeModel = model;
    _cachedGenerativeModelSignature = sig;
    _geminiDevLog('GenerativeModel cached (Firebase AI) sig=${_maskGeminiKey(Firebase.app().options.apiKey)}');
    return model;
  } on Object {
    _geminiDevLog('GenerativeModel initialization failed');
    rethrow;
  }
}

/// للاختبارات أو إعادة التحميل القسري بعد تغيير المفتاح خارج [kGeminiApiKey].
void clearGeminiGenerativeModelCache() {
  _cachedGenerativeModel = null;
  _cachedGenerativeModelSignature = null;
}

/// يتحقق من صحة الاتصال بـ Gemini عبر طلب HTTP مباشر.
///
/// - يتحقق من وجود المفتاح.
/// - يختبر أن عميل HTTP يستطيع الوصول إلى واجهة Gemini.
/// - يعطي رسالة عربية واضحة عند الفشل.
Future<void> validateGeminiApiAccess({http.Client? client}) async {
  if (!isGeminiConfigured) {
    throw const GeminiServiceException(kGeminiMissingKeyUserMessage);
  }

  final ownedClient = client ?? http.Client();
  final shouldDispose = client == null;
  final candidateVersions = <String>['v1', 'v1beta'];
  _geminiDevLog('validateGeminiApiAccess: key=${_maskGeminiKey(kGeminiApiKey)}');

  try {
    for (final version in candidateVersions) {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/$version/models/$kGeminiModel:generateContent?key=$kGeminiApiKey',
      );
      final response = await ownedClient
          .post(
            uri,
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'User-Agent': 'AmmarJo-App/1.0',
            },
            body: jsonEncode(<String, dynamic>{
              'contents': <Map<String, dynamic>>[
                <String, dynamic>{
                  'parts': <Map<String, dynamic>>[
                    <String, dynamic>{'text': 'جاهز'},
                  ],
                },
              ],
              'generationConfig': <String, dynamic>{
                'temperature': 0.0,
                'maxOutputTokens': 8,
              },
            }),
          )
          .timeout(const Duration(seconds: 45));
      _geminiDevLog('validateGeminiApiAccess($version): HTTP ${response.statusCode}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return;
      }
    }
    throw const GeminiServiceException(
      'تعذّر التحقق من Gemini. تأكد من تفعيل Generative Language API واستخدام نموذج مدعوم لحسابك.',
    );
  } on SocketException {
    _geminiDevLog('SocketException');
    throw GeminiServiceException(
      'لا يوجد اتصال بالإنترنت. تأكد من الشبكة ثم أعد المحاولة.',
      cause: const SocketException('network'),
    );
  } on TimeoutException {
    _geminiDevLog('TimeoutException');
    throw GeminiServiceException(
      'انتهت مهلة الاتصال بخدمة Gemini. حاول مرة أخرى بعد قليل.',
      cause: TimeoutException('timeout'),
    );
  } on http.ClientException {
    _geminiDevLog('ClientException');
    throw GeminiServiceException(
      'تعذّر الاتصال بالشبكة. تحقق من الإنترنت ثم أعد المحاولة.',
      cause: http.ClientException('client'),
    );
  } on GeminiServiceException {
    rethrow;
  } on Object {
    _geminiDevLog('Unknown validation error');
    throw GeminiServiceException(
      'حدث خطأ أثناء التحقق من اتصال المساعد الذكي. حاول مرة أخرى.',
    );
  } finally {
    if (shouldDispose) {
      ownedClient.close();
    }
  }
}

/// fallback HTTP مباشر (بدون SDK) لطلبات النص/الصورة.
Future<String> generateGeminiViaHttp({
  required String prompt,
  Uint8List? imageBytes,
  String mimeType = 'image/jpeg',
  http.Client? client,
}) async {
  if (!isGeminiConfigured) {
    throw const GeminiServiceException(kGeminiMissingKeyUserMessage);
  }
  final ownedClient = client ?? http.Client();
  final shouldDispose = client == null;
    // عدة أسماء نماذج لأن Google تُحدّث المعرّفات؛ الفشل على نموذج يجرّب التالي.
    final candidateModels = <String>{
      kGeminiModel,
      'gemini-2.5-flash',
      'gemini-2.5-flash-lite',
      'gemini-2.5-pro',
      'gemini-2.0-flash-lite',
      'gemini-2.0-flash',
      'gemini-2.0-flash-001',
      'gemini-1.5-flash-002',
      'gemini-1.5-flash',
      'gemini-1.5-flash-8b',
      'gemini-pro',
    }.toList();
  try {
    const versions = <String>['v1', 'v1beta'];
    for (final model in candidateModels) {
      for (final version in versions) {
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/$version/models/$model:generateContent?key=$kGeminiApiKey',
        );
        _geminiDevLog('generateContent HTTP version=$version model=$model key=${_maskGeminiKey(kGeminiApiKey)}');
        final parts = <Map<String, dynamic>>[
          <String, dynamic>{'text': prompt},
        ];
        if (imageBytes != null && imageBytes.isNotEmpty) {
          parts.add(<String, dynamic>{
            'inline_data': <String, dynamic>{
              'mime_type': mimeType,
              'data': base64Encode(imageBytes),
            },
          });
        }
        final reqBody = <String, dynamic>{
          'contents': <Map<String, dynamic>>[
            <String, dynamic>{'parts': parts},
          ],
          'generationConfig': <String, dynamic>{
            'temperature': 0.4,
          },
        };
        try {
          final response = await ownedClient
              .post(
                uri,
                headers: const <String, String>{
                  'Content-Type': 'application/json',
                  'User-Agent': 'AmmarJo-App/1.0',
                },
                body: jsonEncode(reqBody),
              )
              .timeout(const Duration(seconds: 45));
          _geminiDevLog('Response status($version/$model): ${response.statusCode}');
          if (kDebugMode && response.body.isNotEmpty) {
            final bh = response.body.length > 480 ? '${response.body.substring(0, 480)}…' : response.body;
            _geminiDevLog('body head: $bh');
          }
          if (response.statusCode < 200 || response.statusCode >= 300) {
            if (kDebugMode && (response.statusCode == 403 || response.statusCode == 400)) {
              _geminiDevLog(
                'Hint: فعّل Generative Language API في Google Cloud لمشروع المفتاح، أو استخدم مفتاحاً من AI Studio (--dart-define=GEMINI_API_KEY).',
              );
            }
            continue;
          }
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          final candidates = decoded['candidates'];
          if (candidates is List && candidates.isNotEmpty) {
            final content = candidates.first['content'];
            if (content is Map) {
              final contentParts = content['parts'];
              if (contentParts is List && contentParts.isNotEmpty) {
                final text = contentParts.first['text']?.toString().trim();
                if (text != null && text.isNotEmpty) return text;
              }
            }
          }
        } on Object {
          _geminiDevLog('API Error on version=$version model=$model');
        }
      }
    }
    throw const GeminiServiceException(
      'تعذّر الحصول على رد من Gemini. تحقق من المفتاح، تفعيل API، والاتصال.',
    );
  } finally {
    if (shouldDispose) ownedClient.close();
  }
}

/// تعليمات سلوك مساعد AmmarJo (العربية) — تُرسل مع سياق المتجر وبيانات Firestore.
const String kGeminiSystemPrompt = '''
أنت مساعد تطبيق Ammarjo الذكي، متخصص في مواد البناء 
والأدوات في الأردن. مهمتك مساعدة العملاء في:

1. البحث عن منتجات محددة وإيجادها في المتاجر
2. مقارنة الأسعار بين المتاجر
3. إيجاد فنيين متخصصين
4. الإجابة عن أسئلة مواد البناء
5. مساعدة العميل في اتخاذ قرار الشراء

عند سؤالك عن منتج، اذكر:
- اسم المنتج
- المتاجر المتوفرة فيه
- السعر التقريبي
- اقتراح للفني المناسب إذا لزم

تحدث باللغة العربية دائماً.
كن ودوداً ومفيداً ومختصراً.
''';

/// قواعد الرموز [[MAINTENANCE_CTA]] و [[QUANTITY_CALC_CTA]] — يجب أن تبقى متوافقة مع [AiChatTab].
const String kGeminiChatMarkerSuffix = '''
[تعليمات تقنية للتطبيق — اتبعها حرفياً]
- عندما يسأل العميل عن عطل أو إصلاح أو تسريب أو كهرباء منزلية أو تركيب يحتاج فنّياً: اقترح من المنتجات المناسبة من السياق إن وُجدت، واشرح باختصار، ثم في **سطر منفصل تماماً** أضف بالضبط الرمز: [[MAINTENANCE_CTA]] (بدون شرح إضافي بعده) ليظهر زر حجز فني في التطبيق.
- لا تضف [[MAINTENANCE_CTA]] إلا عندما يكون السؤال يتعلق فعلاً بصيانة أو عطل أو حاجة لفني.
- عندما يسأل عن **كمية** مواد (دهان، بلاط، طوب، لترات، عبوات، مساحة، متر مربع، كم دلو): أعطِ تقديراً عاماً مفيداً في جملة أو جملتين، ثم في **سطر منفصل تماماً** أضف بالضبط الرمز: [[QUANTITY_CALC_CTA]] ليظهر زر «حاسبة الكميات» في التطبيق (يمكن الجمع بين [[MAINTENANCE_CTA]] و [[QUANTITY_CALC_CTA]] في أسطر منفصلة إذا انطبق ذلك).
- لا تضف [[QUANTITY_CALC_CTA]] إلا عندما يكون السؤال يتعلق فعلاً بحساب كميات أو مساحات أو تغطية دهان/بلاط/بناء.
- استند إلى أسماء المنتجات والأقسام في [سياق المتجر] و [بيانات التطبيق] عند الإمكان؛ لا تخترع منتجات غير منطقية.
''';

/// جلب سياق من backend (`products`) حسب نية الرسالة.
Future<String> getAppContextForAiMessage(String userMessage) async {
  final msg = userMessage.toLowerCase();
  final buf = StringBuffer();

  final productIntent = msg.contains('سعر') ||
      msg.contains('منتج') ||
      msg.contains('يوجد') ||
      msg.contains('عندكم') ||
      msg.contains('اشتري') ||
      msg.contains('شراء');

  if (productIntent) {
    try {
      final rows = await BackendOrdersClient.instance.searchProducts(query: userMessage, hitsPerPage: 10, page: 0);
      if (rows != null && rows.isNotEmpty) {
        buf.writeln('المنتجات المتوفرة:');
        for (final p in rows.take(10)) {
          final name = p['name']?.toString() ?? '';
          final price = p['price']?.toString() ?? '';
          final rawStore = p['storeName']?.toString().trim();
          final storeName = (rawStore != null && rawStore.isNotEmpty) ? rawStore : 'متجر عمار جو';
          buf.writeln('- $name: $price دينار في $storeName');
        }
      }
    } on Object {
      debugPrint('[getAppContextForAiMessage] products failed');
    }
  }

  final techIntent = msg.contains('فني') ||
      msg.contains('تركيب') ||
      msg.contains('صيانة') ||
      msg.contains('كهرباء') ||
      msg.contains('سباك') ||
      msg.contains('سباكة') ||
      msg.contains('دهان') ||
      msg.contains('دهانات');

  if (techIntent) {
    buf.writeln('\nالفنيون المتاحون: يتم جلبهم من خادم الصيانة.');
  }

  return buf.toString();
}
