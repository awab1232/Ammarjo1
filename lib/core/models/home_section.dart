class HomeSection {
  final String id;
  final String name;
  final String? image;
  final String type;

  const HomeSection({
    required this.id,
    required this.name,
    required this.type,
    this.image,
  });

  factory HomeSection.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    final type = json['type']?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty || type.isEmpty) {
      throw const FormatException('INVALID_HOME_SECTION_PAYLOAD');
    }
    return HomeSection(
      id: id,
      name: name,
      type: type,
      image: json['image']?.toString(),
    );
  }
}
