import 'dart:async' show unawaited;
import 'dart:typed_data';

import '../../../core/contracts/feature_state.dart';
import '../../../core/firebase/user_notifications_repository.dart';
import '../../../core/services/backend_tender_client.dart';
import '../../store/domain/models.dart';
import '../../stores/data/stores_repository.dart';
import '../../stores/domain/store_model.dart';
import '../domain/tender_model.dart';

class TenderRepository {
  TenderRepository._();
  static final TenderRepository instance = TenderRepository._();

  /// إنشاء مناقصة جديدة مع ربطها بنوع المتجر (storeTypeId/Key) ليتم توجيه الإشعارات
  /// إلى المتاجر المطابقة فقط (بدلاً من بث موحد لكل المتاجر).
  Future<FeatureState<String>> createTender({
    required List<Uint8List> imageBytesList,
    required String categoryId,
    required String categoryLabel,
    required String description,
    required String city,
    required String userName,
    String? storeTypeId,
    String? storeTypeKey,
    String? storeTypeName,
  }) async {
    final row = await BackendTenderClient.instance.createTender(
      categoryId: categoryId,
      description: description,
      city: city,
      userName: userName,
      storeTypeId: storeTypeId,
      storeTypeKey: storeTypeKey,
      storeTypeName: storeTypeName,
      imageBytesList: imageBytesList,
    );
    final id = row?['id']?.toString().trim() ?? '';
    if (id.isEmpty) return FeatureState.failure('تعذر إنشاء المناقصة');
    unawaited(
      _notifyTargetedStores(
        tenderId: id,
        category: categoryLabel,
        city: city,
        userName: userName,
        storeTypeId: storeTypeId,
        storeTypeKey: storeTypeKey,
        storeTypeName: storeTypeName,
      ),
    );
    return FeatureState.success(id);
  }

  Future<Map<String, dynamic>?> fetchTenderDocument(String tenderId) =>
      BackendTenderClient.instance.fetchTender(tenderId.trim());

  Stream<FeatureState<List<TenderModel>>> watchMyTenders() async* {
    try {
      final rowsState = await BackendTenderClient.instance.fetchMyTenders();
      if (rowsState is! FeatureSuccess<List<Map<String, dynamic>>>) {
        yield switch (rowsState) {
          FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
          _ => FeatureState.failure('Failed to load tenders.'),
        };
        return;
      }
      final items = <TenderModel>[];
      for (final row in rowsState.data) {
        try {
          final id = row['id']?.toString() ?? '';
          if (id.trim().isEmpty) continue;
          items.add(TenderModel.fromMap(id, row));
        } on Object {
          continue;
        }
      }
      yield FeatureState.success(items);
    } on Object {
      yield FeatureState.failure('Failed to load tenders.');
    }
  }

  /// Store-owner feed: calls `/tenders/open` which targets tenders by the store's
  /// own `storeTypeId` (or `storeTypeKey`). `category` and `city` remain optional
  /// client-side filters for finer UX scoping.
  Stream<FeatureState<List<TenderModel>>> watchTendersForStore({
    required String category,
    required String city,
    String? storeTypeId,
    String? storeTypeKey,
  }) async* {
    try {
      final rowsState = await BackendTenderClient.instance.fetchOpenTendersForStore(
        storeTypeId: storeTypeId,
        storeTypeKey: storeTypeKey,
        city: city.trim().isEmpty ? null : city.trim(),
      );
      if (rowsState is! FeatureSuccess<List<Map<String, dynamic>>>) {
        yield switch (rowsState) {
          FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
          _ => FeatureState.failure('Failed to load store tenders.'),
        };
        return;
      }
      var list = <TenderModel>[];
      for (final row in rowsState.data) {
        try {
          final id = row['id']?.toString() ?? '';
          if (id.trim().isEmpty) continue;
          list.add(TenderModel.fromMap(id, row));
        } on Object {
          continue;
        }
      }
      if (category.trim().isNotEmpty) {
        list = list.where((e) => e.categoryId == category.trim()).toList();
      }
      yield FeatureState.success(list);
    } on Object {
      yield FeatureState.failure('Failed to load store tenders.');
    }
  }

  Stream<FeatureState<List<StoreSubmittedOfferRow>>> watchStoreSubmittedOffers({
    required String storeId,
    String? storeOwnerUid,
  }) async* {
    yield FeatureState.failure('Submitted offers endpoint is not wired yet.');
  }

  Stream<FeatureState<List<TenderOffer>>> watchOffers(String tenderId) async* {
    try {
      final rowsState = await BackendTenderClient.instance.fetchTenderOffers(tenderId);
      if (rowsState is! FeatureSuccess<List<Map<String, dynamic>>>) {
        yield switch (rowsState) {
          FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
          _ => FeatureState.failure('Failed to load tender offers.'),
        };
        return;
      }
      final items = <TenderOffer>[];
      for (final row in rowsState.data) {
        try {
          final id = row['id']?.toString() ?? '';
          if (id.trim().isEmpty) continue;
          items.add(TenderOffer.fromMap(id, row));
        } on Object {
          continue;
        }
      }
      yield FeatureState.success(items);
    } on Object {
      yield FeatureState.failure('Failed to load tender offers.');
    }
  }

  Future<FeatureState<void>> submitOffer({
    required String tenderId,
    required String storeId,
    required String storeName,
    required double price,
    required String note,
  }) async {
    final row = await BackendTenderClient.instance.submitOffer(
      tenderId: tenderId,
      storeId: storeId,
      storeName: storeName,
      price: price,
      note: note,
    );
    if (row == null) return FeatureState.failure('تعذر إرسال العرض');
    return FeatureState.success(null);
  }

  Future<FeatureState<CartItem>> acceptOffer({
    required String tenderId,
    required TenderOffer offer,
    required String tenderImageUrl,
    required String category,
  }) async {
    final row = await BackendTenderClient.instance.acceptOffer(tenderId: tenderId, offerId: offer.id);
    if (row == null) return FeatureState.failure('تعذر قبول العرض');
    return FeatureState.success(CartItem.tenderOffer(
      tenderId: tenderId,
      category: category,
      price: offer.price,
      storeId: offer.storeId,
      storeName: offer.storeName,
      tenderImageUrl: tenderImageUrl,
    ));
  }

  Future<void> closeTender(String tenderId, {String status = 'closed'}) async {
    await BackendTenderClient.instance.patchTenderStatus(tenderId, status: status);
  }

  Future<void> deleteTender(String tenderId) async {
    await BackendTenderClient.instance.deleteTender(tenderId);
  }

  /// يُرسل إشعار المناقصة الجديدة إلى أصحاب المتاجر التي تطابق [storeTypeId] أو [storeTypeKey]،
  /// إضافةً إلى بث عام للإداريين. إذا تعذّر جلب المتاجر المطابقة لأي سبب، يسقط المسار على إشعار الإداريين.
  Future<void> _notifyTargetedStores({
    required String tenderId,
    required String category,
    required String city,
    required String userName,
    String? storeTypeId,
    String? storeTypeKey,
    String? storeTypeName,
  }) async {
    final typeLabel = (storeTypeName ?? category).trim();
    final title = 'مناقصة جديدة';
    final body = '$userName يطلب عرض سعر — القسم: $typeLabel — المدينة: $city';

    // 1) إشعار الإداريين دائماً (للمراقبة والمتابعة).
    unawaited(
      UserNotificationsRepository.sendNotificationToAdmin(
        title: title,
        body: body,
        type: 'new_tender',
        referenceId: tenderId,
      ),
    );

    // 2) جلب المتاجر المطابقة لنوع المتجر فقط ثم إشعار أصحابها.
    try {
      final state = await StoresRepository.instance
          .fetchApprovedStores(storeTypeId: storeTypeId?.trim().isNotEmpty == true ? storeTypeId : null);
      if (state is! FeatureSuccess<List<StoreModel>>) return;
      final sid = (storeTypeId ?? '').trim();
      final skey = (storeTypeKey ?? '').trim().toLowerCase();
      final targets = state.data.where((s) {
        if (sid.isNotEmpty) return (s.storeTypeId ?? '').trim() == sid;
        if (skey.isNotEmpty) return (s.storeTypeKey ?? '').trim().toLowerCase() == skey;
        return false;
      }).toList();
      final seen = <String>{};
      for (final s in targets) {
        final uid = s.ownerId.trim();
        if (uid.isEmpty || seen.contains(uid)) continue;
        seen.add(uid);
        unawaited(
          UserNotificationsRepository.sendNotificationToUser(
            userId: uid,
            title: title,
            body: body,
            type: 'new_tender',
            referenceId: tenderId,
          ),
        );
      }
    } on Object {
      // نبتلع الخطأ لعدم منع نجاح إنشاء المناقصة إذا فشل جلب المتاجر.
    }
  }

  Future<({List<Map<String, dynamic>> items, Object? lastDocument, bool hasMore})> getStoreTenderCommissions({
    required String storeId,
    required int limit,
    Object? startAfter,
  }) async {
    final itemsState = await BackendTenderClient.instance.fetchStoreCommissions(storeId, limit: limit);
    if (itemsState is! FeatureSuccess<List<Map<String, dynamic>>>) {
      return (items: <Map<String, dynamic>>[], lastDocument: null, hasMore: false);
    }
    final items = itemsState.data;
    return (items: items, lastDocument: null, hasMore: items.length == limit);
  }

  Future<({List<Map<String, dynamic>> items, Object? lastDocument, bool hasMore})> getAllTenderCommissions({
    required int limit,
    Object? startAfter,
    String? storeId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    if (storeId != null && storeId.trim().isNotEmpty) {
      return getStoreTenderCommissions(storeId: storeId, limit: limit, startAfter: startAfter);
    }
    return (items: const <Map<String, dynamic>>[], lastDocument: null, hasMore: false);
  }
}
