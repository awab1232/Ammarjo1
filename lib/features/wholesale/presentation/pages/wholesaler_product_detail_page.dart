import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/services/chat_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../communication/presentation/unified_chat_page.dart';
import '../../../store/presentation/store_controller.dart';
import '../../domain/quantity_price_tier.dart';
import '../../domain/wholesale_product_model.dart';
import '../../presentation/wholesale_cart_state.dart';

class WholesalerProductDetailPage extends StatefulWidget {
  const WholesalerProductDetailPage({
    super.key,
    required this.wholesalerId,
    required this.wholesalerName,
    required this.wholesalerOwnerId,
    required this.wholesalerEmail,
    required this.product,
  });

  final String wholesalerId;
  final String wholesalerName;
  final String wholesalerOwnerId;
  final String wholesalerEmail;
  final WholesaleProduct product;

  @override
  State<WholesalerProductDetailPage> createState() => _WholesalerProductDetailPageState();
}

class _WholesalerProductDetailPageState extends State<WholesalerProductDetailPage> {
  final TextEditingController _qty = TextEditingController(text: '1');

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  double _priceForQty(int qty, List<QuantityPriceTier> tiers) {
    if (tiers.isEmpty) return 0;
    final sorted = [...tiers]..sort((a, b) => a.minQuantity.compareTo(b.minQuantity));
    var current = sorted.first.price;
    for (final t in sorted) {
      if (qty >= t.minQuantity) current = t.price;
    }
    return current;
  }

  Future<void> _addToWholesaleCart() async {
    final qty = int.tryParse(_qty.text.trim()) ?? 0;
    if (qty <= 0) return;
    final unitPrice = _priceForQty(qty, widget.product.quantityPrices);
    final allState = await WholesaleCartStorage.load();
    final all = switch (allState) {
      FeatureSuccess(:final data) => data,
      _ => <WholesaleCartItem>[],
    };
    final idx = all.indexWhere((e) =>
        e.wholesalerId == widget.wholesalerId && e.productId == widget.product.productId);
    final item = WholesaleCartItem(
      wholesalerId: widget.wholesalerId,
      wholesalerName: widget.wholesalerName,
      productId: widget.product.productId,
      productName: widget.product.name,
      imageUrl: widget.product.imageUrl,
      unit: widget.product.unit,
      quantity: qty,
      unitPrice: unitPrice,
    );
    if (idx >= 0) {
      all[idx] = item;
    } else {
      all.add(item);
    }
    await WholesaleCartStorage.save(all);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تمت الإضافة إلى سلة الجملة', style: GoogleFonts.tajawal())),
    );
  }

  Future<void> _openChat() async {
    final store = context.read<StoreController>();
    final myEmail = store.profile?.email.trim() ?? '';
    if (myEmail.isEmpty || widget.wholesalerEmail.trim().isEmpty) return;
    final chatId = await ChatService().getOrCreateChat(
      otherUserId: widget.wholesalerOwnerId,
      otherUserName: widget.wholesalerName,
      currentUserEmail: myEmail,
      currentUserPhone: '',
      otherUserEmail: widget.wholesalerEmail.trim(),
      otherUserPhone: '',
      chatType: 'wholesale',
      referenceId: widget.wholesalerId,
      referenceName: widget.wholesalerName,
      referenceImageUrl: widget.product.imageUrl.trim().isNotEmpty ? widget.product.imageUrl : null,
    );
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => UnifiedChatPage.resume(existingChatId: chatId, threadTitle: widget.wholesalerName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Scaffold(
      appBar: AppBar(title: Text(p.name, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (p.imageUrl.trim().isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(p.imageUrl, height: 200, fit: BoxFit.cover),
            ),
          const SizedBox(height: 12),
          Text('الوحدة: ${p.unit}', textAlign: TextAlign.right, style: GoogleFonts.tajawal()),
          const SizedBox(height: 12),
          Text('جدول أسعار الجملة حسب الكمية', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...p.quantityPrices
              .map((t) => ListTile(
                    dense: true,
                    title: Text('من ${t.minQuantity} ${p.unit}', style: GoogleFonts.tajawal()),
                    trailing: Text('${t.price.toStringAsFixed(2)} د.أ', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                  )),
          const SizedBox(height: 12),
          TextField(
            controller: _qty,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'الكمية'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
            onPressed: _addToWholesaleCart,
            child: Text('إضافة إلى سلة الجملة', style: GoogleFonts.tajawal(color: Colors.white)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _openChat,
            icon: const Icon(Icons.chat_bubble_outline),
            label: Text('محادثة', style: GoogleFonts.tajawal()),
          ),
        ],
      ),
    );
  }
}
