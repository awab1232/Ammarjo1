/// Local chat notification bridge is disabled until backend push events are fully wired.
abstract final class LocalChatNotificationService {
  static Future<void> init() async {}

  static void bindAuthState() {}
}
