import 'package:flutter/material.dart';

import '../contracts/feature_state.dart';

/// Contract-aware UI for async [FeatureState] loads.
Widget buildFeatureStateUi<T>({
  required BuildContext context,
  required FeatureState<T> state,
  required Widget Function(BuildContext context, T data) dataBuilder,
  Widget Function(BuildContext context, String featureId)? onAdminNotWired,
  Widget Function(BuildContext context, String featureId)? onMissingBackend,
  Widget Function(BuildContext context, String featureId, Object? cause)? onCriticalFailure,
}) {
  return switch (state) {
    FeatureSuccess(:final data) => dataBuilder(context, data),
    FeatureAdminNotWired(:final featureName) =>
      onAdminNotWired?.call(context, featureName) ??
          _MessageCard(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Admin feature not available',
            subtitle: featureName,
          ),
    FeatureAdminMissingEndpoint(:final featureName) =>
      onAdminNotWired?.call(context, featureName) ??
          _MessageCard(
            icon: Icons.link_off,
            title: 'Admin endpoint not configured',
            subtitle: featureName,
          ),
    FeatureMissingBackend(:final featureName) =>
      onMissingBackend?.call(context, featureName) ??
          _MessageCard(
            icon: Icons.cloud_off_outlined,
            title: 'Feature coming soon',
            subtitle: featureName,
          ),
    FeatureCriticalPublicDataFailure(:final featureName, :final cause) =>
      onCriticalFailure?.call(context, featureName, cause) ??
          _MessageCard(
            icon: Icons.warning_amber_rounded,
            title: 'Service temporarily unavailable',
            subtitle: featureName,
            showRetryHint: true,
          ),
    FeatureFailure(:final message) => _MessageCard(
      icon: Icons.error_outline,
      title: 'Service temporarily unavailable',
      subtitle: message,
      showRetryHint: true,
    ),
  };
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.showRetryHint = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool showRetryHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                  if (showRetryHint) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Pull to refresh or try again later.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
