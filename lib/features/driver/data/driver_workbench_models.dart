// View models for `GET /drivers/workbench` (camelCase JSON from Nest).

class DriverOnboardingInfo {
  const DriverOnboardingInfo({
    required this.status,
    this.requestId,
    this.identityImageUrl,
  });

  /// `none` | `pending` | `approved` | `rejected`
  final String status;
  final String? requestId;
  final String? identityImageUrl;

  static DriverOnboardingInfo parse(Object? raw) {
    if (raw is! Map) {
      return const DriverOnboardingInfo(status: 'none');
    }
    final m = Map<String, dynamic>.from(raw);
    return DriverOnboardingInfo(
      status: (m['status'] ?? 'none').toString().toLowerCase(),
      requestId: m['requestId']?.toString(),
      identityImageUrl: m['identityImageUrl']?.toString(),
    );
  }
}

class DriverProfile {
  const DriverProfile({
    required this.id,
    this.name,
    this.phone,
    required this.status,
    required this.isAvailable,
  });

  final String id;
  final String? name;
  final String? phone;
  final String status;
  final bool isAvailable;

  static DriverProfile? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final id = m['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    return DriverProfile(
      id: id,
      name: m['name']?.toString(),
      phone: m['phone']?.toString(),
      status: (m['status'] ?? 'offline').toString().toLowerCase(),
      isAvailable: m['isAvailable'] == true,
    );
  }
}

class DriverWorkbenchOrder {
  const DriverWorkbenchOrder({
    required this.orderId,
    required this.customerName,
    required this.address,
    this.etaMinutes,
    required this.deliveryStatus,
    this.distanceKm,
  });

  final String orderId;
  final String customerName;
  final String address;
  final int? etaMinutes;
  final String deliveryStatus;
  final double? distanceKm;

  static DriverWorkbenchOrder? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final orderId = m['orderId']?.toString().trim() ?? '';
    if (orderId.isEmpty) return null;
    final eta = m['etaMinutes'];
    int? etaMinutes;
    if (eta is int) {
      etaMinutes = eta;
    } else if (eta is num) {
      etaMinutes = eta.round();
    } else if (eta != null) {
      etaMinutes = int.tryParse(eta.toString());
    }
    final dist = m['distanceKm'];
    double? distanceKm;
    if (dist is num) {
      distanceKm = dist.toDouble();
    } else if (dist != null) {
      distanceKm = double.tryParse(dist.toString());
    }
    return DriverWorkbenchOrder(
      orderId: orderId,
      customerName: m['customerName']?.toString().trim().isNotEmpty == true
          ? m['customerName'].toString()
          : '—',
      address: m['address']?.toString().trim().isNotEmpty == true ? m['address'].toString() : '—',
      etaMinutes: etaMinutes,
      deliveryStatus: (m['deliveryStatus'] ?? '').toString(),
      distanceKm: distanceKm,
    );
  }

  static List<DriverWorkbenchOrder> parseList(Object? raw) {
    if (raw is! List) return List<DriverWorkbenchOrder>.empty();
    final out = <DriverWorkbenchOrder>[];
    for (final e in raw) {
      final o = tryParse(e);
      if (o != null) out.add(o);
    }
    return out;
  }
}

class DriverWorkbenchData {
  const DriverWorkbenchData({
    required this.onboarding,
    required this.driver,
    required this.assignedOrders,
    required this.activeOrder,
    required this.history,
  });

  final DriverOnboardingInfo onboarding;
  final DriverProfile? driver;
  final List<DriverWorkbenchOrder> assignedOrders;
  final DriverWorkbenchOrder? activeOrder;
  final List<DriverWorkbenchOrder> history;

  factory DriverWorkbenchData.fromJson(Map<String, dynamic> json) {
    return DriverWorkbenchData(
      onboarding: DriverOnboardingInfo.parse(json['onboarding']),
      driver: DriverProfile.tryParse(json['driver']),
      assignedOrders: DriverWorkbenchOrder.parseList(json['assignedOrders']),
      activeOrder: DriverWorkbenchOrder.tryParse(json['activeOrder']),
      history: DriverWorkbenchOrder.parseList(json['history']),
    );
  }
}
