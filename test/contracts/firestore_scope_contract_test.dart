import 'dart:io';

import 'package:test/test.dart';

/// Build-time / CI contract: `cloud_firestore` must only be imported under
/// `lib/features/communication/`.
void main() {
  test('Firestore SDK is scoped to communication feature only', () {
    final root = Directory('lib');
    expect(root.existsSync(), isTrue, reason: 'Run tests from Flutter project root');
    final violations = <String>[];
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized.contains('lib/features/communication/')) continue;
      final text = entity.readAsStringSync();
      if (text.contains("import 'package:cloud_firestore/cloud_firestore.dart'") ||
          text.contains('import "package:cloud_firestore/cloud_firestore.dart"')) {
        violations.add(normalized);
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'Firestore imports outside communication: ${violations.join(', ')}',
    );
  });
}
