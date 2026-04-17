import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';

/// البنرات تُضبط من لوحة الخادم / التخزين — العرض فقط في التطبيق بعد الانتقال إلى REST.
class AdminBannerManagerSection extends StatelessWidget {
  const AdminBannerManagerSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('إدارة البنرات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 12),
        Text(
          'تم إيقاف تعديل البنرات من Firestore. تهيئة الصفحة الرئيسية والسوق والفنيين تتم عبر الخادم أو مسارات النشر — لا يُخزَّن هنا من التطبيق.',
          style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.45),
          textAlign: TextAlign.right,
        ),
      ],
    );
  }
}
