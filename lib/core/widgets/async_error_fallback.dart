import 'package:flutter/material.dart';

/// Shown when a [FutureBuilder]/[StreamBuilder] receives [AsyncSnapshot.hasError].
class ErrorRetryWidget extends StatelessWidget {
  const ErrorRetryWidget({
    super.key,
    this.title = 'Something went wrong',
    this.message,
    this.onRetry,
    this.compact = false,
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.cloud_off_outlined, size: compact ? 28 : 40, color: theme.colorScheme.outline),
        SizedBox(height: compact ? 6 : 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (message != null && message!.isNotEmpty) ...[
          SizedBox(height: compact ? 4 : 8),
          Text(
            message!,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        if (onRetry != null) ...[
          SizedBox(height: compact ? 8 : 16),
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ],
    );
    if (compact) {
      return Padding(padding: const EdgeInsets.all(12), child: body);
    }
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: body));
  }
}

/// Empty placeholder for successful loads with no data.
class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({
    super.key,
    this.title = 'No data yet',
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 8),
            Text(title, style: theme.textTheme.titleSmall),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Maps [AsyncSnapshot] to child, error UI, or loading without letting errors bubble to FlutterError.
Widget buildAsyncSnapshotSafe<T>({
  required BuildContext context,
  required AsyncSnapshot<T> snapshot,
  required Widget Function(BuildContext context, T data) dataBuilder,
  Widget Function(BuildContext context)? loadingBuilder,
  Widget Function(BuildContext context, Object error, StackTrace? stack)? errorBuilder,
  VoidCallback? onRetry,
  bool compactError = false,
}) {
  if (snapshot.hasError) {
    final err = snapshot.error!;
    final st = snapshot.stackTrace;
    assert(() {
      debugPrint('[AsyncSnapshotError] $err\n$st');
      return true;
    }());
    if (errorBuilder != null) {
      return errorBuilder(context, err, st);
    }
    return ErrorRetryWidget(
      message: err.toString(),
      onRetry: onRetry,
      compact: compactError,
    );
  }
  if (snapshot.connectionState == ConnectionState.waiting ||
      snapshot.connectionState == ConnectionState.none) {
    return loadingBuilder?.call(context) ??
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        );
  }
  return dataBuilder(context, snapshot.requireData);
}
