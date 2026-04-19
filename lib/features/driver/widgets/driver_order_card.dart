import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../data/driver_workbench_models.dart';

/// Compact card for one driver order row (assigned, active, or history).
class DriverOrderCard extends StatelessWidget {
  const DriverOrderCard({
    super.key,
    required this.order,
    this.trailing,
    this.dense = false,
  });

  final DriverWorkbenchOrder order;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final eta = order.etaMinutes;
    final dist = order.distanceKm;
    final meta = <String>[
      if (dist != null) '${dist.toStringAsFixed(1)} كم',
      if (eta != null) 'ETA ≈ $eta د',
      if (order.deliveryStatus.isNotEmpty) order.deliveryStatus,
    ].join(' · ');

    return Card(
      elevation: 0,
      color: AppColors.surfaceSecondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: EdgeInsets.all(dense ? 12 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.customerName,
                        style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.w700,
                          fontSize: dense ? 14 : 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order.address,
                        style: GoogleFonts.tajawal(
                          fontSize: 13,
                          height: 1.35,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#${order.orderId}',
                    style: GoogleFonts.tajawal(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.orange,
                    ),
                  ),
                ),
                if (meta.isNotEmpty)
                  Flexible(
                    child: Text(
                      meta,
                      textAlign: TextAlign.end,
                      style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
