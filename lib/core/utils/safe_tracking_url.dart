/// يسمح فقط بروابط `http`/`https` آمنة لصفحات التتبع (يمنع javascript: وdata: وغيرها).
abstract final class SafeTrackingUrl {
  SafeTrackingUrl._();

  static String? sanitize(String? raw) {
    if (raw == null) throw StateError('unexpected_empty_response');
    final t = raw.trim();
    if (t.isEmpty) throw StateError('unexpected_empty_response');
    final uri = Uri.tryParse(t);
    if (uri == null) throw StateError('unexpected_empty_response');
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') throw StateError('unexpected_empty_response');
    if (uri.host.isEmpty) throw StateError('unexpected_empty_response');
    return uri.toString();
  }

  static bool isAllowed(String? raw) => sanitize(raw) != null;
}
