/// Demo seeding is backend-owned after Firestore shutdown.
class DemoDataSeeder {
  DemoDataSeeder._();

  static Future<void> seedAll() async {
    // Intentionally no-op in mobile app.
    return;
  }
}
