import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../config/chat_feature_config.dart';
import '../../features/communication/data/unified_chat_repository.dart';
import '../../features/communication/domain/unified_chat_models.dart';

class ChatService {
  ChatService();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  UnifiedChatKind _kindForType(String chatType) {
    switch (chatType) {
      case 'store_customer':
      case 'store':
      case 'used_market':
      case 'market':
      case 'used':
        return UnifiedChatKind.storeCustomer;
      case 'home_store_customer':
      case 'home_store':
        return UnifiedChatKind.homeStoreCustomer;
      case 'technician_customer':
      case 'technician':
      case 'technician_request':
        return UnifiedChatKind.technicianCustomer;
      case 'support':
        return UnifiedChatKind.support;
      default:
        return UnifiedChatKind.storeCustomer;
    }
  }

  Future<String> getOrCreateChat({
    required String otherUserId,
    required String otherUserName,
    required String currentUserEmail,
    required String otherUserEmail,
    String currentUserPhone = '',
    String otherUserPhone = '',
    String chatType = 'general',
    String? referenceId,
    String? referenceName,
    String? referenceImageUrl,
    bool seedProductCard = false,
    String? productCardTitle,
    String? productCardPrice,
    String? productCardImageUrl,
  }) async {
    if (!kChatFeatureEnabled) {
      throw Exception(kChatFeatureUnavailableMessage);
    }
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('يرجى تسجيل الدخول أولاً');
    }
    if (currentUser.uid.isEmpty) {
      throw Exception('معرف المستخدم غير صالح. أعد تسجيل الدخول.');
    }

    final myId = currentUser.uid;
    final peerUid = otherUserId.trim();
    if (peerUid.isNotEmpty && peerUid == myId) {
      throw Exception('لا يمكن الدردشة مع نفسك');
    }
    final refId = (referenceId ?? '').trim();
    final type = chatType.trim().isEmpty ? 'general' : chatType.trim();

    final expectedCtx = refId.isEmpty ? 'general_$otherUserId' : refId;

    try {
      final chatId = await UnifiedChatRepository.instance.ensureChat(
        kind: _kindForType(type),
        contextId: expectedCtx,
        currentUserEmail: currentUserEmail,
        currentUserPhone: currentUserPhone,
        peerEmail: otherUserEmail,
        peerPhone: otherUserPhone,
        peerDisplayName: otherUserName,
        contextTitle: (referenceName ?? otherUserName).trim(),
        contextSubtitle: type,
        contextImageUrl: referenceImageUrl,
        seedProductCard: seedProductCard,
        productCardTitle: productCardTitle,
        productCardPrice: productCardPrice,
        productCardImageUrl: productCardImageUrl,
        peerFirebaseUid: otherUserId,
      );
      try {
        await UnifiedChatRepository.instance.ensureParticipantUidOnChat(chatId, currentUserEmail);
      } on Object {
        debugPrint('[ChatService] ensureParticipantUidOnChat after ensureChat failed');
      }
      return chatId;
    } on StateError {
      throw Exception('تعذر فتح المحادثة.');
    } on ArgumentError {
      throw Exception('تعذر فتح المحادثة.');
    } on Object {
      debugPrint('getOrCreateChat failed');
      throw Exception('تعذر فتح المحادثة. تحقق من الاتصال أو جرّب لاحقاً.');
    }
  }
}
