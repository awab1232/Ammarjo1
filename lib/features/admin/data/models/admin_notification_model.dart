/// In-app notification row (PostgreSQL inbox via REST).
class AdminNotification {
  AdminNotification({
    required this.id,
    required this.message,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.targetRole,
  });

  final String id;
  final String message;
  final String type;
  final bool isRead;
  final DateTime? createdAt;
  final String? targetRole;

  factory AdminNotification.fromBackendJson(Map<String, dynamic> j) {
    DateTime? created;
    final t = j['createdAt'] ?? j['created_at'];
    if (t is String) {
      created = DateTime.tryParse(t);
    }
    final title = j['title']?.toString() ?? '';
    final body = j['body']?.toString() ?? '';
    final msg = title.isNotEmpty && body.isNotEmpty ? '$title — $body' : (title.isNotEmpty ? title : body);
    return AdminNotification(
      id: j['id']?.toString() ?? '',
      message: msg,
      type: j['type']?.toString() ?? 'general',
      isRead: j['read'] == true,
      createdAt: created,
      targetRole: null,
    );
  }
}

abstract final class AdminNotificationFields {
  AdminNotificationFields._();

  static const String broadcastTargetRole = '__all__';
}
