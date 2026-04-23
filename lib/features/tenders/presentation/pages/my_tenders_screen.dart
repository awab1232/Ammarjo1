import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../data/tender_repository.dart';
import '../../domain/tender_model.dart';
import 'tender_offers_screen.dart';

class MyTendersScreen extends StatelessWidget {
  const MyTendersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('مناقصاتي', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFFFF6B00),
      ),
      body: StreamBuilder<FeatureState<List<TenderModel>>>(
        stream: TenderRepository.instance.watchMyTenders(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B00)));
          }
          final state = snap.data;
          if (state is FeatureFailure<List<TenderModel>>) {
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
                        MaterialPageRoute<void>(builder: (_) => const MyTendersScreen()),
                      ),
                      child: Text('إعادة المحاولة', style: GoogleFonts.cairo(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            );
          }
          final tenders = switch (state) {
            FeatureSuccess(:final data) => data,
            _ => <TenderModel>[],
          };
          if (tenders.isEmpty) {
            return Center(child: Text('لا توجد مناقصات بعد', style: GoogleFonts.cairo(color: Colors.grey)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: tenders.length,
            itemBuilder: (context, i) {
              final t = tenders[i];
              return Card(
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AmmarCachedImage(imageUrl: t.imageUrl, width: 56, height: 56),
                  ),
                  title: Text(t.category, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  subtitle: Text(t.timeLeft, style: GoogleFonts.cairo(color: Colors.orange)),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TenderOffersScreen(tenderId: t.id)));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
