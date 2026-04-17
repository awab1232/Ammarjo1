import '../../contracts/feature_state.dart';
import '../../models/marketplace_product.dart';
import '../../services/backend_orders_client.dart';

final class ProductFilterRepository {
  ProductFilterRepository._();
  static final ProductFilterRepository instance = ProductFilterRepository._();

  Future<FeatureState<List<MarketplaceProduct>>> getFilteredProducts({
    String? subCategoryId,
    String? storeId,
    String? sectionId,
    String? search,
    double? minPrice,
    double? maxPrice,
  }) async {
    return BackendOrdersClient.instance.fetchFilteredProducts(
      subCategoryId: subCategoryId,
      storeId: storeId,
      sectionId: sectionId,
      search: search,
      minPrice: minPrice,
      maxPrice: maxPrice,
    );
  }
}
