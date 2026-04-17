import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../features/store/domain/models.dart';
import '../../features/store/presentation/pages/product_details_page.dart';

class SeoRoutes {
  static String product(int id) => '/product/$id';
  static String blog(String slug) => '/blog/${Uri.encodeComponent(slug)}';
  static String category(String name) =>
      '/category/${Uri.encodeComponent(name)}';
}

void openProductPage(
  BuildContext context, {
  required Product product,
  String? cartStoreId,
  String? cartStoreName,
}) {
  if (kIsWeb) {
    Navigator.of(context).pushNamed(
      SeoRoutes.product(product.id),
      arguments: <String, dynamic>{
        'product': product,
        'cartStoreId': cartStoreId,
        'cartStoreName': cartStoreName,
      },
    );
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ProductDetailsPage(
        product: product,
        cartStoreId: cartStoreId,
        cartStoreName: cartStoreName,
      ),
    ),
  );
}
