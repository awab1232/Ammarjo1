import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../../core/config/wp_site_config.dart';
import '../../../core/config/woo_jwt_holder.dart';
import '../../../core/network/json_utf8.dart';

class WpPageContent {
  WpPageContent({required this.title, required this.htmlBody});

  final String title;
  final String htmlBody;
}

/// جلب صفحات ووردبريس عبر REST API (عام، بدون مفاتيح WooCommerce).
Future<WpPageContent?> fetchWpPageBySlug(String slug) async {
  final uri = Uri.parse('${WpSiteConfig.storeUrl}/wp-json/wp/v2/pages').replace(
    queryParameters: {'slug': slug, '_fields': 'title,content'},
  );
  final response = await http.get(uri, headers: {...WooJwtHolder.authorizationHeaders()});
  if (response.statusCode != 200) {
    debugPrint('[fetchWpPageBySlug] HTTP ${response.statusCode}');
    return null;
  }
  final decoded = jsonDecodeUtf8Response(response);
  if (decoded is! List<dynamic> || decoded.isEmpty) {
    debugPrint('[fetchWpPageBySlug] empty or invalid list');
    return null;
  }
  final map = decoded.first as Map<String, dynamic>;
  final title = (map['title'] is Map && (map['title'] as Map)['rendered'] != null)
      ? (map['title'] as Map)['rendered'].toString()
      : '';
  final content = (map['content'] is Map && (map['content'] as Map)['rendered'] != null)
      ? (map['content'] as Map)['rendered'].toString()
      : '';
  return WpPageContent(
    title: title.replaceAll(RegExp(r'<[^>]*>'), '').trim(),
    htmlBody: content,
  );
}
