import 'package:flutter/foundation.dart' show debugPrint;

/// Canonical feature identifiers for contracts, logs, and UI.
abstract final class FeatureIds {
  static const String orders = 'orders';
  static const String stores = 'stores';
  static const String products = 'products';
  static const String adminPanel = 'admin_panel';
  static const String coupons = 'coupons';
  static const String promotions = 'promotions';
  static const String support = 'support';
  static const String maintenance = 'maintenance';
  static const String notifications = 'notifications';
  static const String analytics = 'analytics';
  static const String homeBanners = 'home_banners';
  static const String storeCategories = 'store_categories';
  static const String storeDirectory = 'store_directory';
  static const String productCatalogSearch = 'product_catalog_search';
  static const String adminStoreRequests = 'admin_store_requests';
  static const String adminProductUpsert = 'admin_product_upsert';
  static const String adminProductDelete = 'admin_product_delete';
  static const String adminReviews = 'admin_reviews';
}

class FeatureContract {
  const FeatureContract({
    required this.name,
    required this.id,
    this.isCritical = false,
    this.hasBackend = true,
    this.isAdminFeature = false,
  });

  final String name;
  final String id;
  final bool isCritical;
  final bool hasBackend;
  final bool isAdminFeature;
}

/// Registry of all product features — used by [FeatureContractValidator] and audits.
abstract final class FeatureContractRegistry {
  static const List<FeatureContract> all = <FeatureContract>[
    FeatureContract(name: 'Orders', id: FeatureIds.orders, isCritical: true, hasBackend: true),
    FeatureContract(name: 'Stores', id: FeatureIds.stores, isCritical: true, hasBackend: true),
    FeatureContract(name: 'Products', id: FeatureIds.products, isCritical: true, hasBackend: true),
    FeatureContract(name: 'Admin Panel', id: FeatureIds.adminPanel, isCritical: false, hasBackend: true, isAdminFeature: true),
    FeatureContract(name: 'Coupons', id: FeatureIds.coupons, isCritical: false, hasBackend: true),
    FeatureContract(name: 'Promotions', id: FeatureIds.promotions, isCritical: false, hasBackend: true),
    FeatureContract(name: 'Support', id: FeatureIds.support, isCritical: false, hasBackend: true),
    FeatureContract(name: 'Maintenance', id: FeatureIds.maintenance, isCritical: false, hasBackend: true),
    FeatureContract(name: 'Notifications', id: FeatureIds.notifications, isCritical: false, hasBackend: true),
    FeatureContract(name: 'Analytics', id: FeatureIds.analytics, isCritical: false, hasBackend: true),
    FeatureContract(name: 'Home Banners', id: FeatureIds.homeBanners, isCritical: true, hasBackend: true),
  ];

  static void debugPrintRegistry() {
    debugPrint('[FeatureContractRegistry] count=${all.length}');
  }
}
