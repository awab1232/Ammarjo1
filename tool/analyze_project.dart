// تحليل شامل لمشروع Flutter: شاشات، أزرار فارغة، Firebase، مستودعات، إلخ.
//
// التشغيل من جذر المشروع:
//   dart tool/analyze_project.dart
//   dart tool/analyze_project.dart --json-only
//
// يُكتب أيضاً: tool/analysis_report.json

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final jsonOnly = args.contains('--json-only');
  void debugPrint(Object? message) {
    if (!jsonOnly) {
      // ignore: avoid_print
      print('[analyze_project] $message');
    }
  }

  final scriptPath = Platform.script.toFilePath();
  final toolDir = File(scriptPath).parent;
  final projectRoot = toolDir.parent;
  final libDir = Directory('${projectRoot.path}${Platform.pathSeparator}lib');

  if (!libDir.existsSync()) {
    debugPrint('خطأ: لم يُعثر على مجلد lib: ${libDir.path}');
    exitCode = 1;
    return;
  }

  final packageName = _readPackageName(projectRoot);
  debugPrint('جذر المشروع: ${projectRoot.path}');
  debugPrint('الحزمة: $packageName');
  debugPrint('جمع ملفات .dart ...');

  final dartFiles = <File>[];
  _collectDartFiles(libDir, dartFiles);
  debugPrint('عدد الملفات (بعد الاستثناء): ${dartFiles.length}');

  final fileContents = <String, String>{};
  for (final f in dartFiles) {
    try {
      fileContents[_normalizePath(projectRoot, f)] = f.readAsStringSync();
    } catch (e, st) {
      debugPrint('تحذير: فشل قراءة ${f.path}: $e');
      debugPrint('$st');
    }
  }

  // مستودعات: تحت lib/**/data/** واسم الملف يحتوي repository
  final repoFiles = <String, String>{}; // relative path -> content
  for (final e in fileContents.entries) {
    final p = e.key.replaceAll('\\', '/');
    if (p.contains('/data/') && p.toLowerCase().contains('repository')) {
      repoFiles[p] = e.value;
    }
  }

  final repoImportPaths = <String>[];
  for (final path in repoFiles.keys) {
    final imp = _packageImport(packageName, path);
    repoImportPaths.add(imp);
  }
  repoImportPaths.sort();

  // شاشات: *_screen.dart أو .../presentation/pages/...
  final screenPaths = <String>[];
  for (final path in fileContents.keys) {
    final n = path.replaceAll('\\', '/').split('/').last.toLowerCase();
    final p = path.replaceAll('\\', '/');
    if (n.endsWith('_screen.dart') ||
        p.contains('/presentation/pages/') && n.endsWith('.dart')) {
      screenPaths.add(path);
    }
  }
  screenPaths.sort();

  debugPrint('تحليل ${screenPaths.length} شاشة محتملة ...');

  final emptyButtonsList = <Map<String, dynamic>>[];
  final screensOut = <Map<String, dynamic>>[];

  var totalEmptyButtons = 0;
  var mockDataScreens = 0;

  // فهرس استيراد المستودعات من أي ملف (للكشف عن غير المستخدم)
  // مستودعات غير مستوردة في أي **شاشة** (حسب المطلوب)، مع مطابقة اسم الملف أيضاً.
  final repoBasenames = <String, String>{
    for (final path in repoFiles.keys)
      path.replaceAll('\\', '/').split('/').last: _packageImport(packageName, path),
  };

  final repoUsedInScreens = <String, bool>{
    for (final r in repoImportPaths) r: false,
  };

  void markRepoUsed(String screenContent) {
    for (final r in repoImportPaths) {
      if (screenContent.contains(r)) repoUsedInScreens[r] = true;
    }
    for (final e in repoBasenames.entries) {
      if (screenContent.contains(e.key)) {
        repoUsedInScreens[e.value] = true;
      }
    }
  }

  for (final rel in screenPaths) {
    markRepoUsed(fileContents[rel] ?? '');
  }

  final missingRepos = repoImportPaths.where((r) => repoUsedInScreens[r] != true).toList();

  for (final rel in screenPaths) {
    final content = fileContents[rel] ?? '';
    final lines = content.split('\n');

    final type = _classifyType(rel, content);
    final usesFirebase = _usesFirebase(content);
    final usesFirestore = _usesFirestore(content);
    final usesStream = content.contains('StreamBuilder');
    final usesFuture = content.contains('FutureBuilder');
    final usesProviderState = _usesProviderState(content);

    final issues = <String>[];
    final screenEmptyButtons = <Map<String, dynamic>>[];

    // أزرار فارغة / null
    _findEmptyButtons(
      lines,
      rel,
      screenEmptyButtons,
    );
    for (final b in screenEmptyButtons) {
      issues.add('${b['kind']} at line ${b['line']}');
    }
    totalEmptyButtons += screenEmptyButtons.length;
    emptyButtonsList.addAll(screenEmptyButtons);

    // بيانات وهمية (استدلالية)
    final mockFlags = _mockDataHeuristics(content, usesFirestore, usesStream, usesFuture);
    if (mockFlags.isNotEmpty) {
      mockDataScreens++;
      issues.addAll(mockFlags);
    }

    // يتطلب ربطاً ببيانات مباشرة: Firestore/Storage وليس مجرد Auth على النموذج
    if (usesFirestore && !usesStream && !usesFuture) {
      issues.add(
        'Firestore/Storage present but no StreamBuilder/FutureBuilder in file (verify data binding)',
      );
    }

    final hasEmptyButtons = screenEmptyButtons.isNotEmpty;
    final hasMockData = mockFlags.isNotEmpty ||
        (usesFirestore && !usesStream && !usesFuture);

    var status = 'working';
    if (hasEmptyButtons || mockFlags.isNotEmpty) {
      status = 'broken';
    } else if (usesFirestore && !usesStream && !usesFuture) {
      status = 'broken';
    } else if (issues.isNotEmpty) {
      status = 'broken';
    }

    screensOut.add({
      'path': rel.replaceAll('\\', '/'),
      'type': type,
      'usesFirebase': usesFirebase,
      'usesFirestoreApi': usesFirestore,
      'usesStreamBuilder': usesStream,
      'usesFutureBuilder': usesFuture,
      'usesProviderState': usesProviderState,
      'hasEmptyButtons': hasEmptyButtons,
      'hasMockData': hasMockData,
      'status': status,
      'issues': issues,
    });
  }

  final workingScreens = screensOut.where((s) => s['status'] == 'working').length;
  final brokenScreens = screensOut.length - workingScreens;

  final report = <String, dynamic>{
    'summary': {
      'totalScreens': screensOut.length,
      'workingScreens': workingScreens,
      'brokenScreens': brokenScreens,
      'emptyButtons': totalEmptyButtons,
      'mockDataScreens': mockDataScreens,
      'missingRepositories': missingRepos,
      'packageName': packageName,
      'analyzedDartFiles': fileContents.length,
    },
    'screens': screensOut,
    'emptyButtonsList': emptyButtonsList,
    'note':
        'mockData و ListView heuristics تقريبية؛ راجع يدوياً. missingRepositories = مستودعات تحت data/* غير مذكورة في أي ملف شاشة (استيراد package أو اسم الملف).',
  };

  const encoder = JsonEncoder.withIndent('  ');
  final jsonText = encoder.convert(report);

  final outFile = File('${toolDir.path}${Platform.pathSeparator}analysis_report.json');
  outFile.writeAsStringSync(jsonText);
  debugPrint('تم حفظ: ${outFile.path}');

  if (!jsonOnly) {
    // ignore: avoid_print
    print(jsonText);
  } else {
    // ignore: avoid_print
    print(jsonText);
  }
}

String _readPackageName(Directory projectRoot) {
  final pub = File('${projectRoot.path}${Platform.pathSeparator}pubspec.yaml');
  if (!pub.existsSync()) return 'app';
  final text = pub.readAsStringSync();
  final m = RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(text);
  return m?.group(1) ?? 'app';
}

void _collectDartFiles(Directory dir, List<File> out) {
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final p = entity.path;
    final segments = p.replaceAll('\\', '/').split('/');
    if (segments.contains('generated') || segments.contains('l10n') || segments.contains('dev')) {
      continue;
    }
    if (p.endsWith('.dart')) out.add(entity);
  }
}

String _normalizePath(Directory projectRoot, File f) {
  final root = projectRoot.absolute.path;
  var abs = f.absolute.path;
  if (abs.startsWith(root)) {
    abs = abs.substring(root.length);
    if (abs.startsWith(Platform.pathSeparator)) {
      abs = abs.substring(1);
    }
  }
  return abs;
}

String _packageImport(String packageName, String libRelativePath) {
  // lib/features/foo/bar.dart -> package:ammar_store/features/foo/bar.dart
  var s = libRelativePath.replaceAll('\\', '/');
  if (s.startsWith('lib/')) s = s.substring(4);
  return 'package:$packageName/$s';
}

String _classifyType(String relPath, String content) {
  final p = relPath.replaceAll('\\', '/').toLowerCase();
  final lower = content;

  if (p.contains('/data/') && p.contains('repository')) return 'Repository';
  if (p.contains('_repository.dart')) return 'Repository';
  if (p.contains('/services/') || p.endsWith('_service.dart')) return 'Service';
  if (p.contains('_service.dart')) return 'Service';
  if (p.contains('/models/') || p.contains('_model.dart')) return 'Model';
  if (p.contains('_provider.dart') || lower.contains('extends changenotifier')) {
    return 'Provider';
  }
  if (p.contains('_controller.dart')) return 'Controller';
  if (p.contains('_screen.dart') || p.contains('/presentation/pages/')) return 'Screen';
  if (p.contains('/presentation/')) return 'Widget';
  return 'Widget';
}

bool _usesFirebase(String content) {
  return content.contains('FirebaseFirestore') ||
      content.contains('FirebaseAuth') ||
      content.contains('FirebaseStorage') ||
      content.contains('cloud_firestore') ||
      content.contains('firebase_auth') ||
      content.contains('firebase_storage');
}

/// واجهات بيانات تحتاج عادةً Stream/Future (وليس نماذج تسجيل الدخول فقط).
bool _usesFirestore(String content) {
  return content.contains('FirebaseFirestore') ||
      content.contains('FirebaseStorage') ||
      content.contains('cloud_firestore') ||
      content.contains('firebase_storage');
}

bool _usesProviderState(String content) {
  return content.contains('Provider<') ||
      content.contains('Consumer<') ||
      content.contains('context.watch<') ||
      content.contains('context.read<') ||
      content.contains('Selector<');
}

List<String> _mockDataHeuristics(
  String content,
  bool usesFirestore,
  bool usesStream,
  bool usesFuture,
) {
  final issues = <String>[];
  final hasListViewBuilder = content.contains('ListView.builder');
  final hasAsyncBuilder = usesStream || usesFuture;

  if (hasListViewBuilder && !hasAsyncBuilder) {
    issues.add(
      'ListView.builder without StreamBuilder/FutureBuilder in file (possible static/mock list)',
    );
  }

  if (content.contains('snapshot.hasData') &&
      !usesFirestore &&
      !content.contains('FirebaseFirestore') &&
      !content.contains('cloud_firestore')) {
    issues.add('snapshot.hasData present but no Firestore API in file (verify data source)');
  }

  // ListView( ... children: [ — بدون itemBuilder
  if (RegExp(r'ListView\s*\(\s*[^\)]*children\s*:').hasMatch(content) &&
      !content.contains('itemBuilder')) {
    issues.add('ListView with children: instead of itemBuilder (possible static list)');
  }

  return issues;
}

void _findEmptyButtons(
  List<String> lines,
  String fileRel,
  List<Map<String, dynamic>> out,
) {
  final patterns = <(RegExp, String)>[
    (RegExp(r'onPressed:\s*null\b'), 'onPressed: null'),
    (RegExp(r'onTap:\s*null\b'), 'onTap: null'),
    (RegExp(r'onPressed:\s*\(\)\s*\{\s*\}'), 'onPressed: () {}'),
    (RegExp(r'onTap:\s*\(\)\s*\{\s*\}'), 'onTap: () {}'),
    (RegExp(r'onPressed:\s*\(\)\s*=>\s*\{\s*\}'), 'onPressed: () => {}'),
    (RegExp(r'onTap:\s*\(\)\s*=>\s*\{\s*\}'), 'onTap: () => {}'),
  ];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    for (final pair in patterns) {
      if (pair.$1.hasMatch(line)) {
        final widgetGuess = _guessWidgetName(lines, i);
        final textGuess = _guessButtonText(lines, i);
        out.add({
          'file': fileRel.replaceAll('\\', '/'),
          'line': i + 1,
          'widget': widgetGuess,
          'text': textGuess,
          'kind': pair.$2,
        });
      }
    }
  }
}

String _guessWidgetName(List<String> lines, int idx) {
  for (var j = idx; j >= 0 && j > idx - 12; j--) {
    final l = lines[j];
    final m = RegExp(r'^\s*(ElevatedButton|TextButton|OutlinedButton|IconButton|InkWell|GestureDetector|FloatingActionButton)\s*\(')
        .firstMatch(l);
    if (m != null) return m.group(1)!;
  }
  return 'unknown';
}

String _guessButtonText(List<String> lines, int idx) {
  final buf = StringBuffer();
  for (var j = idx; j >= idx - 8 && j >= 0; j--) {
    final l = lines[j];
    var tm = RegExp(r"Text\s*\(\s*'([^']+)'").firstMatch(l);
    tm ??= RegExp(r'Text\s*\(\s*"([^"]+)"').firstMatch(l);
    if (tm != null) {
      buf.write(tm.group(1));
      break;
    }
    final tc = RegExp(r'Text\s*\(\s*context\.l10n\.(\w+)').firstMatch(l);
    if (tc != null) {
      buf.write(tc.group(1));
      break;
    }
  }
  final s = buf.toString();
  return s.isEmpty ? '' : s;
}
