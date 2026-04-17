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
    this.height = 110,
    this.itemWidth = 85,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: itemWidth,
              margin: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? const Color(0xFFFF6B00) : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected ? const Color(0xFFFF6B00).withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.08),
                    blurRadius: isSelected ? 12 : 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl != null && imageUrl.isNotEmpty)
                      AmmarCachedImage(imageUrl: imageUrl, fit: BoxFit.cover)
                    else
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isSelected
                                ? const [Color(0xFFFF6B00), Color(0xFFE65100)]
                                : const [Color(0xFF2C2C54), Color(0xFF1A1A2E)],
                          ),
                        ),
                      ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Positioned(
                        top: 6,
                        right: 6,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFFFF6B00),
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(Icons.check, color: Colors.white, size: 12),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.tajawal(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
