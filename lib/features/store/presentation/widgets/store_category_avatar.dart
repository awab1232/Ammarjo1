import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/widgets/ammar_cached_image.dart';

/// صورة قسم (دائرة أو مربع بحواف دائرية) مع خلفية رمادية و [BoxFit.contain]؛ عند غياب الرابط يُعرض شعار التطبيق أو أيقونة.
class StoreCategoryAvatar extends StatelessWidget {
  const StoreCategoryAvatar({
    super.key,
    required this.imageUrl,
    this.size = 64,
    this.borderRadius = 14,
    this.isCircular = false,
  });

  final String? imageUrl;
  final double size;
  final double borderRadius;
  final bool isCircular;

  @override
  Widget build(BuildContext context) {
    final raw = imageUrl?.trim() ?? '';
    final safe = raw.isNotEmpty ? webSafeImageUrl(raw) : '';

    Widget placeholder() {
      return ClipRRect(
        borderRadius: isCircular ? BorderRadius.circular(size / 2) : BorderRadius.circular(borderRadius),
        child: ColoredBox(
          color: const Color(0xFFE8EAED),
          child: Center(
            child: Icon(
              Icons.warehouse_outlined,
              size: size * 0.42,
              color: AppColors.accent.withValues(alpha: 0.75),
            ),
          ),
        ),
      );
    }

    if (safe.isEmpty) {
      return SizedBox(width: size, height: size, child: placeholder());
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: isCircular ? BorderRadius.circular(size / 2) : BorderRadius.circular(borderRadius),
        child: ColoredBox(
          color: const Color(0xFFF0F1F4),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: AmmarCachedImage(
              imageUrl: safe,
              fit: BoxFit.contain,
              width: size - 12,
              height: size - 12,
            ),
          ),
        ),
      ),
    );
  }
}
