import '../../../core/contracts/feature_state.dart';
import '../../../core/session/backend_identity_controller.dart';
import '../../../core/services/backend_orders_client.dart';
import '../domain/maintenance_models.dart';
import 'technicians_seed_data.dart';

/// مستودع الفنيين — backend first مع دمج عيّنة ثابتة عند الحاجة.
class TechniciansRepository {
  TechniciansRepository._();
  static final TechniciansRepository instance = TechniciansRepository._();

  static const String collection = 'technicians';
  static const int pageSize = 20;

  static List<TechnicianProfile> _mergeWithSeed(
    List<TechnicianProfile> fromApi,
    List<TechnicianProfile> seedPool,
  ) {
    final ids = fromApi.map((e) => e.id).toSet();
    final out = List<TechnicianProfile>.from(fromApi);
    for (final s in seedPool) {
      if (!ids.contains(s.id)) out.add(s);
    }
    out.sort((a, b) => a.displayName.compareTo(b.displayName));
    return out;
  }

  Stream<FeatureState<List<TechnicianProfile>>> watchTechnicians() =>
      Stream<FeatureState<List<TechnicianProfile>>>.fromFuture(fetchTechnicians());

  Future<FeatureState<List<TechnicianProfile>>> fetchTechnicians() async {
    try {
      if (!BackendIdentityController.instance.isBackendFullAdmin) {
        // Non-admin users must not hit `/admin/rest/technicians`.
        return FeatureState.success(TechniciansSeedData.all);
      }
      final rows = await BackendOrdersClient.instance.fetchAdminTechnicians(limit: 300, offset: 0);
      final fromApi = rows
          .map((e) => TechnicianProfile.fromMap((e['id'] ?? e['uid'] ?? '').toString(), e))
          .where((e) => e.id.trim().isNotEmpty)
          .toList();
      if (fromApi.isEmpty) {
        return FeatureState.failure('No technicians returned from backend.');
      }
      return FeatureState.success(_mergeWithSeed(fromApi, TechniciansSeedData.all));
    } on Object {
      return FeatureState.failure('Failed to load technicians.');
    }
  }

  Stream<FeatureState<List<TechnicianProfile>>> watchTechniciansByCategory(String categoryId) {
    return watchApprovedTechnicians(specialty: categoryId, city: null);
  }

  Stream<FeatureState<List<MaintenanceServiceCategory>>> watchTechSpecialtiesWithTimeout({
    Duration timeout = const Duration(seconds: 15),
  }) =>
      Stream<FeatureState<List<MaintenanceServiceCategory>>>.fromFuture(fetchTechSpecialties(timeout: timeout));

  Future<FeatureState<List<MaintenanceServiceCategory>>> fetchTechSpecialties({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      final rows = await BackendOrdersClient.instance.fetchTechSpecialties().timeout(timeout);
      if (rows.isEmpty) {
        return FeatureState.failure('No specialties returned from backend.');
      }
      final out = rows
          .map((e) => MaintenanceServiceCategory.fromMap((e['id'] ?? '').toString(), e))
          .where((e) => e.id.trim().isNotEmpty)
          .toList();
      if (out.isEmpty) {
        return FeatureState.failure('Specialties payload is empty.');
      }
      return FeatureState.success(out);
    } on Object {
      return FeatureState.failure('Failed to load specialties.');
    }
  }

  /// التصفية حسب التخصص/المدينة والترتيب حسب `rating` تتم محلياً بعد جلب البيانات من الـ API.
  Stream<FeatureState<List<TechnicianProfile>>> watchApprovedTechnicians({String? specialty, String? city}) {
    return Stream<FeatureState<List<TechnicianProfile>>>.fromFuture(
      fetchApprovedTechnicians(specialty: specialty, city: city),
    );
  }

  Future<FeatureState<List<TechnicianProfile>>> fetchApprovedTechnicians({String? specialty, String? city}) async {
    final spec = specialty?.trim() ?? '';
    final cityFilter = city?.trim() ?? '';
    final applyCity = cityFilter.isNotEmpty && cityFilter != 'all';
    final techsState = await fetchTechnicians();
    if (techsState is! FeatureSuccess<List<TechnicianProfile>>) {
      return switch (techsState) {
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('Failed to load approved technicians.'),
      };
    }
    var techs = techsState.data;
    techs = techs.where((t) => (t.status ?? 'approved').toLowerCase() == 'approved').toList();
      if (spec.isNotEmpty) {
        techs = techs.where((t) => t.categoryId == spec || t.specialties.contains(spec)).toList();
      }
      if (applyCity) {
        techs = techs.where((t) {
          final c = t.city?.trim();
          return c == null || c.isEmpty || c == cityFilter || c == 'all' || c == 'all_jordan';
        }).toList();
      }
      techs.sort((a, b) => b.rating.compareTo(a.rating));
    return FeatureState.success(techs);
  }

  Future<({
    List<TechnicianProfile> technicians,
    Object? lastDoc,
    bool hasMore,
  })> fetchApprovedTechniciansPage({
    String? specialty,
    String? city,
    int limit = pageSize,
    Object? startAfter,
  }) async {
    final spec = specialty?.trim() ?? '';
    final cityFilter = city?.trim() ?? '';
    final applyCity = cityFilter.isNotEmpty && cityFilter != 'all';

    final techsState = await fetchApprovedTechnicians(specialty: specialty, city: city);
    if (techsState is! FeatureSuccess<List<TechnicianProfile>>) {
      return (technicians: <TechnicianProfile>[], lastDoc: null, hasMore: false);
    }
    var techs = techsState.data;
    if (spec.isNotEmpty) {
      techs = techs.where((t) => t.categoryId == spec || t.specialties.contains(spec)).toList();
    }
    if (applyCity) {
      techs = techs.where((t) {
        final c = t.city?.trim();
        return c == null || c.isEmpty || c == cityFilter || c == 'all' || c == 'all_jordan';
      }).toList();
    }
    techs.sort((a, b) => b.rating.compareTo(a.rating));
    final page = techs.take(limit).toList();
    return (technicians: page, lastDoc: null, hasMore: techs.length > limit);
  }

  Future<void> upsertTechnician(String docId, TechnicianProfile profile) async {
    await BackendOrdersClient.instance.upsertAdminTechnician(docId.trim(), profile.toMap());
  }

  Stream<Map<String, dynamic>?> watchTechnicianDocument(String id) =>
      Stream<Map<String, dynamic>?>.fromFuture(BackendOrdersClient.instance.fetchAdminTechnicianById(id.trim()));

  Stream<Map<String, dynamic>?> watchTechnicianUserRatingDoc(String techId, String userId) =>
      const Stream<Map<String, dynamic>?>.empty();
}

