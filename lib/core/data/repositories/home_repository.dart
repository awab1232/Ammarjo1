import '../../contracts/feature_state.dart';
import '../../models/home_section.dart';
import '../../models/sub_category.dart';
import '../../services/backend_orders_client.dart';

final class HomeRepository {
  HomeRepository._();
  static final HomeRepository instance = HomeRepository._();

  static const Duration _cacheTtl = Duration(minutes: 5);
  FeatureState<List<HomeSection>>? _sectionsCache;
  DateTime? _sectionsCacheAt;
  int _sectionsVersion = -1;
  final Map<String, FeatureState<List<SubCategory>>> _subCategoriesCache = <String, FeatureState<List<SubCategory>>>{};
  final Map<String, DateTime> _subCategoriesCacheAt = <String, DateTime>{};
  final Map<String, int> _subCategoriesVersion = <String, int>{};

  bool _isFresh(DateTime? ts) =>
      ts != null && DateTime.now().difference(ts) <= _cacheTtl;

  Future<FeatureState<List<HomeSection>>> getSections({bool forceRefresh = false}) async {
    if (!forceRefresh && _sectionsCache != null && _isFresh(_sectionsCacheAt)) {
      final probe = await BackendOrdersClient.instance.fetchHomeSectionsVersioned();
      if (probe.version == _sectionsVersion) {
        return _sectionsCache!;
      }
    }
    final payload = await BackendOrdersClient.instance.fetchHomeSectionsVersioned();
    _sectionsCache = payload.state;
    _sectionsCacheAt = DateTime.now();
    _sectionsVersion = payload.version;
    return payload.state;
  }

  Future<FeatureState<List<SubCategory>>> getSubCategories(String sectionId, {bool forceRefresh = false}) async {
    final key = sectionId.trim();
    final cached = _subCategoriesCache[key];
    if (!forceRefresh && cached != null && _isFresh(_subCategoriesCacheAt[key])) {
      final probe = await BackendOrdersClient.instance.fetchSubCategoriesVersioned(sectionId);
      if ((_subCategoriesVersion[key] ?? -1) == probe.version) {
        return cached;
      }
    }
    final payload = await BackendOrdersClient.instance.fetchSubCategoriesVersioned(sectionId);
    _subCategoriesCache[key] = payload.state;
    _subCategoriesCacheAt[key] = DateTime.now();
    _subCategoriesVersion[key] = payload.version;
    return payload.state;
  }

  void invalidateAll() {
    _sectionsCache = null;
    _sectionsCacheAt = null;
    _sectionsVersion = -1;
    _subCategoriesCache.clear();
    _subCategoriesCacheAt.clear();
    _subCategoriesVersion.clear();
  }
}
