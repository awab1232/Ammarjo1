import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/admin_repository.dart';
import 'admin_rest_widgets.dart';

class AdminSubCategoriesSection extends StatefulWidget {
  const AdminSubCategoriesSection({super.key});

  @override
  State<AdminSubCategoriesSection> createState() =>
      _AdminSubCategoriesSectionState();
}

class _AdminSubCategoriesSectionState extends State<AdminSubCategoriesSection> {
  String _activeSectionId = '';
  List<Map<String, dynamic>> _homeSections = List<Map<String, dynamic>>.empty(
    growable: false,
  );
  bool _loadingSections = true;

  @override
  void initState() {
    super.initState();
    _loadSections();
  }

  Future<void> _loadSections() async {
    setState(() => _loadingSections = true);
    final state = await AdminRepository.instance.fetchHomeSections();
    if (!mounted) return;
    switch (state) {
      case FeatureSuccess(:final data):
        setState(() {
          _homeSections = data;
          _loadingSections = false;
          if (_activeSectionId.isEmpty && data.isNotEmpty) {
            _activeSectionId = data.first['id']?.toString() ?? '';
          }
        });
      default:
        setState(() {
          _homeSections = List<Map<String, dynamic>>.empty(growable: false);
          _loadingSections = false;
        });
    }
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
                child: DropdownButtonFormField<String>(
                  value: _activeSectionId.isEmpty ? null : _activeSectionId,
                  items: _homeSections
                      .map(
                        (e) => DropdownMenuItem<String>(
                          value: e['id']?.toString() ?? '',
                          child: Text(e['name']?.toString() ?? '—'),
                        ),
                      )
                      .toList(),
                  onChanged: _loadingSections
                      ? null
                      : (v) {
                          setState(() => _activeSectionId = (v ?? '').trim());
                        },
                  decoration: const InputDecoration(
                    labelText: 'القسم الرئيسي (مطلوب)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingSections
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.orange),
                )
              : _activeSectionId.isEmpty
              ? Center(
                  child: Text(
                    'يجب اختيار قسم رئيسي أولاً',
                    style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                  ),
                )
              : AdminCrudSection(
                  key: ValueKey<String>(_activeSectionId),
                  title: 'إدارة الأقسام الفرعية',
                  fields: const [
                    CrudFieldDef(key: 'name', label: 'الاسم', required: true),
                    CrudFieldDef(key: 'image', label: 'الصورة'),
                    CrudFieldDef(
                      key: 'sortOrder',
                      label: 'sortOrder',
                      readItemKey: 'sortOrder',
                    ),
                    CrudFieldDef(
                      key: 'isActive',
                      label: 'isActive (true/false)',
                      readItemKey: 'isActive',
                    ),
                  ],
                  loadItems: () => AdminRepository.instance.fetchSubCategories(
                    sectionId: _activeSectionId,
                  ),
                  onCreate: (v) => AdminRepository.instance.createSubCategory(
                    homeSectionId: _activeSectionId,
                    name: v['name'] ?? '',
                    image: (v['image'] ?? '').isEmpty ? null : v['image'],
                    sortOrder: int.tryParse(v['sortOrder'] ?? '') ?? 0,
                    isActive:
                        (v['isActive'] ?? 'true').trim().toLowerCase() !=
                        'false',
                  ),
                  onUpdate: (item, v) =>
                      AdminRepository.instance.updateSubCategory(
                        item['id'].toString(),
                        name: v['name'],
                        image: (v['image'] ?? '').isEmpty ? null : v['image'],
                        sortOrder: int.tryParse(v['sortOrder'] ?? ''),
                        isActive: (v['isActive'] ?? '').isEmpty
                            ? null
                            : (v['isActive']!.trim().toLowerCase() == 'true'),
                      ),
                  onDelete: (item) => AdminRepository.instance
                      .deleteSubCategory(item['id'].toString()),
                ),
        ),
      ],
    );
  }
}
