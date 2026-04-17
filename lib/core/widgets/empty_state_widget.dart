import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum EmptyStateType {
  stores,
  products,
  orders,
  serviceRequests,
  wholesale,
  cart,
  search,
  notifications,
  chat,
  reviews,
  technicians,
  generic,
}

class EmptyStateWidget extends StatelessWidget {
  final EmptyStateType type;
  final VoidCallback? onAction;
  final String? customTitle;
  final String? customSubtitle;
  final String? actionLabel;

  const EmptyStateWidget({
    super.key,
    required this.type,
    this.onAction,
    this.customTitle,
    this.customSubtitle,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final config = _configs[type] ?? _configs[EmptyStateType.generic]!;
    final title = customTitle ?? config.title;
    final subtitle = customSubtitle ?? config.subtitle;
    final label = actionLabel ?? config.actionLabel;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B00).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  config.emoji,
                  style: const TextStyle(fontSize: 44),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(
                fontSize: 14,
                color: Colors.grey[500],
                height: 1.6,
              ),
            ),
            if (onAction != null && label != null) ...[
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.tajawal(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyConfig {
  final String emoji;
  final String title;
  final String subtitle;
  final String? actionLabel;

  const _EmptyConfig({
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.actionLabel,
  });
}

const _configs = <EmptyStateType, _EmptyConfig>{
  EmptyStateType.stores: _EmptyConfig(
    emoji: '🏪',
    title: 'لا توجد متاجر بعد',
    subtitle: 'لم نجد أي متاجر في هذه المنطقة.\nجرّب تغيير التصفية أو ابحث في منطقة أخرى.',
    actionLabel: 'استعرض كل المتاجر',
  ),
  EmptyStateType.products: _EmptyConfig(
    emoji: '📦',
    title: 'لا توجد منتجات',
    subtitle: 'هذا المتجر لم يضف منتجات بعد.\nتحقق لاحقاً أو استعرض متاجر أخرى.',
    actionLabel: 'تصفح متاجر أخرى',
  ),
  EmptyStateType.orders: _EmptyConfig(
    emoji: '🛍️',
    title: 'لا توجد طلبات بعد',
    subtitle: 'لم تقم بأي طلب حتى الآن.\nابدأ بتصفح المتاجر واختر ما يناسبك!',
    actionLabel: 'تسوّق الآن',
  ),
  EmptyStateType.serviceRequests: _EmptyConfig(
    emoji: '🔧',
    title: 'لا توجد طلبات صيانة',
    subtitle: 'لم تطلب أي خدمة صيانة بعد.\nفنيونا المحترفون جاهزون لمساعدتك.',
    actionLabel: 'اطلب فنياً الآن',
  ),
  EmptyStateType.wholesale: _EmptyConfig(
    emoji: '🏭',
    title: 'لا توجد موردون',
    subtitle: 'لا يوجد موردون متاحون حالياً.\nتحقق مجدداً قريباً.',
  ),
  EmptyStateType.cart: _EmptyConfig(
    emoji: '🛒',
    title: 'سلتك فارغة',
    subtitle: 'لم تضف أي منتجات بعد.\nابدأ التسوق وأضف ما يعجبك!',
    actionLabel: 'تسوّق الآن',
  ),
  EmptyStateType.search: _EmptyConfig(
    emoji: '🔍',
    title: 'لا توجد نتائج',
    subtitle: 'لم نجد نتائج لبحثك.\nجرّب كلمات مختلفة أو تصفح الفئات.',
    actionLabel: 'تصفح الفئات',
  ),
  EmptyStateType.notifications: _EmptyConfig(
    emoji: '🔔',
    title: 'لا توجد إشعارات',
    subtitle: 'ستظهر هنا إشعاراتك وتحديثات طلباتك.',
  ),
  EmptyStateType.chat: _EmptyConfig(
    emoji: '💬',
    title: 'لا توجد محادثات',
    subtitle: 'ابدأ محادثة مع أحد المتاجر أو الفنيين.',
    actionLabel: 'ابدأ محادثة',
  ),
  EmptyStateType.reviews: _EmptyConfig(
    emoji: '⭐',
    title: 'لا توجد تقييمات بعد',
    subtitle: 'كن أول من يقيّم هذا المتجر أو المنتج!',
    actionLabel: 'أضف تقييمك',
  ),
  EmptyStateType.technicians: _EmptyConfig(
    emoji: '👷',
    title: 'لا يوجد فنيون متاحون',
    subtitle: 'لا يوجد فنيون في منطقتك حالياً.\nسنخطرك فور توفر أحد.',
  ),
  EmptyStateType.generic: _EmptyConfig(
    emoji: '📭',
    title: 'لا توجد بيانات',
    subtitle: 'اسحب للأسفل للمحاولة مجدداً.',
    actionLabel: 'إعادة المحاولة',
  ),
};
