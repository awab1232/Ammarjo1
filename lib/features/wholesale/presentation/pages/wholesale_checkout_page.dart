import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../store/presentation/store_controller.dart';
import '../../data/wholesale_repository.dart';
import '../../domain/wholesale_order_model.dart';
import '../wholesale_cart_state.dart';

class WholesaleCheckoutPage extends StatefulWidget {
  const WholesaleCheckoutPage({super.key});

  @override
  State<WholesaleCheckoutPage> createState() => _WholesaleCheckoutPageState();
}

class _WholesaleCheckoutPageState extends State<WholesaleCheckoutPage> {
  bool _loading = true;
  bool _submitting = false;
  List<WholesaleCartItem> _items = <WholesaleCartItem>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await WholesaleCartStorage.load();
    final x = switch (state) {
      FeatureSuccess(:final data) => data,
      _ => <WholesaleCartItem>[],
    };
    if (!mounted) return;
    setState(() {
      _items = x;
      _loading = false;
    });
  }

  Future<void> _confirm() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _items.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final store = context.read<StoreController>();
      final storeName = (store.profile?.fullName?.trim().isNotEmpty ?? false) ? store.profile!.fullName!.trim() : 'متجر';
      final grouped = <String, List<WholesaleCartItem>>{};
      for (final i in _items) {
        grouped.putIfAbsent(i.wholesalerId, () => <WholesaleCartItem>[]).add(i);
      }
      for (final entry in grouped.entries) {
        final wholesalerId = entry.key;
        final rows = entry.value;
        final wholesalerName = rows.first.wholesalerName;
        final subtotal = rows.fold<double>(0, (s, e) => s + e.total);
        final commission = subtotal * 0.08;
        final net = subtotal - commission;
        final order = WholesaleOrderModel(
          orderId: '',
          wholesalerId: wholesalerId,
          wholesalerName: wholesalerName,
          storeOwnerId: uid,
          storeName: storeName,
          items: rows
              .map((e) => WholesaleOrderItem(
                    productId: e.productId,
                    name: e.productName,
                    unitPrice: e.unitPrice,
                    quantity: e.quantity,
                    total: e.total,
                  ))
              .toList(),
          subtotal: subtotal,
          commission: commission,
          netAmount: net,
          status: 'pending',
          createdAt: DateTime.now(),
          deliveredAt: null,
        );
        await WholesaleRepository.instance.createWholesaleOrder(order);
      }
      await WholesaleCartStorage.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إنشاء طلبات الجملة بنجاح', style: GoogleFonts.tajawal())),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primaryOrange)));
    }
    final subtotal = _items.fold<double>(0, (s, i) => s + i.total);
    return Scaffold(
      appBar: AppBar(title: Text('دفع الجملة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ..._items.map((e) => ListTile(
                title: Text(e.productName, style: GoogleFonts.tajawal()),
                subtitle: Text('${e.quantity} × ${e.unitPrice.toStringAsFixed(2)}', style: GoogleFonts.tajawal()),
                trailing: Text('${e.total.toStringAsFixed(2)} د.أ', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
              )),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('المجموع', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
              Text('${subtotal.toStringAsFixed(2)} د.أ', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'ملاحظة: العمولة تُحسب خلفياً ولا تظهر في الفاتورة.',
            style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey.shade700),
            textAlign: TextAlign.right,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
            onPressed: _submitting ? null : _confirm,
            child: Text(_submitting ? 'جارٍ التأكيد...' : 'تأكيد الطلب', style: GoogleFonts.tajawal(color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
