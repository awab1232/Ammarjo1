/// فلاتر التصفية الخادمية النشطة (سعر + تصنيف اختياري).
class CatalogActiveFilters {
  const CatalogActiveFilters({
    required this.minPrice,
    required this.maxPrice,
    this.categoryWooId,
  });

  final double minPrice;
  final double maxPrice;
  final int? categoryWooId;
}
