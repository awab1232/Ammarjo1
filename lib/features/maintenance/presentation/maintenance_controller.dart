import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/service_requests_repository.dart';
import '../../../core/services/backend_orders_client.dart';

/// حالة وضع الفني وطلبات الانضمام عبر الـ API.
class MaintenanceController extends ChangeNotifier {
  MaintenanceController();

  static const _kTechnicianMode = 'ammarjo_technician_mode';

  bool _technicianMode = false;
  bool get technicianMode => _technicianMode;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _technicianMode = p.getBool(_kTechnicianMode) ?? false;
    notifyListeners();
  }

  Future<void> setTechnicianMode(bool value) async {
    _technicianMode = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kTechnicianMode, value);
    notifyListeners();
  }

  /// تسجيل المستخدم كفني كـ "طلب انضمام" بانتظار موافقة الأدمن.
  /// [specialtyIds] معرّفات وثائق `tech_specialties`؛ [categoryId] للفلترة (مثل plumber).
  Future<void> registerTechnicianProfile({
    required String email,
    required String fullName,
    required String phone,
    required String city,
    required List<String> specialtyIds,
    required String categoryId,
    required String primarySpecialtyLabel,
    String? experienceDescription,
  }) async {
    final desc = (experienceDescription ?? '').trim();
    final ids = specialtyIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final applicantId = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (applicantId.isEmpty) throw StateError('INVALID_ID');
    await BackendOrdersClient.instance.submitStoreApplication({
      'kind': 'technician_request',
      'applicantId': applicantId,
      'email': email.trim().toLowerCase(),
      'fullName': fullName.trim(),
      'displayName': fullName.trim(),
      'phone': phone.trim(),
      'city': city.trim(),
      'specialtyLabel': primarySpecialtyLabel.trim(),
      'specialties': ids.isNotEmpty ? ids : [primarySpecialtyLabel.trim()],
      'categoryId': categoryId,
      'experienceDescription': desc,
      'status': 'pending',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    await setTechnicianMode(false);
  }

  Future<void> submitServiceRequest({
    required String title,
    required String categoryId,
    required String customerEmail,
    required String description,
    required String technicianEmail,
  }) {
    return ServiceRequestsRepository.instance.createRequest(
      title: title,
      categoryId: categoryId,
      customerEmail: customerEmail,
      description: description,
      technicianEmail: technicianEmail,
    );
  }
}
