/// رقم أردني: 9 أرقام تبدأ بـ 7 (مثلاً 791234567) → اسم مستخدم للـ API: `962791234567`.
String normalizeJordanPhoneForUsername(String input) {
  final d = input.replaceAll(RegExp(r'\D'), '');
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
