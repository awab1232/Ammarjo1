import 'dart:convert';

import 'package:http/http.dart' as http;

/// فك JSON من استجابة HTTP بترميز UTF-8 (أسماء عربية من WordPress / WooCommerce).
dynamic jsonDecodeUtf8Response(http.Response response) {
  try {
    return jsonDecode(utf8.decode(response.bodyBytes));
  } on Object {
    throw StateError('INVALID_JSON');
  }
}
