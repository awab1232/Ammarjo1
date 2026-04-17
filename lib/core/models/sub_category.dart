class SubCategory {
  final String id;
  final String name;
  final String? image;
  final String sectionId;

  const SubCategory({
    required this.id,
    required this.name,
    required this.sectionId,
    this.image,
  });

  factory SubCategory.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    final sectionId = json['home_section_id']?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty || sectionId.isEmpty) {
      throw const FormatException('INVALID_SUB_CATEGORY_PAYLOAD');
    }
    return SubCategory(
      id: id,
      name: name,
      sectionId: sectionId,
      image: json['image']?.toString(),
    );
  }
}
