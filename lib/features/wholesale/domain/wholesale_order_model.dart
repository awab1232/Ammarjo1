class WholesaleOrderItem {
  const WholesaleOrderItem({
    required this.productId,
    this.variantId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    required this.total,
  });

  final String productId;
  final String? variantId;
  final String name;
  final double unitPrice;
  final int quantity;
  final double total;

  factory WholesaleOrderItem.fromBackendMap(Map<String, dynamic> data) {
    final up = data['unitPrice'];
    final qty = data['quantity'];
    final t = data['total'];
    return WholesaleOrderItem(
      productId: (data['productId'] ?? '').toString(),
      variantId: data['variantId']?.toString(),
      name: (data['name'] ?? '').toString(),
      unitPrice: up is num
          ? up.toDouble()
          : double.tryParse(up?.toString() ?? '') ??
              0.0,
      quantity: qty is num
          ? qty.toInt()
          : int.tryParse(qty?.toString() ?? '') ?? 0,
      total: t is num
          ? t.toDouble()
          : double.tryParse(t?.toString() ?? '') ??
              0.0,
    );
  }

  Map<String, dynamic> toBackendMap() => <String, dynamic>{
        'productId': productId,
        if (variantId != null) 'variantId': variantId,
        'name': name,
        'unitPrice': unitPrice,
        'quantity': quantity,
        'total': total,
      };
}

class WholesaleOrderModel {
  const WholesaleOrderModel({
    required this.orderId,
    required this.wholesalerId,
    required this.wholesalerName,
    required this.storeOwnerId,
    required this.storeName,
    required this.items,
    required this.subtotal,
    required this.commission,
    required this.netAmount,
    required this.status,
    required this.createdAt,
    this.deliveredAt,
  });

  final String orderId;
  final String wholesalerId;
  final String wholesalerName;
  final String storeOwnerId;
  final String storeName;
  final List<WholesaleOrderItem> items;
  final double subtotal;
  final double commission;
  final double netAmount;
  final String status;
  final DateTime createdAt;
  final DateTime? deliveredAt;

  factory WholesaleOrderModel.fromBackendMap(Map<String, dynamic> data) {
    final itemsRaw = data['items'];
    final parsedItems = <WholesaleOrderItem>[];
    if (itemsRaw is List) {
      for (final row in itemsRaw) {
        if (row is Map) {
          parsedItems.add(
            WholesaleOrderItem.fromBackendMap(Map<String, dynamic>.from(row)),
          );
        }
      }
    }
    final sub = data['subtotal'];
    final com = data['commission'];
    final net = data['netAmount'];
    final created = data['createdAt'];
    final delivered = data['deliveredAt'];
    return WholesaleOrderModel(
      orderId: (data['id'] ?? data['orderId'] ?? '').toString(),
      wholesalerId: (data['wholesalerId'] ?? data['wholesaler_id'] ?? '').toString(),
      wholesalerName: (data['wholesalerName'] ?? '').toString(),
      storeOwnerId: (data['storeOwnerId'] ?? data['store_owner_id'] ?? '').toString(),
      storeName: (data['storeName'] ?? data['store_name'] ?? '').toString(),
      items: parsedItems,
      subtotal: sub is num
          ? sub.toDouble()
          : double.tryParse(sub?.toString() ?? '') ??
              0.0,
      commission: com is num
          ? com.toDouble()
          : double.tryParse(com?.toString() ?? '') ??
              0.0,
      netAmount: net is num
          ? net.toDouble()
          : double.tryParse((data['net_amount'] ?? net)?.toString() ?? '') ??
              0.0,
      status: (data['status'] ?? 'pending').toString(),
      createdAt: created is String ? (DateTime.tryParse(created)?.toLocal() ?? DateTime.now()) : DateTime.now(),
      deliveredAt: delivered is String ? DateTime.tryParse(delivered)?.toLocal() : null,
    );
  }
}
