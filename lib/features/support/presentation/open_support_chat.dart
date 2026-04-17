import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/firebase/user_notifications_repository.dart';
import '../../store/presentation/pages/login_page.dart';
import '../../store/presentation/store_controller.dart';
import '../data/support_chat_repository.dart';
import 'support_chat_page.dart';

String _displayNameFromStore(StoreController store) {
  final p = store.profile;
  if (p == null) return 'Ã˜Â¹Ã™â€¦Ã™Å Ã™â€ž';
  final f = p.fullName?.trim();
  if (f != null && f.isNotEmpty) return f;
  final a = '${p.firstName ?? ''} ${p.lastName ?? ''}'.trim();
  if (a.isNotEmpty) return a;
  return p.email;
}

/// Ã™Å Ã™ÂÃ˜ÂªÃ˜Â­ Ã™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â¯Ã˜Â¹Ã™â€¦: Ã™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â© Ã™â€¦Ã™ÂÃ˜ÂªÃ™Ë†Ã˜Â­Ã˜Â© Ã™Ë†Ã˜Â§Ã˜Â­Ã˜Â¯Ã˜Â© Ã™â€žÃ™Æ’Ã™â€ž Ã™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦Ã˜Å’ Ã˜Â£Ã™Ë† Ã˜Â¥Ã™â€ Ã˜Â´Ã˜Â§Ã˜Â¡ Ã˜Â¬Ã˜Â¯Ã™Å Ã˜Â¯Ã˜Â©.
Future<void> openSupportChat(BuildContext context) async {
  if (!Firebase.apps.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Firebase Ã˜ÂºÃ™Å Ã˜Â± Ã˜Â¬Ã˜Â§Ã™â€¡Ã˜Â².', style: GoogleFonts.tajawal())),
    );
    return;
  }
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ã˜Â³Ã˜Â¬Ã™â€˜Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â¯Ã˜Â®Ã™Ë†Ã™â€ž Ã™â€žÃ™ÂÃ˜ÂªÃ˜Â­ Ã™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â¯Ã˜Â¹Ã™â€¦.', style: GoogleFonts.tajawal()),
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
      uid: user.uid,
      userName: name,
    );
    if (result.created) {
      await UserNotificationsRepository.notifyAdminsNewSupportChat(
        customerName: name,
        preview: 'Ã˜Â¨Ã˜Â¯Ã˜Â£ Ã™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â© Ã˜Â¯Ã˜Â¹Ã™â€¦ Ã˜Â¬Ã˜Â¯Ã™Å Ã˜Â¯Ã˜Â©',
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
      SnackBar(content: Text('Ã˜ÂªÃ˜Â¹Ã˜Â°Ã™â€˜Ã˜Â± Ã™ÂÃ˜ÂªÃ˜Â­ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â©: unexpected error', style: GoogleFonts.tajawal())),
    );
  }
}

