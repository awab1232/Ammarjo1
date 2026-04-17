import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/chat_service.dart';
import '../../store/presentation/store_controller.dart';
import '../domain/marketplace_listing_chat_models.dart';
import 'unified_chat_page.dart';

/// فتح محادثة داخل التطبيق لإعلان قديم (`used_items`).
void openUsedListingInAppChat(BuildContext context, MarketplaceListing listing) {
  final store = context.read<StoreController>();
  final me = store.profile?.email.trim().toLowerCase() ?? '';
  if (me.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('سجّل الدخول لبدء المحادثة.', style: GoogleFonts.cairo())),
    );
    return;
  }
  if (resolvePeerEmailForListing(listing).toLowerCase() == me) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('هذا إعلانك — لا يمكنك مراسلة نفسك.', style: GoogleFonts.cairo())),
    );
    return;
  }
  if (Firebase.apps.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Firebase غير جاهز.', style: GoogleFonts.cairo())),
    );
    return;
  }
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: CircularProgressIndicator(color: Color(0xFFFF6B00)),
    ),
  );
  ChatService()
      .getOrCreateChat(
        otherUserId: listing.sellerId ?? resolvePeerEmailForListing(listing),
        otherUserName: listing.title,
        currentUserEmail: me,
        currentUserPhone: store.profile?.phoneLocal?.trim() ?? '',
        otherUserEmail: resolvePeerEmailForListing(listing),
        otherUserPhone: listing.phone,
        chatType: 'used_market',
        referenceId: listing.id,
        referenceName: listing.title,
        referenceImageUrl: listing.imageUrl,
        seedProductCard: true,
        productCardTitle: listing.title,
        productCardPrice: listing.priceLabel,
        productCardImageUrl: listing.imageUrl,
      )
      .then((chatId) async {
        if (context.mounted) Navigator.of(context).pop();
        if (!context.mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => UnifiedChatPage.resume(
              existingChatId: chatId,
              threadTitle: listing.title,
            ),
          ),
        );
      })
      .catchError((e) {
        if (context.mounted) Navigator.of(context).pop();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ في فتح المحادثة: $e', style: GoogleFonts.cairo())),
          );
        }
      });
}

Future<void> launchSellerPhoneDialer(BuildContext context, String phone) async {
  final t = phone.trim();
  if (t.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يتوفر رقم للاتصال')));
    }
    return;
  }
  final uri = Uri.parse('tel:${Uri.encodeComponent(t)}');
  try {
    final ok = await canLaunchUrl(uri);
    if (ok) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر فتح تطبيق الاتصال')));
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر الاتصال بهذا الرقم')));
    }
  }
}
