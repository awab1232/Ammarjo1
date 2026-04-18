import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../contracts/feature_state.dart';
import '../theme/app_colors.dart';

/// Contract-aware UI for async [FeatureState] loads.
///
/// [onRetry] يُعرض كزر «إعادة المحاولة» عند فشل الخدمة (عند تمريره من الشاشة الأم).
Widget buildFeatureStateUi<T>({
  required BuildContext context,
  required FeatureState<T> state,
  required Widget Function(BuildContext context, T data) dataBuilder,
  Widget Function(BuildContext context, String featureId)? onAdminNotWired,
  Widget Function(BuildContext context, String featureId)? onMissingBackend,
  Widget Function(BuildContext context, String featureId, Object? cause)? onCriticalFailure,
  VoidCallback? onRetry,
}) {
  return switch (state) {
    FeatureSuccess(:final data) => dataBuilder(context, data),
    FeatureAdminNotWired(:final featureName) =>
      onAdminNotWired?.call(context, featureName) ??
          _MessageCard(
            icon: Icons.admin_panel_settings_outlined,
            title: 'ميزة الإدارة غير مفعّلة حالياً',
            subtitle: '',
            detail: featureName,
          ),
    FeatureAdminMissingEndpoint(:final featureName) =>
      onAdminNotWired?.call(context, featureName) ??
          _MessageCard(
            icon: Icons.link_off_rounded,
            title: 'لم يتم ضبط عنوان الخادم لهذه الميزة',
            subtitle: '',
            detail: featureName,
          ),
    FeatureMissingBackend(:final featureName) =>
      onMissingBackend?.call(context, featureName) ??
          _MessageCard(
            icon: Icons.cloud_off_outlined,
            title: 'الميزة ستتوفر قريباً',
            subtitle: '',
            detail: featureName,
          ),
    FeatureCriticalPublicDataFailure(:final featureName, :final cause) =>
      onCriticalFailure?.call(context, featureName, cause) ??
          _MessageCard(
            icon: Icons.wifi_tethering_error_rounded,
            title: 'تعذّر الاتصال بالخادم',
            subtitle: 'تحقق من الإنترنت ثم أعد المحاولة.',
            detail: featureName,
            showRetryHint: true,
            onRetry: onRetry,
          ),
    FeatureFailure(:final message) => _MessageCard(
      icon: Icons.error_outline_rounded,
      title: 'تعذّر إكمال الطلب',
      subtitle: 'جرّب مرة أخرى بعد قليل.',
      detail: message,
      showRetryHint: true,
      onRetry: onRetry,
    ),
  };
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.detail,
    this.showRetryHint = false,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String detail;
  final bool showRetryHint;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: AppColors.surfaceSecondary.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.primaryOrange, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary, height: 1.25),
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
                      ),
                    ],
                    if (detail.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary.withValues(alpha: 0.9)),
                      ),
                    ],
                    if (showRetryHint && onRetry == null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'اسحب للتحديث أو أعد فتح الشاشة.',
                        style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                    if (onRetry != null) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        label: Text('إعادة المحاولة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
