import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// صفحات يدعمها البانر الافتراضي عند غياب صورة من [home_banners].
enum AmmarJoBannerPage { stores, maintenance, marketplace, home }

/// بانر احتياطي موحّد — تدرج، شبكة خفيفة، عنوان وفرعي وأيقونة كبيرة.
class AmmarJoPageBannerFallback extends StatelessWidget {
  const AmmarJoPageBannerFallback({
    super.key,
    required this.page,
    this.height = 150,
    this.borderRadius = 16,
  });

  final AmmarJoBannerPage page;
  final double height;
  final double borderRadius;

  static Map<String, Object> _config(AmmarJoBannerPage p) {
    switch (p) {
      case AmmarJoBannerPage.stores:
        return {
          'gradient': const [Color(0xFFFF6B00), Color(0xFFE65100)],
          'icon': Icons.store_mall_directory_rounded,
          'title': 'متاجر مواد البناء',
          'subtitle': 'أفضل المنتجات بأفضل الأسعار',
        };
      case AmmarJoBannerPage.maintenance:
        return {
          'gradient': const [Color(0xFF1A1A2E), Color(0xFF16213E)],
          'icon': Icons.construction_rounded,
          'title': 'فنيون معتمدون',
          'subtitle': 'خبراء في كل مجال',
        };
      case AmmarJoBannerPage.marketplace:
        return {
          'gradient': const [Color(0xFF2C3E50), Color(0xFF3498DB)],
          'icon': Icons.sell_outlined,
          'title': 'سوق عمارجو للمستعمل',
          'subtitle': 'بيع واشتري بكل سهولة',
        };
      case AmmarJoBannerPage.home:
        return {
          'gradient': const [Color(0xFFFF6B00), Color(0xFF2C2C54)],
          'icon': Icons.home_work_outlined,
          'title': 'عمارجو',
          'subtitle': 'كل ما تحتاجه للبناء في مكان واحد',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _config(page);
    final colors = cfg['gradient'] as List<Color>;
    final icon = cfg['icon'] as IconData;
    final title = cfg['title'] as String;
    final subtitle = cfg['subtitle'] as String;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: colors,
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(painter: _GridPatternPainter()),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.tajawal(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: GoogleFonts.tajawal(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(icon, color: Colors.white.withValues(alpha: 0.35), size: height > 140 ? 70 : 52),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 20) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    for (double x = 0; x < size.width; x += 20) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPatternPainter oldDelegate) => false;
}
