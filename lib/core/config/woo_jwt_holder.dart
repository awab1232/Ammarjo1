/// آخر توكن Woo/JWT من `jwt-auth/v1/token` — يُحدَّث بعد تسجيل الدخول ليُستخدم في رؤوس
/// `Authorization` لطلبات WooCommerce وأي طلبات `ammarjo.net` الأخرى (REST). يُمسح عند تسجيل الخروج.
abstract final class WooJwtHolder {
  static String? _token;

  static String? get token => _token;

  static void setToken(String? value) {
    final v = value?.trim();
    _token = (v == null || v.isEmpty) ? null : v;
  }

  static Map<String, String> authorizationHeaders() {
    final t = _token;
    if (t == null || t.isEmpty) return const {};
    return {'Authorization': 'Bearer $t'};
  }
}
