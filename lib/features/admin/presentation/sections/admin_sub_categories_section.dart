import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/admin_repository.dart';
import 'admin_rest_widgets.dart';

class AdminSubCategoriesSection extends StatefulWidget {
  const AdminSubCategoriesSection({super.key});

  @override
  State<AdminSubCategoriesSection> createState() => _AdminSubCategoriesSectionState();
}

class _AdminSubCategoriesSectionState extends State<AdminSubCategoriesSection> {
  final TextEditingController _sectionIdCtrl = TextEditingController();
  String _activeSectionId = '';

  @override
  void dispose() {
    _sectionIdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _sectionIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Home Section ID',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () {
                  setState(() => _activeSectionId = _sectionIdCtrl.text.trim());
                },
                child: const Text('تحميل'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _activeSectionId.isEmpty
              ? Center(
                  child: Text(
                    'أدخل Home Section ID أولاً',
                    style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                  ),
                )
              : AdminCrudSection(
                  key: ValueKey<String>(_activeSectionId),
                  title: 'إدارة الأقسام الفرعية',
                  fields: const [
                    CrudFieldDef(key: 'homeSectionId', label: 'Home Section ID', required: true, readItemKey: 'home_section_id'),
                    CrudFieldDef(key: 'name', label: 'الاسم', required: true),
                    CrudFieldDef(key: 'image', label: 'الصورة'),
                    CrudFieldDef(key: 'sortOrder', label: 'sortOrder', readItemKey: 'sortOrder'),
                    CrudFieldDef(key: 'isActive', label: 'isActive (true/false)', readItemKey: 'isActive'),
                  ],
                  loadItems: () => AdminRepository.instance.fetchSubCategories(sectionId: _activeSectionId),
                  onCreate: (v) => AdminRepository.instance.createSubCategory(
                    homeSectionId: (v['homeSectionId'] ?? '').isEmpty ? _activeSectionId : (v['homeSectionId'] ?? ''),
                    name: v['name'] ?? '',
                    image: (v['image'] ?? '').isEmpty ? null : v['image'],
                    sortOrder: int.tryParse(v['sortOrder'] ?? '') ?? 0,
                    isActive: (v['isActive'] ?? 'true').trim().toLowerCase() != 'false',
                  ),
                  onUpdate: (item, v) => AdminRepository.instance.updateSubCategory(
                    item['id'].toString(),
                    homeSectionId: (v['homeSectionId'] ?? '').isEmpty ? null : v['homeSectionId'],
                    name: v['name'],
                    image: (v['image'] ?? '').isEmpty ? null : v['image'],
                    sortOrder: int.tryParse(v['sortOrder'] ?? ''),
                    isActive: (v['isActive'] ?? '').isEmpty ? null : (v['isActive']!.trim().toLowerCase() == 'true'),
                  ),
                  onDelete: (item) => AdminRepository.instance.deleteSubCategory(item['id'].toString()),
                ),
        ),
      ],
    );
  }
}
