import 'package:http/http.dart' as http;

import '../../../core/config/home_banners_wp_config.dart';
import '../../../core/config/wp_site_config.dart';
import '../../../core/config/woo_jwt_holder.dart';
import '../../../core/contracts/feature_state.dart';
import '../../../core/network/json_utf8.dart';
import '../domain/wp_home_banner.dart';

/// يجلب مقالات تصنيف البانر مع `_embed` لاستخراج **الصورة البارزة**.
Future<FeatureState<List<WpHomeBannerSlide>>> fetchWpHomeBanners() async {
  final id = HomeBannersWpConfig.categoryId;
  final slug = HomeBannersWpConfig.categorySlug.trim();

  int? categoryId = id;
  if (categoryId == null && slug.isNotEmpty) {
    categoryId = await _fetchCategoryIdBySlug(slug);
  }

  if (categoryId == null) {
    return FeatureState.failure('WP banner category is not configured.');
  }

  final uri = Uri.parse('${WpSiteConfig.storeUrl}/wp-json/wp/v2/posts').replace(
    queryParameters: <String, String>{
      'categories': '$categoryId',
      'per_page': '${HomeBannersWpConfig.perPage}',
      '_embed': '1',
      'orderby': HomeBannersWpConfig.orderBy,
      'order': HomeBannersWpConfig.order,
    },
  );

  final response = await http.get(uri, headers: {...WooJwtHolder.authorizationHeaders()});
  if (response.statusCode != 200) {
    return FeatureState.failure('Failed to fetch WP banners (${response.statusCode}).');
  }

  final decoded = jsonDecodeUtf8Response(response);
  if (decoded is! List<dynamic>) {
    return FeatureState.failure('Invalid WP banners payload.');
  }

  final out = <WpHomeBannerSlide>[];
  for (final raw in decoded) {
    if (raw is! Map<String, dynamic>) continue;
    final imageUrl = _featuredImageUrl(raw);
    if (imageUrl == null || imageUrl.isEmpty) continue;

    final link = raw['link']?.toString();
    final titleRendered = _titleRendered(raw);

    out.add(
      WpHomeBannerSlide(
        imageUrl: imageUrl,
        linkUrl: link != null && link.isNotEmpty ? link : null,
        title: titleRendered,
      ),
    );
  }
  return FeatureState.success(out);
}

Future<int?> _fetchCategoryIdBySlug(String slug) async {
  final uri = Uri.parse('${WpSiteConfig.storeUrl}/wp-json/wp/v2/categories').replace(
    queryParameters: <String, String>{'slug': slug, 'per_page': '1'},
  );
  final response = await http.get(uri, headers: {...WooJwtHolder.authorizationHeaders()});
  if (response.statusCode != 200) throw StateError('NULL_RESPONSE');
  final decoded = jsonDecodeUtf8Response(response);
  if (decoded is! List<dynamic> || decoded.isEmpty) throw StateError('NULL_RESPONSE');
  final first = decoded.first;
  if (first is! Map<String, dynamic>) throw StateError('NULL_RESPONSE');
  final cid = first['id'];
  if (cid is int) return cid;
  if (cid is num) return cid.toInt();
  throw StateError('NULL_RESPONSE');
}

String? _featuredImageUrl(Map<String, dynamic> post) {
  final jetpack = post['jetpack_featured_media_url'];
  if (jetpack is String && jetpack.isNotEmpty) {
    return jetpack;
  }

  final embedded = post['_embedded'];
  if (embedded is Map<String, dynamic>) {
    final media = embedded['wp:featuredmedia'];
    if (media is List && media.isNotEmpty) {
      final first = media.first;
      if (first is Map<String, dynamic>) {
        final url = first['source_url']?.toString();
        if (url != null && url.isNotEmpty) return url;
      }
    }
  }

  throw StateError('NULL_RESPONSE');
}

String? _titleRendered(Map<String, dynamic> post) {
  final title = post['title'];
  if (title is Map && title['rendered'] != null) {
    final s = title['rendered'].toString().replaceAll(RegExp(r'<[^>]*>'), '').trim();
    return s.isEmpty ? null : s;
  }
  throw StateError('NULL_RESPONSE');
}
