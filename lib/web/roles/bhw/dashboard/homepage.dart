import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/roles/bhw/checkups/checkup.dart'
    as checkup_page;
import 'package:mycapstone_project/web/roles/bhw/analytics/health_metrics.dart';
import 'package:mycapstone_project/web/roles/cho/analytics/analytics.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal.dart';
import 'package:mycapstone_project/web/roles/bhw/immunization/immunization.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient.dart';
import 'package:mycapstone_project/web/roles/bhw/dashboard/bhw_profile.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/communicable.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/non_communicable.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/mortality.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/shared/components/app_metric_card.dart';
import 'package:mycapstone_project/web/roles/bhw/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal_database_helper.dart';
import 'package:mycapstone_project/web/roles/bhw/immunization/immunization_database_helper.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_database_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/shared/utils/dashboard_report_launcher.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/firebase_helper.dart';

// Professional Vibrant Color Palette - Matching Analytics Page
// Names are historical (page was dark-themed); values now point at the
// white-card system used across the rest of the app.
const Color _primaryAqua = Color(0xFF2F80ED); // Shared dashboard blue
const Color _secondaryIceBlue = Color(0xFF163B66); // Shared deep blue
const Color _darkDeepTeal = Color(0xFFF5F7FA); // page background
const Color _cardBackground = Colors.white; // card background
const Color _mutedCoolGray = Color(0xFF4B6075); // Shared readable gray
const Color _lightOffWhite = Color(0xFF0D274D); // primary text
const Color _sidebarDark = Colors.white; // panel/surface background
const Color _accentPurple = Color(0xFF7C3AED); // Vibrant Purple
const Color _accentGreen = Color(0xFF10B981); // Bright Green
const Color _accentOrange = Color(0xFFFF8C0D); // Vibrant Orange
const Color _accentRed = Color(0xFFEF4444); // Vibrant Red
const Color _brightCyan = Color(0xFF2F80ED); // Shared dashboard blue
const Color _bgDarkTeal = Color(0xFFF5F7FA); // Analytics-aligned background
const Color _offWhiteOpacity = Color(0xFF0D274D); // primary text

class HomePage extends StatefulWidget {
  final User? user;
  const HomePage({super.key, this.user});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final _checkupHelper = DatabaseHelper.instance;
  final _prenatalHelper = PrenatalDatabaseHelper.instance;
  final _immunizationHelper = ImmunizationDatabaseHelper.instance;
  final _patientHelper = PatientDatabaseHelper.instance;

  int _totalPatients = 0;
  int _checkupsThisMonth = 0;
  int _prenatalRecords = 0;
  int _immunizationRecords = 0;
  int _filteredPatientRegistrations = 0;
  int _filteredCheckupRecords = 0;
  int _filteredPrenatalRecords = 0;
  int _filteredImmunizationRecords = 0;
  bool _isLoadingMetrics = true;
  DateTime? _keyMetricsSelectedDate;

  // Disease Trend data
  Map<String, Map<String, int>> _symptomDateData =
      {}; // symptom -> date -> count
  List<LineChartBarData> _chartLines = [];
  Map<String, Color> _symptomColors = {};
  List<String> _allDates = [];
  List<String> _allSymptoms = [];
  bool _isLoadingTrends = true;
  DateTime _trendStartDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _trendEndDate = DateTime.now();
  StreamSubscription<QuerySnapshot>? _morbidityTrendSubscription;
  StreamSubscription<List<Map<String, dynamic>>>?
  _todaysOverviewCheckupSubscription;
  StreamSubscription<QuerySnapshot>? _todaysOverviewPatientSubscription;
  List<Map<String, dynamic>> _latestRealtimeCheckups =
      const <Map<String, dynamic>>[];
  int _realtimePatientCount = 0;
  bool _isLoadingMorbidityTrends = true;
  List<String> _morbidityTrendMonthLabels = const [
    'M1',
    'M2',
    'M3',
    'M4',
    'M5',
    'M6',
  ];
  Map<String, List<int>> _morbidityTrendSeries = const <String, List<int>>{};

  // Notification state
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoadingNotifications = false;

  // Activity Feed & Recent Activity
  List<Map<String, dynamic>> _recentActivity = [];
  List<Map<String, dynamic>> _upcomingAppointments = [];
  int _criticalAlerts = 0;
  int _pendingReviews = 0;
  bool _isLoadingActivity = false;

  // Widget visibility toggles
  final bool _showActivityFeed = true;
  final bool _showUpcomingAppointments = true;
  final bool _showAdvancedFilter = false;
  final bool _showActivityLog = true;

  // Advanced Filter state
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  final String _filterMetricType = 'All';
  final List<String> _metricFilterOptions = [
    'All',
    'Patients',
    'Check-ups',
    'Prenatal',
    'Immunization',
  ];

  // KPI and Today's Overview state.
  // All values below are derived only from scoped, persisted Firestore
  // records (patients/checkups/prenatal/immunizations) — none are
  // synthesized/randomized. See _loadKPIData().
  int _todaysPendingTasks = 0;
  int _patientsCheckedInToday = 0;
  double _prenatalCoverageRate = 0.0;
  double _documentationCompletionRate = 0.0;
  double _immunizationRate = 0.0;
  List<Map<String, dynamic>> _topDiagnoses = [];
  List<Map<String, dynamic>> _healthInsights = [];
  bool _isLoadingKPI = false;

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
  Map<String, int> _referralStatusCounts = const {};
  List<Map<String, dynamic>> _recentHighRiskAlerts = const [];

  @override
  void initState() {
    super.initState();
    _keyMetricsSelectedDate ??= DateTime.now();
    _loadExecutiveOverview();
    _checkAdminInvite();
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
      snapshot = await query.get(
        kIsWeb ? const GetOptions(source: Source.server) : const GetOptions(),
      );
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

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final monthStarts = List<DateTime>.generate(
        6,
        (index) => DateTime(now.year, now.month - (5 - index), 1),
      );
      final monthKeys = monthStarts
          .map((date) => '${date.year}-${date.month}')
          .toList(growable: false);
      final consultationCounts = <String, int>{
        for (final key in monthKeys) key: 0,
      };

      var consultationsToday = 0;
      var aiAlerts = 0;
      final highRiskIdentities = <String>{};
      final highRiskAlerts = <Map<String, dynamic>>[];

      for (final checkup in checkups) {
        final date = _coerceOverviewDate(checkup);
        if (date != null) {
          if (!date.isBefore(today) && date.isBefore(tomorrow)) {
            consultationsToday++;
          }
          final key = '${date.year}-${date.month}';
          if (consultationCounts.containsKey(key)) {
            consultationCounts[key] = consultationCounts[key]! + 1;
          }
        }

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
          if (hasAiGuidance) aiAlerts++;
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

      var activePregnancies = 0;
      for (final record in prenatal) {
        final status = _dashboardText(record, const [
          'status',
          'recordStatus',
        ], fallback: 'active').toLowerCase();
        if (!status.contains('completed') &&
            !status.contains('closed') &&
            !status.contains('inactive')) {
          activePregnancies++;
        }
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
            'timestamp': _coerceOverviewDate(record),
            'source': 'Prenatal',
          });
        }
        final hasAiGuidance = _dashboardText(record, const [
          'ai_category',
          'ai_method',
        ], fallback: '').isNotEmpty;
        if (hasAiGuidance && _isHighRiskValue(riskValue)) {
          aiAlerts++;
        }
      }

      for (final record in morbidity) {
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
            'timestamp': _coerceOverviewDate(record),
            'source': 'Morbidity',
          });
        }
      }

      final referralCounts = <String, int>{};
      var pendingReferrals = 0;
      for (final referral in referrals) {
        final status = _dashboardText(referral, const [
          'status',
          'referralStatus',
        ], fallback: 'Submitted');
        referralCounts[status] = (referralCounts[status] ?? 0) + 1;
        final normalized = status.toLowerCase();
        if (!normalized.contains('completed') &&
            !normalized.contains('closed') &&
            !normalized.contains('cancel')) {
          pendingReferrals++;
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
          final timestamp = _coerceOverviewDate(record);
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
        patients,
        title: 'Patient registered',
        icon: Icons.person_add_alt_1_rounded,
        color: _primaryAqua,
        detailKeys: const ['patientName', 'name'],
      );
      addActivities(
        checkups,
        title: 'Consultation recorded',
        icon: Icons.medical_services_rounded,
        color: _accentGreen,
        detailKeys: const ['patientName', 'patient', 'disease', 'type'],
      );
      addActivities(
        prenatal,
        title: 'Prenatal record updated',
        icon: Icons.pregnant_woman_rounded,
        color: _accentPurple,
        detailKeys: const ['patientName', 'name', 'status'],
      );
      addActivities(
        morbidity,
        title: 'Morbidity case updated',
        icon: Icons.monitor_heart_rounded,
        color: _accentOrange,
        detailKeys: const ['disease', 'condition', 'patientName'],
      );
      addActivities(
        referrals,
        title: 'Referral status updated',
        icon: Icons.assignment_ind_rounded,
        color: const Color(0xFFF59E0B),
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

      if (!mounted) return;
      setState(() {
        _totalPatients = patients.length;
        _consultationsToday = consultationsToday;
        _activePregnancies = activePregnancies;
        _highRiskPatients = highRiskIdentities.length;
        _pendingReferrals = pendingReferrals;
        _aiGeneratedAlerts = aiAlerts;
        _consultationMonthLabels = monthStarts
            .map((date) => _monthLabelShort(date.month))
            .toList(growable: false);
        _monthlyConsultationCounts = monthKeys
            .map((key) => consultationCounts[key] ?? 0)
            .toList(growable: false);
        _referralStatusCounts = referralCounts;
        _recentHighRiskAlerts = highRiskAlerts.take(6).toList(growable: false);
        _recentActivity = systemActivity.take(10).toList(growable: false);
        _isLoadingExecutiveOverview = false;
        _isLoadingActivity = false;
      });
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

  bool _isAdminInvite = false;

  Future<void> _checkAdminInvite() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Primary method: Check ID token claims (works without Firestore read)
      try {
        final idToken = await user.getIdTokenResult(true);
        final claims = idToken.claims ?? {};
        final roleClaim = (claims['role'] ?? '').toString().toLowerCase();
        if (roleClaim.contains('admin')) {
          if (mounted) setState(() => _isAdminInvite = true);
          return;
        }
      } catch (tokenErr) {
        if (kDebugMode) print('Admin check token claim failed: $tokenErr');
      }

      // Secondary method: Try server read without specifying source (allows offline cache)
      try {
        final doc = await getFirestoreInstance()
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 4)); // Reduced from 5 to 4
        final role = (doc.data()?['role'] ?? '').toString().toLowerCase();
        if (role.contains('admin')) {
          if (mounted) setState(() => _isAdminInvite = true);
          return;
        }
      } catch (e) {
        if (kDebugMode) print('Admin check Firestore read failed: $e');
        // Continue to next check if this fails
      }

      // Tertiary method: Try cache explicitly if server fails
      try {
        final cached = await getFirestoreInstance()
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 2)); // Reduced from 2 to 1
        if (cached.exists) {
          final role = (cached.data()?['role'] ?? '').toString().toLowerCase();
          if (role.contains('admin')) {
            if (mounted) setState(() => _isAdminInvite = true);
            return;
          }
        }
      } catch (cacheErr) {
        if (kDebugMode) print('Admin check cache read failed: $cacheErr');
      }

      // If none of the above work, user is not admin
      if (mounted) setState(() => _isAdminInvite = false);
    } catch (e) {
      if (kDebugMode) print('Admin check failed: $e');
      if (mounted) setState(() => _isAdminInvite = false);
    }
  }

  Future<void> _showInviteDialog() async {
    String? email;
    final controller = TextEditingController();
    final emailRegex = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$");

    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Invite user'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'user@example.com'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final value = controller.text.trim();
              if (value.isEmpty) {
                Get.snackbar(
                  'Invalid',
                  'Please enter an email',
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
                return;
              }
              if (!emailRegex.hasMatch(value)) {
                Get.snackbar(
                  'Invalid',
                  'Please enter a valid email address',
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
                return;
              }
              Navigator.of(c).pop();
              await _createInvitation(value);
            },
            child: const Text('Invite'),
          ),
        ],
      ),
    );

    controller.dispose();
  }

  /// Helper method to retry async operations with exponential backoff
  Future<T> _retryOperation<T>({
    required Future<T> Function() operation,
    int maxAttempts = 3,
    Duration initialDelay = const Duration(seconds: 2),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (attempt < maxAttempts) {
      try {
        return await operation();
      } catch (e) {
        attempt++;
        if (attempt >= maxAttempts) {
          rethrow;
        }
        if (kDebugMode) {
          print('Attempt $attempt failed, retrying in ${delay.inSeconds}s: $e');
        }
        await Future.delayed(delay);
        delay = Duration(
          seconds: delay.inSeconds * 2,
        ); // exponential backoff: 2s -> 4s -> 8s
      }
    }
    throw Exception('Operation failed after $maxAttempts attempts');
  }

  Future<void> _createInvitation(String email) async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      // Step 1: Check if user exists in Firebase Auth by attempting to create
      bool userExists = false;
      String? userId;
      try {
        // Try to get user UID from Firestore first
        try {
          final snapshot = await getFirestoreInstance()
              .collection('users')
              .where('email', isEqualTo: email)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 15));
          if (snapshot.docs.isNotEmpty) {
            userId = snapshot.docs.first.id;
            userExists = true;
          }
        } catch (e) {
          if (kDebugMode) print('Could not fetch user UID: $e');
        }
      } catch (e) {
        if (kDebugMode) print('Error checking if user exists: $e');
      }

      // Step 2: If user doesn't exist, create them first
      if (!userExists) {
        try {
          // Generate random temporary password
          final tempPassword =
              'TempPass${DateTime.now().millisecondsSinceEpoch}@Ab1';

          // Create user in Firebase Auth
          final userCredential = await FirebaseAuth.instance
              .createUserWithEmailAndPassword(
                email: email,
                password: tempPassword,
              );
          userId = userCredential.user?.uid;

          if (kDebugMode) print('Created new user: $email with UID: $userId');

          // Write to users collection with role - with retry logic
          if (userId != null) {
            try {
              await _retryOperation(
                operation: () => getFirestoreInstance()
                    .collection('users')
                    .doc(userId)
                    .set({
                      'email': email,
                      'emailLower': email.toLowerCase().trim(),
                      'role': 'CHO',
                      'invitedBy': user?.uid,
                      'invitedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true))
                    .timeout(const Duration(seconds: 20)),
                maxAttempts: 2,
              );
            } catch (firestoreErr) {
              if (kDebugMode) {
                print(
                  'Failed to write user profile after retries: $firestoreErr',
                );
              }
              // Continue anyway - user exists in Auth, just profile write failed
              // We'll try to save it later via Cloud Function
            }
          }
        } catch (createErr) {
          String errorMsg = 'Failed to create user account';
          if (createErr.toString().contains('email-already-in-use')) {
            errorMsg = 'Email already exists in system';
          } else if (createErr.toString().contains('weak-password')) {
            errorMsg = 'Password creation failed';
          } else if (createErr.toString().contains('TimeoutException')) {
            errorMsg =
                'Connection timeout. Please check your network and try again.';
          }

          Get.snackbar(
            'Error',
            errorMsg,
            backgroundColor: Colors.redAccent,
            colorText: Colors.white,
            duration: const Duration(seconds: 6),
          );
          if (kDebugMode) print('Failed to create user: $createErr');
          return;
        }
      }

      // Step 3: Send password reset email (with timeout handling)
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

        // Create invitation record in Firestore for audit trail - non-blocking
        // This happens in background and won't block the main flow
        _createInvitationRecordAsync(email, userId, user?.uid);

        Get.snackbar(
          'Sent',
          'Password reset email sent to $email\nCheck spam folder if not received',
          backgroundColor: Colors.green,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );

        if (kDebugMode) print('Password reset email sent to $email');
      } catch (sendErr) {
        String errorMsg = 'Failed to send password reset email';

        if (sendErr.toString().contains('too-many-requests')) {
          errorMsg = 'Too many requests. Wait a few minutes and try again.';
        } else if (sendErr.toString().contains('user-not-found')) {
          errorMsg = 'User account not found. Please create account first.';
        } else if (sendErr.toString().contains('invalid-email')) {
          errorMsg = 'Invalid email address.';
        } else if (sendErr.toString().contains('network')) {
          errorMsg = 'Network error. Check your connection.';
        } else if (sendErr.toString().contains('TimeoutException')) {
          errorMsg =
              'Connection timeout. Email may still have been sent. Check spam folder.';
        }

        Get.snackbar(
          'Error',
          errorMsg,
          backgroundColor: Colors.redAccent,
          colorText: Colors.white,
          duration: const Duration(seconds: 6),
        );
        if (kDebugMode) print('Failed to send password reset email: $sendErr');
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to process invitation: $e',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
      if (kDebugMode) print('Error in _createInvitation: $e');
    }
  }

  /// Create invitation record asynchronously (non-blocking, fire-and-forget)
  void _createInvitationRecordAsync(
    String email,
    String? userId,
    String? createdBy,
  ) {
    // Fire and forget - don't await this
    getFirestoreInstance()
        .collection('invitations')
        .add({
          'email': email,
          'role': 'CHO',
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': createdBy,
          'status': 'sent',
          'emailSent': true,
          'method': 'password_reset',
          'userId': userId,
        })
        .timeout(const Duration(seconds: 15))
        .then((_) {
          if (kDebugMode) print('Invitation record created successfully');
        })
        .catchError((e) {
          if (kDebugMode) {
            print('Background: Could not create invitation record: $e');
          }
          // Silent fail - not critical to user experience
          return null; // Return a value to satisfy catchError requirement
        });
  }

  Future<void> _loadMetrics() async {
    if (!mounted) return;
    setState(() => _isLoadingMetrics = true);

    try {
      final patients = await _patientHelper.getAllRecords();
      final checkups = await _checkupHelper.getAllRecords();
      final prenatal = await _prenatalHelper.getAllRecords();
      final immunizations = await _immunizationHelper.getAllRecords();

      final now = DateTime.now();
      final checkupsThisMonth = checkups.where((record) {
        try {
          final date = DateTime.parse(record['datetime'] ?? '');
          return date.year == now.year && date.month == now.month;
        } catch (e) {
          return false;
        }
      }).length;
      final filteredPatientRegistrations = patients.where((record) {
        final date = _resolveMetricDate(record, const [
          'registrationDate',
          'createdAt',
        ]);
        return _matchesKeyMetricFilter(date);
      }).length;
      final filteredCheckupRecords = checkups.where((record) {
        final date = _resolveMetricDate(record, const [
          'datetime',
          'date',
          'createdAt',
        ]);
        return _matchesKeyMetricFilter(date);
      }).length;
      final filteredPrenatalRecords = prenatal.where((record) {
        final date = _resolveMetricDate(record, const [
          'registrationDate',
          'dueDate',
          'lmpDate',
          'createdAt',
        ]);
        return _matchesKeyMetricFilter(date);
      }).length;
      final filteredImmunizationRecords = immunizations.where((record) {
        final date = _resolveMetricDate(record, const [
          'administrationDate',
          'date',
          'createdAt',
        ]);
        return _matchesKeyMetricFilter(date);
      }).length;

      if (!mounted) return;
      setState(() {
        _totalPatients = patients.length;
        _checkupsThisMonth = checkupsThisMonth;
        _prenatalRecords = prenatal.length;
        _immunizationRecords = immunizations.length;
        _filteredPatientRegistrations = filteredPatientRegistrations;
        _filteredCheckupRecords = filteredCheckupRecords;
        _filteredPrenatalRecords = filteredPrenatalRecords;
        _filteredImmunizationRecords = filteredImmunizationRecords;
        _isLoadingMetrics = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMetrics = false);
    }
  }

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

  bool _matchesKeyMetricFilter(DateTime? date) {
    if (date == null) return false;
    final selectedDate = _effectiveKeyMetricsSelectedDate;
    return date.year == selectedDate.year && date.month == selectedDate.month;
  }

  String _metricFilterScopeLabel() {
    return 'for ${_formatKeyMetricsSelectedDate()}';
  }

  DateTime get _effectiveKeyMetricsSelectedDate {
    try {
      final dynamic rawValue = _keyMetricsSelectedDate;
      if (rawValue is DateTime) {
        return rawValue;
      }
      if (rawValue != null) {
        final parsed = _coerceMetricDateValue(rawValue);
        if (parsed != null) {
          _keyMetricsSelectedDate = parsed;
          return parsed;
        }
      }
    } catch (_) {}

    final fallback = DateTime.now();
    try {
      _keyMetricsSelectedDate = fallback;
    } catch (_) {}
    return fallback;
  }

  String _formatKeyMetricsSelectedDate() {
    final selectedDate = _effectiveKeyMetricsSelectedDate;
    return _monthYearLabel(selectedDate);
  }

  String _metricCountLabel(Object? value) {
    if (value is num) {
      return value.toInt().toString();
    }
    return '0';
  }

  Widget _buildKeyMetricsDatePickerButton() {
    return OutlinedButton.icon(
      onPressed: _pickKeyMetricsDate,
      style: OutlinedButton.styleFrom(
        foregroundColor: _lightOffWhite,
        side: BorderSide(color: _primaryAqua.withValues(alpha: 0.25)),
        backgroundColor: _primaryAqua.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: const Icon(Icons.calendar_month_rounded, size: 14),
      label: Text(
        _formatKeyMetricsSelectedDate(),
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _pickKeyMetricsDate() async {
    final selectedDate = _effectiveKeyMetricsSelectedDate;
    final picked = await _pickMonthYear(
      initialDate: selectedDate,
      helpText: 'Select month',
    );

    if (picked == null || !mounted) return;
    setState(() => _keyMetricsSelectedDate = _normalizeToMonth(picked));
    _loadMetrics();
  }

  DateTime _normalizeToMonth(DateTime date) {
    return DateTime(date.year, date.month);
  }

  String _monthYearLabel(DateTime date) {
    return '${_monthLabelLong(date.month)} ${date.year}';
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
                backgroundColor: const Color(0xFF0D274D),
                surfaceTintColor: Colors.transparent,
              ),
              colorScheme: Theme.of(context).colorScheme.copyWith(
                brightness: Brightness.dark,
                primary: _primaryAqua,
                onPrimary: Colors.white,
                surface: const Color(0xFF0D274D),
                onSurface: Colors.white,
              ),
              inputDecorationTheme: Theme.of(context).inputDecorationTheme
                  .copyWith(
                    labelStyle: const TextStyle(color: Colors.white70),
                    hintStyle: const TextStyle(color: Colors.white60),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Colors.black.withValues(alpha: 0.2),
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
                        color: Colors.black.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
            );

            return Theme(
              data: dialogTheme,
              child: AlertDialog(
                backgroundColor: const Color(0xFF0D274D),
                title: Text(
                  helpText,
                  style: const TextStyle(color: Colors.white),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: tempMonth,
                      dropdownColor: const Color(0xFF0D274D),
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
                      dropdownColor: const Color(0xFF0D274D),
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

  Future<void> _pickTrendStartMonth() async {
    final picked = await _pickMonthYear(
      initialDate: _trendStartDate,
      helpText: 'Select start month',
    );

    if (picked == null || !mounted) return;

    setState(() {
      _trendStartDate = _normalizeToMonth(picked);
      if (_trendEndDate.isBefore(_trendStartDate)) {
        _trendEndDate = _trendStartDate;
      }
    });
    _loadDiseaseTrends();
  }

  Future<void> _pickTrendEndMonth() async {
    final picked = await _pickMonthYear(
      initialDate: _trendEndDate,
      helpText: 'Select end month',
    );

    if (picked == null || !mounted) return;

    setState(() {
      _trendEndDate = _normalizeToMonth(picked);
      if (_trendEndDate.isBefore(_trendStartDate)) {
        _trendStartDate = _trendEndDate;
      }
    });
    _loadDiseaseTrends();
  }

  DateTime? _coerceOverviewDate(Map<String, dynamic> record) {
    return _coerceTrendDate(record['datetime']) ??
        _coerceTrendDate(record['date']) ??
        _coerceTrendDate(record['createdAt']) ??
        _coerceTrendDate(record['timestamp']);
  }

  void _startTodaysOverviewRealtimeSync() {
    _todaysOverviewCheckupSubscription?.cancel();
    _todaysOverviewPatientSubscription?.cancel();

    _todaysOverviewCheckupSubscription = _checkupHelper
        .getRecordsStream()
        .listen(
          (records) {
            _latestRealtimeCheckups = records;
            _recomputeTodaysOverviewMetrics();
          },
          onError: (e) {
            if (kDebugMode) print('Today overview checkup sync error: $e');
          },
        );

    if (kIsWeb) {
      unawaited(_startTodaysOverviewPatientSync());
    }
  }

  Future<void> _startTodaysOverviewPatientSync() async {
    final accessScope = await UserAccessScopeService.instance
        .loadCurrentScope();
    _todaysOverviewPatientSubscription =
        buildScopedRecordQuery(
          getFirestoreInstance(),
          'patient_records',
          accessScope,
        ).snapshots().listen(
          (snapshot) {
            _realtimePatientCount = snapshot.docs.length;
            _recomputeTodaysOverviewMetrics();
          },
          onError: (e) {
            if (kDebugMode) print('Today overview patient sync error: $e');
          },
        );
  }

  void _recomputeTodaysOverviewMetrics() {
    if (!mounted) return;

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startOfNextDay = startOfDay.add(const Duration(days: 1));

    var todayCheckins = 0;
    var checkupsThisMonth = 0;
    var pendingReviews = 0;

    for (final checkup in _latestRealtimeCheckups) {
      final date = _coerceOverviewDate(checkup);
      if (date != null) {
        if (!date.isBefore(startOfDay) && date.isBefore(startOfNextDay)) {
          todayCheckins++;
        }
        if (date.year == now.year && date.month == now.month) {
          checkupsThisMonth++;
        }
      }

      if ((checkup['notes'] ?? '').toString().trim().isEmpty) {
        pendingReviews++;
      }
    }

    final patientCount = _realtimePatientCount > 0
        ? _realtimePatientCount
        : _totalPatients;

    var criticalAlerts = 0;
    if (patientCount > 0 && checkupsThisMonth < (patientCount ~/ 10)) {
      criticalAlerts++;
    }

    setState(() {
      _patientsCheckedInToday = todayCheckins;
      _pendingReviews = pendingReviews;
      _criticalAlerts = criticalAlerts;
      _todaysPendingTasks = pendingReviews + criticalAlerts;
      _checkupsThisMonth = checkupsThisMonth;
      if (_realtimePatientCount > 0) {
        _totalPatients = _realtimePatientCount;
      }
    });
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

  bool _isWholeAxisTick(double value) {
    return (value - value.roundToDouble()).abs() < 0.001;
  }

  void _startMorbidityTrendSync() {
    _morbidityTrendSubscription?.cancel();
    if (mounted) {
      setState(() => _isLoadingMorbidityTrends = true);
    }

    unawaited(_startScopedMorbidityTrendSync());
  }

  Future<void> _startScopedMorbidityTrendSync() async {
    final accessScope = await UserAccessScopeService.instance
        .loadCurrentScope();
    _morbidityTrendSubscription =
        buildScopedRecordQuery(
          getFirestoreInstance(),
          'morbidity_records',
          accessScope,
        ).snapshots().listen(
          (snap) {
            if (!mounted) return;
            final now = DateTime.now();
            final monthStarts = List<DateTime>.generate(
              6,
              (index) => DateTime(now.year, now.month - (5 - index), 1),
            );
            final monthKeys = monthStarts
                .map((d) => '${d.year}-${d.month.toString().padLeft(2, '0')}')
                .toList(growable: false);
            final monthLabels = monthStarts
                .map((d) => _monthLabelShort(d.month))
                .toList(growable: false);

            final diseaseTotals = <String, int>{};
            final monthlyDiseaseCounts = <String, Map<String, int>>{};

            for (final doc in snap.docs) {
              final data = doc.data();
              final diseaseRaw =
                  (data['disease'] ??
                          data['diagnosis'] ??
                          data['condition'] ??
                          '')
                      .toString()
                      .trim();
              final disease = diseaseRaw.isEmpty ? 'Unknown' : diseaseRaw;

              DateTime? date = _coerceTrendDate(data['dateReported']);
              date ??= _coerceTrendDate(data['date']);
              date ??= _coerceTrendDate(data['createdAt']);
              date ??= _coerceTrendDate(data['datetime']);
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
              final monthCounts =
                  monthlyDiseaseCounts[disease] ?? <String, int>{};
              trendSeries[disease] = monthKeys
                  .map((key) => monthCounts[key] ?? 0)
                  .toList(growable: false);
            }

            setState(() {
              _morbidityTrendMonthLabels = monthLabels;
              _morbidityTrendSeries = trendSeries;
              _isLoadingMorbidityTrends = false;
            });
          },
          onError: (e) {
            if (kDebugMode) print('Morbidity trend sync error: $e');
            if (!mounted) return;
            setState(() {
              _morbidityTrendMonthLabels = const [
                'M1',
                'M2',
                'M3',
                'M4',
                'M5',
                'M6',
              ];
              _morbidityTrendSeries = const <String, List<int>>{};
              _isLoadingMorbidityTrends = false;
            });
          },
        );
  }

  Future<void> _loadDiseaseTrends() async {
    setState(() {
      _isLoadingTrends = true;
    });

    try {
      final checkups = await _checkupHelper.getAllRecords();
      final symptomDateMap =
          <String, Map<String, int>>{}; // symptom -> date -> count

      // List of all medical keywords to detect
      final allSymptoms = {
        'fever',
        'cough',
        'flu',
        'cold',
        'infection',
        'tuberculosis',
        'dengue',
        'covid',
        'measles',
        'chickenpox',
        'pneumonia',
        'chest pain',
        'difficulty breathing',
        'severe bleeding',
        'unconscious',
        'seizure',
        'stroke',
        'heart attack',
        'diabetes',
        'hypertension',
        'asthma',
        'arthritis',
        'cancer',
        'thyroid',
        'cholesterol',
        'obesity',
        'pregnant',
        'pregnancy',
        'prenatal',
        'antenatal',
        'maternal',
        'infant',
        'child',
        'baby',
        'newborn',
        'toddler',
      };

      // Initialize symptom maps
      for (var symptom in allSymptoms) {
        symptomDateMap[symptom] = {};
      }

      final normalizedStart = _normalizeToMonth(_trendStartDate);
      final normalizedEnd = _normalizeToMonth(_trendEndDate);
      final startBoundary = normalizedStart.isAfter(normalizedEnd)
          ? normalizedEnd
          : normalizedStart;
      final endBoundaryMonth = normalizedStart.isAfter(normalizedEnd)
          ? normalizedStart
          : normalizedEnd;
      final endBoundaryExclusive = DateTime(
        endBoundaryMonth.year,
        endBoundaryMonth.month + 1,
      );

      // Extract symptoms by date for each individual symptom
      for (var record in checkups) {
        try {
          final datetime = DateTime.parse(record['datetime'] ?? '');
          if (!datetime.isBefore(startBoundary) &&
              datetime.isBefore(endBoundaryExclusive)) {
            final dateStr =
                '${datetime.month.toString().padLeft(2, '0')}-${datetime.day.toString().padLeft(2, '0')}';

            final symptoms = (record['symptoms'] ?? '')
                .toString()
                .toLowerCase();
            final details = (record['details'] ?? '').toString().toLowerCase();
            final type = (record['type'] ?? '').toString().toLowerCase();
            final combinedText = '$symptoms $details $type';

            // Track each symptom individually
            for (var symptom in allSymptoms) {
              if (combinedText.contains(symptom)) {
                symptomDateMap[symptom]![dateStr] =
                    (symptomDateMap[symptom]![dateStr] ?? 0) + 1;
              }
            }
          }
        } catch (e) {
          print('Error processing record: $e');
          continue;
        }
      }

      // Get all unique dates
      final allDatesSet = <String>{};
      for (var symptom in allSymptoms) {
        allDatesSet.addAll(symptomDateMap[symptom]!.keys);
      }
      final sortedDates = allDatesSet.toList()..sort();

      // Only keep symptoms that have data
      final symptomsWithData = <String>[];
      for (var symptom in allSymptoms) {
        if (symptomDateMap[symptom]!.isNotEmpty) {
          symptomsWithData.add(symptom);
        }
      }

      if (sortedDates.isEmpty || symptomsWithData.isEmpty) {
        if (mounted) {
          setState(() {
            _symptomDateData = {};
            _chartLines = [];
            _allDates = [];
            _allSymptoms = [];
            _isLoadingTrends = false;
          });
        }
        return;
      }

      // Generate color for each symptom - Enhanced vibrant palette
      final colors = [
        const Color(0xFF00D4FF), // bright cyan
        const Color(0xFFFF4757), // vibrant red
        const Color(0xFF2ED8B6), // bright teal
        const Color(0xFFFFC107), // golden yellow
        const Color(0xFF00E5A0), // bright mint
        const Color(0xFF9D84FF), // vibrant lavender
        const Color(0xFFFF6B9D), // bright pink
        const Color(0xFF1FB871), // bright green
      ];

      final symptomColors = <String, Color>{};
      for (var i = 0; i < symptomsWithData.length; i++) {
        symptomColors[symptomsWithData[i]] = colors[i % colors.length];
      }

      // Create line chart bars for each symptom
      final chartLines = <LineChartBarData>[];
      for (var symptom in symptomsWithData) {
        final spots = <FlSpot>[];
        for (var i = 0; i < sortedDates.length; i++) {
          final count = symptomDateMap[symptom]![sortedDates[i]] ?? 0;
          spots.add(FlSpot(i.toDouble(), count.toDouble()));
        }

        final color = symptomColors[symptom]!;
        chartLines.add(
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 3.5,
                  color: color,
                  strokeWidth: 1.5,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.10),
            ),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _symptomDateData = symptomDateMap;
          _chartLines = chartLines;
          _symptomColors = symptomColors;
          _allDates = sortedDates;
          _allSymptoms = symptomsWithData;
          _isLoadingTrends = false;
        });
      }
    } catch (e) {
      print('Error loading disease trends: $e');
      if (mounted) {
        setState(() {
          _isLoadingTrends = false;
        });
      }
    }
  }

  Future<void> _loadRecentActivity() async {
    if (!mounted) return;
    setState(() => _isLoadingActivity = true);

    try {
      final checkups = await _checkupHelper.getAllRecords();
      final patients = await _patientHelper.getAllRecords();
      final prenatal = await _prenatalHelper.getAllRecords();
      final immunizations = await _immunizationHelper.getAllRecords();

      List<Map<String, dynamic>> activity = [];
      int alerts = 0;
      int reviews = 0;

      // Add recent checkups
      final sortedCheckups = checkups.toList()
        ..sort((a, b) {
          try {
            return DateTime.parse(
              b['datetime'] ?? '0',
            ).compareTo(DateTime.parse(a['datetime'] ?? '0'));
          } catch (e) {
            return 0;
          }
        });

      for (
        var i = 0;
        i < (sortedCheckups.length > 5 ? 5 : sortedCheckups.length);
        i++
      ) {
        activity.add({
          'type': 'checkup',
          'title': 'Patient Check-up',
          'subtitle': sortedCheckups[i]['type'] ?? 'Regular Check-up',
          'timestamp':
              sortedCheckups[i]['datetime'] ?? DateTime.now().toString(),
          'icon': Icons.assignment_turned_in_rounded,
          'color': _primaryAqua,
        });
      }

      // Add recent prenatal records
      for (var i = 0; i < (prenatal.length > 2 ? 2 : prenatal.length); i++) {
        activity.add({
          'type': 'prenatal',
          'title': 'Prenatal Record',
          'subtitle': 'New prenatal care entry',
          'timestamp': prenatal[i]['timestamp'] ?? DateTime.now().toString(),
          'icon': Icons.pregnant_woman_rounded,
          'color': _accentRed,
        });
      }

      // Check for pending reviews
      reviews = checkups
          .where((c) => (c['notes'] ?? '').toString().isEmpty)
          .length;

      // Check for alerts
      if (patients.length > (_totalPatients + 20)) {
        alerts++;
      }
      if (_checkupsThisMonth < (_totalPatients ~/ 10)) {
        alerts++;
      }

      // Add upcoming appointments (mock data - last 5 patients)
      List<Map<String, dynamic>> upcomingAppts = [];
      for (var i = 0; i < (patients.length > 5 ? 5 : patients.length); i++) {
        final appointmentDate = DateTime.now().add(Duration(days: (i + 1) * 2));
        upcomingAppts.add({
          'patientName': patients[i]['name'] ?? 'Patient ${i + 1}',
          'type': 'Routine Check-up',
          'date':
              '${appointmentDate.month}/${appointmentDate.day}/${appointmentDate.year}',
          'time': '${(9 + (i % 8))}:00 AM',
          'status': i % 3 == 0 ? 'Confirmed' : 'Pending',
        });
      }

      if (!mounted) return;
      setState(() {
        _recentActivity = activity;
        _upcomingAppointments = upcomingAppts;
        _criticalAlerts = alerts;
        _pendingReviews = reviews;
        _isLoadingActivity = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingActivity = false);
    }
  }

  Future<void> _generateNotifications() async {
    if (!mounted) return;
    setState(() => _isLoadingNotifications = true);

    try {
      final patients = await _patientHelper.getAllRecords();
      final checkups = await _checkupHelper.getAllRecords();
      final prenatal = await _prenatalHelper.getAllRecords();
      final immunizations = await _immunizationHelper.getAllRecords();

      List<Map<String, dynamic>> notifications = [];

      // System Status Notification
      notifications.add({
        'title': 'System Status',
        'message': 'All systems operational',
        'type': 'info',
        'icon': Icons.check_circle_outline,
        'color': _accentGreen,
        'timestamp': DateTime.now(),
      });

      // Patient Check-up Reminder
      if (_totalPatients > 0 && _checkupsThisMonth < _totalPatients ~/ 5) {
        notifications.add({
          'title': 'Check-up Reminder',
          'message':
              'Only $_checkupsThisMonth check-ups completed this month. Consider scheduling more.',
          'type': 'warning',
          'icon': Icons.warning_amber,
          'color': _accentOrange,
          'timestamp': DateTime.now().subtract(const Duration(minutes: 5)),
        });
      }

      // Prenatal Care Alert
      if (_prenatalRecords > 0) {
        notifications.add({
          'title': 'Prenatal Care Update',
          'message': '$_prenatalRecords active prenatal records in system',
          'type': 'info',
          'icon': Icons.pregnant_woman_rounded,
          'color': _accentRed,
          'timestamp': DateTime.now().subtract(const Duration(minutes: 15)),
        });
      }

      // Immunization Update
      if (_immunizationRecords > 0) {
        notifications.add({
          'title': 'Immunization Records',
          'message': '$_immunizationRecords immunizations administered',
          'type': 'success',
          'icon': Icons.vaccines_rounded,
          'color': _accentGreen,
          'timestamp': DateTime.now().subtract(const Duration(hours: 1)),
        });
      }

      // Patient Count Alert
      if (_totalPatients > 100) {
        notifications.add({
          'title': 'High Patient Load',
          'message':
              'System has $_totalPatients patients registered. Monitor workload.',
          'type': 'info',
          'icon': Icons.people_rounded,
          'color': _primaryAqua,
          'timestamp': DateTime.now().subtract(const Duration(hours: 2)),
        });
      }

      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _isLoadingNotifications = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingNotifications = false);
    }
  }

  Future<void> _loadKPIData() async {
    if (!mounted) return;
    setState(() => _isLoadingKPI = true);

    try {
      final checkups = await _checkupHelper.getAllRecords();
      final patients = await _patientHelper.getAllRecords();
      final prenatal = await _prenatalHelper.getAllRecords();
      final immunizations = await _immunizationHelper.getAllRecords();

      // Calculate today's metrics
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);

      int todayCheckups = 0;
      for (var checkup in checkups) {
        try {
          final date = DateTime.parse(checkup['datetime'] ?? '');
          if (date.isAfter(startOfDay) && date.isBefore(endOfDay)) {
            todayCheckups++;
          }
        } catch (e) {
          // Ignore parse errors
        }
      }

      // Calculate top diagnoses (mock data based on existing records)
      Map<String, int> diagnosisCount = {};
      for (var checkup in checkups) {
        final type = checkup['type'] ?? 'General';
        diagnosisCount[type] = (diagnosisCount[type] ?? 0) + 1;
      }

      List<Map<String, dynamic>> topDiagnoses =
          diagnosisCount.entries
              .map((e) => {'name': e.key, 'count': e.value})
              .toList()
            ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
      topDiagnoses = topDiagnoses.take(5).toList();

      // Generate health insights
      List<Map<String, dynamic>> insights = [];

      if (prenatal.isNotEmpty &&
          (prenatal.length / patients.length * 100) > 5) {
        insights.add({
          'icon': Icons.trending_up,
          'title': 'Prenatal Cases Growing',
          'message':
              'Prenatal cases up ${((prenatal.length / patients.length * 100).toStringAsFixed(0))}% - consider resource allocation',
          'severity': 'info',
        });
      }

      final immunizationRate = immunizations.isNotEmpty
          ? (immunizations.length / patients.length * 100)
          : 0.0;
      if (immunizationRate > 85) {
        insights.add({
          'icon': Icons.vaccines_outlined,
          'title': 'Immunization Rate Strong',
          'message':
              'Immunization rate at ${immunizationRate.toStringAsFixed(1)}% - continue current strategy',
          'severity': 'success',
        });
      }

      if (checkups.isEmpty || (checkups.length / patients.length < 0.2)) {
        insights.add({
          'icon': Icons.warning_amber_rounded,
          'title': 'Low Check-up Activity',
          'message': 'Consider increasing outreach and scheduling campaigns',
          'severity': 'warning',
        });
      }

      // Prenatal coverage: share of registered patients with a prenatal
      // record on file. Same real-data shape as the immunization rate above.
      final prenatalCoverageRate = patients.isNotEmpty
          ? (prenatal.length / patients.length * 100)
          : 0.0;

      // Documentation completion: share of check-up records that have
      // clinical notes recorded, mirroring the "pending review" business
      // rule used elsewhere in this file (checkups with empty notes are
      // treated as awaiting follow-up documentation).
      final documentedCheckups = checkups
          .where((c) => (c['notes'] ?? '').toString().trim().isNotEmpty)
          .length;
      final documentationCompletionRate = checkups.isNotEmpty
          ? (documentedCheckups / checkups.length * 100)
          : 0.0;

      if (!mounted) return;
      setState(() {
        _todaysPendingTasks = (_criticalAlerts + _pendingReviews);
        _patientsCheckedInToday = todayCheckups;
        _prenatalCoverageRate = prenatalCoverageRate;
        _documentationCompletionRate = documentationCompletionRate;
        _immunizationRate = immunizationRate;
        _topDiagnoses = topDiagnoses;
        _healthInsights = insights;
        _isLoadingKPI = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingKPI = false);
    }
  }

  void _showNotificationsPanel(BuildContext context) {
    _generateNotifications();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.notifications_active, color: Colors.white),
            SizedBox(width: 12),
            Text('Notifications'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: _isLoadingNotifications
              ? const Center(child: CircularProgressIndicator())
              : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notifications_off,
                        size: 64,
                        color: _lightOffWhite,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No notifications',
                        style: TextStyle(color: _lightOffWhite),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) {
                    final notif = _notifications[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: (notif['color'] as Color).withValues(
                            alpha: 0.3,
                          ),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: (notif['color'] as Color).withValues(
                          alpha: 0.05,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: (notif['color'] as Color).withValues(
                                    alpha: 0.2,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  notif['icon'] as IconData,
                                  color: _lightOffWhite,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  notif['title'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            notif['message'] as String,
                            style: TextStyle(
                              fontSize: 13,
                              color: _lightOffWhite.withValues(alpha: 0.9),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatTime(notif['timestamp'] as DateTime),
                            style: TextStyle(
                              fontSize: 11,
                              color: _lightOffWhite.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: _generateNotifications,
            style: ElevatedButton.styleFrom(backgroundColor: _primaryAqua),
            child: const Text(
              'Refresh',
              style: TextStyle(color: _darkDeepTeal),
            ),
          ),
        ],
      ),
    );
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
      drawer: WebAppSidebar(
        userName: userName,
        activeItem: WebSidebarItem.dashboard,
      ),
      body: Column(
        children: [
          // Header Section
          Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(color: const Color(0xFF071A33)),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  color: Colors.white,
                  iconSize: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'BHW Dashboard',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _isLoadingExecutiveOverview
                      ? null
                      : _loadExecutiveOverview,
                  tooltip: 'Refresh executive overview',
                  icon: const Icon(Icons.refresh_rounded),
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      showOverallHealthReportDialog(context: context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                    backgroundColor: _sidebarDark.withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: const Text(
                    'Generate Overall PDF',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          // Main Content Area - Two Column Layout for Web
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome - Full Width
                  _buildWelcomeCard(userName),
                  const SizedBox(height: 24),
                  if (_executiveOverviewError != null)
                    _buildExecutiveOverviewError()
                  else ...[
                    _buildExecutiveKpiGrid(),
                    const SizedBox(height: 28),
                    _buildExecutiveAnalytics(),
                  ],
                ],
              ),
            ),
          ),
        ],
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

  void _showSettingsDialog() {
    final user = FirebaseAuth.instance.currentUser;
    final userEmail = user?.email ?? 'No email connected';
    final hasAdminTools = _isAdminInvite || kDebugMode;
    final displayName = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!.trim()
        : (userEmail.contains('@')
              ? userEmail.split('@').first
              : 'Health Worker');
    final avatarLetter = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : 'H';

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (dialogContext) {
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final dialogWidth = screenWidth < 680 ? screenWidth * 0.92 : 580.0;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: dialogWidth),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  colors: [_sidebarDark, _darkDeepTeal],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: _lightOffWhite.withValues(alpha: 0.08),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 28,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              colors: [_primaryAqua, _secondaryIceBlue],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Icon(
                            Icons.settings_suggest_rounded,
                            color: _lightOffWhite,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Workspace Settings',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: _lightOffWhite,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Manage your dashboard access, account actions, and session controls from one place.',
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.45,
                                  color: _lightOffWhite.withValues(alpha: 0.72),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: _lightOffWhite.withValues(alpha: 0.85),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: _lightOffWhite.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [_primaryAqua, _secondaryIceBlue],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              avatarLetter,
                              style: const TextStyle(
                                color: _lightOffWhite,
                                fontSize: 24,
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
                                  displayName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: _lightOffWhite,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  userEmail,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _lightOffWhite.withValues(
                                      alpha: 0.72,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _buildSettingsMetaChip(
                                      label: hasAdminTools
                                          ? 'Administrator Access'
                                          : 'BHW Session',
                                      color: hasAdminTools
                                          ? _accentOrange
                                          : _primaryAqua,
                                    ),
                                    _buildSettingsMetaChip(
                                      label: 'Web Dashboard',
                                      color: _accentGreen,
                                    ),
                                    _buildSettingsMetaChip(
                                      label: 'Session Protected',
                                      color: _accentPurple,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _buildSettingsSectionLabel('Quick Actions'),
                    const SizedBox(height: 12),
                    _buildSettingsActionCard(
                      icon: Icons.person_outline_rounded,
                      title: 'Profile overview',
                      subtitle:
                          'Review your current account identity and dashboard session details.',
                      color: _primaryAqua,
                      badge: 'Account',
                      onTap: () async {
                        Navigator.of(dialogContext).pop();
                        await Get.toNamed(WebRoutes.bhwProfile);
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildSettingsActionCard(
                      icon: Icons.verified_user_rounded,
                      title: 'Security status',
                      subtitle:
                          'Your workspace is authenticated and protected through Firebase session controls.',
                      color: _accentGreen,
                      badge: 'Secure',
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        _showSettingsSnack(
                          'Security status',
                          'Your session is active and protected.',
                        );
                      },
                    ),
                    if (hasAdminTools) ...[
                      const SizedBox(height: 22),
                      _buildSettingsSectionLabel('Admin Tools'),
                      const SizedBox(height: 12),
                      _buildSettingsActionCard(
                        icon: Icons.person_add_alt_1_rounded,
                        title: 'Invite CHO account',
                        subtitle:
                            'Send access to another city health office user directly from this workspace.',
                        color: _accentOrange,
                        badge: 'Admin',
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          _showInviteDialog();
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildSettingsActionCard(
                        icon: Icons.admin_panel_settings_rounded,
                        title: 'Manage roles',
                        subtitle:
                            'Open the role manager to review permissions and account assignments.',
                        color: _accentPurple,
                        badge: 'Access',
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          Get.toNamed(WebRoutes.choRoleManager);
                        },
                      ),
                    ],
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _primaryAqua.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _primaryAqua.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.shield_moon_rounded,
                            color: _primaryAqua,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Use settings for account and access actions only. Clinical dashboard data and live metrics remain unchanged while this panel is open.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: _lightOffWhite.withValues(alpha: 0.82),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _lightOffWhite,
                              side: BorderSide(
                                color: _lightOffWhite.withValues(alpha: 0.18),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text('Close'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              Navigator.of(dialogContext).pop();
                              await FirebaseAuth.instance.signOut();
                              Get.offAllNamed(WebRoutes.login);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accentRed,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text('Sign out'),
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
    );
  }

  void _showSettingsSnack(String title, String message) {
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: _sidebarDark.withValues(alpha: 0.96),
      colorText: Colors.white,
      borderRadius: 14,
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    );
  }

  Widget _buildSettingsSectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
        color: _lightOffWhite.withValues(alpha: 0.56),
      ),
    );
  }

  Widget _buildSettingsMetaChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.black.withValues(alpha: 0.92),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSettingsActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _lightOffWhite.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _lightOffWhite,
                            ),
                          ),
                        ),
                        if (badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: _lightOffWhite.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: _lightOffWhite.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildWebSectionHeader(
          title: 'Key Performance Metrics',
          icon: Icons.trending_up_rounded,
          trailing: _buildKeyMetricsDatePickerButton(),
          onRefresh: _loadMetrics,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100
                ? 4
                : constraints.maxWidth >= 680
                ? 2
                : 1;
            const spacing = 16.0;
            final width = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - spacing * (columns - 1)) / columns;
            final cards = <Widget>[
              _buildWebMetricCard(
                title: 'Total Patients',
                value: _isLoadingMetrics
                    ? '...'
                    : _metricCountLabel(_filteredPatientRegistrations),
                subtitle: 'Registered ${_metricFilterScopeLabel()}',
                icon: Icons.people_outline,
              ),
              _buildWebMetricCard(
                title: 'Check-ups',
                value: _isLoadingMetrics
                    ? '...'
                    : _metricCountLabel(_filteredCheckupRecords),
                subtitle: 'Completed ${_metricFilterScopeLabel()}',
                icon: Icons.assignment_turned_in_outlined,
              ),
              _buildWebMetricCard(
                title: 'Prenatal Care',
                value: _isLoadingMetrics
                    ? '...'
                    : _metricCountLabel(_filteredPrenatalRecords),
                subtitle: 'Visits recorded ${_metricFilterScopeLabel()}',
                icon: Icons.pregnant_woman_outlined,
              ),
              _buildWebMetricCard(
                title: 'Immunizations',
                value: _isLoadingMetrics
                    ? '...'
                    : _metricCountLabel(_filteredImmunizationRecords),
                subtitle: 'Administered ${_metricFilterScopeLabel()}',
                icon: Icons.vaccines_outlined,
              ),
            ];
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: cards
                  .map((card) => SizedBox(width: width, child: card))
                  .toList(growable: false),
            );
          },
        ),
      ],
    );
  }

  Widget _buildExecutiveOverviewError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _accentRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accentRed.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: _accentRed, size: 40),
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
            style: TextStyle(color: Colors.black.withValues(alpha: 0.68)),
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

  Widget _buildExecutiveKpiGrid() {
    final metrics = <Map<String, dynamic>>[
      {
        'title': 'Total Registered Patients',
        'value': _totalPatients,
        'subtitle': 'Visible in your access scope',
        'icon': Icons.groups_2_rounded,
      },
      {
        'title': 'Consultations Today',
        'value': _consultationsToday,
        'subtitle': 'Check-ups recorded today',
        'icon': Icons.medical_services_rounded,
      },
      {
        'title': 'Active Pregnancies',
        'value': _activePregnancies,
        'subtitle': 'Open prenatal care records',
        'icon': Icons.pregnant_woman_rounded,
      },
      {
        'title': 'High-risk Patients',
        'value': _highRiskPatients,
        'subtitle': 'Unique patients requiring attention',
        'icon': Icons.warning_amber_rounded,
      },
      {
        'title': 'Pending Referrals',
        'value': _pendingReferrals,
        'subtitle': 'Not completed or closed',
        'icon': Icons.assignment_late_rounded,
      },
      {
        'title': 'AI-generated Alerts',
        'value': _aiGeneratedAlerts,
        'subtitle': 'AI-guided records requiring attention',
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
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: metrics.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: columns == 1 ? 2.0 : 1.55,
              ),
              itemBuilder: (context, index) {
                final metric = metrics[index];
                return _buildWebMetricCard(
                  title: metric['title'] as String,
                  value: _isLoadingExecutiveOverview
                      ? '...'
                      : '${metric['value']}',
                  subtitle: metric['subtitle'] as String,
                  icon: metric['icon'] as IconData,
                );
              },
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
                        color: Colors.black.withValues(alpha: 0.58),
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
              color: Colors.black.withValues(alpha: 0.35),
              size: 34,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black.withValues(alpha: 0.55)),
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
      title: 'Monthly Consultation Trend',
      subtitle: 'Check-up volume during the last six months',
      icon: Icons.show_chart_rounded,
      child: counts.isEmpty
          ? _buildNoExecutiveData('No consultation history is available.')
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
                      color: Colors.black.withValues(alpha: 0.08),
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
                            color: Colors.black.withValues(alpha: 0.5),
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
                                color: Colors.black.withValues(alpha: 0.62),
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
                          backgroundColor: Colors.black.withValues(alpha: 0.08),
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
                    color: _accentRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _accentRed.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.priority_high_rounded,
                        color: _accentRed,
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
                                color: Colors.black.withValues(alpha: 0.62),
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
                              color: _accentRed,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (date != null)
                            Text(
                              _formatTime(date),
                              style: TextStyle(
                                color: Colors.black.withValues(alpha: 0.42),
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
      _buildRecentHighRiskAlerts(),
      _buildDistributionPanel(
        title: 'Referral Status Summary',
        subtitle: 'Current workflow status of submitted referrals',
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

  Widget _buildDrawer(BuildContext context, String userName) {
    final user = FirebaseAuth.instance.currentUser;
    return Drawer(
      child: Container(
        decoration: const BoxDecoration(color: _sidebarDark),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: 20.0,
                horizontal: 16.0,
              ),
              decoration: BoxDecoration(color: _secondaryIceBlue),
              child: Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.transparent, width: 2),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/bg3.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: _lightOffWhite,
                            child: Icon(
                              Icons.person,
                              size: 35,
                              color: _lightOffWhite,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    userName,
                    style: const TextStyle(
                      color: _lightOffWhite,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.email ?? '',
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.9),
                      fontSize: 11,
                      letterSpacing: 0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: _accentGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Online',
                          style: TextStyle(
                            color: _lightOffWhite,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _primaryAqua,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'MAIN MENU',
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.5),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 10,
                ),
                children: [
                  _buildDrawerSidebarItem(
                    icon: Icons.dashboard_rounded,
                    label: 'Dashboard',
                    onTap: () {
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerSidebarItem(
                    icon: Icons.assignment_turned_in_rounded,
                    label: 'Check-ups',
                    onTap: () => Get.toNamed(WebRoutes.bhwCheckups),
                  ),
                  _buildDrawerSidebarItem(
                    icon: Icons.favorite_rounded,
                    label: 'Summary Generation',
                    onTap: () => Get.toNamed(WebRoutes.bhwSummary),
                  ),
                  _buildDrawerSidebarItem(
                    icon: Icons.analytics_rounded,
                    label: 'Analytics',
                    onTap: () => Get.toNamed(WebRoutes.bhwAnalytics),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _primaryAqua,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'PATIENT CARE',
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.5),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildDrawerSidebarItem(
                    icon: Icons.pregnant_woman_rounded,
                    label: 'Prenatal Care',
                    onTap: () => Get.toNamed(WebRoutes.bhwPrenatal),
                  ),
                  _buildDrawerSidebarItem(
                    icon: Icons.vaccines_rounded,
                    label: 'Immunization',
                    onTap: () => Get.toNamed(WebRoutes.bhwImmunization),
                  ),
                  _buildDrawerSidebarItem(
                    icon: Icons.person_rounded,
                    label: 'Patient Records',
                    onTap: () => Get.toNamed(WebRoutes.bhwPatients),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _primaryAqua,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'DISEASE TRACKING',
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.5),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildDrawerSidebarItem(
                    icon: Icons.coronavirus_rounded,
                    label: 'Communicable',
                    onTap: () => Get.toNamed(WebRoutes.bhwCommunicable),
                  ),
                  _buildDrawerSidebarItem(
                    icon: Icons.health_and_safety_rounded,
                    label: 'Non-Communicable',
                    onTap: () => Get.toNamed(WebRoutes.bhwNonCommunicable),
                  ),
                  _buildDrawerSidebarItem(
                    icon: Icons.analytics_outlined,
                    label: 'Mortality',
                    onTap: () => Get.toNamed(WebRoutes.bhwMortality),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Colors.black.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    Get.offAllNamed(WebRoutes.login);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.red.shade600, Colors.red.shade700],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          color: _lightOffWhite,
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Logout',
                          style: TextStyle(
                            color: _lightOffWhite,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerSidebarItem({
    required IconData icon,
    required String label,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.black.withValues(alpha: 0.08),
          splashColor: _primaryAqua.withValues(alpha: 0.2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              gradient: isActive
                  ? LinearGradient(
                      colors: [
                        _primaryAqua.withValues(alpha: 0.15),
                        _primaryAqua.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(
                  color: isActive ? _primaryAqua : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isActive
                        ? _primaryAqua.withValues(alpha: 0.15)
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, color: _lightOffWhite, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isActive
                          ? Colors.white
                          : Colors.black.withValues(alpha: 0.8),
                      fontSize: 12.5,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _primaryAqua,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chevron_right,
                      color: _lightOffWhite,
                      size: 14,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required String label,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.black.withValues(alpha: 0.08),
          splashColor: _primaryAqua.withValues(alpha: 0.2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              gradient: isActive
                  ? LinearGradient(
                      colors: [
                        _primaryAqua.withValues(alpha: 0.15),
                        _primaryAqua.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(
                  color: isActive ? _primaryAqua : _darkDeepTeal,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isActive
                        ? _primaryAqua.withValues(alpha: 0.15)
                        : _darkDeepTeal.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    icon,
                    color: isActive
                        ? _primaryAqua
                        : Colors.black.withValues(alpha: 0.8),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isActive
                          ? Colors.white
                          : Colors.black.withValues(alpha: 0.8),
                      fontSize: 12.5,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _primaryAqua,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chevron_right,
                      color: _lightOffWhite,
                      size: 14,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStatChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _primaryAqua.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.transparent, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: _lightOffWhite, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: _lightOffWhite,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
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
    final systemStatus = 'All systems operational';
    final greeting = _getTimeBasedGreeting();

    return StatefulBuilder(
      builder: (context, setState) {
        bool isHovered = false;
        return MouseRegion(
          onEnter: (_) => setState(() => isHovered = true),
          onExit: (_) => setState(() => isHovered = false),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _sidebarDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _primaryAqua.withValues(alpha: 0.15),
                width: 1.5,
              ),
              boxShadow: isHovered
                  ? [
                      BoxShadow(
                        color: _primaryAqua.withValues(alpha: 0.6),
                        blurRadius: 20,
                        spreadRadius: 2,
                        offset: const Offset(0, 0),
                      ),
                    ]
                  : [],
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
                          const SizedBox(width: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _accentGreen.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _accentGreen.withValues(alpha: 0.5),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: _accentGreen,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  systemStatus,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _accentGreen,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChoStyleDiseaseTrendSection() {
    final monthLabels = _morbidityTrendMonthLabels.isEmpty
        ? const <String>['M1', 'M2', 'M3', 'M4', 'M5', 'M6']
        : _morbidityTrendMonthLabels;

    final dynamic rawSeries = _morbidityTrendSeries;
    final seriesEntries = <MapEntry<String, List<int>>>[];
    if (rawSeries is Map) {
      rawSeries.forEach((dynamic key, dynamic value) {
        final disease = (key ?? '').toString().trim();
        if (disease.isEmpty) return;
        if (value is! List) return;

        final values = <int>[];
        for (final item in value) {
          if (item is num) {
            values.add(item.toInt());
          } else {
            final parsed = int.tryParse(item.toString());
            if (parsed != null) values.add(parsed);
          }
        }
        if (values.isNotEmpty) {
          seriesEntries.add(MapEntry<String, List<int>>(disease, values));
        }
      });
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
    final maxSource = allValues.isEmpty
        ? 0
        : allValues.reduce((a, b) => a > b ? a : b);
    final maxY = (maxSource <= 0 ? 5.0 : maxSource.toDouble()) * 1.2;
    final interval = ((maxY / 4).clamp(1, maxY)).toDouble();
    const seriesColors = <Color>[
      Colors.redAccent,
      Colors.orangeAccent,
      Colors.lightGreenAccent,
      Colors.cyanAccent,
    ];
    final Widget chartContent = _isLoadingMorbidityTrends
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: _primaryAqua, strokeWidth: 2),
                const SizedBox(height: 10),
                Text(
                  'Syncing disease trends...',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          )
        : plottedSeries.isEmpty
        ? Center(
            child: Text(
              'No disease trend data yet',
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.65),
                fontSize: 12,
              ),
            ),
          )
        : LineChart(
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
                  color: Colors.black.withValues(alpha: 0.10),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: List.generate(plottedSeries.length, (index) {
                final color = seriesColors[index % seriesColors.length];
                return LineChartBarData(
                  isCurved: true,
                  color: color,
                  barWidth: 3,
                  dotData: FlDotData(show: true),
                  spots: List.generate(
                    pointCount,
                    (i) => FlSpot(
                      i.toDouble(),
                      plottedSeries[index].value[i].toDouble(),
                    ),
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
                        color: Colors.black.withValues(alpha: 0.65),
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
                            color: Colors.black.withValues(alpha: 0.72),
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.analytics_outlined, color: _lightOffWhite, size: 24),
              SizedBox(width: 10),
              Text(
                'Disease Trend Analysis',
                style: TextStyle(
                  color: _lightOffWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'CHO-style monthly trend view from Firestore morbidity records.',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.6),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 320,
            padding: const EdgeInsets.fromLTRB(10, 14, 14, 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1F3A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _primaryAqua.withValues(alpha: 0.22),
                width: 1,
              ),
            ),
            child: chartContent,
          ),
          const SizedBox(height: 10),
          if (plottedSeries.isNotEmpty)
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: List.generate(plottedSeries.length, (index) {
                final disease = plottedSeries[index].key;
                final color = seriesColors[index % seriesColors.length];
                final shortLabel = disease.length <= 20
                    ? disease
                    : '${disease.substring(0, 17)}...';
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
                      shortLabel,
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.75),
                        fontSize: 10,
                      ),
                    ),
                  ],
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget _buildDiseaseTrendSection() {
    final hasTrendData = _chartLines.isNotEmpty && _allDates.isNotEmpty;
    final double maxYSource = hasTrendData
        ? _chartLines
              .expand((line) => line.spots)
              .fold<double>(
                0.0,
                (current, spot) => spot.y > current ? spot.y : current,
              )
        : 0.0;
    final double maxY = maxYSource > 0 ? maxYSource + 2.0 : 10.0;
    final double yInterval = maxY <= 8 ? 1.0 : (maxY / 4).ceilToDouble();
    final dateLabelStep = _allDates.length <= 8
        ? 1
        : (_allDates.length / 8).ceil();
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompactTrendCard = screenWidth < 1100;
    final isVeryCompactTrendCard = screenWidth < 760;
    final outerPadding = isVeryCompactTrendCard
        ? 14.0
        : (isCompactTrendCard ? 18.0 : 24.0);
    final innerPadding = isVeryCompactTrendCard
        ? 12.0
        : (isCompactTrendCard ? 16.0 : 20.0);
    final trendChartHeight = isVeryCompactTrendCard
        ? 250.0
        : (isCompactTrendCard ? 290.0 : 340.0);

    var totalCases = 0;
    for (final byDate in _symptomDateData.values) {
      for (final count in byDate.values) {
        totalCases += count;
      }
    }
    final dailyAverage = _allDates.isEmpty
        ? 0.0
        : totalCases / _allDates.length;

    var topSymptom = 'N/A';
    var topSymptomCount = 0;
    _symptomDateData.forEach((symptom, byDate) {
      var sum = 0;
      for (final count in byDate.values) {
        sum += count;
      }
      if (sum > topSymptomCount) {
        topSymptom = symptom;
        topSymptomCount = sum;
      }
    });
    final topSymptomLabel = topSymptom == 'N/A'
        ? 'N/A'
        : '${topSymptom[0].toUpperCase()}${topSymptom.substring(1)}';

    return Container(
      padding: EdgeInsets.all(outerPadding),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_darkDeepTeal, _darkDeepTeal.withValues(alpha: 0.98)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(innerPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isVeryCompactTrendCard)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.analytics_outlined,
                        color: _lightOffWhite,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Disease Trend Analysis',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: _lightOffWhite,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Trend board for symptom movement and load',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _primaryAqua.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.date_range_outlined,
                          color: _lightOffWhite,
                          size: 14,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Selected month window',
                          style: TextStyle(
                            fontSize: 11,
                            color: _primaryAqua,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.analytics_outlined,
                              color: _lightOffWhite,
                              size: 22,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Disease Trend Analysis',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _lightOffWhite,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Trend board for symptom movement and load',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _primaryAqua.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.date_range_outlined,
                          color: _lightOffWhite,
                          size: 14,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Selected month window',
                          style: TextStyle(
                            fontSize: 11,
                            color: _primaryAqua,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _primaryAqua.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _primaryAqua.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Month Range Filter',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _primaryAqua,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (isVeryCompactTrendCard) ...[
                    _buildTrendDateSelector(
                      label: 'Start Month',
                      date: _trendStartDate,
                      onTap: _pickTrendStartMonth,
                    ),
                    const SizedBox(height: 12),
                    _buildTrendDateSelector(
                      label: 'End Month',
                      date: _trendEndDate,
                      onTap: _pickTrendEndMonth,
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: _buildTrendDateSelector(
                            label: 'Start Month',
                            date: _trendStartDate,
                            onTap: _pickTrendStartMonth,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTrendDateSelector(
                            label: 'End Month',
                            date: _trendEndDate,
                            onTap: _pickTrendEndMonth,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildTrendKpiTile(
                  label: 'Total Cases',
                  value: totalCases.toString(),
                  icon: Icons.ssid_chart_outlined,
                  accent: _primaryAqua,
                  minWidth: isVeryCompactTrendCard
                      ? 0
                      : (isCompactTrendCard ? 150 : 180),
                ),
                _buildTrendKpiTile(
                  label: 'Daily Average',
                  value: dailyAverage.toStringAsFixed(1),
                  icon: Icons.timeline_outlined,
                  accent: _accentOrange,
                  minWidth: isVeryCompactTrendCard
                      ? 0
                      : (isCompactTrendCard ? 150 : 180),
                ),
                _buildTrendKpiTile(
                  label: 'Top Symptom',
                  value: topSymptomCount > 0
                      ? '$topSymptomLabel ($topSymptomCount)'
                      : 'No data',
                  icon: Icons.local_hospital_outlined,
                  accent: _accentGreen,
                  minWidth: isVeryCompactTrendCard
                      ? 0
                      : (isCompactTrendCard ? 150 : 180),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: const Color(0xFF0B1F3A),
                border: Border.all(
                  color: _primaryAqua.withValues(alpha: 0.2),
                  width: 1.2,
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: trendChartHeight,
                child: _isLoadingTrends
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              color: _primaryAqua,
                              strokeWidth: 2,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Loading trend data...',
                              style: TextStyle(
                                color: Colors.black.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    : (_chartLines.isEmpty || _allDates.isEmpty)
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.black.withValues(alpha: 0.3),
                              size: 40,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No disease data available for the selected period',
                              style: TextStyle(
                                color: Colors.black.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    : LineChart(
                        LineChartData(
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: yInterval,
                            getDrawingHorizontalLine: (value) {
                              return FlLine(
                                color: Colors.black.withValues(alpha: 0.09),
                                strokeWidth: 0.9,
                              );
                            },
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 36,
                                interval: 1,
                                getTitlesWidget:
                                    (double value, TitleMeta meta) {
                                      final index = value.toInt();
                                      if (index < 0 ||
                                          index >= _allDates.length) {
                                        return const SizedBox.shrink();
                                      }
                                      final isVisible =
                                          index % dateLabelStep == 0 ||
                                          index == _allDates.length - 1;
                                      if (!isVisible) {
                                        return const SizedBox.shrink();
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          _allDates[index],
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.75,
                                            ),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      );
                                    },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 34,
                                interval: yInterval,
                                getTitlesWidget:
                                    (double value, TitleMeta meta) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 6,
                                        ),
                                        child: Text(
                                          value.toInt().toString(),
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.78,
                                            ),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      );
                                    },
                              ),
                            ),
                          ),
                          borderData: FlBorderData(
                            show: true,
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.black.withValues(alpha: 0.2),
                                width: 1,
                              ),
                              left: BorderSide(
                                color: Colors.black.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                          ),
                          minX: 0,
                          maxX: (_allDates.length - 1).toDouble(),
                          minY: 0,
                          maxY: maxY,
                          lineBarsData: _chartLines,
                          lineTouchData: LineTouchData(
                            enabled: true,
                            touchTooltipData: LineTouchTooltipData(
                              tooltipPadding: const EdgeInsets.all(10),
                              tooltipMargin: 10,
                              fitInsideHorizontally: true,
                              fitInsideVertically: true,
                              getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                                if (touchedBarSpots.isEmpty) return [];
                                final xIndex = touchedBarSpots.first.x.toInt();
                                if (xIndex < 0 || xIndex >= _allDates.length) {
                                  return [];
                                }
                                final date = _allDates[xIndex];
                                return touchedBarSpots.map((barSpot) {
                                  final barIndex = barSpot.barIndex;
                                  if (barIndex < 0 ||
                                      barIndex >= _allSymptoms.length) {
                                    return null;
                                  }
                                  final symptom = _allSymptoms[barIndex];
                                  final count = barSpot.y.toInt();
                                  final symptomLabel =
                                      '${symptom[0].toUpperCase()}${symptom.substring(1)}';
                                  return LineTooltipItem(
                                    '$symptomLabel: $count\n',
                                    TextStyle(
                                      color:
                                          _symptomColors[symptom] ??
                                          Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: date,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.78,
                                          ),
                                          fontWeight: FontWeight.w500,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList();
                              },
                            ),
                            handleBuiltInTouches: true,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 18),
            if (_allSymptoms.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _primaryAqua.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Legend',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _primaryAqua,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _allSymptoms.map((symptom) {
                        final color = _symptomColors[symptom] ?? _primaryAqua;
                        final symptomLabel =
                            '${symptom[0].toUpperCase()}${symptom.substring(1)}';
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _sidebarDark.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: color.withValues(alpha: 0.5),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                symptomLabel,
                                style: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.9),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendDateSelector({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.black.withValues(alpha: 0.6),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _primaryAqua.withValues(alpha: 0.2),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(8),
                color: _sidebarDark.withValues(alpha: 0.35),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _monthYearLabel(date),
                      style: const TextStyle(
                        color: _lightOffWhite,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.calendar_month, color: _primaryAqua, size: 18),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrendKpiTile({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
    double minWidth = 180,
  }) {
    return Container(
      constraints: minWidth > 0
          ? BoxConstraints(minWidth: minWidth)
          : const BoxConstraints(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _sidebarDark.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.65),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _lightOffWhite,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
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
        color: const Color(0xFFEDF3FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9E5F2)),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      color: _lightOffWhite,
                      size: 24,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Recent Activity',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _lightOffWhite,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _loadExecutiveOverview,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: _primaryAqua,
                  ),
                  label: const Text(
                    'Refresh',
                    style: TextStyle(color: _primaryAqua),
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
                          border: Border.all(
                            color: const Color(0xFFD9E5F2),
                            width: 1,
                          ),
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

  Widget _buildUpcomingAppointments() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _accentGreen.withValues(alpha: 0.08),
            _primaryAqua.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  color: _lightOffWhite,
                  size: 24,
                ),
                SizedBox(width: 10),
                Text(
                  'Upcoming Appointments',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _lightOffWhite,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_upcomingAppointments.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'No upcoming appointments',
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                height: 280,
                child: ListView.builder(
                  itemCount: _upcomingAppointments.length,
                  itemBuilder: (context, index) {
                    final appt = _upcomingAppointments[index];
                    final isConfirmed = appt['status'] == 'Confirmed';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _sidebarDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isConfirmed
                                ? _accentGreen.withValues(alpha: 0.2)
                                : _accentOrange.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isConfirmed
                                    ? _accentGreen.withValues(alpha: 0.15)
                                    : _accentOrange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.person_outline_rounded,
                                color: isConfirmed
                                    ? _accentGreen
                                    : _accentOrange,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    appt['patientName'] as String,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _lightOffWhite,
                                    ),
                                  ),
                                  Text(
                                    '${appt['date']} at ${appt['time']}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isConfirmed
                                    ? _accentGreen.withValues(alpha: 0.12)
                                    : _accentOrange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                appt['status'] as String,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isConfirmed
                                      ? _accentGreen
                                      : _accentOrange,
                                ),
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

  Widget _buildTodaysOverview() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.today_rounded, color: _lightOffWhite, size: 24),
              SizedBox(width: 10),
              Text(
                "Today's Overview",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _lightOffWhite,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildTodayStatChip(
                  label: 'Pending Tasks',
                  value: _todaysPendingTasks.toString(),
                  icon: Icons.assignment_rounded,
                  color: _accentOrange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTodayStatChip(
                  label: 'Check-ins Today',
                  value: _patientsCheckedInToday.toString(),
                  icon: Icons.person_add_rounded,
                  color: _primaryAqua,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTodayStatChip(
                  label: 'Critical Alerts',
                  value: _criticalAlerts.toString(),
                  icon: Icons.warning_rounded,
                  color: _accentRed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodayStatChip({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.transparent, width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: _lightOffWhite, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.black.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthSnapshot() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.favorite_rounded, color: _lightOffWhite, size: 24),
              SizedBox(width: 10),
              Text(
                'Health Snapshot',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _lightOffWhite,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_topDiagnoses.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'No diagnosis data available',
                  style: TextStyle(color: Colors.black.withValues(alpha: 0.5)),
                ),
              ),
            )
          else
            Column(
              children: [
                Row(
                  children: [
                    Text(
                      'Top Diagnoses This Month',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _primaryAqua.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _topDiagnoses.length.toString(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _primaryAqua,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ..._topDiagnoses.take(3).toList().asMap().entries.map((e) {
                  final index = e.key;
                  final diagnosis = e.value;
                  final colors = [_primaryAqua, _accentPurple, _accentGreen];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: colors[index].withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colors[index],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (diagnosis['name'] ?? 'Unknown').toString(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _lightOffWhite,
                                ),
                              ),
                              Text(
                                '${(diagnosis['count'] ?? 0)} cases',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.black.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${(diagnosis['count'] ?? 0)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors[index],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildKPIDashboard() {
    // Every score below is derived from persisted Firestore records
    // (patients/checkups/prenatal/immunizations) via _loadKPIData() — none
    // are randomized or formula-fabricated.
    final double checkupVolumeScore = _totalPatients > 0
        ? ((_checkupsThisMonth / _totalPatients) * 100.0)
              .clamp(0.0, 100.0)
              .toDouble()
        : 0.0;
    final double documentationScore = _documentationCompletionRate
        .clamp(0.0, 100.0)
        .toDouble();
    final double prenatalScore = _prenatalCoverageRate
        .clamp(0.0, 100.0)
        .toDouble();
    final double immunizationScore = _immunizationRate
        .clamp(0.0, 100.0)
        .toDouble();

    final metrics = <Map<String, dynamic>>[
      {
        'label': 'Check-ups This Month',
        'short': 'Ckup',
        'display': '$_checkupsThisMonth of $_totalPatients patients',
        'score': checkupVolumeScore,
        'target': 50.0,
        'color': _accentGreen,
      },
      {
        'label': 'Documentation Completion',
        'short': 'Docs',
        'display': '${_documentationCompletionRate.toStringAsFixed(1)}%',
        'score': documentationScore,
        'target': 90.0,
        'color': _primaryAqua,
      },
      {
        'label': 'Prenatal Coverage',
        'short': 'Pren',
        'display': '${_prenatalCoverageRate.toStringAsFixed(1)}%',
        'score': prenatalScore,
        'target': 80.0,
        'color': _accentOrange,
      },
      {
        'label': 'Immunization Coverage',
        'short': 'Imm',
        'display': '${_immunizationRate.toStringAsFixed(1)}%',
        'score': immunizationScore,
        'target': 95.0,
        'color': _accentPurple,
      },
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.trending_up_rounded, color: _lightOffWhite, size: 24),
              SizedBox(width: 10),
              Text(
                'Performance Indicators',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _lightOffWhite,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'KPI matrix (actual versus target, normalized score)',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.6),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoadingKPI)
            SizedBox(
              height: 250,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: _primaryAqua),
                    const SizedBox(height: 10),
                    Text(
                      'Loading performance indicators...',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Container(
              height: 260,
              padding: const EdgeInsets.fromLTRB(10, 14, 14, 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1F3A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _primaryAqua.withValues(alpha: 0.22),
                  width: 1,
                ),
              ),
              child: BarChart(
                BarChartData(
                  minY: 0,
                  maxY: 100,
                  barTouchData: BarTouchData(
                    enabled: true,
                    handleBuiltInTouches: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipPadding: const EdgeInsets.all(10),
                      tooltipMargin: 10,
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipItem:
                          (
                            BarChartGroupData group,
                            int groupIndex,
                            BarChartRodData rod,
                            int rodIndex,
                          ) {
                            if (groupIndex < 0 ||
                                groupIndex >= metrics.length) {
                              return null;
                            }

                            final item = metrics[groupIndex];
                            final String label = item['label'].toString();
                            final String display = item['display'].toString();
                            final double score = item['score'] as double;
                            final double target = item['target'] as double;
                            final double gap = score - target;
                            final bool isTargetRod = rodIndex == 1;
                            final String gapText =
                                '${gap >= 0 ? '+' : ''}${gap.toStringAsFixed(1)}';

                            return BarTooltipItem(
                              '$label\n',
                              const TextStyle(
                                color: _lightOffWhite,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                              children: [
                                TextSpan(
                                  text:
                                      'Actual: $display (${score.toStringAsFixed(1)}/100)\n',
                                  style: TextStyle(
                                    color: Colors.black.withValues(alpha: 0.85),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 11,
                                  ),
                                ),
                                TextSpan(
                                  text:
                                      'Target: ${target.toStringAsFixed(1)}/100\n',
                                  style: TextStyle(
                                    color: Colors.black.withValues(alpha: 0.85),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 11,
                                  ),
                                ),
                                TextSpan(
                                  text: 'Gap: $gapText points\n',
                                  style: TextStyle(
                                    color: gap >= 0
                                        ? _accentGreen
                                        : _accentOrange,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                                TextSpan(
                                  text:
                                      'Hovered: ${isTargetRod ? 'Target' : 'Actual'} ${rod.toY.toStringAsFixed(1)}',
                                  style: TextStyle(
                                    color: Colors.black.withValues(alpha: 0.72),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            );
                          },
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 20,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: Colors.black.withValues(alpha: 0.10),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      left: BorderSide(
                        color: Colors.black.withValues(alpha: 0.22),
                        width: 1,
                      ),
                      bottom: BorderSide(
                        color: Colors.black.withValues(alpha: 0.22),
                        width: 1,
                      ),
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
                        reservedSize: 32,
                        interval: 20,
                        getTitlesWidget: (value, _) => Text(
                          '${value.toInt()}',
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.72),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) {
                          final int index = value.toInt();
                          if (index < 0 || index >= metrics.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                              metrics[index]['short'].toString(),
                              style: TextStyle(
                                color: Colors.black.withValues(alpha: 0.82),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: List.generate(metrics.length, (index) {
                    final item = metrics[index];
                    final double score = (item['score'] as double);
                    final double target = (item['target'] as double);
                    final Color color = item['color'] as Color;
                    return BarChartGroupData(
                      x: index,
                      barsSpace: 4,
                      barRods: [
                        BarChartRodData(
                          toY: score,
                          width: 16,
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        BarChartRodData(
                          toY: target,
                          width: 7,
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
