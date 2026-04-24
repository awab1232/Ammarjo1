import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/contracts/feature_state.dart';
import '../../../../core/data/repositories/store_repository.dart';
import '../../../stores/domain/store_model.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../../../core/widgets/full_screen_image_viewer.dart';
import '../../data/tender_repository.dart';
import '../../domain/tender_model.dart';

String _resolveStoreCityForTenders(Map<String, dynamic> storeData) {
  final c = storeData['city']?.toString().trim() ?? '';
  if (c.isNotEmpty) return c;
  final raw = storeData['cities'];
  if (raw is List) {
    for (final e in raw) {
      final s = e.toString().trim();
      if (s.isEmpty || s == 'all' || s == 'all_jordan') continue;
      return s;
    }
  }
  return '';
}

/// مناقصات من المتجر: مفتوحة للمزايدة + سجل عروض المتجر السابقة.
class StoreTendersTab extends StatelessWidget {
  const StoreTendersTab({
    super.key,
    required this.storeId,
    required this.storeName,
  });

  final String storeId;
  final String storeName;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FeatureState<StoreModel>>(
      future: RestStoreRepository.instance.fetchStoreDocument(storeId),
      builder: (ctx, storeSnap) {
        final storeData = switch (storeSnap.data) {
          FeatureSuccess(:final data) => data.toMap(),
          _ => <String, dynamic>{},
        };
        final storeCategory = storeData['category']?.toString() ?? '';
        final storeCity = _resolveStoreCityForTenders(storeData);
        final storeTypeId = storeData['storeTypeId']?.toString() ?? storeData['store_type_id']?.toString();
        final storeTypeKey = storeData['storeTypeKey']?.toString() ?? storeData['store_type_key']?.toString();
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              TabBar(
                labelColor: const Color(0xFFFF6B00),
                unselectedLabelColor: Colors.grey,
                indicatorColor: const Color(0xFFFF6B00),
                tabs: [
                  Tab(child: Text('مناقصات مفتوحة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 13))),
                  Tab(child: Text('عروضي السابقة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 13))),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _OpenTendersList(
                      storeId: storeId,
                      storeName: storeName,
                      storeCategory: storeCategory,
                      storeCity: storeCity,
                      storeTypeId: storeTypeId,
                      storeTypeKey: storeTypeKey,
                    ),
                    _MyOffersHistoryList(
                      storeId: storeId,
                      storeOwnerUid: FirebaseAuth.instance.currentUser?.uid,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OpenTendersList extends StatelessWidget {
  const _OpenTendersList({
    required this.storeId,
    required this.storeName,
    required this.storeCategory,
    required this.storeCity,
    this.storeTypeId,
    this.storeTypeKey,
  });

  final String storeId;
  final String storeName;
  final String storeCategory;
  final String storeCity;
  final String? storeTypeId;
  final String? storeTypeKey;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FeatureState<List<TenderModel>>>(
      stream: TenderRepository.instance.watchTendersForStore(
        category: storeCategory,
        city: storeCity,
        storeTypeId: storeTypeId,
        storeTypeKey: storeTypeKey,
      ),
      builder: (ctx, snap) {
        final tenders = switch (snap.data) {
          FeatureSuccess(:final data) => data,
          _ => <TenderModel>[],
        };
        if (tenders.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                storeCity.isEmpty
                    ? 'لا توجد مناقصات مفتوحة حالياً، أو لا يطابق تصنيف متجرك أي مناقصة.'
                    : 'لا توجد مناقصات مفتوحة في مدينة متجرك ($storeCity) وتصنيفه.',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(color: Colors.grey),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: tenders.length,
          itemBuilder: (ctx, i) {
            final tender = tenders[i];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => openImageViewer(
                        context,
                        imageUrl: tender.imageUrl,
                        title: tender.categoryId,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AmmarCachedImage(imageUrl: tender.imageUrl, width: 64, height: 64),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tender.categoryId, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                          if (tender.description.trim().isNotEmpty)
                            Text(
                              tender.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          const SizedBox(height: 4),
                          Text('المدينة: ${tender.city}', style: GoogleFonts.cairo(fontSize: 12)),
                          Text(tender.timeLeft, style: GoogleFonts.cairo(color: Colors.orange, fontSize: 12)),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B00)),
                              onPressed: () => _showOfferSheet(context, tender),
                              child: Text('قدم عرضاً', style: GoogleFonts.cairo(color: Colors.white, fontSize: 12)),
                            ),
                          ),
                        ],
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
  }

  void _showOfferSheet(BuildContext context, TenderModel tender) {
    final priceController = TextEditingController();
    final noteController = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر')),
            const SizedBox(height: 8),
            TextField(controller: noteController, maxLines: 2, decoration: const InputDecoration(labelText: 'ملاحظة')),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B00)),
                onPressed: () async {
                  final price = double.tryParse(priceController.text.trim());
                  if (price == null || price <= 0) return;
                  final state = await TenderRepository.instance.submitOffer(
                    tenderId: tender.id,
                    storeId: storeId,
                    storeName: storeName,
                    price: price,
                    note: noteController.text.trim(),
                  );
                  if (context.mounted && state is FeatureSuccess<void>) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال العرض ✅')));
                  } else if (context.mounted && state is FeatureFailure<void>) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
                  }
                },
                child: Text('إرسال العرض', style: GoogleFonts.cairo(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyOffersHistoryList extends StatelessWidget {
  const _MyOffersHistoryList({
    required this.storeId,
    this.storeOwnerUid,
  });

  final String storeId;
  final String? storeOwnerUid;

  static String _statusLabel(String s) {
    switch (s) {
      case 'accepted':
        return 'مقبول';
      case 'rejected':
        return 'مرفوض';
      default:
        return 'قيد الانتظار';
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FeatureState<List<StoreSubmittedOfferRow>>>(
      stream: TenderRepository.instance.watchStoreSubmittedOffers(
        storeId: storeId,
        storeOwnerUid: storeOwnerUid,
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'تعذر تحميل عروضك. تحقق من الاتصال.',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(color: Colors.red.shade700),
              ),
            ),
          );
        }
        final rows = switch (snap.data) {
          FeatureSuccess(:final data) => data,
          _ => <StoreSubmittedOfferRow>[],
        };
        if (rows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'لم تقدّم أي عرض من هذا المتجر بعد، أو لا توجد بيانات.',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(color: Colors.grey),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          itemBuilder: (ctx, i) {
            final row = rows[i];
            final o = row.offer;
            final d = o.createdAt;
            final dateStr = '${d.year}/${d.month}/${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${o.price.toStringAsFixed(2)} د.أ',
                            style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: o.status == 'accepted'
                                ? Colors.green.shade50
                                : o.status == 'rejected'
                                    ? Colors.red.shade50
                                    : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _statusLabel(o.status),
                            style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('تاريخ العرض: $dateStr', style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey.shade700)),
                    Text('مناقصة: ${row.tenderId}', style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey)),
                    if (o.note.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(o.note, style: GoogleFonts.tajawal(fontSize: 13)),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
