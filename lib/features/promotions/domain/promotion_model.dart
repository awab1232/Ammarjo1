import '../../store/domain/models.dart';

class Promotion {
  const Promotion({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.value,
    required this.buyQuantity,
    required this.getQuantity,
    required this.getDiscount,
    required this.applicableOn,
    required this.applicableIds,
    required this.minOrderAmount,
    required this.maxDiscount,
    required this.startDate,
    required this.endDate,
    required this.daysOfWeek,
    required this.usageLimit,
    required this.usagePerUser,
    required this.usedCount,
    required this.isActive,
    required this.isStackable,
    required this.createdAt,
    required this.createdBy,
  });

  final String id;
  final String name;
  final String description;
  final String type; // percentage | fixed | buy_x_get_y | free_shipping
  final double value;
  final int buyQuantity;
  final int getQuantity;
  final double getDiscount;
  final String applicableOn; // all | category | store | wholesaler | product
  final List<String> applicableIds;
  final double minOrderAmount;
  final double? maxDiscount;
  final DateTime startDate;
  final DateTime endDate;
  final List<int> daysOfWeek;
  final int? usageLimit;
  final int usagePerUser;
  final int usedCount;
  final bool isActive;
  final bool isStackable;
  final DateTime? createdAt;
  final String createdBy;

  factory Promotion.fromMap(Map<String, dynamic> d) {
    DateTime parseTs(dynamic v, DateTime fallback) =>
        DateTime.tryParse(v?.toString() ?? '') ?? fallback;
    final rawDays = d['daysOfWeek'];
    final days = <int>[];
    if (rawDays is List) {
      for (final e in rawDays) {
        final n = e is num ? e.toInt() : int.tryParse(e.toString());
        if (n != null && n >= 1 && n <= 7) days.add(n);
      }
    }
    final rawIds = d['applicableIds'];
    final ids = <String>[];
    if (rawIds is List) {
      for (final e in rawIds) {
        final s = e.toString().trim();
        if (s.isNotEmpty) ids.add(s);
      }
    }
    return Promotion(
      id: d['id']?.toString() ?? '',
      name: (d['name'] ?? '').toString(),
      description:
          (d['description'] ?? '').toString(),
      type: (d['type'] ?? 'percentage').toString(),
      value: (d['value'] is num)
          ? (d['value'] as num).toDouble()
          : 0.0,
      buyQuantity: (d['buyQuantity'] is num)
          ? (d['buyQuantity'] as num).toInt()
          : 0,
      getQuantity: (d['getQuantity'] is num)
          ? (d['getQuantity'] as num).toInt()
          : 0,
      getDiscount: (d['getDiscount'] is num)
          ? (d['getDiscount'] as num).toDouble()
          : 0.0,
      applicableOn: (d['applicableOn'] ?? 'all').toString(),
      applicableIds: ids,
      minOrderAmount: (d['minOrderAmount'] is num)
          ? (d['minOrderAmount'] as num).toDouble()
          : 0.0,
      maxDiscount: d['maxDiscount'] is num ? (d['maxDiscount'] as num).toDouble() : null,
      startDate: parseTs(d['startDate'], DateTime.fromMillisecondsSinceEpoch(0)),
      endDate: parseTs(d['endDate'], DateTime.fromMillisecondsSinceEpoch(253402300799000)),
      daysOfWeek: days.isEmpty ? const [1, 2, 3, 4, 5, 6, 7] : days,
      usageLimit: d['usageLimit'] is num ? (d['usageLimit'] as num).toInt() : null,
      usagePerUser: (d['usagePerUser'] is num)
          ? (d['usagePerUser'] as num).toInt()
          : 0,
      usedCount: (d['usedCount'] is num)
          ? (d['usedCount'] as num).toInt()
          : 0,
      isActive: d['isActive'] != false,
      isStackable: d['isStackable'] == true,
      createdAt: DateTime.tryParse(
        d['createdAt']?.toString() ?? '',
      ),
      createdBy: (d['createdBy'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'name': name,
        'description': description,
        'type': type,
        'value': value,
        'buyQuantity': buyQuantity,
        'getQuantity': getQuantity,
        'getDiscount': getDiscount,
        'applicableOn': applicableOn,
        'applicableIds': applicableIds,
        'minOrderAmount': minOrderAmount,
        if (maxDiscount != null) 'maxDiscount': maxDiscount,
        'startDate': startDate.toUtc().toIso8601String(),
        'endDate': endDate.toUtc().toIso8601String(),
        'daysOfWeek': daysOfWeek,
        if (usageLimit != null) 'usageLimit': usageLimit,
        'usagePerUser': usagePerUser,
        'usedCount': usedCount,
        'isActive': isActive,
        'isStackable': isStackable,
        if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
        'createdBy': createdBy,
      };
}

class PromotionValidationResult {
  const PromotionValidationResult({
    required this.isValid,
    required this.message,
    this.discountAmount = 0.0,
  });
  final bool isValid;
  final String message;
  final double discountAmount;
}

class PromotionsCalculationResult {
  const PromotionsCalculationResult({
    required this.appliedPromotions,
    required this.discountAmount,
    required this.freeShipping,
  });
  final List<Promotion> appliedPromotions;
  final double discountAmount;
  final bool freeShipping;
}

double productUnitPrice(Product p) {
  final raw = p.price.trim();
  final first = raw.contains('–') ? raw.split('–').first.trim() : raw;
  return double.tryParse(first) ?? 0.0;
}
