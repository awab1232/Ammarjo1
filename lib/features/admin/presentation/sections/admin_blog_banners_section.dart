import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';

/// المدونة والبانرات — بدون Firestore في لوحة الإدارة.
class AdminBlogBannersSection extends StatelessWidget {
  const AdminBlogBannersSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('المدونة والبانرات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 12),
        Text(
          'إدارة مقالات المدونة والبانرات أصبحت خارج واجهة Firestore. استخدم أدوات النشر أو لوحة الخادم.',
          style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.45),
          textAlign: TextAlign.right,
        ),
      ],
    );
  }
}
