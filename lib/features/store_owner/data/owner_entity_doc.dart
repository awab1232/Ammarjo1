/// مستند بسيط يستبدل [QueryDocumentSnapshot] في لوحة التاجر عند القراءة من REST.
class OwnerEntityDoc {
  const OwnerEntityDoc(this.id, this._data);
  final String id;
  final Map<String, dynamic> _data;
  Map<String, dynamic> data() => _data;
}

/// بديل [DocumentSnapshot] لبثّ بيانات المتجر من REST.
class OwnerStoreSnapshot {
  const OwnerStoreSnapshot({required this.exists, Map<String, dynamic>? data}) : _data = data;
  final bool exists;
  final Map<String, dynamic>? _data;
  Map<String, dynamic>? data() => _data;
}

/// ملخص + طلبات عمولة من `GET /stores/:id/commissions`.
class StoreCommissionView {
  const StoreCommissionView({
    required this.totalCommission,
    required this.totalPaid,
    required this.balance,
    required this.orderDocs,
  });

  final double totalCommission;
  final double totalPaid;
  final double balance;
  final List<OwnerEntityDoc> orderDocs;
}
