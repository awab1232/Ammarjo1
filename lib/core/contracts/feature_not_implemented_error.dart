/// Typed error for tooling / tests — prefer [FeatureState] in repository APIs.
class FeatureNotImplementedError extends Error {
  FeatureNotImplementedError(this.feature);
  final String feature;

  @override
  String toString() => 'FeatureNotImplementedError: $feature';
}
