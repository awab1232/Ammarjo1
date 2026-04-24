import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/backend_orders_config.dart';
import '../../../core/services/firebase_auth_header_provider.dart';

class SupportMessage {
  SupportMessage({
    required this.senderName,
    required this.senderId,
    required this.text,
    required this.createdAt,
  });

  final String senderName;
  final String senderId;
  final String text;
  final DateTime createdAt;

  factory SupportMessage.fromMap(Map<String, dynamic> map) => SupportMessage(
        senderName: map['senderName']?.toString() ?? '',
        senderId: map['senderId']?.toString() ?? '',
        text: map['text']?.toString() ?? '',
        createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

class SupportChatOpenResult {
  const SupportChatOpenResult({required this.chatId, required this.created});

  final String chatId;
  final bool created;
}

class SupportTicket {
  SupportTicket({
    required this.id,
    required this.status,
    required this.messages,
  });

  final String id;
  final String status;
  final List<SupportMessage> messages;

  factory SupportTicket.fromMap(Map<String, dynamic> map) {
    final raw = map['messages'];
    final messages = raw is List
        ? raw.whereType<Map>().map((e) => SupportMessage.fromMap(Map<String, dynamic>.from(e))).toList()
        : const <SupportMessage>[];
    return SupportTicket(
      id: map['id']?.toString() ?? '',
      status: map['status']?.toString() ?? 'open',
      messages: messages,
    );
  }
}

class SupportChatRepository {
  SupportChatRepository._();
  static final SupportChatRepository instance = SupportChatRepository._();

  Future<Map<String, String>> _headers() async {
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) throw StateError('Backend URL غير مضبوط');
    final auth = await FirebaseAuthHeaderProvider.requireAuthHeaders(reason: 'support_chat_headers');
    return {...auth, 'Content-Type': 'application/json'};
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '')}$path').replace(queryParameters: query);

  /// Opens the user’s single open support ticket or creates one (`POST /support/tickets`).
  Future<SupportChatOpenResult> findOrCreateOpenChat({
    required String uid,
    required String userName,
  }) async {
    final cur = FirebaseAuth.instance.currentUser;
    if (cur == null || cur.uid != uid) {
      throw StateError('جلسة المستخدم غير متطابقة');
    }
    final res = await http.post(
      _uri('/support/tickets'),
      headers: await _headers(),
      body: jsonEncode(<String, dynamic>{'userName': userName}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('تعذّر فتح المحادثة (${res.statusCode})');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } on Object {
      throw StateError('INVALID_JSON');
    }
    if (decoded is! Map) {
      throw StateError('استجابة غير صالحة من الخادم');
    }
    final m = Map<String, dynamic>.from(decoded);
    final id = m['id']?.toString() ?? '';
    if (id.isEmpty) throw StateError('معرّف المحادثة غير صالح');
    final created = m['created'] == true;
    return SupportChatOpenResult(chatId: id, created: created);
  }

  Future<SupportTicket?> fetchTicket(String ticketId) async {
    final res = await http.get(_uri('/support/tickets', {'id': ticketId.trim()}), headers: await _headers());
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('NULL_RESPONSE');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } on Object {
      throw StateError('INVALID_JSON');
    }
    if (decoded is Map<String, dynamic>) return SupportTicket.fromMap(decoded);
    if (decoded is Map) return SupportTicket.fromMap(Map<String, dynamic>.from(decoded));
    throw StateError('NULL_RESPONSE');
  }

  Future<void> sendMessage({
    required String chatId,
    required String text,
    String? senderId,
    required String senderName,
  }) async {
    final resolvedSenderId = senderId != null && senderId.trim().isNotEmpty
        ? senderId
        : FirebaseAuth.instance.currentUser?.uid;
    if (resolvedSenderId == null || resolvedSenderId.trim().isEmpty) {
      throw StateError('INVALID_ID');
    }
    final res = await http.patch(
      _uri('/support/tickets/${Uri.encodeComponent(chatId.trim())}'),
      headers: await _headers(),
      body: jsonEncode(<String, dynamic>{
        'message': {
          'senderId': resolvedSenderId,
          'senderName': senderName,
          'text': text.trim(),
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('تعذّر الإرسال (${res.statusCode})');
    }
  }

  Future<void> closeChat(String chatId) async {
    final res = await http.patch(
      _uri('/support/tickets/${Uri.encodeComponent(chatId.trim())}'),
      headers: await _headers(),
      body: jsonEncode(<String, dynamic>{'status': 'closed'}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('تعذّر إغلاق المحادثة (${res.statusCode})');
    }
  }

  Future<void> resetAdminUnreadCount(String chatId) async {
    await _touchTicket(chatId);
  }

  Future<void> resetUserUnreadCount(String chatId) async {
    await _touchTicket(chatId);
  }

  Future<void> _touchTicket(String chatId) async {
    final id = chatId.trim();
    if (id.isEmpty) return;
    final ticket = await fetchTicket(id);
    if (ticket == null) return;
    final res = await http.patch(
      _uri('/support/tickets/${Uri.encodeComponent(id)}'),
      headers: await _headers(),
      body: jsonEncode(<String, dynamic>{'status': ticket.status}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('تعذّر تحديث حالة القراءة (${res.statusCode})');
    }
  }
}
