import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/config/chat_feature_config.dart';
import '../../../core/contracts/feature_state.dart';
import '../../../core/firebase/chat_firebase_sync.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_bar_back_button.dart';
import '../../../core/utils/jordan_phone.dart';
import '../../../core/utils/web_image_url.dart';
import '../../maintenance/domain/maintenance_models.dart';
import '../domain/marketplace_listing_chat_models.dart';
import '../../store/presentation/store_controller.dart';
import '../data/unified_chat_repository.dart';
import '../domain/unified_chat_models.dart';

/// محادثة Firebase مؤقتة — سوق مستعمل أو فني.
class UnifiedChatPage extends StatefulWidget {
  const UnifiedChatPage.usedListing({super.key, required this.listing})
      : tech = null,
        categoryLabel = null,
        existingChatId = null,
        threadTitle = null;

  const UnifiedChatPage.technician({super.key, required this.tech, required this.categoryLabel})
      : listing = null,
        existingChatId = null,
        threadTitle = null;

  /// فتح محادثة موجودة من صندوق الوارد.
  const UnifiedChatPage.resume({super.key, required this.existingChatId, required this.threadTitle})
      : listing = null,
        tech = null,
        categoryLabel = null;

  final MarketplaceListing? listing;
  final TechnicianProfile? tech;
  final String? categoryLabel;
  final String? existingChatId;
  final String? threadTitle;

  @override
  State<UnifiedChatPage> createState() => _UnifiedChatPageState();
}

class _UnifiedChatPageState extends State<UnifiedChatPage> {
  final _ctrl = TextEditingController();
  String? _chatId;
  Object? _initError;
  bool _loading = true;
  int _messagesRetryKey = 0;

  @override
  void initState() {
    super.initState();
    if (!kChatFeatureEnabled) {
      _initError = kChatFeatureUnavailableMessage;
      _loading = false;
      return;
    }
    final resume = widget.existingChatId;
    if (resume != null && resume.isNotEmpty) {
      _chatId = resume;
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncParticipantAndShow());
      return;
    }
    _open();
  }

  /// يملأ [buyer_id]/[seller_id] على الوثيقة إن لزم — مطلوب مع قواعد الأمان المعتمدة على UID فقط.
  Future<void> _syncParticipantAndShow() async {
    final store = context.read<StoreController>();
    final email =
        store.profile?.email.trim() ?? (throw StateError('NULL_RESPONSE'));
    final id = _chatId;
    if (email.isNotEmpty && id != null && Firebase.apps.isNotEmpty) {
      try {
        await syncChatFirebaseIdentity(store.profile);
        await UnifiedChatRepository.instance.ensureParticipantUidOnChat(id, email);
      } on Object {
        debugPrint('[UnifiedChatPage] ensureParticipantUidOnChat / sync failed');
        if (mounted) {
          setState(() => _initError = 'sync_failed');
        }
      }
    } else if (email.isEmpty) {
      if (mounted) setState(() => _initError = 'غير مسجّل');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _retryOpen() {
    final resume = widget.existingChatId;
    setState(() {
      _initError = null;
      _loading = true;
      _messagesRetryKey++;
      if (resume != null && resume.isNotEmpty) {
        _chatId = resume;
      } else {
        _chatId = null;
      }
    });
    if (resume != null && resume.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncParticipantAndShow());
      return;
    }
    _open();
  }

  Future<void> _open() async {
    final store = context.read<StoreController>();
    final email =
        store.profile?.email.trim() ?? (throw StateError('NULL_RESPONSE'));
    if (email.isEmpty) {
      setState(() {
        _loading = false;
        _initError = 'غير مسجّل';
      });
      return;
    }
    if (Firebase.apps.isEmpty) {
      setState(() {
        _loading = false;
        _initError = 'Firebase';
      });
      return;
    }

    try {
      await syncChatFirebaseIdentity(store.profile);
    } on Object {
      debugPrint('[UnifiedChatPage] syncChatFirebaseIdentity failed');
    }

    try {
      final repo = UnifiedChatRepository.instance;
      if (widget.listing != null) {
        final l = widget.listing!;
        final peerEmail = resolvePeerEmailForListing(l);
        final buyerPhone = dialablePhoneFromProfileEmail(email) ??
            (throw StateError('NULL_RESPONSE'));
        final id = await repo.ensureChat(
          kind: UnifiedChatKind.storeCustomer,
          contextId: l.id,
          currentUserEmail: email,
          currentUserPhone: buyerPhone,
          peerEmail: peerEmail,
          peerPhone: l.phone.trim(),
          peerDisplayName: l.title,
          contextTitle: l.title,
          contextSubtitle: '${l.priceLabel} JD · ${l.city}',
          contextImageUrl: l.imageUrl,
          seedProductCard: true,
          productCardTitle: l.title,
          productCardPrice: l.priceLabel,
          productCardImageUrl: l.imageUrl,
        );
        if (mounted) {
          setState(() => _chatId = id);
          try {
            await UnifiedChatRepository.instance.ensureParticipantUidOnChat(id, email);
          } on Object {
            debugPrint('[UnifiedChatPage] ensureParticipantUidOnChat (listing) failed');
          }
        }
      } else if (widget.tech != null) {
        final t = widget.tech!;
        final techEmail =
            (t.email ?? (throw StateError('NULL_RESPONSE'))).trim();
        if (techEmail.isEmpty) throw StateError('لا بريد للفني');
        final buyerPhone = dialablePhoneFromProfileEmail(email) ??
            (throw StateError('NULL_RESPONSE'));
        final id = await repo.ensureChat(
          kind: UnifiedChatKind.technicianCustomer,
          contextId: t.id,
          currentUserEmail: email,
          currentUserPhone: buyerPhone,
          peerEmail: techEmail,
          peerPhone: (t.phone ?? (throw StateError('NULL_RESPONSE'))).trim(),
          technicianId: t.id,
          peerDisplayName: t.displayName,
          contextTitle: t.displayName,
          contextSubtitle: widget.categoryLabel ?? 'صيانة',
          contextImageUrl: t.photoUrl,
          seedProductCard: false,
        );
        if (mounted) {
          setState(() => _chatId = id);
          try {
            await UnifiedChatRepository.instance.ensureParticipantUidOnChat(id, email);
          } on Object {
            debugPrint('[UnifiedChatPage] ensureParticipantUidOnChat (tech) failed');
          }
        }
      }
    } on Object {
      debugPrint('[UnifiedChatPage] ensureChat / _open failed');
      if (mounted) setState(() => _initError = 'open_failed');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final store = context.read<StoreController>();
    final email =
        store.profile?.email.trim() ?? (throw StateError('NULL_RESPONSE'));
    final id = _chatId;
    final t = _ctrl.text.trim();
    if (email.isEmpty || id == null || t.isEmpty) return;
    _ctrl.clear();
    try {
      await UnifiedChatRepository.instance.sendText(chatId: id, senderEmail: email, text: t);
    } on Object {
      debugPrint('[UnifiedChatPage] sendText failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إرسال الرسالة. تحقق من الصلاحيات.', style: GoogleFonts.tajawal())),
        );
      }
    }
  }

  String get _title {
    if (widget.threadTitle != null && widget.threadTitle!.isNotEmpty) return widget.threadTitle!;
    if (widget.listing != null) return widget.listing!.title;
    if (widget.tech != null) return widget.tech!.displayName;
    return 'محادثة';
  }

  String _messageForInitError(Object? err) {
    if (err?.toString().trim() == kChatFeatureUnavailableMessage) {
      return kChatFeatureUnavailableMessage;
    }
    if (err == 'غير مسجّل') return 'سجّل الدخول لبدء المحادثة.';
    if (err == 'Firebase') return 'Firebase غير مهيأ.';
    if (err is StateError) return err.message;
    if (err is ArgumentError) return err.message;
    if (err is Exception) return err.toString();
    return 'تعذّر فتح المحادثة. تحقق من الشبكة أو صلاحيات Firebase وحاول مرة أخرى.';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreController>();
    final myEmail =
        store.profile?.email.trim() ?? (throw StateError('NULL_RESPONSE'));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        leading: const AppBarBackButton(),
        title: Text(_title, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _initError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey.shade500),
                        const SizedBox(height: 16),
                        Text(
                          _messageForInitError(_initError),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.4),
                        ),
                        const SizedBox(height: 20),
                        if (_initError?.toString().trim() != kChatFeatureUnavailableMessage)
                          FilledButton.icon(
                            onPressed: _retryOpen,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text('إعادة المحاولة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                  ),
                )
              : _chatId == null
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        Expanded(
                          child: StreamBuilder<FeatureState<List<UnifiedChatMessage>>>(
                            key: ValueKey<int>(_messagesRetryKey),
                            stream: UnifiedChatRepository.instance.watchMessages(_chatId!),
                            builder: (context, snap) {
                              try {
                                if (snap.hasError) {
                                  debugPrint('[UnifiedChatPage] messages stream error: ${snap.error}');
                                  return Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.error_outline, size: 48, color: Colors.red.shade700),
                                          const SizedBox(height: 12),
                                          Text(
                                            'حدث خطأ في تحميل الرسائل',
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'تأكد أن حسابك ضمن participants في المحادثة.',
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                                          ),
                                          const SizedBox(height: 16),
                                          FilledButton.icon(
                                            onPressed: () async {
                                              final em = store.profile?.email
                                                      .trim() ??
                                                  (throw StateError(
                                                      'NULL_RESPONSE'));
                                              if (em.isNotEmpty && _chatId != null) {
                                                try {
                                                  await UnifiedChatRepository.instance.ensureParticipantUidOnChat(
                                                    _chatId!,
                                                    em,
                                                  );
                                                } on Object {
                                                  debugPrint('[UnifiedChatPage] retry ensureParticipant failed');
                                                }
                                              }
                                              if (mounted) {
                                                setState(() => _messagesRetryKey++);
                                              }
                                            },
                                            icon: const Icon(Icons.refresh_rounded),
                                            label: Text('إعادة المحاولة', style: GoogleFonts.tajawal()),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                                if (snap.connectionState == ConnectionState.waiting) {
                                  return const Center(child: CircularProgressIndicator(color: AppColors.accent));
                                }
                                final msgs = switch (snap.data) {
                                  FeatureSuccess(:final data) => data,
                                  _ => <UnifiedChatMessage>[],
                                };
                                if (msgs.isEmpty) {
                                  return Center(
                                    child: Text(
                                      'لا رسائل بعد. ابدأ المحادثة…',
                                      style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                                    ),
                                  );
                                }
                                return ListView.builder(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: msgs.length,
                                  itemBuilder: (context, i) {
                                    final m = msgs[i];
                                    final mine = m.senderEmail.toLowerCase() == myEmail.toLowerCase();
                                    return _MsgBubble(message: m, mine: mine);
                                  },
                                );
                              } on Object {
                                debugPrint('[UnifiedChatPage] messages builder failed');
                                return Center(
                                  child: Text(
                                    'تعذر عرض الرسائل',
                                    style: GoogleFonts.tajawal(color: AppColors.error),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              border: Border(top: BorderSide(color: AppColors.border)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _ctrl,
                                    textAlign: TextAlign.right,
                                    minLines: 1,
                                    maxLines: 4,
                                    style: GoogleFonts.tajawal(),
                                    decoration: InputDecoration(
                                      hintText: 'اكتب رسالتك…',
                                      hintStyle: GoogleFonts.tajawal(color: AppColors.textSecondary),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    ),
                                    onSubmitted: (_) => _send(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: _send,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.accent,
                                    foregroundColor: Colors.white,
                                    shape: const CircleBorder(),
                                    padding: const EdgeInsets.all(14),
                                  ),
                                  child: const Icon(Icons.send_rounded),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

class _MsgBubble extends StatelessWidget {
  const _MsgBubble({required this.message, required this.mine});

  final UnifiedChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    if (message.type == UnifiedMessageType.productCard) {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.88),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
            boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 6)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                child: Row(
                  children: [
                    Icon(Icons.shopping_bag_outlined, color: AppColors.accent, size: 20),
                    const SizedBox(width: 6),
                    Text('المنتج', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, color: AppColors.heading)),
                  ],
                ),
              ),
              if (message.productImageUrl != null && message.productImageUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(0)),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      webSafeImageUrl(message.productImageUrl!),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const ColoredBox(color: AppColors.orangeLight),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.productTitle ??
                          (throw StateError('NULL_RESPONSE')),
                      style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${message.productPriceLabel ?? (throw StateError('NULL_RESPONSE'))} JD',
                      style: GoogleFonts.tajawal(color: AppColors.accent, fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        decoration: BoxDecoration(
          color: mine ? AppColors.accent : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 4),
            bottomRight: Radius.circular(mine ? 4 : 14),
          ),
          boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 4)],
        ),
        child: Text(
          message.text,
          textAlign: TextAlign.right,
          style: GoogleFonts.tajawal(
            color: mine ? Colors.white : AppColors.textPrimary,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
