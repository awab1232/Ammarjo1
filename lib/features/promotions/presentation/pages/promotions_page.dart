import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/promotion_repository.dart';
import '../../domain/promotion_model.dart';

class PromotionsPage extends StatelessWidget {
  const PromotionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('العروض', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800))),
      body: FutureBuilder<FeatureState<List<Promotion>>>(
        future: PromotionRepository.instance.fetchActivePromotions(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final state = snap.data!;
          if (state is FeatureFailure<List<Promotion>>) {
            return Center(child: Text(state.message, style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
          }
          if (state is! FeatureSuccess<List<Promotion>>) {
            return Center(child: Text('Not available', style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
          }
          final list = state.data;
          if (list.isEmpty) {
            return Center(child: Text('لا توجد عروض حالياً', style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final p = list[i];
              return Card(
                child: ListTile(
                  title: Text(p.name, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                  subtitle: Text('${p.description}\nالنوع: ${p.type}', style: GoogleFonts.tajawal(fontSize: 12), textAlign: TextAlign.right),
                  trailing: Text('القيمة: ${p.value}', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
