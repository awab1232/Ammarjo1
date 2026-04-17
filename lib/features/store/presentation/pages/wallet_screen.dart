import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../maintenance/data/technicians_repository.dart';
import '../../../maintenance/domain/maintenance_models.dart';
import '../../../../core/data/repositories/customer_ops_repository.dart';
import '../store_controller.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Future<void> _showPayDialog(String customerEmail) async {
    final messenger = ScaffoldMessenger.of(context);
    String? selectedTechEmail;
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController(text: 'Ã˜Â¯Ã™ÂÃ˜Â¹ Ã™â€¦Ã™â€šÃ˜Â§Ã˜Â¨Ã™â€ž Ã˜Â®Ã˜Â¯Ã™â€¦Ã˜Â© Ã™ÂÃ™â€ Ã™Å ');
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text('Pay Technician', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
            content: StreamBuilder<FeatureState<List<TechnicianProfile>>>(
              stream: TechniciansRepository.instance.watchTechnicians(),
              builder: (context, snapshot) {
                final state = snapshot.requireData;
                final techs = switch (state) {
                  FeatureSuccess(:final data) => data,
                  _ => <TechnicianProfile>[],
                };
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedTechEmail,
                      items: techs
                          .where((t) => (t.email ?? '').trim().isNotEmpty)
                          .map<DropdownMenuItem<String>>(
                            (t) => DropdownMenuItem<String>(
                              value: t.email!.trim(),
                              child: Text(t.displayName, style: GoogleFonts.tajawal()),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setLocal(() => selectedTechEmail = v),
                      decoration: InputDecoration(
                        labelText: 'Ã˜Â§Ã˜Â®Ã˜ÂªÃ˜Â± Ã˜Â§Ã™â€žÃ™ÂÃ™â€ Ã™Å ',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â¨Ã™â€žÃ˜Âº (JOD)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtrl,
                      decoration: InputDecoration(
                        labelText: 'Ã™â€¦Ã™â€žÃ˜Â§Ã˜Â­Ã˜Â¸Ã˜Â©',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                );
              },
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Ã˜Â¥Ã™â€žÃ˜ÂºÃ˜Â§Ã˜Â¡', style: GoogleFonts.tajawal())),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
                onPressed: () async {
                  final tech = (selectedTechEmail ?? '').trim();
                  final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                  if (tech.isEmpty || amount <= 0) return;
                  try {
                    await CustomerOpsRepository.instance.payTechnician(
                      customerEmail: customerEmail,
                      technicianEmail: tech,
                      amount: amount,
                      note: noteCtrl.text.trim(),
                    );
                    if (!mounted || !ctx.mounted) return;
                    Navigator.pop(ctx);
                    messenger.showSnackBar(
                      SnackBar(content: Text('Ã˜ÂªÃ™â€¦ Ã˜Â§Ã™â€žÃ˜Â¯Ã™ÂÃ˜Â¹ Ã˜Â¨Ã™â€ Ã˜Â¬Ã˜Â§Ã˜Â­.', style: GoogleFonts.tajawal())),
                    );
                  } on StateError {
                    if (!mounted) return;
                    final msg = 'Ã˜ÂªÃ˜Â¹Ã˜Â°Ã™â€˜Ã˜Â± Ã˜ÂªÃ™â€ Ã™ÂÃ™Å Ã˜Â° Ã˜Â§Ã™â€žÃ˜Â¹Ã™â€¦Ã™â€žÃ™Å Ã˜Â©.';
                    messenger.showSnackBar(SnackBar(content: Text(msg, style: GoogleFonts.tajawal())));
                  }
                },
                child: Text('Ã˜Â¯Ã™ÂÃ˜Â¹', style: GoogleFonts.tajawal(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
    amountCtrl.dispose();
    noteCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = context.watch<StoreController>().profile?.email.trim() ?? '';
    if (email.isNotEmpty) {
      CustomerOpsRepository.instance.ensureUserWalletDoc(email);
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: const AppBarBackButton(),
        title: Text('Ã™â€¦Ã˜Â­Ã™ÂÃ˜Â¸Ã˜Â© Ã˜Â¹Ã™Å½Ã™â€¦Ã™â€˜Ã˜Â§Ã˜Â±', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
      ),
      body: email.isEmpty
          ? Center(child: Text('Ã˜Â³Ã˜Â¬Ã™â€˜Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â¯Ã˜Â®Ã™Ë†Ã™â€ž Ã™â€žÃ™â€žÃ™Ë†Ã˜ÂµÃ™Ë†Ã™â€ž Ã˜Â¥Ã™â€žÃ™â€° Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã™ÂÃ˜Â¸Ã˜Â©.', style: GoogleFonts.tajawal(color: AppColors.textSecondary)))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: StreamBuilder<double>(
                    stream: CustomerOpsRepository.instance.watchWalletBalance(email),
                    builder: (context, snapshot) {
                      final balance = switch (snapshot.connectionState) {
                        ConnectionState.waiting => 0.0,
                        _ => snapshot.requireData,
                      };
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: LinearGradient(
                            colors: [AppColors.navy, AppColors.slate.withValues(alpha: 0.95)],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                          boxShadow: [
                            BoxShadow(color: AppColors.shadow, blurRadius: 16, offset: const Offset(0, 8)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('AmmarJo Wallet', style: GoogleFonts.tajawal(color: Colors.white70)),
                            const SizedBox(height: 8),
                            Text(
                              'Balance: ${balance.toStringAsFixed(2)} JOD',
                              style: GoogleFonts.tajawal(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton.icon(
                      onPressed: () => _showPayDialog(email),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white),
                      icon: const Icon(Icons.payments_rounded),
                      label: Text('Pay Technician', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'Ã˜Â³Ã˜Â¬Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â±Ã™Æ’Ã˜Â§Ã˜Âª',
                      style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: StreamBuilder<FeatureState<List<WalletTransactionItem>>>(
                    stream: CustomerOpsRepository.instance.watchTransactions(email),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: AppColors.orange));
                      }
                      final state = snapshot.requireData;
                      final txs = switch (state) {
                        FeatureSuccess(:final data) => data,
                        _ => <WalletTransactionItem>[],
                      };
                      if (txs.isEmpty) {
                        return Center(
                          child: Text('Ã™â€žÃ˜Â§ Ã™Å Ã™Ë†Ã˜Â¬Ã˜Â¯ Ã˜Â­Ã˜Â±Ã™Æ’Ã˜Â§Ã˜Âª Ã˜Â­Ã˜ÂªÃ™â€° Ã˜Â§Ã™â€žÃ˜Â¢Ã™â€ .', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: txs.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final t = txs[index];
                          final debit = t.type == 'pay_technician';
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: debit ? Colors.red.shade50 : Colors.green.shade50,
                                  child: Icon(
                                    debit ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                                    color: debit ? Colors.red : Colors.green,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        t.note.isEmpty ? t.type : t.note,
                                        textAlign: TextAlign.right,
                                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                                      ),
                                      Text(
                                        t.counterpartyEmail,
                                        textAlign: TextAlign.right,
                                        style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${debit ? '-' : '+'}${t.amount.toStringAsFixed(2)}',
                                  style: GoogleFonts.tajawal(
                                    fontWeight: FontWeight.w800,
                                    color: debit ? Colors.red : Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

