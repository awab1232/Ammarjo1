import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';

class EmailService {
  EmailService._();
  static final EmailService instance = EmailService._();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<void> sendEmail({
    required String to,
    required String subject,
    required String body,
    String? htmlBody,
  }) async {
    try {
      final callable = _functions.httpsCallable('sendEmail');
      await callable.call(<String, dynamic>{
        'to': to.trim(),
        'subject': subject.trim(),
        'body': body,
        if (htmlBody != null && htmlBody.trim().isNotEmpty) 'htmlBody': htmlBody,
      });
    } on Object catch (e, st) {
      debugPrint('FIREBASE ERROR: $e');
      debugPrint('[EmailService] sendEmail failed\n$st');
      rethrow;
    }
  }

  Future<void> sendOrderConfirmation(String email, String orderId, double total) {
    return sendEmail(
      to: email,
      subject: 'تأكيد طلبك #$orderId',
      body: 'تم استلام طلبك بنجاح. رقم الطلب: $orderId\nالإجمالي: ${total.toStringAsFixed(2)} د.أ',
    );
  }

  Future<void> sendOrderStatusUpdate(String email, String orderId, String status) {
    return sendEmail(
      to: email,
      subject: 'تحديث حالة الطلب #$orderId',
      body: 'تم تحديث حالة طلبك #$orderId إلى: $status',
    );
  }

  Future<void> sendStoreApproval(String email, String storeName) {
    return sendEmail(
      to: email,
      subject: 'تم قبول طلب فتح المتجر',
      body: 'تم قبول طلب فتح متجر $storeName. يمكنك الآن إدارة متجرك.',
    );
  }

  Future<void> sendStoreRejection(String email, String storeName, String reason) {
    return sendEmail(
      to: email,
      subject: 'تم رفض طلب فتح المتجر',
      body: 'نعتذر، تم رفض طلب متجر $storeName.\nالسبب: $reason',
    );
  }

  Future<void> sendWholesalerApproval(String email, String wholesalerName) {
    return sendEmail(
      to: email,
      subject: 'تم قبول طلب تسجيل تاجر الجملة',
      body: 'تم قبول طلب تسجيل $wholesalerName كتاجر جملة.',
    );
  }

  Future<void> sendWholesalerRejection(String email, String wholesalerName, String reason) {
    return sendEmail(
      to: email,
      subject: 'تم رفض طلب تسجيل تاجر الجملة',
      body: 'تم رفض طلب تسجيل $wholesalerName.\nالسبب: $reason',
    );
  }

  Future<void> sendPasswordReset(String email, String resetLink) {
    return sendEmail(
      to: email,
      subject: 'إعادة تعيين كلمة المرور',
      body: 'لطلب إعادة تعيين كلمة المرور، استخدم الرابط التالي:\n$resetLink',
      htmlBody: '<p>لطلب إعادة تعيين كلمة المرور، استخدم الرابط التالي:</p><p><a href="$resetLink">$resetLink</a></p>',
    );
  }
}
