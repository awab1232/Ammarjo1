class SeoIndexingHooks {
  static bool _started = false;

  static void start() {
    _started = true;
  }

  static Future<void> stop() async {
    if (!_started) return;
    _started = false;
  }
}
