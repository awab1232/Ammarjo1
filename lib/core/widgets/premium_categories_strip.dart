import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ammar_cached_image.dart';

/// شريط تصنيفات أفقي — تصميم موحّد (المتاجر، الصيانة، …).
class PremiumCategoriesStrip extends StatelessWidget {
  const PremiumCategoriesStrip({
    super.key,
    required this.categories,
    required this.selectedName,
    this.selectedId,
    required this.onSelect,
    this.height = 100,
    this.itemWidth = 70,
  });

  final List<Map<String, dynamic>> categories;
  final String selectedName;
  /// معرّف مستند التصنيف في Firestore (إن وُجد) — يُفضّل للتمييز عند تطابق الأسماء.
  final String? selectedId;
  final void Function(String name, String? categoryDocId) onSelect;
  final double height;
  final double itemWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        itemBuilder: (ctx, i) {
          final cat = categories[i];
          final name = cat['name'] as String;
          final imageUrl = cat['imageUrl'] as String?;
          final id = cat['id'] as String?;
          final bool isSelected;
          if (id != null && selectedId != null && selectedId!.isNotEmpty) {
            isSelected = selectedId == id;
          } else if (name == 'الكل') {
            isSelected = (selectedId == null || selectedId!.isEmpty) && selectedName == 'الكل';
          } else {
            isSelected = selectedName == name;
          }

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onSelect(name, id);
            },
            child: Container(
              width: itemWidth,
              margin: const EdgeInsets.only(left: 12),
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? const Color(0xFFE8471A) : Colors.transparent,
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isSelected
                              ? const Color(0xFFE8471A).withValues(alpha: 0.3)
                              : Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: imageUrl != null && imageUrl.isNotEmpty
                          ? AmmarCachedImage(imageUrl: imageUrl, fit: BoxFit.cover)
                          : Container(
                              color: const Color(0xFFF5F5F5),
                              child: const Icon(
                                Icons.category_rounded,
                                color: Color(0xFFE8471A),
                                size: 28,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.tajawal(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                      color: isSelected ? const Color(0xFFE8471A) : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
