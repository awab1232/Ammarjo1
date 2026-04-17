// استيراد منتجات من ملف CSV إلى Firestore.
//
// الاستخدام من جذر المشروع:
//   dart run tool/import_products_csv.dart path/to/products.csv
//
// يتطلب تسجيل الدخول/تهيئة Firebase المناسبة لمنصة التشغيل (نفس مشروع التطبيق).

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:ammar_store/features/admin/data/csv_product_importer.dart';
import 'package:ammar_store/firebase_options.dart';

Future<void> main(List<String> args) async {
  final path = args.isNotEmpty ? args[0] : 'products.csv';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('لم يُعثر على الملف: $path');
    exit(1);
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final text = file.readAsStringSync();
  final result = await CsvProductImporter.importFromCsvString(text, onProgress: stdout.writeln);
  stdout.writeln('— تم — منتجات مكتوبة: ${result.productsWritten}، صفوف متخطاة: ${result.rowsSkipped}');
  final w = result.warnings;
  if (w.isNotEmpty) {
    stdout.writeln('— تحذيرات (أول ${w.length > 30 ? 30 : w.length}) —');
    for (final e in w.take(30)) {
      stdout.writeln('  • $e');
    }
  }
}
