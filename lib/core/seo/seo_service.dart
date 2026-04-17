import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'organic_traffic_system.dart';
import 'seo_platform.dart';

class SeoData {
  const SeoData({
    required this.title,
    required this.description,
    this.keywords,
    this.path,
    this.imageUrl,
    this.lastModified,
    this.structuredData = const <Map<String, dynamic>>[],
    this.internalLinks = const <String>[],
  });

  final String title;
  final String description;
  final String? keywords;
  final String? path;
  final String? imageUrl;
  final DateTime? lastModified;
  final List<Map<String, dynamic>> structuredData;
  final List<String> internalLinks;
}

class SeoService {
  static final SeoPlatform _platform = getSeoPlatform();
  static String? _lastSignature;
  static const String _defaultPingEndpoint = String.fromEnvironment(
    'SEO_PING_ENDPOINT',
  );
  static String? _lastImpressionPath;

  static const SeoData homeFallback = SeoData(
    title: 'AmmarJo - Construction Marketplace',
    description:
        'AmmarJo marketplace for construction materials, maintenance services, and professional suppliers.',
    keywords:
        'AmmarJo, construction marketplace, building materials, maintenance',
    path: '/',
  );

  static void apply(SeoData data, {bool updatePath = false}) {
    if (!kIsWeb) return;
    final cleanPath = _normalizePath(data.path ?? _platform.currentPath);
    final canonical = '${_platform.currentOrigin}$cleanPath';
    final modified =
        data.lastModified?.toUtc().toIso8601String() ??
        _platform.readLastModified(cleanPath) ??
        DateTime.now().toUtc().toIso8601String();
    final signature =
        '${data.title}|${data.description}|${data.keywords ?? ''}|$canonical|${data.imageUrl ?? ''}|$modified|${data.structuredData.length}|${data.internalLinks.length}';
    if (_lastSignature == signature) return;
    _lastSignature = signature;

    _platform.setTitle(data.title);
    _platform.setMetaByName('description', data.description);
    if (data.keywords != null && data.keywords!.trim().isNotEmpty) {
      _platform.setMetaByName('keywords', data.keywords!.trim());
    }
    _platform.setMetaByProperty('og:title', data.title);
    _platform.setMetaByProperty('og:description', data.description);
    _platform.setMetaByProperty('og:url', canonical);
    _platform.setMetaByProperty('og:type', 'website');
    _platform.setMetaByName('last-modified', modified);
    _platform.setMetaByProperty('article:modified_time', modified);
    _platform.setMetaByProperty('og:updated_time', modified);
    if (data.imageUrl != null && data.imageUrl!.trim().isNotEmpty) {
      _platform.setMetaByProperty('og:image', data.imageUrl!.trim());
    }
    for (var i = 0; i < data.structuredData.length; i++) {
      final schema = Map<String, dynamic>.from(data.structuredData[i]);
      schema['dateModified'] = schema['dateModified'] ?? modified;
      _platform.setJsonLd('schema-$i', jsonEncode(schema));
    }
    if (data.internalLinks.isNotEmpty) {
      final links = data.internalLinks
          .map((e) => '${_platform.currentOrigin}${_normalizePath(e)}')
          .toList();
      _platform.setInternalLinks(links);
    }
    _platform.persistLastModified(cleanPath, modified);
    if (_lastImpressionPath != cleanPath) {
      _lastImpressionPath = cleanPath;
      // Background metrics only; does not affect rendering path.
      OrganicTrafficSystem.instance.recordImpression(path: cleanPath);
    }
    _platform.setCanonical(canonical);
    if (updatePath) {
      _platform.setPath(cleanPath);
    }
  }

  static void markContentUpdated(String path, {DateTime? at}) {
    if (!kIsWeb) return;
    _platform.persistLastModified(
      _normalizePath(path),
      (at ?? DateTime.now()).toUtc().toIso8601String(),
    );
  }

  static Future<void> pingIndexingEndpoint({
    required List<String> paths,
    required String reason,
    required String lastModifiedIso,
  }) async {
    if (!kIsWeb || _defaultPingEndpoint.trim().isEmpty) return;
    try {
      await http.post(
        Uri.parse(_defaultPingEndpoint),
        headers: const <String, String>{'content-type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'reason': reason,
          'paths': paths,
          'lastModified': lastModifiedIso,
          'sitemap': '/sitemap.xml',
        }),
      );
    } on Object {
      return;
    }
  }

  static String _normalizePath(String value) {
    if (value.trim().isEmpty) return '/';
    final raw = value.trim();
    return raw.startsWith('/') ? raw : '/$raw';
  }
}
