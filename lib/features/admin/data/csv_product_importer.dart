// ignore_for_file: avoid_print — استيراد CSV يتطلب طباعة نجاح لكل صف

import 'package:csv/csv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'backend_admin_client.dart';

/// خطأ عام أثناء الاستيراد (قبل/بعد الحلقة).
class CsvProductImportException implements Exception {
  CsvProductImportException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'CsvImport: $message${cause != null ? ' — $cause' : ''}';
}

/// نتيجة التحقق من CSV (لا يُكتب كتالوج من التطبيق — يُسجَّل ملخص في الخادم فقط).
class CsvProductImportResult {
  CsvProductImportResult({
    required this.productsWritten,
    required this.rowsSkipped,
    this.warnings = const [],
  });

  /// عدد الصفوف الصالحة التي تم التحقق منها (معادل سابقاً لعدد المنتجات المكتوبة في Firestore).
  final int productsWritten;
  final int rowsSkipped;
  final List<String> warnings;
}

/// تقدم الاستيراد لـ UI — استخدم مع [ListenableBuilder].
class CsvImportProgress extends ChangeNotifier {
  CsvImportProgress();

  int uploaded = 0;
  int total = 0;

  void reset({required int totalRows}) {
    uploaded = 0;
    total = totalRows;
    notifyListeners();
  }

  void incrementUploaded() {
    uploaded++;
    notifyListeners();
  }

  String get label => total > 0 ? '$uploaded of $total products uploaded' : '$uploaded products uploaded';
}

/// تحليل CSV والتحقق من الصفوف — تسجيل ملخص في `admin_migration_status` عبر REST.
final class CsvProductImporter {
  CsvProductImporter._();

  static const int _colName = 0;
  static const int _colPrice = 2;
  static const int _colImageFile = 4;

  static const CsvToListConverter _converter = CsvToListConverter(
    eol: '\n',
    shouldParseNumbers: false,
  );

  static String _safe(dynamic v) {
    if (v == null) return '';
    try {
      return v.toString().trim();
    } on Object {
      return '';
    }
  }

  /// رابط تنزيل عام لملف في Firebase Storage (مجلد `products/`).
  static String storageImageUrlForFileName(String fileName) {
    final name = fileName.trim();
    if (name.isEmpty) return '';
    if (!Firebase.apps.isNotEmpty) return '';
    final app = Firebase.app();
    final opts = app.options;
    final bucket = (opts.storageBucket != null && opts.storageBucket!.isNotEmpty)
        ? opts.storageBucket!
        : '${opts.projectId}.appspot.com';
    final objectPath = 'products/$name';
    final encoded = Uri.encodeComponent(objectPath);
    return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$encoded?alt=media';
  }

  static Future<void> _patchMigrationSummary({
    required int validatedRows,
    required int skipped,
  }) async {
    final cur = await BackendAdminClient.instance.fetchMigrationStatus();
    final existing = cur?['payload'];
    final merged = <String, dynamic>{
      if (existing is Map<String, dynamic>) ...existing,
      'phase': 'csv_validated',
      'csvValidatedRows': validatedRows,
      'csvSkippedRows': skipped,
      'csvValidatedAt': DateTime.now().toUtc().toIso8601String(),
      'note': 'CSV analyzed in admin app; catalog writes are server-side only.',
    };
    final res = await BackendAdminClient.instance.patchMigrationStatus(merged);
    if (res == null) throw StateError('تعذر حفظ ملخص CSV في الخادم');
  }

  static Future<CsvProductImportResult> importFromCsvString(
    String csvText, {
    void Function(String message)? onProgress,
    CsvImportProgress? progress,
  }) async {
    if (!Firebase.apps.isNotEmpty) {
      throw CsvProductImportException('Firebase غير مهيأ');
    }

    final normalized = csvText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    List<List<dynamic>> rows;
    try {
      rows = _converter.convert(normalized);
    } on Object {
      print('[CsvImport] فشل تحليل CSV');
      throw CsvProductImportException('تعذر تحليل CSV');
    }

    return importFromParsedRows(
      rows,
      onProgress: onProgress,
      progress: progress,
    );
  }

  static Future<CsvProductImportResult> importFromParsedRows(
    List<List<dynamic>> rows, {
    void Function(String message)? onProgress,
    CsvImportProgress? progress,
  }) async {
    if (!Firebase.apps.isNotEmpty) {
      throw CsvProductImportException('Firebase غير مهيأ');
    }
    print('CSV Rows found: ${rows.length}');

    if (rows.isEmpty) {
      throw CsvProductImportException('CSV فارغ');
    }

    final dataRowCount = rows.length - 1;
    progress?.reset(totalRows: dataRowCount > 0 ? dataRowCount : 0);
    onProgress?.call(progress?.label ?? '0 of 0 products uploaded');

    var validated = 0;
    var skipped = 0;
    final warnings = <String>[];

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      try {
        if (row.length <= _colImageFile) {
          skipped++;
          warnings.add('سطر ${i + 1}: أعمدة أقل من ${_colImageFile + 1}');
          continue;
        }

        final name = _safe(row[_colName]);
        if (name.isEmpty) {
          skipped++;
          continue;
        }

        final priceNum = double.tryParse(row[_colPrice].toString()) ?? 0.0;
        if (priceNum < 0) {
          skipped++;
          warnings.add('سطر ${i + 1}: سعر غير صالح');
          continue;
        }

        validated++;
        progress?.incrementUploaded();
        onProgress?.call(progress?.label ?? '$validated validated');
        print('OK row: ${row[_colName]}');
      } on Object {
        skipped++;
        warnings.add('سطر ${i + 1}: خطأ غير متوقع');
        print('[CsvImport] Row $i skipped');
      }
    }

    await _patchMigrationSummary(validatedRows: validated, skipped: skipped);

    return CsvProductImportResult(
      productsWritten: validated,
      rowsSkipped: skipped,
      warnings: warnings,
    );
  }

  static String priceStrForDouble(double v) {
    final s = v.toStringAsFixed(2);
    return s.replaceAll(RegExp(r'\.?0+$'), '');
  }
}

abstract final class CsvImportService {
  static Future<CsvProductImportResult> importFromCsvString(
    String csvText, {
    void Function(String message)? onProgress,
    CsvImportProgress? progress,
  }) =>
      CsvProductImporter.importFromCsvString(csvText, onProgress: onProgress, progress: progress);

  static Future<CsvProductImportResult> importFromParsedRows(
    List<List<dynamic>> rows, {
    void Function(String message)? onProgress,
    CsvImportProgress? progress,
  }) =>
      CsvProductImporter.importFromParsedRows(rows, onProgress: onProgress, progress: progress);
}
