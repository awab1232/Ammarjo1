/// تطبيع نص عربي للمطابقة في البحث (أ/إ/آ، ى/ي، ة، تشكيل…).
String normalizeArabicForSearch(String input) {
  var s = input.trim().toLowerCase();
  // إزالة التشكيل
  s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
  const replacements = <String, String>{
    'أ': 'ا',
    'إ': 'ا',
    'آ': 'ا',
    'ٱ': 'ا',
    'ى': 'ي',
    'ة': 'ه',
    'ؤ': 'و',
    'ئ': 'ي',
  };
  for (final e in replacements.entries) {
    s = s.replaceAll(e.key, e.value);
  }
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// إزالة وسوم HTML من وصف ووكومرس للفهرسة النصية.
String stripHtmlForSearch(String? html) {
  if (html == null || html.isEmpty) return '';
  return html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
