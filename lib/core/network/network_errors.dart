import 'dart:io';

import 'package:http/http.dart' as http;

/// رسالة عربية عند فقدان الشبكة أو فشل الاتصال.
String networkUserMessage(Object error) {
  if (error is SocketException) {
    return 'لا يوجد اتصال بالإنترنت. تحقق من الشبكة ثم أعد المحاولة.';
  }
  if (error is http.ClientException) {
    return 'تعذر الاتصال بالخادم. تحقق من الإنترنت.';
  }
  if (error is HandshakeException || error is TlsException) {
    return 'تعذر إنشاء اتصال آمن. تحقق من التاريخ والوقت أو الشبكة.';
  }
  return '';
}
