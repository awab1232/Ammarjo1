/**
 * اختياري — التطبيق يعرض إشعارات محلية عبر Firestore + flutter_local_notifications بدون نشر دالة.
 * يمكنك حذف هذا الملف أو تركيه لاستخدام لاحق مع FCM من الخادم.
 */
const functions = require('firebase-functions/v1');
const { onCall } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');

admin.initializeApp();

async function emitChatEvent(eventType, payload) {
  try {
    await admin.firestore().collection('chat_events').add({
      type: eventType,
      payload,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.warn(`emitChatEvent failed for ${eventType}:`, e);
  }
}

// NOTE: في Firebase params لا يوجد defineJsonSecret حالياً في Node runtime،
// لذلك نستخدم Secret واحد نصّي JSON ونقوم بعمل JSON.parse.
const emailConfigSecret = defineSecret('EMAIL_CONFIG');

function readEmailConfig() {
  // أولاً: Secret (موصى به)
  const rawSecret = emailConfigSecret.value();
  if (rawSecret && String(rawSecret).trim()) {
    const parsed = JSON.parse(String(rawSecret));
    return {
      host: String(parsed.host || '').trim(),
      port: Number(parsed.port || 587),
      user: String(parsed.user || '').trim(),
      pass: String(parsed.pass || '').trim(),
      from: String(parsed.from || 'no-reply@ammarjo.app').trim(),
      secure: Boolean(parsed.secure),
    };
  }
  // ثانياً: fallback من .env / environment (للتطوير المحلي)
  return {
    host: String(process.env.SMTP_HOST || '').trim(),
    port: Number(process.env.SMTP_PORT || 587),
    user: String(process.env.SMTP_USER || '').trim(),
    pass: String(process.env.SMTP_PASS || '').trim(),
    from: String(process.env.SMTP_FROM || 'no-reply@ammarjo.app').trim(),
    secure: String(process.env.SMTP_SECURE || 'false') === 'true',
  };
}

exports.sendEmail = onCall({ secrets: [emailConfigSecret] }, async (request) => {
  if (!request.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const to = String(request.data?.to || '').trim();
  const subject = String(request.data?.subject || '').trim();
  const body = String(request.data?.body || '').trim();
  const htmlBody = String(request.data?.htmlBody || '').trim();
  if (!to || !subject || !body) {
    throw new functions.https.HttpsError('invalid-argument', 'to, subject and body are required');
  }

  let config;
  try {
    config = readEmailConfig();
  } catch (e) {
    console.warn('Email config parse error:', e);
    throw new functions.https.HttpsError('failed-precondition', 'Email service not configured');
  }
  if (!config.host || !config.user || !config.pass) {
    throw new functions.https.HttpsError('failed-precondition', 'Email service not configured');
  }

  const transporter = nodemailer.createTransport({
    host: config.host,
    port: config.port,
    secure: config.secure,
    auth: { user: config.user, pass: config.pass },
  });
  await transporter.sendMail({
    from: config.from,
    to,
    subject,
    text: body,
    html: htmlBody || body,
  });
  return { success: true };
});

exports.sendPushNotification = onCall(async (request) => {
  if (!request.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const userId = String(request.data?.userId || '').trim();
  const title = String(request.data?.title || '').trim();
  const body = String(request.data?.body || '').trim();
  const notificationDataRaw = request.data?.notificationData || {};

  if (!userId || !title || !body) {
    throw new functions.https.HttpsError('invalid-argument', 'userId, title and body are required');
  }

  const userDoc = await admin.firestore().collection('users').doc(userId).get();
  const fcmToken = userDoc.data() && userDoc.data().fcmToken ? String(userDoc.data().fcmToken) : '';
  if (!fcmToken) {
    return { success: false, message: 'No FCM token' };
  }

  const notificationData = {};
  Object.keys(notificationDataRaw).forEach((k) => {
    if (!k) return;
    const v = notificationDataRaw[k];
    if (v === undefined || v === null) return;
    notificationData[k] = String(v);
  });

  await admin.messaging().send({
    token: fcmToken,
    notification: { title: title || 'Ammarjo', body },
    data: {
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
      ...notificationData,
    },
    android: {
      priority: 'high',
      notification: {
        channel_id: 'ammarjo_high_importance',
        icon: 'ic_launcher',
        color: '#FF6B00',
        sound: 'default',
        tag: 'ammarjo',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
          badge: 1,
        },
      },
    },
  });

  return { success: true };
});

/**
 * عند إنشاء رسالة جديدة: إشعار FCM للمستقبل (البائع/مقدّم الخدمة) إن وُجد رمز.
 */
exports.onUnifiedChatMessage = functions.firestore
  .document('unified_chats/{chatId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const msg = snap.data() || {};
    const chatId = context.params.chatId;
    const messageId = context.params.messageId;

    const chatSnap = await admin.firestore().doc(`unified_chats/${chatId}`).get();
    const chat = chatSnap.data() || {};
    await emitChatEvent('message.sent', {
      chatId,
      messageId,
      conversationType: chat.type || chat.kind || null,
      senderId: msg.senderId || null,
      receiverId: msg.receiverId || null,
    });
    const productName = chat.contextTitle || 'المنتج';

    let receiverId = (msg.receiverId || '').trim();

    if (!receiverId) {
      const se = String(chat.seller_email || '').toLowerCase();
      const be = String(chat.buyer_email || '').toLowerCase();
      const senderEmail = String(msg.senderEmail || '').toLowerCase();
      const peerEmail = senderEmail === be ? se : be;
      if (peerEmail) {
        const map = await admin.firestore().doc(`firebase_uid_by_email/${peerEmail}`).get();
        receiverId = (map.data() && map.data().uid) ? String(map.data().uid) : '';
      }
    }

    if (!receiverId) {
      return null;
    }

    const senderId = String(msg.senderId || '');
    if (senderId && receiverId === senderId) {
      return null;
    }

    const userDoc = await admin.firestore().doc(`users/${receiverId}`).get();
    const token = userDoc.data() && userDoc.data().fcmToken;
    if (!token) {
      return null;
    }

    const body = `لديك رسالة جديدة بخصوص ${productName}`;

    await admin.messaging().send({
      token,
      notification: {
        title: 'Ammarjo',
        body,
      },
      data: {
        chatId,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      android: {
        priority: 'high',
        notification: {
          channel_id: 'ammarjo_high_importance',
          icon: 'ic_launcher',
          color: '#FF6B00',
          sound: 'default',
          tag: 'ammarjo',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    });

    return null;
  });

exports.onUnifiedChatConversationCreated = functions.firestore
  .document('unified_chats/{chatId}')
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    await emitChatEvent('conversation.created', {
      chatId: context.params.chatId,
      conversationType: data.type || data.kind || null,
      customerId: data.customerId || data.buyer_id || null,
      storeId: data.storeId || null,
      technicianId: data.technicianId || data.seller_id || null,
    });
    return null;
  });

exports.onUnifiedChatMessageRead = functions.firestore
  .document('unified_chats/{chatId}/messages/{messageId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const becameRead = (!before.readAt && !!after.readAt) || (before.isRead !== true && after.isRead === true);
    if (!becameRead) return null;
    await emitChatEvent('message.read', {
      chatId: context.params.chatId,
      messageId: context.params.messageId,
      readerId: after.readBy || null,
      senderId: after.senderId || null,
    });
    return null;
  });

exports.onSupportConversationCreated = functions.firestore
  .document('support_chats/{chatId}')
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    await emitChatEvent('conversation.created', {
      chatId: context.params.chatId,
      conversationType: 'support',
      customerId: data.customerId || data.userId || null,
    });
    return null;
  });

exports.onSupportMessageSent = functions.firestore
  .document('support_chats/{chatId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const msg = snap.data() || {};
    await emitChatEvent('message.sent', {
      chatId: context.params.chatId,
      messageId: context.params.messageId,
      conversationType: 'support',
      senderId: msg.senderId || null,
    });
    return null;
  });

/**
 * عند اكتمال الطلب (delivered): تسجيل عمولة 5% مرة واحدة لكل order.
 */
exports.onOrderDelivered = functions.firestore
  .document('orders/{orderId}')
  .onUpdate(async (change, context) => {
    try {
      const before = change.before.data() || {};
      const after = change.after.data() || {};
      const beforeStatus = String(before.status || '').toLowerCase();
      const afterStatus = String(after.status || '').toLowerCase();

      if (beforeStatus === afterStatus) return null;
      if (!['delivered', 'completed', 'تم التسليم'].includes(afterStatus)) return null;

      const orderId = context.params.orderId;
      const storeId = String(after.storeId || '').trim();
      if (!storeId) return null;

      const commissionRef = admin
        .firestore()
        .collection('commissions')
        .doc(storeId)
        .collection('orders')
        .doc(orderId);

      const existing = await commissionRef.get();
      if (existing.exists) return null;

      const totalRaw = after.totalNumeric ?? after.total;
      const total = Number(totalRaw || 0);
      if (!Number.isFinite(total) || total <= 0) return null;

      const commissionRate = 0.05;
      const commissionAmount = Number((total * commissionRate).toFixed(3));
      const netAmount = Number((total - commissionAmount).toFixed(3));

      const rootRef = admin.firestore().collection('commissions').doc(storeId);
      await admin.firestore().runTransaction(async (tx) => {
        const rootSnap = await tx.get(rootRef);
        const rootData = rootSnap.data() || {};
        const prevTotal = Number(rootData.totalCommission || 0);
        const prevBalance = Number(rootData.balance || 0);
        const prevPaid = Number(rootData.totalPaid || 0);

        tx.set(
          commissionRef,
          {
            orderId,
            storeId,
            storeName: String(after.storeName || ''),
            orderTotal: total,
            commissionRate,
            commissionAmount,
            netAmount,
            paid: false,
            paymentStatus: 'unpaid',
            date: admin.firestore.FieldValue.serverTimestamp(),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        tx.set(
          rootRef,
          {
            storeId,
            storeName: String(after.storeName || ''),
            totalCommission: Number((prevTotal + commissionAmount).toFixed(3)),
            totalPaid: Number(prevPaid.toFixed(3)),
            balance: Number((prevBalance + commissionAmount).toFixed(3)),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      });

      return null;
    } catch (e) {
      console.error('onOrderDelivered failed:', e);
      return null;
    }
  });

/**
 * إضافة نقاط الولاء عند تحول الطلب إلى delivered (مرة واحدة لكل طلب).
 * تُنفذ في الخلفية عبر Admin SDK لتجنب أي كتابة نقاط من العميل.
 */
exports.addLoyaltyPoints = functions.firestore
  .document('orders/{orderId}')
  .onUpdate(async (change, context) => {
    const newData = change.after.data() || {};
    const oldData = change.before.data() || {};

    const newStatus = String(newData.status || '').toLowerCase();
    const oldStatus = String(oldData.status || '').toLowerCase();
    if (!['delivered', 'completed', 'تم التسليم'].includes(newStatus)) {
      return null;
    }
    if (['delivered', 'completed', 'تم التسليم'].includes(oldStatus)) {
      return null;
    }

    const orderId = String(context.params.orderId || '').trim();
    const customerId = String(newData.customerId || newData.customerUid || '').trim();
    if (!orderId || !customerId) return null;

    const totalRaw = newData.totalAmount ?? newData.totalNumeric ?? newData.total;
    const parsed = Number(totalRaw || 0);
    const pointsToAdd = Math.floor(parsed);
    if (!Number.isFinite(pointsToAdd) || pointsToAdd <= 0) return null;

    const userRef = admin.firestore().collection('users').doc(customerId);
    const orderRef = admin.firestore().collection('orders').doc(orderId);
    const userOrderRef = admin
      .firestore()
      .collection('users')
      .doc(customerId)
      .collection('orders')
      .doc(orderId);

    try {
      await admin.firestore().runTransaction(async (tx) => {
        const userSnap = await tx.get(userRef);
        const userData = userSnap.data() || {};
        const awarded = Array.isArray(userData.pointsAwardedOrders)
          ? userData.pointsAwardedOrders.map((v) => String(v))
          : [];
        if (awarded.includes(orderId)) return;

        tx.set(
          userRef,
          {
            loyaltyPoints: admin.firestore.FieldValue.increment(pointsToAdd),
            pointsAwardedOrders: admin.firestore.FieldValue.arrayUnion([orderId]),
            pointsHistory: admin.firestore.FieldValue.arrayUnion([
              {
                amount: pointsToAdd,
                reason: 'تم تسليم الطلب',
                orderId,
                date: admin.firestore.Timestamp.now(),
              },
            ]),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        tx.set(
          orderRef,
          {
            pointsAdded: true,
            pointsEarned: pointsToAdd,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        tx.set(
          userOrderRef,
          {
            pointsAdded: true,
            pointsEarned: pointsToAdd,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      });
      console.log(`Added ${pointsToAdd} loyalty points to user ${customerId} for order ${orderId}`);
    } catch (error) {
      console.error('addLoyaltyPoints failed:', error);
    }
    return null;
  });
