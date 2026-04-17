/// توحيد قيم حالة الطلب بين لوحة المتجر (عربي)، و`orders` الجذرية، و`users/.../orders` (إنجليزي).
abstract final class OrderStatus {
  OrderStatus._();

  static const Map<String, String> arToEn = {
    'قيد المراجعة': 'pending',
    'قيد التحضير': 'processing',
    'قيد التوصيل': 'shipped',
    'تم التسليم': 'delivered',
    'مكتمل': 'completed',
    'ملغي': 'cancelled',
    'إلغاء': 'cancelled',
  };

  static const Map<String, String> enToAr = {
    'pending': 'قيد المراجعة',
    'processing': 'قيد التحضير',
    'shipped': 'قيد التوصيل',
    'delivered': 'تم التسليم',
    'completed': 'مكتمل',
    'cancelled': 'ملغي',
  };

  /// يحوّل حالة الواجهة العربية أو أي قيمة قديمة إلى المفتاح الإنجليزي الموحّد.
  static String toEnglish(String status) {
    final t = status.trim();
    if (t.isEmpty) return 'pending';
    if (arToEn.containsKey(t)) return arToEn[t]!;
    final lower = t.toLowerCase();
    if (enToAr.containsKey(lower)) return lower;
    const legacy = <String, String>{
      'loading': 'processing',
      'reviewing': 'pending',
      'preparing': 'processing',
      'on_the_way': 'shipped',
      'delivering': 'shipped',
      'on-hold': 'pending',
      'refunded': 'cancelled',
      'failed': 'cancelled',
    };
    return legacy[lower] ?? lower;
  }

  /// للعرض للمستخدم (طلباتي) — إن كانت المخزّنة إنجليزية تُرجَع العربية؛ وإلا النص كما هو.
  static String toArabicForDisplay(String stored) {
    final en = toEnglish(stored);
    return enToAr[en] ?? stored;
  }
}
