import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../../../core/widgets/full_screen_image_viewer.dart';
import '../../../store/presentation/store_controller.dart';
import '../../data/tender_repository.dart';
import '../../domain/tender_model.dart';

class TenderOffersScreen extends StatelessWidget {
  const TenderOffersScreen({super.key, required this.tenderId});

  final String tenderId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('عروض التجار', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFFFF6B00),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: TenderRepository.instance.fetchTenderDocument(tenderId),
        builder: (ctx, tenderSnap) {
          if (tenderSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B00)));
          }
          if (tenderSnap.hasError) {
            final msg = tenderSnap.error?.toString().trim();
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(msg == null || msg.isEmpty ? 'تعذر تحميل المناقصة.' : msg, style: GoogleFonts.cairo()),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(builder: (_) => TenderOffersScreen(tenderId: tenderId)),
                      ),
                      child: Text('إعادة المحاولة', style: GoogleFonts.cairo(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            );
          }
          if (tenderSnap.data == null) {
            return Center(child: Text('المناقصة غير موجودة', style: GoogleFonts.cairo()));
          }
          TenderModel tender;
          try {
            tender = TenderModel.fromMap(tenderId, tenderSnap.data!);
          } on Object {
            return Center(child: Text('بيانات المناقصة غير صالحة.', style: GoogleFonts.cairo()));
          }
          return Column(
            children: [
              ListTile(
                leading: GestureDetector(
                  onTap: () => openImageViewer(
                    context,
                    imageUrl: tender.imageUrl,
                    title: 'صورة المناقصة',
                  ),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AmmarCachedImage(imageUrl: tender.imageUrl, width: 56, height: 56),
                      ),
                      Positioned(
                        left: 2,
                        top: 2,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.zoom_in, color: Colors.white, size: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                title: Text(tender.categoryId, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                subtitle: Text(tender.timeLeft, style: GoogleFonts.cairo(color: Colors.orange)),
              ),
              Expanded(
                child: StreamBuilder<FeatureState<List<TenderOffer>>>(
                  stream: TenderRepository.instance.watchOffers(tenderId),
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B00)));
                    }
                    final state = snap.data;
                    if (state is FeatureFailure<List<TenderOffer>>) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(state.message, style: GoogleFonts.cairo()),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () => Navigator.of(context).pushReplacement(
                                  MaterialPageRoute<void>(builder: (_) => TenderOffersScreen(tenderId: tenderId)),
                                ),
                                child: Text('إعادة المحاولة', style: GoogleFonts.cairo(color: Colors.white)),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final offers = switch (state) {
                      FeatureSuccess(:final data) => data,
                      _ => <TenderOffer>[],
                    };
                    if (offers.isEmpty) {
                      return Center(child: Text('في انتظار عروض التجار...', style: GoogleFonts.cairo(color: Colors.grey)));
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: offers.length,
                      itemBuilder: (ctx, i) {
                        final offer = offers[i];
                        final isAccepted = tender.acceptedOfferId == offer.id;
                        final isCheapest = i == 0;
                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: isAccepted
                                  ? Colors.green
                                  : isCheapest
                                      ? const Color(0xFFFF6B00)
                                      : Colors.transparent,
                              width: 1.6,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        offer.storeName.trim().isNotEmpty ? offer.storeName : 'متجر',
                                        style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 15),
                                      ),
                                    ),
                                    if (isCheapest && !isAccepted)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF6B00),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text('الأرخص', style: GoogleFonts.cairo(color: Colors.white, fontSize: 12)),
                                      ),
                                    if (isAccepted)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text('مقبول ✅', style: GoogleFonts.cairo(color: Colors.white, fontSize: 12)),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${offer.price.toStringAsFixed(2)} دينار',
                                  style: GoogleFonts.cairo(
                                    color: const Color(0xFFFF6B00),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 22,
                                  ),
                                ),
                                if (offer.note.trim().isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(offer.note, style: GoogleFonts.cairo(color: Colors.grey.shade700)),
                                ],
                                const SizedBox(height: 10),
                                if (tender.isOpen && !isAccepted)
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: Text('تأكيد القبول', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                                                content: Text(
                                                  'هل تريد قبول عرض ${offer.storeName} بسعر ${offer.price.toStringAsFixed(2)} دينار؟',
                                                  style: GoogleFonts.cairo(),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.of(ctx).pop(false),
                                                    child: Text('إلغاء', style: GoogleFonts.cairo()),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () => Navigator.of(ctx).pop(true),
                                                    child: Text('قبول', style: GoogleFonts.cairo(color: Colors.white)),
                                                  ),
                                                ],
                                              ),
                                            ) ??
                                            false;
                                        if (!ok) return;
                                        final cartItem = await TenderRepository.instance.acceptOffer(
                                          tenderId: tender.id,
                                          offer: offer,
                                          tenderImageUrl: tender.imageUrl,
                                          category: tender.categoryId,
                                        );
                                        if (!context.mounted) return;
                                        context.read<StoreController>().addCartItem(cartItem);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('تمت إضافة عرض المناقصة للسلة ✅')),
                                        );
                                      },
                                      child: Text('قبول العرض', style: GoogleFonts.cairo(color: Colors.white)),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
