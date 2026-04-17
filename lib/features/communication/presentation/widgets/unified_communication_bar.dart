import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';

/// شريط سفلي ثابت: دردشة (إطار) + اتصال (ممتلئ باللون الأساسي).
class UnifiedCommunicationBar extends StatelessWidget {
  const UnifiedCommunicationBar({
    super.key,
    required this.onChat,
    required this.onCall,
    required this.callEnabled,
    this.chatLabel = 'ابدأ الدردشة',
    this.callLabel = 'اتصل الآن',
  });

  final VoidCallback onChat;
  final VoidCallback onCall;
  final bool callEnabled;
  final String chatLabel;
  final String callLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      shadowColor: AppColors.shadow,
      color: AppColors.background,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onChat,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.navy,
                    side: const BorderSide(color: AppColors.navy, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    backgroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 22),
                  label: Text(chatLabel, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: callEnabled ? onCall : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.border,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.phone_in_talk_rounded, size: 22),
                  label: Text(callLabel, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
