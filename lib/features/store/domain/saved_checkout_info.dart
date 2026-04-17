/// بيانات توصيل محفوظة محلياً بعد أول عملية شراء (أو من صفحة الإعدادات).
class SavedCheckoutInfo {
  const SavedCheckoutInfo({
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.phone = '',
    this.address1 = '',
    this.city = '',
    this.country = 'JO',
  });

  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String address1;
  final String city;
  final String country;

  bool get hasAny =>
      firstName.isNotEmpty ||
      lastName.isNotEmpty ||
      phone.isNotEmpty ||
      address1.isNotEmpty ||
      city.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'address1': address1,
        'city': city,
        'country': country,
      };

  factory SavedCheckoutInfo.fromJson(Map<String, dynamic> json) {
    return SavedCheckoutInfo(
      firstName: json['firstName']?.toString() ?? '',
      lastName: json['lastName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      address1: json['address1']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      country: json['country']?.toString() ?? 'JO',
    );
  }

  SavedCheckoutInfo copyWith({
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? address1,
    String? city,
    String? country,
  }) {
    return SavedCheckoutInfo(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address1: address1 ?? this.address1,
      city: city ?? this.city,
      country: country ?? this.country,
    );
  }
}
