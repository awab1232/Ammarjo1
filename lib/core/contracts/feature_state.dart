import 'package:flutter/foundation.dart' show debugPrint;

import 'feature_unit.dart';

/// Explicit contract outcome for repository / feature calls (no silent empty fallbacks).
sealed class FeatureState<T> {
  const FeatureState._();

  static FeatureState<T> success<T>(T data) => FeatureSuccess<T>(data);
  static FeatureState<T> missingBackend<T>(String featureName) => FeatureMissingBackend<T>(featureName);
  static FeatureState<T> adminNotWired<T>(String featureName) => FeatureAdminNotWired<T>(featureName);
  static FeatureState<T> adminMissingEndpoint<T>(String featureName) =>
      FeatureAdminMissingEndpoint<T>(featureName);
  static FeatureState<T> criticalPublicDataFailure<T>(String featureName, [Object? cause]) =>
      FeatureCriticalPublicDataFailure<T>(featureName, cause);
  static FeatureState<T> failure<T>(String message, [Object? cause]) =>
      FeatureFailure<T>(message, cause);

  void logIfNotSuccess(String context) {
    switch (this) {
      case FeatureSuccess():
        return;
      case FeatureMissingBackend(:final featureName):
        debugPrint('[$context] missingBackend: $featureName');
      case FeatureAdminNotWired(:final featureName):
        debugPrint('[$context] adminNotWired: $featureName');
      case FeatureAdminMissingEndpoint(:final featureName):
        debugPrint('[$context] adminMissingEndpoint: $featureName');
      case FeatureCriticalPublicDataFailure(:final featureName, :final cause):
        debugPrint('[$context] criticalPublicDataFailure: $featureName cause=$cause');
      case FeatureFailure(:final message, :final cause):
        debugPrint('[$context] failure: $message cause=$cause');
    }
  }
}

final class FeatureSuccess<T> extends FeatureState<T> {
  const FeatureSuccess(this.data) : super._();
  final T data;
}

final class FeatureMissingBackend<T> extends FeatureState<T> {
  const FeatureMissingBackend(this.featureName) : super._();
  final String featureName;
}

final class FeatureAdminNotWired<T> extends FeatureState<T> {
  const FeatureAdminNotWired(this.featureName) : super._();
  final String featureName;
}

final class FeatureAdminMissingEndpoint<T> extends FeatureState<T> {
  const FeatureAdminMissingEndpoint(this.featureName) : super._();
  final String featureName;
}

/// Customer-facing data could not be loaded — UI must show "Service temporarily unavailable".
final class FeatureCriticalPublicDataFailure<T> extends FeatureState<T> {
  const FeatureCriticalPublicDataFailure(this.featureName, [this.cause]) : super._();
  final String featureName;
  final Object? cause;
}

final class FeatureFailure<T> extends FeatureState<T> {
  const FeatureFailure(this.message, [this.cause]) : super._();
  final String message;
  final Object? cause;
}

typedef AdminFeatureState = FeatureState<FeatureUnit>;
