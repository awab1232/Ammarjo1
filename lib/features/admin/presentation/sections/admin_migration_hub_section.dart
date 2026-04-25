import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/dev/demo_data_seeder.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../store/presentation/store_controller.dart';
import '../../data/admin_repository.dart';
import '../../data/csv_product_importer.dart';
import '../../data/migration_hub_service.dart';

/// يسجّل حالة الهجرة على الخادم (PostgreSQL) — سابقاً كان فحص Woo.
class AdminMigrationHubSection extends StatefulWidget {
  const AdminMigrationHubSection({super.key});

  @override
  State<AdminMigrationHubSection> createState() => _AdminMigrationHubSectionState();
}

class _AdminMigrationHubSectionState extends State<AdminMigrationHubSection> {
  bool _running = false;
  bool _csvImporting = false;
  bool _seedingDemo = false;
  String _log = '';
  bool _showSuccessBanner = false;
  MigrationHubResult? _lastResult;
  CsvProductImportResult? _lastCsvResult;
  final CsvImportProgress _csvImportProgress = CsvImportProgress();
  Future<Map<String, dynamic>?>? _migrationPayloadFuture;

  @override
  void dispose() {
    _csvImportProgress.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _migrationPayloadFuture = AdminRepository.instance.fetchMigrationStatusPayload();
  }

  void _refreshMigrationPayload() {
    setState(() {
      _migrationPayloadFuture = AdminRepository.instance.fetchMigrationStatusPayload();
    });
  }

  Future<void> _runMigration() async {
    if (!Firebase.apps.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Firebase غير مهيأ.', style: GoogleFonts.tajawal())),
      );
      return;
    }
    setState(() {
      _running = true;
      _log = 'بدء الهجرة…';
      _showSuccessBanner = false;
      _lastResult = null;
    });
    try {
      final store = context.read<StoreController>();
      final result = await MigrationHubService.instance.run(
        onProgress: (m) {
          if (mounted) setState(() => _log = m);
        },
      );
      await store.reloadCatalogAfterMigration();
      if (!mounted) return;
      setState(() {
        _lastResult = result;
        _showSuccessBanner = true;
        _log = 'تم تسجيل حالة الخادم (Migration Hub).';
      });
      _refreshMigrationPayload();
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade700, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text('نجاح — Migration Hub', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18)),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              'تُسجّل حالة Migration Hub على الخادم (لا يوجد اتصال بـ Woo/WordPress بعد الآن).\n\n'
              '• الأقسام: ${result.categoriesCount}\n'
              '• المنتجات: ${result.productsCount}\n\n'
              'الكتالوج الفعلي يُدار في PostgreSQL؛ لا يُكتب إلى Firestore من لوحة الإدارة.',
              style: GoogleFonts.tajawal(height: 1.4, fontSize: 15),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('حسناً', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    } on Object {
      if (mounted) {
        setState(() => _log = 'فشل: تعذر إكمال العملية.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إكمال العملية حالياً.', style: GoogleFonts.tajawal())),
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _pickAndImportCsv() async {
    if (!Firebase.apps.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Firebase غير مهيأ.', style: GoogleFonts.tajawal())),
      );
      return;
    }
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    if (pick == null || pick.files.isEmpty) return;
    if (!mounted) return;
    final bytes = pick.files.first.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر قراءة الملف.', style: GoogleFonts.tajawal())),
      );
      return;
    }
    setState(() {
      _csvImporting = true;
      _log = 'جاري استيراد CSV…';
      _lastCsvResult = null;
    });
    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      final result = await CsvProductImporter.importFromCsvString(
        text,
        progress: _csvImportProgress,
        onProgress: (m) {
          if (mounted) setState(() => _log = m);
        },
      );
      if (!mounted) return;
      final store = context.read<StoreController>();
      await store.reloadCatalogAfterMigration();
      if (!mounted) return;
      setState(() {
        _lastCsvResult = result;
        _log = 'اكتمل التحقق من CSV: ${result.productsWritten} صفاً.';
      });
      _refreshMigrationPayload();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('استيراد CSV', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Text(
              'تم التحقق من ${result.productsWritten} صفاً صالحاً وتسجيل الملخص على الخادم.\n'
              'صفوف متخطاة: ${result.rowsSkipped}\n\n'
              '${result.warnings.isEmpty ? '' : 'تحذيرات (${result.warnings.length}):\n${result.warnings.take(25).join('\n')}'}\n\n'
              'استيراد المنتجات الفعلي يتم من لوحة الخادم.',
              style: GoogleFonts.tajawal(height: 1.4),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('حسناً', style: GoogleFonts.tajawal())),
          ],
        ),
      );
    } on Object {
      if (mounted) {
        setState(() => _log = 'فشل CSV: تعذر إكمال العملية.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر استيراد CSV حالياً.', style: GoogleFonts.tajawal())),
        );
      }
    } finally {
      if (mounted) setState(() => _csvImporting = false);
    }
  }

  Future<void> _seedDemoData() async {
    if (!Firebase.apps.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Firebase غير مهيأ.', style: GoogleFonts.tajawal())),
      );
      return;
    }
    setState(() => _seedingDemo = true);
    try {
      await DemoDataSeeder.seedAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم إدراج بيانات تجريبية: إعلانات مستعمل، فنيون، تجار جملة.',
            style: GoogleFonts.tajawal(),
          ),
        ),
      );
    } on Object {
      debugPrint('[MigrationHub] demo seed failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إدراج البيانات التجريبية حالياً.', style: GoogleFonts.tajawal())),
        );
      }
    } finally {
      if (mounted) setState(() => _seedingDemo = false);
    }
  }

  Future<void> _confirmDeleteAllProducts() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف المنتجات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        content: Text(
          'حذف كتالوج المنتجات يتم من لوحة الخادم / قاعدة البيانات. لا يتوفر حذف جماعي من التطبيق بعد الانتقال إلى REST.',
          style: GoogleFonts.tajawal(height: 1.4),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('حسناً', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Migration Hub',
          style: GoogleFonts.tajawal(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          'تشغيل لمرة واحدة: جلب أعداد الأقسام والمنتجات من Woo وتسجيلها في حالة الهجرة على الخادم (PostgreSQL). لا يُكتب كتالوج في Firestore.',
          style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.45),
        ),
        const SizedBox(height: 20),
        Text('بيانات تجريبية', style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          'يُدرج 3 فنيين في technicians، و3 تجار جملة في wholesalers (يتطلب تسجيل دخول وصلاحية كتابة).',
          style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.45, fontSize: 13),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: (_running || _csvImporting || _seedingDemo) ? null : _seedDemoData,
          icon: _seedingDemo
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.science_outlined),
          label: Text(
            _seedingDemo ? 'جاري الإدراج…' : 'إدراج بيانات تجريبية',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 24),
        Text('استيراد من CSV', style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          'ارفع ملف CSV للتحقق من الصفوف وتسجيل ملخص على الخادم. الاستيراد الفعلي للمنتجات يتم من لوحة الخادم.',
          style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.45, fontSize: 13),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: (_running || _csvImporting) ? null : _pickAndImportCsv,
          icon: _csvImporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.upload_file_outlined),
          label: Text(
            _csvImporting ? 'جاري استيراد CSV…' : 'اختيار ملف CSV ورفعه',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
          ),
        ),
        if (_csvImporting)
          ListenableBuilder(
            listenable: _csvImportProgress,
            builder: (context, _) {
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _csvImportProgress.label,
                  style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.navy),
                ),
              );
            },
          ),
        if (_lastCsvResult != null) ...[
          const SizedBox(height: 8),
          Text(
            'آخر استيراد: ${_lastCsvResult!.productsWritten} منتج',
            style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: 24),
        Text('حذف الكتالوج', style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.red.shade900)),
        const SizedBox(height: 8),
        Text(
          'حذف المنتجات يتم من لوحة الخادم بعد الانتقال إلى REST.',
          style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.45, fontSize: 13),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: (_running || _csvImporting) ? null : _confirmDeleteAllProducts,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red.shade800,
            side: BorderSide(color: Colors.red.shade700),
          ),
          icon: const Icon(Icons.info_outline),
          label: Text(
            'معلومات الحذف (الخادم)',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 24),
        Text('هجرة من Woo عبر API', style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (_showSuccessBanner && _lastResult != null)
          Material(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_rounded, color: Colors.green.shade800, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Success — جاهز للتحويل الدائم',
                          style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, color: Colors.green.shade900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'تم تسجيل الأعداد: ${_lastResult!.categoriesCount} قسم، ${_lastResult!.productsCount} منتج (Woo). '
                          'الكتالوج على الخادم.',
                          style: GoogleFonts.tajawal(fontSize: 14, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_showSuccessBanner) const SizedBox(height: 16),
        FutureBuilder<Map<String, dynamic>?>(
          future: _migrationPayloadFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final d = snap.data;
            if (d == null || d.isEmpty) {
              return Row(
                children: [
                  Expanded(child: Text('لا توجد حالة هجرة بعد.', style: GoogleFonts.tajawal(color: AppColors.textSecondary))),
                  IconButton(onPressed: _refreshMigrationPayload, icon: const Icon(Icons.refresh_rounded)),
                ],
              );
            }
            final phase = d['phase']?.toString() ?? '';
            final done = d['migrationCompleted'] == true;
            final cats = d['categoriesCount'];
            final prods = d['productsCount'];
            final err = d['lastError']?.toString();
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('حالة السيرفر: $phase${done ? " ✓" : ""}', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                        ),
                        IconButton(onPressed: _refreshMigrationPayload, icon: const Icon(Icons.refresh_rounded)),
                      ],
                    ),
                    if (cats != null) Text('أقسام (Woo): $cats', style: GoogleFonts.tajawal(fontSize: 13)),
                    if (prods != null) Text('منتجات (Woo): $prods', style: GoogleFonts.tajawal(fontSize: 13)),
                    if (err != null && err.isNotEmpty)
                      Text('خطأ سابق: $err', style: GoogleFonts.tajawal(fontSize: 12, color: Colors.red)),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: (_running || _csvImporting) ? null : _runMigration,
          icon: _running
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.sync_alt_rounded),
          label: Text(
            _running ? 'جاري الهجرة…' : 'تشغيل الهجرة الآن',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.navy,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
        ),
        const SizedBox(height: 16),
        Text(_log, style: GoogleFonts.tajawal(fontSize: 14, color: AppColors.textSecondary)),
      ],
    );
  }
}
