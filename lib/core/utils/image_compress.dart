import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// ضغط صور قبل الرفع إلى Storage (جودة وحجم أقصى).
Future<Uint8List> compressImageBytes(Uint8List bytes, {int quality = 85, int minWidth = 800}) async {
  try {
    final out = await FlutterImageCompress.compressWithList(
      bytes,
      quality: quality,
      minWidth: minWidth,
      minHeight: minWidth,
    );
    if (out.isNotEmpty) return Uint8List.fromList(out);
  } on Object {
    return bytes;
  }
  return bytes;
}
