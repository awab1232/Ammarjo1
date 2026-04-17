import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('No forbidden patterns in lib/', () async {
    final dir = Directory('lib');
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) {
      final normalized = f.path.replaceAll('\\', '/');
      return !normalized.endsWith('lib/core/security/deterministic_guard.dart');
    });

    final forbidden = [
      'Future<List',
      'Stream<List',
      'return []',
      '?? []',
      'snapshot.data',
    ];

    for (final file in files) {
      final content = await file.readAsString();
      for (final pattern in forbidden) {
        if (content.contains(pattern)) {
          fail('Forbidden pattern "$pattern" in ${file.path}');
        }
      }
    }
  });
}
