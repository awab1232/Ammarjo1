import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ammar_store/core/session/user_session.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_bar_back_button.dart';
import '../../store/presentation/store_controller.dart';
import '../data/support_chat_repository.dart';

/// محادثة دعم بين المستخدم والإدارة.
class SupportChatPage extends StatefulWidget {
  const SupportChatPage({
    super.key,
    required this.chatId,
    this.isAdmin = false,
  });

  final String chatId;
  final bool isAdmin;

  @override
  State<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatPageState extends State<SupportChatPage> {
  final _textCtrl = TextEditingController();
  final _scroll = ScrollController();
  bool _ending = false;
  bool _unreadResetDone = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _resetUnreadOnOpen() async {
    if (_unreadResetDone) return;
    _unreadResetDone = true;
    try {
      if (widget.isAdmin) {
        await SupportChatRepository.instance.resetAdminUnreadCount(widget.chatId);
      } else {
        await SupportChatRepository.instance.resetUserUnreadCount(widget.chatId);
      }
    } on Object catch (e, st) {
      debugPrint('[SupportChatPage] _resetUnreadOnOpen: $e\n$st');
    }
  }

  Future<void> _endChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('إنهاء المحادثة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        content: Text(
          'هل تريد إنهاء هذه المحادثة؟ لن يمكن إرسال رسائل جديدة حتى تبدأ محادثة جديدة من «احصل على مساعدة».',
          style: GoogleFonts.tajawal(height: 1.35),
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء', style: GoogleFonts.tajawal())),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
            child: Text('إنهاء', style: GoogleFonts.tajawal(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _ending = true);
    try {
      await SupportChatRepository.instance.closeChat(widget.chatId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إنهاء المحادثة.', style: GoogleFonts.tajawal())),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر الإنهاء: $e', style: GoogleFonts.tajawal()),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _ending = false);
    }
  }

  Future<void> _send() async {
    final t = _textCtrl.text.trim();
    if (t.isEmpty) return;
    final store = context.read<StoreController>();
    final uid = UserSession.currentUid;
    if (!UserSession.isLoggedIn || uid.isEmpty) return;

    String senderName;
    if (widget.isAdmin) {
      senderName = 'فريق الدعم';
    } else {
      final p = store.profile;
      senderName = p?.fullName?.trim().isNotEmpty == true
          ? p!.fullName!.trim()
          : '${p?.firstName ?? ''} ${p?.lastName ?? ''}'.trim();
      if (senderName.isEmpty) senderName = p?.email ?? 'عميل';
    }

    try {
      await SupportChatRepository.instance.sendMessage(
        chatId: widget.chatId,
        text: t,
        senderName: senderName,
      );
      _textCtrl.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent + 120,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } on Object catch (e) {
      debugPrint('[SupportChatPage] _send: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الإرسال: $e', style: GoogleFonts.tajawal())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SupportTicket?>(
      future: SupportChatRepository.instance.fetchTicket(widget.chatId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: const Color(0xFFFF6B00),
              foregroundColor: Colors.white,
              leading: const AppBarBackButton(),
              title: Text('المساعدة والدعم', style: GoogleFonts.tajawal(color: Colors.white)),
            ),
            body: const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange)),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: const Color(0xFFFF6B00),
              foregroundColor: Colors.white,
              leading: const AppBarBackButton(),
              title: Text('المساعدة والدعم', style: GoogleFonts.tajawal(color: Colors.white)),
            ),
            body: Center(child: Text('${snap.error}', style: GoogleFonts.tajawal())),
          );
        }
        if (!snap.hasData || snap.data == null) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: const Color(0xFFFF6B00),
              foregroundColor: Colors.white,
              leading: const AppBarBackButton(),
              title: Text('المساعدة والدعم', style: GoogleFonts.tajawal(color: Colors.white)),
            ),
            body: Center(child: Text('المحادثة غير موجودة.', style: GoogleFonts.tajawal())),
          );
        }
        final data = snap.data!;
        final status = data.status;
        final isClosed = status == 'closed';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _resetUnreadOnOpen();
        });

        return Scaffold(
          appBar: AppBar(
            title: Text('المساعدة والدعم', style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.w700)),
            backgroundColor: const Color(0xFFFF6B00),
            foregroundColor: Colors.white,
            leading: const AppBarBackButton(),
            actions: [
              if (!isClosed)
                TextButton(
                  onPressed: _ending ? null : _endChat,
                  child: Text(
                    'إنهاء المحادثة',
                    style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              if (isClosed)
                Container(
                  width: double.infinity,
                  color: Colors.red[50],
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'تم إنهاء هذه المحادثة. للتواصل مرة أخرى اضغط على «احصل على مساعدة».',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.tajawal(color: Colors.red[800], fontSize: 13, height: 1.35),
                  ),
                ),
              Expanded(child: _buildMessagesList(data.messages)),
              if (!isClosed) _buildMessageInput(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessagesList(List<SupportMessage> messages) {
    if (messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'ابدأ المحادثة بكتابة رسالتك أدناه.',
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    final myUid = UserSession.currentUid;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final m = messages[i];
        final senderId = m.senderId;
        final senderName = m.senderName;
        final text = m.text;
        final at = m.createdAt;
        final mine = senderId == myUid;
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
            decoration: BoxDecoration(
              color: mine ? AppColors.primaryOrange.withValues(alpha: 0.12) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  senderName,
                  style: GoogleFonts.tajawal(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 4),
                Text(text, style: GoogleFonts.tajawal(fontSize: 15, height: 1.35), textAlign: TextAlign.right),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                    style: GoogleFonts.tajawal(fontSize: 10, color: AppColors.textSecondary),
                    textAlign: TextAlign.left,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageInput() {
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _textCtrl,
                  minLines: 1,
                  maxLines: 4,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: 'اكتب رسالتك…',
                    hintStyle: GoogleFonts.tajawal(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.surfaceSecondary,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                  style: GoogleFonts.tajawal(fontSize: 15),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(14),
                  shape: const CircleBorder(),
                ),
                onPressed: _send,
                child: const Icon(Icons.send_rounded, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
