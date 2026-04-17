import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';

/// Premium gold-style card for AmmarJo loyalty balance (orange accent).
class AmmarjoLoyaltyGoldCard extends StatelessWidget {
  const AmmarjoLoyaltyGoldCard({
    super.key,
    required this.points,
  });

  final int points;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF8B6914),
            Color(0xFFC9A227),
            Color(0xFFE8D48A),
            Color(0xFFD4AF37),
          ],
          stops: [0.0, 0.35, 0.65, 1.0],
        ),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.95), width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.orange.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.workspace_premium_rounded, color: Colors.white.withValues(alpha: 0.95), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'AmmarJo Points: $points',
                  style: GoogleFonts.tajawal(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.3,
                    shadows: [
                      Shadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(0, 1)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '1 JD = 1 Point. Collect points for free gifts!',
            style: GoogleFonts.tajawal(
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }
}
