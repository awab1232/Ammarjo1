// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'seo_platform.dart';

class _SeoPlatformWeb implements SeoPlatform {
  @override
  String get currentHref => html.window.location.href;

  @override
  String get currentOrigin => html.window.location.origin;

  @override
  String get currentPath => html.window.location.pathname ?? '/';

  @override
  void setTitle(String value) {
    html.document.title = value;
  }

  @override
  void setMetaByName(String name, String content) {
    final existing =
        html.document.head?.querySelector('meta[name="$name"]')
            as html.MetaElement?;
    if (existing != null) {
      existing.content = content;
      return;
    }
    final meta = html.MetaElement()
      ..name = name
      ..content = content;
    html.document.head?.append(meta);
  }

  @override
  void setMetaByProperty(String property, String content) {
    final existing =
        html.document.head?.querySelector('meta[property="$property"]')
            as html.MetaElement?;
    if (existing != null) {
      existing.content = content;
      return;
    }
    final meta = html.MetaElement()
      ..setAttribute('property', property)
      ..content = content;
    html.document.head?.append(meta);
  }

  @override
  void setCanonical(String href) {
    final existing =
        html.document.head?.querySelector('link[rel="canonical"]')
            as html.LinkElement?;
    if (existing != null) {
      existing.href = href;
      return;
    }
    final canonical = html.LinkElement()
      ..rel = 'canonical'
      ..href = href;
    html.document.head?.append(canonical);
  }

  @override
  void setPath(String path) {
    final next = path.startsWith('/') ? path : '/$path';
    if (html.window.location.pathname == next) return;
    html.window.history.pushState(null, '', next);
  }

  @override
  void setJsonLd(String id, String jsonText) {
    final selector = 'script[type="application/ld+json"][data-seo-id="$id"]';
    final existing =
        html.document.head?.querySelector(selector) as html.ScriptElement?;
    if (existing != null) {
      existing.text = jsonText;
      return;
    }
    final script = html.ScriptElement()
      ..type = 'application/ld+json'
      ..setAttribute('data-seo-id', id)
      ..text = jsonText;
    html.document.head?.append(script);
  }

  @override
  void setInternalLinks(List<String> absoluteUrls) {
    final body = html.document.body;
    if (body == null) return;
    final existing = html.document.getElementById('seo-internal-links');
    final container =
        existing ??
        (html.DivElement()
          ..id = 'seo-internal-links'
          ..setAttribute('aria-hidden', 'true')
          ..style.display = 'none');
    container.children.clear();
    for (final url in absoluteUrls) {
      final link = html.AnchorElement(href: url)..text = url;
      container.append(link);
    }
    if (existing == null) {
      body.append(container);
    }
  }

  @override
  void persistLastModified(String key, String value) {
    html.window.localStorage['seo-lastmod-$key'] = value;
  }

  @override
  String? readLastModified(String key) {
    return html.window.localStorage['seo-lastmod-$key'];
  }
}

SeoPlatform getSeoPlatform() => _SeoPlatformWeb();
