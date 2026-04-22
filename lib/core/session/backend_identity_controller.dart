import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/backend_auth_me.dart';
import '../services/backend_orders_client.dart';
import '../services/permission_service.dart';

/// Holds `GET /auth/me` for UI hints only; authorization remains on the server.
class BackendIdentityController extends ChangeNotifier {
  BackendIdentityController._();
  static final BackendIdentityController instance = BackendIdentityController._();

  BackendAuthMe? _me;
  BackendAuthMe? get me => _me;

  final StreamController<void> _identityTick = StreamController<void>.broadcast();
  Stream<void> get identityUpdates => _identityTick.stream;

  bool get isBackendFullAdmin {
    final role = _me?.role.trim() ?? '';
    if (role.isEmpty) return false;
    final normalized = PermissionService.normalizeRole(role);
    return normalized == PermissionService.roleAdmin || normalized == PermissionService.roleSystemInternal;
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    if (!_identityTick.isClosed) {
      _identityTick.add(null);
    }
  }

  Future<void> refresh() async {
    try {
      final next = await BackendOrdersClient.instance.fetchAuthMe();
      _me = next;
    } on Object catch (e) {
      // `/auth/me` may return 401 right after OTP on some environments;
      // keep UI alive and treat backend identity as unavailable.
      debugPrint('[BackendIdentityController] refresh skipped: $e');
      _me = null;
    }
    notifyListeners();
  }

  void clear() {
    _me = null;
    notifyListeners();
  }
}
