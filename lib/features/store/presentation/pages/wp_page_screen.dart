import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/network/network_errors.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../data/wp_pages_api.dart';

/// عرض محتوى صفحة ووردبريس (نص بعد إزالة HTML البسيطة).
class WpPageScreen extends StatefulWidget {
  const WpPageScreen({
    super.key,
    required this.slug,
    required this.fallbackTitle,
  });

  final String slug;
  final String fallbackTitle;

  @override
  State<WpPageScreen> createState() => _WpPageScreenState();
}

class _WpPageScreenState extends State<WpPageScreen> {
  Future<WpPageContent?>? _future;

  @override
  void initState() {
    super.initState();
    _future = fetchWpPageBySlug(widget.slug);
  }

  static String _plainText(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const AppBarBackButton(),
        title: Text(widget.fallbackTitle, style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
      ),
      body: FutureBuilder<WpPageContent?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.orange));
          }
          if (snapshot.hasError) {
            final err = snapshot.error;
            final net = err != null ? networkUserMessage(err) : '';
            final msg = net.isNotEmpty
                ? net
                : 'تعذّر تحميل الصفحة. حاول مرة أخرى.';
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  msg,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          final page = snapshot.requireData;
          if (page == null) {
            return Center(
              child: Text(
                'الصفحة غير موجودة. تحقق من slug في wp_pages_config.dart',
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(color: AppColors.textSecondary),
              ),
            );
          }
          final body = _plainText(page.htmlBody);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (page.title.isNotEmpty)
                  Text(
                    page.title,
                    style: GoogleFonts.tajawal(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                if (page.title.isNotEmpty) const SizedBox(height: 16),
                Text(
                  body.isEmpty ? 'لا يوجد محتوى.' : body,
                  style: GoogleFonts.tajawal(fontSize: 15, height: 1.55, color: AppColors.textPrimary),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
