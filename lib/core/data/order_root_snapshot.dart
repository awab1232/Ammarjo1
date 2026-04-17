/// Read model for root `orders/{id}` data from backend APIs.
class OrderRootSnapshot {
  const OrderRootSnapshot({required this.exists, required this.data});

  final bool exists;
  final Map<String, dynamic>? data;
}
