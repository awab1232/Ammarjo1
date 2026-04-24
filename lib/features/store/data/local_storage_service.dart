import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models.dart';
import '../domain/saved_checkout_info.dart';

typedef CartItemList = List<CartItem>;
typedef StringList = List<String>;

class LocalStorageService {
  static const _savedCheckoutKey = 'ammarjo_saved_checkout_v1';
  static const _cartKey = 'woo_cart_items_v1';
  static const _recentSearchesKey = 'store_recent_searches_v1';
  static const _favoritesKey = 'woo_favorite_ids_v1';
  static const _tokenKey = 'woo_auth_token_v1';
  static const _emailKey = 'woo_auth_email_v1';
  static const _nameKey = 'woo_auth_name_v1';
  static const _profileJsonKey = 'ammarjo_customer_profile_json_v2';
  static const _localBypassSessionKey = 'ammarjo_local_bypass_session_v1';

  String _loyaltyKey(String email) => 'woo_loyalty_pts_v1_$email';

  Future<int> loyaltyPointsForEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_loyaltyKey(email)) ?? 0;
  }

  Future<void> saveCart(List<CartItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = items.map((e) => e.toJson()).toList();
    await prefs.setString(_cartKey, jsonEncode(payload));
  }

  Future<void> saveFavoriteIds(Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_favoritesKey, jsonEncode(ids.toList()));
  }

  Future<Set<int>> getFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_favoritesKey);
    if (raw == null || raw.isEmpty) return <int>{};
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => e as int).toSet();
  }

  Future<CartItemList> getCart() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cartKey);
    if (raw == null || raw.isEmpty) throw StateError('EMPTY_RESPONSE');
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => CartItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveProfile(CustomerProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileJsonKey, jsonEncode(profile.toJson()));
    await prefs.setString(_emailKey, profile.email);
    await prefs.setString(_tokenKey, profile.token ?? '');
    await prefs.setString(_nameKey, profile.fullName ?? '');
    await prefs.setInt(_loyaltyKey(profile.email), profile.loyaltyPoints);
  }

  Future<CustomerProfile?> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonRaw = prefs.getString(_profileJsonKey);
    if (jsonRaw != null && jsonRaw.isNotEmpty) {
      try {
        final j = jsonDecode(jsonRaw) as Map<String, dynamic>;
        final p = CustomerProfile.fromJson(j);
        final pts = prefs.getInt(_loyaltyKey(p.email)) ?? 0;
        return p.copyWith(loyaltyPoints: pts);
      } on Object {
        throw StateError('INVALID_PROFILE_CACHE');
      }
    }
    final email = prefs.getString(_emailKey);
    if (email == null || email.isEmpty) return null;
    final pts = prefs.getInt(_loyaltyKey(email)) ?? 0;
    return CustomerProfile(
      email: email,
      token: prefs.getString(_tokenKey),
      fullName: prefs.getString(_nameKey),
      loyaltyPoints: pts,
    );
  }

  Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileJsonKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_localBypassSessionKey);
  }

  /// جلسة «دخول محلي» بدون Firebase Auth — لا تستدعِ [syncChatFirebaseIdentity] حتى لا يُستدعَى ensureFirebaseUser.
  Future<void> setLocalBypassSession(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      await prefs.setBool(_localBypassSessionKey, true);
    } else {
      await prefs.remove(_localBypassSessionKey);
    }
  }

  Future<bool> getLocalBypassSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_localBypassSessionKey) ?? false;
  }

  Future<StringList> getRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentSearchesKey);
    if (raw == null || raw.isEmpty) throw StateError('EMPTY_RESPONSE');
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => 'unexpected error').toList();
    } on Object {
      throw StateError('unexpected_empty_response');
    }
  }

  Future<void> addRecentSearch(String query) async {
    var q = query.trim();
    if (q.length < 2) return;
    final prefs = await SharedPreferences.getInstance();
    var list = await getRecentSearches();
    list = list.where((e) => e.toLowerCase() != q.toLowerCase()).toList();
    list.insert(0, q);
    if (list.length > 14) {
      list = list.sublist(0, 14);
    }
    await prefs.setString(_recentSearchesKey, jsonEncode(list));
  }

  Future<void> removeRecentSearch(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (await getRecentSearches()).where((e) => e != query).toList();
    await prefs.setString(_recentSearchesKey, jsonEncode(list));
  }

  Future<void> clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentSearchesKey);
  }

  Future<SavedCheckoutInfo?> getSavedCheckoutInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedCheckoutKey);
    if (raw == null || raw.isEmpty) throw StateError('unexpected_empty_response');
    try {
      final d = jsonDecode(raw) as Map<String, dynamic>;
      return SavedCheckoutInfo.fromJson(d);
    } on Object {
      throw StateError('unexpected_empty_response');
    }
  }

  Future<void> saveSavedCheckoutInfo(SavedCheckoutInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedCheckoutKey, jsonEncode(info.toJson()));
  }

  Future<void> clearSavedCheckoutInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedCheckoutKey);
  }
}
