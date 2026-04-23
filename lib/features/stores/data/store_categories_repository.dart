import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/contracts/feature_state.dart';
import '../../../core/services/backend_orders_client.dart';

class StoreCategoryEntry {
  const StoreCategoryEntry({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.order,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String imageUrl;
  final int order;
  final bool isActive;

  factory StoreCategoryEntry.fromBackendMap(Map<String, dynamic> d, int index) {
    final o = (d['order'] as num?)?.toInt() ?? (index + 1);
    return StoreCategoryEntry(
      id: d['id']?.toString().trim().isNotEmpty == true ? d['id'].toString().trim() : 'cat_$index',
      name: d['name']?.toString().trim() ?? 'Category',
      imageUrl: d['imageUrl']?.toString().trim() ?? '',
      order: o,
      isActive: d['isActive'] != false,
    );
  }
}

/// Default imagery URLs for static category grids (exported for legacy imports).
const List<String> kStoresCategoryFallbackImageUrls = <String>[
  'https://images.unsplash.com/photo-1541888946425-d81bb19240f5?w=600&q=80',
  'https://images.unsplash.com/photo-1621905252507-b35492cc74b4?w=600&q=80',
  'https://images.unsplash.com/photo-1589939705384-5185137a7f0f?w=600&q=80',
  'https://images.unsplash.com/photo-1585704031112-1a95f6ecd6db?w=600&q=80',
  'https://images.unsplash.com/photo-1503387762-592deb58ef4e?w=600&q=80',
  'https://images.unsplash.com/photo-1615873968403-89e068629265?w=600&q=80',
  'https://images.unsplash.com/photo-1504307651254-35680f356dfd?w=600&q=80',
  'https://images.unsplash.com/photo-1504148455328-c376907d081c?w=600&q=80',
];

/// Store category chips — **backend stores list only**. Falls back to public list; empty OK.
Future<FeatureState<List<StoreCategoryEntry>>> fetchStoreCategoriesFromFirestore() async {
  List<Map<String, dynamic>>? stores;
  try {
    stores = await BackendOrdersClient.instance.fetchStores(limit: 200);
  } on Object catch (e) {
    debugPrint('[StoreCategories] authed /stores failed: $e');
    return FeatureState.failure('تعذر تحميل تصنيفات المتاجر.', e);
  }
  if (stores == null || stores.isEmpty) {
    return FeatureState.success(const <StoreCategoryEntry>[]);
  }
  final seen = <String>{};
  final out = <StoreCategoryEntry>[];
  var index = 0;
  for (final s in stores) {
    final raw = (s['category']?.toString() ?? '').trim();
    if (raw.isEmpty || !seen.add(raw)) continue;
    out.add(StoreCategoryEntry.fromBackendMap({'id': raw, 'name': raw, 'isActive': true}, index));
    index++;
  }
  return FeatureState.success(out);
}

Stream<FeatureState<List<StoreCategoryEntry>>> watchActiveStoreCategories() {
  return Stream<FeatureState<List<StoreCategoryEntry>>>.fromFuture(fetchStoreCategoriesFromFirestore());
}

/// @deprecated Use [watchActiveStoreCategories] — kept for a single call site; identical stream (no silent error swallow).
Stream<FeatureState<List<StoreCategoryEntry>>> watchActiveStoreCategoriesWithFallback() {
  return watchActiveStoreCategories();
}
