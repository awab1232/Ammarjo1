import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/services/backend_orders_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../store_detail_page.dart';
import '../../data/stores_repository.dart';
import '../../domain/store_model.dart';
import '../widgets/store_card.dart';

class CategoryPage extends StatefulWidget {
  const CategoryPage({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  final String categoryId;
  final String categoryName;

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loadingSubs = true;
  bool _loadingStores = false;
  String? _error;
  List<_SubCategoryVm> _subCategories = <_SubCategoryVm>[];
  String _selectedSubId = '';
  List<StoreModel> _stores = <StoreModel>[];

  @override
  void initState() {
    super.initState();
    _loadSubCategories();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSubCategories() async {
    setState(() {
      _loadingSubs = true;
      _error = null;
    });
    final state = await BackendOrdersClient.instance.fetchSubCategories(
      widget.categoryId,
    );
    if (!mounted) return;
    switch (state) {
      case FeatureSuccess(:final data):
        final rows = data
            .map(
              (s) => _SubCategoryVm(
                id: s.id,
                name: s.name,
                imageUrl: (s.image ?? '').trim(),
              ),
            )
            .toList();
        if (rows.isEmpty) {
          setState(() {
            _subCategories = <_SubCategoryVm>[];
            _selectedSubId = '';
            _stores = <StoreModel>[];
            _loadingSubs = false;
          });
          return;
        }
        final firstId = rows.first.id;
        setState(() {
          _subCategories = rows;
          _selectedSubId = firstId;
          _loadingSubs = false;
        });
        await _loadStores(firstId);
      case FeatureFailure(:final message):
        setState(() {
          _error = message;
          _loadingSubs = false;
        });
      default:
        setState(() {
          _error = 'تعذر تحميل التصنيفات الفرعية';
          _loadingSubs = false;
        });
    }
  }

  Future<void> _loadStores(String subCategoryId) async {
    setState(() => _loadingStores = true);
    final state = await StoresRepository.instance.getStoresBySubCategory(
      subCategoryId,
    );
    if (!mounted) return;
    switch (state) {
      case FeatureSuccess(:final data):
        setState(() {
          _stores = data;
          _loadingStores = false;
        });
      case FeatureFailure():
      default:
        setState(() {
          _stores = <StoreModel>[];
          _loadingStores = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filteredStores = _stores.where((s) {
      if (query.isEmpty) return true;
      return s.name.toLowerCase().contains(query) ||
          s.category.toLowerCase().contains(query);
    }).toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const AppBarBackButton(),
        title: Text(
          widget.categoryName,
          style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loadingSubs
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryOrange),
            )
          : _error != null
          ? Center(
              child: Text(
                _error!,
                style: GoogleFonts.tajawal(color: AppColors.textSecondary),
              ),
            )
          : _subCategories.isEmpty
          ? Center(
              child: Text(
                'لا توجد تصنيفات فرعية حالياً',
                style: GoogleFonts.tajawal(color: AppColors.textSecondary),
              ),
            )
          : Row(
              children: [
                SizedBox(
                  width: 100,
                  child: ListView.builder(
                    itemCount: _subCategories.length,
                    itemBuilder: (ctx, i) {
                      final sub = _subCategories[i];
                      final selected = _selectedSubId == sub.id;
                      return GestureDetector(
                        onTap: () async {
                          setState(() => _selectedSubId = sub.id);
                          await _loadStores(sub.id);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          color: selected
                              ? const Color(0xFFE8471A).withValues(alpha: 0.1)
                              : Colors.white,
                          child: Column(
                            children: [
                              if (sub.imageUrl.isNotEmpty)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    imageUrl: sub.imageUrl,
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              else
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.grey.shade100,
                                  ),
                                  child: const Icon(
                                    Icons.category_outlined,
                                    size: 18,
                                    color: AppColors.primaryOrange,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                sub.name,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.tajawal(
                                  fontSize: 11,
                                  color: selected
                                      ? const Color(0xFFE8471A)
                                      : Colors.black87,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              if (selected)
                                Container(
                                  height: 2,
                                  color: const Color(0xFFE8471A),
                                  margin: const EdgeInsets.only(top: 4),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(width: 1, color: Colors.grey.shade200),
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'ابحث في ${widget.categoryName}...',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _loadingStores
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primaryOrange,
                                ),
                              )
                            : filteredStores.isEmpty
                            ? Center(
                                child: Text(
                                  'لا توجد متاجر ضمن التصنيف الفرعي المختار',
                                  style: GoogleFonts.tajawal(
                                    color: AppColors.textSecondary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : ListView.builder(
                                itemCount: filteredStores.length,
                                itemBuilder: (ctx, i) {
                                  final store = filteredStores[i];
                                  return StoreCard(
                                    store: store,
                                    onTap: () => Navigator.push(
                                      ctx,
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            StoreDetailPage(store: store),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SubCategoryVm {
  const _SubCategoryVm({
    required this.id,
    required this.name,
    required this.imageUrl,
  });

  final String id;
  final String name;
  final String imageUrl;
}
