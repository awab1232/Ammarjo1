import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/contracts/feature_state.dart';
import '../../../core/firebase/chat_firebase_sync.dart';
import '../../../core/firebase/phone_auth_service.dart';
import '../../../core/utils/jordan_phone.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_bar_back_button.dart';
import '../../../core/widgets/empty_state_widget.dart';
import 'listing_peer_chat_dialer.dart';
import '../../store/domain/models.dart';
import '../../store/presentation/store_controller.dart';
import '../data/unified_chat_repository.dart';
import '../domain/unified_chat_models.dart';
import 'unified_chat_page.dart';

/// صندوق الوارد — كل المحادثات النشطة (سوق + فنيين).
class MessagesInboxPage extends StatelessWidget {
  const MessagesInboxPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreController>();
    var email = store.profile?.email.trim() ?? '';
    final u = FirebaseAuth.instance.currentUser;
    if (email.isEmpty && u != null) {
      final un = PhoneAuthService.jordanUsernameFromFirebaseUser(u);
      if (un != null) email = syntheticEmailForPhone(un);
    }
    final signedIn = u != null || email.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        leading: Navigator.of(context).canPop() ? const AppBarBackButton() : null,
        title: Text('الرسائل', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, color: AppColors.heading)),
      ),
      body: !signedIn
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'سجّل الدخول لعرض محادثاتك.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                ),
              ),
            )
          : Firebase.apps.isEmpty
              ? Center(child: Text('Firebase غير جاهز.', style: GoogleFonts.tajawal(color: AppColors.textSecondary)))
              : FutureBuilder<void>(
                  future: syncChatFirebaseIdentity(
                    store.profile ?? (email.isNotEmpty ? CustomerProfile(email: email) : null),
                  ),
                  builder: (context, ready) {
                    if (ready.connectionState != ConnectionState.done) {
                      return const Center(
                        child: CircularProgressIndicator(color: AppColors.orange),
                      );
                    }
                    return StreamBuilder<FeatureState<List<UnifiedChatThread>>>(
                      stream: UnifiedChatRepository.instance.watchInbox(email),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'تعذّر تحميل المحادثات. إذا استمر الخطأ: راجع قواعد Firestore لمجموعة unified_chats وتأكد من نشر uid في firebase_uid_by_email.\n${snap.error}',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                              ),
                            ),
                          );
                        }
                        final list = switch (snap.data) {
                          FeatureSuccess(:final data) => data,
                          _ => <UnifiedChatThread>[],
                        };
                        if (list.isEmpty) {
                          return const EmptyStateWidget(
                            type: EmptyStateType.chat,
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: list.length,
                          separatorBuilder: (context, _) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final t = list[i];
                            final phone = t.peerPhoneForViewer(email) ?? '';
                            return Material(
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: const BorderSide(color: AppColors.border),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.accentLight,
                                  child: Icon(
                                    switch (t.kind) {
                                      UnifiedChatKind.storeCustomer => Icons.store_mall_directory_outlined,
                                      UnifiedChatKind.homeStoreCustomer => Icons.home_work_outlined,
                                      UnifiedChatKind.technicianCustomer => Icons.engineering_outlined,
                                      UnifiedChatKind.support => Icons.support_agent_outlined,
                                    },
                                    color: AppColors.accent,
                                  ),
                                ),
                                title: Text(
                                  t.contextTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
                                ),
                                subtitle: Text(
                                  t.lastMessagePreview,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (phone.isNotEmpty)
                                      IconButton(
                                        tooltip: 'اتصال',
                                        onPressed: () => launchSellerPhoneDialer(context, phone),
                                        icon: const Icon(Icons.phone_in_talk_rounded, color: AppColors.accent),
                                      ),
                                    const Icon(Icons.chevron_left, color: AppColors.textSecondary),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) => UnifiedChatPage.resume(
                                        existingChatId: t.id,
                                        threadTitle: t.contextTitle,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
    );
  }
}
