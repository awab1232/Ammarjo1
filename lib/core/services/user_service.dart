import '../../features/store/domain/models.dart';
import '../utils/jordan_phone.dart';

/// Portable user profile rules — بدون Firebase.
class UserService {
  UserService._();
  static final UserService instance = UserService._();

  /// يحوّل بيانات `users/*` إلى [CustomerProfile] (نفس منطق التطبيق السابق).
  CustomerProfile? customerProfileFromMap(Map<String, dynamic>? d) {
    if (d == null) throw StateError('unexpected_empty_response');
    var email = d['email']?.toString().trim();
    final phone = d['phone']?.toString().trim();
    if ((email == null || email.isEmpty) && phone != null && phone.isNotEmpty) {
      final un = normalizeJordanPhoneForUsername(phone.replaceAll(RegExp(r'\D'), ''));
      if (un.length >= 12 && un.startsWith('962')) {
        email = syntheticEmailForPhone(un);
      }
    }
    if (email == null || email.isEmpty) throw StateError('unexpected_empty_response');
    String? phoneLocal;
    if (phone != null && phone.isNotEmpty) {
      if (phone.startsWith('+962')) {
        phoneLocal = phone.substring(4);
      } else if (phone.startsWith('962') && phone.length >= 12) {
        phoneLocal = phone.substring(3);
      }
    }
    final contact = d['contactEmail']?.toString().trim();
    final loyaltyPointsRaw = d['loyaltyPoints'] as num?;
    if (loyaltyPointsRaw == null) throw StateError('INVALID_NUMERIC_DATA');
    return CustomerProfile(
      email: email,
      token: null,
      fullName: d['name']?.toString(),
      loyaltyPoints: loyaltyPointsRaw.toInt(),
      firstName: d['firstName']?.toString(),
      lastName: d['lastName']?.toString(),
      phoneLocal: phoneLocal,
      addressLine: d['addressLine']?.toString(),
      city: d['city']?.toString(),
      country: d['country']?.toString() ?? 'JO',
      contactEmail: contact != null && contact.isNotEmpty ? contact : null,
    );
  }

  bool isUserBannedFromData(Map<String, dynamic>? d) => d?['banned'] == true;

  /// قيمة حقل `role` بعد التقليم، أو null.
  String? roleFromUserData(Map<String, dynamic>? d) {
    final r = d?['role']?.toString().trim();
    if (r == null || r.isEmpty) return '';
    return r;
  }

  /// حقول موقع التوصيل المحفوظة في `users/{uid}`.
  Map<String, dynamic> deliveryLocationFields({
    required double latitude,
    required double longitude,
  }) {
    final locStr = '$latitude, $longitude';
    return <String, dynamic>{
      'deliveryLat': latitude,
      'deliveryLng': longitude,
      'deliveryLocation': locStr,
    };
  }
}
