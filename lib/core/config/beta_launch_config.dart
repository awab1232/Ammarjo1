/// إعدادات إطلاق البيتا: عنوان API الإنتاج الافتراضي وقناة الملاحظات (اختياري عبر dart-define).
abstract final class BetaLaunchConfig {
  /// النطاق المخصّص للـ API (HTTPS، بدون شرطة مائلة أخيرة).
  /// يُستبدل بـ `--dart-define=BACKEND_ORDERS_BASE_URL=...` عند الحاجة.
  static const String productionOrdersApiDefault = 'https://api.ammarjo.com';

  /// رابط واتساب أو نموذج ويب للمختبرين، مثال:
  /// `--dart-define=BETA_FEEDBACK_URL=https://wa.me/9627xxxxxxxx`
  static const String feedbackUrl = String.fromEnvironment('BETA_FEEDBACK_URL', defaultValue: '');
}
