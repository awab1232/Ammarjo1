class OrganicTrafficSystem {
  OrganicTrafficSystem._();
  static final OrganicTrafficSystem instance = OrganicTrafficSystem._();

  bool _started = false;

  void start() {
    _started = true;
  }

  Future<void> stop() async {
    _started = false;
  }

  void recordImpression({required String path}) {
    if (!_started) return;
  }
}
