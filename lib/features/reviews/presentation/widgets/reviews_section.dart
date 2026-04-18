import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/contracts/feature_state.dart';
import '../../../../core/contracts/feature_unit.dart';
import '../../../../core/widgets/empty_state_widget.dart';
import '../../data/reviews_repository.dart';
import '../../domain/review_model.dart';

class ReviewsSection extends StatefulWidget {
  const ReviewsSection({
    super.key,
    required this.targetId,
    required this.targetType,
    required this.title,
    this.canReply = false,
    this.canDeleteReviews = false,
    this.emptyText = 'لا توجد مراجعات بعد',
    this.productWooIdForPurchaseCheck,
  });

  final String targetId;
  final String targetType;
  final String title;
  final bool canReply;
  final bool canDeleteReviews;
  final String emptyText;
  final int? productWooIdForPurchaseCheck;

  @override
  State<ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<ReviewsSection> {
  double _myRating = 5;
  final TextEditingController _comment = TextEditingController();
  bool _saving = false;
  bool _loading = true;
  String? _error;
  List<ReviewModel> _items = const <ReviewModel>[];
  RatingAggregate _aggregate = const RatingAggregate(averageRating: 0, totalReviews: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reviewsState = await ReviewsRepository.instance.getReviews(
        targetId: widget.targetId,
        targetType: widget.targetType,
      );
      final aggState = await ReviewsRepository.instance.getAggregate(
        targetId: widget.targetId,
        targetType: widget.targetType,
      );
      if (reviewsState is! FeatureSuccess<List<ReviewModel>>) {
        final msg = (reviewsState is FeatureFailure<List<ReviewModel>>)
            ? reviewsState.message
            : 'تعذر تحميل التقييمات حالياً.';
        if (!mounted) return;
        setState(() => _error = msg);
        return;
      }
      if (aggState is! FeatureSuccess<RatingAggregate>) {
        final msg = (aggState is FeatureFailure<RatingAggregate>)
            ? aggState.message
            : 'تعذر تحميل ملخص التقييمات.';
        if (!mounted) return;
        setState(() => _error = msg);
        return;
      }
      final ids = <String>{};
      final deduped = reviewsState.data.where((r) => ids.add(r.id)).toList();
      if (!mounted) return;
      setState(() {
        _items = deduped;
        _aggregate = aggState.data;
      });
    } on Object catch (e, st) {
      debugPrint('[ReviewsSection] _load: $e\n$st');
      if (!mounted) return;
      setState(() => _error = 'تعذر تحميل التقييمات حالياً.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      final createState = await ReviewsRepository.instance.createReview(
        targetId: widget.targetId,
        targetType: widget.targetType,
        userId: user.uid,
        userName: user.displayName?.trim().isNotEmpty == true ? user.displayName!.trim() : 'مستخدم',
        rating: _myRating,
        comment: _comment.text,
      );
      if (createState is! FeatureSuccess) {
        if (!mounted) return;
        final msg = (createState is FeatureFailure<FeatureUnit>)
            ? createState.message
            : 'تعذر إرسال التقييم حالياً';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg, style: GoogleFonts.tajawal())),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إرسال التقييم بنجاح', style: GoogleFonts.tajawal())),
      );
      _comment.clear();
      await _load();
    } on Object catch (e, st) {
      debugPrint('[ReviewsSection] createReview: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إرسال التقييم حالياً', style: GoogleFonts.tajawal())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (_loading) return _shimmer();
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16), textAlign: TextAlign.right),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('(${_aggregate.totalReviews})', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
                    const SizedBox(width: 6),
                    Text(_aggregate.averageRating.toStringAsFixed(1), style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    const Icon(Icons.star, color: Colors.amber),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.tajawal(color: AppColors.error)),
                ],
                const SizedBox(height: 8),
                if (user != null) ...[
                  _PurchaseGatedReviewForm(
                    targetType: widget.targetType,
                    productWooId: widget.productWooIdForPurchaseCheck,
                    user: user,
                    myRating: _myRating,
                    onRatingChanged: (v) => setState(() => _myRating = v),
                    commentController: _comment,
                    saving: _saving,
                    onSubmit: _submit,
                  ),
                  const Divider(height: 20),
                ],
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: EmptyStateWidget(
                      type: EmptyStateType.reviews,
                      customTitle: widget.emptyText,
                    ),
                  )
                else
                  ..._items.map(
                    (review) => _ReviewTile(
                      review: review,
                      canReply: widget.canReply,
                      canDelete: widget.canDeleteReviews,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _shimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        margin: const EdgeInsets.only(top: 16),
        height: 180,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _PurchaseGatedReviewForm extends StatelessWidget {
  const _PurchaseGatedReviewForm({
    required this.targetType,
    required this.productWooId,
    required this.user,
    required this.myRating,
    required this.onRatingChanged,
    required this.commentController,
    required this.saving,
    required this.onSubmit,
  });

  final String targetType;
  final int? productWooId;
  final User user;
  final double myRating;
  final ValueChanged<double> onRatingChanged;
  final TextEditingController commentController;
  final bool saving;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final needPurchase = targetType == 'product' && productWooId != null;
    if (!needPurchase) {
      return _ReviewInputFields(
        myRating: myRating,
        onRatingChanged: onRatingChanged,
        commentController: commentController,
        saving: saving,
        onSubmit: onSubmit,
      );
    }
    return FutureBuilder<bool>(
      future: ReviewsRepository.instance.hasCustomerPurchasedProductWooId(
        customerUid: user.uid,
        productWooId: productWooId!,
      ),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryOrange),
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'تعذر التحقق من سجل الشراء. حاول لاحقاً.',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.35),
            ),
          );
        }
        if (snap.data != true) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'يمكنك تقييم هذا المنتج بعد شرائه وإتمام الطلب.',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.35),
            ),
          );
        }
        return _ReviewInputFields(
          myRating: myRating,
          onRatingChanged: onRatingChanged,
          commentController: commentController,
          saving: saving,
          onSubmit: onSubmit,
        );
      },
    );
  }
}

class _ReviewInputFields extends StatelessWidget {
  const _ReviewInputFields({
    required this.myRating,
    required this.onRatingChanged,
    required this.commentController,
    required this.saving,
    required this.onSubmit,
  });

  final double myRating;
  final ValueChanged<double> onRatingChanged;
  final TextEditingController commentController;
  final bool saving;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: List.generate(5, (i) {
            final value = (i + 1).toDouble();
            final selected = myRating >= value - 0.001;
            return InkWell(
              onTap: () => onRatingChanged(value),
              child: Icon(
                selected ? Icons.star_rounded : Icons.star_border_rounded,
                size: 32,
                color: Colors.amber,
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: commentController,
          textAlign: TextAlign.right,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'اكتب تعليقك',
            hintStyle: GoogleFonts.tajawal(),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: saving ? null : onSubmit,
            child: Text('إرسال التقييم', style: GoogleFonts.tajawal()),
          ),
        ),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review, required this.canReply, this.canDelete = false});
  final ReviewModel review;
  final bool canReply;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(review.userName, textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Text(review.rating.toStringAsFixed(1), style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
              const Icon(Icons.star, size: 16, color: Colors.amber),
            ],
          ),
          if (review.comment.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(review.comment, textAlign: TextAlign.right, style: GoogleFonts.tajawal()),
            ),
          if (canDelete || canReply)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'تم إيقاف حذف/ردود المراجعات في مرحلة الترحيل الحالية.',
                textAlign: TextAlign.right,
                style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

