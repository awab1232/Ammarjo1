import '../../../core/services/backend_notifications_client.dart';
import '../../../core/contracts/feature_unit.dart';
import '../../../core/contracts/feature_state.dart';

class TechnicianNotification {
  TechnicianNotification({
    required this.id,
    required this.technicianEmail,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
    this.requestId,
  });

  final String id;
  final String technicianEmail;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final String? requestId;

  factory TechnicianNotification.fromMap(Map<String, dynamic> d) {
    final created = DateTime.tryParse(d['createdAt']?.toString() ?? '') ?? DateTime.now();
    return TechnicianNotification(
      id: d['id']?.toString() ?? '',
      technicianEmail: d['technicianEmail'] as String? ?? '',
      title: d['title'] as String? ?? 'إشعار جديد',
      body: d['body'] as String? ?? '',
      createdAt: created,
      read: d['read'] as bool? ?? false,
      requestId: d['requestId'] as String?,
    );
  }
}

class TechnicianNotificationsRepository {
  TechnicianNotificationsRepository._();
  static final TechnicianNotificationsRepository instance = TechnicianNotificationsRepository._();

  Future<FeatureState<List<TechnicianNotification>>> fetchRecent(String technicianEmail) async {
    if (technicianEmail.isEmpty) {
      return FeatureState.failure('Technician email is required.');
    }
    final rowsState = await BackendNotificationsClient.instance.fetchNotifications(limit: 50, offset: 0);
    if (rowsState is! FeatureSuccess<List<Map<String, dynamic>>>) {
      return switch (rowsState) {
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('Failed to load notifications.'),
      };
    }
    final list = rowsState.data
        .where((e) => (e['type']?.toString() ?? '').contains('service_request'))
        .map(TechnicianNotification.fromMap)
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return FeatureState.success(list.take(30).toList());
  }

  Stream<FeatureState<List<TechnicianNotification>>> watchRecent(String technicianEmail) =>
      Stream<FeatureState<List<TechnicianNotification>>>.fromFuture(fetchRecent(technicianEmail));

  Stream<FeatureState<int>> watchUnreadCount(String technicianEmail) {
    return watchRecent(technicianEmail).map((state) {
      return switch (state) {
        FeatureSuccess(:final data) => FeatureState.success(data.where((n) => !n.read).length),
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('Failed to compute unread notifications.'),
      };
    });
  }

  Future<FeatureState<int>> fetchUnreadCount(String technicianEmail) async {
    final state = await fetchRecent(technicianEmail);
    return switch (state) {
      FeatureSuccess(:final data) => FeatureState.success(data.where((n) => !n.read).length),
      FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
      _ => FeatureState.failure('Failed to load unread notifications count.'),
    };
  }

  Future<FeatureState<FeatureUnit>> markAllRead(String technicianEmail) async {
    final listState = await fetchRecent(technicianEmail);
    if (listState is! FeatureSuccess<List<TechnicianNotification>>) {
      return switch (listState) {
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('Failed to load notifications for mark-all-read.'),
      };
    }
    for (final n in listState.data.where((e) => !e.read)) {
      await BackendNotificationsClient.instance.markRead(n.id);
    }
    return FeatureState.success(FeatureUnit.value);
  }
}
