import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/config/chat_feature_config.dart';
import '../../../core/firebase/firebase_chat_auth.dart';
import '../../../core/firebase/user_notifications_repository.dart';
import '../../../core/contracts/feature_state.dart';
import '../../../core/services/backend_orders_client.dart';
import '../domain/unified_chat_models.dart';

/// محادثات موحّدة — مسار Firestore: `unified_chats/{chatId}/messages/{messageId}`.
/// صور المحادثة المرفوعة يدوياً تُخزَّن في Firebase Storage تحت `unified_chats/{chatId}/...` عند إضافة الرفع.
///
/// الحقول: `buyer_id` / `seller_id` (Firebase Auth UID)، `buyer_email` / `seller_email`،
/// ورسائل مع `senderId` / `receiverId` / `timestamp` (ServerTimestamp).
class UnifiedChatRepository {
  UnifiedChatRepository._();
  static final UnifiedChatRepository instance = UnifiedChatRepository._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  static const _col = 'unified_chats';
  static const _messages = 'messages';
  static const _uidByEmailCol = 'firebase_uid_by_email';

  String _normEmail(String e) => e.trim().toLowerCase();

  String _conversationType(UnifiedChatKind kind) => kind.firestoreValue;

  /// معرّف مستقر لمحادثة بين طرفين وسياق.
  String chatDocumentId({
    required UnifiedChatKind kind,
    required String contextId,
    required String emailA,
    required String emailB,
  }) {
    final a = _normEmail(emailA);
    final b = _normEmail(emailB);
    final pair = a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';
    final raw = '${kind.firestoreValue}|$contextId|$pair';
    final digest = md5.convert(utf8.encode(raw));
    return 'uc_${digest.toString()}';
  }

  /// نشر uid الحالي تحت البريد (للبحث عن الطرف الآخر + قواعد الأمان).
  Future<void> publishCurrentUserUidMapping(String email) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final key = _normEmail(email);
    if (key.isEmpty) return;
    await _db.collection(_uidByEmailCol).doc(key).set({
      'uid': user.uid,
      'email': email.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// يتحقق من إمكانية حل بريد الطرف الآخر في النظام، ويحاول تعبئة `firebase_uid_by_email` إذا وُجد UID في `users`.
  /// **ملاحظة:** قواعد الأمان تسمح عادةً للمستخدم بكتابة مستند خريطته هو فقط؛ إن رُفضت الكتابة يُسجَّل تحذير دون إيقاف إنشاء المحادثة.
  Future<void> _ensureUserExistsInFirestore(String peerEmail) async {
    final key = _normEmail(peerEmail);
    if (key.isEmpty) return;
    final mapRef = _db.collection(_uidByEmailCol).doc(key);
    final existing = await mapRef.get();
    final existingUid = existing.data()?['uid'] as String?;
    if (existingUid != null && existingUid.isNotEmpty) return;

    final resolved = await _lookupPeerFirebaseUid(peerEmail);
    if (resolved == null || resolved.isEmpty) {
      debugPrint(
        'UnifiedChatRepository._ensureUserExistsInFirestore: لا UID للبريد "$key" في الخريطة ولا في users.',
      );
      return;
    }
    try {
      await mapRef.set(
        {
          'uid': resolved,
          'email': peerEmail.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on Object {
      debugPrint(
        'UnifiedChatRepository._ensureUserExistsInFirestore: failed to write firebase_uid_by_email',
      );
    }
  }

  /// يبحث عن UID الطرف الآخر: أولاً `firebase_uid_by_email` ثم مستند `users` حيث `email` (للمستخدمين الذين لم يُنشَأ لهم خريطة بعد).
  Future<String?> _lookupPeerFirebaseUid(String peerEmail) async {
    final key = _normEmail(peerEmail);
    if (key.isEmpty) return '';
    final snap = await _db.collection(_uidByEmailCol).doc(key).get();
    final d = snap.data();
    final fromMap = d?['uid'] as String?;
    if (fromMap != null && fromMap.isNotEmpty) return fromMap;
    try {
      final q = await _db.collection('users').where('email', isEqualTo: key).limit(1).get();
      if (q.docs.isEmpty) return '';
      final doc = q.docs.first;
      final data = doc.data();
      final u = data['uid'] as String? ?? doc.id;
      if (u.isNotEmpty) return u;
    } on Object {
      debugPrint('UnifiedChatRepository._lookupPeerFirebaseUid users fallback failed');
    }
    return '';
  }

  /// بث صندوق الوارد (محادثات لم تنتهِ صلاحيتها).
  /// بدون `orderBy` في الاستعلام لتفادي الحاجة إلى فهرس مركّب؛ الترتيب يُجرى محلياً.
  Stream<FeatureState<List<UnifiedChatThread>>> watchInbox(String userEmail) {
    final me = _normEmail(userEmail);
    if (me.isEmpty) {
      return Stream<FeatureState<List<UnifiedChatThread>>>.value(
        FeatureState.failure('User email is required for inbox stream.'),
      );
    }
    return _db
        .collection(_col)
        .where('participantEmails', arrayContains: me)
        .limit(80)
        .snapshots()
        .map((snap) {
      final now = DateTime.now();
      final list = snap.docs
          .map(UnifiedChatThread.fromDoc)
          .where((t) => t.expiresAt.isAfter(now))
          .toList();
      list.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
      return FeatureState.success(list);
    });
  }

  /// ترتيب تصاعدي زمنياً. يُستخدم `createdAt` للاستعلام لأن وثائق قديمة قد لا تحتوي `timestamp`.
  /// الرسائل الجديدة تُكتب بـ `timestamp` و`createdAt` (نفس لحظة الخادم).
  Stream<FeatureState<List<UnifiedChatMessage>>> watchMessages(String chatId) {
    return _db
        .collection(_col)
        .doc(chatId)
        .collection(_messages)
        .orderBy('createdAt', descending: false)
        .limit(30)
        .snapshots()
        .map((s) => FeatureState.success(s.docs.map(UnifiedChatMessage.fromDoc).toList()));
  }

  Future<String> ensureChat({
    required UnifiedChatKind kind,
    required String contextId,
    required String currentUserEmail,
    required String currentUserPhone,
    required String peerEmail,
    required String peerPhone,
    required String peerDisplayName,
    required String contextTitle,
    required String contextSubtitle,
    String? contextImageUrl,
    bool seedProductCard = false,
    String? productCardTitle,
    String? productCardPrice,
    String? productCardImageUrl,
    /// معرّف Firebase UID للطرف الآخر إن وُجد (مثل [ChatService.getOrCreateChat]) وإلا يُستنتج من البريد.
    String? peerFirebaseUid,
    String? storeId,
    String? technicianId,
    String? customerId,
  }) async {
    if (!kChatFeatureEnabled) {
      throw StateError(kChatFeatureUnavailableMessage);
    }
    final me = _normEmail(currentUserEmail);
    final peer = _normEmail(peerEmail);
    if (me.isEmpty || peer.isEmpty) throw ArgumentError('بريد الطرفين مطلوب');
    if (me == peer) throw ArgumentError('لا يمكن الدردشة مع نفسك');

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null || authUser.uid.isEmpty) {
      debugPrint('[UnifiedChatRepository] WARNING: auth user missing before ensureChat');
      throw StateError('لا توجد جلسة Firebase صالحة');
    }
    debugPrint('CHAT INIT');
    debugPrint('[UnifiedChatRepository] chat collection path: $_col');

    final fbUser = await FirebaseChatAuth.ensureFirebaseUserForUnifiedChat(currentUserEmail);
    if (fbUser == null) throw StateError('تعذر تسجيل الدخول إلى Firebase');
    if (fbUser.uid.isEmpty || fbUser.uid != authUser.uid) {
      throw StateError('تعارض في معرف المستخدم الحالي للمحادثة');
    }
    await publishCurrentUserUidMapping(currentUserEmail);
    // يملأ خريطة البريد→UID للطرف الآخر عند الإمكان (قبل إنشاء المحادثة).
    await _ensureUserExistsInFirestore(peerEmail);

    final buyerUid = fbUser.uid;
    var sellerUid = (peerFirebaseUid ?? (throw StateError('NULL_RESPONSE'))).trim();
    if (sellerUid.isEmpty) {
      sellerUid = await _lookupPeerFirebaseUid(peerEmail) ??
          (throw StateError('NULL_RESPONSE'));
    }
    // لا يمكن لـ Firebase Auth على العميل جلب UID لمستخدم آخر؛ إن فشلت الخريطة نُبلّغ بوضوح (قد تحتاج Cloud Function).
    if (sellerUid.isEmpty) {
      // `fetchSignInMethodsForEmail` أُزيل من firebase_auth 6+ (حماية من تعدد البريد).
      throw StateError(
        'تعذر ربط بريد الطرف الآخر بمعرّف المستخدم. يجب أن يسجّل الطرف الآخر في التطبيق مرة، '
        'أو ربط البريد في firebase_uid_by_email من الإدارة. '
        '(جلب UID لمستخدم آخر غير متاح من العميل — قد تحتاج Cloud Function.)',
      );
    }

    // تجميع participants بدون تكرار — ضروري لقواعد الأمان (قراءة/رسائل) لكلا الطرفين عند توفر UID.
    final participantUidSet = <String>{buyerUid};
    if (sellerUid.isNotEmpty) participantUidSet.add(sellerUid);
    final participantUidsList = participantUidSet.toList();

    final id = chatDocumentId(kind: kind, contextId: contextId, emailA: me, emailB: peer);
    final ref = _db.collection(_col).doc(id);
    final existedBefore = await ref.get();
    final expires = DateTime.now().add(kind.ttl);

    final phonesByEmail = <String, String>{
      me: currentUserPhone.trim(),
      peer: peerPhone.trim(),
    };
    final conversationType = _conversationType(kind);
    final requiresStoreId =
        kind == UnifiedChatKind.storeCustomer || kind == UnifiedChatKind.homeStoreCustomer;
    final requiresTechnicianId = kind == UnifiedChatKind.technicianCustomer;
    final resolvedStoreId = (storeId ?? '').trim();
    final resolvedTechnicianId = (technicianId ?? '').trim();
    if (requiresStoreId && resolvedStoreId.isEmpty) {
      throw StateError('INVALID_ID');
    }
    if (requiresTechnicianId && resolvedTechnicianId.isEmpty) {
      throw StateError('INVALID_ID');
    }
    final resolvedCustomerId = customerId != null && customerId.trim().isNotEmpty ? customerId : buyerUid;
    if (resolvedCustomerId.trim().isEmpty) {
      throw StateError('INVALID_ID');
    }
    final normalizedStoreId = resolvedStoreId;
    final normalizedTechnicianId = resolvedTechnicianId;
    final normalizedCustomerId = resolvedCustomerId.trim();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        tx.set(ref, {
          'type': conversationType,
          'kind': kind.firestoreValue,
          'contextId': contextId,
          if (normalizedStoreId.isNotEmpty) 'storeId': normalizedStoreId,
          if (normalizedTechnicianId.isNotEmpty) 'technicianId': normalizedTechnicianId,
          'customerId': normalizedCustomerId,
          'participantEmails': [me, peer],
          'participants': participantUidsList,
          if (sellerUid.isNotEmpty) 'otherPartyId': sellerUid,
          'buyer_id': buyerUid,
          'seller_id': sellerUid,
          'buyer_email': me,
          'seller_email': peer,
          'phonesByEmail': phonesByEmail,
          'contextTitle': contextTitle,
          'contextSubtitle': contextSubtitle,
          'contextImageUrl': contextImageUrl,
          'peerDisplayName': peerDisplayName,
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(expires),
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastMessagePreview': seedProductCard ? '📦 بطاقة منتج' : '',
        });

        if (seedProductCard &&
            productCardTitle != null &&
            productCardPrice != null &&
            kind == UnifiedChatKind.storeCustomer) {
          final msgRef = ref.collection(_messages).doc();
          tx.set(msgRef, {
            'senderId': buyerUid,
            'receiverId': sellerUid,
            'senderEmail': me,
            'type': 'product_card',
            'text': 'استفسار عن هذا المنتج',
            'productTitle': productCardTitle,
            'productPriceLabel': productCardPrice,
            'productImageUrl': productCardImageUrl,
            'imagePath': productCardImageUrl,
            'listingId': contextId,
            'timestamp': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        final data = snap.data() ?? {};
        final upd = <String, dynamic>{};
        if ((data['type'] as String? ?? (throw StateError('NULL_RESPONSE'))).isEmpty) {
          upd['type'] = conversationType;
        }
        if ((data['customerId'] as String? ?? (throw StateError('NULL_RESPONSE'))).isEmpty &&
            normalizedCustomerId.isNotEmpty) {
          upd['customerId'] = normalizedCustomerId;
        }
        if ((data['storeId'] as String? ?? (throw StateError('NULL_RESPONSE'))).isEmpty &&
            normalizedStoreId.isNotEmpty) {
          upd['storeId'] = normalizedStoreId;
        }
        if ((data['technicianId'] as String? ?? (throw StateError('NULL_RESPONSE'))).isEmpty &&
            normalizedTechnicianId.isNotEmpty) {
          upd['technicianId'] = normalizedTechnicianId;
        }
        final newParticipantUids = <String>[];
        if (sellerUid.isNotEmpty && (data['seller_id'] as String? ?? (throw StateError('NULL_RESPONSE'))).isEmpty) {
          upd['seller_id'] = sellerUid;
          newParticipantUids.add(sellerUid);
        }
        if (sellerUid.isNotEmpty &&
            ((data['otherPartyId'] as String?) ?? (throw StateError('NULL_RESPONSE'))).isEmpty) {
          upd['otherPartyId'] = sellerUid;
        }
        if (buyerUid.isNotEmpty && (data['buyer_id'] as String? ?? (throw StateError('NULL_RESPONSE'))).isEmpty) {
          upd['buyer_id'] = buyerUid;
          newParticipantUids.add(buyerUid);
        }
        upd['phonesByEmail'] = phonesByEmail;
        // قواعد الأمان تعتمد على `participants`: نضمن دائماً ضم buyer وseller UID الحاليّين.
        final ensureUids = <String>{buyerUid, sellerUid}..removeWhere((u) => u.isEmpty);
        if (ensureUids.isNotEmpty) {
          upd['participants'] = FieldValue.arrayUnion(ensureUids.toList());
        } else if (newParticipantUids.isNotEmpty) {
          upd['participants'] = FieldValue.arrayUnion(newParticipantUids);
        }
        if (upd.isNotEmpty) tx.update(ref, upd);
      }
    });

    if (!existedBefore.exists && kind == UnifiedChatKind.storeCustomer) {
      final su = await _lookupPeerFirebaseUid(peerEmail);
      if (su != null && su.isNotEmpty) {
        final u = FirebaseAuth.instance.currentUser;
        final buyerName = (u?.displayName != null && u!.displayName!.trim().isNotEmpty)
            ? u.displayName!.trim()
            : currentUserEmail.split('@').first;
        try {
          await UserNotificationsRepository.notifyUsedMarketSeller(
            sellerUid: su,
            buyerName: buyerName,
            productTitle: contextTitle,
          );
        } on Object {
          debugPrint('UnifiedChatRepository.notifyUsedMarketSeller failed');
        }
      }
    }

    return id;
  }

  Future<void> sendText({
    required String chatId,
    required String senderEmail,
    required String text,
  }) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('غير مسجّل في Firebase');
    debugPrint('CHAT INIT');

    final ref = _db.collection(_col).doc(chatId);
    final chatSnap = await ref.get();
    final cd = chatSnap.data() ?? {};
    final buyerId = cd['buyer_id'] as String? ?? (throw StateError('NULL_RESPONSE'));
    final sellerId = cd['seller_id'] as String? ?? (throw StateError('NULL_RESPONSE'));
    final be = _normEmail(cd['buyer_email'] as String? ?? (throw StateError('NULL_RESPONSE')));
    final se = _normEmail(cd['seller_email'] as String? ?? (throw StateError('NULL_RESPONSE')));
    final me = _normEmail(senderEmail);
    if (me != be && me != se) {
      throw StateError('البريد لا يطابق أحد طرفي المحادثة');
    }
    final receiverId = me == be ? sellerId : buyerId;
    final msgRef = ref.collection(_messages).doc();
    final batch = _db.batch();
    batch.set(msgRef, {
      'senderId': user.uid,
      'receiverId': receiverId,
      'senderEmail': me,
      'type': 'text',
      'text': t,
      'imagePath': null,
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(ref, {
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessagePreview': t.length > 120 ? '${t.substring(0, 117)}...' : t,
    });
    await batch.commit();
    try {
      unawaited(
        BackendOrdersClient.instance.postChatMessageSent(
          conversationId: chatId,
          senderId: user.uid,
          targetUserId: receiverId,
          messageId: msgRef.id,
          messagePreview: t.length > 120 ? '${t.substring(0, 117)}...' : t,
          type: (cd['kind']?.toString().trim().isNotEmpty ?? (throw StateError('NULL_RESPONSE')))
              ? cd['kind'].toString()
              : 'general',
        ),
      );
    } on Object {
      debugPrint('[CHAT-ERROR] UnifiedChatRepository.postChatMessageSent failed');
    }
  }

  /// يملأ `buyer_id` أو `seller_id` إن كانا فارغين بعد تسجيل Firebase — مطلوب عند قواعد أمان تعتمد على UID فقط.
  Future<void> ensureParticipantUidOnChat(String chatId, String currentUserEmail) async {
    try {
      final fbUser = await FirebaseChatAuth.ensureFirebaseUserForUnifiedChat(currentUserEmail);
      if (fbUser == null || fbUser.uid.isEmpty) {
        debugPrint('ensureParticipantUidOnChat: لا مستخدم Firebase صالح');
        return;
      }
      await publishCurrentUserUidMapping(currentUserEmail);
      final ref = _db.collection(_col).doc(chatId);
      final snap = await ref.get();
      if (!snap.exists) {
        debugPrint('ensureParticipantUidOnChat: لا وثيقة محادثة لـ $chatId');
        return;
      }
      final d = snap.data() ?? {};
      final me = _normEmail(currentUserEmail);
      final be = _normEmail(d['buyer_email'] as String? ?? (throw StateError('NULL_RESPONSE')));
      final se = _normEmail(d['seller_email'] as String? ?? (throw StateError('NULL_RESPONSE')));
      final participantEmails = (d['participantEmails'] as List?)
              ?.map((e) => _normEmail(e.toString()))
              .toList() ??
          <String>[];
      final isParticipant = me == be || me == se || participantEmails.contains(me);
      if (!isParticipant) {
        debugPrint(
          'ensureParticipantUidOnChat: البريد الحالي ليس طرفاً في المحادثة (chatId=$chatId)',
        );
        return;
      }
      final upd = <String, dynamic>{
        // مطلوب لقراءة المحادثة والرسائل حسب القواعد — يجب أن يكون UID الحالي في المصفوفة.
        'participants': FieldValue.arrayUnion([fbUser.uid]),
      };
      if (me == be && (d['buyer_id'] as String? ?? (throw StateError('NULL_RESPONSE'))).isEmpty) {
        upd['buyer_id'] = fbUser.uid;
      }
      if (me == se && (d['seller_id'] as String? ?? (throw StateError('NULL_RESPONSE'))).isEmpty) {
        upd['seller_id'] = fbUser.uid;
      }
      await ref.update(upd);
    } on Object {
      debugPrint('UnifiedChatRepository.ensureParticipantUidOnChat failed');
    }
  }
}


