import '../../../core/config/calculator_mapping_config.dart';
import 'calculator_service.dart';
import 'construction_calculator_models.dart';
import 'models.dart';

/// منتج موصى به مع وصف دوره (للمستلزمات).
class RecommendedEssential {
  RecommendedEssential({required this.product, required this.roleLabelAr});

  final Product product;
  final String roleLabelAr;
}

class _EssentialSlot {
  _EssentialSlot(this.roleLabelAr, this.anyOf, this.avoid, this.boostCategoryId);

  final String roleLabelAr;
  final List<String> anyOf;
  final List<String> avoid;
  final int? boostCategoryId;
}

/// ربط ذكي: مواد رئيسية + مستلزمات حسب نوع المهمة والبند المحسوب.
abstract final class QuantityProductMapper {
  static List<Product> mergeCatalog(List<Product> base, Iterable<Product> extra) {
    final seen = <int>{};
    final out = <Product>[];
    for (final p in [...base, ...extra]) {
      if (seen.add(p.id)) out.add(p);
    }
    return out;
  }

  static List<Product> pickMainProducts({
    required QuantityJobKind job,
    required ConstructionItem item,
    required ConstructionComputationResult result,
    required List<Product> catalog,
  }) {
    switch (job) {
      case QuantityJobKind.paints:
        return _mainPaints(item, catalog);
      case QuantityJobKind.flooring:
        return _mainFlooring(item, catalog, result);
      case QuantityJobKind.skeleton:
        return _mainSkeleton(item, catalog);
      case QuantityJobKind.generic:
        final keys = CalculatorService.keywordsForCartHints(item: item, result: result);
        if (keys.isEmpty) return <Product>[];
        return _byKeywords(catalog, keys, max: 10);
    }
  }

  static List<RecommendedEssential> pickEssentials({
    required QuantityJobKind job,
    required ConstructionItem item,
    required List<Product> catalog,
    required Set<int> excludeProductIds,
  }) {
    final slots = _slotsForJob(job);
    if (slots.isEmpty) return <RecommendedEssential>[];
    final used = <int>{...excludeProductIds};
    final out = <RecommendedEssential>[];
    final tagBoost = CalculatorMappingConfig.tagIdForJob(job);

    for (final slot in slots) {
      Product? best;
      var bestScore = -1000;
      for (final p in catalog) {
        if (used.contains(p.id)) continue;
        final s = _scoreSlot(p, slot, tagBoost);
        if (s > bestScore) {
          bestScore = s;
          best = p;
        }
      }
      if (best != null && bestScore >= 0) {
        out.add(RecommendedEssential(product: best, roleLabelAr: slot.roleLabelAr));
        used.add(best.id);
      }
    }
    return out;
  }

  // --- Main product heuristics ---

  static List<Product> _mainPaints(ConstructionItem item, List<Product> catalog) {
    final scored = <({Product p, int score})>[];
    for (final p in catalog) {
      final n = p.name.toLowerCase();
      final s = _paintMainScore(n);
      if (s >= 6) scored.add((p: p, score: s));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    // تقوية المطابقة مع اسم صنف الدهان في القاعدة
    final hint = item.nameAr.toLowerCase();
    scored.sort((a, b) {
      final ba = _nameOverlap(a.p.name.toLowerCase(), hint);
      final bb = _nameOverlap(b.p.name.toLowerCase(), hint);
      if (ba != bb) return bb.compareTo(ba);
      return b.score.compareTo(a.score);
    });
    return scored.map((e) => e.p).take(8).toList();
  }

  static int _nameOverlap(String productName, String hint) {
    var n = 0;
    for (final part in hint.split(RegExp(r'\s+'))) {
      final t = part.replaceAll(RegExp(r'[()\-]'), '').trim();
      if (t.length >= 3 && productName.contains(t)) n += t.length;
    }
    return n;
  }

  /// عبوات دهان — استبعاد أدوات (رول/فرش) كـ «رئيسي».
  static int _paintMainScore(String n) {
    if (_isPaintToolProduct(n)) return 0;
    var s = 0;
    if (n.contains('دهان') || n.contains('طلاء') || n.contains('أملشن')) s += 6;
    if (n.contains('emulsion') || n.contains('silk') || n.contains('vinyl')) s += 4;
    if (n.contains('جالون') || n.contains('دلو') || n.contains('gallon') || n.contains('drum')) s += 5;
    if (n.contains('معجون') && !n.contains('رول')) s += 3;
    return s;
  }

  static bool _isPaintToolProduct(String n) {
    final toolish = n.contains('رول') || n.contains('فرش') || n.contains('شريط لاصق') || n.contains('brush');
    final paintish = n.contains('دهان') || n.contains('طلاء') || n.contains('أملشن') || n.contains('جالون') || n.contains('دلو');
    return toolish && !paintish;
  }

  static List<Product> _mainFlooring(
    ConstructionItem item,
    List<Product> catalog,
    ConstructionComputationResult result,
  ) {
    final tiles = <Product>[];
    for (final p in catalog) {
      final n = p.name.toLowerCase();
      if (n.contains('بلاط') || n.contains('بورسلان') || n.contains('سيراميك') || n.contains('بورسلين')) {
        tiles.add(p);
      }
    }
    if (tiles.isNotEmpty) return tiles.take(8).toList();

    final adhesives = <Product>[];
    for (final p in catalog) {
      final n = p.name.toLowerCase();
      if (n.contains('لاصق') && (n.contains('بلاط') || n.contains('سيراميك') || n.contains('بورسلان'))) {
        adhesives.add(p);
      }
    }
    if (adhesives.isNotEmpty) {
      final hint = item.nameAr.toLowerCase();
      adhesives.sort((a, b) => _nameOverlap(b.name.toLowerCase(), hint).compareTo(_nameOverlap(a.name.toLowerCase(), hint)));
      return adhesives.take(8).toList();
    }

    final keys = CalculatorService.keywordsForCartHints(item: item, result: result);
    return _byKeywords(catalog, keys, max: 8);
  }

  static List<Product> _mainSkeleton(ConstructionItem item, List<Product> catalog) {
    final keys = switch (item.id) {
      'concrete_reinforced' => ['اسمنت', 'شيكارة', 'cement', 'bag', '50kg'],
      'reinforcement_steel' => ['حديد', 'تسليح', 'سيخ', 'rebar', 'steel'],
      'brick_walls_10cm' => ['طوب', 'طوبة', 'brick'],
      _ => <String>['اسمنت', 'طوب', 'حديد'],
    };
    return _byKeywords(catalog, keys, max: 8);
  }

  static List<Product> _byKeywords(List<Product> catalog, List<String> keys, {required int max}) {
    final seen = <int>{};
    final out = <Product>[];
    for (final p in catalog) {
      if (seen.contains(p.id)) continue;
      final n = p.name.toLowerCase();
      if (keys.any((k) => k.isNotEmpty && n.contains(k.toLowerCase()))) {
        seen.add(p.id);
        out.add(p);
        if (out.length >= max) break;
      }
    }
    return out;
  }

  // --- Essential slots ---

  static List<_EssentialSlot> _slotsForJob(QuantityJobKind job) {
    switch (job) {
      case QuantityJobKind.paints:
        return [
          _EssentialSlot(
            'رول دهان',
            ['رول', 'roller', 'رولة'],
            ['سلك كهرب', 'كابل'],
            CalculatorMappingConfig.wcCategoryPaintTools,
          ),
          _EssentialSlot(
            'فرش',
            ['فرش', 'فرشاة', 'brush'],
            ['معجون جدار فقط'],
            CalculatorMappingConfig.wcCategoryPaintTools,
          ),
          _EssentialSlot(
            'شريط تغطية',
            ['شريط لاصق', 'شريط تغليف', 'شريط تغطية', 'masking', 'tape'],
            ['سلك', 'كهرباء', 'لاصق بلاط'],
            CalculatorMappingConfig.wcCategoryPaintTools,
          ),
          _EssentialSlot(
            'غطاء حماية (بلاستيك/نايلون)',
            ['غطاء', 'نايلون', 'بلاستيك حماية', 'شرينك', 'ورق تغطية', 'sheeting', 'تغطية أرض'],
            ['جالون', 'دلو'],
            CalculatorMappingConfig.wcCategoryPaintTools,
          ),
        ];
      case QuantityJobKind.flooring:
        return [
          _EssentialSlot(
            'لاصق بلاط (داب)',
            ['لاصق بلاط', 'لاصق', 'داب', 'غراء بلاط', 'adhesive', 'thinset'],
            ['ترويب', 'grout فقط'],
            CalculatorMappingConfig.wcCategoryTileMaterials,
          ),
          _EssentialSlot(
            'ترويبة',
            ['ترويب', 'grout', 'رويب', 'مونة ترويب'],
            ['لاصق بلاط', 'فاصل'],
            CalculatorMappingConfig.wcCategoryTileMaterials,
          ),
          _EssentialSlot(
            'فواصل بلاستيك',
            ['فاصل', 'فواصل', 'spacer', 'مسافات', 'صليب'],
            ['لاصق'],
            CalculatorMappingConfig.wcCategoryTileMaterials,
          ),
        ];
      case QuantityJobKind.skeleton:
        return [
          _EssentialSlot(
            'رمل',
            ['رمل', 'رمال'],
            ['دهان', 'معجون'],
            CalculatorMappingConfig.wcCategoryAggregates,
          ),
          _EssentialSlot(
            'زلط / كنكري',
            ['زلط', 'حصى', 'كنكري', 'gravel'],
            ['دهان'],
            CalculatorMappingConfig.wcCategoryAggregates,
          ),
          _EssentialSlot(
            'حديد تسليح',
            ['حديد', 'تسليح', 'سيخ', 'rebar'],
            ['فرش', 'رول'],
            CalculatorMappingConfig.wcCategorySteel,
          ),
        ];
      case QuantityJobKind.generic:
        return <_EssentialSlot>[];
    }
  }

  static int _scoreSlot(Product p, _EssentialSlot slot, int? tagBoostId) {
    final n = p.name.toLowerCase();
    if (!slot.anyOf.any((k) => k.isNotEmpty && n.contains(k.toLowerCase()))) return -1;
    var sc = 8;
    for (final a in slot.avoid) {
      if (a.isNotEmpty && n.contains(a.toLowerCase())) sc -= 10;
    }
    final bc = slot.boostCategoryId;
    if (bc != null && p.categoryIds.contains(bc)) sc += 14;
    if (tagBoostId != null && p.tagIds.contains(tagBoostId)) sc += 10;
    return sc;
  }
}
