import 'package:shared_preferences/shared_preferences.dart';

abstract final class NotificationPreferences {
  static const String keyOrders = 'notif_orders';
  static const String keyTenders = 'notif_tenders';
  static const String keyOffers = 'notif_offers';
  static const String keySupport = 'notif_support';
  static const String keyDelivery = 'notif_delivery';

  static const Map<String, bool> defaults = <String, bool>{
    keyOrders: true,
    keyTenders: true,
    keyOffers: true,
    keySupport: true,
    keyDelivery: true,
  };

  static Future<bool> getBool(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? (defaults[key] ?? true);
  }

  static Future<void> setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  static Future<bool> allowsNotificationType(String typeRaw) async {
    final type = typeRaw.trim().toLowerCase();
    if (type.contains('order') || type.contains('status')) {
      return getBool(keyOrders);
    }
    if (type.contains('tender')) {
      return getBool(keyTenders);
    }
    if (type.contains('offer')) {
      return getBool(keyOffers);
    }
    if (type.contains('message') || type.contains('support')) {
      return getBool(keySupport);
    }
    if (type.contains('delivery') || type.contains('driver')) {
      return getBool(keyDelivery);
    }
    return true;
  }
}
