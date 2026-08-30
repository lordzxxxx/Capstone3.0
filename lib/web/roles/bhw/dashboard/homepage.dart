import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/shared/components/app_metric_card.dart';
import 'package:mycapstone_project/web/shared/components/web_data_components.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/web/shared/components/web_responsive_body.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

// Use the same centralized palette as the shared BHW/CHO web components.
// The dashboard uses navy and blue tones for all presentation accents; labels
// and icons continue to communicate the underlying record state.
const Color _primaryAqua = AppColors.primary;
const Color _secondaryIceBlue = AppColors.secondary;
const Color _darkDeepTeal = AppColors.backgroundLight;
const Color _mutedCoolGray = AppColors.textSecondary;
const Color _lightOffWhite = AppColors.surfaceDark;
const Color _sidebarDark = AppColors.surfaceLight;
const Color _insightBlue = AppColors.primary;
const Color _insightNavy = AppColors.secondary;

enum DashboardDateFilterMode {
  today,
  last7Days,
  last30Days,
  thisMonth,
  last6Months,
  customDay,
  customRange,
  allTime,
}

class _TrendData {
  final String title;
  final String subtitle;
  final List<String> labels;
  final List<int> counts;

  const _TrendData({
    required this.title,
    required this.subtitle,
    required this.labels,
    required this.counts,
  });
}

class HomePage extends StatefulWidget {
  final User? user;
  const HomePage({super.key, this.user});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Raw scoped datasets loaded from Firestore for fast filtering without redundant network requests
  List<Map<String, dynamic>> _rawPatients = [];
  List<Map<String, dynamic>> _rawCheckups = [];
  List<Map<String, dynamic>> _rawPrenatal = [];
  List<Map<String, dynamic>> _rawMorbidity = [];
  List<Map<String, dynamic>> _rawReferrals = [];

  // Active Date Filter state
  DashboardDateFilterMode _dateFilterMode = DashboardDateFilterMode.thisMonth;
  DateTime? _selectedCustomDate;
  DateTime? _selectedMonthDate;
  DateTime _selectedRangeStart = DateTime.now().subtract(
    const Duration(days: 6),
  );
  DateTime _selectedRangeEnd = DateTime.now();

  int _totalPatients = 0;
  // Actionable Health Insights for active window
  List<Map<String, dynamic>> _actionableInsights = const [];

  // Disease Trend data
  // symptom -> date -> count
  StreamSubscription<QuerySnapshot>? _morbidityTrendSubscription;
  StreamSubscription<List<Map<String, dynamic>>>?
  _todaysOverviewCheckupSubscription;
  StreamSubscription<QuerySnapshot>? _todaysOverviewPatientSubscription;

  // Notification state

  // Activity Feed & Recent Activity
  List<Map<String, dynamic>> _recentActivity = [];
  bool _isLoadingActivity = false;

  // Widget visibility toggles
  final bool _showActivityFeed = true;

  // Advanced Filter state

  // KPI and Today's Overview state.
  // All values below are derived only from scoped, persisted Firestore
  // records (patients/checkups/prenatal/immunizations) — none are
  // synthesized/randomized. See _loadKPIData().

  // Executive overview data. These values are derived only from scoped,
  // persisted health records; the dashboard does not generate sample metrics.
  bool _isLoadingExecutiveOverview = true;
  String? _executiveOverviewError;
  int _consultationsToday = 0;
  int _activePregnancies = 0;
  int _highRiskPatients = 0;
  int _pendingReferrals = 0;
  int _aiGeneratedAlerts = 0;
  List<String> _consultationMonthLabels = const [];
  List<int> _monthlyConsultationCounts = const [];
  String _trendChartTitle = 'Monthly Consultation Trend';
  String _trendChartSubtitle = 'Check-up volume during the selected period';
  Map<String, int> _referralStatusCounts = const {};
  List<Map<String, dynamic>> _recentHighRiskAlerts = const [];

  @override
  void initState() {
    super.initState();
    _selectedMonthDate ??= DateTime.now();
    _selectedRangeStart = DateTime.now().subtract(const Duration(days: 6));
    _selectedRangeEnd = DateTime.now();
    _loadExecutiveOverview();
  }

  Future<List<Map<String, dynamic>>> _loadScopedDashboardRecords(
    String collectionName, {
    UserAccessScope? accessScope,
  }) async {
    final scope =
        accessScope ?? await UserAccessScopeService.instance.loadCurrentScope();
    Query<Map<String, dynamic>> query = buildScopedRecordQuery(
      getFirestoreInstance(),
      collectionName,
      scope,
    );
    if (collectionName == 'referrals' && scope.isBhw) {
      // Firestore referral rules permit a BHW to read only referrals they
      // created. Including this constraint lets Firestore prove the query is
      // authorized instead of rejecting the entire barangay collection read.
      query = query.where('createdByUid', isEqualTo: scope.userId);
    }
    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      // Let Firestore choose the freshest available source. On web this is
      // cache-first when the browser is offline and server-backed when it is
      // online; forcing Source.server made a short outage look like an empty
      // dashboard even after records had already been loaded.
      snapshot = await query.get();
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'BHW dashboard query failed: collection=$collectionName '
          'barangay=${scope.barangayCode} error=$error',
        );
      }
      rethrow;
    }

    // Some records have a root compatibility document and a barangay mirror.
    // Stable document IDs prevent those mirrors from inflating dashboard totals.
    final unique = <String, Map<String, dynamic>>{};
    for (final doc in snapshot.docs) {
      unique[doc.id] = <String, dynamic>{
        ...doc.data(),
        'id': doc.id,
        '_firestorePath': doc.reference.path,
      };
    }
    return unique.values.toList(growable: false);
  }

  String _dashboardText(
    Map<String, dynamic> record,
    List<String> keys, {
    String fallback = 'Unknown',
  }) {
    for (final key in keys) {
      final value = record[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return fallback;
  }

  bool _isHighRiskValue(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return normalized.contains('high risk') ||
        normalized == 'high' ||
        normalized.contains('critical') ||
        normalized.contains('severe') ||
        normalized.contains('emergency');
  }

  String _patientIdentity(Map<String, dynamic> record) {
    return _dashboardText(record, const [
      'linkedPatientId',
      'patientId',
      'patientRecordId',
      'patientName',
      'name',
    ], fallback: record['id']?.toString() ?? 'unknown').toLowerCase();
  }

  Future<void> _loadExecutiveOverview() async {
    if (!mounted) return;
    setState(() {
      _isLoadingExecutiveOverview = true;
      _isLoadingActivity = true;
      _executiveOverviewError = null;
    });

    try {
      // Refresh once after login/approval, then reuse the exact same resolved
      // barangay and role for every dashboard query. This avoids concurrent
      // scope fallbacks producing differently scoped collection paths.
      final scope = await UserAccessScopeService.instance.loadCurrentScope(
        forceRefresh: true,
      );
      if (!scope.isAuthenticated || !scope.isBhw) {
        throw StateError('An approved BHW account is required.');
      }

      final results = await Future.wait<List<Map<String, dynamic>>>([
        _loadScopedDashboardRecords('patient_records', accessScope: scope),
        _loadScopedDashboardRecords('checkup_records', accessScope: scope),
        _loadScopedDashboardRecords('prenatal_records', accessScope: scope),
        _loadScopedDashboardRecords('morbidity_records', accessScope: scope),
      ]);
      final patients = results[0];
      final checkups = results[1];
      final prenatal = results[2];
      final morbidity = results[3];
      List<Map<String, dynamic>> referrals = const [];
      try {
        // Referral rules intentionally expose only records created by this
        // BHW. `_loadScopedDashboardRecords` adds the required createdByUid
        // constraint so Firestore can authorize the query.
        referrals = await _loadScopedDashboardRecords(
          'referrals',
          accessScope: scope,
        );
      } on FirebaseException catch (error) {
        if (error.code != 'permission-denied') rethrow;
        // Referral statistics are supplementary. A temporary/stale referral
        // permission must not hide the otherwise authorized health dashboard.
        if (kDebugMode) {
          debugPrint(
            'BHW dashboard referral summary unavailable for '
            '${scope.userId}: ${error.code}',
          );
        }
      }

      _rawPatients = patients;
      _rawCheckups = checkups;
      _rawPrenatal = prenatal;
      _rawMorbidity = morbidity;
      _rawReferrals = referrals;

      _recomputeDashboardMetrics();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('BHW executive dashboard load failed: $error');
      }
      if (!mounted) return;
      setState(() {
        _isLoadingExecutiveOverview = false;
        _isLoadingActivity = false;
        _executiveOverviewError = error.toString();
      });
    }
  }

  DateTime? _coerceRecordDate(Map<String, dynamic> record) {
    return _coerceOverviewDate(record) ??
        _resolveMetricDate(record, const [
          'datetime',
          'date',
          'registrationDate',
          'consultationDate',
          'administrationDate',
          'diagnosisDate',
          'recordDate',
          'createdAt',
          'updatedAt',
          'timestamp',
          'lmpDate',
          'dueDate',
        ]);
  }

  bool _matchesDateFilter(DateTime? date) {
    if (_dateFilterMode == DashboardDateFilterMode.allTime) return true;
    if (date == null) return false;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (_dateFilterMode) {
      case DashboardDateFilterMode.today:
        return !date.isBefore(todayStart) && !date.isAfter(todayEnd);
      case DashboardDateFilterMode.last7Days:
        final start = todayStart.subtract(const Duration(days: 6));
        return !date.isBefore(start) && !date.isAfter(todayEnd);
      case DashboardDateFilterMode.last30Days:
        final start = todayStart.subtract(const Duration(days: 29));
        return !date.isBefore(start) && !date.isAfter(todayEnd);
      case DashboardDateFilterMode.thisMonth:
        final targetMonth = _selectedMonthDate ?? now;
        return date.year == targetMonth.year && date.month == targetMonth.month;
      case DashboardDateFilterMode.last6Months:
        final start = DateTime(now.year, now.month - 5, 1);
        return !date.isBefore(start) && !date.isAfter(todayEnd);
      case DashboardDateFilterMode.customDay:
        final target = _selectedCustomDate ?? now;
        final start = DateTime(target.year, target.month, target.day);
        final end = DateTime(target.year, target.month, target.day, 23, 59, 59);
        return !date.isBefore(start) && !date.isAfter(end);
      case DashboardDateFilterMode.customRange:
        final start = DateTime(
          _selectedRangeStart.year,
          _selectedRangeStart.month,
          _selectedRangeStart.day,
        );
        final end = DateTime(
          _selectedRangeEnd.year,
          _selectedRangeEnd.month,
          _selectedRangeEnd.day,
          23,
          59,
          59,
        );
        return !date.isBefore(start) && !date.isAfter(end);
      case DashboardDateFilterMode.allTime:
        return true;
    }
  }

  String _activeWindowLabel([DashboardDateFilterMode? mode]) {
    final activeMode = mode ?? _dateFilterMode;
    final now = DateTime.now();
    try {
      switch (activeMode) {
        case DashboardDateFilterMode.today:
          return 'Today (${_monthLabelShort(now.month)} ${now.day}, ${now.year})';
        case DashboardDateFilterMode.last7Days:
          final start = now.subtract(const Duration(days: 6));
          return 'Last 7 Days (${_monthLabelShort(start.month)} ${start.day} - ${_monthLabelShort(now.month)} ${now.day})';
        case DashboardDateFilterMode.last30Days:
          final start = now.subtract(const Duration(days: 29));
          return 'Last 30 Days (${_monthLabelShort(start.month)} ${start.day} - ${_monthLabelShort(now.month)} ${now.day})';
        case DashboardDateFilterMode.thisMonth:
          final target = _selectedMonthDate ?? now;
          return '${_monthLabelLong(target.month)} ${target.year}';
        case DashboardDateFilterMode.last6Months:
          final start = DateTime(now.year, now.month - 5, 1);
          return 'Last 6 Months (${_monthLabelShort(start.month)} ${start.year} - ${_monthLabelShort(now.month)} ${now.year})';
        case DashboardDateFilterMode.customDay:
          final d = _selectedCustomDate ?? now;
          return '${_monthLabelLong(d.month)} ${d.day}, ${d.year}';
        case DashboardDateFilterMode.customRange:
          final s = _selectedRangeStart;
          final e = _selectedRangeEnd;
          return '${_monthLabelShort(s.month)} ${s.day} - ${_monthLabelShort(e.month)} ${e.day}, ${e.year}';
        case DashboardDateFilterMode.allTime:
          return 'All Time History';
      }
    } catch (_) {}
    return 'This Month';
  }

  void _recomputeDashboardMetrics() {
    final filteredPatients = _rawPatients
        .where((p) => _matchesDateFilter(_coerceRecordDate(p)))
        .toList(growable: false);
    final filteredCheckups = _rawCheckups
        .where((c) => _matchesDateFilter(_coerceRecordDate(c)))
        .toList(growable: false);
    final filteredPrenatal = _rawPrenatal
        .where((p) => _matchesDateFilter(_coerceRecordDate(p)))
        .toList(growable: false);
    final filteredMorbidity = _rawMorbidity
        .where((m) => _matchesDateFilter(_coerceRecordDate(m)))
        .toList(growable: false);
    final filteredReferrals = _rawReferrals
        .where((r) => _matchesDateFilter(_coerceRecordDate(r)))
        .toList(growable: false);

    final consultationsInWindow = filteredCheckups.length;

    var activePregnanciesInWindow = 0;
    for (final record in filteredPrenatal) {
      final status = _dashboardText(record, const [
        'status',
        'recordStatus',
      ], fallback: 'active').toLowerCase();
      if (!status.contains('completed') &&
          !status.contains('closed') &&
          !status.contains('inactive')) {
        activePregnanciesInWindow++;
      }
    }

    var aiAlertsInWindow = 0;
    final highRiskIdentities = <String>{};
    final highRiskAlerts = <Map<String, dynamic>>[];

    for (final checkup in filteredCheckups) {
      final date = _coerceRecordDate(checkup);
      final hasAiGuidance = _dashboardText(checkup, const [
        'ai_category',
        'ai_method',
      ], fallback: '').isNotEmpty;
      final riskValue = _dashboardText(checkup, const [
        'ai_severity',
        'severity',
        'riskLevel',
      ], fallback: '');
      if (_isHighRiskValue(riskValue)) {
        if (hasAiGuidance) aiAlertsInWindow++;
        highRiskIdentities.add(_patientIdentity(checkup));
        highRiskAlerts.add({
          'title': _dashboardText(checkup, const [
            'patientName',
            'patient',
            'name',
          ], fallback: 'Check-up patient'),
          'subtitle': 'Check-up flagged as $riskValue',
          'timestamp': date,
          'source': hasAiGuidance ? 'AI guidance' : 'Check-up',
        });
      }
    }

    for (final record in filteredPrenatal) {
      final riskValue = _dashboardText(record, const [
        'riskLevel',
        'ai_severity',
        'severity',
      ], fallback: '');
      if (_isHighRiskValue(riskValue)) {
        highRiskIdentities.add(_patientIdentity(record));
        highRiskAlerts.add({
          'title': _dashboardText(record, const [
            'patientName',
            'name',
          ], fallback: 'Prenatal patient'),
          'subtitle': 'Prenatal case flagged as $riskValue',
          'timestamp': _coerceRecordDate(record),
          'source': 'Prenatal',
        });
      }
      final hasAiGuidance = _dashboardText(record, const [
        'ai_category',
        'ai_method',
      ], fallback: '').isNotEmpty;
      if (hasAiGuidance && _isHighRiskValue(riskValue)) {
        aiAlertsInWindow++;
      }
    }

    for (final record in filteredMorbidity) {
      final disease = _dashboardText(record, const [
        'disease',
        'diagnosis',
        'condition',
      ], fallback: 'Unspecified');

      final riskValue = _dashboardText(record, const [
        'severity',
        'riskLevel',
      ], fallback: '');
      if (_isHighRiskValue(riskValue)) {
        highRiskIdentities.add(_patientIdentity(record));
        highRiskAlerts.add({
          'title': _dashboardText(record, const [
            'patientName',
            'name',
          ], fallback: disease),
          'subtitle': '$disease • $riskValue severity',
          'timestamp': _coerceRecordDate(record),
          'source': 'Morbidity',
        });
      }
    }

    final referralCounts = <String, int>{};
    var pendingReferralsInWindow = 0;
    for (final referral in filteredReferrals) {
      final status = _dashboardText(referral, const [
        'status',
        'referralStatus',
      ], fallback: 'Submitted');
      referralCounts[status] = (referralCounts[status] ?? 0) + 1;
      final normalized = status.toLowerCase();
      if (!normalized.contains('completed') &&
          !normalized.contains('closed') &&
          !normalized.contains('cancel')) {
        pendingReferralsInWindow++;
      }
    }

    final systemActivity = <Map<String, dynamic>>[];
    void addActivities(
      List<Map<String, dynamic>> records, {
      required String title,
      required IconData icon,
      required Color color,
      required List<String> detailKeys,
    }) {
      for (final record in records) {
        final timestamp = _coerceRecordDate(record);
        if (timestamp == null) continue;
        systemActivity.add({
          'title': title,
          'subtitle': _dashboardText(
            record,
            detailKeys,
            fallback: 'Record updated',
          ),
          'timestamp': timestamp,
          'icon': icon,
          'color': color,
        });
      }
    }

    addActivities(
      filteredPatients,
      title: 'Patient registered',
      icon: Icons.person_add_alt_1_rounded,
      color: _primaryAqua,
      detailKeys: const ['patientName', 'name'],
    );
    addActivities(
      filteredCheckups,
      title: 'Consultation recorded',
      icon: Icons.medical_services_rounded,
      color: _insightBlue,
      detailKeys: const ['patientName', 'patient', 'disease', 'type'],
    );
    addActivities(
      filteredPrenatal,
      title: 'Prenatal record updated',
      icon: Icons.pregnant_woman_rounded,
      color: _insightBlue,
      detailKeys: const ['patientName', 'name', 'status'],
    );
    addActivities(
      filteredMorbidity,
      title: 'Morbidity case updated',
      icon: Icons.monitor_heart_rounded,
      color: _insightNavy,
      detailKeys: const ['disease', 'condition', 'patientName'],
    );
    addActivities(
      filteredReferrals,
      title: 'Referral status updated',
      icon: Icons.assignment_ind_rounded,
      color: _insightNavy,
      detailKeys: const ['patientName', 'status', 'referralReason'],
    );

    systemActivity.sort((a, b) {
      final aDate = a['timestamp'] as DateTime;
      final bDate = b['timestamp'] as DateTime;
      return bDate.compareTo(aDate);
    });

    highRiskAlerts.sort((a, b) {
      final aDate = a['timestamp'] as DateTime?;
      final bDate = b['timestamp'] as DateTime?;
      return (bDate ?? DateTime(1970)).compareTo(aDate ?? DateTime(1970));
    });

    final trendData = _generateConsultationTrendData(filteredCheckups);

    final insights = _generateActionableHealthInsights(
      patients: filteredPatients,
      checkups: filteredCheckups,
      prenatal: filteredPrenatal,
      morbidity: filteredMorbidity,
      referrals: filteredReferrals,
      highRiskCount: highRiskIdentities.length,
      pendingReferralsCount: pendingReferralsInWindow,
      aiAlertsCount: aiAlertsInWindow,
    );

    if (!mounted) return;
    setState(() {
      _totalPatients = _dateFilterMode == DashboardDateFilterMode.allTime
          ? _rawPatients.length
          : filteredPatients.length;
      _consultationsToday = consultationsInWindow;
      _activePregnancies = activePregnanciesInWindow;
      _highRiskPatients = highRiskIdentities.length;
      _pendingReferrals = pendingReferralsInWindow;
      _aiGeneratedAlerts = aiAlertsInWindow;
      _consultationMonthLabels = trendData.labels;
      _monthlyConsultationCounts = trendData.counts;
      _trendChartTitle = trendData.title;
      _trendChartSubtitle = trendData.subtitle;
      _referralStatusCounts = referralCounts;
      _recentHighRiskAlerts = highRiskAlerts.take(6).toList(growable: false);
      _recentActivity = systemActivity.take(10).toList(growable: false);
      _actionableInsights = insights;
      _isLoadingExecutiveOverview = false;
      _isLoadingActivity = false;
    });
  }

  _TrendData _generateConsultationTrendData(
    List<Map<String, dynamic>> checkups,
  ) {
    final now = DateTime.now();

    if (_dateFilterMode == DashboardDateFilterMode.today ||
        _dateFilterMode == DashboardDateFilterMode.customDay) {
      final targetDate = _dateFilterMode == DashboardDateFilterMode.today
          ? now
          : (_selectedCustomDate ?? now);
      final slotLabels = ['8 AM', '10 AM', '12 PM', '2 PM', '4 PM', '6 PM+'];
      final slotCounts = List<int>.filled(slotLabels.length, 0);

      for (final c in checkups) {
        final d = _coerceRecordDate(c);
        if (d != null &&
            d.year == targetDate.year &&
            d.month == targetDate.month &&
            d.day == targetDate.day) {
          final hour = d.hour;
          if (hour < 9) {
            slotCounts[0]++;
          } else if (hour < 11) {
            slotCounts[1]++;
          } else if (hour < 13) {
            slotCounts[2]++;
          } else if (hour < 15) {
            slotCounts[3]++;
          } else if (hour < 17) {
            slotCounts[4]++;
          } else {
            slotCounts[5]++;
          }
        }
      }

      return _TrendData(
        title: 'Intraday Consultation Activity',
        subtitle:
            'Consultations recorded by time interval for ${_monthLabelShort(targetDate.month)} ${targetDate.day}, ${targetDate.year}',
        labels: slotLabels,
        counts: slotCounts,
      );
    }

    if (_dateFilterMode == DashboardDateFilterMode.last7Days) {
      final days = List<DateTime>.generate(
        7,
        (index) => now.subtract(Duration(days: 6 - index)),
      );
      final labels = days
          .map((d) => '${_monthLabelShort(d.month)} ${d.day}')
          .toList(growable: false);
      final counts = List<int>.filled(7, 0);

      for (final c in checkups) {
        final d = _coerceRecordDate(c);
        if (d != null) {
          for (var i = 0; i < days.length; i++) {
            if (d.year == days[i].year &&
                d.month == days[i].month &&
                d.day == days[i].day) {
              counts[i]++;
              break;
            }
          }
        }
      }

      return _TrendData(
        title: '7-Day Daily Consultation Volume',
        subtitle: 'Daily consultations over the last 7 days',
        labels: labels,
        counts: counts,
      );
    }

    if (_dateFilterMode == DashboardDateFilterMode.last30Days ||
        (_dateFilterMode == DashboardDateFilterMode.customRange &&
            _selectedRangeEnd.difference(_selectedRangeStart).inDays <= 31)) {
      final startDate = _dateFilterMode == DashboardDateFilterMode.last30Days
          ? now.subtract(const Duration(days: 29))
          : _selectedRangeStart;
      final endDate = _dateFilterMode == DashboardDateFilterMode.last30Days
          ? now
          : _selectedRangeEnd;
      final totalDays = endDate.difference(startDate).inDays + 1;
      final safeDays = totalDays.clamp(1, 31);

      final days = List<DateTime>.generate(
        safeDays,
        (index) => startDate.add(Duration(days: index)),
      );
      final labels = days
          .map((d) => '${_monthLabelShort(d.month)} ${d.day}')
          .toList(growable: false);
      final counts = List<int>.filled(safeDays, 0);

      for (final c in checkups) {
        final d = _coerceRecordDate(c);
        if (d != null) {
          for (var i = 0; i < days.length; i++) {
            if (d.year == days[i].year &&
                d.month == days[i].month &&
                d.day == days[i].day) {
              counts[i]++;
              break;
            }
          }
        }
      }

      return _TrendData(
        title: 'Daily Consultation Trend',
        subtitle:
            'Daily consultations across ${_activeWindowLabel().toLowerCase()}',
        labels: labels,
        counts: counts,
      );
    }

    if (_dateFilterMode == DashboardDateFilterMode.thisMonth) {
      final target = _selectedMonthDate ?? now;
      final daysInMonth = DateTime(target.year, target.month + 1, 0).day;
      final weekLabels = [
        'Week 1',
        'Week 2',
        'Week 3',
        'Week 4',
        if (daysInMonth > 28) 'Week 5',
      ];
      final weekCounts = List<int>.filled(weekLabels.length, 0);

      for (final c in checkups) {
        final d = _coerceRecordDate(c);
        if (d != null && d.year == target.year && d.month == target.month) {
          final weekIndex = ((d.day - 1) ~/ 7).clamp(0, weekLabels.length - 1);
          weekCounts[weekIndex]++;
        }
      }

      return _TrendData(
        title: 'Weekly Consultation Breakdown',
        subtitle:
            'Weekly consultations for ${_monthLabelLong(target.month)} ${target.year}',
        labels: weekLabels,
        counts: weekCounts,
      );
    }

    // Default / Last 6 Months / All Time
    final monthStarts = List<DateTime>.generate(
      6,
      (index) => DateTime(now.year, now.month - (5 - index), 1),
    );
    final monthKeys = monthStarts
        .map((date) => '${date.year}-${date.month}')
        .toList(growable: false);
    final counts = <String, int>{for (final k in monthKeys) k: 0};

    for (final c in checkups) {
      final d = _coerceRecordDate(c);
      if (d != null) {
        final key = '${d.year}-${d.month}';
        if (counts.containsKey(key)) {
          counts[key] = counts[key]! + 1;
        }
      }
    }

    return _TrendData(
      title: 'Monthly Consultation Trend',
      subtitle: 'Check-up volume over the last 6 months',
      labels: monthStarts.map((d) => _monthLabelShort(d.month)).toList(),
      counts: monthKeys.map((k) => counts[k] ?? 0).toList(),
    );
  }

  List<Map<String, dynamic>> _generateActionableHealthInsights({
    required List<Map<String, dynamic>> patients,
    required List<Map<String, dynamic>> checkups,
    required List<Map<String, dynamic>> prenatal,
    required List<Map<String, dynamic>> morbidity,
    required List<Map<String, dynamic>> referrals,
    required int highRiskCount,
    required int pendingReferralsCount,
    required int aiAlertsCount,
  }) {
    final insights = <Map<String, dynamic>>[];

    // 1. High-risk Alert Insight
    if (highRiskCount > 0) {
      insights.add({
        'icon': Icons.warning_amber_rounded,
        'title':
            '$highRiskCount High-Risk ${highRiskCount == 1 ? 'Case' : 'Cases'} Detected',
        'message':
            '$highRiskCount patients require immediate clinical prioritization and monitoring during this reporting period.',
        'severity': 'critical',
        'color': _insightNavy,
      });
    } else {
      insights.add({
        'icon': Icons.check_circle_outline_rounded,
        'title': 'No High-Risk Flags',
        'message':
            'No high-risk patient flags recorded in this period. Standard health monitoring continues.',
        'severity': 'success',
        'color': _insightBlue,
      });
    }

    // 2. Consultation Load Insight
    if (checkups.isNotEmpty) {
      insights.add({
        'icon': Icons.medical_services_outlined,
        'title': '${checkups.length} Consultations Recorded',
        'message':
            'Consultation services are actively ongoing with ${checkups.length} check-up ${checkups.length == 1 ? 'session' : 'sessions'} in this period.',
        'severity': 'info',
        'color': _primaryAqua,
      });
    } else {
      insights.add({
        'icon': Icons.assignment_late_outlined,
        'title': 'No Consultations in Period',
        'message':
            'Zero consultations recorded for this date window. Check community scheduling or pending walk-ins.',
        'severity': 'warning',
        'color': _insightNavy,
      });
    }

    // 3. Prenatal Care Insight
    if (prenatal.isNotEmpty) {
      insights.add({
        'icon': Icons.pregnant_woman_rounded,
        'title':
            '${prenatal.length} Maternal / Prenatal ${prenatal.length == 1 ? 'Record' : 'Records'}',
        'message':
            'Active prenatal care monitoring maintained. Ensure scheduled trimester follow-ups.',
        'severity': 'info',
        'color': _insightBlue,
      });
    }

    // 4. Morbidity Surveillance Insight
    if (morbidity.isNotEmpty) {
      final diseaseCounts = <String, int>{};
      for (final m in morbidity) {
        final disease = _dashboardText(m, const [
          'disease',
          'diagnosis',
          'condition',
        ], fallback: 'General Illness');
        diseaseCounts[disease] = (diseaseCounts[disease] ?? 0) + 1;
      }
      final sortedDiseases = diseaseCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (sortedDiseases.isNotEmpty) {
        final top = sortedDiseases.first;
        insights.add({
          'icon': Icons.coronavirus_outlined,
          'title': 'Top Condition: ${top.key}',
          'message':
              '${top.value} case(s) reported in this window. Monitor community spread and stock appropriate supplies.',
          'severity': 'warning',
          'color': _insightNavy,
        });
      }
    }

    // 5. Referral Workflow Insight
    if (pendingReferralsCount > 0) {
      insights.add({
        'icon': Icons.assignment_ind_outlined,
        'title':
            '$pendingReferralsCount Pending ${pendingReferralsCount == 1 ? 'Referral' : 'Referrals'}',
        'message':
            '$pendingReferralsCount patient referrals are awaiting doctor or CHO confirmation and treatment follow-through.',
        'severity': 'warning',
        'color': _insightNavy,
      });
    }

    // 6. AI Decision Support
    if (aiAlertsCount > 0) {
      insights.add({
        'icon': Icons.psychology_alt_rounded,
        'title':
            '$aiAlertsCount ${aiAlertsCount == 1 ? 'Patient Needs' : 'Patients Need'} Follow-up',
        'message':
            'Flagged by the system for possible risk — review these $aiAlertsCount record${aiAlertsCount == 1 ? '' : 's'} and decide if further action is needed.',
        'severity': 'info',
        'color': _primaryAqua,
      });
    }

    return insights;
  }

  /// Helper method to retry async operations with exponential backoff

  /// Create invitation record asynchronously (non-blocking, fire-and-forget)

  DateTime? _resolveMetricDate(
    Map<String, dynamic> record,
    List<String> candidateKeys,
  ) {
    for (final key in candidateKeys) {
      final parsed = _coerceMetricDateValue(record[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  DateTime? _coerceMetricDateValue(dynamic value) {
    final direct = _coerceTrendDate(value);
    if (direct != null) return direct;
    if (value is! String) return null;

    final text = value.trim();
    if (text.isEmpty) return null;

    final normalized = text.contains('T') ? text.split('T').first : text;
    final slashParts = normalized.split('/');
    if (slashParts.length == 3) {
      final first = int.tryParse(slashParts[0]);
      final second = int.tryParse(slashParts[1]);
      final third = int.tryParse(slashParts[2]);
      if (first != null && second != null && third != null) {
        if (slashParts[0].length == 4) {
          return DateTime(first, second, third);
        }
        return DateTime(third, first, second);
      }
    }

    final dashParts = normalized.split('-');
    if (dashParts.length == 3) {
      final first = int.tryParse(dashParts[0]);
      final second = int.tryParse(dashParts[1]);
      final third = int.tryParse(dashParts[2]);
      if (first != null && second != null && third != null) {
        if (dashParts[0].length == 4) {
          return DateTime(first, second, third);
        }
        return DateTime(third, first, second);
      }
    }

    return null;
  }

  DateTime _normalizeToMonth(DateTime date) {
    return DateTime(date.year, date.month);
  }

  Future<DateTime?> _pickMonthYear({
    required DateTime initialDate,
    String helpText = 'Select month',
  }) async {
    final min = DateTime(2000, 1);
    final max = DateTime(2040, 12);

    var selected = _normalizeToMonth(initialDate);
    if (selected.isBefore(min)) selected = min;
    if (selected.isAfter(max)) selected = max;

    final years = <int>[];
    for (var year = min.year; year <= max.year; year++) {
      years.add(year);
    }

    List<int> monthsForYear(int year) {
      return const <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
    }

    var tempYear = selected.year;
    var tempMonth = selected.month;

    return showDialog<DateTime>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final availableMonths = monthsForYear(tempYear);
            if (!availableMonths.contains(tempMonth)) {
              tempMonth = availableMonths.first;
            }

            final dialogTheme = Theme.of(context).copyWith(
              brightness: Brightness.dark,
              dialogTheme: Theme.of(context).dialogTheme.copyWith(
                backgroundColor: _lightOffWhite,
                surfaceTintColor: Colors.transparent,
              ),
              colorScheme: Theme.of(context).colorScheme.copyWith(
                brightness: Brightness.dark,
                primary: _primaryAqua,
                onPrimary: Colors.white,
                surface: _lightOffWhite,
                onSurface: Colors.white,
              ),
              inputDecorationTheme: Theme.of(context).inputDecorationTheme
                  .copyWith(
                    labelStyle: const TextStyle(color: Colors.white70),
                    hintStyle: const TextStyle(color: Colors.white60),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: _secondaryIceBlue.withValues(alpha: 0.35),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: _primaryAqua.withValues(alpha: 0.8),
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: _secondaryIceBlue.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
            );

            return Theme(
              data: dialogTheme,
              child: AlertDialog(
                backgroundColor: _lightOffWhite,
                title: Text(
                  helpText,
                  style: const TextStyle(color: Colors.white),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: tempMonth,
                      dropdownColor: _lightOffWhite,
                      style: const TextStyle(color: Colors.white),
                      iconEnabledColor: Colors.white70,
                      iconDisabledColor: Colors.white54,
                      decoration: InputDecoration(
                        labelText: 'Month',
                        labelStyle: const TextStyle(color: Colors.white70),
                        floatingLabelStyle: const TextStyle(
                          color: _lightOffWhite,
                        ),
                        filled: true,
                        fillColor: _secondaryIceBlue.withValues(alpha: 0.22),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                      items: availableMonths
                          .map(
                            (month) => DropdownMenuItem<int>(
                              value: month,
                              child: Text(
                                _monthLabelLong(month),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => tempMonth = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: tempYear,
                      dropdownColor: _lightOffWhite,
                      style: const TextStyle(color: Colors.white),
                      iconEnabledColor: Colors.white70,
                      iconDisabledColor: Colors.white54,
                      decoration: InputDecoration(
                        labelText: 'Year',
                        labelStyle: const TextStyle(color: Colors.white70),
                        floatingLabelStyle: const TextStyle(
                          color: _lightOffWhite,
                        ),
                        filled: true,
                        fillColor: _secondaryIceBlue.withValues(alpha: 0.22),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                      items: years
                          .map(
                            (year) => DropdownMenuItem<int>(
                              value: year,
                              child: Text(
                                year.toString(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          tempYear = value;
                          final updatedMonths = monthsForYear(tempYear);
                          if (!updatedMonths.contains(tempMonth)) {
                            tempMonth = updatedMonths.first;
                          }
                        });
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryAqua,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(DateTime(tempYear, tempMonth)),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  DateTime? _coerceOverviewDate(Map<String, dynamic> record) {
    return _coerceTrendDate(record['datetime']) ??
        _coerceTrendDate(record['date']) ??
        _coerceTrendDate(record['createdAt']) ??
        _coerceTrendDate(record['timestamp']);
  }

  DateTime? _coerceTrendDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is num) {
      final raw = value.toInt();
      if (raw <= 0) return null;
      final ms = raw > 100000000000 ? raw : raw * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return null;
      final parsed = DateTime.tryParse(text);
      if (parsed != null) return parsed;
    }
    return null;
  }

  String _monthLabelShort(int month) {
    const labels = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    if (month < 1 || month > 12) return 'N/A';
    return labels[month - 1];
  }

  String _monthLabelLong(int month) {
    const labels = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    if (month < 1 || month > 12) return 'N/A';
    return labels[month - 1];
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else {
      return '${difference.inDays} days ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName =
        (user?.displayName != null && user!.displayName!.trim().isNotEmpty)
        ? user.displayName!.trim()
        : user?.email?.split('@')[0] ?? 'User';
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _darkDeepTeal,
      body: WebResponsiveBody(
        sidebar: WebAppSidebar(
          userName: userName,
          activeItem: WebSidebarItem.dashboard,
        ),
        title: 'BHW Dashboard',
        child: SingleChildScrollView(
          child: WebPageContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Welcome - Full Width
                _buildWelcomeCard(userName),
                const SizedBox(height: 24),
                if (_executiveOverviewError != null)
                  _buildExecutiveOverviewError()
                else ...[
                  _buildAnalyticsFilterBar(),
                  const SizedBox(height: 24),
                  _buildExecutiveKpiGrid(),
                  const SizedBox(height: 28),
                  _buildExecutiveAnalytics(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _morbidityTrendSubscription?.cancel();
    _todaysOverviewCheckupSubscription?.cancel();
    _todaysOverviewPatientSubscription?.cancel();
    super.dispose();
  }

  Widget _buildExecutiveOverviewError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _secondaryIceBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _secondaryIceBlue.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: _secondaryIceBlue,
            size: 40,
          ),
          const SizedBox(height: 12),
          const Text(
            'Barangay dashboard could not be loaded',
            style: TextStyle(
              color: _lightOffWhite,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            (_executiveOverviewError ?? '').contains('permission-denied')
                ? 'Your BHW account could not read one or more barangay collections. Sign out, sign in again, and retry after deploying the latest Firestore rules.'
                : 'Check your Firestore connection and account permissions, then try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _mutedCoolGray.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _loadExecutiveOverview,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsFilterBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideHeader = constraints.maxWidth > 760;
        final filterBorderColor = _lightOffWhite.withValues(alpha: 0.12);

        final headerCopy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Barangay Insights & Analytics Filter',
              style: TextStyle(
                color: _lightOffWhite,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose the reporting window for every KPI card, consultation trend, risk alert, and clinical insight. The active range is ${_activeWindowLabel().toLowerCase()}.',
              maxLines: isWideHeader ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _lightOffWhite.withValues(alpha: 0.74),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        );

        final activeWindowCard = Container(
          width: isWideHeader ? 230 : double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _primaryAqua.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _primaryAqua.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.filter_alt_rounded, size: 13, color: _primaryAqua),
                  const SizedBox(width: 5),
                  Text(
                    'Active Window',
                    style: TextStyle(
                      color: _primaryAqua,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _activeWindowLabel(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _lightOffWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'KPIs, charts, and insights auto-synced',
                style: TextStyle(
                  color: _lightOffWhite.withValues(alpha: 0.65),
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        );

        final filterChips = <Widget>[
          _buildFilterChip(
            'Today',
            Icons.today_rounded,
            DashboardDateFilterMode.today,
          ),
          _buildFilterChip(
            'Last 7 Days',
            Icons.calendar_view_week_rounded,
            DashboardDateFilterMode.last7Days,
          ),
          _buildFilterChip(
            'Last 30 Days',
            Icons.date_range_rounded,
            DashboardDateFilterMode.last30Days,
          ),
          _buildFilterChip(
            'This Month',
            Icons.calendar_month_rounded,
            DashboardDateFilterMode.thisMonth,
          ),
          _buildFilterChip(
            'Last 6 Months',
            Icons.stacked_bar_chart_rounded,
            DashboardDateFilterMode.last6Months,
          ),
          _buildFilterChip(
            'All Time',
            Icons.all_inclusive_rounded,
            DashboardDateFilterMode.allTime,
          ),
          OutlinedButton.icon(
            onPressed: _showDateFilterPickerModal,
            icon: const Icon(Icons.tune_rounded, size: 14),
            label: Text(
              _dateFilterMode == DashboardDateFilterMode.customDay ||
                      _dateFilterMode == DashboardDateFilterMode.customRange
                  ? 'Custom (${_activeWindowLabel()})'
                  : 'Pick Date / Range...',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  (_dateFilterMode == DashboardDateFilterMode.customDay ||
                      _dateFilterMode == DashboardDateFilterMode.customRange)
                  ? _primaryAqua
                  : _lightOffWhite,
              backgroundColor:
                  (_dateFilterMode == DashboardDateFilterMode.customDay ||
                      _dateFilterMode == DashboardDateFilterMode.customRange)
                  ? _primaryAqua.withValues(alpha: 0.12)
                  : Colors.white,
              side: BorderSide(
                color:
                    (_dateFilterMode == DashboardDateFilterMode.customDay ||
                        _dateFilterMode == DashboardDateFilterMode.customRange)
                    ? _primaryAqua
                    : filterBorderColor,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ];

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _primaryAqua.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                color: _secondaryIceBlue.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isWideHeader)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: headerCopy),
                    const SizedBox(width: 16),
                    activeWindowCard,
                  ],
                )
              else ...[
                headerCopy,
                const SizedBox(height: 10),
                activeWindowCard,
              ],
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: filterChips),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(
    String label,
    IconData icon,
    DashboardDateFilterMode mode,
  ) {
    final isSelected = _dateFilterMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        if (isSelected) return;
        setState(() {
          _dateFilterMode = mode;
          if (mode == DashboardDateFilterMode.thisMonth) {
            _selectedMonthDate = DateTime.now();
          }
        });
        _recomputeDashboardMetrics();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? _primaryAqua
              : _darkDeepTeal.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? _primaryAqua
                : _secondaryIceBlue.withValues(alpha: 0.12),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _primaryAqua.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : _lightOffWhite,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : _lightOffWhite,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDateFilterPickerModal() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Text(
                'Choose Date for Insights',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _lightOffWhite,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.event_available_rounded,
                  color: _primaryAqua,
                ),
                title: const Text(
                  'Specific Calendar Date',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Pick any specific day'),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedCustomDate ?? now,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _dateFilterMode = DashboardDateFilterMode.customDay;
                    _selectedCustomDate = picked;
                  });
                  _recomputeDashboardMetrics();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.calendar_month_rounded,
                  color: _primaryAqua,
                ),
                title: const Text(
                  'Select Month & Year',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Pick a target month (Current: ${_monthLabelLong((_selectedMonthDate ?? DateTime.now()).month)})',
                ),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  final target = _selectedMonthDate ?? DateTime.now();
                  final picked = await _pickMonthYear(
                    initialDate: target,
                    helpText: 'Select Month & Year for Dashboard',
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _dateFilterMode = DashboardDateFilterMode.thisMonth;
                    _selectedMonthDate = picked;
                  });
                  _recomputeDashboardMetrics();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.date_range_outlined,
                  color: _primaryAqua,
                ),
                title: const Text(
                  'Custom Date Range',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Select custom start and end dates'),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  final picked = await showDateRangePicker(
                    context: context,
                    initialDateRange: DateTimeRange(
                      start: _selectedRangeStart,
                      end: _selectedRangeEnd,
                    ),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _dateFilterMode = DashboardDateFilterMode.customRange;
                    _selectedRangeStart = picked.start;
                    _selectedRangeEnd = picked.end;
                  });
                  _recomputeDashboardMetrics();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.today_rounded, color: _primaryAqua),
                title: const Text(
                  'Quick: Today',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(dialogContext);
                  setState(() {
                    _dateFilterMode = DashboardDateFilterMode.today;
                  });
                  _recomputeDashboardMetrics();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.all_inclusive_rounded,
                  color: _secondaryIceBlue,
                ),
                title: const Text(
                  'Quick: All Time',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(dialogContext);
                  setState(() {
                    _dateFilterMode = DashboardDateFilterMode.allTime;
                  });
                  _recomputeDashboardMetrics();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionableInsightsPanel() {
    return _buildExecutivePanel(
      title: 'Actionable Health Insights',
      subtitle:
          'Data-driven clinical guidance for ${_activeWindowLabel().toLowerCase()}',
      icon: Icons.insights_rounded,
      child: _actionableInsights.isEmpty
          ? _buildNoExecutiveData(
              'No insights available for the selected period.',
            )
          : Column(
              children: _actionableInsights.map((insight) {
                final Color color =
                    (insight['color'] as Color?) ?? _primaryAqua;
                final IconData icon =
                    (insight['icon'] as IconData?) ?? Icons.insights_rounded;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.22)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: color, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              insight['title']?.toString() ?? 'Insight',
                              style: const TextStyle(
                                color: _lightOffWhite,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              insight['message']?.toString() ?? '',
                              style: TextStyle(
                                color: _mutedCoolGray.withValues(alpha: 0.9),
                                fontSize: 11.5,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildExecutiveKpiGrid() {
    final subtitlePeriod = _activeWindowLabel();
    final metrics = <Map<String, dynamic>>[
      {
        'title': 'Total Registered Patients',
        'value': _totalPatients,
        'subtitle': _dateFilterMode == DashboardDateFilterMode.allTime
            ? 'Total visible registry'
            : 'Registrations in $subtitlePeriod',
        'icon': Icons.groups_2_rounded,
      },
      {
        'title': 'Consultations',
        'value': _consultationsToday,
        'subtitle': 'Recorded in $subtitlePeriod',
        'icon': Icons.medical_services_rounded,
      },
      {
        'title': 'Active Pregnancies',
        'value': _activePregnancies,
        'subtitle': 'Open prenatal care in $subtitlePeriod',
        'icon': Icons.pregnant_woman_rounded,
      },
      {
        'title': 'High-risk Patients',
        'value': _highRiskPatients,
        'subtitle': 'Flagged in $subtitlePeriod',
        'icon': Icons.warning_amber_rounded,
      },
      {
        'title': 'Pending Referrals',
        'value': _pendingReferrals,
        'subtitle': 'Open referrals in $subtitlePeriod',
        'icon': Icons.assignment_late_rounded,
      },
      {
        'title': 'Patients Flagged for Review',
        'value': _aiGeneratedAlerts,
        'subtitle': 'System-flagged records in $subtitlePeriod',
        'icon': Icons.psychology_alt_rounded,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildWebSectionHeader(
          title: 'Barangay Health Operations',
          icon: Icons.dashboard_customize_rounded,
          onRefresh: _isLoadingExecutiveOverview
              ? null
              : _loadExecutiveOverview,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1180
                ? 4
                : constraints.maxWidth >= 650
                ? 2
                : 1;
            const spacing = 16.0;
            final cardWidth = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: List.generate(metrics.length, (index) {
                final metric = metrics[index];
                return SizedBox(
                  width: cardWidth,
                  child: _buildWebMetricCard(
                    title: metric['title'] as String,
                    value: _isLoadingExecutiveOverview
                        ? '...'
                        : '${metric['value']}',
                    subtitle: metric['subtitle'] as String,
                    icon: metric['icon'] as IconData,
                  ),
                );
              }, growable: false),
            );
          },
        ),
      ],
    );
  }

  Widget _buildExecutivePanel({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: _lightOffWhite, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _lightOffWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _mutedCoolGray.withValues(alpha: 0.9),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _buildNoExecutiveData(String message) {
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.insert_chart_outlined_rounded,
              color: _mutedCoolGray.withValues(alpha: 0.65),
              size: 34,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: _mutedCoolGray.withValues(alpha: 0.9)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyConsultationTrend() {
    final counts = _monthlyConsultationCounts;
    final maxCount = counts.isEmpty
        ? 1
        : counts.reduce((a, b) => a > b ? a : b).clamp(1, 1000000);
    return _buildExecutivePanel(
      title: _trendChartTitle,
      subtitle: _trendChartSubtitle,
      icon: Icons.show_chart_rounded,
      child: counts.isEmpty
          ? _buildNoExecutiveData(
              'No consultation history is available for this period.',
            )
          : SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: (maxCount * 1.25).ceilToDouble(),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxCount <= 4
                        ? 1
                        : (maxCount / 4).ceilToDouble(),
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: _secondaryIceBlue.withValues(alpha: 0.12),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        interval: maxCount <= 4
                            ? 1
                            : (maxCount / 4).ceilToDouble(),
                        getTitlesWidget: (value, meta) => Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            color: _mutedCoolGray.withValues(alpha: 0.9),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 ||
                              index >= _consultationMonthLabels.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _consultationMonthLabels[index],
                              style: TextStyle(
                                color: _mutedCoolGray.withValues(alpha: 0.9),
                                fontSize: 10,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => _darkDeepTeal,
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List<FlSpot>.generate(
                        counts.length,
                        (index) =>
                            FlSpot(index.toDouble(), counts[index].toDouble()),
                      ),
                      isCurved: true,
                      color: _primaryAqua,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: _primaryAqua.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildDistributionPanel({
    required String title,
    required String subtitle,
    required IconData icon,
    required Map<String, int> values,
    int limit = 6,
  }) {
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final visible = entries.take(limit).toList(growable: false);
    final maxValue = visible.isEmpty ? 1 : visible.first.value;

    return _buildExecutivePanel(
      title: title,
      subtitle: subtitle,
      icon: icon,
      child: visible.isEmpty
          ? _buildNoExecutiveData('No records are available for this summary.')
          : Column(
              children: visible.map((entry) {
                final ratio = maxValue == 0 ? 0.0 : entry.value / maxValue;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 13),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.key,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _lightOffWhite,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${entry.value}',
                            style: const TextStyle(
                              color: _primaryAqua,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: LinearProgressIndicator(
                          minHeight: 7,
                          value: ratio,
                          backgroundColor: _secondaryIceBlue.withValues(
                            alpha: 0.12,
                          ),
                          color: _primaryAqua,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildRecentHighRiskAlerts() {
    return _buildExecutivePanel(
      title: 'Recent High-risk Alerts',
      subtitle: 'Prioritized clinical and AI-assisted decision-support flags',
      icon: Icons.warning_amber_rounded,
      child: _recentHighRiskAlerts.isEmpty
          ? _buildNoExecutiveData('No high-risk flags are currently recorded.')
          : Column(
              children: _recentHighRiskAlerts.map((alert) {
                final date = alert['timestamp'] as DateTime?;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _secondaryIceBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _secondaryIceBlue.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.priority_high_rounded,
                        color: _secondaryIceBlue,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alert['title']?.toString() ?? 'Patient alert',
                              style: const TextStyle(
                                color: _lightOffWhite,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              alert['subtitle']?.toString() ?? '',
                              style: TextStyle(
                                color: _mutedCoolGray.withValues(alpha: 0.9),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            alert['source']?.toString() ?? 'Record',
                            style: const TextStyle(
                              color: _secondaryIceBlue,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (date != null)
                            Text(
                              _formatTime(date),
                              style: TextStyle(
                                color: _mutedCoolGray.withValues(alpha: 0.75),
                                fontSize: 9,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildExecutiveAnalytics() {
    final panels = <Widget>[
      _buildMonthlyConsultationTrend(),
      _buildActionableInsightsPanel(),
      _buildRecentHighRiskAlerts(),
      _buildDistributionPanel(
        title: 'Referral Status Summary',
        subtitle:
            'Workflow status for referrals in ${_activeWindowLabel().toLowerCase()}',
        icon: Icons.assignment_ind_rounded,
        values: _referralStatusCounts,
      ),
      if (_showActivityFeed) _buildRecentActivityFeed(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildWebSectionHeader(
          title: 'Barangay Activity and Follow-up',
          icon: Icons.insights_rounded,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 1040;
            final panelWidth = twoColumns
                ? (constraints.maxWidth - 20) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 20,
              runSpacing: 20,
              children: panels
                  .map((panel) => SizedBox(width: panelWidth, child: panel))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildWebMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    return AppMetricCard(
      label: title,
      value: value,
      icon: icon,
      supportingText: subtitle,
    );
  }

  Widget _buildWebSectionHeader({
    required String title,
    required IconData icon,
    Widget? trailing,
    VoidCallback? onRefresh,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: _lightOffWhite, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _lightOffWhite,
                  ),
                ),
              ),
              if (trailing != null) ...[trailing, const SizedBox(width: 8)],
              if (onRefresh != null)
                IconButton(
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: _lightOffWhite,
                  ),
                  onPressed: onRefresh,
                  tooltip: 'Refresh',
                  splashRadius: 20,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _primaryAqua.withValues(alpha: 0.5),
                  _primaryAqua.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }

  String _getTimeBasedGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning';
    } else if (hour < 18) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
    }
  }

  Widget _buildWelcomeCard(String userName) {
    final now = DateTime.now();
    final timeFormatted =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final greeting = _getTimeBasedGreeting();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.15),
          width: 1.5,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12071A33),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Info Section
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$greeting, ',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _lightOffWhite,
                        ),
                      ),
                      TextSpan(
                        text: userName,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _primaryAqua,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 16,
                      color: _lightOffWhite,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      timeFormatted,
                      style: const TextStyle(
                        fontSize: 14,
                        color: _lightOffWhite,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // New Widget Builders

  Widget _buildRecentActivityFeed() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        color: _lightOffWhite,
                        size: 24,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Recent Activity',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _lightOffWhite,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _loadExecutiveOverview,
                  tooltip: 'Refresh recent activity',
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color: _primaryAqua,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoadingActivity)
              Center(
                child: SizedBox(
                  height: 200,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: _primaryAqua),
                      const SizedBox(height: 12),
                      Text(
                        'Loading activity...',
                        style: TextStyle(color: _mutedCoolGray),
                      ),
                    ],
                  ),
                ),
              )
            else if (_recentActivity.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.inbox,
                        size: 40,
                        color: _mutedCoolGray.withValues(alpha: 0.55),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No recent activity',
                        style: TextStyle(color: _mutedCoolGray),
                      ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                height: 250,
                child: ListView.builder(
                  itemCount: _recentActivity.length,
                  itemBuilder: (context, index) {
                    final activity = _recentActivity[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border, width: 1),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (activity['color'] as Color).withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                activity['icon'] as IconData,
                                color: activity['color'] as Color,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    activity['title'] as String,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _lightOffWhite,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    activity['subtitle'] as String,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _mutedCoolGray,
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
                ),
              ),
          ],
        ),
      ),
    );
  }

  // New Dashboard Enhancement Widgets
}
