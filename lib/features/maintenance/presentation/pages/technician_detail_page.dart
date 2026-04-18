import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/contracts/feature_unit.dart';
import '../../../../core/services/chat_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/widgets/home_page_shimmers.dart';
import '../../../communication/presentation/unified_chat_page.dart';
import '../../../communication/presentation/widgets/unified_communication_bar.dart';
import '../../../communication/presentation/listing_peer_chat_dialer.dart';
import '../../../store/presentation/store_controller.dart';
import '../../domain/maintenance_models.dart';
import '../../../reviews/data/reviews_repository.dart';
import '../../../reviews/domain/review_model.dart';

/// تفاصيل فني + شريط تواصل (دردشة + اتصال).
class TechnicianDetailPage extends StatelessWidget {
  const TechnicianDetailPage({
    super.key,
    required this.tech,
    required this.categoryHint,
    required this.onBookService,
  });

  final TechnicianProfile tech;
  final String categoryHint;
  final VoidCallback onBookService;

  void _startChat(BuildContext context) {
    final store = context.read<StoreController>();
    if (store.profile?.email.trim().isEmpty ?? true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('سجّل الدخول لبدء المحادثة.', style: GoogleFonts.tajawal())),
      );
      return;
    }
    if (Firebase.apps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Firebase غير جاهز.', style: GoogleFonts.tajawal())),
      );
      return;
    }
    final te = (tech.email ?? '').trim();
    if (te.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('هذا الفني غير موصول ببريد للمحادثة.', style: GoogleFonts.tajawal())),
      );
      return;
    }
    final myEmail = store.profile?.email.trim() ?? '';
    final myPhone = store.profile?.phoneLocal?.trim() ?? '';
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DialogLoadingPanel(message: 'جاري فتح المحادثة…'),
    );
    ChatService()
        .getOrCreateChat(
          otherUserId: tech.id,
          otherUserName: tech.displayName,
          currentUserEmail: myEmail,
          currentUserPhone: myPhone,
          otherUserEmail: te,
          otherUserPhone: (tech.phone ?? '').trim(),
          chatType: 'technician',
          referenceId: tech.id,
          referenceName: tech.displayName,
          referenceImageUrl: tech.photoUrl,
        )
        .then((chatId) async {
          if (context.mounted) Navigator.of(context).pop();
          if (!context.mounted) return;
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => UnifiedChatPage.resume(
                existingChatId: chatId,
                threadTitle: tech.displayName,
              ),
            ),
          );
        })
        .catchError((e) {
          if (context.mounted) Navigator.of(context).pop();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('خطأ في فتح المحادثة: $e', style: GoogleFonts.tajawal())),
            );
          }
        });
  }

  void _call(BuildContext context) {
    final p = tech.phone?.trim() ?? '';
    launchSellerPhoneDialer(context, p);
  }

  @override
  Widget build(BuildContext context) {
    final phone = tech.phone?.trim() ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: const AppBarBackButton(),
        title: Text(tech.displayName, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {},
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                Center(
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.surfaceSecondary,
                    child: (tech.photoUrl != null && tech.photoUrl!.isNotEmpty)
                        ? ClipOval(
                            child: Image.network(
                              tech.photoUrl!,
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(Icons.engineering_rounded, size: 40, color: AppColors.navy),
                            ),
                          )
                        : Icon(Icons.engineering_rounded, size: 40, color: AppColors.navy),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  tech.displayName,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.heading),
                ),
                const SizedBox(height: 8),
                Text(
                  tech.specialties.join(' · '),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                FutureBuilder<FeatureState<RatingAggregate>>(
                  future: ReviewsRepository.instance.getAggregate(targetId: tech.id, targetType: 'technician'),
                  builder: (context, snap) {
                    final data = snap.data;
                    final avg = data is FeatureSuccess<RatingAggregate>
                        ? data.data.averageRating
                        : tech.rating;
                    final stars = avg.round().clamp(0, 5);
                    return Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ...List.generate(
                              5,
                              (i) => Icon(
                                i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                                color: AppColors.accent,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              avg.toStringAsFixed(1),
                              style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, color: AppColors.accent),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _TechnicianUserRatingRow(tech: tech),
                      ],
                    );
                  },
                ),
                if (tech.bio != null && tech.bio!.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(tech.bio!, style: GoogleFonts.tajawal(height: 1.45)),
                ],
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.place_outlined, color: AppColors.accent),
                  title: Text('${tech.city ?? tech.locationLabel} · ~${tech.distanceKm.toStringAsFixed(1)} كم', style: GoogleFonts.tajawal()),
                ),
                if (phone.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.phone_rounded, color: AppColors.accent),
                    title: Text(phone, style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: onBookService,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.event_available_outlined),
                    label: Text('احجز خدمة الآن', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                  ),
                ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
          UnifiedCommunicationBar(
            onChat: () => _startChat(context),
            onCall: () => _call(context),
            callEnabled: phone.isNotEmpty,
          ),
        ],
      ),
    );
  }
}

class _TechnicianUserRatingRow extends StatelessWidget {
  const _TechnicianUserRatingRow({required this.tech});

  final TechnicianProfile tech;

  Future<void> _submit(BuildContext context, int rating, String uid, String userName) async {
    try {
      final state = await ReviewsRepository.instance.createReview(
        targetId: tech.id,
        targetType: 'technician',
        userId: uid,
        userName: userName,
        rating: rating.toDouble(),
        comment: '',
      );
      if (state is! FeatureSuccess) {
        if (context.mounted) {
          final msg = state is FeatureFailure<FeatureUnit> ? state.message : 'تعذر حفظ التقييم.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg, style: GoogleFonts.tajawal())),
          );
        }
        return;
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('شكراً على تقييمك! ⭐', style: GoogleFonts.tajawal()),
          backgroundColor: AppColors.accent,
        ),
      );
    } on Object {
      debugPrint('_TechnicianUserRatingRow._submit failed.');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر حفظ التقييم.', style: GoogleFonts.tajawal())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final store = context.read<StoreController>();
    if (uid == null) {
      return TextButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('سجّل الدخول لتقييم الفني.', style: GoogleFonts.tajawal())),
          );
        },
        child: Text('سجّل الدخول لتقييم الفني', style: GoogleFonts.tajawal(color: AppColors.accent)),
      );
    }
    final myEmail = store.profile?.email.trim().toLowerCase() ?? '';
    final techEmail = tech.email?.trim().toLowerCase() ?? '';
    if (myEmail.isNotEmpty && techEmail.isNotEmpty && myEmail == techEmail) {
      return const SizedBox.shrink();
    }
    final userName = (store.profile?.fullName?.trim().isNotEmpty ?? false)
        ? store.profile!.fullName!.trim()
        : 'مستخدم';

    return Column(
      children: [
        Text('قيّم هذا الفني', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            5,
            (i) => IconButton(
              icon: Icon(
                Icons.star_border,
                color: AppColors.accent,
                size: 30,
              ),
              onPressed: () => _submit(context, i + 1, uid, userName),
            ),
          ),
        ),
      ],
    );
  }
}

