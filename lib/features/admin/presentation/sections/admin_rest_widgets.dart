import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/contracts/feature_unit.dart';
import '../../../../core/theme/app_colors.dart';

typedef AdminLoadItems = Future<FeatureState<List<Map<String, dynamic>>>> Function();
typedef AdminSaveMap = Future<FeatureState<FeatureUnit>> Function(Map<String, String> values);
typedef AdminSaveItemMap = Future<FeatureState<FeatureUnit>> Function(Map<String, dynamic> item, Map<String, String> values);
typedef AdminDeleteItem = Future<FeatureState<FeatureUnit>> Function(Map<String, dynamic> item);
typedef AdminUpdateStatus = Future<FeatureState<FeatureUnit>> Function(Map<String, dynamic> item, String status);

class CrudFieldDef {
  const CrudFieldDef({
    required this.key,
    required this.label,
    this.required = false,
    this.readItemKey,
  });

  final String key;
  final String label;
  final bool required;
  final String? readItemKey;
}

class AdminCrudSection extends StatefulWidget {
  const AdminCrudSection({
    super.key,
    required this.title,
    required this.fields,
    required this.loadItems,
    this.onCreate,
    this.onUpdate,
    this.onDelete,
  });

  final String title;
  final List<CrudFieldDef> fields;
  final AdminLoadItems loadItems;
  final AdminSaveMap? onCreate;
  final AdminSaveItemMap? onUpdate;
  final AdminDeleteItem? onDelete;

  @override
  State<AdminCrudSection> createState() => _AdminCrudSectionState();
}

class _AdminCrudSectionState extends State<AdminCrudSection> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await widget.loadItems();
      switch (state) {
        case FeatureSuccess(:final data):
          _items = data;
        case FeatureFailure(:final message):
          _error = message;
          _items = const [];
        default:
          _error = 'Feature not available';
          _items = const [];
      }
    } on Object {
      _error = 'حدث خطأ غير متوقع.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEdit({Map<String, dynamic>? item}) async {
    final ctrls = <String, TextEditingController>{};
    for (final f in widget.fields) {
      final initial = item?[f.readItemKey ?? f.key]?.toString() ?? '';
      ctrls[f.key] = TextEditingController(text: initial);
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item == null ? 'إضافة' : 'تعديل', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: widget.fields
                .map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: ctrls[f.key],
                      decoration: InputDecoration(labelText: f.label),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true) return;
    final values = <String, String>{for (final f in widget.fields) f.key: ctrls[f.key]!.text.trim()};
    for (final f in widget.fields) {
      if (f.required && (values[f.key]?.isEmpty ?? true)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('الحقل ${f.label} مطلوب')));
        return;
      }
    }
    try {
      if (item == null) {
        final res = await widget.onCreate?.call(values);
        if (res case FeatureFailure(:final message)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message, style: GoogleFonts.tajawal())),
          );
          return;
        }
      } else {
        final res = await widget.onUpdate?.call(item, values);
        if (res case FeatureFailure(:final message)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message, style: GoogleFonts.tajawal())),
          );
          return;
        }
      }
      await _refresh();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إتمام العملية حالياً.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(child: Text(widget.title, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18))),
              if (widget.onCreate != null) IconButton(onPressed: () => _openEdit(), icon: const Icon(Icons.add_circle)),
            ],
          ),
          if (_loading) const Padding(padding: EdgeInsets.only(top: 32), child: Center(child: CircularProgressIndicator())),
          if (_error != null) Text(_error!, style: GoogleFonts.tajawal(color: AppColors.error)),
          if (!_loading && _error == null && _items.isEmpty)
            Text('لا توجد بيانات حالياً', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
          ..._items.map(
            (item) => Card(
              margin: const EdgeInsets.only(top: 10),
              child: ListTile(
                title: Text(
                  item['name']?.toString() ??
                      item['code']?.toString() ??
                      item['title']?.toString() ??
                      item['subject']?.toString() ??
                      item['id']?.toString() ??
                      '-',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'status: ${item['status'] ?? '-'}',
                  style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                ),
                trailing: Wrap(
                  spacing: 2,
                  children: [
                    if (widget.onUpdate != null) IconButton(onPressed: () => _openEdit(item: item), icon: const Icon(Icons.edit)),
                    if (widget.onDelete != null)
                      IconButton(
                        onPressed: () async {
                          await widget.onDelete!(item);
                          await _refresh();
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminStatusSection extends StatefulWidget {
  const AdminStatusSection({
    super.key,
    required this.title,
    required this.loadItems,
    required this.onUpdateStatus,
  });

  final String title;
  final AdminLoadItems loadItems;
  final AdminUpdateStatus onUpdateStatus;

  @override
  State<AdminStatusSection> createState() => _AdminStatusSectionState();
}

class _AdminStatusSectionState extends State<AdminStatusSection> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await widget.loadItems();
      switch (state) {
        case FeatureSuccess(:final data):
          _items = data;
        case FeatureFailure(:final message):
          _error = message;
          _items = const [];
        default:
          _error = 'Feature not available';
          _items = const [];
      }
    } on Object {
      _error = 'حدث خطأ غير متوقع.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(Map<String, dynamic> item, String status) async {
    try {
      final res = await widget.onUpdateStatus(item, status);
      if (res case FeatureFailure(:final message)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message, style: GoogleFonts.tajawal())),
        );
        return;
      }
      await _refresh();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديث الحالة حالياً.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(widget.title, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18)),
          if (_loading) const Padding(padding: EdgeInsets.only(top: 32), child: Center(child: CircularProgressIndicator())),
          if (_error != null) Text(_error!, style: GoogleFonts.tajawal(color: AppColors.error)),
          ..._items.map(
            (item) => Card(
              margin: const EdgeInsets.only(top: 10),
              child: ListTile(
                title: Text(
                  item['name']?.toString() ??
                      item['title']?.toString() ??
                      item['subject']?.toString() ??
                      item['id']?.toString() ??
                      '-',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('status: ${item['status'] ?? '-'}', style: GoogleFonts.tajawal()),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => _setStatus(item, v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'pending', child: Text('pending')),
                    PopupMenuItem(value: 'approved', child: Text('approved')),
                    PopupMenuItem(value: 'rejected', child: Text('rejected')),
                    PopupMenuItem(value: 'open', child: Text('open')),
                    PopupMenuItem(value: 'closed', child: Text('closed')),
                    PopupMenuItem(value: 'active', child: Text('active')),
                    PopupMenuItem(value: 'disabled', child: Text('disabled')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
