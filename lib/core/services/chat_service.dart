import 'package:flutter/foundation.dart';

class ChatService {
  ChatService();

  Future<String?> getOrCreateChat({
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
    if (kDebugMode) {
      debugPrint('ChatService disabled: chat feature flag is off');
    }
    return null;
  }
}
