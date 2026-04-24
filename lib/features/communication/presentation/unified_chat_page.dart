import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/chat_feature_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_bar_back_button.dart';
import '../../maintenance/domain/maintenance_models.dart';
import '../domain/marketplace_listing_chat_models.dart';

class UnifiedChatPage extends StatefulWidget {
  const UnifiedChatPage.usedListing({super.key, required this.listing})
      : tech = null,
        categoryLabel = null,
        existingChatId = null,
        threadTitle = null;

  const UnifiedChatPage.technician({super.key, required this.tech, required this.categoryLabel})
      : listing = null,
        existingChatId = null,
        threadTitle = null;

  const UnifiedChatPage.resume({super.key, required this.existingChatId, required this.threadTitle})
      : listing = null,
        tech = null,
        categoryLabel = null;

  final MarketplaceListing? listing;
  final TechnicianProfile? tech;
  final String? categoryLabel;
  final String? existingChatId;
  final String? threadTitle;

  @override
  State<UnifiedChatPage> createState() => _UnifiedChatPageState();
}

class _UnifiedChatPageState extends State<UnifiedChatPage> {
  String get _title {
    if (widget.threadTitle != null && widget.threadTitle!.isNotEmpty) return widget.threadTitle!;
    if (widget.listing != null) return widget.listing!.title;
    if (widget.tech != null) return widget.tech!.displayName;
    return 'المحادثة';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        leading: Navigator.of(context).canPop() ? const AppBarBackButton() : null,
        title: Text(
          _title,
          style: GoogleFonts.tajawal(
            fontWeight: FontWeight.w800,
            color: AppColors.heading,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            kChatFeatureEnabled ? 'الدردشة معطلة مؤقتًا.' : kChatFeatureUnavailableMessage,
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}
