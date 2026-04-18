const List<String> kJordanRegions = <String>[
  'عمّان',
  'إربد',
  'الزرقاء',
  'البلقاء',
  'مادبا',
  'العقبة',
  'الكرك',
  'معان',
  'الطفيلة',
  'جرش',
  'عجلون',
  'المفرق',
];

/// يطابق نص المدينة المحفوظ مع إحدى محافظات [kJordanRegions] (تشذيب + حالة أحرف لاتينية).
String? matchJordanRegion(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  for (final r in kJordanRegions) {
    if (r == t) return r;
    if (r.toLowerCase() == t.toLowerCase()) return r;
  }
  return null;
}
