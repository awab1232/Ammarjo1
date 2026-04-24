/// نماذج بيانات قاعدة حاسبة البناء (مصدر JSON).
class CalculatorMetadata {
  const CalculatorMetadata({
    required this.region,
    required this.standard,
    required this.dataSources,
    required this.lastUpdated,
  });

  final String region;
  final String standard;
  final List<String> dataSources;
  final String lastUpdated;

  factory CalculatorMetadata.fromJson(Map<String, dynamic> j) {
    final src = j['data_sources'];
    final list = <String>[];
    if (src is List) {
      for (final e in src) {
        list.add(e.toString());
      }
    }
    return CalculatorMetadata(
      region: j['region']?.toString() ?? (throw StateError('unexpected_empty_response')),
      standard: j['standard']?.toString() ?? (throw StateError('unexpected_empty_response')),
      dataSources: list,
      lastUpdated: j['last_updated']?.toString() ?? (throw StateError('unexpected_empty_response')),
    );
  }
}

class MaterialComponent {
  const MaterialComponent({
    required this.material,
    required this.quantity,
    required this.unit,
  });

  /// مفتاح إنجليزي للمطابقة مع المتجر.
  final String material;
  final double quantity;
  final String unit;

  factory MaterialComponent.fromJson(Map<String, dynamic> j) {
    final q = j['quantity'];
    return MaterialComponent(
      material: j['material']?.toString() ?? (throw StateError('unexpected_empty_response')),
      quantity: q is num
          ? q.toDouble()
          : double.tryParse(q?.toString() ?? (throw StateError('unexpected_empty_response'))) ??
              (throw StateError('INVALID_NUMERIC_DATA')),
      unit: j['unit']?.toString() ?? (throw StateError('unexpected_empty_response')),
    );
  }
}

class PackageSize {
  const PackageSize({
    required this.size,
    required this.coverage,
    required this.unit,
  });

  final String size;
  final double coverage;
  final String unit;

  factory PackageSize.fromJson(Map<String, dynamic> j) {
    final c = j['coverage'];
    return PackageSize(
      size: j['size']?.toString() ?? (throw StateError('unexpected_empty_response')),
      coverage: c is num
          ? c.toDouble()
          : double.tryParse(c?.toString() ?? (throw StateError('unexpected_empty_response'))) ??
              (throw StateError('INVALID_NUMERIC_DATA')),
      unit: j['unit']?.toString() ?? (throw StateError('unexpected_empty_response')),
    );
  }
}

class ConstructionItem {
  const ConstructionItem({
    required this.id,
    required this.nameAr,
    required this.unit,
    required this.wasteFactor,
    required this.expertTip,
    required this.components,
    required this.availableSizes,
  });

  final String id;
  final String nameAr;
  /// قيمة JSON خام (m3, m2, Meter, m3 of concrete, …).
  final String unit;
  final double wasteFactor;
  final String expertTip;
  final List<MaterialComponent> components;
  final List<PackageSize> availableSizes;

  bool get isComponentBased => components.isNotEmpty;
  bool get isCoverageBased => availableSizes.isNotEmpty;

  factory ConstructionItem.fromJson(Map<String, dynamic> j) {
    final comps = <MaterialComponent>[];
    final rawC = j['components'];
    if (rawC is List) {
      for (final e in rawC) {
        if (e is Map<String, dynamic>) comps.add(MaterialComponent.fromJson(e));
      }
    }
    final sizes = <PackageSize>[];
    final rawS = j['available_sizes'];
    if (rawS is List) {
      for (final e in rawS) {
        if (e is Map<String, dynamic>) sizes.add(PackageSize.fromJson(e));
      }
    }
    final w = j['waste_factor'];
    return ConstructionItem(
      id: j['id']?.toString() ?? (throw StateError('unexpected_empty_response')),
      nameAr: j['name_ar']?.toString() ?? (throw StateError('unexpected_empty_response')),
      unit: j['unit']?.toString() ?? (throw StateError('unexpected_empty_response')),
      wasteFactor: w is num
          ? w.toDouble()
          : double.tryParse(w?.toString() ?? (throw StateError('unexpected_empty_response'))) ??
              (throw StateError('INVALID_NUMERIC_DATA')),
      expertTip: j['expert_tip']?.toString() ?? (throw StateError('unexpected_empty_response')),
      components: comps,
      availableSizes: sizes,
    );
  }
}

class ConstructionCategory {
  const ConstructionCategory({
    required this.id,
    required this.nameAr,
    required this.items,
  });

  final String id;
  final String nameAr;
  final List<ConstructionItem> items;

  factory ConstructionCategory.fromJson(Map<String, dynamic> j) {
    final raw = j['items'];
    final items = <ConstructionItem>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) items.add(ConstructionItem.fromJson(e));
      }
    }
    return ConstructionCategory(
      id: j['id']?.toString() ?? (throw StateError('unexpected_empty_response')),
      nameAr: j['name_ar']?.toString() ?? (throw StateError('unexpected_empty_response')),
      items: items,
    );
  }
}

class ConstructionCalculatorDb {
  const ConstructionCalculatorDb({
    required this.metadata,
    required this.categories,
  });

  final CalculatorMetadata metadata;
  final List<ConstructionCategory> categories;

  factory ConstructionCalculatorDb.fromJson(Map<String, dynamic> j) {
    final raw = j['categories'];
    final cats = <ConstructionCategory>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) cats.add(ConstructionCategory.fromJson(e));
      }
    }
    return ConstructionCalculatorDb(
      metadata: CalculatorMetadata.fromJson((j['metadata'] as Map<String, dynamic>?) ?? {}),
      categories: cats,
    );
  }

  ConstructionItem? findItemById(String itemId) {
    for (final c in categories) {
      for (final i in c.items) {
        if (i.id == itemId) return i;
      }
    }
    return null;
  }
}

/// سطر مادة بعد تطبيق الهدر.
class ComputedMaterialLine {
  const ComputedMaterialLine({
    required this.materialKey,
    required this.labelEn,
    required this.quantity,
    required this.unitLabel,
  });

  final String materialKey;
  final String labelEn;
  final double quantity;
  final String unitLabel;
}

/// خيار تغطية (عبوات دهان / لاصق).
class ComputedPackageLine {
  const ComputedPackageLine({
    required this.packageLabel,
    required this.coveragePerPackage,
    required this.coverageUnitNote,
    required this.packagesNeeded,
    required this.effectiveAreaM2,
  });

  final String packageLabel;
  final double coveragePerPackage;
  final String coverageUnitNote;
  final int packagesNeeded;
  final double effectiveAreaM2;
}

/// نتيجة حاسبة موحّدة للواجهة.
class ConstructionComputationResult {
  const ConstructionComputationResult({
    required this.itemNameAr,
    required this.inputLabel,
    required this.inputValue,
    required this.inputUnitRaw,
    required this.wasteFactor,
    required this.materialLines,
    required this.packageLines,
    required this.expertTip,
  });

  final String itemNameAr;
  final String inputLabel;
  final double inputValue;
  final String inputUnitRaw;
  final double wasteFactor;
  final List<ComputedMaterialLine> materialLines;
  final List<ComputedPackageLine> packageLines;
  final String expertTip;

  bool get hasPackages => packageLines.isNotEmpty;
  bool get hasMaterials => materialLines.isNotEmpty;
}
