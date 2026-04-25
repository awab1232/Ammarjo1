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
    this.onDirectionsStore,
    this.onDirectionsCustomer,
    this.onStartDelivery,
    this.onPickedUp,
    this.onDelivered,
  });

  final DriverWorkbenchOrder order;
  final Widget? trailing;
  final bool dense;
  final VoidCallback? onDirectionsStore;
  final VoidCallback? onDirectionsCustomer;
  final VoidCallback? onStartDelivery;
  final VoidCallback? onPickedUp;
  final VoidCallback? onDelivered;

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
                        '🏪 نقطة الاستلام',
                        style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.w800,
                          fontSize: dense ? 13 : 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order.storeName,
                        style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.w700,
                          fontSize: dense ? 13 : 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '📍 ${order.storeAddress}',
                        style: GoogleFonts.tajawal(
                          fontSize: 12,
                          height: 1.35,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if ((order.storePhone ?? '').trim().isNotEmpty)
                        Text(
                          '☎️ ${order.storePhone}',
                          style: GoogleFonts.tajawal(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        '👤 نقطة التسليم',
                        style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.w800,
                          fontSize: dense ? 13 : 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order.customerName,
                        style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.w700,
                          fontSize: dense ? 13 : 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '📍 ${order.address}',
                        style: GoogleFonts.tajawal(
                          fontSize: 12,
                          height: 1.35,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if ((order.customerPhone ?? '').trim().isNotEmpty)
                        Text(
                          '☎️ ${order.customerPhone}',
                          style: GoogleFonts.tajawal(
                            fontSize: 12,
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
                      style: GoogleFonts.tajawal(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            if (!dense &&
                (onDirectionsStore != null ||
                    onDirectionsCustomer != null ||
                    onStartDelivery != null ||
                    onPickedUp != null ||
                    onDelivered != null)) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onDirectionsStore != null)
                    OutlinedButton.icon(
                      onPressed: onDirectionsStore,
                      icon: const Icon(
                        Icons.store_mall_directory_outlined,
                        size: 18,
                      ),
                      label: Text(
                        'اتجاهات للمتجر',
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (onDirectionsCustomer != null)
                    OutlinedButton.icon(
                      onPressed: onDirectionsCustomer,
                      icon: const Icon(Icons.route_outlined, size: 18),
                      label: Text(
                        'اتجاهات للعميل',
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (onStartDelivery != null)
                    FilledButton.icon(
                      onPressed: onStartDelivery,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.navy,
                      ),
                      icon: const Icon(Icons.navigation_outlined, size: 18),
                      label: Text(
                        'ابدأ التوصيل',
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (onPickedUp != null)
                    FilledButton(
                      onPressed: onPickedUp,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.orange,
                      ),
                      child: Text(
                        'تم الاستلام',
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (onDelivered != null)
                    FilledButton(
                      onPressed: onDelivered,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                      ),
                      child: Text(
                        'تم التسليم',
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
