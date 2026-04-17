import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/firebase/firebase_chat_auth.dart';
import '../../../core/firebase/user_notifications_repository.dart';
import '../../../core/contracts/feature_state.dart';
import '../../../core/services/backend_orders_client.dart';
import '../domain/unified_chat_models.dart';

/// Ã™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â§Ã˜Âª Ã™â€¦Ã™Ë†Ã˜Â­Ã™â€˜Ã˜Â¯Ã˜Â© Ã¢â‚¬â€ Ã™â€¦Ã˜Â³Ã˜Â§Ã˜Â± Firestore: `unified_chats/{chatId}/messages/{messageId}`.
/// Ã˜ÂµÃ™Ë†Ã˜Â± Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â±Ã™ÂÃ™Ë†Ã˜Â¹Ã˜Â© Ã™Å Ã˜Â¯Ã™Ë†Ã™Å Ã˜Â§Ã™â€¹ Ã˜ÂªÃ™ÂÃ˜Â®Ã˜Â²Ã™â€˜Ã™Å½Ã™â€  Ã™ÂÃ™Å  Firebase Storage Ã˜ÂªÃ˜Â­Ã˜Âª `unified_chats/{chatId}/...` Ã˜Â¹Ã™â€ Ã˜Â¯ Ã˜Â¥Ã˜Â¶Ã˜Â§Ã™ÂÃ˜Â© Ã˜Â§Ã™â€žÃ˜Â±Ã™ÂÃ˜Â¹.
///
/// Ã˜Â§Ã™â€žÃ˜Â­Ã™â€šÃ™Ë†Ã™â€ž: `buyer_id` / `seller_id` (Firebase Auth UID)Ã˜Å’ `buyer_email` / `seller_email`Ã˜Å’
/// Ã™Ë†Ã˜Â±Ã˜Â³Ã˜Â§Ã˜Â¦Ã™â€ž Ã™â€¦Ã˜Â¹ `senderId` / `receiverId` / `timestamp` (ServerTimestamp).
class UnifiedChatRepository {
  UnifiedChatRepository._();
  static final UnifiedChatRepository instance = UnifiedChatRepository._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  static const _col = 'unified_chats';
  static const _messages = 'messages';
  static const _uidByEmailCol = 'firebase_uid_by_email';

  String _normEmail(String e) => e.trim().toLowerCase();

  String _conversationType(UnifiedChatKind kind) => kind.firestoreValue;

  /// Ã™â€¦Ã˜Â¹Ã˜Â±Ã™â€˜Ã™Â Ã™â€¦Ã˜Â³Ã˜ÂªÃ™â€šÃ˜Â± Ã™â€žÃ™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â© Ã˜Â¨Ã™Å Ã™â€  Ã˜Â·Ã˜Â±Ã™ÂÃ™Å Ã™â€  Ã™Ë†Ã˜Â³Ã™Å Ã˜Â§Ã™â€š.
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

  /// Ã™â€ Ã˜Â´Ã˜Â± uid Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ™Å  Ã˜ÂªÃ˜Â­Ã˜Âª Ã˜Â§Ã™â€žÃ˜Â¨Ã˜Â±Ã™Å Ã˜Â¯ (Ã™â€žÃ™â€žÃ˜Â¹Ã˜Â«Ã™Ë†Ã˜Â± Ã˜Â¹Ã™â€žÃ™â€° Ã˜Â§Ã™â€žÃ˜Â·Ã˜Â±Ã™Â Ã˜Â§Ã™â€žÃ˜Â¢Ã˜Â®Ã˜Â± + Ã™â€šÃ™Ë†Ã˜Â§Ã˜Â¹Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â£Ã™â€¦Ã˜Â§Ã™â€ ).
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

  /// Ã™Å Ã˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã™â€¦Ã™â€  Ã˜Â¥Ã™â€¦Ã™Æ’Ã˜Â§Ã™â€ Ã™Å Ã˜Â© Ã˜Â­Ã™â€ž Ã˜Â¨Ã˜Â±Ã™Å Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â·Ã˜Â±Ã™Â Ã˜Â§Ã™â€žÃ˜Â¢Ã˜Â®Ã˜Â± Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ™â€ Ã˜Â¸Ã˜Â§Ã™â€¦Ã˜Å’ Ã™Ë†Ã™Å Ã˜Â­Ã˜Â§Ã™Ë†Ã™â€ž Ã˜ÂªÃ˜Â¹Ã˜Â¨Ã˜Â¦Ã˜Â© `firebase_uid_by_email` Ã˜Â¥Ã˜Â°Ã˜Â§ Ã™Ë†Ã™ÂÃ˜Â¬Ã˜Â¯ UID Ã™ÂÃ™Å  `users`.
  /// **Ã™â€¦Ã™â€žÃ˜Â§Ã˜Â­Ã˜Â¸Ã˜Â©:** Ã™â€šÃ™Ë†Ã˜Â§Ã˜Â¹Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â£Ã™â€¦Ã˜Â§Ã™â€  Ã˜ÂªÃ˜Â³Ã™â€¦Ã˜Â­ Ã˜Â¹Ã˜Â§Ã˜Â¯Ã˜Â©Ã™â€¹ Ã™â€žÃ™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Ã˜Â¨Ã™Æ’Ã˜ÂªÃ˜Â§Ã˜Â¨Ã˜Â© Ã™â€¦Ã˜Â³Ã˜ÂªÃ™â€ Ã˜Â¯ Ã˜Â®Ã˜Â±Ã™Å Ã˜Â·Ã˜ÂªÃ™â€¡ Ã™â€¡Ã™Ë† Ã™ÂÃ™â€šÃ˜Â·Ã˜â€º Ã˜Â¥Ã™â€  Ã˜Â±Ã™ÂÃ™ÂÃ˜Â¶Ã˜Âª Ã˜Â§Ã™â€žÃ™Æ’Ã˜ÂªÃ˜Â§Ã˜Â¨Ã˜Â© Ã™Å Ã™ÂÃ˜Â³Ã˜Â¬Ã™â€˜Ã™Å½Ã™â€ž Ã˜ÂªÃ˜Â­Ã˜Â°Ã™Å Ã˜Â± Ã˜Â¯Ã™Ë†Ã™â€  Ã˜Â¥Ã™Å Ã™â€šÃ˜Â§Ã™Â Ã˜Â¥Ã™â€ Ã˜Â´Ã˜Â§Ã˜Â¡ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â©.
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
        'UnifiedChatRepository._ensureUserExistsInFirestore: Ã™â€žÃ˜Â§ UID Ã™â€žÃ™â€žÃ˜Â¨Ã˜Â±Ã™Å Ã˜Â¯ "$key" Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ˜Â®Ã˜Â±Ã™Å Ã˜Â·Ã˜Â© Ã™Ë†Ã™â€žÃ˜Â§ Ã™ÂÃ™Å  users.',
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

  /// Ã™Å Ã˜Â¨Ã˜Â­Ã˜Â« Ã˜Â¹Ã™â€  UID Ã˜Â§Ã™â€žÃ˜Â·Ã˜Â±Ã™Â Ã˜Â§Ã™â€žÃ˜Â¢Ã˜Â®Ã˜Â±: Ã˜Â£Ã™Ë†Ã™â€žÃ˜Â§Ã™â€¹ `firebase_uid_by_email` Ã˜Â«Ã™â€¦ Ã™â€¦Ã˜Â³Ã˜ÂªÃ™â€ Ã˜Â¯ `users` Ã˜Â­Ã™Å Ã˜Â« `email` (Ã™â€žÃ™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦Ã™Å Ã™â€  Ã˜Â§Ã™â€žÃ˜Â°Ã™Å Ã™â€  Ã™â€žÃ™â€¦ Ã™Å Ã™ÂÃ™â€ Ã˜Â´Ã™Å½Ã˜Â£ Ã™â€žÃ™â€¡Ã™â€¦ Ã˜Â®Ã˜Â±Ã™Å Ã˜Â·Ã˜Â© Ã˜Â¨Ã˜Â¹Ã˜Â¯).
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

  /// Ã˜Â¨Ã˜Â« Ã˜ÂµÃ™â€ Ã˜Â¯Ã™Ë†Ã™â€š Ã˜Â§Ã™â€žÃ™Ë†Ã˜Â§Ã˜Â±Ã˜Â¯ (Ã™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â§Ã˜Âª Ã™â€žÃ™â€¦ Ã˜ÂªÃ™â€ Ã˜ÂªÃ™â€¡Ã™Â Ã˜ÂµÃ™â€žÃ˜Â§Ã˜Â­Ã™Å Ã˜ÂªÃ™â€¡Ã˜Â§).
  /// Ã˜Â¨Ã˜Â¯Ã™Ë†Ã™â€  `orderBy` Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ˜Â§Ã˜Â³Ã˜ÂªÃ˜Â¹Ã™â€žÃ˜Â§Ã™â€¦ Ã™â€žÃ˜ÂªÃ™ÂÃ˜Â§Ã˜Â¯Ã™Å  Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã˜Â¬Ã˜Â© Ã˜Â¥Ã™â€žÃ™â€° Ã™ÂÃ™â€¡Ã˜Â±Ã˜Â³ Ã™â€¦Ã˜Â±Ã™Æ’Ã™â€˜Ã˜Â¨Ã˜â€º Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â±Ã˜ÂªÃ™Å Ã˜Â¨ Ã™Å Ã˜ÂªÃ™â€¦ Ã™â€¦Ã˜Â­Ã™â€žÃ™Å Ã˜Â§Ã™â€¹.
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

  /// Ã˜ÂªÃ˜Â±Ã˜ÂªÃ™Å Ã˜Â¨ Ã˜ÂªÃ˜ÂµÃ˜Â§Ã˜Â¹Ã˜Â¯Ã™Å  Ã˜Â²Ã™â€¦Ã™â€ Ã™Å Ã˜Â§Ã™â€¹. Ã™Å Ã™ÂÃ˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ `createdAt` Ã™â€žÃ™â€žÃ˜Â§Ã˜Â³Ã˜ÂªÃ˜Â¹Ã™â€žÃ˜Â§Ã™â€¦ Ã™â€žÃ˜Â£Ã™â€  Ã™Ë†Ã˜Â«Ã˜Â§Ã˜Â¦Ã™â€š Ã™â€šÃ˜Â¯Ã™Å Ã™â€¦Ã˜Â© Ã™â€šÃ˜Â¯ Ã™â€žÃ˜Â§ Ã˜ÂªÃ˜Â­Ã˜ÂªÃ™Ë†Ã™Å  `timestamp`Ã˜â€º
  /// Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â³Ã˜Â§Ã˜Â¦Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â¬Ã˜Â¯Ã™Å Ã˜Â¯Ã˜Â© Ã˜ÂªÃ™ÂÃ™Æ’Ã˜ÂªÃ˜Â¨ Ã˜Â¨Ã™â‚¬ `timestamp` Ã™Ë†`createdAt` (Ã™â€ Ã™ÂÃ˜Â³ Ã™â€žÃ˜Â­Ã˜Â¸Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â®Ã˜Â§Ã˜Â¯Ã™â€¦).
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
    /// Ã™â€¦Ã˜Â¹Ã˜Â±Ã™â€˜Ã™Â Firebase UID Ã™â€žÃ™â€žÃ˜Â·Ã˜Â±Ã™Â Ã˜Â§Ã™â€žÃ˜Â¢Ã˜Â®Ã˜Â± Ã˜Â¥Ã™â€  Ã™Ë†Ã™ÂÃ˜Â¬Ã˜Â¯ (Ã™â€¦Ã˜Â«Ã™â€ž [ChatService.getOrCreateChat])Ã˜â€º Ã™Ë†Ã˜Â¥Ã™â€žÃ˜Â§ Ã™Å Ã™ÂÃ˜Â³Ã˜ÂªÃ™â€ Ã˜ÂªÃ˜Â¬ Ã™â€¦Ã™â€  Ã˜Â§Ã™â€žÃ˜Â¨Ã˜Â±Ã™Å Ã˜Â¯.
    String? peerFirebaseUid,
    String? storeId,
    String? technicianId,
    String? customerId,
  }) async {
    final me = _normEmail(currentUserEmail);
    final peer = _normEmail(peerEmail);
    if (me.isEmpty || peer.isEmpty) throw ArgumentError('Ã˜Â¨Ã˜Â±Ã™Å Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â·Ã˜Â±Ã™ÂÃ™Å Ã™â€  Ã™â€¦Ã˜Â·Ã™â€žÃ™Ë†Ã˜Â¨');
    if (me == peer) throw ArgumentError('Ã™â€žÃ˜Â§ Ã™Å Ã™â€¦Ã™Æ’Ã™â€  Ã˜Â§Ã™â€žÃ˜Â¯Ã˜Â±Ã˜Â¯Ã˜Â´Ã˜Â© Ã™â€¦Ã˜Â¹ Ã™â€ Ã™ÂÃ˜Â³Ã™Æ’');

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null || authUser.uid.isEmpty) {
      throw StateError('Ã™â€žÃ˜Â§ Ã˜ÂªÃ™Ë†Ã˜Â¬Ã˜Â¯ Ã˜Â¬Ã™â€žÃ˜Â³Ã˜Â© Firebase Ã˜ÂµÃ˜Â§Ã™â€žÃ˜Â­Ã˜Â©');
    }

    final fbUser = await FirebaseChatAuth.ensureFirebaseUserForUnifiedChat(currentUserEmail);
    if (fbUser == null) throw StateError('Ã˜ÂªÃ˜Â¹Ã˜Â°Ã˜Â± Ã˜ÂªÃ˜Â³Ã˜Â¬Ã™Å Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â¯Ã˜Â®Ã™Ë†Ã™â€ž Ã˜Â¥Ã™â€žÃ™â€° Firebase');
    if (fbUser.uid.isEmpty || fbUser.uid != authUser.uid) {
      throw StateError('Ã˜ÂªÃ˜Â¹Ã˜Â§Ã˜Â±Ã˜Â¶ Ã™ÂÃ™Å  Ã™â€¦Ã˜Â¹Ã˜Â±Ã™Â Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ™Å  Ã™â€žÃ™â€žÃ™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â©');
    }
    await publishCurrentUserUidMapping(currentUserEmail);
    // Ã™Å Ã™â€¦Ã™â€žÃ˜Â£ Ã˜Â®Ã˜Â±Ã™Å Ã˜Â·Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â¨Ã˜Â±Ã™Å Ã˜Â¯Ã¢â€ â€™UID Ã™â€žÃ™â€žÃ˜Â·Ã˜Â±Ã™Â Ã˜Â§Ã™â€žÃ˜Â¢Ã˜Â®Ã˜Â± Ã˜Â¹Ã™â€ Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â¥Ã™â€¦Ã™Æ’Ã˜Â§Ã™â€  (Ã™â€šÃ˜Â¨Ã™â€ž Ã˜Â¥Ã™â€ Ã˜Â´Ã˜Â§Ã˜Â¡ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â©).
    await _ensureUserExistsInFirestore(peerEmail);

    final buyerUid = fbUser.uid;
    var sellerUid = (peerFirebaseUid ?? (throw StateError('NULL_RESPONSE'))).trim();
    if (sellerUid.isEmpty) {
      sellerUid = await _lookupPeerFirebaseUid(peerEmail) ??
          (throw StateError('NULL_RESPONSE'));
    }
    // Ã™â€žÃ˜Â§ Ã™Å Ã™â€¦Ã™Æ’Ã™â€  Ã™â€žÃ™â‚¬ Firebase Auth Ã˜Â¹Ã™â€žÃ™â€° Ã˜Â§Ã™â€žÃ˜Â¹Ã™â€¦Ã™Å Ã™â€ž Ã˜Â¬Ã™â€žÃ˜Â¨ UID Ã™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Ã˜Â¢Ã˜Â®Ã˜Â±Ã˜â€º Ã˜Â¥Ã™â€  Ã™ÂÃ˜Â´Ã™â€žÃ˜Âª Ã˜Â§Ã™â€žÃ˜Â®Ã˜Â±Ã™Å Ã˜Â·Ã˜Â© Ã™â€ Ã™ÂÃ˜Â¨Ã™â€žÃ™â€˜Ã˜Âº Ã˜Â¨Ã™Ë†Ã˜Â¶Ã™Ë†Ã˜Â­ (Ã™â€šÃ˜Â¯ Ã˜ÂªÃ˜Â­Ã˜ÂªÃ˜Â§Ã˜Â¬ Ã™â€žÃ˜Â§Ã˜Â­Ã™â€šÃ˜Â§Ã™â€¹ Cloud Function).
    if (sellerUid.isEmpty) {
      // `fetchSignInMethodsForEmail` Ã˜Â£Ã™ÂÃ˜Â²Ã™Å Ã™â€ž Ã™â€¦Ã™â€  firebase_auth 6+ (Ã˜Â­Ã™â€¦Ã˜Â§Ã™Å Ã˜Â© Ã™â€¦Ã™â€  Ã˜ÂªÃ˜Â¹Ã˜Â¯Ã˜Â§Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â¨Ã˜Â±Ã™Å Ã˜Â¯).
      throw StateError(
        'Ã˜ÂªÃ˜Â¹Ã˜Â°Ã˜Â± Ã˜Â±Ã˜Â¨Ã˜Â· Ã˜Â¨Ã˜Â±Ã™Å Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â·Ã˜Â±Ã™Â Ã˜Â§Ã™â€žÃ˜Â¢Ã˜Â®Ã˜Â± Ã˜Â¨Ã™â€¦Ã˜Â¹Ã˜Â±Ã™â€˜Ã™Â Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦. Ã™Å Ã˜Â¬Ã˜Â¨ Ã˜Â£Ã™â€  Ã™Å Ã˜Â³Ã˜Â¬Ã™â€˜Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â·Ã˜Â±Ã™Â Ã˜Â§Ã™â€žÃ˜Â¢Ã˜Â®Ã˜Â± Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â·Ã˜Â¨Ã™Å Ã™â€š Ã™â€¦Ã˜Â±Ã˜Â©Ã˜Å’ '
        'Ã˜Â£Ã™Ë† Ã˜Â±Ã˜Â¨Ã˜Â· Ã˜Â§Ã™â€žÃ˜Â¨Ã˜Â±Ã™Å Ã˜Â¯ Ã™ÂÃ™Å  firebase_uid_by_email Ã™â€¦Ã™â€  Ã˜Â§Ã™â€žÃ˜Â¥Ã˜Â¯Ã˜Â§Ã˜Â±Ã˜Â©. '
        '(Ã˜Â¬Ã™â€žÃ˜Â¨ UID Ã™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Ã˜Â¢Ã˜Â®Ã˜Â± Ã˜ÂºÃ™Å Ã˜Â± Ã™â€¦Ã˜ÂªÃ˜Â§Ã˜Â­ Ã™â€¦Ã™â€  Ã˜Â§Ã™â€žÃ˜Â¹Ã™â€¦Ã™Å Ã™â€ž Ã¢â‚¬â€ Ã™â€šÃ˜Â¯ Ã˜ÂªÃ˜Â­Ã˜ÂªÃ˜Â§Ã˜Â¬ Cloud Function.)',
      );
    }

    // Ã˜ÂªÃ˜Â¬Ã™â€¦Ã™Å Ã˜Â¹ participants Ã˜Â¨Ã˜Â¯Ã™Ë†Ã™â€  Ã˜ÂªÃ™Æ’Ã˜Â±Ã˜Â§Ã˜Â± Ã¢â‚¬â€ Ã˜Â¶Ã˜Â±Ã™Ë†Ã˜Â±Ã™Å  Ã™â€žÃ™â€šÃ™Ë†Ã˜Â§Ã˜Â¹Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â£Ã™â€¦Ã˜Â§Ã™â€  (Ã™â€šÃ˜Â±Ã˜Â§Ã˜Â¡Ã˜Â©/Ã˜Â±Ã˜Â³Ã˜Â§Ã˜Â¦Ã™â€ž) Ã™â€žÃ™Æ’Ã™â€žÃ˜Â§ Ã˜Â§Ã™â€žÃ˜Â·Ã˜Â±Ã™ÂÃ™Å Ã™â€  Ã˜Â¹Ã™â€ Ã˜Â¯ Ã˜ÂªÃ™Ë†Ã™ÂÃ˜Â± UID.
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
    final resolvedStoreId = storeId;
    if (resolvedStoreId == null || resolvedStoreId.trim().isEmpty) {
      throw StateError('INVALID_ID');
    }
    final resolvedTechnicianId = technicianId;
    if (resolvedTechnicianId == null || resolvedTechnicianId.trim().isEmpty) {
      throw StateError('INVALID_ID');
    }
    final resolvedCustomerId = customerId != null && customerId.trim().isNotEmpty ? customerId : buyerUid;
    if (resolvedCustomerId.trim().isEmpty) {
      throw StateError('INVALID_ID');
    }
    final normalizedStoreId = resolvedStoreId.trim();
    final normalizedTechnicianId = resolvedTechnicianId.trim();
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
          'lastMessagePreview': seedProductCard ? 'Ã°Å¸â€œÂ¦ Ã˜Â¨Ã˜Â·Ã˜Â§Ã™â€šÃ˜Â© Ã™â€¦Ã™â€ Ã˜ÂªÃ˜Â¬' : '',
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
            'text': 'Ã˜Â§Ã˜Â³Ã˜ÂªÃ™ÂÃ˜Â³Ã˜Â§Ã˜Â± Ã˜Â¹Ã™â€  Ã™â€¡Ã˜Â°Ã˜Â§ Ã˜Â§Ã™â€žÃ™â€¦Ã™â€ Ã˜ÂªÃ˜Â¬',
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
        // Ã™â€šÃ™Ë†Ã˜Â§Ã˜Â¹Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â£Ã™â€¦Ã˜Â§Ã™â€  Ã˜ÂªÃ˜Â¹Ã˜ÂªÃ™â€¦Ã˜Â¯ Ã˜Â¹Ã™â€žÃ™â€° `participants`: Ã™â€ Ã˜Â¶Ã™â€¦Ã™â€  Ã˜Â¯Ã˜Â§Ã˜Â¦Ã™â€¦Ã˜Â§Ã™â€¹ Ã˜Â¶Ã™â€¦ buyer Ã™Ë†seller UID Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ™Å Ã™Å½Ã™Å Ã™â€ .
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
    if (user == null) throw StateError('Ã˜ÂºÃ™Å Ã˜Â± Ã™â€¦Ã˜Â³Ã˜Â¬Ã™â€˜Ã™â€ž Ã™ÂÃ™Å  Firebase');

    final ref = _db.collection(_col).doc(chatId);
    final chatSnap = await ref.get();
    final cd = chatSnap.data() ?? {};
    final buyerId = cd['buyer_id'] as String? ?? (throw StateError('NULL_RESPONSE'));
    final sellerId = cd['seller_id'] as String? ?? (throw StateError('NULL_RESPONSE'));
    final be = _normEmail(cd['buyer_email'] as String? ?? (throw StateError('NULL_RESPONSE')));
    final se = _normEmail(cd['seller_email'] as String? ?? (throw StateError('NULL_RESPONSE')));
    final me = _normEmail(senderEmail);
    if (me != be && me != se) {
      throw StateError('Ã˜Â§Ã™â€žÃ˜Â¨Ã˜Â±Ã™Å Ã˜Â¯ Ã™â€žÃ˜Â§ Ã™Å Ã˜Â·Ã˜Â§Ã˜Â¨Ã™â€š Ã˜Â£Ã˜Â­Ã˜Â¯ Ã˜Â·Ã˜Â±Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â©');
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
          type: (cd['kind']?.toString().trim().isNotEmpty ?? (throw StateError('NULL_RESPONSE')))
              ? cd['kind'].toString()
              : 'general',
        ),
      );
    } on Object {
      debugPrint('UnifiedChatRepository.postChatMessageSent failed');
    }
  }

  /// Ã™Å Ã™â€¦Ã™â€žÃ˜Â£ `buyer_id` Ã˜Â£Ã™Ë† `seller_id` Ã˜Â¥Ã™â€  Ã™Æ’Ã˜Â§Ã™â€ Ã˜Â§ Ã™ÂÃ˜Â§Ã˜Â±Ã˜ÂºÃ™Å½Ã™Å Ã™â€  Ã˜Â¨Ã˜Â¹Ã˜Â¯ Ã˜ÂªÃ˜Â³Ã˜Â¬Ã™Å Ã™â€ž Firebase Ã¢â‚¬â€ Ã™â€¦Ã˜Â·Ã™â€žÃ™Ë†Ã˜Â¨ Ã˜Â¹Ã™â€ Ã˜Â¯ Ã™â€šÃ™Ë†Ã˜Â§Ã˜Â¹Ã˜Â¯ Ã˜Â£Ã™â€¦Ã˜Â§Ã™â€  Ã˜ÂªÃ˜Â¹Ã˜ÂªÃ™â€¦Ã˜Â¯ Ã˜Â¹Ã™â€žÃ™â€° UID Ã™ÂÃ™â€šÃ˜Â·.
  Future<void> ensureParticipantUidOnChat(String chatId, String currentUserEmail) async {
    try {
      final fbUser = await FirebaseChatAuth.ensureFirebaseUserForUnifiedChat(currentUserEmail);
      if (fbUser == null || fbUser.uid.isEmpty) {
        debugPrint('ensureParticipantUidOnChat: Ã™â€žÃ˜Â§ Ã™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Firebase Ã˜ÂµÃ˜Â§Ã™â€žÃ˜Â­');
        return;
      }
      await publishCurrentUserUidMapping(currentUserEmail);
      final ref = _db.collection(_col).doc(chatId);
      final snap = await ref.get();
      if (!snap.exists) {
        debugPrint('ensureParticipantUidOnChat: Ã™â€žÃ˜Â§ Ã™Ë†Ã˜Â«Ã™Å Ã™â€šÃ˜Â© Ã™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â© Ã™â€žÃ™â‚¬ $chatId');
        return;
      }
      final d = snap.data() ?? {};
      final me = _normEmail(currentUserEmail);
      final be = _normEmail(d['buyer_email'] as String? ?? (throw StateError('NULL_RESPONSE')));
      final se = _normEmail(d['seller_email'] as String? ?? (throw StateError('NULL_RESPONSE')));
      final participantEmails = (d['participantEmails'] as List?)
              ?.map((e) => _normEmail(''))
              .toList() ??
          <String>[];
      final isParticipant = me == be || me == se || participantEmails.contains(me);
      if (!isParticipant) {
        debugPrint(
          'ensureParticipantUidOnChat: Ã˜Â§Ã™â€žÃ˜Â¨Ã˜Â±Ã™Å Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ™Å  Ã™â€žÃ™Å Ã˜Â³ Ã˜Â·Ã˜Â±Ã™ÂÃ˜Â§Ã™â€¹ Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â© (chatId=$chatId)',
        );
        return;
      }
      final upd = <String, dynamic>{
        // Ã™â€¦Ã˜Â·Ã™â€žÃ™Ë†Ã˜Â¨ Ã™â€žÃ™â€šÃ˜Â±Ã˜Â§Ã˜Â¡Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â© Ã™Ë†Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â³Ã˜Â§Ã˜Â¦Ã™â€ž Ã˜Â­Ã˜Â³Ã˜Â¨ Ã˜Â§Ã™â€žÃ™â€šÃ™Ë†Ã˜Â§Ã˜Â¹Ã˜Â¯ Ã¢â‚¬â€ Ã™Å Ã˜Â¬Ã˜Â¨ Ã˜Â£Ã™â€  Ã™Å Ã™Æ’Ã™Ë†Ã™â€  UID Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ™Å  Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ™â€¦Ã˜ÂµÃ™ÂÃ™Ë†Ã™ÂÃ˜Â©.
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


