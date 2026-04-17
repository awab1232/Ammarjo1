import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// مشاركة ملف CSV (Android / iOS / سطح المكتب).
Future<void> shareOrderCsvExport(String csv, String fileName) async {
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/$fileName';
  final file = File(path);
  await file.writeAsString(csv, encoding: utf8);
  await Share.shareXFiles(
    [XFile(path, mimeType: 'text/csv', name: fileName)],
    subject: fileName,
  );
}
