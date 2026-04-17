import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Silent parity check: Firebase root order map vs backend `order` map (no UI impact).
abstract final class BackendOrderReadValidator {
  static const double _eps = 0.001;

  static void logMismatchIfAny(
    String orderId,
    Map<String, dynamic> firebase,
    Map<String, dynamic> backendOrder,
  ) {
    if (!kDebugMode) return;
    final mismatches = collectMismatches(firebase, backendOrder);
    if (mismatches.isEmpty) return;
    debugPrint(
      '[BackendOrderReadValidator] orderId=$orderId ${mismatches.join('; ')}',
    );
  }

  static List<String> collectMismatches(
    Map<String, dynamic> firebase,
    Map<String, dynamic> backendOrder,
  ) {
    final mismatches = <String>[];

    final fbTotal = _toDouble(firebase['totalNumeric']);
    final beTotal = _toDouble(backendOrder['totalNumeric']);
    if (!fbTotal.isNaN && !beTotal.isNaN && !_near(fbTotal, beTotal)) {
      mismatches.add('totalNumeric firebase=$fbTotal backend=$beTotal');
    }

    final fbCount = _itemCount(firebase['items']);
    final beCount = _itemCount(backendOrder['items']);
    if (fbCount != beCount) {
      mismatches.add('itemCount firebase=$fbCount backend=$beCount');
    }

    final fbStore = _str(firebase['storeId']);
    final beStore = _str(backendOrder['storeId']);
    if (fbStore.isNotEmpty && beStore.isNotEmpty && fbStore != beStore) {
      mismatches.add('storeId firebase=$fbStore backend=$beStore');
    }

    final fbUid = _str(firebase['customerUid']);
    final beUid = _str(backendOrder['customerUid']);
    if (fbUid.isNotEmpty && beUid.isNotEmpty && fbUid != beUid) {
      mismatches.add('userId(customerUid) firebase=$fbUid backend=$beUid');
    }

    return mismatches;
  }

  static Map<String, dynamic> backendOrderMap(Map<String, dynamic> backend) {
    final o = backend['order'];
    if (o is Map<String, dynamic>) return o;
    if (o is Map) return Map<String, dynamic>.from(o);
    return backend;
  }

  static int _itemCount(Object? items) {
    if (items is List) return items.length;
    return -1;
  }

  static String _str(Object? v) {
    if (v == null) return '';
    final s = v.toString().trim();
    return s.isEmpty ? '' : s;
  }

  static double _toDouble(Object? v) {
    if (v == null) return double.nan;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? double.nan;
  }

  static bool _near(double a, double b) => (a - b).abs() < _eps;
}
