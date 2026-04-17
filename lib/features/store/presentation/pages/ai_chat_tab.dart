import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/config/gemini_connection_validation.dart';
import '../../../../core/services/gemini_ai_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/models.dart';
import '../ai/gemini_store_chat.dart';
import '../store_controller.dart';

class _ChatMsg {
  final bool isUser;
  final String text;
  final bool showMaintenanceCta;
  final bool showQuantityCalcCta;
  final List<Product> suggestedProducts;
  _ChatMsg({
    required this.isUser,
    required this.text,
    this.showMaintenanceCta = false,
    this.showQuantityCalcCta = false,
    this.suggestedProducts = const [],
  });
}

/// Ã™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â© Ã™â€ Ã˜ÂµÃ™Å Ã˜Â© Ã™â€¦Ã˜Â¹ Gemini Ã™Ë†Ã˜Â³Ã™Å Ã˜Â§Ã™â€š Ã˜Â§Ã™â€žÃ™â€¦Ã˜ÂªÃ˜Â¬Ã˜Â±.
class AiChatTab extends StatefulWidget {
  const AiChatTab({super.key, this.onBookMaintenance, this.onOpenQuantityCalculator});

  final VoidCallback? onBookMaintenance;
  final VoidCallback? onOpenQuantityCalculator;

  @override
  State<AiChatTab> createState() => _AiChatTabState();
}

class _AiChatTabState extends State<AiChatTab> {
  final _textCtrl = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_ChatMsg>[
    _ChatMsg(
      isUser: false,
      text:
          'Ã™â€¦Ã˜Â±Ã˜Â­Ã˜Â¨Ã˜Â§Ã™â€¹Ã˜Å’ Ã˜Â£Ã™â€ Ã˜Â§ Ã™â€¦Ã˜Â³Ã˜Â§Ã˜Â¹Ã˜Â¯ AmmarJo Ã™â€žÃ™â€¦Ã˜ÂªÃ˜Â¬Ã˜Â± **Ã™â€¦Ã™Ë†Ã˜Â§Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â¨Ã™â€ Ã˜Â§Ã˜Â¡ Ã™Ë†Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â´Ã™Å Ã™Å Ã˜Â¯**. Ã˜Â§Ã˜Â³Ã˜Â£Ã™â€žÃ™â€ Ã™Å  Ã˜Â¹Ã™â€  Ã˜Â§Ã™â€žÃ˜Â¯Ã™â€¡Ã˜Â§Ã™â€ Ã˜Â§Ã˜ÂªÃ˜Å’ Ã˜Â§Ã™â€žÃ˜Â³Ã˜Â¨Ã˜Â§Ã™Æ’Ã˜Â©Ã˜Å’ Ã˜Â§Ã™â€žÃ™Æ’Ã™â€¡Ã˜Â±Ã˜Â¨Ã˜Â§Ã˜Â¡Ã˜Å’ Ã˜Â§Ã™â€žÃ˜Â£Ã˜Â¯Ã™Ë†Ã˜Â§Ã˜ÂªÃ˜Å’ Ã˜ÂªÃ™Ë†Ã™ÂÃ˜Â± Ã™â€¦Ã™â€ Ã˜ÂªÃ˜Â¬Ã˜Å’ Ã˜Â£Ã™Ë† Ã™Æ’Ã™â€¦Ã™Å Ã˜Â§Ã˜Âª Ã™â€¦Ã™Ë†Ã˜Â§Ã˜Â¯ Ã™â€žÃ™â€¦Ã˜Â³Ã˜Â§Ã˜Â­Ã˜Â© Ã™â€¦Ã˜Â¹Ã™Å Ã™â€˜Ã™â€ Ã˜Â© Ã¢â‚¬â€ Ã™Ë†Ã˜Â³Ã˜Â£Ã˜Â¬Ã™Å Ã˜Â¨ Ã˜Â¨Ã˜Â§Ã™â€žÃ˜Â¹Ã˜Â±Ã˜Â¨Ã™Å Ã˜Â© Ã™Ë†Ã™ÂÃ™â€š Ã™Æ’Ã˜ÂªÃ˜Â§Ã™â€žÃ™Ë†Ã˜Â¬ Ã˜Â§Ã™â€žÃ™â€¦Ã˜ÂªÃ˜Â¬Ã˜Â±. Ã™Å Ã™â€¦Ã™Æ’Ã™â€ Ã™Æ’ Ã™ÂÃ˜ÂªÃ˜Â­ Ã‚Â«Ã˜Â­Ã˜Â§Ã˜Â³Ã˜Â¨Ã˜Â© Ã˜Â§Ã™â€žÃ™Æ’Ã™â€¦Ã™Å Ã˜Â§Ã˜ÂªÃ‚Â» Ã™â€¦Ã™â€  Ã˜Â§Ã™â€žÃ˜Â²Ã˜Â± Ã˜Â¹Ã™â€ Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã˜Â¬Ã˜Â©.',
    ),
  ];
  bool _sending = false;

  static const _ctaMarker = '[[MAINTENANCE_CTA]]';
  static const _quantityMarker = '[[QUANTITY_CALC_CTA]]';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final r = await validateGeminiConnection();
      if (kDebugMode && !r.isSuccess) {
        debugPrint('[AmmarJo Assistant] Gemini: ${r.userMessage ?? r.kind}');
      }
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Ã™Å Ã˜Â·Ã˜Â§Ã˜Â¨Ã™â€š Ã˜Â£Ã˜Â³Ã™â€¦Ã˜Â§Ã˜Â¡ Ã˜Â§Ã™â€žÃ™â€¦Ã™â€ Ã˜ÂªÃ˜Â¬Ã˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã™â€¦Ã™â€˜Ã™â€žÃ˜Â© Ã™ÂÃ™Å  Ã™Æ’Ã˜ÂªÃ˜Â§Ã™â€žÃ™Ë†Ã˜Â¬ Ã˜Â§Ã™â€žÃ™â€¦Ã˜ÂªÃ˜Â¬Ã˜Â± Ã™â€¦Ã˜Â¹ Ã™â€ Ã˜Âµ Ã˜Â±Ã˜Â¯ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜Â§Ã˜Â¹Ã˜Â¯ Ã™â€žÃ˜Â¹Ã˜Â±Ã˜Â¶ Ã˜Â£Ã˜Â²Ã˜Â±Ã˜Â§Ã˜Â± Ã‚Â«Ã˜Â£Ã˜Â¶Ã™Â Ã™â€žÃ™â€žÃ˜Â³Ã™â€žÃ˜Â©Ã‚Â».
  List<Product> _suggestedProductsForReply(String reply, StoreController store) {
    final lower = reply.toLowerCase();
    final out = <Product>[];
    for (final p in store.products) {
      final n = p.name.trim();
      if (n.length < 3) continue;
      if (lower.contains(n.toLowerCase())) {
        out.add(p);
        if (out.length >= 5) break;
      }
    }
    return out;
  }

  ({String text, bool showMaintenance, bool showQuantity}) _parseAssistantReply(String raw) {
    var t = raw.trim();
    final m = t.contains(_ctaMarker);
    final q = t.contains(_quantityMarker);
    t = t.replaceAll(_ctaMarker, '').replaceAll(_quantityMarker, '').replaceAll(RegExp(r'\n+\s*$'), '').trim();
    return (text: t, showMaintenance: m, showQuantity: q);
  }

  Future<void> _send() async {
    final q = _textCtrl.text.trim();
    if (q.isEmpty || _sending) return;
    final store = context.read<StoreController>();
    setState(() {
      _msgs.add(_ChatMsg(isUser: true, text: q));
      _sending = true;
      _textCtrl.clear();
    });
    _scrollToEnd();

    try {
      final ctx = buildCompactStoreContext(store);
      final appContext = await getAppContextForAiMessage(q);
      final reply = await chatWithStoreAssistant(
        userMessage: q,
        storeContext: ctx,
        appContext: appContext,
      );
      if (!mounted) return;
      final parsed = _parseAssistantReply(reply);
      final suggested = _suggestedProductsForReply(parsed.text, store);
      setState(() {
        _msgs.add(
          _ChatMsg(
            isUser: false,
            text: parsed.text,
            showMaintenanceCta: parsed.showMaintenance,
            showQuantityCalcCta: parsed.showQuantity,
            suggestedProducts: suggested,
          ),
        );
        _sending = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _msgs.add(_ChatMsg(isUser: false, text: 'Ã˜Â¹Ã˜Â°Ã˜Â±Ã˜Â§Ã™â€¹Ã˜Å’ Ã˜Â­Ã˜Â¯Ã˜Â« Ã˜Â®Ã˜Â·Ã˜Â£: unexpected error'));
        _sending = false;
      });
    }
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxW = 560.0;
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, _) {
        return Column(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                itemCount: _msgs.length + (_sending ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i < _msgs.length) {
                    return _Bubble(
                      msg: _msgs[i],
                      onBookMaintenance: widget.onBookMaintenance,
                      onOpenQuantityCalculator: widget.onOpenQuantityCalculator,
                      onAddProductToCart: (product) async {
                        final s = context.read<StoreController>();
                        await s.addToCart(product);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Ã˜ÂªÃ™â€¦ Ã˜Â¥Ã˜Â¶Ã˜Â§Ã™ÂÃ˜Â© ${product.name} Ã™â€žÃ™â€žÃ˜Â³Ã™â€žÃ˜Â© Ã¢Å“â€¦',
                              style: GoogleFonts.tajawal(),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        );
                      },
                    );
                  }
                  return Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orange),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Ã˜Â¬Ã˜Â§Ã˜Â±Ã™Å  Ã˜Â§Ã™â€žÃ˜ÂªÃ™ÂÃ™Æ’Ã™Å Ã˜Â±...',
                            style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textCtrl,
                        minLines: 1,
                        maxLines: 4,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.tajawal(fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Ã˜Â§Ã™Æ’Ã˜ÂªÃ˜Â¨ Ã˜Â³Ã˜Â¤Ã˜Â§Ã™â€žÃ™Æ’... (Ã™â€¦Ã˜Â«Ã˜Â§Ã™â€ž: Ã˜ÂªÃ˜Â³Ã˜Â±Ã™Å Ã˜Â¨ Ã˜ÂªÃ˜Â­Ã˜Âª Ã˜Â§Ã™â€žÃ™â€¦Ã˜ÂºÃ˜Â³Ã™â€žÃ˜Â©)',
                          hintStyle: GoogleFonts.tajawal(color: AppColors.textSecondary),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(color: AppColors.orange, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(14),
                        shape: const CircleBorder(),
                      ),
                      onPressed: _sending ? null : _send,
                      child: const Icon(Icons.send_rounded, size: 22),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  final _ChatMsg msg;
  final VoidCallback? onBookMaintenance;
  final VoidCallback? onOpenQuantityCalculator;
  final Future<void> Function(Product product) onAddProductToCart;

  const _Bubble({
    required this.msg,
    required this.onAddProductToCart,
    this.onBookMaintenance,
    this.onOpenQuantityCalculator,
  });

  @override
  Widget build(BuildContext context) {
    final user = msg.isUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: user ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.88),
            decoration: BoxDecoration(
              color: user ? AppColors.orange : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(user ? 16 : 4),
                bottomRight: Radius.circular(user ? 4 : 16),
              ),
              boxShadow: [
                BoxShadow(color: AppColors.shadow, blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Text(
              msg.text,
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(
                fontSize: 15,
                height: 1.4,
                color: user ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
          if (!user && msg.showMaintenanceCta && onBookMaintenance != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.icon(
                onPressed: onBookMaintenance,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.home_repair_service_rounded, size: 20),
                label: Text(
                  'Ã˜Â§Ã˜Â­Ã˜Â¬Ã˜Â² Ã™ÂÃ™â€ Ã™â€˜Ã™Å Ã˜Â§Ã™â€¹ Ã™â€žÃ˜Â¥Ã˜ÂµÃ™â€žÃ˜Â§Ã˜Â­ Ã™â€¡Ã˜Â°Ã˜Â§',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
          if (!user && msg.showQuantityCalcCta && onOpenQuantityCalculator != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.icon(
                onPressed: onOpenQuantityCalculator,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.calculate_outlined, size: 20),
                label: Text(
                  'Ã˜Â§Ã™ÂÃ˜ÂªÃ˜Â­ Ã˜Â­Ã˜Â§Ã˜Â³Ã˜Â¨Ã˜Â© Ã˜Â§Ã™â€žÃ™Æ’Ã™â€¦Ã™Å Ã˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ˜Â°Ã™Æ’Ã™Å Ã˜Â©',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
          if (!user && msg.suggestedProducts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: msg.suggestedProducts.map((p) {
                    return ElevatedButton.icon(
                      icon: const Icon(Icons.add_shopping_cart, size: 18),
                      label: Text(
                        'Ã˜Â£Ã˜Â¶Ã™Â ${p.name} Ã™â€žÃ™â€žÃ˜Â³Ã™â€žÃ˜Â©',
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => onAddProductToCart(p),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

