void enforceDeterministicRules(String content) {
  final forbidden = [
    '?? 0',
    '?? 0.0',
    "?? ''",
    '?? false',
    'return []',
    'return null',
    'success(null)',
  ];

  for (final rule in forbidden) {
    if (content.contains(rule)) {
      throw StateError('DETERMINISM VIOLATION: $rule');
    }
  }
}

