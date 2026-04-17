import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main() async {
  final siteUrl = _readEnv('SITE_URL', fallback: 'https://ammarjo.net');
  final projectId = _readEnv('FIREBASE_PROJECT_ID', fallback: 'ammarjo-app');
  final apiKey = _readEnv('FIREBASE_WEB_API_KEY', fallback: '');
  final nowDate = DateTime.now().toUtc().toIso8601String().split('T').first;
  final nowIso = DateTime.now().toUtc().toIso8601String();

  final entries = <_SitemapEntry>[
    _SitemapEntry(
      path: '/',
      priority: 1.0,
      lastmod: nowDate,
      title: 'AmmarJo - Construction Marketplace',
      description:
          'AmmarJo marketplace for construction materials, maintenance services, and professional suppliers.',
      type: 'WebSite',
    ),
    _SitemapEntry(
      path: '/about',
      priority: 0.7,
      lastmod: nowDate,
      title: 'About AmmarJo',
      description: 'Learn about AmmarJo construction marketplace.',
      type: 'WebPage',
    ),
    _SitemapEntry(
      path: '/privacy',
      priority: 0.6,
      lastmod: nowDate,
      title: 'Privacy Policy | AmmarJo',
      description: 'AmmarJo privacy policy.',
      type: 'WebPage',
    ),
    _SitemapEntry(
      path: '/terms',
      priority: 0.6,
      lastmod: nowDate,
      title: 'Terms of Use | AmmarJo',
      description: 'AmmarJo terms of use.',
      type: 'WebPage',
    ),
    _SitemapEntry(
      path: '/return-policy',
      priority: 0.6,
      lastmod: nowDate,
      title: 'Return Policy | AmmarJo',
      description: 'AmmarJo return policy.',
      type: 'WebPage',
    ),
    _SitemapEntry(
      path: '/blog',
      priority: 0.6,
      lastmod: nowDate,
      title: 'AmmarJo Blog',
      description:
          'Construction insights, maintenance guides, and marketplace updates from AmmarJo.',
      type: 'CollectionPage',
    ),
    _SitemapEntry(
      path: '/product/:id',
      priority: 0.8,
      lastmod: nowDate,
      title: 'Product {{id}} | AmmarJo',
      description: 'Browse product details on AmmarJo.',
      type: 'Product',
      isTemplate: true,
    ),
    _SitemapEntry(
      path: '/blog/:slug',
      priority: 0.6,
      lastmod: nowDate,
      title: 'Blog: {{slug}} | AmmarJo',
      description: 'Read AmmarJo blog content.',
      type: 'Article',
      isTemplate: true,
    ),
    _SitemapEntry(
      path: '/category/:name',
      priority: 0.7,
      lastmod: nowDate,
      title: 'Category: {{name}} | AmmarJo',
      description: 'Browse category products and stores on AmmarJo.',
      type: 'CollectionPage',
      isTemplate: true,
    ),
  ];

  if (apiKey.isNotEmpty) {
    entries.addAll(await _readProducts(projectId, apiKey, nowDate));
    entries.addAll(await _readBlogs(projectId, apiKey, nowDate));
    entries.addAll(await _readCategories(projectId, apiKey, nowDate));
  }

  entries.sort((a, b) => a.path.compareTo(b.path));
  await _writeSitemap(siteUrl, entries);
  await _writeRegistry(siteUrl, entries, nowIso);
  stdout.writeln(
    'Sitemap + seo_registry generated (${entries.length} entries).',
  );
}

Future<List<_SitemapEntry>> _readProducts(
  String projectId,
  String apiKey,
  String fallbackDate,
) async {
  final docs = await _readCollection(projectId, apiKey, 'products');
  final out = <_SitemapEntry>[];
  for (final doc in docs) {
    final rawId = _fieldString(doc, 'id');
    final id = rawId.isNotEmpty ? rawId : _documentId(doc);
    if (id.isEmpty || int.tryParse(id) == null) continue;
    out.add(
      _SitemapEntry(
        path: '/product/$id',
        priority: 0.8,
        lastmod: _fieldTimestamp(doc, 'updatedAt', fallbackDate),
        title:
            '${_fieldString(doc, 'name').isEmpty ? 'Product $id' : _fieldString(doc, 'name')} | AmmarJo',
        description: _trim(
          _fieldString(doc, 'description'),
          fallback: 'Browse product details on AmmarJo.',
        ),
        type: 'Product',
        image: _fieldString(doc, 'imageUrl'),
      ),
    );
  }
  return out;
}

Future<List<_SitemapEntry>> _readBlogs(
  String projectId,
  String apiKey,
  String fallbackDate,
) async {
  final docs = await _readCollection(projectId, apiKey, 'blog_posts');
  final out = <_SitemapEntry>[];
  for (final doc in docs) {
    final slug = _fieldString(doc, 'slug').isNotEmpty
        ? _fieldString(doc, 'slug')
        : _documentId(doc);
    if (slug.isEmpty) continue;
    final title = _fieldString(doc, 'title');
    out.add(
      _SitemapEntry(
        path: '/blog/${Uri.encodeComponent(slug)}',
        priority: 0.6,
        lastmod: _fieldTimestamp(
          doc,
          'updatedAt',
          _fieldTimestamp(doc, 'publishedAt', fallbackDate),
        ),
        title: title.isEmpty ? 'Blog | AmmarJo' : '$title | AmmarJo',
        description: _trim(
          _fieldString(doc, 'excerpt'),
          fallback: 'Read AmmarJo blog content.',
        ),
        type: 'Article',
      ),
    );
  }
  return out;
}

Future<List<_SitemapEntry>> _readCategories(
  String projectId,
  String apiKey,
  String fallbackDate,
) async {
  final docs = await _readCollection(projectId, apiKey, 'store_categories');
  final out = <_SitemapEntry>[];
  for (final doc in docs) {
    final name = _fieldString(doc, 'name');
    if (name.isEmpty) continue;
    out.add(
      _SitemapEntry(
        path: '/category/${Uri.encodeComponent(name)}',
        priority: 0.7,
        lastmod: _fieldTimestamp(doc, 'updatedAt', fallbackDate),
        title: '$name | AmmarJo',
        description: 'Browse $name category on AmmarJo.',
        type: 'CollectionPage',
      ),
    );
  }
  return out;
}

Future<List<Map<String, dynamic>>> _readCollection(
  String projectId,
  String apiKey,
  String collection,
) async {
  final uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$collection?pageSize=1000&key=$apiKey',
  );
  final response = await http.get(uri);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    return const <Map<String, dynamic>>[];
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! Map<String, dynamic>) return const <Map<String, dynamic>>[];
  final docs = decoded['documents'];
  if (docs is! List) return const <Map<String, dynamic>>[];
  return docs.whereType<Map<String, dynamic>>().toList();
}

Future<void> _writeSitemap(String siteUrl, List<_SitemapEntry> entries) async {
  final sink = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');
  for (final e in entries.where((e) => !e.isTemplate)) {
    sink.writeln('  <url>');
    sink.writeln('    <loc>${_xml(siteUrl)}${_xml(e.path)}</loc>');
    sink.writeln('    <lastmod>${e.lastmod}</lastmod>');
    sink.writeln('    <priority>${e.priority.toStringAsFixed(1)}</priority>');
    sink.writeln('  </url>');
  }
  sink.writeln('</urlset>');
  await File('web/sitemap.xml').writeAsString(sink.toString());
}

Future<void> _writeRegistry(
  String siteUrl,
  List<_SitemapEntry> entries,
  String generatedAt,
) async {
  final routes = <String, dynamic>{};
  for (final e in entries) {
    routes[e.path] = <String, dynamic>{
      'type': e.type,
      'title': e.isTemplate ? null : e.title,
      'titleTemplate': e.isTemplate ? e.title : null,
      'description': e.description,
      'canonical': '$siteUrl${e.path}',
      'lastModified': e.lastmod,
      'priority': e.priority,
      if (e.image.trim().isNotEmpty) 'image': e.image,
    }..removeWhere((key, value) => value == null);
  }
  final payload = <String, dynamic>{
    'generatedAt': generatedAt,
    'siteUrl': siteUrl,
    'routes': routes,
  };
  await File(
    'web/seo_registry.json',
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
}

String _fieldString(Map<String, dynamic> doc, String key) {
  final fields = doc['fields'];
  if (fields is! Map<String, dynamic>) return '';
  final field = fields[key];
  if (field is! Map<String, dynamic>) return '';
  for (final value in field.values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  return '';
}

String _fieldTimestamp(Map<String, dynamic> doc, String key, String fallback) {
  final raw = _fieldString(doc, key);
  if (raw.isEmpty) return fallback;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return fallback;
  return parsed.toUtc().toIso8601String().split('T').first;
}

String _documentId(Map<String, dynamic> doc) {
  final name = doc['name']?.toString() ?? '';
  if (name.isEmpty) return '';
  final parts = name.split('/');
  return parts.isEmpty ? '' : parts.last;
}

String _readEnv(String key, {required String fallback}) {
  final value = Platform.environment[key]?.trim() ?? '';
  return value.isEmpty ? fallback : value;
}

String _trim(String text, {required String fallback}) {
  final cleaned = text
      .replaceAll(RegExp('<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return fallback;
  return cleaned.length <= 180 ? cleaned : '${cleaned.substring(0, 180)}...';
}

String _xml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

class _SitemapEntry {
  const _SitemapEntry({
    required this.path,
    required this.priority,
    required this.lastmod,
    required this.title,
    required this.description,
    required this.type,
    this.image = '',
    this.isTemplate = false,
  });

  final String path;
  final double priority;
  final String lastmod;
  final String title;
  final String description;
  final String type;
  final String image;
  final bool isTemplate;
}
