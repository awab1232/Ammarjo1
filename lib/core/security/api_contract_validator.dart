import 'package:flutter/foundation.dart' show debugPrint;

/// Lightweight checks for JSON maps from the HTTP backend.
/// Returns `false` and logs on mismatch — does **not** throw (production stability).
abstract final class ApiContractValidator {
  static bool validateOrderMap(Map<String, dynamic>? m, {String context = 'Order'}) {
    if (m == null) {
      debugPrint('[ApiContractValidator] mismatch: $context is null');
      return false;
    }
    final id = m['id'] ?? m['orderId'];
    if (id == null || '$id'.trim().isEmpty) {
      debugPrint('[ApiContractValidator] order map keys: ${m.keys.toList()}');
      return false;
    }
    return true;
  }

  static bool validateProductMap(Map<String, dynamic>? m, {String context = 'Product'}) {
    if (m == null) {
      debugPrint('[ApiContractValidator] mismatch: $context is null');
      return false;
    }
    if ((m['name']?.toString().trim().isEmpty ?? true) &&
        (m['productCode']?.toString().trim().isEmpty ?? true)) {
      return false;
    }
    return true;
  }

  static bool validateStoreMap(Map<String, dynamic>? m, {String context = 'Store'}) {
    if (m == null) {
      debugPrint('[ApiContractValidator] mismatch: $context is null');
      return false;
    }
    if (m['id'] == null || m['id'].toString().trim().isEmpty) {
      return false;
    }
    return true;
  }

  static bool validateUserMap(Map<String, dynamic>? m, {String context = 'User'}) {
    if (m == null) {
      debugPrint('[ApiContractValidator] mismatch: $context is null');
      return false;
    }
    if ((m['id'] ?? m['uid']) == null) {
      return false;
    }
    return true;
  }

  static bool validateCouponMap(Map<String, dynamic>? m, {String context = 'Coupon'}) {
    if (m == null) {
      debugPrint('[ApiContractValidator] mismatch: $context is null');
      return false;
    }
    if ((m['code']?.toString().trim().isEmpty ?? true) &&
        (m['id'] == null || m['id'].toString().trim().isEmpty)) {
      return false;
    }
    return true;
  }
}
