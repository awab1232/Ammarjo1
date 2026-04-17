import 'package:flutter/foundation.dart';

/// أول رابط صورة من قائمة أو سلسلة أو عناصر وصفية (مثل WooCommerce `{src: ...}`).
String? getFirstImage(dynamic images) {
  if (images == null) return '';
  if (images is List && images.isNotEmpty) {
    final first = images.first;
    if (first == null) return '';
    if (first is Map) {
      final u = (first['src'] ?? first['url'] ?? first['imageUrl'])?.toString().trim();
      return (u != null && u.isNotEmpty) ? u : '';
    }
    final s = first.toString().trim();
    return s.isEmpty ? '' : s;
  }
  if (images is String && images.trim().isNotEmpty) {
    return images.trim();
  }
  return '';
}

/// [getFirstImage] ثم [webSafeImageUrl] — للبطاقات والمعاينات.
String webSafeFirstProductImage(dynamic images) {
  final raw = getFirstImage(images);
  if (raw == null || raw.isEmpty) return '';
  return webSafeImageUrl(raw);
}

/// Legacy CORS proxy (Heroku demo) — **لا تُستخدم لعناوين Firebase Storage**؛ تُكسر رموز التوقيع.
@Deprecated('Avoid for production; prefer direct URLs with proper bucket CORS.')
const String kDefaultCorsProxy = 'https://cors-anywhere.herokuapp.com/';

/// Hosts that support browser image loads without a third-party proxy (Firebase / Google buckets).
bool _isDirectWebImageHost(String lowerUrl) {
  return lowerUrl.contains('firebasestorage.googleapis.com') ||
      lowerUrl.contains('storage.googleapis.com') ||
      lowerUrl.contains('googleusercontent.com') ||
      lowerUrl.contains('ggpht.com') ||
      lowerUrl.contains('firebaseapp.com');
}

/// يزيل `?alt=media` وغيره من الروابط الخارجية فقط — أحياناً تُنسَخ من واجهة Firebase Storage فيخطئ على Unsplash وغيره فيعطي 404.
String _stripBogusAltMediaOnExternalHosts(String u) {
  final lower = u.toLowerCase();
  if (!lower.contains('alt=media')) return u;
  if (_isDirectWebImageHost(lower) || lower.contains('googleapis.com')) {
    return u;
  }
  final q = u.indexOf('?');
  if (q >= 0) return u.substring(0, q);
  return u;
}

/// **الويب:** سابقاً كانت كل عناوين الصور تُمرَّر عبر [kDefaultCorsProxy]، ما يُفسد روابط
/// **Firebase Storage** (توقيعات طويلة + إعادة توجيه). الآن نُرجع الرابط كما هو لـ Firebase/Google،
/// وللبقية نُرجع الرابط مباشرة أيضاً (بدون بروكسي افتراضي) لتفادي تعطيل الإنتاج.
///
/// إن احتجت بروكسي لوسائط WordPress فقط، اضبطه لاحقاً عبر نطاقات محددة وليس عالمياً.
String webSafeImageUrl(String? rawUrl, {String proxyBase = kDefaultCorsProxy}) {
  final trimmed = rawUrl?.trim();
  if (trimmed == null) return '';
  var u = trimmed;
  if (u.isEmpty) return '';
  u = _stripBogusAltMediaOnExternalHosts(u);
  if (!kIsWeb) return u;
  if (u.startsWith('data:') || u.startsWith('blob:')) return u;
  final lower = u.toLowerCase();
  if (_isDirectWebImageHost(lower)) return u;
  if (u.startsWith(proxyBase)) return u;
  return u;
}
