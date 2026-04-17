import 'package:flutter/material.dart';

/// AmmarJo — هوية برتقالية: أساس [primaryOrange]، خلفيات فاتحة، نصوص محايدة.
abstract final class AppColors {
  // ——— أساس ———
  static const Color background = Color(0xFFFFFFFF);
  /// خلفيات ثانوية للبطاقات والأقسام (#F5F5F7).
  static const Color surfaceSecondary = Color(0xFFF5F5F7);
  /// سوق المستعمل: لمسة خلفية خفيفة.
  static const Color surfaceMarketplace = Color(0xFFF7F7F9);

  // ——— برتقالي العلامة ———
  static const Color primaryOrange = Color(0xFFFF6B00);

  /// لون موحّد لأيقونة الرجوع في [AppBar] (`Icons.arrow_back_ios`).
  static const Color appBarBackIcon = primaryOrange;
  static const Color darkOrange = Color(0xFFE65100);
  static const Color lightOrange = Color(0xFFFFF3E0);
  static const Color accentOrange = Color(0xFFFFB347);
  /// وسيط للتدرجات (بديل أزرق مثل #3949AB).
  static const Color orangeMedium = Color(0xFFFF8C00);

  /// تمييز أساسي للأزرار والروابط (كان خوخياً؛ الآن برتقالي أساسي).
  static const Color accent = primaryOrange;
  static const Color accentLight = lightOrange;
  static const Color accentDark = darkOrange;

  /// أسماء قديمة متوافقة مع الكود الحالي.
  static const Color orange = accent;
  static const Color orangeLight = accentLight;
  static const Color orangeDark = accentDark;

  // ——— نص (ثابتة كما طُلب) ———
  /// عناوين — برتقالي أساسي (استبدال الكحلي #1A237E).
  static const Color heading = primaryOrange;
  static const Color textPrimary = Color(0xFF242830);
  static const Color textSecondary = Color(0xFF757575);

  /// اسم قديم: كان #1A237E — الآن برتقالي أساسي.
  static const Color navy = primaryOrange;
  static const Color slate = Color(0xFF5C6370);

  static const Color border = Color(0xFFE8E8ED);
  static const Color shadow = Color(0x14000000);

  static const Color error = Color(0xFFF44336);
  static const Color success = Color(0xFF4CAF50);

  // ——— تدرج رأس قسم الصيانة (بديل الأزرق #1A237E / #283593 / #303F9F) ———
  static const LinearGradient maintenanceHeaderGradient = LinearGradient(
    colors: <Color>[primaryOrange, orangeMedium, darkOrange],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );
}
