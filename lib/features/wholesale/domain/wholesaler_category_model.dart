/// قسم داخل تاجر جملة — `wholesalers/{wid}/categories/{categoryId}`.
class WholesalerCategory {
  const WholesalerCategory({
    required this.id,
    required this.name,
    required this.order,
  });

  final String id;
  final String name;
  final int order;

  factory WholesalerCategory.fromBackendMap(Map<String, dynamic> d) {
    final o = d['order'];
    return WholesalerCategory(
      id: (d['id'] ?? '').toString(),
      name: (d['name'] ?? '').toString().trim(),
      order: o is num ? o.toInt() : int.tryParse(o?.toString() ?? '0') ?? 0,
    );
  }
}
