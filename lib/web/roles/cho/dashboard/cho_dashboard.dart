import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart' hide Query;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/shared/malaybalay_barangays.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/features/auth/cho_access_session.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/roles/cho/referrals/referral.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_navigation.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_config.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/shared/utils/csv_download.dart';

const Color _primaryAqua = Color(0xFF00A8B5);
const Color _secondaryIceBlue = Color(0xFF1E5A7A);
const Color _darkDeepTeal = Color(0xFF0A1F24);
const Color _panelTeal = Color(0xFF102E38);
const Color _panelTealAlt = Color(0xFF123B46);
const Color _mutedCoolGray = Color(0xFF546E7A);
const Color _lightOffWhite = Color(0xFFF5F5F5);

class _ChartLegendDot extends StatelessWidget {
  final String label;
  final Color color;

  const _ChartLegendDot({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: _lightOffWhite.withValues(alpha: 0.75),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

enum _ChoAnalyticsWindow { last30Days, last90Days, last6Months, last12Months }

class ChoDashboard extends StatefulWidget {
  const ChoDashboard({super.key});

  @override
  State<ChoDashboard> createState() => _ChoDashboardState();
}

class _ChoDashboardState extends State<ChoDashboard> {
  static const List<int> _forecastWindows = <int>[30, 60, 90];

  final FirebaseFirestore _firestore = getFirestoreInstance();
  final List<Map<String, dynamic>> _rows = [];
  final List<Map<String, dynamic>> _checkupRows = [];
  final List<Map<String, dynamic>> _prenatalRows = [];
  final List<Map<String, dynamic>> _immunizationRows = [];
  final List<Map<String, dynamic>> _morbidityRows = [];
  final List<Map<String, dynamic>> _mortalityRows = [];
  final List<Map<String, dynamic>> _referralRows = [];
  final List<Map<String, dynamic>> _overdueFollowUps = [];
  bool _isLoading = false;
  bool _authorized = false;
  _ChoAnalyticsWindow _analyticsWindow = _ChoAnalyticsWindow.last6Months;

  // Sync status tracking
  final Map<String, bool> _syncStatus = {
    'patient_records': false,
    'checkup_records': false,
    'prenatal_records': false,
    'immunization_records': false,
    'morbidity_records': false,
    'mortality_records': false,
    'referrals': false,
  };

  // If a CHO collectionGroup read gets permission-denied, retry once
  // with the root collection query for that module.
  final Map<String, bool> _choRootFallbackEnabled = <String, bool>{};

  StreamSubscription<QuerySnapshot>? _patientsSubscription;
  StreamSubscription<QuerySnapshot>? _checkupSubscription;
  StreamSubscription<QuerySnapshot>? _prenatalSubscription;
  StreamSubscription<QuerySnapshot>? _immunizationSubscription;
  StreamSubscription<QuerySnapshot>? _morbiditySubscription;
  StreamSubscription<QuerySnapshot>? _mortalitySubscription;
  StreamSubscription<QuerySnapshot>? _referralSubscription;
  bool _referralTargetRetryPending = false;
  bool _patientSyncFallbackAttempted = false;
  bool _initialDashboardSyncTriggered = false;
  bool _isRestartingDashboardSync = false;
  bool _roleMirrorResyncTriggered = false;
  UserAccessScope? _accessScope;

  int _totalPatients = 0;
  int _checkupsThisMonth = 0;
  int _activePrenatal = 0;
  int _immunizationRecords = 0;
  int _morbidityReports = 0;
  int _mortalityReports = 0;
  int _referralReports = 0;
  int _referralsSubmitted = 0;
  int _referralsAssigned = 0;
  int _referralsInTreatment = 0;
  int _referralsCompleted = 0;
  List<int> _referralTrendValues = List<int>.filled(6, 0);
  List<String> _referralTrendLabels = const [
    'M1',
    'M2',
    'M3',
    'M4',
    'M5',
    'M6',
  ];
  List<int> _referralBarangayValues = const <int>[];
  List<String> _referralBarangayLabels = const <String>[];
  int _highRiskPatients = 0;
  int _followUpPatients = 0;
  int _coverageNoRecentCheckup = 0;
  int _coverageMissingNextCheckup = 0;
  int _coverageUnknownRisk = 0;
  int _coverageFollowUpNoSchedule = 0;
  List<int> _checkupTrendValues = List<int>.filled(6, 0);
  List<String> _checkupTrendLabels = const ['M1', 'M2', 'M3', 'M4', 'M5', 'M6'];
  List<int> _riskLevelCounts = List<int>.filled(4, 0);
  List<String> _diseaseTrendMonthLabels = const [
    'M1',
    'M2',
    'M3',
    'M4',
    'M5',
    'M6',
  ];
  Map<String, List<int>> _diseaseTrendSeries = const <String, List<int>>{};
  Map<int, int> _checkupForecast = const <int, int>{30: 0, 60: 0, 90: 0};
  Map<int, int> _prenatalForecast = const <int, int>{30: 0, 60: 0, 90: 0};
  Map<int, int> _immunizationForecast = const <int, int>{30: 0, 60: 0, 90: 0};
  DateTime _doctorAvailabilityDate = DateTime.now().add(
    const Duration(days: 1),
  );
  TimeOfDay _doctorAvailabilityTime = const TimeOfDay(hour: 9, minute: 0);
  int _doctorAvailabilityDuration = 60;
  String _doctorSpecialtyFilter = 'All specialties';
  bool _isCheckingDoctorAvailability = false;
  String? _doctorAvailabilityError;
  List<Map<String, dynamic>> _doctorAvailabilityResults =
      <Map<String, dynamic>>[];
  String? _selectedDemographicBarangayCode;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  bool _isChoRole(String role) {
    final roleVal = role.trim().toLowerCase();
    return roleVal == 'cho' ||
        roleVal == 'cho_super_admin' ||
        roleVal == 'super_admin' ||
        roleVal == 'admin';
  }

  void _authorizeAndStart() {
    if (!mounted) return;
    if (!_authorized) {
      setState(() => _authorized = true);
    }
    if (_initialDashboardSyncTriggered) return;
    _initialDashboardSyncTriggered = true;
    unawaited(_startDashboardSync());
  }

  Future<UserAccessScope> _ensureAccessScopeLoaded() async {
    final scope = await UserAccessScopeService.instance.loadCurrentScope(
      forceRefresh: true,
    );
    _accessScope = scope;
    if (kDebugMode) {
      print(
        'Dashboard scope resolved: role=${scope.role}, barangayCode=${scope.barangayCode}, canViewAll=${scope.canViewAllBarangays}',
      );
    }
    return scope;
  }

  Future<void> _ensureFirestoreRoleMirror(User user, String role) async {
    final normalizedRole = role.trim().toUpperCase();
    if (normalizedRole.isEmpty) return;

    try {
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'emailLower': user.email?.trim().toLowerCase(),
        'role': normalizedRole,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      UserAccessScopeService.instance.clearCachedScope(userId: user.uid);
      if (kDebugMode) {
        print(
          'Dashboard access - ensured Firestore role mirror: $normalizedRole',
        );
      }

      // If sync started before role mirror finished, restart once so all
      // collection streams re-open with the latest role state.
      if (_initialDashboardSyncTriggered && !_roleMirrorResyncTriggered) {
        _roleMirrorResyncTriggered = true;
        if (kDebugMode) {
          print(
            'Dashboard access - role mirror updated post-start; restarting dashboard sync once',
          );
        }
        unawaited(_startDashboardSync());
      }
    } catch (e) {
      if (kDebugMode) {
        print('Dashboard access - Firestore role mirror update failed: $e');
      }
    }
  }

  Future<String?> _readRoleFromFirestore(User user) async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        if (kDebugMode) {
          print(
            'Dashboard access - Firestore role check (attempt $attempt/3)...',
          );
        }
        final userDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 15));

        if (!userDoc.exists) {
          if (kDebugMode) {
            print('Dashboard access - user doc not found in Firestore');
          }
          if (attempt < 3) {
            await Future.delayed(Duration(milliseconds: 300 * attempt));
            continue;
          }
          return null;
        }

        final role = (userDoc.data()?['role'] ?? '').toString();
        if (kDebugMode) {
          print('Dashboard access - Firestore role: "$role"');
        }
        return role;
      } catch (e) {
        if (kDebugMode) {
          print(
            'Dashboard access - Firestore check attempt $attempt failed: $e',
          );
        }
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }
      }
    }
    return null;
  }

  Future<String?> _readRoleFromRealtimeDb(User user) async {
    try {
      if (kDebugMode) {
        print('Dashboard access - checking role from Realtime Database...');
      }
      final roleSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid)
          .child('role')
          .get()
          .timeout(const Duration(seconds: 12));
      if (!roleSnapshot.exists || roleSnapshot.value == null) {
        if (kDebugMode) {
          print('Dashboard access - RTDB role not found');
        }
        return null;
      }
      final role = roleSnapshot.value.toString();
      if (kDebugMode) {
        print('Dashboard access - RTDB role: "$role"');
      }
      return role;
    } catch (e) {
      if (kDebugMode) {
        print('Dashboard access - RTDB role check failed: $e');
      }
      return null;
    }
  }

  Future<void> _checkAccess() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Get.snackbar(
          'Access',
          'Please sign in to access the CHO dashboard',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        await Future.delayed(const Duration(milliseconds: 300));
        Get.offAll(() => const Login());
        return;
      }

      // Fast path: role was already validated during login/signup for this UID.
      final args = Get.arguments;
      if (args is Map && args['roleValidated'] == true) {
        final argUid = (args['uid'] ?? '').toString();
        final argRole = (args['role'] ?? '').toString().trim().toLowerCase();
        if ((argUid.isEmpty || argUid == user.uid) && _isChoRole(argRole)) {
          if (kDebugMode) {
            print('Dashboard access granted via trusted route arguments');
          }
          await _ensureFirestoreRoleMirror(user, argRole);
          _authorizeAndStart();
          return;
        }
      }
      // Primary source: Firestore role
      final firestoreRole = await _readRoleFromFirestore(user);
      if (_isChoRole(firestoreRole ?? '')) {
        if (kDebugMode) {
          print('Dashboard access granted via Firestore role: $firestoreRole');
        }
        await _ensureFirestoreRoleMirror(user, firestoreRole!);
        _authorizeAndStart();
        return;
      }

      // Fallback source: Realtime Database role
      final realtimeRole = await _readRoleFromRealtimeDb(user);
      if (_isChoRole(realtimeRole ?? '')) {
        if (kDebugMode) {
          print(
            'Dashboard access granted via Realtime Database role: $realtimeRole',
          );
        }
        await _ensureFirestoreRoleMirror(user, realtimeRole!);
        _authorizeAndStart();
        return;
      }

      // Try custom claims fallback
      try {
        if (kDebugMode) print('Dashboard access - checking custom claims...');
        final idToken = await user
            .getIdTokenResult(true)
            .timeout(const Duration(seconds: 12));
        final claims = idToken.claims ?? {};
        final claimRole = (claims['role'] ?? '').toString().toLowerCase();
        final claimRoles = (claims['roles'] is List)
            ? (claims['roles'] as List)
                  .map((e) => e.toString().toLowerCase())
                  .toList()
            : <String>[];
        if (kDebugMode) {
          print('Dashboard access - custom claims role: "$claimRole"');
        }
        final hasChoClaimRole =
            _isChoRole(claimRole) || claimRoles.any(_isChoRole);
        if (hasChoClaimRole) {
          if (kDebugMode) print('Dashboard access granted via custom claims');
          final resolvedClaimRole = _isChoRole(claimRole)
              ? claimRole
              : claimRoles.firstWhere(_isChoRole, orElse: () => 'cho');
          await _ensureFirestoreRoleMirror(user, resolvedClaimRole);
          _authorizeAndStart();
          return;
        }
      } catch (e) {
        if (kDebugMode) print('⚠ Custom claims check failed: $e');
      }

      if (kDebugMode) {
        print('Dashboard access denied - no valid CHO role found');
      }
      Get.snackbar(
        'Access denied',
        'You need a CHO role to access this dashboard.',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
      ChoAccessSession.trustedUid = null;
      await Future.delayed(const Duration(milliseconds: 500));
      Get.offAll(() => const Login());
    } catch (e) {
      if (kDebugMode) print('Access check error: $e');
      Get.snackbar(
        'Error',
        'Could not verify access: $e',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
      ChoAccessSession.trustedUid = null;
      Get.offAll(() => const Login());
    }
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime? _coerceDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is num) {
      final raw = value.toInt();
      if (raw <= 0) return null;
      final milliseconds = raw > 100000000000 ? raw : raw * 1000;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return null;
      final parsed = DateTime.tryParse(text);
      if (parsed != null) return parsed;

      final ymd = RegExp(
        r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})$',
      ).firstMatch(text);
      if (ymd != null) {
        final year = int.tryParse(ymd.group(1) ?? '');
        final month = int.tryParse(ymd.group(2) ?? '');
        final day = int.tryParse(ymd.group(3) ?? '');
        if (year != null && month != null && day != null) {
          return DateTime(year, month, day);
        }
      }

      final mdy = RegExp(
        r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$',
      ).firstMatch(text);
      if (mdy != null) {
        final month = int.tryParse(mdy.group(1) ?? '');
        final day = int.tryParse(mdy.group(2) ?? '');
        final year = int.tryParse(mdy.group(3) ?? '');
        if (year != null && month != null && day != null) {
          return DateTime(year, month, day);
        }
      }
    }
    return null;
  }

  DateTime? _parseDocDate(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final parsed = _coerceDate(data[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  String _patientName(Map<String, dynamic> row) {
    return (row['patientName'] ??
            row['name'] ??
            row['fullName'] ??
            row['id'] ??
            '-')
        .toString();
  }

  String _patientBarangay(Map<String, dynamic> row) {
    return (row['barangay'] ?? row['addressBarangay'] ?? row['address'] ?? '')
        .toString();
  }

  String _normalizeRiskLabel(String raw) {
    final text = raw.trim().toLowerCase();
    if (text.contains('high')) return 'High';
    if (text.contains('moderate') || text.contains('medium')) return 'Moderate';
    if (text.contains('low')) return 'Low';
    return 'Unknown';
  }

  String _patientRiskLabel(Map<String, dynamic> row) {
    final candidates = <Object?>[
      row['morbidityRiskLevel'],
      row['riskLevel'],
      row['ai_severity'],
      row['status'],
    ];
    for (final candidate in candidates) {
      final raw = candidate?.toString() ?? '';
      final normalized = _normalizeRiskLabel(raw);
      if (normalized != 'Unknown') return normalized;
    }
    return 'Unknown';
  }

  int _riskPriority(String riskLabel) {
    switch (riskLabel.toLowerCase()) {
      case 'high':
        return 3;
      case 'moderate':
        return 2;
      case 'low':
        return 1;
      default:
        return 0;
    }
  }

  bool _isFollowUpStatus(String status) {
    return status.trim().toLowerCase().contains('follow');
  }

  String _dateLabel(DateTime value) {
    final date = _dateOnly(value);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  DateTime? _nextCheckupDate(Map<String, dynamic> row) {
    return _parseDocDate(row, <String>[
      'nextCheckup',
      'nextVisit',
      'followup',
      'followUp',
      'followUpDate',
      'appointmentDate',
      'scheduledDate',
    ]);
  }

  DateTime? _lastCheckupDate(Map<String, dynamic> row) {
    return _parseDocDate(row, <String>[
      'lastVisit',
      'datetime',
      'date',
      'updatedAt',
      'createdAt',
    ]);
  }

  Map<int, int> _countUpcomingByWindow(Iterable<DateTime> dates) {
    final now = _dateOnly(DateTime.now());
    final counts = <int, int>{for (final window in _forecastWindows) window: 0};
    for (final rawDate in dates) {
      final date = _dateOnly(rawDate);
      final diff = date.difference(now).inDays;
      if (diff < 0) continue;
      for (final window in _forecastWindows) {
        if (diff <= window) {
          counts[window] = (counts[window] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  String _monthLabel(int month) {
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

  String _analyticsWindowLabel([_ChoAnalyticsWindow? window]) {
    final dynamic candidate = window ?? _analyticsWindow;
    final resolved = candidate is _ChoAnalyticsWindow
        ? candidate
        : _ChoAnalyticsWindow.last6Months;

    switch (resolved) {
      case _ChoAnalyticsWindow.last30Days:
        return 'Last 30 Days';
      case _ChoAnalyticsWindow.last90Days:
        return 'Last 90 Days';
      case _ChoAnalyticsWindow.last6Months:
        return 'Last 6 Months';
      case _ChoAnalyticsWindow.last12Months:
        return 'Last 12 Months';
    }
  }

  String _analyticsWindowShortLabel(_ChoAnalyticsWindow window) {
    switch (window) {
      case _ChoAnalyticsWindow.last30Days:
        return '30D';
      case _ChoAnalyticsWindow.last90Days:
        return '90D';
      case _ChoAnalyticsWindow.last6Months:
        return '6M';
      case _ChoAnalyticsWindow.last12Months:
        return '12M';
    }
  }

  String _analyticsWindowSupportText(_ChoAnalyticsWindow window) {
    switch (window) {
      case _ChoAnalyticsWindow.last30Days:
        return 'Fast pulse for recent checkups and urgent follow-ups.';
      case _ChoAnalyticsWindow.last90Days:
        return 'Quarter-scale monitoring for service activity and risk shifts.';
      case _ChoAnalyticsWindow.last6Months:
        return 'Balanced planning view for outreach, workload, and trends.';
      case _ChoAnalyticsWindow.last12Months:
        return 'Long-range annual review for broader program direction.';
    }
  }

  IconData _analyticsWindowIcon(_ChoAnalyticsWindow window) {
    switch (window) {
      case _ChoAnalyticsWindow.last30Days:
        return Icons.bolt_rounded;
      case _ChoAnalyticsWindow.last90Days:
        return Icons.query_stats_rounded;
      case _ChoAnalyticsWindow.last6Months:
        return Icons.timeline_rounded;
      case _ChoAnalyticsWindow.last12Months:
        return Icons.stacked_line_chart_rounded;
    }
  }

  DateTime _monthStart(DateTime value) => DateTime(value.year, value.month, 1);

  DateTime _addMonths(DateTime value, int delta) {
    final totalMonths = value.year * 12 + (value.month - 1) + delta;
    final year = totalMonths ~/ 12;
    final month = totalMonths % 12 + 1;
    return DateTime(year, month, 1);
  }

  DateTime _analyticsWindowStart(DateTime now) {
    final today = _dateOnly(now);
    switch (_analyticsWindow) {
      case _ChoAnalyticsWindow.last30Days:
        return today.subtract(const Duration(days: 29));
      case _ChoAnalyticsWindow.last90Days:
        return today.subtract(const Duration(days: 89));
      case _ChoAnalyticsWindow.last6Months:
        return _addMonths(_monthStart(today), -5);
      case _ChoAnalyticsWindow.last12Months:
        return _addMonths(_monthStart(today), -11);
    }
  }

  List<DateTime> _analyticsMonthStarts(DateTime now) {
    final startMonth = _monthStart(_analyticsWindowStart(now));
    final endMonth = _monthStart(now);
    final months = <DateTime>[];
    var cursor = startMonth;
    while (!cursor.isAfter(endMonth)) {
      months.add(cursor);
      cursor = _addMonths(cursor, 1);
    }
    return months;
  }

  bool _isWithinAnalyticsWindow(DateTime? value, DateTime start) {
    if (value == null) return false;
    return !_dateOnly(value).isBefore(start);
  }

  DateTime? _patientAnalyticsDate(Map<String, dynamic> row) {
    return _lastCheckupDate(row) ??
        _nextCheckupDate(row) ??
        _parseDocDate(row, <String>[
          'updatedAt',
          'createdAt',
          'registrationDate',
          'date',
        ]);
  }

  bool _matchesPatientAnalyticsWindow(
    Map<String, dynamic> row,
    DateTime start,
  ) {
    final referenceDate = _patientAnalyticsDate(row);
    if (referenceDate == null) return true;
    return _isWithinAnalyticsWindow(referenceDate, start);
  }

  DateTime? _checkupRecordDate(Map<String, dynamic> row) {
    return _parseDocDate(row, <String>[
      'datetime',
      'date',
      'createdAt',
      'lastVisit',
    ]);
  }

  DateTime? _prenatalRecordDate(Map<String, dynamic> row) {
    return _parseDocDate(row, <String>[
      'registrationDate',
      'createdAt',
      'updatedAt',
      'appointmentDate',
      'nextVisit',
      'date',
    ]);
  }

  DateTime? _immunizationRecordDate(Map<String, dynamic> row) {
    return _parseDocDate(row, <String>[
      'administrationDate',
      'date',
      'createdAt',
      'updatedAt',
      'nextDoseDueDate',
    ]);
  }

  DateTime? _morbidityRecordDate(Map<String, dynamic> row) {
    return _parseDocDate(row, <String>[
      'dateReported',
      'date',
      'createdAt',
      'datetime',
    ]);
  }

  DateTime? _mortalityRecordDate(Map<String, dynamic> row) {
    return _parseDocDate(row, <String>[
      'dateReported',
      'dateOfDeath',
      'date',
      'createdAt',
      'datetime',
    ]);
  }

  DateTime? _referralRecordDate(Map<String, dynamic> row) {
    return _parseDocDate(row, <String>[
      'referralDateTime',
      'createdAt',
      'updatedAt',
      'assignedAt',
      'date',
    ]);
  }

  void _recomputeAnalyticsState() {
    final now = DateTime.now();
    final today = _dateOnly(now);
    final analyticsStart = _analyticsWindowStart(now);
    final monthStarts = _analyticsMonthStarts(now);
    final monthKeys = monthStarts
        .map((d) => '${d.year}-${d.month.toString().padLeft(2, '0')}')
        .toList(growable: false);
    final monthLabels = monthStarts
        .map((d) => _monthLabel(d.month))
        .toList(growable: false);

    int highRisk = 0;
    int moderateRisk = 0;
    int lowRisk = 0;
    int unknownRisk = 0;
    int followUp = 0;
    int noRecentCheckup = 0;
    int missingNextCheckup = 0;
    int unknownRiskCoverage = 0;
    int followUpNoSchedule = 0;
    final upcomingCheckups = <DateTime>[];
    final overdueQueue = <Map<String, dynamic>>[];

    final filteredPatientRows = _rows
        .where((row) => _matchesPatientAnalyticsWindow(row, analyticsStart))
        .toList(growable: false);

    for (final row in filteredPatientRows) {
      final riskLabel = _patientRiskLabel(row);
      final riskPriority = _riskPriority(riskLabel);
      final status = (row['status'] ?? '').toString();
      final isFollowUp = _isFollowUpStatus(status);
      final lastCheckupDate = _lastCheckupDate(row);
      final nextCheckupDate = _nextCheckupDate(row);

      if (riskLabel == 'High') {
        highRisk++;
      } else if (riskLabel == 'Moderate') {
        moderateRisk++;
      } else if (riskLabel == 'Low') {
        lowRisk++;
      } else {
        unknownRisk++;
      }

      if (isFollowUp) followUp++;
      if (riskLabel == 'Unknown') unknownRiskCoverage++;

      if (lastCheckupDate == null ||
          today.difference(_dateOnly(lastCheckupDate)).inDays > 90) {
        noRecentCheckup++;
      }

      if (nextCheckupDate == null) {
        missingNextCheckup++;
        if (isFollowUp) followUpNoSchedule++;
      } else {
        upcomingCheckups.add(nextCheckupDate);
        final overdueDays = today.difference(_dateOnly(nextCheckupDate)).inDays;
        if (overdueDays > 0 && (isFollowUp || riskPriority >= 3)) {
          overdueQueue.add(<String, dynamic>{
            'name': _patientName(row),
            'nextDate': nextCheckupDate,
            'nextDateLabel': _dateLabel(nextCheckupDate),
            'overdueDays': overdueDays,
            'riskLabel': riskLabel,
            'riskPriority': riskPriority,
            'status': status,
          });
        }
      }
    }

    overdueQueue.sort((a, b) {
      final riskCompare = (b['riskPriority'] as int).compareTo(
        a['riskPriority'] as int,
      );
      if (riskCompare != 0) return riskCompare;
      final overdueCompare = (a['overdueDays'] as int).compareTo(
        b['overdueDays'] as int,
      );
      if (overdueCompare != 0) return overdueCompare;
      final aName = (a['name'] ?? '').toString().toLowerCase();
      final bName = (b['name'] ?? '').toString().toLowerCase();
      return aName.compareTo(bName);
    });

    final checkupMonthCounts = <String, int>{
      for (final key in monthKeys) key: 0,
    };
    int checkupCount = 0;
    for (final row in _checkupRows) {
      final date = _checkupRecordDate(row);
      if (!_isWithinAnalyticsWindow(date, analyticsStart)) continue;
      checkupCount++;
      final key = '${date!.year}-${date.month.toString().padLeft(2, '0')}';
      if (checkupMonthCounts.containsKey(key)) {
        checkupMonthCounts[key] = (checkupMonthCounts[key] ?? 0) + 1;
      }
    }

    int activePrenatal = 0;
    final upcomingPrenatal = <DateTime>[];
    for (final row in _prenatalRows) {
      final recordDate = _prenatalRecordDate(row);
      if (!_isWithinAnalyticsWindow(recordDate, analyticsStart)) continue;
      final status = (row['status'] ?? '').toString().toLowerCase();
      if (status.contains('active')) activePrenatal++;
      final dueDate = _parseDocDate(row, <String>[
        'dueDate',
        'nextVisit',
        'nextCheckup',
        'followup',
        'appointmentDate',
      ]);
      if (dueDate != null) upcomingPrenatal.add(dueDate);
    }

    int immunizationCount = 0;
    final upcomingImmunizations = <DateTime>[];
    for (final row in _immunizationRows) {
      final recordDate = _immunizationRecordDate(row);
      if (!_isWithinAnalyticsWindow(recordDate, analyticsStart)) continue;
      immunizationCount++;
      final dueDate = _parseDocDate(row, <String>[
        'nextDoseDueDate',
        'dueDate',
        'nextVisit',
        'followup',
        'appointmentDate',
      ]);
      if (dueDate != null) upcomingImmunizations.add(dueDate);
    }

    final diseaseTotals = <String, int>{};
    final monthlyDiseaseCounts = <String, Map<String, int>>{};
    int morbidityCount = 0;
    for (final row in _morbidityRows) {
      final date = _morbidityRecordDate(row);
      if (!_isWithinAnalyticsWindow(date, analyticsStart)) continue;
      morbidityCount++;
      final diseaseRaw =
          (row['disease'] ?? row['diagnosis'] ?? row['condition'] ?? '')
              .toString()
              .trim();
      final disease = diseaseRaw.isEmpty ? 'Unknown' : diseaseRaw;
      final monthKey = '${date!.year}-${date.month.toString().padLeft(2, '0')}';
      if (!monthKeys.contains(monthKey)) continue;

      final diseaseMonthCounts = monthlyDiseaseCounts.putIfAbsent(
        disease,
        () => <String, int>{for (final key in monthKeys) key: 0},
      );
      diseaseMonthCounts[monthKey] = (diseaseMonthCounts[monthKey] ?? 0) + 1;
      diseaseTotals[disease] = (diseaseTotals[disease] ?? 0) + 1;
    }

    final topDiseases = diseaseTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final selectedDiseases = topDiseases
        .take(3)
        .map((entry) => entry.key)
        .toList(growable: false);
    final trendSeries = <String, List<int>>{};
    for (final disease in selectedDiseases) {
      final countsPerMonth = monthlyDiseaseCounts[disease] ?? <String, int>{};
      trendSeries[disease] = monthKeys
          .map((key) => countsPerMonth[key] ?? 0)
          .toList(growable: false);
    }

    int mortalityCount = 0;
    for (final row in _mortalityRows) {
      final date = _mortalityRecordDate(row);
      if (_isWithinAnalyticsWindow(date, analyticsStart)) {
        mortalityCount++;
      }
    }

    final referralMonthCounts = <String, int>{
      for (final key in monthKeys) key: 0,
    };
    final referralBarangayCounts = <String, int>{};
    int referralCount = 0;
    int referralsSubmitted = 0;
    int referralsAssigned = 0;
    int referralsInTreatment = 0;
    int referralsCompleted = 0;
    for (final row in _referralRows) {
      final date = _referralRecordDate(row);
      if (!_isWithinAnalyticsWindow(date, analyticsStart)) continue;
      referralCount++;

      final key = '${date!.year}-${date.month.toString().padLeft(2, '0')}';
      if (referralMonthCounts.containsKey(key)) {
        referralMonthCounts[key] = (referralMonthCounts[key] ?? 0) + 1;
      }

      final barangay = (row['barangay'] ?? 'Unassigned barangay')
          .toString()
          .trim();
      final barangayKey = barangay.isEmpty ? 'Unassigned barangay' : barangay;
      referralBarangayCounts[barangayKey] =
          (referralBarangayCounts[barangayKey] ?? 0) + 1;

      final status = (row['status'] ?? 'submitted').toString().toLowerCase();
      if (status == 'assigned') {
        referralsAssigned++;
      } else if (status == 'in_treatment') {
        referralsInTreatment++;
      } else if (status == 'completed') {
        referralsCompleted++;
      } else {
        // Includes submitted and under_review statuses.
        referralsSubmitted++;
      }
    }

    final topReferralBarangays = referralBarangayCounts.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) {
          return countCompare;
        }
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });
    final referralBarangayLabels = topReferralBarangays
        .take(6)
        .map((entry) => entry.key)
        .toList(growable: false);
    final referralBarangayValues = topReferralBarangays
        .take(6)
        .map((entry) => entry.value)
        .toList(growable: false);

    _overdueFollowUps
      ..clear()
      ..addAll(overdueQueue.take(10));
    _totalPatients = filteredPatientRows.length;
    _highRiskPatients = highRisk;
    _followUpPatients = followUp;
    _coverageNoRecentCheckup = noRecentCheckup;
    _coverageMissingNextCheckup = missingNextCheckup;
    _coverageUnknownRisk = unknownRiskCoverage;
    _coverageFollowUpNoSchedule = followUpNoSchedule;
    _riskLevelCounts = <int>[highRisk, moderateRisk, lowRisk, unknownRisk];
    _checkupForecast = _countUpcomingByWindow(upcomingCheckups);
    _checkupsThisMonth = checkupCount;
    _checkupTrendLabels = monthLabels;
    _checkupTrendValues = monthKeys
        .map((key) => checkupMonthCounts[key] ?? 0)
        .toList(growable: false);
    _activePrenatal = activePrenatal;
    _prenatalForecast = _countUpcomingByWindow(upcomingPrenatal);
    _immunizationRecords = immunizationCount;
    _immunizationForecast = _countUpcomingByWindow(upcomingImmunizations);
    _morbidityReports = morbidityCount;
    _diseaseTrendMonthLabels = monthLabels;
    _diseaseTrendSeries = trendSeries;
    _mortalityReports = mortalityCount;
    _referralReports = referralCount;
    _referralsSubmitted = referralsSubmitted;
    _referralsAssigned = referralsAssigned;
    _referralsInTreatment = referralsInTreatment;
    _referralsCompleted = referralsCompleted;
    _referralTrendLabels = monthLabels;
    _referralTrendValues = monthKeys
        .map((key) => referralMonthCounts[key] ?? 0)
        .toList(growable: false);
    _referralBarangayLabels = referralBarangayLabels;
    _referralBarangayValues = referralBarangayValues;
  }

  bool _isWholeAxisTick(double value) {
    return (value - value.roundToDouble()).abs() < 0.001;
  }

  void _markSyncPending() {
    if (!mounted) return;
    setState(() {
      _syncStatus.updateAll((_, _) => false);
      _isLoading = true;
    });
  }

  Future<void> _cancelQuerySubscription(
    StreamSubscription<QuerySnapshot>? subscription,
  ) async {
    if (subscription == null) return;
    try {
      await subscription.cancel();
    } catch (e) {
      if (kDebugMode) {
        print('Stream cancel warning: $e');
      }
    }
  }

  Future<void> _cancelAllSyncSubscriptions() async {
    final patientsSubscription = _patientsSubscription;
    final checkupSubscription = _checkupSubscription;
    final prenatalSubscription = _prenatalSubscription;
    final immunizationSubscription = _immunizationSubscription;
    final morbiditySubscription = _morbiditySubscription;
    final mortalitySubscription = _mortalitySubscription;
    final referralSubscription = _referralSubscription;

    _patientsSubscription = null;
    _checkupSubscription = null;
    _prenatalSubscription = null;
    _immunizationSubscription = null;
    _morbiditySubscription = null;
    _mortalitySubscription = null;
    _referralSubscription = null;

    await _cancelQuerySubscription(patientsSubscription);
    await _cancelQuerySubscription(checkupSubscription);
    await _cancelQuerySubscription(prenatalSubscription);
    await _cancelQuerySubscription(immunizationSubscription);
    await _cancelQuerySubscription(morbiditySubscription);
    await _cancelQuerySubscription(mortalitySubscription);
    await _cancelQuerySubscription(referralSubscription);
  }

  Future<void> _startDashboardSync() async {
    if (_isRestartingDashboardSync) return;
    _isRestartingDashboardSync = true;
    try {
      await _ensureAccessScopeLoaded();
      _markSyncPending();
      await _cancelAllSyncSubscriptions();
      if (!mounted) return;
      if (kDebugMode) print('Starting CHO dashboard sync...');
      await _startPatientsSync();
      await _startCheckupSync();
      await _startPrenatalSync();
      await _startImmunizationSync();
      await _startMorbiditySync();
      await _startMortalitySync();
      await _startReferralSync();
    } finally {
      _isRestartingDashboardSync = false;
    }
  }

  void _refreshSync() {
    _choRootFallbackEnabled.clear();
    Get.snackbar(
      'Sync',
      'Refreshing dashboard data...',
      backgroundColor: _primaryAqua,
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
    );
    unawaited(_startDashboardSync());
  }

  Query<Map<String, dynamic>> _buildModuleQuery(
    String collectionName,
    UserAccessScope accessScope,
  ) {
    final useRootFallback =
        accessScope.canViewAllBarangays &&
        (_choRootFallbackEnabled[collectionName] ?? false);

    if (useRootFallback) {
      return _firestore.collection(collectionName);
    }

    return buildScopedRecordQuery(_firestore, collectionName, accessScope);
  }

  bool _activateChoRootFallbackIfNeeded(
    String collectionName,
    Object error,
    UserAccessScope accessScope,
  ) {
    if (!accessScope.canViewAllBarangays) {
      return false;
    }

    final normalizedError = error.toString().toLowerCase();
    if (!normalizedError.contains('permission-denied')) {
      return false;
    }

    if (_choRootFallbackEnabled[collectionName] == true) {
      return false;
    }

    _choRootFallbackEnabled[collectionName] = true;
    if (kDebugMode) {
      print(
        'CHO fallback enabled for $collectionName: retrying with root collection query',
      );
    }
    return true;
  }

  Future<void> _startPatientsSync({bool resetFallback = true}) async {
    final existingSubscription = _patientsSubscription;
    _patientsSubscription = null;
    await _cancelQuerySubscription(existingSubscription);
    if (!mounted) return;
    if (resetFallback) _patientSyncFallbackAttempted = false;
    setState(() {
      _isLoading = true;
      _syncStatus['patient_records'] = false;
    });
    if (kDebugMode) print('Syncing patient records...');

    final accessScope = _accessScope ?? await _ensureAccessScopeLoaded();
    Query<Map<String, dynamic>> patientQuery = _buildModuleQuery(
      'patient_records',
      accessScope,
    );
    if (!_patientSyncFallbackAttempted) {
      patientQuery = patientQuery.orderBy('createdAt', descending: true);
    }

    _patientsSubscription = patientQuery
        .limit(500)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            int highRisk = 0;
            int moderateRisk = 0;
            int lowRisk = 0;
            int unknownRisk = 0;
            int followUp = 0;
            final today = _dateOnly(DateTime.now());
            int noRecentCheckup = 0;
            int missingNextCheckup = 0;
            int unknownRiskCoverage = 0;
            int followUpNoSchedule = 0;

            final upcomingCheckups = <DateTime>[];
            final overdueQueue = <Map<String, dynamic>>[];

            final rows = snap.docs
                .map((d) => {'id': d.id, ...(d.data())})
                .toList(growable: false);

            for (final row in rows) {
              final riskLabel = _patientRiskLabel(row);
              final riskPriority = _riskPriority(riskLabel);
              final status = (row['status'] ?? '').toString();
              final isFollowUp = _isFollowUpStatus(status);
              final lastCheckupDate = _lastCheckupDate(row);
              final nextCheckupDate = _nextCheckupDate(row);

              if (riskLabel == 'High') {
                highRisk++;
              } else if (riskLabel == 'Moderate') {
                moderateRisk++;
              } else if (riskLabel == 'Low') {
                lowRisk++;
              } else {
                unknownRisk++;
              }

              if (isFollowUp) followUp++;
              if (riskLabel == 'Unknown') unknownRiskCoverage++;

              if (lastCheckupDate == null ||
                  today.difference(_dateOnly(lastCheckupDate)).inDays > 90) {
                noRecentCheckup++;
              }

              if (nextCheckupDate == null) {
                missingNextCheckup++;
                if (isFollowUp) followUpNoSchedule++;
              } else {
                upcomingCheckups.add(nextCheckupDate);
                final overdueDays = today
                    .difference(_dateOnly(nextCheckupDate))
                    .inDays;
                if (overdueDays > 0 && (isFollowUp || riskPriority >= 3)) {
                  overdueQueue.add(<String, dynamic>{
                    'name': _patientName(row),
                    'nextDate': nextCheckupDate,
                    'nextDateLabel': _dateLabel(nextCheckupDate),
                    'overdueDays': overdueDays,
                    'riskLabel': riskLabel,
                    'riskPriority': riskPriority,
                    'status': status,
                  });
                }
              }
            }

            overdueQueue.sort((a, b) {
              final riskCompare = (b['riskPriority'] as int).compareTo(
                a['riskPriority'] as int,
              );
              if (riskCompare != 0) return riskCompare;
              final overdueCompare = (a['overdueDays'] as int).compareTo(
                b['overdueDays'] as int,
              );
              if (overdueCompare != 0) return overdueCompare;
              final aName = (a['name'] ?? '').toString().toLowerCase();
              final bName = (b['name'] ?? '').toString().toLowerCase();
              return aName.compareTo(bName);
            });

            if (kDebugMode) print('✓ Synced ${rows.length} patient records');
            setState(() {
              _rows
                ..clear()
                ..addAll(rows);
              _overdueFollowUps
                ..clear()
                ..addAll(overdueQueue.take(10));
              _totalPatients = rows.length;
              _highRiskPatients = highRisk;
              _followUpPatients = followUp;
              _coverageNoRecentCheckup = noRecentCheckup;
              _coverageMissingNextCheckup = missingNextCheckup;
              _coverageUnknownRisk = unknownRiskCoverage;
              _coverageFollowUpNoSchedule = followUpNoSchedule;
              _riskLevelCounts = <int>[
                highRisk,
                moderateRisk,
                lowRisk,
                unknownRisk,
              ];
              _checkupForecast = _countUpcomingByWindow(upcomingCheckups);
              _isLoading = false;
              _syncStatus['patient_records'] = true;
              _recomputeAnalyticsState();
            });
          },
          onError: (e) {
            if (!mounted) return;
            if (kDebugMode) print('✗ Patient sync error: $e');
            if (!_patientSyncFallbackAttempted) {
              _patientSyncFallbackAttempted = true;
              if (kDebugMode) {
                print(
                  'Primary patient Firestore sync failed; retrying without createdAt sort: $e',
                );
              }
              unawaited(_startPatientsSync(resetFallback: false));
              return;
            }

            if (_activateChoRootFallbackIfNeeded(
              'patient_records',
              e,
              accessScope,
            )) {
              unawaited(_startPatientsSync(resetFallback: false));
              return;
            }

            setState(() {
              _isLoading = false;
              _syncStatus['patient_records'] = false;
            });
            Get.snackbar(
              'Sync error',
              'Could not sync patient records from Firestore: $e',
              backgroundColor: Colors.redAccent,
              colorText: Colors.white,
              duration: const Duration(seconds: 5),
            );
          },
        );
  }

  Future<void> _startCheckupSync() async {
    final existingSubscription = _checkupSubscription;
    _checkupSubscription = null;
    await _cancelQuerySubscription(existingSubscription);
    if (!mounted) return;
    if (kDebugMode) print('Syncing checkup records...');
    final accessScope = _accessScope ?? await _ensureAccessScopeLoaded();
    _checkupSubscription = _buildModuleQuery('checkup_records', accessScope)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            final rows = snap.docs
                .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
                .toList(growable: false);
            final now = DateTime.now();
            final monthStart = DateTime(now.year, now.month, 1);
            final monthStarts = <DateTime>[];
            for (int i = 5; i >= 0; i--) {
              final month = now.month - i;
              final year = now.year + (month > 0 ? 0 : -1);
              final adjustedMonth = month > 0 ? month : month + 12;
              monthStarts.add(DateTime(year, adjustedMonth, 1));
            }
            final monthKeys = monthStarts
                .map((d) => '${d.year}-${d.month.toString().padLeft(2, '0')}')
                .toList(growable: false);
            final monthLabels = monthStarts
                .map((d) => _monthLabel(d.month))
                .toList(growable: false);
            final monthCounts = <String, int>{
              for (final key in monthKeys) key: 0,
            };
            int total = 0;
            for (final d in snap.docs) {
              final data = d.data();
              final date = _parseDocDate(data, [
                'datetime',
                'date',
                'createdAt',
                'lastVisit',
              ]);
              if (date != null && !date.isBefore(monthStart)) total++;
              if (date != null) {
                final key =
                    '${date.year}-${date.month.toString().padLeft(2, '0')}';
                if (monthCounts.containsKey(key)) {
                  monthCounts[key] = (monthCounts[key] ?? 0) + 1;
                }
              }
            }
            if (kDebugMode) {
              print(
                '✓ Synced ${snap.docs.length} checkup records ($total this month)',
              );
            }
            setState(() {
              _checkupRows
                ..clear()
                ..addAll(rows);
              _checkupsThisMonth = total;
              _checkupTrendLabels = monthLabels;
              _checkupTrendValues = monthKeys
                  .map((key) => monthCounts[key] ?? 0)
                  .toList(growable: false);
              _syncStatus['checkup_records'] = true;
              _recomputeAnalyticsState();
            });
          },
          onError: (e) {
            if (kDebugMode) print('✗ Checkup sync error: $e');
            if (!mounted) return;
            if (_activateChoRootFallbackIfNeeded(
              'checkup_records',
              e,
              accessScope,
            )) {
              unawaited(_startCheckupSync());
              return;
            }
            setState(() => _syncStatus['checkup_records'] = false);
          },
        );
  }

  Future<void> _startPrenatalSync() async {
    final existingSubscription = _prenatalSubscription;
    _prenatalSubscription = null;
    await _cancelQuerySubscription(existingSubscription);
    if (!mounted) return;
    if (kDebugMode) print('Syncing prenatal records...');
    final accessScope = _accessScope ?? await _ensureAccessScopeLoaded();
    _prenatalSubscription = _buildModuleQuery('prenatal_records', accessScope)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            final rows = snap.docs
                .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
                .toList(growable: false);
            int active = 0;
            final upcomingPrenatal = <DateTime>[];
            for (final d in snap.docs) {
              final data = d.data();
              final status = (data['status'] ?? '').toString().toLowerCase();
              if (status.contains('active')) active++;
              final dueDate = _parseDocDate(data, <String>[
                'dueDate',
                'nextVisit',
                'nextCheckup',
                'followup',
                'appointmentDate',
              ]);
              if (dueDate != null) upcomingPrenatal.add(dueDate);
            }
            if (kDebugMode) {
              print(
                '✓ Synced ${snap.docs.length} prenatal records ($active active)',
              );
            }
            setState(() {
              _prenatalRows
                ..clear()
                ..addAll(rows);
              _activePrenatal = active;
              _prenatalForecast = _countUpcomingByWindow(upcomingPrenatal);
              _syncStatus['prenatal_records'] = true;
              _recomputeAnalyticsState();
            });
          },
          onError: (e) {
            if (kDebugMode) print('✗ Prenatal sync error: $e');
            if (!mounted) return;
            if (_activateChoRootFallbackIfNeeded(
              'prenatal_records',
              e,
              accessScope,
            )) {
              unawaited(_startPrenatalSync());
              return;
            }
            setState(() => _syncStatus['prenatal_records'] = false);
          },
        );
  }

  Future<void> _startImmunizationSync() async {
    final existingSubscription = _immunizationSubscription;
    _immunizationSubscription = null;
    await _cancelQuerySubscription(existingSubscription);
    if (!mounted) return;
    if (kDebugMode) print('Syncing immunization records...');
    final accessScope = _accessScope ?? await _ensureAccessScopeLoaded();
    _immunizationSubscription =
        _buildModuleQuery(
          'immunization_records',
          accessScope,
        ).snapshots().listen(
          (snap) {
            if (!mounted) return;
            final rows = snap.docs
                .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
                .toList(growable: false);
            final upcomingImmunizations = <DateTime>[];
            for (final d in snap.docs) {
              final data = d.data();
              final dueDate = _parseDocDate(data, <String>[
                'nextDoseDueDate',
                'dueDate',
                'nextVisit',
                'followup',
                'appointmentDate',
              ]);
              if (dueDate != null) upcomingImmunizations.add(dueDate);
            }
            if (kDebugMode) {
              print('✓ Synced ${snap.docs.length} immunization records');
            }
            setState(() {
              _immunizationRows
                ..clear()
                ..addAll(rows);
              _immunizationRecords = snap.docs.length;
              _immunizationForecast = _countUpcomingByWindow(
                upcomingImmunizations,
              );
              _syncStatus['immunization_records'] = true;
              _recomputeAnalyticsState();
            });
          },
          onError: (e) {
            if (kDebugMode) print('✗ Immunization sync error: $e');
            if (!mounted) return;
            if (_activateChoRootFallbackIfNeeded(
              'immunization_records',
              e,
              accessScope,
            )) {
              unawaited(_startImmunizationSync());
              return;
            }
            setState(() => _syncStatus['immunization_records'] = false);
          },
        );
  }

  Future<void> _startMorbiditySync() async {
    final existingSubscription = _morbiditySubscription;
    _morbiditySubscription = null;
    await _cancelQuerySubscription(existingSubscription);
    if (!mounted) return;
    if (kDebugMode) print('Syncing morbidity records...');
    final accessScope = _accessScope ?? await _ensureAccessScopeLoaded();
    _morbiditySubscription = _buildModuleQuery('morbidity_records', accessScope)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            final rows = snap.docs
                .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
                .toList(growable: false);
            final now = DateTime.now();
            final monthStarts = <DateTime>[];
            for (int i = 5; i >= 0; i--) {
              final month = now.month - i;
              final year = now.year + (month > 0 ? 0 : -1);
              final adjustedMonth = month > 0 ? month : month + 12;
              monthStarts.add(DateTime(year, adjustedMonth, 1));
            }
            final monthKeys = monthStarts
                .map((d) => '${d.year}-${d.month.toString().padLeft(2, '0')}')
                .toList(growable: false);
            final monthLabels = monthStarts
                .map((d) => _monthLabel(d.month))
                .toList(growable: false);

            final diseaseTotals = <String, int>{};
            final monthlyDiseaseCounts = <String, Map<String, int>>{};

            for (final d in snap.docs) {
              final data = d.data();
              final diseaseRaw =
                  (data['disease'] ??
                          data['diagnosis'] ??
                          data['condition'] ??
                          '')
                      .toString()
                      .trim();
              final disease = diseaseRaw.isEmpty ? 'Unknown' : diseaseRaw;
              final date = _parseDocDate(data, [
                'dateReported',
                'date',
                'createdAt',
                'datetime',
              ]);
              if (date == null) continue;

              final monthKey =
                  '${date.year}-${date.month.toString().padLeft(2, '0')}';
              if (!monthKeys.contains(monthKey)) continue;

              final diseaseMonthCounts = monthlyDiseaseCounts.putIfAbsent(
                disease,
                () => <String, int>{for (final key in monthKeys) key: 0},
              );
              diseaseMonthCounts[monthKey] =
                  (diseaseMonthCounts[monthKey] ?? 0) + 1;
              diseaseTotals[disease] = (diseaseTotals[disease] ?? 0) + 1;
            }

            final topDiseases = diseaseTotals.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final selectedDiseases = topDiseases
                .take(3)
                .map((entry) => entry.key)
                .toList(growable: false);

            final trendSeries = <String, List<int>>{};
            for (final disease in selectedDiseases) {
              final countsPerMonth =
                  monthlyDiseaseCounts[disease] ?? <String, int>{};
              trendSeries[disease] = monthKeys
                  .map((key) => countsPerMonth[key] ?? 0)
                  .toList(growable: false);
            }

            if (kDebugMode) {
              print('✓ Synced ${snap.docs.length} morbidity records');
            }
            setState(() {
              _morbidityRows
                ..clear()
                ..addAll(rows);
              _morbidityReports = snap.docs.length;
              _diseaseTrendMonthLabels = monthLabels;
              _diseaseTrendSeries = trendSeries;
              _syncStatus['morbidity_records'] = true;
              _recomputeAnalyticsState();
            });
          },
          onError: (e) {
            if (kDebugMode) print('✗ Morbidity sync error: $e');
            if (!mounted) return;
            if (_activateChoRootFallbackIfNeeded(
              'morbidity_records',
              e,
              accessScope,
            )) {
              unawaited(_startMorbiditySync());
              return;
            }
            setState(() => _syncStatus['morbidity_records'] = false);
          },
        );
  }

  Future<void> _startMortalitySync() async {
    final existingSubscription = _mortalitySubscription;
    _mortalitySubscription = null;
    await _cancelQuerySubscription(existingSubscription);
    if (!mounted) return;
    if (kDebugMode) print('Syncing mortality records...');
    final accessScope = _accessScope ?? await _ensureAccessScopeLoaded();
    _mortalitySubscription = _buildModuleQuery('mortality_records', accessScope)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            if (kDebugMode) {
              print('✓ Synced ${snap.docs.length} mortality records');
            }
            setState(() {
              _mortalityRows
                ..clear()
                ..addAll(
                  snap.docs
                      .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
                      .toList(growable: false),
                );
              _mortalityReports = snap.docs.length;
              _syncStatus['mortality_records'] = true;
              _recomputeAnalyticsState();
            });
          },
          onError: (e) {
            if (kDebugMode) print('✗ Mortality sync error: $e');
            if (!mounted) return;
            if (_activateChoRootFallbackIfNeeded(
              'mortality_records',
              e,
              accessScope,
            )) {
              unawaited(_startMortalitySync());
              return;
            }
            setState(() => _syncStatus['mortality_records'] = false);
          },
        );
  }

  Future<void> _startReferralSync() async {
    final existingSubscription = _referralSubscription;
    _referralSubscription = null;
    await _cancelQuerySubscription(existingSubscription);
    if (!mounted) return;
    if (kDebugMode) print('Syncing referrals...');
    _referralSubscription = _firestore
        .collection('referrals')
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            final rows = snap.docs
                .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
                .toList(growable: false);
            if (kDebugMode) print('✓ Synced ${snap.docs.length} referrals');
            setState(() {
              _referralRows
                ..clear()
                ..addAll(rows);
              _syncStatus['referrals'] = true;
              _recomputeAnalyticsState();
            });
          },
          onError: (e) {
            final normalizedError = e.toString().toLowerCase();
            if (normalizedError.contains('already-exists') &&
                !_referralTargetRetryPending) {
              _referralTargetRetryPending = true;
              if (kDebugMode) {
                print(
                  'Referral sync target conflict detected; restarting listener...',
                );
              }
              Future<void>.delayed(const Duration(milliseconds: 300), () {
                _referralTargetRetryPending = false;
                if (mounted) {
                  unawaited(_startReferralSync());
                }
              });
              return;
            }
            if (kDebugMode) print('✗ Referral sync error: $e');
            if (!mounted) return;
            setState(() => _syncStatus['referrals'] = false);
          },
        );
  }

  @override
  void dispose() {
    unawaited(_cancelAllSyncSubscriptions());
    super.dispose();
  }

  void _exportCsv() {
    if (_rows.isEmpty) {
      Get.snackbar(
        'No data',
        'No rows to export',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    final headers = _rows.first.keys.toList();
    final csvBuffer = StringBuffer();
    csvBuffer.writeln(headers.join(','));
    for (final r in _rows) {
      final line = headers
          .map((h) => HtmlEscape().convert('${r[h] ?? ''}'))
          .join(',');
      csvBuffer.writeln(line);
    }

    final bytes = const Utf8Encoder().convert(csvBuffer.toString());
    final exported = downloadCsvFile(
      bytes: bytes,
      filename: 'cho_export_${DateTime.now().toIso8601String()}.csv',
    );
    if (!exported) {
      Get.snackbar(
        'Export unavailable',
        'CSV export is only supported in the web dashboard.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
    }
  }

  String _doctorName(Map<String, dynamic> doctor) {
    return (doctor['fullName'] ??
            doctor['username'] ??
            doctor['displayName'] ??
            doctor['email'] ??
            'Doctor')
        .toString()
        .trim();
  }

  String _doctorSpecialty(Map<String, dynamic> doctor) {
    final value =
        (doctor['specialization'] ??
                doctor['doctorSpecialization'] ??
                doctor['specialty'] ??
                'General Medicine')
            .toString()
            .trim();
    return value.isEmpty ? 'General Medicine' : value;
  }

  String _doctorDirectoryKey(Map<String, dynamic> doctor) {
    final uid = (doctor['userUid'] ?? doctor['uid'] ?? '').toString().trim();
    if (uid.isNotEmpty) return 'uid:${uid.toLowerCase()}';
    final email = (doctor['emailLower'] ?? doctor['email'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (email.isNotEmpty) return 'email:$email';
    return 'name:${_doctorName(doctor).toLowerCase()}';
  }

  bool _doctorIsArchived(Map<String, dynamic> doctor) {
    final status = (doctor['accountStatus'] ?? '').toString().toLowerCase();
    return doctor['isArchived'] == true || status == 'archived';
  }

  String _doctorStatus(Map<String, dynamic> doctor) {
    final value =
        (doctor['availability'] ??
                doctor['doctorAvailability'] ??
                doctor['status'] ??
                'available')
            .toString()
            .trim()
            .toLowerCase();
    return value.isEmpty ? 'available' : value;
  }

  Future<List<Map<String, dynamic>>> _loadDoctorsForAvailability() async {
    final merged = <String, Map<String, dynamic>>{};

    try {
      final registry = await _firestore.collection('doctor_registry').get();
      for (final doc in registry.docs) {
        final data = <String, dynamic>{...doc.data(), 'registryDocId': doc.id};
        merged[_doctorDirectoryKey(data)] = data;
      }
    } catch (error) {
      if (kDebugMode) {
        print('Doctor availability registry read failed: $error');
      }
    }

    try {
      final users = await _firestore
          .collection('users')
          .where('role', whereIn: const <String>['DOCTOR', 'doctor'])
          .get();
      for (final doc in users.docs) {
        final userData = <String, dynamic>{
          ...doc.data(),
          'uid': doc.id,
          'userUid': doc.id,
        };
        final key = _doctorDirectoryKey(userData);
        merged[key] = <String, dynamic>{...?merged[key], ...userData};
      }
    } catch (error) {
      if (kDebugMode) {
        print('Doctor availability user read failed: $error');
      }
    }

    final doctors = merged.values
        .where((doctor) => !_doctorIsArchived(doctor))
        .toList(growable: false);
    doctors.sort(
      (a, b) =>
          _doctorName(a).toLowerCase().compareTo(_doctorName(b).toLowerCase()),
    );
    return doctors;
  }

  int? _parseClockMinutes(Object? raw) {
    if (raw == null) return null;
    final text = raw.toString().trim().toLowerCase();
    if (text.isEmpty) return null;
    final match = RegExp(
      r'^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$',
    ).firstMatch(text);
    if (match == null) return null;
    var hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '0');
    if (hour == null || minute == null || minute > 59) return null;
    final meridiem = match.group(3);
    if (meridiem != null) {
      if (hour < 1 || hour > 12) return null;
      if (meridiem == 'pm' && hour != 12) hour += 12;
      if (meridiem == 'am' && hour == 12) hour = 0;
    }
    if (hour > 23) return null;
    return (hour * 60) + minute;
  }

  List<String> _doctorWorkingDays(Map<String, dynamic> doctor) {
    final raw =
        doctor['availableDays'] ??
        doctor['workingDays'] ??
        doctor['scheduleDays'];
    if (raw is Iterable) {
      return raw
          .map((value) => value.toString().trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw
          .split(',')
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  String _weekdayName(int weekday, {bool short = false}) {
    const full = <String>[
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    final value = full[(weekday - 1).clamp(0, 6)];
    return short ? value.substring(0, 3) : value;
  }

  Map<String, Object?> _doctorHoursForDate(
    Map<String, dynamic> doctor,
    DateTime date,
  ) {
    final dayName = _weekdayName(date.weekday);
    final dayShort = _weekdayName(date.weekday, short: true);
    Object? start =
        doctor['workStartTime'] ??
        doctor['availableFrom'] ??
        doctor['startTime'];
    Object? end =
        doctor['workEndTime'] ?? doctor['availableUntil'] ?? doctor['endTime'];
    var hasPublishedSchedule = start != null || end != null;

    final workingHours = doctor['workingHours'] ?? doctor['schedule'];
    if (workingHours is Map) {
      final dayEntry =
          workingHours[dayName] ??
          workingHours[dayShort] ??
          workingHours[dayName[0].toUpperCase() + dayName.substring(1)];
      if (dayEntry is Map) {
        start = dayEntry['start'] ?? dayEntry['from'] ?? start;
        end = dayEntry['end'] ?? dayEntry['to'] ?? end;
        hasPublishedSchedule = true;
      } else if (dayEntry is String && dayEntry.contains('-')) {
        final parts = dayEntry.split('-');
        if (parts.length >= 2) {
          start = parts.first.trim();
          end = parts.last.trim();
          hasPublishedSchedule = true;
        }
      }
    }

    return <String, Object?>{
      'start': _parseClockMinutes(start),
      'end': _parseClockMinutes(end),
      'published': hasPublishedSchedule,
    };
  }

  bool _referralMatchesDoctor(
    Map<String, dynamic> referral,
    Map<String, dynamic> doctor,
  ) {
    final doctorUid = (doctor['userUid'] ?? doctor['uid'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final referralUid = (referral['assignedDoctorUid'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (doctorUid.isNotEmpty && referralUid == doctorUid) return true;

    final doctorEmail = (doctor['email'] ?? '').toString().trim().toLowerCase();
    final referralEmail = (referral['assignedDoctorEmail'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (doctorEmail.isNotEmpty && referralEmail == doctorEmail) return true;

    final referralName = (referral['assignedDoctorName'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return referralName.isNotEmpty &&
        referralName == _doctorName(doctor).toLowerCase();
  }

  DateTime? _referralAppointmentDate(Map<String, dynamic> referral) {
    return _parseDocDate(referral, const <String>[
      'appointmentDateTime',
      'scheduledDateTime',
      'referralDateTime',
      'appointmentDate',
      'scheduledDate',
    ]);
  }

  Map<String, dynamic> _assessDoctorAvailability(
    Map<String, dynamic> doctor,
    DateTime requestedStart,
  ) {
    final requestedEnd = requestedStart.add(
      Duration(minutes: _doctorAvailabilityDuration),
    );
    final status = _doctorStatus(doctor);
    if (status == 'unavailable' || status == 'busy' || status == 'inactive') {
      return <String, dynamic>{
        ...doctor,
        '_isAvailable': false,
        '_availabilityReason': 'Directory status: ${status.toUpperCase()}',
        '_scheduleConfidence': 'Confirmed unavailable',
      };
    }

    final workingDays = _doctorWorkingDays(doctor);
    final requestedDay = _weekdayName(requestedStart.weekday);
    final requestedShortDay = _weekdayName(requestedStart.weekday, short: true);
    if (workingDays.isNotEmpty &&
        !workingDays.any(
          (day) => day == requestedDay || day.startsWith(requestedShortDay),
        )) {
      return <String, dynamic>{
        ...doctor,
        '_isAvailable': false,
        '_availabilityReason': 'Not scheduled on ${_titleCase(requestedDay)}',
        '_scheduleConfidence': 'Published weekly schedule',
      };
    }

    final hours = _doctorHoursForDate(doctor, requestedStart);
    final startMinutes = hours['start'] as int?;
    final endMinutes = hours['end'] as int?;
    final requestedStartMinutes =
        (requestedStart.hour * 60) + requestedStart.minute;
    final requestedEndMinutes =
        requestedStartMinutes + _doctorAvailabilityDuration;
    if (startMinutes != null &&
        endMinutes != null &&
        (requestedStartMinutes < startMinutes ||
            requestedEndMinutes > endMinutes)) {
      return <String, dynamic>{
        ...doctor,
        '_isAvailable': false,
        '_availabilityReason':
            'Outside published consultation hours (${_clockLabel(startMinutes)}–${_clockLabel(endMinutes)})',
        '_scheduleConfidence': 'Published working hours',
      };
    }

    for (final referral in _referralRows) {
      if (!_referralMatchesDoctor(referral, doctor)) continue;
      final referralStatus = (referral['status'] ?? '')
          .toString()
          .toLowerCase();
      if (referralStatus.contains('completed') ||
          referralStatus.contains('cancel')) {
        continue;
      }
      final bookingStart = _referralAppointmentDate(referral);
      if (bookingStart == null) continue;
      final bookingMinutes = _safeMetricCount(
        referral['durationMinutes'],
        fallback: 60,
      ).clamp(15, 480);
      final bookingEnd = bookingStart.add(Duration(minutes: bookingMinutes));
      if (requestedStart.isBefore(bookingEnd) &&
          requestedEnd.isAfter(bookingStart)) {
        return <String, dynamic>{
          ...doctor,
          '_isAvailable': false,
          '_availabilityReason':
              'Conflicts with an active referral at ${_timeLabel(TimeOfDay.fromDateTime(bookingStart))}',
          '_scheduleConfidence': 'Referral conflict detected',
        };
      }
    }

    final published = hours['published'] == true || workingDays.isNotEmpty;
    return <String, dynamic>{
      ...doctor,
      '_isAvailable': true,
      '_availabilityReason': published
          ? 'Available within the published schedule'
          : 'No working hours published; confirm before assigning',
      '_scheduleConfidence': published
          ? 'Schedule checked'
          : 'Directory status only',
    };
  }

  String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1).toLowerCase();
  }

  String _clockLabel(int totalMinutes) {
    final normalized = totalMinutes.clamp(0, (24 * 60) - 1);
    return _timeLabel(
      TimeOfDay(hour: normalized ~/ 60, minute: normalized % 60),
    );
  }

  String _timeLabel(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${time.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  Future<void> _checkDoctorAvailability() async {
    setState(() {
      _isCheckingDoctorAvailability = true;
      _doctorAvailabilityError = null;
    });
    try {
      final doctors = await _loadDoctorsForAvailability();
      final requestedStart = DateTime(
        _doctorAvailabilityDate.year,
        _doctorAvailabilityDate.month,
        _doctorAvailabilityDate.day,
        _doctorAvailabilityTime.hour,
        _doctorAvailabilityTime.minute,
      );
      var results = doctors
          .map((doctor) => _assessDoctorAvailability(doctor, requestedStart))
          .where(
            (doctor) =>
                _doctorSpecialtyFilter == 'All specialties' ||
                _doctorSpecialty(doctor) == _doctorSpecialtyFilter,
          )
          .toList(growable: false);
      results.sort((a, b) {
        final availabilityCompare = (b['_isAvailable'] == true ? 1 : 0)
            .compareTo(a['_isAvailable'] == true ? 1 : 0);
        if (availabilityCompare != 0) return availabilityCompare;
        return _doctorName(a).compareTo(_doctorName(b));
      });
      if (!mounted) return;
      setState(() {
        _doctorAvailabilityResults = results;
        _isCheckingDoctorAvailability = false;
        if (doctors.isEmpty) {
          _doctorAvailabilityError =
              'No active doctors were found in the CHO directory.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isCheckingDoctorAvailability = false;
        _doctorAvailabilityError =
            'Doctor availability could not be checked: $error';
      });
    }
  }

  Widget _buildExecutiveHero() {
    final allSynced = _syncStatus.values.every((value) => value);
    final completionRate = _referralReports == 0
        ? 0
        : ((_referralsCompleted / _referralReports) * 100).round();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF123B46),
            Color(0xFF0A2830),
            Color(0xFF07191E),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.22)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: _primaryAqua.withValues(alpha: 0.06),
            blurRadius: 34,
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 860;
          final overview = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _primaryAqua.withValues(alpha: 0.28),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.auto_graph_rounded,
                      size: 15,
                      color: _primaryAqua,
                    ),
                    SizedBox(width: 7),
                    Text(
                      'LIVE HEALTH INTELLIGENCE',
                      style: TextStyle(
                        color: _primaryAqua,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'City Health Operations\nCommand Center',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'One operational view for population coverage, clinical demand, risk surveillance, referrals, and field-service performance.',
                style: TextStyle(
                  color: _lightOffWhite.withValues(alpha: 0.72),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _buildHeroAction(
                    icon: Icons.assignment_ind_outlined,
                    label: 'Referral workspace',
                    onTap: () => Get.to(() => const CHOPreferralPage()),
                    primary: true,
                  ),
                  _buildHeroAction(
                    icon: Icons.refresh_rounded,
                    label: 'Refresh intelligence',
                    onTap: _refreshSync,
                  ),
                  _buildHeroAction(
                    icon: Icons.download_outlined,
                    label: 'Export dataset',
                    onTap: _exportCsv,
                  ),
                ],
              ),
            ],
          );

          final snapshot = Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.055),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      allSynced
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_sync_rounded,
                      color: allSynced ? Colors.greenAccent : _primaryAqua,
                      size: 20,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        allSynced
                            ? 'All data sources synchronized'
                            : 'Synchronizing health data sources',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildHeroMetric(
                  'Active population view',
                  _safeMetricText(_totalPatients),
                  'patient records',
                  _primaryAqua,
                ),
                const SizedBox(height: 14),
                _buildHeroMetric(
                  'Referral completion',
                  '$completionRate%',
                  '${_safeMetricText(_referralsCompleted)} completed cases',
                  Colors.greenAccent,
                ),
                const SizedBox(height: 14),
                _buildHeroMetric(
                  'Clinical attention',
                  _safeMetricText(_highRiskPatients + _followUpPatients),
                  'high-risk and follow-up cases',
                  Colors.orangeAccent,
                ),
              ],
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                overview,
                const SizedBox(height: 20),
                snapshot,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(child: overview),
              const SizedBox(width: 28),
              Expanded(child: snapshot),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeroAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: primary
            ? _primaryAqua
            : Colors.white.withValues(alpha: 0.08),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(
            color: primary
                ? _primaryAqua
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroMetric(
    String label,
    String value,
    String context,
    Color accent,
  ) {
    return Row(
      children: <Widget>[
        Container(
          width: 4,
          height: 44,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  color: _lightOffWhite.withValues(alpha: 0.62),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        context,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _lightOffWhite.withValues(alpha: 0.58),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOperationalInsights() {
    final coverageGaps =
        _coverageNoRecentCheckup +
        _coverageMissingNextCheckup +
        _coverageUnknownRisk +
        _coverageFollowUpNoSchedule;
    final referralBacklog =
        _referralsSubmitted + _referralsAssigned + _referralsInTreatment;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 1080
            ? (constraints.maxWidth - 30) / 4
            : constraints.maxWidth > 620
            ? (constraints.maxWidth - 10) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _buildInsightCard(
              width: width,
              title: 'Priority caseload',
              value: _safeMetricText(_highRiskPatients),
              context: 'High-risk patients require clinical review',
              icon: Icons.health_and_safety_outlined,
              color: Colors.redAccent,
            ),
            _buildInsightCard(
              width: width,
              title: 'Referral pipeline',
              value: _safeMetricText(referralBacklog),
              context: 'Cases not yet marked completed',
              icon: Icons.route_outlined,
              color: Colors.cyanAccent,
            ),
            _buildInsightCard(
              width: width,
              title: 'Coverage gaps',
              value: _safeMetricText(coverageGaps),
              context: 'Missing visits, schedules, or risk data',
              icon: Icons.data_exploration_outlined,
              color: Colors.orangeAccent,
            ),
            _buildInsightCard(
              width: width,
              title: 'Follow-up queue',
              value: _safeMetricText(_followUpPatients),
              context: 'Patients requiring continuity of care',
              icon: Icons.event_repeat_outlined,
              color: Colors.greenAccent,
            ),
          ],
        );
      },
    );
  }

  BarangayReference? get _selectedDemographicBarangay {
    final code = _selectedDemographicBarangayCode;
    if (code == null || code.isEmpty) return null;
    return MalaybalayBarangays.byCode(code);
  }

  bool _recordMatchesDemographicBarangay(
    Map<String, dynamic> record,
    BarangayReference barangay,
  ) {
    final inferred = inferBarangayReference(record);
    if (inferred != null) {
      return normalizeStoredBarangayCode(inferred.code) ==
          normalizeStoredBarangayCode(barangay.code);
    }
    final rawCode = normalizeStoredBarangayCode(
      (record['barangayCode'] ?? '').toString(),
    );
    if (rawCode.isNotEmpty) {
      return rawCode == normalizeStoredBarangayCode(barangay.code);
    }
    final rawName = (record['barangay'] ?? record['barangayName'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return rawName == barangay.name.toLowerCase();
  }

  String _demographicClassification(Map<String, dynamic> record) {
    final raw =
        (record['caseClassification'] ??
                record['classification'] ??
                record['diseaseType'] ??
                record['type'] ??
                '')
            .toString()
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z]'), '');
    if (raw.contains('noncommunicable')) return 'non_communicable';
    if (raw.contains('communicable')) return 'communicable';

    final narrative = <Object?>[
      record['disease'],
      record['diagnosis'],
      record['condition'],
      record['symptoms'],
      record['chiefComplaint'],
      record['ai_category'],
    ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
    const communicableTerms = <String>{
      'tuberculosis',
      'dengue',
      'influenza',
      'covid',
      'measles',
      'pneumonia',
      'diarrhea',
      'hepatitis',
      'malaria',
      'infection',
    };
    const nonCommunicableTerms = <String>{
      'hypertension',
      'diabetes',
      'cancer',
      'asthma',
      'stroke',
      'arthritis',
      'cardiovascular',
      'kidney disease',
      'heart disease',
    };
    if (nonCommunicableTerms.any(narrative.contains)) {
      return 'non_communicable';
    }
    if (communicableTerms.any(narrative.contains)) return 'communicable';
    return 'unclassified';
  }

  List<Map<String, dynamic>> _uniqueDemographicRecords(
    Iterable<Map<String, dynamic>> records,
  ) {
    final unique = <String, Map<String, dynamic>>{};
    var fallbackIndex = 0;
    for (final record in records) {
      final id =
          (record['id'] ??
                  record['documentId'] ??
                  record['linkedCheckupId'] ??
                  '')
              .toString()
              .trim();
      final key = id.isNotEmpty ? id : 'fallback-${fallbackIndex++}';
      unique[key] = record;
    }
    return unique.values.toList(growable: false);
  }

  Map<String, List<Map<String, dynamic>>> _selectedBarangayDemographics() {
    final barangay = _selectedDemographicBarangay;
    if (barangay == null) {
      return const <String, List<Map<String, dynamic>>>{};
    }
    List<Map<String, dynamic>> select(Iterable<Map<String, dynamic>> records) {
      return records
          .where(
            (record) => _recordMatchesDemographicBarangay(record, barangay),
          )
          .toList(growable: false);
    }

    final patients = select(_rows);
    final checkups = select(_checkupRows);
    final prenatal = select(_prenatalRows);
    final mortality = select(_mortalityRows);
    final morbidity = select(_morbidityRows);
    final classificationPool = _uniqueDemographicRecords(<Map<String, dynamic>>[
      ...checkups,
      ...morbidity,
    ]);
    final communicable = classificationPool
        .where((record) => _demographicClassification(record) == 'communicable')
        .toList(growable: false);
    final nonCommunicable = classificationPool
        .where(
          (record) => _demographicClassification(record) == 'non_communicable',
        )
        .toList(growable: false);
    return <String, List<Map<String, dynamic>>>{
      'Patient Records': patients,
      'Check-ups': checkups,
      'Prenatal': prenatal,
      'Mortality': mortality,
      'Morbidity': morbidity,
      'Communicable': communicable,
      'Non-Communicable': nonCommunicable,
    };
  }

  int? _demographicAge(Map<String, dynamic> record) {
    final direct = record['age'] ?? record['patientAge'];
    if (direct is num) return direct.toInt();
    final parsed = int.tryParse(direct?.toString().trim() ?? '');
    if (parsed != null) return parsed;
    final birthDate = _parseDocDate(record, const <String>[
      'birthDate',
      'dateOfBirth',
      'dob',
    ]);
    if (birthDate == null) return null;
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age < 0 ? null : age;
  }

  String _demographicSex(Map<String, dynamic> record) {
    final raw = (record['gender'] ?? record['sex'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (raw == 'm' || raw == 'male') return 'Male';
    if (raw == 'f' || raw == 'female') return 'Female';
    if (raw.isEmpty) return 'Unknown';
    return 'Other';
  }

  Map<String, int> _demographicAgeCounts(
    Map<String, List<Map<String, dynamic>>> modules,
  ) {
    final counts = <String, int>{
      '0–14': 0,
      '15–24': 0,
      '25–44': 0,
      '45–64': 0,
      '65+': 0,
      'Unknown': 0,
    };
    final patients = modules['Patient Records'] ?? const [];
    final source = patients.isNotEmpty
        ? patients
        : _uniqueDemographicRecords(<Map<String, dynamic>>[
            ...?modules['Check-ups'],
            ...?modules['Prenatal'],
            ...?modules['Morbidity'],
          ]);
    for (final record in source) {
      final age = _demographicAge(record);
      final bucket = age == null
          ? 'Unknown'
          : age <= 14
          ? '0–14'
          : age <= 24
          ? '15–24'
          : age <= 44
          ? '25–44'
          : age <= 64
          ? '45–64'
          : '65+';
      counts[bucket] = (counts[bucket] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> _demographicSexCounts(
    Map<String, List<Map<String, dynamic>>> modules,
  ) {
    final counts = <String, int>{
      'Male': 0,
      'Female': 0,
      'Other': 0,
      'Unknown': 0,
    };
    final patients = modules['Patient Records'] ?? const [];
    final source = patients.isNotEmpty
        ? patients
        : _uniqueDemographicRecords(<Map<String, dynamic>>[
            ...?modules['Check-ups'],
            ...?modules['Prenatal'],
            ...?modules['Morbidity'],
          ]);
    for (final record in source) {
      final sex = _demographicSex(record);
      counts[sex] = (counts[sex] ?? 0) + 1;
    }
    return counts;
  }

  Widget _buildInsightCard({
    required double width,
    required String title,
    required String value,
    required String context,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelTeal,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: _lightOffWhite.withValues(alpha: 0.72),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  context,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _lightOffWhite.withValues(alpha: 0.52),
                    fontSize: 9.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarangayDemographicsExplorer() {
    final selectedBarangay = _selectedDemographicBarangay;
    final modules = _selectedBarangayDemographics();
    final ageCounts = _demographicAgeCounts(modules);
    final sexCounts = _demographicSexCounts(modules);
    final totalSex = sexCounts.values.fold<int>(
      0,
      (total, value) => total + value,
    );
    const moduleIcons = <String, IconData>{
      'Patient Records': Icons.groups_2_outlined,
      'Check-ups': Icons.medical_services_outlined,
      'Prenatal': Icons.pregnant_woman_rounded,
      'Mortality': Icons.monitor_heart_outlined,
      'Morbidity': Icons.sick_outlined,
      'Communicable': Icons.coronavirus_outlined,
      'Non-Communicable': Icons.favorite_border_rounded,
    };
    const moduleColors = <String, Color>{
      'Patient Records': _primaryAqua,
      'Check-ups': Color(0xFF60A5FA),
      'Prenatal': Color(0xFFF472B6),
      'Mortality': Color(0xFFFB7185),
      'Morbidity': Color(0xFFF59E0B),
      'Communicable': Color(0xFFA78BFA),
      'Non-Communicable': Color(0xFF34D399),
    };
    const ageColors = <Color>[
      Color(0xFF38BDF8),
      Color(0xFF818CF8),
      Color(0xFF34D399),
      Color(0xFFF59E0B),
      Color(0xFFEF4444),
      Color(0xFF94A3B8),
    ];
    const sexColors = <String, Color>{
      'Male': Color(0xFF60A5FA),
      'Female': Color(0xFFF472B6),
      'Other': Color(0xFFA78BFA),
      'Unknown': Color(0xFF94A3B8),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[_panelTealAlt, _panelTeal, _darkDeepTeal],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.20)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              final header = Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[_primaryAqua, _secondaryIceBlue],
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.diversity_3_outlined,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Barangay Demographic Explorer',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Select one barangay first to reveal its population profile and health-program activity.',
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.62),
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final selector = SizedBox(
                width: compact ? constraints.maxWidth : 340,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedDemographicBarangayCode,
                  isExpanded: true,
                  dropdownColor: _panelTealAlt,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: _availabilityInputDecoration(
                    'Choose barangay first',
                    Icons.location_on_outlined,
                  ),
                  hint: Text(
                    'Select barangay',
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.55),
                    ),
                  ),
                  items: MalaybalayBarangays.all
                      .map(
                        (barangay) => DropdownMenuItem<String>(
                          value: barangay.code,
                          child: Text(
                            '${barangay.name} • ${barangay.district}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    setState(() => _selectedDemographicBarangayCode = value);
                  },
                ),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    header,
                    const SizedBox(height: 14),
                    selector,
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(child: header),
                  const SizedBox(width: 20),
                  selector,
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          if (selectedBarangay == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Column(
                children: <Widget>[
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.location_searching_rounded,
                      color: _primaryAqua,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Choose a barangay to view demographics',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'No city-wide totals are shown here. This explorer intentionally requires a barangay selection before displaying health records.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.52),
                      fontSize: 10.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            )
          else ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        selectedBarangay.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${selectedBarangay.district} • ${selectedBarangay.code}',
                        style: TextStyle(
                          color: _lightOffWhite.withValues(alpha: 0.55),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _selectedDemographicBarangayCode = null),
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('Clear selection'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 1100
                    ? 4
                    : constraints.maxWidth > 680
                    ? 2
                    : 1;
                final width = columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - ((columns - 1) * 10)) / columns;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: modules.entries
                      .map(
                        (entry) => Container(
                          width: width,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.045),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: (moduleColors[entry.key] ?? _primaryAqua)
                                  .withValues(alpha: 0.18),
                            ),
                          ),
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color:
                                      (moduleColors[entry.key] ?? _primaryAqua)
                                          .withValues(alpha: 0.11),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Icon(
                                  moduleIcons[entry.key] ?? Icons.analytics,
                                  color:
                                      moduleColors[entry.key] ?? _primaryAqua,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Text(
                                  entry.key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _lightOffWhite.withValues(
                                      alpha: 0.72,
                                    ),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                entry.value.length.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 760;
                final ageChart = _buildDemographicChartPanel(
                  title: 'Age Distribution',
                  subtitle: 'Latest available patient demographic profile',
                  child: _buildDemographicAgeChart(ageCounts, ageColors),
                );
                final sexChart = _buildDemographicChartPanel(
                  title: 'Sex Distribution',
                  subtitle: 'Registered population composition',
                  child: _buildDemographicSexChart(
                    sexCounts,
                    sexColors,
                    totalSex,
                  ),
                );
                if (stacked) {
                  return Column(
                    children: <Widget>[
                      ageChart,
                      const SizedBox(height: 10),
                      sexChart,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: ageChart),
                    const SizedBox(width: 10),
                    Expanded(child: sexChart),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Text(
              'Communicable and non-communicable totals are derived from explicit case classification first, then recognized condition keywords when classification is missing.',
              style: TextStyle(
                color: _lightOffWhite.withValues(alpha: 0.46),
                fontSize: 9.5,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDemographicChartPanel({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.50),
              fontSize: 9.5,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildDemographicAgeChart(
    Map<String, int> counts,
    List<Color> colors,
  ) {
    final entries = counts.entries.toList(growable: false);
    final maxCount = entries.fold<int>(
      0,
      (current, entry) => entry.value > current ? entry.value : current,
    );
    if (maxCount == 0) {
      return Center(
        child: Text(
          'No age data recorded for this barangay.',
          style: TextStyle(
            color: _lightOffWhite.withValues(alpha: 0.55),
            fontSize: 10.5,
          ),
        ),
      );
    }
    final maxY = (maxCount < 4 ? 4 : maxCount * 1.2).toDouble();
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withValues(alpha: 0.07),
            strokeWidth: 1,
          ),
        ),
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
              reservedSize: 28,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  color: _lightOffWhite.withValues(alpha: 0.48),
                  fontSize: 8,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= entries.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    entries[index].key,
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.62),
                      fontSize: 8,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: List<BarChartGroupData>.generate(entries.length, (index) {
          return BarChartGroupData(
            x: index,
            barRods: <BarChartRodData>[
              BarChartRodData(
                toY: entries[index].value.toDouble(),
                width: 18,
                color: colors[index % colors.length],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildDemographicSexChart(
    Map<String, int> counts,
    Map<String, Color> colors,
    int total,
  ) {
    if (total == 0) {
      return Center(
        child: Text(
          'No sex data recorded for this barangay.',
          style: TextStyle(
            color: _lightOffWhite.withValues(alpha: 0.55),
            fontSize: 10.5,
          ),
        ),
      );
    }
    final entries = counts.entries.where((entry) => entry.value > 0).toList();
    return Row(
      children: <Widget>[
        Expanded(
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 42,
              sectionsSpace: 2,
              centerSpaceColor: Colors.transparent,
              sections: entries
                  .map(
                    (entry) => PieChartSectionData(
                      value: entry.value.toDouble(),
                      color: colors[entry.key] ?? _mutedCoolGray,
                      radius: 48,
                      title: '${(entry.value / total * 100).round()}%',
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entries
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colors[entry.key] ?? _mutedCoolGray,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              color: _lightOffWhite.withValues(alpha: 0.65),
                              fontSize: 9.5,
                            ),
                          ),
                        ),
                        Text(
                          entry.value.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }

  Widget _buildDoctorAvailabilityPlanner() {
    const specialties = <String>[
      'All specialties',
      'General Medicine',
      'General Practice',
      'Family Medicine',
      'Cardiology',
      'Pediatrics',
      'Obstetrics',
      'Pulmonology',
      'Infectious Disease',
    ];
    final availableCount = _doctorAvailabilityResults
        .where((doctor) => doctor['_isAvailable'] == true)
        .length;
    final requestedDateTime = DateTime(
      _doctorAvailabilityDate.year,
      _doctorAvailabilityDate.month,
      _doctorAvailabilityDate.day,
      _doctorAvailabilityTime.hour,
      _doctorAvailabilityTime.minute,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF123B46),
            Color(0xFF0D2A32),
            Color(0xFF081C21),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.20)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final heading = Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[_primaryAqua, _secondaryIceBlue],
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Referral Doctor Availability',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Check directory status, published working hours, and referral conflicts before assigning a patient.',
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.62),
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final resultBadge = Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: availableCount > 0
                      ? Colors.greenAccent.withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: availableCount > 0
                        ? Colors.greenAccent.withValues(alpha: 0.28)
                        : Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: Text(
                  _doctorAvailabilityResults.isEmpty
                      ? 'Ready to check'
                      : '$availableCount available',
                  style: TextStyle(
                    color: availableCount > 0
                        ? Colors.greenAccent
                        : _lightOffWhite.withValues(alpha: 0.72),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    heading,
                    const SizedBox(height: 12),
                    resultBadge,
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(child: heading),
                  const SizedBox(width: 16),
                  resultBadge,
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 1050
                  ? 5
                  : constraints.maxWidth > 680
                  ? 3
                  : 1;
              final fieldWidth = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - ((columns - 1) * 10)) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: fieldWidth,
                    child: _buildAvailabilityPicker(
                      label: 'Referral date',
                      value: _dateLabel(_doctorAvailabilityDate),
                      icon: Icons.event_outlined,
                      onTap: () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: _doctorAvailabilityDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (selected != null && mounted) {
                          setState(() {
                            _doctorAvailabilityDate = selected;
                            _doctorAvailabilityResults =
                                <Map<String, dynamic>>[];
                          });
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _buildAvailabilityPicker(
                      label: 'Start time',
                      value: _timeLabel(_doctorAvailabilityTime),
                      icon: Icons.schedule_outlined,
                      onTap: () async {
                        final selected = await showTimePicker(
                          context: context,
                          initialTime: _doctorAvailabilityTime,
                        );
                        if (selected != null && mounted) {
                          setState(() {
                            _doctorAvailabilityTime = selected;
                            _doctorAvailabilityResults =
                                <Map<String, dynamic>>[];
                          });
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: DropdownButtonFormField<int>(
                      initialValue: _doctorAvailabilityDuration,
                      dropdownColor: _panelTealAlt,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: _availabilityInputDecoration(
                        'Duration',
                        Icons.timelapse_rounded,
                      ),
                      items: const <int>[30, 45, 60, 90, 120]
                          .map(
                            (minutes) => DropdownMenuItem<int>(
                              value: minutes,
                              child: Text('$minutes minutes'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _doctorAvailabilityDuration = value;
                          _doctorAvailabilityResults = <Map<String, dynamic>>[];
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: DropdownButtonFormField<String>(
                      initialValue: _doctorSpecialtyFilter,
                      dropdownColor: _panelTealAlt,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: _availabilityInputDecoration(
                        'Specialty',
                        Icons.medical_information_outlined,
                      ),
                      items: specialties
                          .map(
                            (specialty) => DropdownMenuItem<String>(
                              value: specialty,
                              child: Text(
                                specialty,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _doctorSpecialtyFilter = value;
                          _doctorAvailabilityResults = <Map<String, dynamic>>[];
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: _isCheckingDoctorAvailability
                          ? null
                          : _checkDoctorAvailability,
                      icon: _isCheckingDoctorAvailability
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.manage_search_rounded),
                      label: Text(
                        _isCheckingDoctorAvailability
                            ? 'Checking...'
                            : 'Check doctors',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _primaryAqua,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          if (_doctorAvailabilityError != null) ...<Widget>[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: Colors.orangeAccent.withValues(alpha: 0.28),
                ),
              ),
              child: Text(
                _doctorAvailabilityError!,
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 11,
                ),
              ),
            ),
          ],
          if (_doctorAvailabilityResults.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Availability for ${_dateLabel(requestedDateTime)} at ${_timeLabel(_doctorAvailabilityTime)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Get.to(() => const CHOPreferralPage()),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Open referrals'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth > 1000
                    ? (constraints.maxWidth - 20) / 3
                    : constraints.maxWidth > 620
                    ? (constraints.maxWidth - 10) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _doctorAvailabilityResults
                      .map(
                        (doctor) => SizedBox(
                          width: cardWidth,
                          child: _buildDoctorAvailabilityResult(doctor),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Availability is planning guidance. A result based only on directory status must be confirmed with the doctor before final referral assignment.',
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.50),
              fontSize: 9.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _availabilityInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: _lightOffWhite.withValues(alpha: 0.58),
        fontSize: 11,
      ),
      prefixIcon: Icon(icon, color: _primaryAqua, size: 19),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.055),
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: _primaryAqua, width: 1.5),
      ),
    );
  }

  Widget _buildAvailabilityPicker({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: InputDecorator(
        decoration: _availabilityInputDecoration(label, icon),
        child: Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildDoctorAvailabilityResult(Map<String, dynamic> doctor) {
    final available = doctor['_isAvailable'] == true;
    final confidence = (doctor['_scheduleConfidence'] ?? '').toString();
    final reason = (doctor['_availabilityReason'] ?? '').toString();
    final accent = available ? Colors.greenAccent : Colors.orangeAccent;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  available
                      ? Icons.person_search_rounded
                      : Icons.event_busy_rounded,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _doctorName(doctor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _doctorSpecialty(doctor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.58),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  available ? 'AVAILABLE' : 'UNAVAILABLE',
                  style: TextStyle(
                    color: accent,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            reason,
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.74),
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            confidence,
            style: TextStyle(
              color: accent.withValues(alpha: 0.82),
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[_panelTealAlt, _panelTeal, _darkDeepTeal],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _lightOffWhite.withValues(alpha: 0.68),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsFilterBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideHeader = constraints.maxWidth > 760;
        final optionColumns = constraints.maxWidth > 1120
            ? 4
            : (constraints.maxWidth > 700 ? 2 : 1);
        final optionSpacing = optionColumns == 1 ? 8.0 : 10.0;
        final calculatedOptionWidth = optionColumns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - (optionSpacing * (optionColumns - 1))) /
                  optionColumns;
        final optionWidthLimit = optionColumns == 1
            ? constraints.maxWidth
            : (optionColumns == 4 ? 188.0 : 214.0);
        final optionWidth = calculatedOptionWidth > optionWidthLimit
            ? optionWidthLimit
            : calculatedOptionWidth;
        final optionMinHeight = optionColumns == 1 ? 86.0 : 78.0;
        final supportTextMaxLines = optionColumns == 1 ? 2 : 2;
        final filterAccent = _mutedCoolGray;
        final filterBorderColor = _lightOffWhite.withValues(alpha: 0.12);

        final headerCopy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _lightOffWhite.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: filterBorderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.insights_rounded,
                    size: 12,
                    color: _lightOffWhite.withValues(alpha: 0.82),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Live Analytics Scope',
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.86),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Statistics Analysis Filter',
              style: TextStyle(
                color: _lightOffWhite,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose the reporting window for every KPI card, chart, and workload trend. The active range is ${_analyticsWindowLabel().toLowerCase()}.',
              maxLines: isWideHeader ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _lightOffWhite.withValues(alpha: 0.74),
                fontSize: 10,
                height: 1.35,
              ),
            ),
          ],
        );

        final activeWindowCard = Container(
          width: isWideHeader ? 196 : double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _lightOffWhite.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: filterBorderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Active Window',
                style: TextStyle(
                  color: _lightOffWhite.withValues(alpha: 0.66),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _analyticsWindowLabel(),
                style: const TextStyle(
                  color: _lightOffWhite,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Summary cards and charts stay in sync automatically.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _lightOffWhite.withValues(alpha: 0.72),
                  fontSize: 9.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF13242A),
                _darkDeepTeal,
                const Color(0xFF061419),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: filterBorderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, 8),
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
                    const SizedBox(width: 10),
                    activeWindowCard,
                  ],
                )
              else ...[
                headerCopy,
                const SizedBox(height: 10),
                activeWindowCard,
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: optionSpacing,
                runSpacing: optionSpacing,
                children: _ChoAnalyticsWindow.values
                    .map((window) {
                      final isSelected = window == _analyticsWindow;
                      final icon = _analyticsWindowIcon(window);
                      return SizedBox(
                        width: optionWidth,
                        child: Tooltip(
                          message: _analyticsWindowLabel(window),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                if (isSelected) return;
                                setState(() {
                                  _analyticsWindow = window;
                                  _recomputeAnalyticsState();
                                });
                              },
                              child: Container(
                                constraints: BoxConstraints(
                                  minHeight: optionMinHeight,
                                ),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: isSelected
                                        ? <Color>[
                                            const Color(0xFF24353A),
                                            const Color(0xFF17262B),
                                          ]
                                        : <Color>[
                                            const Color(0xFF13242A),
                                            _darkDeepTeal.withValues(
                                              alpha: 0.96,
                                            ),
                                          ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? _lightOffWhite.withValues(alpha: 0.24)
                                        : filterBorderColor,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.24,
                                            ),
                                            blurRadius: 14,
                                            offset: const Offset(0, 6),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 26,
                                          height: 26,
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? _lightOffWhite.withValues(
                                                    alpha: 0.16,
                                                  )
                                                : filterAccent.withValues(
                                                    alpha: 0.14,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              9,
                                            ),
                                          ),
                                          child: Icon(
                                            icon,
                                            size: 15,
                                            color: _lightOffWhite,
                                          ),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? _lightOffWhite.withValues(
                                                    alpha: 0.18,
                                                  )
                                                : _lightOffWhite.withValues(
                                                    alpha: 0.06,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: _lightOffWhite.withValues(
                                                alpha: isSelected ? 0.28 : 0.10,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            _analyticsWindowShortLabel(window),
                                            style: const TextStyle(
                                              color: _lightOffWhite,
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _analyticsWindowLabel(window),
                                      style: const TextStyle(
                                        color: _lightOffWhite,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _analyticsWindowSupportText(window),
                                      maxLines: supportTextMaxLines,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _lightOffWhite.withValues(
                                          alpha: isSelected ? 0.92 : 0.70,
                                        ),
                                        fontSize: 9.25,
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      isSelected
                                          ? 'Applied now'
                                          : 'Tap to apply',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _lightOffWhite.withValues(
                                          alpha: isSelected ? 0.94 : 0.58,
                                        ),
                                        fontSize: 8.75,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ],
          ),
        );
      },
    );
  }

  String _safeObjectText(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    if (value is String) {
      final text = value.trim();
      return text.isEmpty ? fallback : text;
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    try {
      final text = value.toString().trim();
      return text.isEmpty ? fallback : text;
    } catch (_) {
      return fallback;
    }
  }

  int _safeMetricCount(Object? value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value.trim()) ?? fallback;
    }
    final text = _safeObjectText(value, fallback: '');
    if (text.isEmpty) return fallback;
    return int.tryParse(text) ?? fallback;
  }

  String _safeMetricText(Object? value, {int fallback = 0}) {
    return _safeMetricCount(value, fallback: fallback).toString();
  }

  List<int> _safeIntList(Object? values, {int fallbackLength = 1}) {
    if (values is List) {
      final out = <int>[];
      for (int i = 0; i < values.length; i++) {
        final raw = values[i];
        if (raw is num) {
          out.add(raw.toInt());
          continue;
        }
        final parsed = int.tryParse(_safeObjectText(raw, fallback: ''));
        if (parsed != null) out.add(parsed);
      }
      if (out.isNotEmpty) return out;
    }
    return List<int>.filled(fallbackLength, 0);
  }

  List<String> _safeStringList(
    Object? values, {
    int fallbackLength = 1,
    String fallbackPrefix = 'M',
  }) {
    if (values is List) {
      final out = <String>[];
      for (int i = 0; i < values.length; i++) {
        final raw = values[i];
        final text = _safeObjectText(raw, fallback: '');
        if (text.isNotEmpty) out.add(text);
      }
      if (out.isNotEmpty) return out;
    }
    return List<String>.generate(
      fallbackLength,
      (i) => '$fallbackPrefix${i + 1}',
    );
  }

  double _maxFromIntValues(Object? values, {double minimum = 1}) {
    final safeValues = _safeIntList(values, fallbackLength: 1);
    int maxVal = 0;
    for (final v in safeValues) {
      if (v > maxVal) maxVal = v;
    }
    final result = maxVal.toDouble();
    return result < minimum ? minimum : result;
  }

  Widget _buildAnalyticsPanel({
    required String title,
    required String subtitle,
    required Widget child,
    double contentHeight = 190,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[_panelTealAlt, _panelTeal, _darkDeepTeal],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: <Widget>[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _primaryAqua.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.query_stats_rounded,
                    color: _primaryAqua,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: _lightOffWhite,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: _lightOffWhite.withValues(alpha: 0.62),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(height: contentHeight, child: child),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientQueueSection() {
    return SizedBox(
      height: 360,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _darkDeepTeal,
            border: Border.all(color: _primaryAqua.withValues(alpha: 0.06)),
          ),
          child: _rows.isEmpty && _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
              ? Center(
                  child: Text(
                    'No patient records available yet.',
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.78),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final r = _rows[i];
                    final name = _patientName(r);
                    final barangay = _patientBarangay(r);
                    final nextCheckupDate = _nextCheckupDate(r);
                    final nextCheckup = nextCheckupDate == null
                        ? 'N/A'
                        : _dateLabel(nextCheckupDate);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _secondaryIceBlue.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _primaryAqua.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 25,
                            backgroundColor: _primaryAqua.withValues(
                              alpha: 0.45,
                            ),
                            child: Text(
                              (i + 1).toString(),
                              style: const TextStyle(
                                color: _darkDeepTeal,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _lightOffWhite,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Barangay: ${barangay.isEmpty ? 'N/A' : barangay}  |  Next checkup: $nextCheckup',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _lightOffWhite.withValues(
                                      alpha: 0.72,
                                    ),
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildCheckupTrendDetail(
    List<int> trendValues,
    List<String> trendLabels,
  ) {
    if (trendValues.isEmpty || trendLabels.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _secondaryIceBlue.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _primaryAqua.withValues(alpha: 0.20)),
        ),
        child: Text(
          'No check-up trend data available yet.',
          style: TextStyle(
            color: _lightOffWhite.withValues(alpha: 0.82),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    int peakIndex = 0;
    int total = 0;
    for (int i = 0; i < trendValues.length; i++) {
      total += trendValues[i];
      if (trendValues[i] > trendValues[peakIndex]) {
        peakIndex = i;
      }
    }

    final latestIndex = trendValues.length - 1;
    final latestValue = trendValues[latestIndex];
    final latestLabel = trendLabels[latestIndex];
    final previousIndex = latestIndex > 0 ? latestIndex - 1 : latestIndex;
    final previousValue = trendValues[previousIndex];
    final previousLabel = trendLabels[previousIndex];
    final monthDelta = latestValue - previousValue;
    final deltaText = latestIndex == 0
        ? 'no prior month comparison yet'
        : monthDelta == 0
        ? 'same as $previousLabel'
        : monthDelta > 0
        ? 'up by $monthDelta vs $previousLabel'
        : 'down by ${monthDelta.abs()} vs $previousLabel';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _secondaryIceBlue.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.20)),
      ),
      child: Text(
        'Latest ($latestLabel): $latestValue check-ups, $deltaText. '
        'Peak: ${trendLabels[peakIndex]} (${trendValues[peakIndex]}). '
        'Window total: $total.',
        style: TextStyle(
          color: _lightOffWhite.withValues(alpha: 0.82),
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _buildCheckupTrendChart() {
    final trendValues = _safeIntList(_checkupTrendValues, fallbackLength: 6);
    final rawTrendLabels = _safeStringList(
      _checkupTrendLabels,
      fallbackLength: trendValues.length,
      fallbackPrefix: 'M',
    );
    final trendLabels = List<String>.generate(
      trendValues.length,
      (i) => i < rawTrendLabels.length ? rawTrendLabels[i] : 'M${i + 1}',
      growable: false,
    );
    final maxY = _maxFromIntValues(trendValues, minimum: 5) * 1.2;
    final interval = ((maxY / 4).clamp(1, maxY)).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (trendValues.length - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: _lightOffWhite.withValues(alpha: 0.12),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  color: _primaryAqua,
                  barWidth: 3,
                  dotData: FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: _primaryAqua.withValues(alpha: 0.18),
                  ),
                  spots: List.generate(
                    trendValues.length,
                    (i) => FlSpot(i.toDouble(), trendValues[i].toDouble()),
                  ),
                ),
              ],
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
                    reservedSize: 28,
                    interval: interval,
                    getTitlesWidget: (value, _) => Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.65),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, _) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= trendLabels.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          trendLabels[idx],
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.70),
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildCheckupTrendDetail(trendValues, trendLabels),
      ],
    );
  }

  Widget _buildDiseaseTrendChart() {
    final monthLabels = _safeStringList(
      _diseaseTrendMonthLabels,
      fallbackLength: 6,
      fallbackPrefix: 'M',
    );
    final dynamic rawSeries = _diseaseTrendSeries;
    if (rawSeries is! Map) {
      return Center(
        child: Text(
          'No disease trend data yet',
          style: TextStyle(
            color: _lightOffWhite.withValues(alpha: 0.75),
            fontSize: 12,
          ),
        ),
      );
    }

    final seriesEntries = <MapEntry<String, List<int>>>[];
    rawSeries.forEach((dynamic key, dynamic value) {
      final disease = (key ?? '').toString().trim();
      if (disease.isEmpty) return;

      final values = <int>[];
      if (value is List) {
        for (final item in value) {
          if (item is num) {
            values.add(item.toInt());
          } else {
            final parsed = int.tryParse(item.toString());
            if (parsed != null) values.add(parsed);
          }
        }
      }

      if (values.isNotEmpty) {
        seriesEntries.add(MapEntry<String, List<int>>(disease, values));
      }
    });

    if (seriesEntries.isEmpty) {
      return Center(
        child: Text(
          'No disease trend data yet',
          style: TextStyle(
            color: _lightOffWhite.withValues(alpha: 0.75),
            fontSize: 12,
          ),
        ),
      );
    }

    final pointCount = monthLabels.length;
    final plottedSeries = seriesEntries
        .map(
          (entry) => MapEntry(
            entry.key,
            List<int>.generate(
              pointCount,
              (i) => i < entry.value.length ? entry.value[i] : 0,
              growable: false,
            ),
          ),
        )
        .toList(growable: false);

    final allValues = <int>[
      for (final series in plottedSeries) ...series.value,
    ];
    final maxY = _maxFromIntValues(allValues, minimum: 5) * 1.2;
    final interval = ((maxY / 4).clamp(1, maxY)).toDouble();
    const seriesColors = <Color>[
      Colors.redAccent,
      Colors.orangeAccent,
      Colors.lightGreenAccent,
      Colors.cyanAccent,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (pointCount - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: _lightOffWhite.withValues(alpha: 0.12),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: List.generate(plottedSeries.length, (index) {
                final series = plottedSeries[index];
                final color = seriesColors[index % seriesColors.length];
                return LineChartBarData(
                  isCurved: true,
                  color: color,
                  barWidth: 3,
                  dotData: FlDotData(show: true),
                  spots: List.generate(
                    pointCount,
                    (i) => FlSpot(i.toDouble(), series.value[i].toDouble()),
                  ),
                );
              }),
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
                    reservedSize: 28,
                    interval: interval,
                    getTitlesWidget: (value, _) => Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.65),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    interval: 1,
                    getTitlesWidget: (value, _) {
                      if (!_isWholeAxisTick(value)) {
                        return const SizedBox.shrink();
                      }
                      final idx = value.round();
                      if (idx < 0 || idx >= monthLabels.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          monthLabels[idx],
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.70),
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: List.generate(plottedSeries.length, (index) {
            final disease = plottedSeries[index].key;
            final color = seriesColors[index % seriesColors.length];
            return _ChartLegendDot(
              label: _truncateLabel(disease, max: 18),
              color: color,
            );
          }),
        ),
      ],
    );
  }

  Widget _buildServiceLoadChart() {
    final values = <int>[
      _safeMetricCount(_totalPatients),
      _safeMetricCount(_checkupsThisMonth),
      _safeMetricCount(_activePrenatal),
      _safeMetricCount(_immunizationRecords),
      _safeMetricCount(_morbidityReports),
      _safeMetricCount(_mortalityReports),
      _safeMetricCount(_referralReports),
    ];
    final labels = <String>['Pts', 'Chk', 'Pre', 'Imm', 'Mrb', 'Mrt', 'Ref'];
    final colors = <Color>[
      _primaryAqua,
      _secondaryIceBlue,
      Colors.pinkAccent,
      Colors.greenAccent,
      Colors.orangeAccent,
      Colors.redAccent,
      Colors.cyanAccent,
    ];
    final maxY = _maxFromIntValues(values, minimum: 5) * 1.2;
    final interval = ((maxY / 4).clamp(1, maxY)).toDouble();

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: _lightOffWhite.withValues(alpha: 0.12),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(values.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: values[i].toDouble(),
                width: 16,
                color: colors[i],
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }),
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
              reservedSize: 28,
              interval: interval,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  color: _lightOffWhite.withValues(alpha: 0.65),
                  fontSize: 10,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx < 0 || idx >= labels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    labels[idx],
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.70),
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReferralTrendChart() {
    final trendValues = _safeIntList(_referralTrendValues, fallbackLength: 6);
    final rawTrendLabels = _safeStringList(
      _referralTrendLabels,
      fallbackLength: trendValues.length,
      fallbackPrefix: 'M',
    );
    final trendLabels = List<String>.generate(
      trendValues.length,
      (i) => i < rawTrendLabels.length ? rawTrendLabels[i] : 'M${i + 1}',
      growable: false,
    );
    final maxY = _maxFromIntValues(trendValues, minimum: 5) * 1.2;
    final interval = ((maxY / 4).clamp(1, maxY)).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (trendValues.length - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: _lightOffWhite.withValues(alpha: 0.12),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  color: Colors.cyanAccent,
                  barWidth: 3,
                  dotData: FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.cyanAccent.withValues(alpha: 0.18),
                  ),
                  spots: List.generate(
                    trendValues.length,
                    (i) => FlSpot(i.toDouble(), trendValues[i].toDouble()),
                  ),
                ),
              ],
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
                    reservedSize: 28,
                    interval: interval,
                    getTitlesWidget: (value, _) => Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.65),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, _) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= trendLabels.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          trendLabels[idx],
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.70),
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Submitted: ${_safeMetricText(_referralsSubmitted)} | Assigned: ${_safeMetricText(_referralsAssigned)} | In-treatment: ${_safeMetricText(_referralsInTreatment)} | Completed: ${_safeMetricText(_referralsCompleted)}',
          style: TextStyle(
            color: _lightOffWhite.withValues(alpha: 0.78),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildReferralStatusChart() {
    final labels = <String>['Submitted', 'Assigned', 'In Tx', 'Completed'];
    final values = <int>[
      _safeMetricCount(_referralsSubmitted),
      _safeMetricCount(_referralsAssigned),
      _safeMetricCount(_referralsInTreatment),
      _safeMetricCount(_referralsCompleted),
    ];
    final colors = <Color>[
      Colors.orangeAccent,
      Colors.lightBlueAccent,
      Colors.amberAccent,
      Colors.greenAccent,
    ];

    final total = values.fold<int>(0, (sum, value) => sum + value);
    if (total == 0) {
      return Center(
        child: Text(
          'No referral status activity yet',
          style: TextStyle(
            color: _lightOffWhite.withValues(alpha: 0.75),
            fontSize: 12,
          ),
        ),
      );
    }

    final maxY = _maxFromIntValues(values, minimum: 5) * 1.2;
    final interval = ((maxY / 4).clamp(1, maxY)).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: _lightOffWhite.withValues(alpha: 0.12),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(values.length, (i) {
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: values[i].toDouble(),
                      width: 18,
                      color: colors[i],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                );
              }),
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
                    reservedSize: 28,
                    interval: interval,
                    getTitlesWidget: (value, _) => Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.65),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, _) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= labels.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          labels[idx],
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.70),
                            fontSize: 9,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: List.generate(labels.length, (i) {
            return _ChartLegendDot(
              label: '${labels[i]} (${values[i]})',
              color: colors[i],
            );
          }),
        ),
      ],
    );
  }

  Widget _buildReferralBarangayChart() {
    final values = _safeIntList(_referralBarangayValues, fallbackLength: 0);
    final labels = _safeStringList(
      _referralBarangayLabels,
      fallbackLength: values.length,
      fallbackPrefix: 'Brgy',
    );

    if (values.isEmpty || labels.isEmpty) {
      return Center(
        child: Text(
          'No referral barangay data yet',
          style: TextStyle(
            color: _lightOffWhite.withValues(alpha: 0.75),
            fontSize: 12,
          ),
        ),
      );
    }

    final maxY = _maxFromIntValues(values, minimum: 5) * 1.2;
    final interval = ((maxY / 4).clamp(1, maxY)).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: _lightOffWhite.withValues(alpha: 0.12),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(values.length, (i) {
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: values[i].toDouble(),
                      width: 16,
                      color: Colors.tealAccent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                );
              }),
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
                    reservedSize: 28,
                    interval: interval,
                    getTitlesWidget: (value, _) => Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.65),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, _) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= labels.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _truncateLabel(labels[idx], max: 8),
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.70),
                            fontSize: 9,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: List.generate(labels.length, (i) {
            return _ChartLegendDot(
              label: '${_truncateLabel(labels[i], max: 16)} (${values[i]})',
              color: Colors.tealAccent,
            );
          }),
        ),
      ],
    );
  }

  Widget _buildRiskDonutChart() {
    final labels = <String>['High', 'Moderate', 'Low', 'Unknown'];
    final colors = <Color>[
      Colors.redAccent,
      Colors.orangeAccent,
      Colors.lightGreenAccent,
      Colors.blueGrey,
    ];
    final rawRiskValues = _safeIntList(_riskLevelCounts, fallbackLength: 4);
    final riskValues = rawRiskValues
        .take(labels.length)
        .toList(growable: false);
    final total = riskValues.fold<int>(0, (sum, item) => sum + item);
    if (total == 0) {
      return Center(
        child: Text(
          'No risk data yet',
          style: TextStyle(
            color: _lightOffWhite.withValues(alpha: 0.75),
            fontSize: 12,
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 34,
              sectionsSpace: 2,
              sections: List.generate(riskValues.length, (i) {
                final value = riskValues[i].toDouble();
                if (value <= 0) {
                  return PieChartSectionData(
                    value: 0,
                    title: '',
                    radius: 0,
                    color: Colors.transparent,
                  );
                }
                final pct = (value / total * 100).round();
                return PieChartSectionData(
                  value: value,
                  color: colors[i],
                  radius: 46,
                  title: '$pct%',
                  titleStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: List.generate(labels.length, (i) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors[i],
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '${labels[i]} (${riskValues[i]})',
                  style: TextStyle(
                    color: _lightOffWhite.withValues(alpha: 0.75),
                    fontSize: 10,
                  ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _buildPowerBiCharts() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = maxWidth > 1200 ? 3 : (maxWidth > 820 ? 2 : 1);
        final panelWidth = columns == 1
            ? maxWidth
            : (maxWidth - (10 * (columns - 1))) / columns;

        final panels = <Widget>[
          SizedBox(
            width: panelWidth,
            child: _buildAnalyticsPanel(
              title: 'Checkup Trend',
              subtitle:
                  'Monthly activity in ${_analyticsWindowLabel().toLowerCase()}',
              contentHeight: 250,
              child: _buildCheckupTrendChart(),
            ),
          ),
          SizedBox(
            width: panelWidth,
            child: _buildAnalyticsPanel(
              title: 'Disease Trend Analysis',
              subtitle:
                  'Top diseases in ${_analyticsWindowLabel().toLowerCase()}',
              contentHeight: 250,
              child: _buildDiseaseTrendChart(),
            ),
          ),
          SizedBox(
            width: panelWidth,
            child: _buildAnalyticsPanel(
              title: 'Service Load',
              subtitle:
                  'Cross-program volume in ${_analyticsWindowLabel().toLowerCase()}',
              contentHeight: 250,
              child: _buildServiceLoadChart(),
            ),
          ),
          SizedBox(
            width: panelWidth,
            child: _buildAnalyticsPanel(
              title: 'Referral Trend',
              subtitle:
                  'Monthly referrals in ${_analyticsWindowLabel().toLowerCase()}',
              contentHeight: 250,
              child: _buildReferralTrendChart(),
            ),
          ),
          SizedBox(
            width: panelWidth,
            child: _buildAnalyticsPanel(
              title: 'Referral Status Mix',
              subtitle: 'Submitted, assigned, in-treatment, and completed',
              contentHeight: 250,
              child: _buildReferralStatusChart(),
            ),
          ),
          SizedBox(
            width: panelWidth,
            child: _buildAnalyticsPanel(
              title: 'Referrals by Barangay',
              subtitle:
                  'Top barangays sending referrals in ${_analyticsWindowLabel().toLowerCase()}',
              contentHeight: 250,
              child: _buildReferralBarangayChart(),
            ),
          ),
          SizedBox(
            width: panelWidth,
            child: _buildAnalyticsPanel(
              title: 'Patient Risk Split',
              subtitle: 'Risk-level distribution for filtered patients',
              contentHeight: 250,
              child: _buildRiskDonutChart(),
            ),
          ),
          SizedBox(
            width: panelWidth,
            child: _buildAnalyticsPanel(
              title: '30/60/90 Forecast',
              subtitle: 'Projected service demand from filtered records',
              contentHeight: 250,
              child: _buildForecastChart(),
            ),
          ),
          SizedBox(
            width: panelWidth,
            child: _buildAnalyticsPanel(
              title: 'Coverage Gaps',
              subtitle: 'Data and scheduling backlog in selected window',
              contentHeight: 250,
              child: _buildCoverageGapChart(),
            ),
          ),
          SizedBox(
            width: panelWidth,
            child: _buildAnalyticsPanel(
              title: 'Overdue Follow-up',
              subtitle: 'Priority pressure from filtered patients',
              contentHeight: 250,
              child: _buildOverdueFollowUpChart(),
            ),
          ),
        ];

        return Wrap(spacing: 10, runSpacing: 10, children: panels);
      },
    );
  }

  int _forecastValue(Map<int, int> values, int days) => values[days] ?? 0;

  Color _riskColor(String riskLabel) {
    switch (riskLabel.toLowerCase()) {
      case 'high':
        return Colors.redAccent;
      case 'moderate':
        return Colors.orangeAccent;
      case 'low':
        return Colors.lightGreenAccent;
      default:
        return Colors.blueGrey;
    }
  }

  String _truncateLabel(String value, {int max = 14}) {
    final text = value.trim();
    if (text.length <= max) return text;
    return '${text.substring(0, max - 3)}...';
  }

  Widget _buildForecastChart() {
    final windows = _forecastWindows;
    final checkVals = windows
        .map((day) => _forecastValue(_checkupForecast, day))
        .toList(growable: false);
    final prenatalVals = windows
        .map((day) => _forecastValue(_prenatalForecast, day))
        .toList(growable: false);
    final immunizationVals = windows
        .map((day) => _forecastValue(_immunizationForecast, day))
        .toList(growable: false);
    final allValues = <int>[...checkVals, ...prenatalVals, ...immunizationVals];
    final maxY = _maxFromIntValues(allValues, minimum: 5) * 1.2;
    final interval = ((maxY / 4).clamp(1, maxY)).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: _lightOffWhite.withValues(alpha: 0.12),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(windows.length, (i) {
                return BarChartGroupData(
                  x: i,
                  barsSpace: 4,
                  barRods: [
                    BarChartRodData(
                      toY: checkVals[i].toDouble(),
                      width: 7,
                      color: _secondaryIceBlue,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    BarChartRodData(
                      toY: prenatalVals[i].toDouble(),
                      width: 7,
                      color: Colors.pinkAccent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    BarChartRodData(
                      toY: immunizationVals[i].toDouble(),
                      width: 7,
                      color: Colors.greenAccent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                );
              }),
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
                    reservedSize: 28,
                    interval: interval,
                    getTitlesWidget: (value, _) => Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.65),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, _) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= windows.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${windows[idx]}d',
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.70),
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: const [
            _ChartLegendDot(label: 'Checkups', color: _secondaryIceBlue),
            _ChartLegendDot(label: 'Prenatal', color: Colors.pinkAccent),
            _ChartLegendDot(label: 'Immunization', color: Colors.greenAccent),
          ],
        ),
      ],
    );
  }

  Widget _buildCoverageGapChart() {
    final labels = <String>['>90d', 'No Next', 'Unknown', 'F-up No Date'];
    final values = <int>[
      _coverageNoRecentCheckup,
      _coverageMissingNextCheckup,
      _coverageUnknownRisk,
      _coverageFollowUpNoSchedule,
    ];
    final colors = <Color>[
      Colors.orangeAccent,
      Colors.amberAccent,
      Colors.blueGrey,
      Colors.redAccent,
    ];
    final total = values.fold<int>(0, (sum, v) => sum + v);
    if (total == 0) {
      return Center(
        child: Text(
          'No coverage gaps detected.',
          style: TextStyle(
            color: _lightOffWhite.withValues(alpha: 0.78),
            fontSize: 12,
          ),
        ),
      );
    }

    final maxY = _maxFromIntValues(values, minimum: 5) * 1.2;
    final interval = ((maxY / 4).clamp(1, maxY)).toDouble();

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: _lightOffWhite.withValues(alpha: 0.12),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(values.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: values[i].toDouble(),
                width: 18,
                color: colors[i],
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }),
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
              reservedSize: 28,
              interval: interval,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  color: _lightOffWhite.withValues(alpha: 0.65),
                  fontSize: 10,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx < 0 || idx >= labels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    labels[idx],
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.70),
                      fontSize: 9,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverdueFollowUpChart() {
    final items = _overdueFollowUps.take(6).toList(growable: false);
    if (items.isEmpty) {
      return Center(
        child: Text(
          'No overdue follow-ups detected.',
          style: TextStyle(
            color: _lightOffWhite.withValues(alpha: 0.78),
            fontSize: 12,
          ),
        ),
      );
    }

    final overdueValues = items
        .map((item) => (item['overdueDays'] as int?) ?? 0)
        .toList(growable: false);
    final maxY = _maxFromIntValues(overdueValues, minimum: 5) * 1.2;
    final interval = ((maxY / 4).clamp(1, maxY)).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: _lightOffWhite.withValues(alpha: 0.12),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(items.length, (i) {
                final riskLabel = (items[i]['riskLabel'] ?? 'Unknown')
                    .toString();
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: overdueValues[i].toDouble(),
                      width: 16,
                      color: _riskColor(riskLabel),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                );
              }),
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
                    reservedSize: 28,
                    interval: interval,
                    getTitlesWidget: (value, _) => Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.65),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, _) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= items.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          (idx + 1).toString(),
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.70),
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: List.generate(items.length, (i) {
            final name = _truncateLabel(
              (items[i]['name'] ?? '-').toString(),
              max: 16,
            );
            final riskLabel = (items[i]['riskLabel'] ?? 'Unknown').toString();
            final color = _riskColor(riskLabel);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: color.withValues(alpha: 0.45)),
              ),
              child: Text(
                '${i + 1}. $name',
                style: TextStyle(
                  color: _lightOffWhite.withValues(alpha: 0.88),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_authorized) {
      return Scaffold(
        backgroundColor: _darkDeepTeal,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: _darkDeepTeal,
      drawer: const ChoNavigationDrawer(current: ChoDestination.dashboard),
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.health_and_safety_rounded, color: _primaryAqua),
            SizedBox(width: 10),
            Text(
              'CHO Intelligence Center',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        backgroundColor: _darkDeepTeal,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: ListView(
          children: [
            _buildExecutiveHero(),
            const SizedBox(height: 14),
            _buildOperationalInsights(),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: _secondaryIceBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _primaryAqua.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CHO Dashboard: Firestore-powered patient monitoring, service delivery tracking, and public health risk surveillance.',
                    style: TextStyle(color: _lightOffWhite, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  // Sync status indicator
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _darkDeepTeal.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _syncStatus.values.every((v) => v)
                              ? Icons.cloud_done
                              : Icons.cloud_sync,
                          color: _syncStatus.values.every((v) => v)
                              ? Colors.greenAccent
                              : _primaryAqua,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _syncStatus.values.every((v) => v)
                              ? 'All Firestore collections synced ✓'
                              : 'Syncing Firestore collections...',
                          style: TextStyle(
                            color: _syncStatus.values.every((v) => v)
                                ? Colors.greenAccent
                                : _primaryAqua,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _buildAnalyticsFilterBar(),
            const SizedBox(height: 18),
            const Text(
              'Program Performance Snapshot',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Live service volumes for the active reporting window.',
              style: TextStyle(
                color: _lightOffWhite.withValues(alpha: 0.55),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 280,
                  child: _summaryCard(
                    'Patient Records',
                    _safeMetricText(_totalPatients),
                    Icons.people,
                    _primaryAqua,
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: _summaryCard(
                    'Checkup Records',
                    _safeMetricText(_checkupsThisMonth),
                    Icons.medical_services,
                    _secondaryIceBlue,
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: _summaryCard(
                    'Active Prenatal Cases',
                    _safeMetricText(_activePrenatal),
                    Icons.pregnant_woman,
                    Colors.pinkAccent,
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: _summaryCard(
                    'Immunization Records',
                    _safeMetricText(_immunizationRecords),
                    Icons.vaccines,
                    Colors.greenAccent,
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: _summaryCard(
                    'Morbidity Reports',
                    _safeMetricText(_morbidityReports),
                    Icons.monitor_heart,
                    Colors.orangeAccent,
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: _summaryCard(
                    'Mortality Reports',
                    _safeMetricText(_mortalityReports),
                    Icons.heart_broken,
                    Colors.redAccent,
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: _summaryCard(
                    'Referral Reports',
                    _safeMetricText(_referralReports),
                    Icons.assignment_ind_outlined,
                    Colors.cyanAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildBarangayDemographicsExplorer(),
            const SizedBox(height: 20),
            _buildDoctorAvailabilityPlanner(),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    _primaryAqua.withValues(alpha: 0.15),
                    _secondaryIceBlue.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.stacked_line_chart_rounded,
                      color: _primaryAqua,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Power BI-Style Health Analytics',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Interactive trend, distribution, forecast, workload, and coverage visuals for ${_analyticsWindowLabel().toLowerCase()}.',
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.60),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _buildPowerBiCharts(),
            const SizedBox(height: 20),
            const Text(
              'Population Follow-up Queue',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Patient-level continuity view for scheduling and outreach coordination.',
              style: TextStyle(
                color: _lightOffWhite.withValues(alpha: 0.55),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 10),
            _buildPatientQueueSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Get.back(),
        backgroundColor: _primaryAqua,
        child: const Icon(Icons.arrow_back),
      ),
    );
  }
}
