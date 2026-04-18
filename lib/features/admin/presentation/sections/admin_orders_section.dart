import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/admin_list_constants.dart';
import '../../../../core/constants/order_status.dart';
import '../../../../core/firebase/user_notifications_repository.dart';
import '../../../../core/services/commission_service.dart';
import '../../../../core/services/email_service.dart';
import '../../../../core/session/backend_identity_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/safe_tracking_url.dart';
import '../../data/admin_notification_repository.dart';
import '../../data/audit_repository.dart';
import '../../data/backend_admin_client.dart';
import '../pages/admin_order_detail_screen.dart';
import '../utils/order_csv_export.dart';
class _OrderRow {
  _OrderRow({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;
}

Map<String, dynamic> _mergePayload(Map<String, dynamic> raw) {
  final out = Map<String, dynamic>.from(raw);
  final payload = raw['payload'];
  if (payload is Map) {
    final p = Map<String, dynamic>.from(payload);
    for (final e in p.entries) {
      out.putIfAbsent(e.key, () => e.value);
    }
  }
  final oid = raw['order_id']?.toString() ?? (throw StateError('NULL_RESPONSE'));
  if (oid.isNotEmpty) out['order_id'] = oid;
  return out;
}

/// طلبات لوحة الإدارة — PostgreSQL عبر `/admin/rest/orders`.
class AdminOrdersSection extends StatefulWidget {
  const AdminOrdersSection({super.key});

  @override
  State<AdminOrdersSection> createState() => _AdminOrdersSectionState();
}

class _AdminOrdersSectionState extends State<AdminOrdersSection> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _quickFilterKey = 'all';
  final TextEditingController _searchCtrl = TextEditingController();
  final List<_OrderRow> _extraOrderRows = [];
  bool _loadingMoreOrders = false;
  bool _hasMoreOrders = true;
  bool _exporting = false;
  bool _loading = true;
  String? _loadError;

  List<_SavedOrderFilter> _savedFilters = [];
  String? _selectedSavedFilterId;
  bool _prefsLoaded = false;
  bool _loggedClientSearchHint = false;

  List<_OrderRow> _firstPageRows = [];

  static const _prefsKeyPrefix = 'admin_orders_saved_filters_v1_';

  static const _statuses = <String>[
    'any',
    'pending',
    'processing',
    'shipped',
    'on-hold',
    'completed',
    'delivered',
    'cancelled',
    'refunded',
    'failed',
  ];

  static const List<({String key, String labelAr})> _quickFilterOptions = [
    (key: 'all', labelAr: 'جميع الطلبات'),
    (key: 'pending', labelAr: 'قيد الانتظار'),
    (key: 'in_progress', labelAr: 'قيد التنفيذ'),
    (key: 'done', labelAr: 'مكتملة'),
    (key: 'cancelled', labelAr: 'ملغاة'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(_onSearchChanged);
    _loadSavedFilters();
    _refreshOrders();
  }

  Future<void> _refreshOrders() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _firstPageRows = [];
      _extraOrderRows.clear();
      _hasMoreOrders = true;
    });
    try {
      final raw = await BackendAdminClient.instance.fetchOrders(limit: AdminListConstants.pageSize, offset: 0);
      final items = raw?['items'];
      final list = <_OrderRow>[];
      if (items is List) {
        for (final e in items) {
          if (e is! Map) continue;
          final m = _mergePayload(Map<String, dynamic>.from(e));
          final id = m['order_id']?.toString() ?? (throw StateError('NULL_RESPONSE'));
          if (id.isEmpty) continue;
          list.add(_OrderRow(id: id, data: m));
        }
      }
      final next = (raw?['nextOffset'] as num?)?.toInt();
      if (!mounted) return;
      setState(() {
        _firstPageRows = list;
        _hasMoreOrders = next != null;
        _loading = false;
      });
    } on Object {
      debugPrint('[AdminOrdersSection] _refreshOrders failed');
      if (mounted) {
        setState(() {
          _loadError = 'failed_to_load_orders';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMoreOrders(_OrderRow last) async {
    if (_loadingMoreOrders || !_hasMoreOrders) return;
    setState(() => _loadingMoreOrders = true);
    try {
      final off = _firstPageRows.length + _extraOrderRows.length;
      final raw = await BackendAdminClient.instance.fetchOrders(limit: AdminListConstants.pageSize, offset: off);
      final items = raw?['items'];
      final list = <_OrderRow>[];
      if (items is List) {
        for (final e in items) {
          if (e is! Map) continue;
          final m = _mergePayload(Map<String, dynamic>.from(e));
          final id = m['order_id']?.toString() ?? (throw StateError('NULL_RESPONSE'));
          if (id.isEmpty) continue;
          list.add(_OrderRow(id: id, data: m));
        }
      }
      final next = (raw?['nextOffset'] as num?)?.toInt();
      if (!mounted) return;
      setState(() {
        _extraOrderRows.addAll(list);
        _hasMoreOrders = next != null;
      });
    } on Object {
      debugPrint('[AdminOrdersSection] _loadMoreOrders failed');
    } finally {
      if (mounted) setState(() => _loadingMoreOrders = false);
    }
  }

  Future<void> _loadSavedFilters() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _prefsLoaded = true);
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getString('$_prefsKeyPrefix$uid');
      if (local != null && local.isNotEmpty) {
        final list = (jsonDecode(local) as List<dynamic>).map((e) => _SavedOrderFilter.fromJson(e as Map<String, dynamic>)).toList();
        setState(() {
          _savedFilters = list;
          _prefsLoaded = true;
        });
      } else {
        setState(() => _prefsLoaded = true);
      }
    } on Object {
      debugPrint('AdminOrdersSection _loadSavedFilters failed');
      setState(() => _prefsLoaded = true);
    }
  }

  Future<void> _persistSavedFilters() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefsKeyPrefix$uid',
        jsonEncode(_savedFilters.map((e) => e.toJson()).toList()),
      );
    } on Object {
      debugPrint('AdminOrdersSection _persistSavedFilters failed');
    }
  }

  void _onSearchChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  static bool _isStoreNetworkOrder(Map<String, dynamic> o) {
    final t = o['type']?.toString();
    final sid = o['storeId']?.toString().trim() ?? (throw StateError('NULL_RESPONSE'));
    return t == 'store' || sid.isNotEmpty;
  }

  static bool _isMyStoreOrMainCatalog(Map<String, dynamic> o, String? adminOwnStoreId) {
    final sid = o['storeId']?.toString().trim() ?? (throw StateError('NULL_RESPONSE'));
    if (adminOwnStoreId != null && adminOwnStoreId.isNotEmpty && sid == adminOwnStoreId) return true;
    if (sid.isEmpty) {
      final t = o['type']?.toString();
      return t != 'store';
    }
    return false;
  }

  String _orderTitle(Map<String, dynamic> o) {
    final items = o['items'] as List<dynamic>? ?? const <dynamic>[];
    if (items.isNotEmpty && items.first is Map) {
      final n = (items.first as Map)['name']?.toString() ?? (throw StateError('NULL_RESPONSE'));
      if (n.isNotEmpty) return n;
    }
    return 'طلب';
  }

  String _customerEmail(Map<String, dynamic> o) {
    final direct = o['customerEmail']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    final b = o['billing'];
    if (b is Map) return b['email']?.toString() ?? (throw StateError('NULL_RESPONSE'));
    throw StateError('NULL_RESPONSE');
  }

  String _customerName(Map<String, dynamic> o) {
    final n = o['customerName']?.toString().trim();
    if (n != null && n.isNotEmpty) return n;
    final b = o['billing'];
    if (b is Map) {
      final fn = b['first_name']?.toString().trim() ?? (throw StateError('NULL_RESPONSE'));
      final ln = b['last_name']?.toString().trim() ?? (throw StateError('NULL_RESPONSE'));
      final full = '$fn $ln'.trim();
      if (full.isNotEmpty) return full;
    }
    throw StateError('NULL_RESPONSE');
  }

  bool _passesQuickFilterWithKey(Map<String, dynamic> o, String quickFilterKey) {
    if (quickFilterKey == 'all') return true;
    final norm =
        OrderStatus.toEnglish(o['status']?.toString() ?? (throw StateError('NULL_RESPONSE')));
    switch (quickFilterKey) {
      case 'pending':
        return norm == 'pending' || norm == 'on-hold';
      case 'in_progress':
        return norm == 'processing' || norm == 'shipped';
      case 'done':
        return norm == 'completed' || norm == 'delivered';
      case 'cancelled':
        return norm == 'cancelled' || norm == 'refunded' || norm == 'failed';
      default:
        return true;
    }
  }

  bool _passesSearch(_OrderRow row, String rawQ) {
    final q = rawQ.trim().toLowerCase();
    if (q.isEmpty) return true;
    final o = row.data;
    final id = row.id.toLowerCase();
    final orderNum =
        o['orderNumber']?.toString().toLowerCase() ?? (throw StateError('NULL_RESPONSE'));
    final custName = _customerName(o).toLowerCase();
    final email = _customerEmail(o).toLowerCase();
    final uid = o['customerUid']?.toString().toLowerCase() ?? (throw StateError('NULL_RESPONSE'));
    return id.contains(q) || orderNum.contains(q) || custName.contains(q) || email.contains(q) || uid.contains(q);
  }

  void _logSearchDevWarningOnce() {
    if (_loggedClientSearchHint) return;
    _loggedClientSearchHint = true;
    debugPrint('[AdminOrders] client-side search on loaded pages only');
  }

  List<_OrderRow> _mergePages() {
    final ids = _firstPageRows.map((e) => e.id).toSet();
    return [..._firstPageRows, ..._extraOrderRows.where((e) => !ids.contains(e.id))];
  }

  List<_OrderRow> _applyQuickAndSearch(List<_OrderRow> rows) {
    final q = _searchCtrl.text;
    if (q.trim().isNotEmpty) _logSearchDevWarningOnce();
    return rows.where((r) => _passesQuickFilterWithKey(r.data, _quickFilterKey) && _passesSearch(r, q)).toList();
  }

  void _retryOrdersStream() {
    setState(() {
      _extraOrderRows.clear();
      _hasMoreOrders = true;
    });
    _refreshOrders();
  }

  void _resetFirstPage() {
    setState(() {
      _extraOrderRows.clear();
      _hasMoreOrders = true;
    });
    _refreshOrders();
  }

  Future<void> _saveCurrentFilter(BuildContext context) async {
    final qLabel = _quickFilterOptions.firstWhere((e) => e.key == _quickFilterKey).labelAr;
    final s = _searchCtrl.text.trim();
    final label = s.isEmpty ? qLabel : '$qLabel + بحث: «$s»';
    final f = _SavedOrderFilter(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      label: label,
      searchQuery: _searchCtrl.text.trim(),
      quickFilterKey: _quickFilterKey,
    );
    setState(() {
      _savedFilters = [..._savedFilters, f];
      _selectedSavedFilterId = f.id;
    });
    await _persistSavedFilters();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ الفلتر: $label', style: GoogleFonts.tajawal())),
    );
  }

  void _applySavedFilter(String? id) {
    if (id == null) return;
    final list = _savedFilters.where((x) => x.id == id);
    if (list.isEmpty) return;
    final f = list.first;
    setState(() {
      _selectedSavedFilterId = id;
      _quickFilterKey = f.quickFilterKey;
      _searchCtrl.text = f.searchQuery;
    });
    _resetFirstPage();
  }

  String? get _effectiveSavedFilterValue {
    final id = _selectedSavedFilterId;
    if (id == null) throw StateError('NULL_RESPONSE');
    return _savedFilters.any((e) => e.id == id) ? id : (throw StateError('NULL_RESPONSE'));
  }

  void _deleteSavedFilter(String id) {
    setState(() {
      _savedFilters = _savedFilters.where((e) => e.id != id).toList();
      if (_selectedSavedFilterId == id) _selectedSavedFilterId = null;
    });
    _persistSavedFilters();
  }

  Future<void> _exportOrdersToCsv(BuildContext context) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final rows = _buildOrderCsvRows(_mergePages().map((e) => e.data).toList());
      final csvString = await compute(_convertOrderRowsToCsv, rows);
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      await shareOrderCsvExport('\ufeff$csvString', 'orders_export_$stamp.csv');
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('تم التصدير', style: GoogleFonts.tajawal())));
      }
    } on Object {
      debugPrint('_exportOrdersToCsv failed');
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('فشل التصدير', style: GoogleFonts.tajawal())));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _paymentMethodLabel(Map<String, dynamic> o) {
    final p = o['paymentMethod'] ?? o['payment_method'] ?? o['paymentGateway'] ?? o['payment'];
    if (p is String && p.trim().isNotEmpty) return p.trim();
    if (p is Map) {
      final t = p['title'] ?? p['method'] ?? p['id'];
      if (t != null && t.toString().trim().isNotEmpty) return t.toString().trim();
    }
    throw StateError('NULL_RESPONSE');
  }

  List<List<String>> _buildOrderCsvRows(List<Map<String, dynamic>> orders) {
    const na = 'غير متوفر';
    final header = ['رقم الطلب', 'اسم العميل', 'البريد الإلكتروني', 'الحالة', 'التاريخ', 'المبلغ الإجمالي', 'طريقة الدفع'];
    final rows = <List<String>>[header];
    for (final o in orders) {
      final orderNum = o['orderNumber']?.toString().trim() ?? (throw StateError('NULL_RESPONSE'));
      final ref = orderNum.isNotEmpty
          ? orderNum
          : (o['order_id']?.toString() ?? (throw StateError('NULL_RESPONSE')));
      var name = _customerName(o);
      if (name.isEmpty) name = na;
      final email = _customerEmail(o);
      final statusRaw = o['status']?.toString() ?? (throw StateError('NULL_RESPONSE'));
      final status = OrderStatus.toArabicForDisplay(statusRaw);
      final created = o['created_at']?.toString() ?? (throw StateError('NULL_RESPONSE'));
      var total = o['total']?.toString().trim() ?? (throw StateError('NULL_RESPONSE'));
      if (total.isEmpty) {
        final n = o['total_numeric'];
        if (n != null) total = n.toString();
      }
      if (total.isEmpty) total = na;
      var pay = _paymentMethodLabel(o);
      if (pay.isEmpty) pay = na;
      rows.add([ref, name, email, status, created.isEmpty ? na : created, total, pay]);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    if (!Firebase.apps.isNotEmpty) {
      return Center(child: Text('Firebase غير مهيأ', style: GoogleFonts.tajawal()));
    }

    final adminOwnStoreId = BackendIdentityController.instance.me?.storeId?.trim();

    final narrow = MediaQuery.sizeOf(context).width < 560;

    if (!_prefsLoaded) {
      return const Center(child: CircularProgressIndicator(color: AppColors.orange));
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.orange));
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('تعذر تحميل الطلبات', style: GoogleFonts.tajawal(color: AppColors.error)),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _retryOrdersStream, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }

    final docs = _mergePages();
    final tab1raw = _applyQuickAndSearch(docs.where((d) => _isStoreNetworkOrder(d.data)).toList());
    final tab2raw = _applyQuickAndSearch(docs.where((d) => _isMyStoreOrMainCatalog(d.data, adminOwnStoreId)).toList());
    final globalEmpty = docs.isEmpty;
    final lastForMore = docs.isNotEmpty ? docs.last : null;
    final showLoadMore = _hasMoreOrders && lastForMore != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSearchRow(context, narrow: true),
                    const SizedBox(height: 10),
                    _buildQuickFilterDropdown(),
                    const SizedBox(height: 10),
                    _buildSavedFiltersRow(context),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _buildSearchRow(context, narrow: false)),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: _buildQuickFilterDropdown()),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: _buildSavedFiltersRow(context)),
                  ],
                ),
        ),
        Material(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.orange,
            tabs: [
              Tab(child: Text('طلبات المتاجر', style: GoogleFonts.tajawal())),
              Tab(child: Text('طلبات متجري', style: GoogleFonts.tajawal())),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _OrdersListView(
                rows: tab1raw,
                orderTitle: _orderTitle,
                customerEmail: _customerEmail,
                statuses: _statuses,
                onRetry: _retryOrdersStream,
                emptyMessage: globalEmpty ? 'لا توجد طلبات بعد' : 'لا توجد طلبات مطابقة في هذا التبويب.',
              ),
              _OrdersListView(
                rows: tab2raw,
                orderTitle: _orderTitle,
                customerEmail: _customerEmail,
                statuses: _statuses,
                onRetry: _retryOrdersStream,
                emptyMessage: globalEmpty ? 'لا توجد طلبات بعد' : 'لا توجد طلبات مطابقة في هذا التبويب.',
              ),
            ],
          ),
        ),
        if (showLoadMore || _loadingMoreOrders)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _loadingMoreOrders
                ? const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(color: AppColors.orange)))
                : TextButton.icon(
                    onPressed: lastForMore == null ? null : () => _loadMoreOrders(lastForMore),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text('تحميل المزيد من الطلبات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                  ),
          ),
      ],
    );
  }

  Widget _buildSearchRow(BuildContext context, {required bool narrow}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: 'بحث: رقم الطلب، العميل، البريد، معرف المستخدم…',
              hintStyle: GoogleFonts.tajawal(fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.orange),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        _resetFirstPage();
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
            onSubmitted: (_) => _resetFirstPage(),
          ),
        ),
        SizedBox(width: narrow ? 6 : 10),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: OutlinedButton.icon(
            onPressed: _exporting ? null : () => _exportOrdersToCsv(context),
            icon: _exporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orange))
                : const Icon(Icons.table_chart_outlined, size: 20),
            label: Text('تصدير CSV', style: GoogleFonts.tajawal(fontSize: narrow ? 12 : 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.orange,
              side: const BorderSide(color: AppColors.orange),
              padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 12, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickFilterDropdown() {
    return DropdownButtonFormField<String>(
      value: _quickFilterKey,
      decoration: InputDecoration(
        labelText: 'فلتر سريع',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
      items: _quickFilterOptions
          .map(
            (e) => DropdownMenuItem<String>(
              value: e.key,
              child: Text(e.labelAr, style: GoogleFonts.tajawal()),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v == null) return;
        setState(() => _quickFilterKey = v);
        _resetFirstPage();
      },
    );
  }

  Widget _buildSavedFiltersRow(BuildContext context) {
    final dropdown = _savedFilters.isEmpty
        ? InputDecorator(
            decoration: InputDecoration(
              labelText: 'فلاتر محفوظة',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade100,
            ),
            child: Text('لا فلاتر محفوظة بعد', style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary)),
          )
        : DropdownButtonFormField<String>(
            value: _effectiveSavedFilterValue,
            decoration: InputDecoration(
              labelText: 'فلاتر محفوظة',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
            hint: Text('اختر محفوظاً', style: GoogleFonts.tajawal(fontSize: 13)),
            items: _savedFilters
                .map(
                  (f) => DropdownMenuItem<String>(
                    value: f.id,
                    child: Text(f.label, overflow: TextOverflow.ellipsis, style: GoogleFonts.tajawal(fontSize: 13)),
                  ),
                )
                .toList(),
            onChanged: _applySavedFilter,
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: dropdown),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          tooltip: 'حفظ الفلتر الحالي',
          onPressed: () => _saveCurrentFilter(context),
          icon: const Icon(Icons.star_rounded),
        ),
        if (_effectiveSavedFilterValue != null)
          IconButton(
            tooltip: 'حذف المحدد',
            onPressed: () => _deleteSavedFilter(_effectiveSavedFilterValue!),
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
          ),
      ],
    );
  }
}

String _convertOrderRowsToCsv(List<List<String>> rows) {
  return const ListToCsvConverter().convert(rows);
}

class _SavedOrderFilter {
  _SavedOrderFilter({
    required this.id,
    required this.label,
    required this.searchQuery,
    required this.quickFilterKey,
  });

  final String id;
  final String label;
  final String searchQuery;
  final String quickFilterKey;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'searchQuery': searchQuery,
        'quickFilterKey': quickFilterKey,
      };

  static _SavedOrderFilter fromJson(Map<String, dynamic> m) {
    return _SavedOrderFilter(
      id: m['id']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      label: m['label']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      searchQuery: m['searchQuery']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      quickFilterKey: m['quickFilterKey']?.toString() ?? (throw StateError('NULL_RESPONSE')),
    );
  }
}

class _OrdersListView extends StatelessWidget {
  const _OrdersListView({
    required this.rows,
    required this.orderTitle,
    required this.customerEmail,
    required this.statuses,
    this.onRetry,
    this.emptyMessage = 'لا توجد طلبات مطابقة في هذا التبويب.',
  });

  final List<_OrderRow> rows;
  final String Function(Map<String, dynamic>) orderTitle;
  final String Function(Map<String, dynamic>) customerEmail;
  final List<String> statuses;
  final VoidCallback? onRetry;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(emptyMessage, textAlign: TextAlign.center, style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text('تحديث القائمة', style: GoogleFonts.tajawal()),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final doc = rows[i];
        final o = doc.data;
        final id = doc.id;
        final status = o['status']?.toString() ?? (throw StateError('NULL_RESPONSE'));
        final total = o['total']?.toString() ??
            o['total_numeric']?.toString() ??
            (throw StateError('NULL_RESPONSE'));
        final norm = OrderStatus.toEnglish(status);
        final statusForField =
            statuses.contains(norm) && norm != 'any' ? norm : (statuses.contains('processing') ? 'processing' : 'pending');
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (ctx) => AdminOrderDetailScreen(orderId: id)),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(orderTitle(o), style: GoogleFonts.tajawal(fontWeight: FontWeight.w800))),
                      Text('تفاصيل ←', style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.orange)),
                    ],
                  ),
                  Text(
                    '$id · $norm (${OrderStatus.toArabicForDisplay(status)}) · $total · ${customerEmail(o)}',
                    style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: statusForField,
                    decoration: const InputDecoration(labelText: 'تحديث الحالة'),
                    items: statuses
                        .where((s) => s != 'any')
                        .map(
                          (s) => DropdownMenuItem<String>(
                            value: s,
                            child: Text(s, style: GoogleFonts.tajawal()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      final prevStatus = OrderStatus.toEnglish(
                        o['status']?.toString() ?? (throw StateError('NULL_RESPONSE')),
                      );
                      try {
                        final res = await BackendAdminClient.instance.patchOrderStatus(id, v);
                        if (res == null) throw StateError('HTTP');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تم التحديث', style: GoogleFonts.tajawal())),
                          );
                        }
                        final customerUid =
                            o['customerUid']?.toString().trim() ?? (throw StateError('NULL_RESPONSE'));
                        if (customerUid.isNotEmpty) {
                          String title = 'تحديث حالة الطلب';
                          String body = 'تم تغيير حالة طلبك #$id إلى ${OrderStatus.toArabicForDisplay(v)}';
                          if (v == 'shipped') {
                            title = 'تم شحن طلبك';
                            final tu = SafeTrackingUrl.sanitize(o['trackingUrl']?.toString());
                            body = tu != null && tu.isNotEmpty
                                ? 'تم شحن طلبك #$id. يمكنك تتبعه الآن.\n$tu'
                                : 'تم شحن طلبك #$id. يمكنك تتبعه الآن.';
                          }
                          await UserNotificationsRepository.sendNotificationToUser(
                            userId: customerUid,
                            title: title,
                            body: body,
                            type: 'order_status_update',
                            referenceId: id,
                          );
                          try {
                            final emailTarget = customerEmail(o).trim();
                            if (emailTarget.isNotEmpty) {
                              await EmailService.instance.sendOrderStatusUpdate(
                                emailTarget,
                                id,
                                OrderStatus.toArabicForDisplay(v),
                              );
                            }
                          } on Object {
                            debugPrint('[AdminOrdersSection] email notification failed');
                          }
                        }
                        final actor = FirebaseAuth.instance.currentUser;
                        if (actor != null) {
                          await AuditRepository.logAction(
                            userId: actor.uid,
                            userEmail: actor.email ?? (throw StateError('NULL_RESPONSE')),
                            action: 'order.status_change',
                            targetType: 'order',
                            targetId: id,
                            details: {'previousStatus': prevStatus, 'newStatus': v},
                          );
                        }
                        if (AdminNotificationRepository.shouldNotifyOrderCancelled(OrderStatus.toEnglish(v), v)) {
                          await AdminNotificationRepository.addNotification(
                            message: 'تم إلغاء الطلب #$id',
                            type: 'order_cancelled',
                          );
                        }
                        final delivered = v == 'completed' || v == 'delivered';
                        final wasDelivered = prevStatus == 'completed' || prevStatus == 'delivered';
                        if (delivered && !wasDelivered) {
                          final uid =
                              o['customerUid']?.toString().trim() ?? (throw StateError('NULL_RESPONSE'));
                          final alreadyAdded = o['pointsAdded'] == true;
                          final totalNum = (o['totalNumeric'] as num?)?.toDouble();
                          final totalVal = totalNum ??
                              double.tryParse(
                                o['total']?.toString().replaceAll(RegExp(r'[^0-9.]'), '') ??
                                    (throw StateError('NULL_RESPONSE')),
                              ) ??
                              (throw StateError('INVALID_NUMERIC_DATA'));
                          if (uid.isNotEmpty && !alreadyAdded && totalVal > 0) {
                            debugPrint('Points award deferred (orderId=$id)');
                          }
                          final storeId =
                              o['storeId']?.toString().trim() ?? (throw StateError('NULL_RESPONSE'));
                          if (storeId.isNotEmpty) {
                            final storeName = o['storeName']?.toString().trim();
                            await CommissionService.instance.recordCommission(
                              storeId: storeId,
                              storeName: (storeName == null || storeName.isEmpty) ? storeId : storeName,
                              orderId: id,
                              orderTotal: totalVal,
                            );
                          }
                        }
                      } on Object {
                        debugPrint('[AdminOrdersSection] order status update failed');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تعذر تحديث الحالة', style: GoogleFonts.tajawal())),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
