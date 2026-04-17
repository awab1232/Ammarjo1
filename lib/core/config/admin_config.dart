/// بريد احتياطي (إن وُجد في وثيقة `users/{uid}`).
const Set<String> kAdminEmails = {
  'awabaloran@gmail.com',
};

/// رقم المسؤول الأعلى (أردن، بصيغة أرقام فقط `9627XXXXXXXX`) — يُمنح دور admin دائماً.
const String kHardcodedAdminJordanPhoneDigits = '962777983482';

/// يطابق [User.phoneNumber] بعد التطبيع (مثل `+962777983482` → `962777983482`).
bool isHardcodedAdminPhoneNumber(String? phoneE164OrDigits) {
  final raw = (phoneE164OrDigits ?? '').replaceAll(RegExp(r'\D'), '');
  if (raw.isEmpty) return false;
  var d = raw;
  if (d.startsWith('00')) d = d.substring(2);
  if (d.length == 9 && d.startsWith('7')) {
    d = '962$d';
  }
  return d == kHardcodedAdminJordanPhoneDigits;
}

/// معرّفات **Firebase Auth UID** للمسؤولين (من Console → Authentication → Users).
/// ضع UID الحساب الإداري هنا حتى تظهر «لوحة التحكم» حتى لو لم تُضبط وثيقة `users/{uid}`.
const List<String> kHardcodedAdminUids = [
  'btzpO5w4OVZiYZEctyxe3GJPke',
];

bool isHardcodedAdminUid(String? uid) {
  final u = (uid ?? '').trim();
  if (u.isEmpty) return false;
  return kHardcodedAdminUids.contains(u);
}

bool isStaticAdminEmail(String? email) {
  final e = (email ?? '').trim().toLowerCase();
  if (e.isEmpty) return false;
  return kAdminEmails.contains(e);
}
