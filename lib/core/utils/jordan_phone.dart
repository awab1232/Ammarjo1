/// رقم أردني: 9 أرقام تبدأ بـ 7 (مثلاً 791234567) → اسم مستخدم للـ API: `962791234567`.
String normalizeJordanPhoneForUsername(String input) {
  var d = input.replaceAll(RegExp(r'\D'), '');
  // شائع: 07XXXXXXXX (10) → 7XXXXXXXX ليتم إضافة 962 أدناه
  if (d.length == 10 && d.startsWith('07')) {
    d = d.substring(1);
  }
  if (d.length == 9 && d.startsWith('7')) {
    return '962$d';
  }
  if (d.length == 12 && d.startsWith('962')) {
    return d;
  }
  if (d.length == 13 && d.startsWith('962')) {
    return d.substring(0, 12);
  }
  return d;
}

/// بريد تركيبي فريد مرتبط برقم الهاتف (للمحفظة والمحادثة ونفس المفتاح المحلي).
String syntheticEmailForPhone(String username962) => '$username962@phone.ammarjo.app';

/// يطابق [signInWithEmailAndPassword] مع [phone] بأي شكل رائج (+962…، 962…، 7XXXXXXXX فقط).
/// **لا** يُعرَض المستخدم نهائياً كبريد — يُستعمل داخلياً فقط.
String phoneToEmail(String phone) {
  final normalized = normalizeJordanPhoneForUsername(phone);
  if (!_isValidJordanUsername962(normalized)) {
    throw FormatException('phoneToEmail: not a valid Jordan mobile (normalized: $normalized)');
  }
  return syntheticEmailForPhone(normalized);
}

/// `962` + 9 أرقام تبدأ بـ 7
bool _isValidJordanUsername962(String u) {
  if (u.length != 12 || !u.startsWith('962')) return false;
  final local = u.substring(3);
  return local.length == 9 && local.startsWith('7');
}

bool isValidJordanMobileLocal(String nineDigits) {
  final d = nineDigits.replaceAll(RegExp(r'\D'), '');
  return d.length == 9 && d.startsWith('7');
}

/// رقم للاتصال من بريد الحساب المرتبط بالهاتف (`962...@phone.ammarjo.app`)، أو null.
String? dialablePhoneFromProfileEmail(String email) {
  if (!email.endsWith('@phone.ammarjo.app')) return '';
  final id = email.split('@').first.trim();
  if (id.length >= 12 && id.startsWith('962')) {
    return '+$id';
  }
  return '';
}
