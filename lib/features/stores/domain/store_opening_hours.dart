/// أوقات عمل المتجر (يُخزَّن كـ JSON في `opening_hours` / `openingHours`).
class StoreWeeklyHours {
  const StoreWeeklyHours({
    required this.enabled,
    required this.byWeekday,
  });

  /// إذا `false` يُعتبر المتجر مفتوحاً دائماً من ناحية العرض.
  final bool enabled;

  /// مفاتيح [DateTime.weekday] (1 = اثنين … 7 = أحد).
  final Map<int, StoreDaySlot> byWeekday;

  static const _weekdayOrder = <int>[1, 2, 3, 4, 5, 6, 7];

  static StoreWeeklyHours? tryParse(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final enabled = m['enabled'] == true;
    final by = <int, StoreDaySlot>{};
    final map = m['byWeekday'] ?? m['by_weekday'];
    if (map is Map) {
      for (final e in map.entries) {
        final k = int.tryParse(e.key.toString());
        if (k == null || k < 1 || k > 7) continue;
        final v = e.value;
        if (v is! Map) continue;
        final vm = Map<String, dynamic>.from(v);
        final closed = vm['closed'] == true;
        final open = (vm['open'] ?? vm['openHm'] ?? '09:00').toString().trim();
        final close = (vm['close'] ?? vm['closeHm'] ?? '21:00').toString().trim();
        by[k] = StoreDaySlot(closed: closed, openHm: open, closeHm: close);
      }
    }
    return StoreWeeklyHours(enabled: enabled, byWeekday: by);
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'byWeekday': {
          for (final k in _weekdayOrder)
            if (byWeekday.containsKey(k)) '$k': byWeekday[k]!.toJson(),
        },
      };

  /// يُرجع `null` إن لم تُفعَّل أوقات العمل (لا يُعرض «مغلق»).
  /// عند التفعيل دون تعريف لليوم الحالي يُعامل كمغلق.
  bool? isOpenNow(DateTime localNow) {
    if (!enabled) return null;
    final wd = localNow.weekday;
    final slot = byWeekday[wd];
    if (slot == null) return false;
    if (slot.closed) return false;
    final openM = _parseHm(slot.openHm);
    final closeM = _parseHm(slot.closeHm);
    if (openM == null || closeM == null) return false;
    if (closeM <= openM) return false;
    final nowM = localNow.hour * 60 + localNow.minute;
    return nowM >= openM && nowM < closeM;
  }

  static int? _parseHm(String s) {
    final p = s.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0].trim());
    final m = int.tryParse(p[1].trim());
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  static StoreWeeklyHours defaultTemplate() {
    const slot = StoreDaySlot(closed: false, openHm: '09:00', closeHm: '21:00');
    return StoreWeeklyHours(
      enabled: false,
      byWeekday: {for (final d in _weekdayOrder) d: slot},
    );
  }

  static String weekdayLabelAr(int weekday) {
    return switch (weekday) {
      1 => 'الاثنين',
      2 => 'الثلاثاء',
      3 => 'الأربعاء',
      4 => 'الخميس',
      5 => 'الجمعة',
      6 => 'السبت',
      7 => 'الأحد',
      _ => '',
    };
  }
}

class StoreDaySlot {
  const StoreDaySlot({
    required this.closed,
    required this.openHm,
    required this.closeHm,
  });

  final bool closed;
  final String openHm;
  final String closeHm;

  Map<String, dynamic> toJson() => {
        'closed': closed,
        'open': openHm,
        'close': closeHm,
      };
}
