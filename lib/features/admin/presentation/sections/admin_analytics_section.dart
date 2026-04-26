import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/backend_admin_client.dart';

class AdminAnalyticsSection extends StatefulWidget {
  const AdminAnalyticsSection({super.key});

  @override
  State<AdminAnalyticsSection> createState() => _AdminAnalyticsSectionState();
}

class _AdminAnalyticsSectionState extends State<AdminAnalyticsSection> {
  late final Future<_AdminAnalyticsPayload> _future = _loadAnalytics();

  Future<_AdminAnalyticsPayload> _loadAnalytics() async {
    final overview = await BackendAdminClient.instance.fetchOverview();
    final finance = await BackendAdminClient.instance.fetchFinance();
    final activity = await BackendAdminClient.instance.fetchActivity();
    if (overview == null && finance == null && activity == null) {
      final reports = await BackendAdminClient.instance.fetchReports();
      if (reports == null) return const _AdminAnalyticsPayload.empty();
      return _AdminAnalyticsPayload(
        overview: reports,
        finance: null,
        activity: null,
      );
    }
    return _AdminAnalyticsPayload(
      overview: overview,
      finance: finance,
      activity: activity,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminAnalyticsPayload>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primaryOrange),
          );
        }
        final data = snap.data;
        if (data == null || data.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'التحليلات ستكون متاحة قريباً',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.tajawal(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final cards = <_AnalyticsEntry>[
          ..._extractEntries('نظرة عامة', data.overview),
          ..._extractEntries('المالية', data.finance),
          ..._extractEntries('النشاط', data.activity),
        ];
        if (cards.isEmpty) {
          return Center(
            child: Text(
              'التحليلات ستكون متاحة قريباً',
              style: GoogleFonts.tajawal(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'تحليلات الإدارة (من الخادم)',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            ...cards.map(_kpi),
          ],
        );
      },
    );
  }

  List<_AnalyticsEntry> _extractEntries(
    String section,
    Map<String, dynamic>? map,
  ) {
    if (map == null || map.isEmpty) return const <_AnalyticsEntry>[];
    final out = <_AnalyticsEntry>[];
    map.forEach((key, value) {
      if (value == null) return;
      if (value is num || value is String || value is bool) {
        out.add(_AnalyticsEntry(section: section, key: key, value: '$value'));
      }
    });
    return out;
  }

  Widget _kpi(_AnalyticsEntry e) => Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: ListTile(
        title: Text(
          '${e.section} • ${e.key}',
          textAlign: TextAlign.right,
          style: GoogleFonts.tajawal(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        trailing: Text(
          e.value,
          style: GoogleFonts.tajawal(
            fontWeight: FontWeight.w800,
            color: AppColors.orange,
          ),
        ),
      ),
    ),
  );
}

class _AdminAnalyticsPayload {
  const _AdminAnalyticsPayload({
    required this.overview,
    required this.finance,
    required this.activity,
  });

  const _AdminAnalyticsPayload.empty()
    : overview = null,
      finance = null,
      activity = null;

  final Map<String, dynamic>? overview;
  final Map<String, dynamic>? finance;
  final Map<String, dynamic>? activity;

  bool get isEmpty =>
      (overview == null || overview!.isEmpty) &&
      (finance == null || finance!.isEmpty) &&
      (activity == null || activity!.isEmpty);
}

class _AnalyticsEntry {
  const _AnalyticsEntry({
    required this.section,
    required this.key,
    required this.value,
  });

  final String section;
  final String key;
  final String value;
}
