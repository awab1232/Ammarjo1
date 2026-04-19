import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../store/presentation/pages/order_tracking_page.dart';
import '../../data/backend_admin_client.dart';

/// صف واحد من API الإدارة (حقول camelCase + توافق مع الحقول القديمة).
class _DeliveryOrderRow {
  _DeliveryOrderRow({
    required this.orderId,
    required this.customerName,
    required this.totalLabel,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    required this.deliveryStatus,
    required this.etaMinutes,
    required this.createdAtLabel,
  });

  final String orderId;
  final String customerName;
  final String totalLabel;
  final String? driverId;
  final String driverName;
  final String driverPhone;
  final String deliveryStatus;
  final String etaMinutes;
  final String createdAtLabel;

  static _DeliveryOrderRow? tryParse(Map<String, dynamic> m) {
    final oid = (m['orderId'] ?? m['order_id'])?.toString().trim() ?? '';
    if (oid.isEmpty) return null;
    final cn = (m['customerName'] ?? '').toString().trim();
    final total = m['total'] ?? m['total_numeric'];
    final totalLabel = total == null ? '—' : total.toString();
    final did = (m['driverId'] ?? m['driver_id'])?.toString().trim();
    final ds = (m['deliveryStatus'] ?? m['delivery_status'] ?? '').toString().trim();
    final dn = (m['driverName'] ?? m['driver_name'] ?? '').toString().trim();
    final dp = (m['driverPhone'] ?? m['driver_phone'] ?? '').toString().trim();
    final etaRaw = m['etaMinutes'] ?? m['eta_minutes'];
    final eta = etaRaw == null ? '—' : etaRaw.toString();
    final ca = m['createdAt'] ?? m['created_at'];
    String createdLabel = '—';
    if (ca != null) {
      final dt = DateTime.tryParse(ca.toString()) ?? (ca is DateTime ? ca : null);
      if (dt != null) {
        createdLabel = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      } else {
        createdLabel = ca.toString();
      }
    }
    return _DeliveryOrderRow(
      orderId: oid,
      customerName: cn.isEmpty ? '—' : cn,
      totalLabel: totalLabel,
      driverId: did != null && did.isNotEmpty ? did : null,
      driverName: dn.isEmpty ? '—' : dn,
      driverPhone: dp.isEmpty ? '—' : dp,
      deliveryStatus: ds.isEmpty ? '—' : ds,
      etaMinutes: eta,
      createdAtLabel: createdLabel,
    );
  }
}

String _deliveryStatusAr(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'pending':
      return 'بانتظار سائق';
    case 'assigned':
      return 'تم التعيين';
    case 'accepted':
      return 'تم القبول';
    case 'on_the_way':
      return 'في الطريق';
    case 'delivered':
      return 'تم التسليم';
    case 'no_driver_found':
      return 'لا يوجد سائق';
    default:
      return raw.isEmpty || raw == '—' ? '—' : raw;
  }
}

Color _statusColor(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'pending':
      return Colors.blueGrey;
    case 'assigned':
    case 'accepted':
      return Colors.indigo;
    case 'on_the_way':
      return AppColors.orange;
    case 'delivered':
      return Colors.green.shade700;
    case 'no_driver_found':
      return AppColors.error;
    default:
      return AppColors.textSecondary;
  }
}

/// مراقبة طلبات التوصيل للإدارة: جدول، فلاتر، تعيين سائق، تتبع.
class AdminDeliveryDashboardPage extends StatefulWidget {
  const AdminDeliveryDashboardPage({super.key});

  @override
  State<AdminDeliveryDashboardPage> createState() => _AdminDeliveryDashboardPageState();
}

class _AdminDeliveryDashboardPageState extends State<AdminDeliveryDashboardPage> {
  static const _statusFilterKeys = <String?>[
    null,
    'pending',
    'assigned',
    'accepted',
    'on_the_way',
    'delivered',
    'no_driver_found',
  ];

  Timer? _timer;
  bool _loading = true;
  String? _error;
  List<_DeliveryOrderRow> _rows = List<_DeliveryOrderRow>.empty(growable: true);
  final TextEditingController _searchCtrl = TextEditingController();

  String? _filterStatus;
  String? _filterDriverId;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_load(silent: true)));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _error = null;
        _loading = true;
      });
    }
    try {
      final df = _dateFrom != null ? _dateToIsoDate(_dateFrom!) : null;
      final dt = _dateTo != null ? _dateToIsoDate(_dateTo!) : null;
      final raw = await BackendAdminClient.instance.fetchOrders(
        limit: 200,
        offset: 0,
        deliveryStatus: _filterStatus,
        driverId: _filterDriverId,
        dateFrom: df,
        dateTo: dt,
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      );
      if (!mounted) return;
      final items = raw?['items'];
      final list = <_DeliveryOrderRow>[];
      if (items is List) {
        for (final e in items) {
          if (e is Map<String, dynamic>) {
            final row = _DeliveryOrderRow.tryParse(e);
            if (row != null) list.add(row);
          } else if (e is Map) {
            final row = _DeliveryOrderRow.tryParse(Map<String, dynamic>.from(e));
            if (row != null) list.add(row);
          }
        }
      }
      setState(() {
        _rows = list;
        _loading = false;
        _error = null;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر تحميل الطلبات. تحقق من الاتصال أو الصلاحيات.';
      });
    }
  }

  String _dateToIsoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _dateFrom : _dateTo;
    final now = DateTime.now();
    final first = DateTime(now.year - 2);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: first,
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
    });
    await _load();
  }

  Future<void> _openChangeDriver(_DeliveryOrderRow row) async {
    Map<String, dynamic>? raw;
    try {
      raw = await BackendAdminClient.instance.fetchAvailableDrivers();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر تحميل السائقين.', style: GoogleFonts.tajawal())),
        );
      }
      return;
    }
    final drivers = raw?['drivers'];
    if (drivers is! List || drivers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('لا يوجد سائقون متاحون حالياً.', style: GoogleFonts.tajawal())),
        );
      }
      return;
    }
    String? selectedId;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعيين سائق', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: drivers.length,
            itemBuilder: (context, i) {
              final d = drivers[i];
              if (d is! Map) return const SizedBox.shrink();
              final m = Map<String, dynamic>.from(d);
              final id = m['id']?.toString() ?? '';
              final name = m['name']?.toString() ?? id;
              final phone = m['phone']?.toString() ?? '';
              return ListTile(
                title: Text(name, style: GoogleFonts.tajawal(), textAlign: TextAlign.right),
                subtitle: phone.isNotEmpty
                    ? Text(phone, style: GoogleFonts.tajawal(fontSize: 12), textAlign: TextAlign.right)
                    : null,
                onTap: () {
                  selectedId = id;
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.tajawal())),
        ],
      ),
    );
    if (selectedId == null || selectedId!.isEmpty || !mounted) return;
    try {
      await BackendAdminClient.instance.patchAssignDriverToOrder(row.orderId, selectedId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تعيين السائق.', style: GoogleFonts.tajawal())),
      );
      await _load(silent: true);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل التعيين. تحقق من الصلاحيات أو حالة الطلب.', style: GoogleFonts.tajawal())),
        );
      }
    }
  }

  Future<void> _forceReassign(_DeliveryOrderRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('إعادة التعيين', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        content: Text(
          'إعادة جلب سائق تلقائياً لهذا الطلب؟',
          style: GoogleFonts.tajawal(),
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('لا', style: GoogleFonts.tajawal())),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('نعم', style: GoogleFonts.tajawal()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await BackendAdminClient.instance.postAdminRetryDeliveryAssignment(row.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم طلب إعادة التعيين.', style: GoogleFonts.tajawal())),
      );
      await _load(silent: true);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّرت إعادة التعيين.', style: GoogleFonts.tajawal())),
        );
      }
    }
  }

  List<MapEntry<String, String>> get _driverFilterEntries {
    final map = <String, String>{};
    for (final r in _rows) {
      final id = r.driverId;
      if (id != null && id.isNotEmpty) {
        final label = r.driverName != '—' ? '${r.driverName} ($id)' : id;
        map[id] = label;
      }
    }
    final list = map.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: Text('إدارة التوصيل', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String?>(
                    value: _filterStatus,
                    decoration: InputDecoration(
                      labelText: 'حالة التوصيل',
                      labelStyle: GoogleFonts.tajawal(),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('الكل')),
                      for (final k in _statusFilterKeys.skip(1))
                        DropdownMenuItem<String?>(
                          value: k,
                          child: Text(_deliveryStatusAr(k!), style: GoogleFonts.tajawal(fontSize: 13)),
                        ),
                    ],
                    onChanged: (v) {
                      setState(() => _filterStatus = v);
                      unawaited(_load());
                    },
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(isFrom: true),
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(_dateFrom == null ? 'من تاريخ' : _dateToIsoDate(_dateFrom!), style: GoogleFonts.tajawal()),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(isFrom: false),
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(_dateTo == null ? 'إلى تاريخ' : _dateToIsoDate(_dateTo!), style: GoogleFonts.tajawal()),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _dateFrom = null;
                      _dateTo = null;
                    });
                    unawaited(_load());
                  },
                  child: Text('مسح التواريخ', style: GoogleFonts.tajawal()),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    value: _filterDriverId,
                    decoration: InputDecoration(
                      labelText: 'السائق',
                      labelStyle: GoogleFonts.tajawal(),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('كل السائقين')),
                      ..._driverFilterEntries.map(
                        (e) => DropdownMenuItem<String?>(value: e.key, child: Text(e.value, style: GoogleFonts.tajawal(fontSize: 12))),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _filterDriverId = v);
                      unawaited(_load());
                    },
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _searchCtrl,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      hintText: 'بحث: رقم الطلب أو الاسم',
                      hintStyle: GoogleFonts.tajawal(),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => _load(),
                      ),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: Text(_error!, style: GoogleFonts.tajawal(color: AppColors.error))),
                  TextButton(onPressed: () => _load(), child: Text('إعادة المحاولة', style: GoogleFonts.tajawal())),
                ],
              ),
            ),
          Expanded(
            child: _loading && _rows.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
                : _rows.isEmpty
                    ? Center(child: Text('لا توجد طلبات.', style: GoogleFonts.tajawal(color: AppColors.textSecondary)))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          return Scrollbar(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                child: SingleChildScrollView(
                                  child: DataTable(
                                    headingRowColor: WidgetStateProperty.all(Colors.grey.shade200),
                                    columns: [
                                      DataColumn(label: Text('رقم الطلب', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                                      DataColumn(label: Text('العميل', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                                      DataColumn(label: Text('الإجمالي', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                                      DataColumn(label: Text('السائق', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                                      DataColumn(label: Text('هاتف السائق', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                                      DataColumn(label: Text('الحالة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                                      DataColumn(label: Text('الوقت المتوقع', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                                      DataColumn(label: Text('التاريخ', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                                      DataColumn(label: Text('إجراءات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                                    ],
                                    rows: [
                                      for (final r in _rows)
                                        DataRow(
                                          cells: [
                                            DataCell(SelectableText(r.orderId, style: GoogleFonts.tajawal(fontSize: 12))),
                                            DataCell(Text(r.customerName, style: GoogleFonts.tajawal())),
                                            DataCell(Text(r.totalLabel, style: GoogleFonts.tajawal())),
                                            DataCell(Text(r.driverName, style: GoogleFonts.tajawal())),
                                            DataCell(Text(r.driverPhone, style: GoogleFonts.tajawal())),
                                            DataCell(
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: _statusColor(r.deliveryStatus).withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  _deliveryStatusAr(r.deliveryStatus),
                                                  style: GoogleFonts.tajawal(
                                                    fontWeight: FontWeight.w600,
                                                    color: _statusColor(r.deliveryStatus),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            DataCell(Text(r.etaMinutes, style: GoogleFonts.tajawal())),
                                            DataCell(Text(r.createdAtLabel, style: GoogleFonts.tajawal(fontSize: 12))),
                                            DataCell(
                                              Wrap(
                                                spacing: 4,
                                                children: [
                                                  TextButton(
                                                    onPressed: () {
                                                      Navigator.of(context).push<void>(
                                                        MaterialPageRoute<void>(
                                                          builder: (_) => OrderTrackingPage(orderId: r.orderId),
                                                        ),
                                                      );
                                                    },
                                                    child: Text('تتبع', style: GoogleFonts.tajawal(fontSize: 12)),
                                                  ),
                                                  TextButton(
                                                    onPressed: () => _openChangeDriver(r),
                                                    child: Text('تغيير السائق', style: GoogleFonts.tajawal(fontSize: 12)),
                                                  ),
                                                  TextButton(
                                                    onPressed: () => _forceReassign(r),
                                                    child: Text('إعادة تعيين', style: GoogleFonts.tajawal(fontSize: 12)),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'تحديث تلقائي كل 10 ثوانٍ • ${_rows.length} طلباً',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
