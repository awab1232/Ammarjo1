class StoreTypeModel {
  const StoreTypeModel({
    required this.id,
    required this.name,
    required this.key,
    this.icon,
    this.image,
    this.displayOrder = 0,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String key;
  final String? icon;
  final String? image;
  final int displayOrder;
  final bool isActive;

  factory StoreTypeModel.fromMap(Map<String, dynamic> raw) {
    return StoreTypeModel(
      id: raw['id']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      name: raw['name']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      key: raw['key']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      icon: raw['icon']?.toString(),
      image: raw['image']?.toString(),
      displayOrder: (raw['displayOrder'] as num?)?.toInt() ?? 0,
      isActive: raw['isActive'] != false,
    );
  }
}
