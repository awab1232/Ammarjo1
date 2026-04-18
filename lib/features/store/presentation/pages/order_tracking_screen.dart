import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/order_status.dart';
import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/safe_tracking_url.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/data/repositories/customer_ops_repository.dart';
import '../../../reviews/data/reviews_repository.dart';
import '../../../../core/contracts/feature_unit.dart';
import '../store_controller.dart';
import 'advanced_order_tracking_screen.dart';

Future<void> _launchSafeTrackingUrl(String? raw) async {
  final u = SafeTrackingUrl.sanitize(raw);
  if (u == null) return;
  final uri = Uri.parse(u);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// قائمة الطلبات. التفاصيل عبر [AdvancedOrderTrackingScreen] تستخدم `BackendOrderRepository.watchOrderDocument` لكل مسارات المتجر (بما فيها تبويب «أدوات منزلية») عند تفعيل `BackendOrdersConfig`.
class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({super.key, this.appBarTitle = 'تتبع طلبي'});

  final String appBarTitle;

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  static const int _kOrdersPageSize = 20;
  int _ordersLimit = _kOrdersPageSize;

  int _statusStep(String status) {
    final s = OrderStatus.toEnglish(status);
    switch (s) {
      case 'cancelled':
      case 'refunded':
      case 'failed':
        return -1;
      case 'processing':
        return 1;
      case 'shipped':
        return 2;
      case 'delivered':
      case 'completed':
        return 3;
      case 'pending':
      default:
        return 0;
    }
  }

  bool _canCancel(String status) {
    final s = OrderStatus.toEnglish(status);
    return s == 'pending' || s == 'processing';
  }

  String _ordersLoadError(Object? error) {
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'صلاحيات Firestore تمنع قراءة الطلبات (permission-denied). راجع Rules للمسار users/{uid}/orders.';
      }
      return error.message?.isNotEmpty == true ? error.message! : 'تعذّر تحميل الطلبات.';
    }
    if (error is TimeoutException) {
      return 'انتهت مهلة الاتصال. تحقق من الشبكة وحاول مرة أخرى.';
    }
    return 'تعذّر تحميل الطلبات.';
  }

  Future<void> _confirmCancel(BuildContext context, TrackOrderItem o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('إلغاء الطلب', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        content: Text('هل أنت متأكد من إلغاء الطلب؟', style: GoogleFonts.tajawal()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('لا', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('نعم، إلغاء الطلب', style: GoogleFonts.tajawal(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final cancelled = await CustomerOpsRepository.instance.cancelFirebaseOrderForCustomer(
      uid: uid,
      userOrderDocId: o.id,
      rootOrderId: o.firebaseOrderId ?? o.id,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cancelled ? 'تم إلغاء الطلب' : 'تعذّر إلغاء الطلب. تحقق من الاتصال أو من حالة الطلب.',
          style: GoogleFonts.tajawal(),
        ),
      ),
    );
  }

  Future<void> _rateDeliveredOrder(BuildContext context, TrackOrderItem order) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    double overall = 5;
    double delivery = 5;
    double quality = 5;
    final commentCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('قيّم الطلب', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('التجربة العامة', textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                Slider(
                  value: overall,
                  min: 1,
                  max: 5,
                  divisions: 4,
                  activeColor: AppColors.primaryOrange,
                  label: overall.toStringAsFixed(0),
                  onChanged: (v) => setLocal(() => overall = v),
                ),
                Text('سرعة التوصيل', textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                Slider(
                  value: delivery,
                  min: 1,
                  max: 5,
                  divisions: 4,
                  activeColor: AppColors.primaryOrange,
                  label: delivery.toStringAsFixed(0),
                  onChanged: (v) => setLocal(() => delivery = v),
                ),
                Text('جودة المنتجات', textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                Slider(
                  value: quality,
                  min: 1,
                  max: 5,
                  divisions: 4,
                  activeColor: AppColors.primaryOrange,
                  label: quality.toStringAsFixed(0),
                  onChanged: (v) => setLocal(() => quality = v),
                ),
                TextField(
                  controller: commentCtrl,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'تعليق اختياري',
                    hintStyle: GoogleFonts.tajawal(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء', style: GoogleFonts.tajawal())),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('إرسال', style: GoogleFonts.tajawal())),
          ],
        ),
      ),
    );
    final comment = commentCtrl.text;
    commentCtrl.dispose();
    if (confirmed != true) return;
    final state = await ReviewsRepository.instance.createReview(
      targetId: (order.firebaseOrderId ?? order.id).trim(),
      targetType: 'order',
      userId: user.uid,
      userName: user.displayName?.trim().isNotEmpty == true ? user.displayName!.trim() : 'مستخدم',
      rating: overall,
      comment: comment,
      orderId: (order.firebaseOrderId ?? order.id).trim(),
      deliverySpeed: delivery,
      productQuality: quality,
    );
    if (!context.mounted) return;
    final message = switch (state) {
      FeatureSuccess<FeatureUnit>() => 'تم إرسال تقييم الطلب',
      FeatureFailure<FeatureUnit>(:final message) => message,
      _ => 'تعذّر إرسال التقييم',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: GoogleFonts.tajawal())));
  }

  @override
  Widget build(BuildContext context) {
    final profileEmail = context.watch<StoreController>().profile?.email.trim() ?? '';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: const AppBarBackButton(),
        title: Text(widget.appBarTitle, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
      ),
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnap) {
          final authEmail = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
          final email = authEmail.isNotEmpty ? authEmail : profileEmail;
          if (email.isEmpty) {
            return Center(
              child: Text(
                'سجّل الدخول لعرض حالة طلباتك.',
                style: GoogleFonts.tajawal(color: AppColors.textSecondary),
              ),
            );
          }
          return StreamBuilder<FeatureState<List<TrackOrderItem>>>(
            key: ValueKey<int>(_ordersLimit),
            stream: CustomerOpsRepository.instance.watchOrders(email, limit: _ordersLimit),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _ordersLoadError(snapshot.error),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tajawal(),
                    ),
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppColors.orange));
              }
              final state = snapshot.requireData;
              final items = switch (state) {
                FeatureSuccess(:final data) => data,
                _ => <TrackOrderItem>[],
              };
              if (items.isEmpty) {
                return Center(
                  child: Text(
                    'لا يوجد عناصر في هذا القسم حالياً.',
                    style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                  ),
                );
              }
              final showLoadMore = items.length >= _ordersLimit;
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length + (showLoadMore ? 1 : 0),
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (showLoadMore && index == items.length) {
                    return Center(
                      child: FilledButton.icon(
                        onPressed: () => setState(() => _ordersLimit += _kOrdersPageSize),
                        icon: const Icon(Icons.expand_more),
                        label: Text('تحميل المزيد', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                      ),
                    );
                  }
                  final o = items[index];
                  final step = _statusStep(o.status);
                  final totalLine = o.totalLabel ?? '';
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (o.storeName != null && o.storeName!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Icon(Icons.store_mall_directory_outlined, size: 18, color: AppColors.primaryOrange),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      o.storeName!,
                                      textAlign: TextAlign.right,
                                      style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 15),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Text(o.title, textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                          if (o.items.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            ...o.items.map(
                              (it) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        it['name']?.toString() ?? '',
                                        textAlign: TextAlign.right,
                                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '×${it['quantity'] ?? 1}',
                                      style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${it['price'] ?? ''}',
                                      style: GoogleFonts.tajawal(fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (totalLine.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'الإجمالي: $totalLine د.أ',
                                textAlign: TextAlign.right,
                                style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, color: AppColors.primaryOrange),
                              ),
                            ),
                          Builder(
                            builder: (context) {
                              final fallbackPoints = double.tryParse(
                                    totalLine.replaceAll(RegExp(r'[^0-9.]'), ''),
                                  )?.floor() ??
                                  0;
                              final expectedPoints = o.pointsEarned > 0 ? o.pointsEarned : fallbackPoints;
                              if (expectedPoints <= 0) return const SizedBox.shrink();
                              final added = o.pointsAdded;
                              return Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: added ? Colors.green.shade50 : Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      added ? Icons.loyalty : Icons.info_outline,
                                      size: 18,
                                      color: added ? Colors.green.shade700 : Colors.blue.shade700,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        added
                                            ? 'تم إضافة $expectedPoints نقطة إلى رصيدك'
                                            : 'ستُضاف $expectedPoints نقاط إلى رصيدك بعد تسليم الطلب',
                                        textAlign: TextAlign.right,
                                        style: GoogleFonts.tajawal(
                                          fontWeight: FontWeight.w700,
                                          color: added ? Colors.green.shade700 : Colors.blue.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          if (o.pointsAdded)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'النقاط المكتسبة: ${o.pointsEarned}',
                                textAlign: TextAlign.right,
                                style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, color: Colors.green.shade700),
                              ),
                            ),
                          const SizedBox(height: 10),
                          if (step < 0)
                            Text(
                              'تم إلغاء الطلب أو استرداد المبلغ.',
                              textAlign: TextAlign.right,
                              style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                            )
                          else
                            _OrderStatusStepper(currentStep: step),
                          Builder(
                            builder: (context) {
                              final safeUrl = SafeTrackingUrl.sanitize(o.trackingUrl);
                              if (safeUrl == null) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.orange,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size.fromHeight(48),
                                  ),
                                  onPressed: () => _launchSafeTrackingUrl(o.trackingUrl),
                                  icon: const Icon(Icons.local_shipping_outlined),
                                  label: Text('تتبع الشحن', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                                ),
                              );
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push<void>(
                                  MaterialPageRoute<void>(
                                    builder: (_) => AdvancedOrderTrackingScreen(order: o),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.route_outlined),
                              label: Text('تتبع متقدّم', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                            ),
                          ),
                          if (_canCancel(o.status)) ...[
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                                onPressed: () => _confirmCancel(context, o),
                                child: Text('إلغاء الطلب', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ],
                          if (_statusStep(o.status) >= 3)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () => _rateDeliveredOrder(context, o),
                                  icon: const Icon(Icons.rate_review_outlined),
                                  label: Text('قيّم هذا الطلب', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _OrderStatusStepper extends StatelessWidget {
  const _OrderStatusStepper({required this.currentStep});

  final int currentStep;

  static const _labels = ['قيد المراجعة', 'قيد التجهيز', 'في الطريق', 'تم التوصيل'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_labels.length, (i) {
        final done = i <= currentStep;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: done ? AppColors.orange : AppColors.border,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _labels[i],
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tajawal(
                        fontSize: 11,
                        color: done ? AppColors.orangeDark : AppColors.textSecondary,
                        fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (i != _labels.length - 1)
                Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.only(bottom: 24),
                    color: i < currentStep ? AppColors.orange : AppColors.border,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}
