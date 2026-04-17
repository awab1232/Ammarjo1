import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import 'construction_calculator_models.dart';

/// تحميل JSON وتطبيق معادلات الكميات مع [waste_factor].
class CalculatorService {
  CalculatorService._(this.db);

  final ConstructionCalculatorDb db;

  static CalculatorService? _cached;

  static const assetPath = 'assets/data/construction_calculator_db.json';

  static Future<CalculatorService> instance() async {
    if (_cached != null) return _cached!;
    final raw = await rootBundle.loadString(assetPath);
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final inner = map['construction_calculator_db'] as Map<String, dynamic>;
    _cached = CalculatorService._(ConstructionCalculatorDb.fromJson(inner));
    return _cached!;
  }

  /// لاختبار الوحدات دون أصول.
  static CalculatorService fromJsonString(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final inner = map['construction_calculator_db'] as Map<String, dynamic>;
    return CalculatorService._(ConstructionCalculatorDb.fromJson(inner));
  }

  /// تسمية حقل الإدخال بالعربية وفق وحدة العنصر في JSON.
  static String inputFieldLabelAr(String unitRaw) {
    final u = unitRaw.trim().toLowerCase();
    if (u == 'm3' || u.contains('m3')) return 'الحجم (م³)';
    if (u == 'm2' || u.contains('m2')) return 'المساحة (م²)';
    if (u == 'meter' || u == 'م') return 'الطول (م)';
    return 'الكمية';
  }

  /// وصف قصير للوحدة في بطاقة النتيجة.
  static String inputUnitDescriptionAr(String unitRaw) {
    final u = unitRaw.trim().toLowerCase();
    if (u.contains('m3') && u.contains('concrete')) return 'م³ خرسانة';
    if (u == 'm3' || (u.contains('m3') && !u.contains('m2'))) return 'م³';
    if (u == 'm2' || u.contains('m2')) return 'م²';
    if (u == 'meter') return 'متر';
    return unitRaw;
  }

  ConstructionComputationResult compute({
    required ConstructionItem item,
    required double inputValue,
  }) {
    if (inputValue <= 0) {
      throw ArgumentError.value(inputValue, 'inputValue', 'يجب أن تكون القيمة أكبر من صفر');
    }
    if (!item.isComponentBased && !item.isCoverageBased) {
      throw StateError('عنصر بدون مكوّنات ولا أحجام تغطية: ${item.id}');
    }

    final waste = item.wasteFactor;
    final inputLabel = inputFieldLabelAr(item.unit);
    final materials = <ComputedMaterialLine>[];
    final packages = <ComputedPackageLine>[];

    if (item.isComponentBased) {
      final m = 1.0 + waste;
      for (final c in item.components) {
        final q = inputValue * c.quantity * m;
        materials.add(
          ComputedMaterialLine(
            materialKey: c.material,
            labelEn: c.material,
            quantity: q,
            unitLabel: c.unit,
          ),
        );
      }
    }

    if (item.isCoverageBased) {
      final effective = inputValue * (1.0 + waste);
      for (final sz in item.availableSizes) {
        if (sz.coverage <= 0) continue;
        final n = math.max(1, (effective / sz.coverage).ceil());
        packages.add(
          ComputedPackageLine(
            packageLabel: sz.size,
            coveragePerPackage: sz.coverage,
            coverageUnitNote: sz.unit,
            packagesNeeded: n,
            effectiveAreaM2: effective,
          ),
        );
      }
    }

    return ConstructionComputationResult(
      itemNameAr: item.nameAr,
      inputLabel: inputLabel,
      inputValue: inputValue,
      inputUnitRaw: item.unit,
      wasteFactor: waste,
      materialLines: materials,
      packageLines: packages,
      expertTip: item.expertTip,
    );
  }

  /// كلمات للبحث في كتالوج المتجر عن مادة محسوبة.
  static List<String> keywordsForMaterial(String materialKey) {
    final k = materialKey.trim().toLowerCase();
    switch (k) {
      case 'cement':
        return ['اسمنت', 'سمنت', 'cement', 'bag'];
      case 'sand':
        return ['رمل', 'رمال', 'sand'];
      case 'gravel':
        return ['حصى', 'زلط', 'كنكري', 'gravel'];
      case 'water':
        return <String>[];
      case 'steel rebar':
        return ['حديد', 'تسليح', 'سيخ', 'rebar', 'steel'];
      case 'bricks (20x40x10)':
      case 'bricks':
        return ['طوب', 'طوبة', 'brick'];
      case 'ppr pipe':
        return ['ppr', 'أنبوب', 'مواسير', 'pipe'];
      case 'bitumen rolls':
        return ['عزل', 'زفت', 'رول', 'bitumen', 'أسفلت'];
      default:
        return [materialKey];
    }
  }

  /// دمج كلمات كل المواد + اسم الصنف (للدهانات واللاصق).
  static List<String> keywordsForCartHints({
    required ConstructionItem item,
    required ConstructionComputationResult result,
  }) {
    final set = <String>{};
    for (final line in result.materialLines) {
      for (final kw in keywordsForMaterial(line.materialKey)) {
        if (kw.isNotEmpty) set.add(kw);
      }
    }
    final name = item.nameAr;
    for (final part in name.split(RegExp(r'[\s()\-،]+'))) {
      final t = part.trim();
      if (t.length >= 3) set.add(t);
    }
    for (final idPart in item.id.split('_')) {
      if (idPart.length > 2) set.add(idPart);
    }
    return set.toList();
  }

  static bool shouldSuggestProductForMaterial(String materialKey) =>
      keywordsForMaterial(materialKey).isNotEmpty;

  /// عرض عربي للمكوّن في واجهة النتائج.
  static String materialLabelAr(String materialKey) {
    switch (materialKey.trim().toLowerCase()) {
      case 'cement':
        return 'أسمنت';
      case 'sand':
        return 'رمل';
      case 'gravel':
        return 'حصى (كنكري)';
      case 'water':
        return 'ماء';
      case 'steel rebar':
        return 'حديد تسليح';
      case 'bricks (20x40x10)':
        return 'طوب (20×40×10 سم)';
      case 'ppr pipe':
        return 'أنبوب PPR';
      case 'bitumen rolls':
        return 'رولات عزل زفتي';
      default:
        return materialKey;
    }
  }
}
