import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/config/chat_feature_config.dart';
import '../../../core/firebase/phone_auth_service.dart';
import '../../../core/utils/jordan_phone.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_bar_back_button.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../store/presentation/store_controller.dart';

/// صندوق الوارد — كل المحادثات النشطة (سوق + فنيين).
class MessagesInboxPage extends StatelessWidget {
  const MessagesInboxPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kChatFeatureEnabled) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
          leading: Navigator.of(context).canPop() ? const AppBarBackButton() : null,
          title: Text('الرسائل', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, color: AppColors.heading)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              kChatFeatureUnavailableMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }
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
          : const EmptyStateWidget(type: EmptyStateType.chat),
    );
  }
}
