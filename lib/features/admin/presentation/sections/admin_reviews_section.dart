import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/contracts/feature_unit.dart';
import '../../../../core/widgets/feature_state_builder.dart';
import '../../../reviews/data/reviews_repository.dart';
import '../../../reviews/domain/review_model.dart';

class AdminReviewsSection extends StatefulWidget {
  const AdminReviewsSection({super.key});

  @override
  State<AdminReviewsSection> createState() => _AdminReviewsSectionState();
}

class _AdminReviewsSectionState extends State<AdminReviewsSection> {
  String _type = 'store';
  late Future<FeatureState<List<ReviewModel>>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _deleteReview(String reviewId) async {
    setState(() => _busy = true);
    final state = await ReviewsRepository.instance.deleteReview(reviewId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _future = _load();
    });
    final msg = state is FeatureSuccess ? 'تم حذف التقييم' : (state as FeatureFailure<FeatureUnit>).message;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: GoogleFonts.tajawal())));
  }

  Future<void> _moderateReview(ReviewModel review) async {
    final ctrl = TextEditingController(text: review.comment);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعديل تعليق التقييم', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          textAlign: TextAlign.right,
          decoration: InputDecoration(hintText: 'اكتب التعليق المعدّل', hintStyle: GoogleFonts.tajawal()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.tajawal())),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('حفظ', style: GoogleFonts.tajawal()),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null) return;
    setState(() => _busy = true);
    final state = await ReviewsRepository.instance.addReply(
      reviewId: review.id,
      authorId: 'admin',
      authorName: 'admin',
      text: text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _future = _load();
    });
    final msg = state is FeatureSuccess ? 'تم تحديث التعليق' : (state as FeatureFailure<FeatureUnit>).message;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: GoogleFonts.tajawal())));
  }

  Future<FeatureState<List<ReviewModel>>> _load() async {
    return ReviewsRepository.instance
        .watchByTargetTypeForAdmin(targetType: _type, limit: 50)
        .first;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: DropdownButtonFormField<String>(
            initialValue: _type,
            items: const [
              DropdownMenuItem(value: 'store', child: Text('مراجعات المتاجر')),
              DropdownMenuItem(value: 'product', child: Text('مراجعات المنتجات')),
              DropdownMenuItem(value: 'wholesaler', child: Text('مراجعات الجملة')),
            ],
            onChanged: (v) {
              setState(() {
                _type = v ?? 'store';
                _future = _load();
              });
            },
          ),
        ),
        Expanded(
          child: FutureBuilder<FeatureState<List<ReviewModel>>>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return buildFeatureStateUi<List<ReviewModel>>(
                context: context,
                state: snap.data!,
                dataBuilder: (context, items) {
                  if (items.isEmpty) {
                    return Center(child: Text('لا توجد مراجعات حالياً', style: GoogleFonts.tajawal()));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final r = items[i];
                      return Card(
                        child: ListTile(
                          title: Text(
                            '${r.userName} • ${r.rating.toStringAsFixed(1)}★',
                            style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            'الهدف: ${r.targetType} (${r.targetId})\n${r.comment}',
                            style: GoogleFonts.tajawal(fontSize: 12),
                            textAlign: TextAlign.right,
                          ),
                          trailing: _busy
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'edit') {
                                      _moderateReview(r);
                                      return;
                                    }
                                    if (v == 'delete') {
                                      _deleteReview(r.id);
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    PopupMenuItem(value: 'edit', child: Text('تعديل التعليق', style: GoogleFonts.tajawal())),
                                    PopupMenuItem(value: 'delete', child: Text('حذف التقييم', style: GoogleFonts.tajawal())),
                                  ],
                                ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
