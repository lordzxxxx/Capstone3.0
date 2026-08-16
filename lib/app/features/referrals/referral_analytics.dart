import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';

class ReferralAnalyticsPage extends StatefulWidget {
  const ReferralAnalyticsPage({super.key});

  @override
  State<ReferralAnalyticsPage> createState() => _ReferralAnalyticsPageState();
}

class _ReferralAnalyticsPageState extends State<ReferralAnalyticsPage> {
  final FirebaseFirestore _firestore = getFirestoreInstance();
  UserAccessScope _scope = UserAccessScope.unauthenticated;
  bool _isLoadingScope = true;

  @override
  void initState() {
    super.initState();
    _loadScope();
  }

  Future<void> _loadScope() async {
    setState(() {
      _isLoadingScope = true;
    });
    try {
      final scope = await UserAccessScopeService.instance.loadCurrentScope();
      if (!mounted) return;
      setState(() {
        _scope = scope;
        _isLoadingScope = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingScope = false;
      });
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _referralsStream() {
    final referrals = _firestore.collection('referrals');
    if (_scope.canViewAllBarangays) return referrals.snapshots();
    if (_scope.role == 'doctor') {
      return referrals
          .where('assignedDoctorUid', isEqualTo: _scope.userId)
          .snapshots();
    }
    return referrals
        .where('createdByUid', isEqualTo: _scope.userId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesign.page,
      appBar: AppBar(
        backgroundColor: AppDesign.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Referral Analytics',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _isLoadingScope ? null : _loadScope,
            tooltip: 'Refresh analytics',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoadingScope
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _referralsStream(),
              builder: (context, snapshot) {
                final docRecords = (snapshot.hasData && snapshot.data != null)
                    ? snapshot.data!.docs
                          .map((document) => document.data())
                          .toList(growable: false)
                    : <Map<String, dynamic>>[];

                return _ReferralAnalyticsBody(records: docRecords);
              },
            ),
    );
  }
}

class _ReferralAnalyticsBody extends StatelessWidget {
  const _ReferralAnalyticsBody({required this.records});
  final List<Map<String, dynamic>> records;

  String _value(Map<String, dynamic> record, String key) =>
      (record[key] ?? '').toString().trim();

  Map<String, int> _countsFor(
    String field, {
    String fallback = 'Not recorded',
  }) {
    final counts = <String, int>{};
    for (final record in records) {
      final raw = _value(record, field);
      final label = raw.isEmpty
          ? fallback
          : raw
                .replaceAll('_', ' ')
                .split(' ')
                .map(
                  (word) => word.isEmpty
                      ? word
                      : '${word[0].toUpperCase()}${word.substring(1)}',
                )
                .join(' ');
      counts[label] = (counts[label] ?? 0) + 1;
    }
    return Map.fromEntries(
      counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  int get _completed => records.where((record) {
    return _value(record, 'status').toLowerCase() == 'completed';
  }).length;

  int get _active => records.where((record) {
    final status = _value(record, 'status').toLowerCase();
    return status != 'completed' &&
        status != 'cancelled' &&
        status != 'rejected';
  }).length;

  int get _submittedThisMonth {
    final now = DateTime.now();
    return records.where((record) {
      final raw = record['createdAt'];
      DateTime? date;
      if (raw is Timestamp) date = raw.toDate();
      if (raw is DateTime) date = raw;
      if (raw is String) date = DateTime.tryParse(raw);
      return date != null && date.year == now.year && date.month == now.month;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final completionRate = records.isEmpty
        ? 0
        : (_completed / records.length * 100).round();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppDesign.informationBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppDesign.blue.withValues(alpha: .22)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppDesign.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.call_split_rounded,
                  color: AppDesign.referrals,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Referral performance',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Live referral workload, completion, reasons, and case distribution for your access level.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppDesign.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 12) / 2;
            final metrics = <({String label, String value, IconData icon})>[
              (
                label: 'Total referrals',
                value: '${records.length}',
                icon: Icons.folder_shared_outlined,
              ),
              (
                label: 'Active cases',
                value: '$_active',
                icon: Icons.pending_actions_outlined,
              ),
              (
                label: 'This month',
                value: '$_submittedThisMonth',
                icon: Icons.calendar_month_outlined,
              ),
              (
                label: 'Completion rate',
                value: '$completionRate%',
                icon: Icons.task_alt_rounded,
              ),
            ];
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: metrics
                  .map(
                    (metric) => SizedBox(
                      width: width,
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(metric.icon, color: AppDesign.referrals),
                              const SizedBox(height: 12),
                              Text(
                                metric.value,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                metric.label,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppDesign.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
        const SizedBox(height: 16),
        _ReferralDistribution(
          title: 'Referral status',
          icon: Icons.donut_large_rounded,
          values: _countsFor('status'),
          total: records.length,
        ),
        const SizedBox(height: 16),
        _ReferralDistribution(
          title: 'Reasons for referral',
          icon: Icons.medical_information_outlined,
          values: _countsFor('referralReason'),
          total: records.length,
        ),
        const SizedBox(height: 16),
        _ReferralDistribution(
          title: 'Referral categories',
          icon: Icons.category_outlined,
          values: _countsFor('referralCategorySummary'),
          total: records.length,
        ),
      ],
    );
  }
}

class _ReferralDistribution extends StatelessWidget {
  const _ReferralDistribution({
    required this.title,
    required this.icon,
    required this.values,
    required this.total,
  });
  final String title;
  final IconData icon;
  final Map<String, int> values;
  final int total;

  @override
  Widget build(BuildContext context) {
    final entries = values.entries.where((entry) => entry.value > 0).toList();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppDesign.referrals),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (entries.isEmpty)
              const Text(
                'No data available yet.',
                style: TextStyle(color: AppDesign.muted),
              )
            else ...[
              ...entries.asMap().entries.map((item) {
                final index = item.key;
                final entry = item.value;
                final ratio = total == 0 ? 0.0 : entry.value / total;

                final barColor = AppDesign
                    .chartPalette[index % AppDesign.chartPalette.length];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppDesign.ink,
                              ),
                            ),
                          ),
                          Text(
                            '${entry.value}  ${(ratio * 100).round()}%',
                            style: const TextStyle(
                              color: AppDesign.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      LinearProgressIndicator(
                        value: ratio,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(99),
                        color: barColor,
                        backgroundColor: barColor.withValues(alpha: 0.14),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
