import 'seo_platform.dart';

class _SeoPlatformStub implements SeoPlatform {
  @override
  String get currentHref => '';

  @override
  String get currentOrigin => '';

  @override
  String get currentPath => '/';

  @override
  void setCanonical(String href) {}

  @override
  void setMetaByName(String name, String content) {}

  @override
  void setMetaByProperty(String property, String content) {}

  @override
  void setPath(String path) {}

  @override
  void setTitle(String value) {}

  @override
  void setJsonLd(String id, String jsonText) {}

  @override
  void setInternalLinks(List<String> absoluteUrls) {}

  @override
  void persistLastModified(String key, String value) {}

  @override
  String? readLastModified(String key) => null;
}

SeoPlatform getSeoPlatform() => _SeoPlatformStub();
