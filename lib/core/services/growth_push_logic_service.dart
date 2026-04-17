import 'package:flutter/foundation.dart' show debugPrint;

class GrowthPushLogicService {
  GrowthPushLogicService._();

  static final GrowthPushLogicService instance = GrowthPushLogicService._();

  DateTime? _lastCartActivityAt;
  DateTime? _lastOfferSignalAt;

  void markCartActivity() {
    _lastCartActivityAt = DateTime.now();
  }

  void triggerAbandonedCartIfNeeded() {
    final last = _lastCartActivityAt;
    if (last == null) return;
    if (DateTime.now().difference(last) >= const Duration(hours: 6)) {
      debugPrint('[GrowthPushLogic] abandoned_cart trigger');
    }
  }

  void triggerNewOffersSignal({required int offersCount}) {
    if (offersCount <= 0) return;
    final now = DateTime.now();
    if (_lastOfferSignalAt != null &&
        now.difference(_lastOfferSignalAt!) < const Duration(hours: 2)) {
      return;
    }
    _lastOfferSignalAt = now;
    debugPrint('[GrowthPushLogic] new_offers trigger count=$offersCount');
  }

  void triggerPriceDropSignal({
    required int productId,
    required double oldPrice,
    required double newPrice,
  }) {
    if (newPrice >= oldPrice) return;
    debugPrint('[GrowthPushLogic] price_drop trigger product=$productId');
  }
}
