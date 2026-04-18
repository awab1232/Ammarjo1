import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../wholesale_cart_state.dart';
import 'wholesale_checkout_page.dart';

class WholesaleCartPage extends StatefulWidget {
  const WholesaleCartPage({super.key});

  @override
  State<WholesaleCartPage> createState() => _WholesaleCartPageState();
}

class _WholesaleCartPageState extends State<WholesaleCartPage> {
  List<WholesaleCartItem> _items = <WholesaleCartItem>[];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final localState = await WholesaleCartStorage.load();
    final local = switch (localState) {
      FeatureSuccess(:final data) => data,
      _ => <WholesaleCartItem>[],
    };
    var merged = local;
    if (Firebase.apps.isNotEmpty) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final cloudState = await WholesaleCartStorage.loadCartFromFirestore(uid);
        final cloud = switch (cloudState) {
          FeatureSuccess(:final data) => data,
          _ => <WholesaleCartItem>[],
        };
        if (cloud.isNotEmpty) {
          merged = cloud;
          await WholesaleCartStorage.save(merged);
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _items = merged;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await WholesaleCartStorage.save(_items);
    if (mounted) setState(() {});
  }

  Future<void> _syncToCloud() async {
    if (!Firebase.apps.isNotEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('سجّل الدخول لحفظ السلة في السحابة.', style: GoogleFonts.tajawal())),
        );
      }
      return;
    }
    setState(() => _syncing = true);
    try {
      await WholesaleCartStorage.syncCartWithFirestore(uid, _items);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ السلة في السحابة.', style: GoogleFonts.tajawal())),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر المزامنة حالياً.', style: GoogleFonts.tajawal())),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primaryOrange)));
    }
    final grouped = <String, List<WholesaleCartItem>>{};
    for (final i in _items) {
      grouped.putIfAbsent(i.wholesalerId, () => <WholesaleCartItem>[]).add(i);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('سلة الجملة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        actions: [
          if (Firebase.apps.isNotEmpty && FirebaseAuth.instance.currentUser != null)
            IconButton(
              tooltip: 'حفظ السلة في السحابة',
              onPressed: _syncing ? null : _syncToCloud,
              icon: _syncing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
            ),
        ],
      ),
      body: _items.isEmpty
          ? Center(child: Text('سلة الجملة فارغة', style: GoogleFonts.tajawal()))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final e in grouped.entries) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(e.value.first.wholesalerName, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          ...e.value.map((it) {
                            return Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${it.productName} · ${it.unitPrice.toStringAsFixed(2)} × ${it.quantity}',
                                    style: GoogleFonts.tajawal(),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    _items = _items.map((x) {
                                      if (x.productId != it.productId || x.wholesalerId != it.wholesalerId) return x;
                                      final q = x.quantity > 1 ? x.quantity - 1 : 1;
                                      return x.copyWith(quantity: q);
                                    }).toList();
                                    _save();
                                  },
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                IconButton(
                                  onPressed: () {
                                    _items = _items.map((x) {
                                      if (x.productId != it.productId || x.wholesalerId != it.wholesalerId) return x;
                                      return x.copyWith(quantity: x.quantity + 1);
                                    }).toList();
                                    _save();
                                  },
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                                IconButton(
                                  onPressed: () {
                                    _items.removeWhere((x) =>
                                        x.productId == it.productId &&
                                        x.wholesalerId == it.wholesalerId);
                                    _save();
                                  },
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                ),
                              ],
                            );
                          }),
                          const Divider(),
                          Text(
                            'المجموع الفرعي: ${e.value.fold<double>(0, (s, i) => s + i.total).toStringAsFixed(2)} د.أ',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
      bottomNavigationBar: _items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                  onPressed: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (_) => const WholesaleCheckoutPage()),
                    );
                    _load();
                  },
                  child: Text('متابعة إلى الدفع', style: GoogleFonts.tajawal(color: Colors.white)),
                ),
              ),
            ),
    );
  }
}

