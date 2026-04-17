/// سجل تدقيق من PostgreSQL (`admin_audit_log`).
class AuditLogModel {
  AuditLogModel({
    required this.id,
    required this.userId,
    required this.userEmail,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.details,
    required this.timestamp,
  });

  final String id;
  final String userId;
  final String userEmail;
  final String action;
  final String targetType;
  final String targetId;
  final Map<String, dynamic> details;
  final DateTime? timestamp;

  factory AuditLogModel.fromPgRow(Map<String, dynamic> row) {
    DateTime? ts;
    final raw = row['created_at'];
    if (raw is String) {
      ts = DateTime.tryParse(raw);
    }
    final payload = row['payload'];
    return AuditLogModel(
      id: row['id']?.toString() ?? '',
      userId: row['admin_firebase_uid']?.toString() ?? '',
      userEmail: '',
      action: row['action']?.toString() ?? '',
      targetType: row['target_type']?.toString() ?? '',
      targetId: row['target_id']?.toString() ?? '',
      details: payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{},
      timestamp: ts,
    );
  }
}
