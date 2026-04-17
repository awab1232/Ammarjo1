import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/contracts/feature_state.dart';
import '../data/wholesale_repository.dart';

class WholesaleCartItem {
  const WholesaleCartItem({
    required this.wholesalerId,
    required this.wholesalerName,
    required this.productId,
    required this.productName,
    required this.imageUrl,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
  });

  final String wholesalerId;
  final String wholesalerName;
  final String productId;
  final String productName;
  final String imageUrl;
  final String unit;
  final int quantity;
  final double unitPrice;

  double get total => unitPrice * quantity;

  WholesaleCartItem copyWith({int? quantity, double? unitPrice}) {
    return WholesaleCartItem(
      wholesalerId: wholesalerId,
      wholesalerName: wholesalerName,
      productId: productId,
      productName: productName,
      imageUrl: imageUrl,
      unit: unit,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'wholesalerId': wholesalerId,
        'wholesalerName': wholesalerName,
        'productId': productId,
        'productName': productName,
        'imageUrl': imageUrl,
        'unit': unit,
        'quantity': quantity,
        'unitPrice': unitPrice,
      };

  factory WholesaleCartItem.fromJson(Map<String, dynamic> json) {
    final q = json['quantity'];
    final p = json['unitPrice'];
    return WholesaleCartItem(
      wholesalerId: (json['wholesalerId'] ?? '').toString(),
      wholesalerName: (json['wholesalerName'] ?? '').toString(),
      productId: (json['productId'] ?? '').toString(),
      productName: (json['productName'] ?? '').toString(),
      imageUrl: (json['imageUrl'] ?? '').toString(),
      unit: (json['unit'] ?? '').toString(),
      quantity: q is num ? q.toInt() : int.tryParse(q?.toString() ?? '') ?? 1,
      unitPrice: p is num ? p.toDouble() : double.tryParse(p?.toString() ?? '') ?? 0.0,
    );
  }
}

class WholesaleCartStorage {
  static const String _key = 'wholesale_cart_v1';

  static Future<FeatureState<List<WholesaleCartItem>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return FeatureState.failure('Wholesale cart is empty.');
    final list = jsonDecode(raw) as List<dynamic>;
    return FeatureState.success(
      list.map((e) => WholesaleCartItem.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  static Future<void> save(List<WholesaleCartItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Ø­ÙØ¸ Ù…Ø­Ù„ÙŠ (Ø§Ù„Ø§Ø³Ù… Ø§Ù„ØµØ±ÙŠØ­ Ù„Ù„ØªÙˆØ§ÙÙ‚ Ù…Ø¹ Ø§Ù„Ù…Ø·Ù„ÙˆØ¨).
  static Future<void> saveCartLocally(List<WholesaleCartItem> items) => save(items);

  /// Ø±ÙØ¹ Ø§Ù„Ø³Ù„Ø© Ø¥Ù„Ù‰ Ø§Ù„Ø³Ø­Ø§Ø¨Ø© (Ø§Ø®ØªÙŠØ§Ø±ÙŠ).
  static Future<void> syncCartWithFirestore(String userId, List<WholesaleCartItem> items) async {
    if (Firebase.apps.isEmpty) return;
    final uid = userId.trim();
    if (uid.isEmpty) return;
    try {
      await WholesaleRepository.instance.syncWholesaleCartCloud(uid, items.map((e) => e.toJson()).toList());
    } on Object {
      debugPrint('[WholesaleCartStorage] syncCartWithFirestore failed.');
      rethrow;
    }
  }

  /// Ø§Ø³ØªØ¹Ø§Ø¯Ø© Ø§Ù„Ø³Ù„Ø© Ù…Ù† Ø§Ù„Ø³Ø­Ø§Ø¨Ø© Ø¹Ù†Ø¯ ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„.
  static Future<FeatureState<List<WholesaleCartItem>>> loadCartFromFirestore(String userId) async {
    if (Firebase.apps.isEmpty) return FeatureState.failure('Firebase is not initialized.');
    final uid = userId.trim();
    if (uid.isEmpty) return FeatureState.failure('User id is required for cart sync.');
    try {
      final mapsState = await WholesaleRepository.instance.loadWholesaleCartItemsFromCloud(uid);
      final maps = switch (mapsState) {
        FeatureSuccess(:final data) => data,
        _ => <Map<String, dynamic>>[],
      };
      return FeatureState.success(maps.map(WholesaleCartItem.fromJson).toList());
    } on Object {
      debugPrint('[WholesaleCartStorage] loadCartFromFirestore failed.');
      return FeatureState.failure('Failed to load cart from cloud.');
    }
  }

  /// Ù…Ø³Ø­ Ù†Ø³Ø®Ø© Ø§Ù„Ø³Ø­Ø§Ø¨Ø© (Ø¨Ø¹Ø¯ Ø¥ØªÙ…Ø§Ù… Ø§Ù„Ø·Ù„Ø¨ Ø£Ùˆ ÙŠØ¯ÙˆÙŠØ§Ù‹).
  static Future<void> clearFirestoreCart(String userId) async {
    if (Firebase.apps.isEmpty) return;
    await WholesaleRepository.instance.clearWholesaleCartCloud(userId);
  }
}

