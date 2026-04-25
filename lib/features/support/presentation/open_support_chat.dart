import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ammar_store/core/session/user_session.dart';

import '../../../core/firebase/user_notifications_repository.dart';
import '../../store/presentation/pages/login_page.dart';
import '../../store/presentation/store_controller.dart';
import '../data/support_chat_repository.dart';
import 'support_chat_page.dart';

String _displayNameFromStore(StoreController store) {
  final p = store.profile;
  if (p == null) return 'عميل';
  final f = p.fullName?.trim();
  if (f != null && f.isNotEmpty) return f;
  final a = '${p.firstName ?? ''} ${p.lastName ?? ''}'.trim();
  if (a.isNotEmpty) return a;
  return p.email;
}

/// يفتح محادثة الدعم: محادثة مفتوحة واحدة لكل مستخدم، أو إنشاء جديدة.
Future<void> openSupportChat(BuildContext context) async {
  if (!Firebase.apps.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Firebase غير جاهز.', style: GoogleFonts.tajawal())),
    );
    return;
  }
  final uid = UserSession.currentUid;
  if (!UserSession.isLoggedIn || uid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('سجّل الدخول لفتح محادثة الدعم.', style: GoogleFonts.tajawal()),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    );
    return;
  }

  final store = context.read<StoreController>();
  final name = _displayNameFromStore(store);

  try {
    final result = await SupportChatRepository.instance.findOrCreateOpenChat(
      uid: uid,
      userName: name,
    );
    if (result.created) {
      await UserNotificationsRepository.notifyAdminsNewSupportChat(
        customerName: name,
        preview: 'بدأ محادثة دعم جديدة',
      );
    }
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SupportChatPage(
          chatId: result.chatId,
          isAdmin: false,
        ),
      ),
    );
  } on Object {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعذّر فتح المحادثة. حاول مرة أخرى.', style: GoogleFonts.tajawal())),
    );
  }
}

