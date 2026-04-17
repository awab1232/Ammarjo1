// يُشغَّل من جذر المشروع: dart run tool/process_app_icon.dart
// يقص الخلفية الرمادية/الفاتحة ويُصدّر 1024×1024 لـ flutter_launcher_icons.

import 'dart:io';

import 'package:image/image.dart';

/// خلفية الصورة (رمادي فاتح حول الأيقونة) — نعتبرها ليست جزءاً من المحتوى.
bool _isBackground(int r, int g, int b) {
  final avg = (r + g + b) / 3.0;
  final spread = (r - avg).abs() + (g - avg).abs() + (b - avg).abs();
  // أوسع قليلاً لاعتبار إطار أبيض/رمادي فاتح حول الشعار كخلفية وقصّه.
  return avg > 195 && spread < 55;
}

/// اختياري: `dart run tool/process_app_icon.dart "C:\مسار\صورة.png"`
void main(List<String> args) {
  final root = Directory.current.path;
  final inputPath = args.isNotEmpty ? args.first.trim() : '$root/assets/logo/source_icon.png';
  final input = File(inputPath);
  if (!input.existsSync()) {
    stderr.writeln(
      'Missing: ${input.path}\n'
      'ضع صورة الأيقونة كـ assets/logo/source_icon.png أو مرّر المسار كوسيط.',
    );
    exit(1);
  }

  final raw = input.readAsBytesSync();
  final decoded = decodeImage(raw);
  if (decoded == null) {
    stderr.writeln('تعذر فك ترميز PNG');
    exit(1);
  }

  var image = decoded;

  var minX = image.width;
  var minY = image.height;
  var maxX = 0;
  var maxY = 0;

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final p = image.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      if (!_isBackground(r, g, b)) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX < minX || maxY < minY) {
    stderr.writeln('لم يُعثر على محتوى بعد الخلفية — استخدم صورة بخلفية أوضح.');
    exit(1);
  }

  const pad = 2;
  minX = (minX - pad).clamp(0, image.width - 1);
  minY = (minY - pad).clamp(0, image.height - 1);
  maxX = (maxX + pad).clamp(0, image.width - 1);
  maxY = (maxY + pad).clamp(0, image.height - 1);

  final w = maxX - minX + 1;
  final h = maxY - minY + 1;
  final maxSide = image.width < image.height ? image.width : image.height;
  var side = w > h ? w : h;
  if (side > maxSide) side = maxSide;
  final cx = minX + w ~/ 2;
  final cy = minY + h ~/ 2;
  final left = (cx - side ~/ 2).clamp(0, image.width - side);
  final top = (cy - side ~/ 2).clamp(0, image.height - side);

  var square = copyCrop(
    image,
    x: left,
    y: top,
    width: side,
    height: side,
  );

  const outSize = 1024;
  square = copyResize(
    square,
    width: outSize,
    height: outSize,
    interpolation: Interpolation.cubic,
  );

  // تعزيز بسيط للتباين (إبراز احترافي خفيف)
  square = adjustColor(square, contrast: 1.06, saturation: 1.08);

  final outDir = Directory('$root/assets/logo');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  final iconPath = '$root/assets/logo/icon.png';
  final fgPath = '$root/assets/logo/icon_foreground.png';
  File(iconPath).writeAsBytesSync(encodePng(square));
  File(fgPath).writeAsBytesSync(encodePng(square));

  stdout.writeln('OK: $iconPath + $fgPath (${square.width}×${square.height})');
}
