import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/contracts/feature_unit.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/admin_repository.dart';
import 'admin_rest_widgets.dart';

class AdminProductsSection extends StatefulWidget {
  const AdminProductsSection({super.key});

  @override
  State<AdminProductsSection> createState() => _AdminProductsSectionState();
}

class _AdminProductsSectionState extends State<AdminProductsSection> {
  Future<void> _openBulkStockDialog() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Bulk Stock', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'أدخل كل سطر بالشكل: productId:stock',
              style: GoogleFonts.tajawal(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 10,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('تحديث')),
        ],
      ),
    );
    if (ok != true) return;
    final lines = ctrl.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final items = <Map<String, dynamic>>[];
    for (final line in lines) {
      final p = line.split(':');
      if (p.length != 2) continue;
      final id = p[0].trim();
      final stock = int.tryParse(p[1].trim());
      if (id.isEmpty || stock == null) continue;
      items.add({'id': id, 'stock': stock});
    }
    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('صيغة الإدخال غير صحيحة')));
      return;
    }
    final state = await AdminRepository.instance.bulkUpdateMarketplaceStock(items);
    if (!mounted) return;
    if (state is FeatureFailure<FeatureUnit>) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث المخزون بنجاح')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'إدارة المنتجات (Marketplace)',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 17),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _openBulkStockDialog,
                icon: const Icon(Icons.inventory),
                label: const Text('Bulk Stock'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: AdminCrudSection(
            title: 'CRUD المنتجات',
            fields: const [
              CrudFieldDef(key: 'name', label: 'الاسم', required: true),
              CrudFieldDef(key: 'storeId', label: 'Store ID', required: true, readItemKey: 'store_id'),
              CrudFieldDef(key: 'subCategoryId', label: 'Sub Category ID', readItemKey: 'sub_category_id'),
              CrudFieldDef(key: 'price', label: 'السعر', required: true),
              CrudFieldDef(key: 'stock', label: 'المخزون'),
              CrudFieldDef(key: 'isActive', label: 'isActive (true/false)'),
              CrudFieldDef(key: 'image', label: 'الصورة', readItemKey: 'image'),
              CrudFieldDef(key: 'description', label: 'الوصف'),
            ],
            loadItems: () => AdminRepository.instance.fetchMarketplaceProducts(),
            onCreate: (v) => AdminRepository.instance.createMarketplaceProduct(
              storeId: v['storeId'] ?? '',
              subCategoryId: (v['subCategoryId'] ?? '').trim().isEmpty ? null : v['subCategoryId'],
              name: v['name'] ?? '',
              description: v['description'],
              price: double.tryParse(v['price'] ?? ''),
              image: v['image'],
              stock: int.tryParse(v['stock'] ?? ''),
              isActive: (v['isActive'] ?? 'true').trim().toLowerCase() != 'false',
            ),
            onUpdate: (item, v) => AdminRepository.instance.updateMarketplaceProduct(
              item['id'].toString(),
              storeId: v['storeId'],
              subCategoryId: (v['subCategoryId'] ?? '').trim().isEmpty ? null : v['subCategoryId'],
              name: v['name'],
              description: v['description'],
              price: double.tryParse(v['price'] ?? ''),
              image: v['image'],
              stock: int.tryParse(v['stock'] ?? ''),
              isActive: (v['isActive'] ?? '').trim().isEmpty ? null : (v['isActive']!.trim().toLowerCase() == 'true'),
            ),
            onDelete: (item) => AdminRepository.instance.deleteMarketplaceProduct(item['id'].toString()),
          ),
        ),
      ],
    );
  }
}
