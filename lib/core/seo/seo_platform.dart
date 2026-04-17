import 'seo_platform_stub.dart'
    if (dart.library.html) 'seo_platform_web.dart'
    as platform;

abstract class SeoPlatform {
  String get currentOrigin;
  String get currentPath;
  String get currentHref;
  void setTitle(String value);
  void setMetaByName(String name, String content);
  void setMetaByProperty(String property, String content);
  void setCanonical(String href);
  void setPath(String path);
  void setJsonLd(String id, String jsonText);
  void setInternalLinks(List<String> absoluteUrls);
  void persistLastModified(String key, String value);
  String? readLastModified(String key);
}

SeoPlatform getSeoPlatform() => platform.getSeoPlatform();
