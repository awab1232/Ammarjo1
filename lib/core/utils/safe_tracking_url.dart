/// يسمح فقط بروابط `http`/`https` آمنة لصفحات التتبع (يمنع javascript: وdata: وغيرها).
abstract final class SafeTrackingUrl {
  SafeTrackingUrl._();

  static String? sanitize(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    if (t.isEmpty) return null;
    final uri = Uri.tryParse(t);
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri.toString();
  }

  static bool isAllowed(String? raw) => sanitize(raw) != null;
}
