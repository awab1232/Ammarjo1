import 'package:flutter/material.dart';

/// أيقونة التخصص من لوحة الإدارة (`icon` نصي) أو افتراضي حسب [docId]/الاسم.
IconData resolveTechSpecialtyIcon(String? iconKey, String docId, String nameAr) {
  for (final c in MaintenanceServiceCategory.grid) {
    if (c.id == docId) return c.icon;
  }
  final k = iconKey?.trim().toLowerCase() ?? '';
  const map = <String, IconData>{
    'plumbing_outlined': Icons.plumbing_outlined,
    'plumber': Icons.plumbing_outlined,
    'electrical_services_outlined': Icons.electrical_services_outlined,
    'electrician': Icons.electrical_services_outlined,
    'format_paint_outlined': Icons.format_paint_outlined,
    'painter': Icons.format_paint_outlined,
    'carpenter_outlined': Icons.carpenter_outlined,
    'carpenter': Icons.carpenter_outlined,
    'handyman_outlined': Icons.handyman_outlined,
    'blacksmith': Icons.handyman_outlined,
    'construction_outlined': Icons.construction_outlined,
    'daily_laborer': Icons.construction_outlined,
    'build': Icons.build_outlined,
    'home_repair_service': Icons.home_repair_service_outlined,
    'engineering': Icons.engineering_outlined,
  };
  if (k.isNotEmpty && map.containsKey(k)) return map[k]!;
  final n = nameAr.toLowerCase();
  if (n.contains('سباكة') || n.contains('موسرجي') || n.contains('سبّاك') || n.contains('سباك')) return Icons.plumbing_outlined;
  if (n.contains('كهرب')) return Icons.electrical_services_outlined;
  if (n.contains('دهان') || n.contains('دهانين')) return Icons.format_paint_outlined;
  if (n.contains('نجار')) return Icons.carpenter_outlined;
  if (n.contains('حداد')) return Icons.handyman_outlined;
  if (n.contains('مياومة') || n.contains('عامل')) return Icons.construction_outlined;
  return Icons.home_repair_service_outlined;
}

/// فئات خدمات AmmarJo Maintenance (تتطابق مع واجهة الشبكة).
class MaintenanceServiceCategory {
  const MaintenanceServiceCategory({
    required this.id,
    required this.labelAr,
    required this.icon,
    this.backgroundImageUrl,
  });

  final String id;
  final String labelAr;
  final IconData icon;
  /// خلفية البطاقة من `tech_specialties.imageUrl` (اختياري).
  final String? backgroundImageUrl;

  static const List<MaintenanceServiceCategory> grid = [
    MaintenanceServiceCategory(id: 'plumber', labelAr: 'سبّاك', icon: Icons.plumbing_outlined),
    MaintenanceServiceCategory(id: 'electrician', labelAr: 'كهربائي', icon: Icons.electrical_services_outlined),
    MaintenanceServiceCategory(id: 'painter', labelAr: 'دهان', icon: Icons.format_paint_outlined),
    MaintenanceServiceCategory(id: 'carpenter', labelAr: 'نجار', icon: Icons.carpenter_outlined),
    MaintenanceServiceCategory(id: 'blacksmith', labelAr: 'حداد', icon: Icons.handyman_outlined),
    MaintenanceServiceCategory(id: 'daily_laborer', labelAr: 'عامل مياومة', icon: Icons.construction_outlined),
  ];

  factory MaintenanceServiceCategory.fromMap(String id, Map<String, dynamic> d) {
    final name = d['name']?.toString().trim() ?? '';
    final img = d['imageUrl']?.toString().trim();
    return MaintenanceServiceCategory(
      id: id,
      labelAr: name.isEmpty ? id : name,
      icon: resolveTechSpecialtyIcon(d['icon']?.toString(), id, name.isEmpty ? id : name),
      backgroundImageUrl: img != null && img.isNotEmpty ? img : null,
    );
  }

  static String labelForId(String id) {
    for (final c in grid) {
      if (c.id == id) return c.labelAr;
    }
    return id;
  }

  static String idForLabel(String label) {
    for (final c in grid) {
      if (c.labelAr == label) return c.id;
    }
    return 'plumber';
  }
}

/// بيانات الفني القادمة من الخادم.
class TechnicianProfile {
  TechnicianProfile({
    required this.id,
    required this.displayName,
    required this.specialties,
    required this.rating,
    required this.distanceKm,
    required this.locationLabel,
    this.photoUrl,
    this.email,
    this.categoryId,
    this.phone,
    this.city,
    this.bio,
    this.status,
  });

  final String id;
  final String displayName;
  final List<String> specialties;
  final double rating;
  final double distanceKm;
  final String locationLabel;
  final String? photoUrl;
  final String? email;
  final String? categoryId;
  final String? phone;
  final String? city;
  /// نبذة قصيرة للعرض في البطاقات.
  final String? bio;
  /// مثال: `approved` | `pending` — للفلترة والإدارة.
  final String? status;

  factory TechnicianProfile.fromMap(String id, Map<String, dynamic> d) {
    final specs = d['specialties'];
    return TechnicianProfile(
      id: id,
      displayName: d['displayName'] as String? ?? 'فني',
      specialties: specs is List ? specs.map((e) => e.toString()).toList() : const <String>[],
      rating: (d['rating'] as num?)?.toDouble() ?? 4.5,
      distanceKm: (d['distanceKm'] as num?)?.toDouble() ?? 1.0,
      locationLabel: d['locationLabel'] as String? ?? 'عمان',
      photoUrl: d['photoUrl'] as String?,
      email: d['email'] as String?,
      categoryId: d['category'] as String?,
      phone: d['phone'] as String?,
      city: d['city'] as String?,
      bio: d['bio'] as String?,
      status: d['status'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'specialties': specialties,
        'rating': rating,
        'distanceKm': distanceKm,
        'locationLabel': locationLabel,
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (email != null) 'email': email,
        if (categoryId != null) 'category': categoryId,
        if (phone != null) 'phone': phone,
        if (city != null) 'city': city,
        if (bio != null) 'bio': bio,
        if (status != null) 'status': status,
      };
}

/// يصفّي الفنيين حسب [userCity] من ملف المستخدم؛ `all` أو فراغ = كل القائمة.
/// الفني بـ `city` من `all` / `all_jordan` يُعرض للجميع.
List<TechnicianProfile> filterTechniciansByProfileCity(
  List<TechnicianProfile> techs,
  String? userCity,
) {
  final u = userCity?.trim();
  if (u == null || u.isEmpty || u == 'all') return techs;
  return techs.where((t) {
    final c = t.city?.trim();
    if (c == null || c.isEmpty) return true;
    if (c == 'all' || c == 'all_jordan') return true;
    return c == u;
  }).toList();
}

/// طلب خدمة من الخادم.
class ServiceRequest {
  ServiceRequest({
    required this.id,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerEmail,
    required this.title,
    this.description,
    required this.categoryId,
    this.categoryName,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.assignedTechnicianId,
    this.assignedTechnicianEmail,
    this.adminNote,
    this.notes,
    this.imageUrl,
    this.chatId,
  });

  final String id;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;
  final String title;
  final String? description;
  final String categoryId;
  final String? categoryName;
  final String status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? assignedTechnicianId;
  final String? assignedTechnicianEmail;
  final String? adminNote;
  final String? notes;
  final String? imageUrl;
  final String? chatId;

  factory ServiceRequest.fromMap(String id, Map<String, dynamic> d) {
    DateTime _parseDate(dynamic value) {
      if (value is String && value.trim().isNotEmpty) {
        return DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
      }
      try {
        final sec = (value as dynamic).seconds;
        if (sec is int) return DateTime.fromMillisecondsSinceEpoch(sec * 1000);
      } on Object {
        // Keep current-time fallback when timestamp shape is unknown.
      }
      return DateTime.now();
    }
    final created = _parseDate(d['createdAt']);
    final updatedRaw = d['updatedAt'];
    final DateTime? updated = updatedRaw == null ? null : _parseDate(updatedRaw);
    return ServiceRequest(
      id: id,
      customerId: d['customerId'] as String?,
      customerName: d['customerName'] as String?,
      customerPhone: d['customerPhone'] as String?,
      customerEmail: d['customerEmail'] as String?,
      title: d['title'] as String? ?? 'طلب',
      description: d['description'] as String?,
      categoryId: d['categoryId'] as String? ?? '',
      categoryName: d['categoryNameAr'] as String? ?? d['categoryName'] as String?,
      status: d['status'] as String? ?? 'pending',
      createdAt: created,
      updatedAt: updated,
      assignedTechnicianId: d['assignedTechnicianId'] as String?,
      assignedTechnicianEmail: d['assignedTechnicianEmail'] as String?,
      adminNote: d['adminNote'] as String?,
      notes: d['notes'] as String?,
      imageUrl: d['imageUrl'] as String?,
      chatId: d['chatId'] as String?,
    );
  }
}

