import 'package:flutter/material.dart';

/// زر رجوع موحّد — يعتمد لون الأيقونة على [IconTheme] القادم من [AppBar]
/// (أبيض على شريط برتقالي، داكن على شريط فاتح) ما دام لا يُمرَّر [iconColor].
class AppBarBackButton extends StatelessWidget {
  const AppBarBackButton({super.key, this.iconColor});

  /// عند الحاجة لتجاوز السياق (مثلاً شريط شفاف فوق صورة).
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final themed = IconTheme.of(context).color;
    final fg = iconColor ?? themed ?? Theme.of(context).appBarTheme.foregroundColor ?? Theme.of(context).colorScheme.onSurface;
    return IconButton(
      icon: Icon(Icons.arrow_back_ios, color: fg, size: 20),
      onPressed: () => Navigator.maybePop(context),
    );
  }
}
