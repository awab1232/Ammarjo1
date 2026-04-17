import '../constants/app_constants.dart';
import 'backend_orders_client.dart';

class CommissionService {
  CommissionService._();
  static final CommissionService instance = CommissionService._();

  static const double commissionRate = storeCommissionRate;

  Future<void> recordCommission({
    required String storeId,
    required String storeName,
    required String orderId,
    required double orderTotal,
  }) async {
    final cleanStoreId = storeId.trim();
    final cleanOrderId = orderId.trim();
    if (cleanStoreId.isEmpty || cleanOrderId.isEmpty || orderTotal <= 0) return;
    final commissionAmount = orderTotal * commissionRate;
    await BackendOrdersClient.instance.postInternalNotificationByEmail(
      email: 'commissions@ammarjo.app',
      title: 'commission_record',
      body: 'store=$cleanStoreId order=$cleanOrderId',
      type: 'commission',
      metadata: <String, dynamic>{
        'storeId': cleanStoreId,
        'storeName': storeName,
        'orderId': cleanOrderId,
        'orderTotal': orderTotal,
        'commissionAmount': commissionAmount,
      },
    );
  }
}
