import 'package:cloud_firestore/cloud_firestore.dart';

/// نوع المحادثة المدعوم في النظام.
enum UnifiedChatKind {
  /// عميل ↔ متجر مواد بناء.
  storeCustomer,

  /// عميل ↔ متجر أجهزة منزلية.
  homeStoreCustomer,

  /// عميل ↔ فني.
  technicianCustomer,

  /// عميل ↔ دعم.
  support,
}

extension UnifiedChatKindX on UnifiedChatKind {
  String get firestoreValue {
    switch (this) {
      case UnifiedChatKind.storeCustomer:
        return 'store_customer';
      case UnifiedChatKind.homeStoreCustomer:
        return 'home_store_customer';
      case UnifiedChatKind.technicianCustomer:
        return 'technician_customer';
      case UnifiedChatKind.support:
        return 'support';
    }
  }

  static UnifiedChatKind? fromString(String? v) {
    switch (v) {
      case 'store_customer':
      case 'user_store':
      case 'store':
      case 'used_market':
      case 'market':
      case 'used':
        return UnifiedChatKind.storeCustomer;
      case 'home_store_customer':
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

  Duration get ttl {
    switch (this) {
      case UnifiedChatKind.storeCustomer:
      case UnifiedChatKind.homeStoreCustomer:
      case UnifiedChatKind.support:
        return const Duration(days: 30);
      case UnifiedChatKind.technicianCustomer:
        return const Duration(hours: 48);
    }
  }
}

enum UnifiedMessageType {
  text,
  productCard,
}

class UnifiedChatThread {
  UnifiedChatThread({
    required this.id,
    required this.kind,
    required this.contextId,
    required this.participantEmails,
    required this.contextTitle,
    required this.contextSubtitle,
    this.contextImageUrl,
    required this.phonesByEmail,
    required this.peerDisplayName,
    required this.expiresAt,
    required this.lastMessageAt,
    required this.lastMessagePreview,
    required this.createdAt,
  });

  final String id;
  final UnifiedChatKind kind;
  final String contextId;
  final List<String> participantEmails;
  final String contextTitle;
  final String contextSubtitle;
  final String? contextImageUrl;
  /// مفاتيح بريد مُطبَّعة بأحرف صغيرة.
  final Map<String, String> phonesByEmail;
  final String peerDisplayName;
  final DateTime expiresAt;
  final DateTime lastMessageAt;
  final String lastMessagePreview;
  final DateTime createdAt;

  static String _ne(String e) => e.trim().toLowerCase();

  /// رقم الطرف الآخر للاتصال السريع من صندوق الوارد.
  String? peerPhoneForViewer(String myEmail) {
    final me = _ne(myEmail);
    for (final e in participantEmails) {
      if (_ne(e) != me) {
        return phonesByEmail[_ne(e)];
      }
    }
    return '';
  }

  factory UnifiedChatThread.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    DateTime ts(String key) {
      final v = d[key];
      if (v is Timestamp) return v.toDate();
      return DateTime.now();
    }

    final rawPhones = d['phonesByEmail'];
    final phones = <String, String>{};
    if (rawPhones is Map) {
      for (final e in rawPhones.entries) {
        phones[e.key.toString().trim().toLowerCase()] = e.value.toString();
      }
    }

    return UnifiedChatThread(
      id: doc.id,
      kind: UnifiedChatKindX.fromString((d['type'] ?? d['kind']) as String?) ?? UnifiedChatKind.storeCustomer,
      contextId: d['contextId'] as String? ?? '',
      participantEmails:
          (d['participantEmails'] as List<dynamic>?)?.map((e) => 'unexpected error').toList() ?? const <String>[],
      contextTitle: d['contextTitle'] as String? ?? '',
      contextSubtitle: d['contextSubtitle'] as String? ?? '',
      contextImageUrl: d['contextImageUrl'] as String?,
      phonesByEmail: phones,
      peerDisplayName: d['peerDisplayName'] as String? ?? '',
      expiresAt: ts('expiresAt'),
      lastMessageAt: ts('lastMessageAt'),
      lastMessagePreview: d['lastMessagePreview'] as String? ?? '',
      createdAt: ts('createdAt'),
    );
  }
}

class UnifiedChatMessage {
  UnifiedChatMessage({
    required this.id,
    this.senderId,
    this.receiverId,
    required this.senderEmail,
    required this.type,
    required this.text,
    this.imagePath,
    this.productTitle,
    this.productPriceLabel,
    this.productImageUrl,
    required this.createdAt,
  });

  final String id;
  final String? senderId;
  final String? receiverId;
  final String senderEmail;
  final UnifiedMessageType type;
  final String text;
  /// رابط صورة مرفقة أو صورة بطاقة منتج (حسب النوع).
  final String? imagePath;
  final String? productTitle;
  final String? productPriceLabel;
  final String? productImageUrl;
  final DateTime createdAt;

  factory UnifiedChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final t = d['type'] as String? ?? 'text';
    DateTime at(String a, String b) {
      for (final key in [a, b]) {
        final v = d[key];
        if (v is Timestamp) return v.toDate();
      }
      return DateTime.now();
    }

    final img = d['imagePath'] as String?;
    final cardImg = d['productImageUrl'] as String?;
    return UnifiedChatMessage(
      id: doc.id,
      senderId: d['senderId'] as String?,
      receiverId: d['receiverId'] as String?,
      senderEmail: d['senderEmail'] as String? ?? '',
      type: t == 'product_card' ? UnifiedMessageType.productCard : UnifiedMessageType.text,
      text: d['text'] as String? ?? '',
      imagePath: img ?? cardImg,
      productTitle: d['productTitle'] as String?,
      productPriceLabel: d['productPriceLabel'] as String?,
      productImageUrl: d['productImageUrl'] as String?,
      createdAt: at('timestamp', 'createdAt'),
    );
  }
}
