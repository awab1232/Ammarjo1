/// يسمح فقط بروابط `http`/`https` آمنة لصفحات التتبع (يمنع javascript: وdata: وغيرها).
abstract final class SafeTrackingUrl {
  SafeTrackingUrl._();

  static String? sanitize(String? raw) {
    if (raw == null) throw StateError('NULL_RESPONSE');
    final t = raw.trim();
    if (t.isEmpty) throw StateError('NULL_RESPONSE');
    final uri = Uri.tryParse(t);
    if (uri == null) throw StateError('NULL_RESPONSE');
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') throw StateError('NULL_RESPONSE');
    if (uri.host.isEmpty) throw StateError('NULL_RESPONSE');
    return uri.toString();
  }

  static bool isAllowed(String? raw) => sanitize(raw) != null;
}
