import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/app/features/auth/login.dart';
import 'package:mycapstone_project/app/features/auth/signup.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart'
    as charts;
import 'package:fl_chart/fl_chart.dart';
import 'package:mycapstone_project/app/features/checkups/checkup.dart';
import 'package:mycapstone_project/app/features/analytics/analytics.dart';
import 'package:mycapstone_project/app/features/referrals/referrals.dart';
import 'package:mycapstone_project/app/features/prenatal/prenatal.dart';
import 'package:mycapstone_project/app/features/immunization/immunization.dart';
import 'package:mycapstone_project/app/features/patients/patient.dart';
import 'package:mycapstone_project/app/features/surveillance/communicable/communicable_list.dart';
import 'package:mycapstone_project/app/features/surveillance/non_communicable/non_communicable.dart';
import 'package:mycapstone_project/app/features/surveillance/mortality/mortality.dart';
import 'package:mycapstone_project/app/features/surveillance/morbidity/morbidity_list.dart';
import 'package:mycapstone_project/app/features/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/app/features/prenatal/prenatal_database_helper.dart';
import 'package:mycapstone_project/app/features/immunization/immunization_database_helper.dart';
import 'package:mycapstone_project/app/features/patients/patient_database_helper.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _secondaryIceBlue = AppDesign.navySoft;
const Color _darkDeepTeal = AppDesign.ink;
const Color _mutedCoolGray = AppDesign.muted;
const Color _lightOffWhite = Colors.white;

class HomePage extends StatefulWidget {
  final User? user;
  const HomePage({super.key, this.user});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<void> signout() async {
    await FirebaseAuth.instance.signOut();
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final bool _isOfflineMode;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _offlineSnackbarShown = false;
  bool _lastKnownHasInternet = true;
  bool _shouldPromptReconnectLogin = false;
  String? _dashboardUserName;
  String? _dashboardBarangayName;
  bool _isReconnectDialogVisible = false;
  int _selectedBottomNavIndex = 0;

  // Database helpers
  final _checkupHelper = DatabaseHelper.instance;
  final _prenatalHelper = PrenatalDatabaseHelper.instance;
  final _immunizationHelper = ImmunizationDatabaseHelper.instance;
  final _patientHelper = PatientDatabaseHelper.instance;

  // Metrics data
  int _totalPatients = 0;
  int _checkupsThisMonth = 0;
  int _prenatalRecords = 0;
  int _immunizationRecords = 0;
  int _highRiskCases = 0;
  bool _isLoadingMetrics = true;
  DateTime? _keyMetricsSelectedDate;
  int _filteredPatientRegistrations = 0;
  int _filteredCheckupRecords = 0;
  int _filteredPrenatalRecords = 0;
  int _filteredImmunizationRecords = 0;

  // Recent activities
  List<Map<String, dynamic>> _recentActivities = [];
  bool _isLoadingActivities = true;

  // Disease Trend data
  Map<String, Map<String, int>> _symptomDateData =
      {}; // symptom -> date -> count
  List<LineChartBarData> _chartLines = [];
  Map<String, Color> _symptomColors = {};
  List<String> _allDates = [];
  List<String> _allSymptoms = [];
  bool _isLoadingTrends = true;

  // Chart interaction
  double _chartZoom = 1.0;
  int? _selectedDotIndex;

  // Notification panel state
  List<Map<String, dynamic>> _notificationsList = [];
  bool _isLoadingNotificationsList = false;

  // Notification plugin and tracking
  late FlutterLocalNotificationsPlugin _notificationsPlugin;
  final Set<String> _notifiedSymptoms =
      {}; // Track symptoms that already notified
  final Map<String, String> _symptomRecommendations = {
    'fever': 'Increase monitoring. Ensure proper hydration and rest.',
    'cough': 'Monitor respiratory health. Consider air quality assessment.',
    'flu': 'Alert patients. Recommend flu testing and isolation.',
    'cold': 'Monitor symptoms. Increase hygiene standard protocols.',
    'infection': 'Alert healthcare providers. Increase patient follow-ups.',
    'tuberculosis': 'URGENT: Refer to TB specialist immediately.',
    'dengue': 'Alert local health authority. Initiate dengue control measures.',
    'covid': 'Alert infection control. Recommend testing & isolation.',
    'measles': 'URGENT: Isolate patients. Notify public health.',
    'chickenpox': 'Monitor cluster. Recommend vaccination drives.',
    'pneumonia': 'URGENT: Refer to specialist. Monitor oxygen levels.',
    'chest pain': 'URGENT: Cardiac assessment needed immediately.',
    'difficulty breathing': 'URGENT: Respiratory support may be needed.',
    'severe bleeding': 'URGENT: Emergency response required.',
    'unconscious': 'CRITICAL: Immediate emergency intervention.',
    'seizure': 'CRITICAL: Neurological emergency response.',
    'stroke': 'CRITICAL: Stroke response protocol activate.',
    'heart attack': 'CRITICAL: Cardiology emergency response.',
    'diabetes':
        'Increase glucose monitoring. Nutritionist consultation recommended.',
    'hypertension':
        'Medication review needed. Lifestyle modification counseling.',
    'asthma': 'Respiratory assessment. Inhalers availability check.',
    'arthritis': 'Physical therapy referral. Pain management review.',
    'cancer': 'Oncology referral. Treatment plan review.',
    'thyroid': 'Endocrinology assessment. Hormone level testing.',
    'cholesterol': 'Dietary counseling. Consider statin therapy review.',
    'obesity': 'Nutritionist referral. Exercise program recommended.',
    'pregnant': 'Prenatal checkup scheduling. Nutritional assessment.',
    'pregnancy': 'Ensure prenatal care pathway. Risk assessment.',
    'prenatal': 'Schedule comprehensive prenatal screening.',
    'antenatal': 'Antenatal care monitoring. Blood pressure check.',
    'maternal': 'Maternal health assessment. Postpartum planning.',
    'infant': 'Newborn screening. Vaccination schedule check.',
    'child': 'Pediatric assessment. Development milestones check.',
    'baby': 'Infant health monitoring. Feeding assessment.',
    'newborn': 'Newborn screening protocol. Health assessment.',
    'toddler': 'Developmental assessment. Nutrition review.',
  };

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    _isOfflineMode = args is Map && args['offline'] == true;
    _keyMetricsSelectedDate ??= DateTime.now();
    _initializeNotifications();
    _loadMetrics();
    _loadRecentActivities();
    _loadDiseaseTrends();
    _loadDashboardUserProfile();
    _initializeOfflineReconnectWatcher();

    // Migrate recovery plans from old UTF-8 format to ASCII-safe format
    _checkupHelper.migrateRecoveryPlans();
    _prenatalHelper.migrateRecoveryPlans();
  }

  Future<void> _loadDashboardUserProfile() async {
    final user = FirebaseAuth.instance.currentUser ?? widget.user;
    if (user == null) return;

    Map<String, dynamic>? profile;
    try {
      final firestore = getFirestoreInstance();
      final userDocument = await firestore
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 12));

      if (userDocument.exists) {
        profile = userDocument.data();
      } else if (user.email != null && user.email!.trim().isNotEmpty) {
        final normalizedEmail = user.email!.trim().toLowerCase();
        var matchingUsers = await firestore
            .collection('users')
            .where('emailLower', isEqualTo: normalizedEmail)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 12));

        if (matchingUsers.docs.isEmpty) {
          matchingUsers = await firestore
              .collection('users')
              .where('email', isEqualTo: user.email!.trim())
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 12));
        }

        if (matchingUsers.docs.isNotEmpty) {
          profile = matchingUsers.docs.first.data();
        }
      }
    } catch (_) {
      // Firebase Auth values remain available when the profile is offline.
    }

    final profileName =
        (profile?['username'] ??
                profile?['displayName'] ??
                profile?['fullName'] ??
                profile?['name'] ??
                '')
            .toString()
            .trim();
    final authName = user.displayName?.trim() ?? '';
    final emailName = user.email?.split('@').first.trim() ?? '';
    final resolvedName = profileName.isNotEmpty
        ? profileName
        : authName.isNotEmpty
        ? authName
        : emailName.isNotEmpty
        ? emailName
        : 'BHW User';

    final barangayName =
        (profile?['barangay'] ??
                profile?['barangayName'] ??
                profile?['assignedBarangay'] ??
                profile?['barangayCode'] ??
                '')
            .toString()
            .trim();

    if (!mounted) return;
    setState(() {
      _dashboardUserName = resolvedName;
      _dashboardBarangayName = barangayName.isNotEmpty
          ? barangayName
          : 'Not assigned';
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  bool _hasInternetConnection(List<ConnectivityResult> results) {
    return !results.contains(ConnectivityResult.none);
  }

  Future<void> _initializeOfflineReconnectWatcher() async {
    if (kIsWeb || !_isOfflineMode) {
      return;
    }

    final initialConnectivity = await Connectivity().checkConnectivity();
    _lastKnownHasInternet = _hasInternetConnection(initialConnectivity);
    _shouldPromptReconnectLogin =
        !_lastKnownHasInternet && FirebaseAuth.instance.currentUser == null;

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) async {
      final hasInternet = _hasInternetConnection(results);
      final regainedInternet = !_lastKnownHasInternet && hasInternet;
      _lastKnownHasInternet = hasInternet;

      if (!hasInternet) {
        _shouldPromptReconnectLogin =
            _isOfflineMode && FirebaseAuth.instance.currentUser == null;
        return;
      }

      if (!_isOfflineMode || FirebaseAuth.instance.currentUser != null) {
        _shouldPromptReconnectLogin = false;
        return;
      }

      if (regainedInternet && _shouldPromptReconnectLogin) {
        await _showReconnectLoginDialog();
      }
    });
  }

  Future<void> _openLoginScreen({
    bool replaceCurrentRoute = false,
    bool syncOfflineAfterLogin = false,
  }) async {
    final route = MaterialPageRoute(
      builder: (context) => Login(syncOfflineAfterLogin: syncOfflineAfterLogin),
    );

    if (replaceCurrentRoute) {
      await Navigator.of(context).pushReplacement(route);
      return;
    }

    await Navigator.of(context).push(route);
  }

  Future<void> _openSignupScreen({bool replaceCurrentRoute = false}) async {
    final route = MaterialPageRoute(builder: (context) => const Signup());

    if (replaceCurrentRoute) {
      await Navigator.of(context).pushReplacement(route);
      return;
    }

    await Navigator.of(context).push(route);
  }

  Future<void> _showReconnectLoginDialog() async {
    if (!mounted || _isReconnectDialogVisible) {
      return;
    }

    _isReconnectDialogVisible = true;
    _shouldPromptReconnectLogin = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _darkDeepTeal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: _lightOffWhite.withValues(alpha: 0.18),
              width: 1.4,
            ),
          ),
          title: Row(
            children: [
              const Icon(Icons.wifi, color: _primaryAqua, size: 24),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Internet Connection Detected',
                  style: TextStyle(
                    color: _lightOffWhite,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'You have an internet connection. Do you want to log in now? After login, your offline records will automatically upload to Firestore.',
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.82),
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Cancel',
                style: TextStyle(color: _lightOffWhite),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _openLoginScreen(syncOfflineAfterLogin: true);
              },
              icon: const Icon(Icons.login, size: 18),
              label: const Text('Login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryAqua,
                foregroundColor: _darkDeepTeal,
              ),
            ),
          ],
        );
      },
    );

    _isReconnectDialogVisible = false;
  }

  Future<void> _initializeNotifications() async {
    _notificationsPlugin = FlutterLocalNotificationsPlugin();

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          // Notification permission is not requested during app startup.
          // A future notification opt-in flow must request it in context.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );

    Future<void> initializeWithIcon(String iconName) async {
      final initializationSettings = InitializationSettings(
        android: AndroidInitializationSettings(iconName),
        iOS: initializationSettingsIOS,
      );
      await _notificationsPlugin.initialize(initializationSettings);
    }

    try {
      await initializeWithIcon('app_icon');
    } on PlatformException catch (e) {
      if (e.code == 'invalid_icon') {
        try {
          await initializeWithIcon('launch_background');
        } on PlatformException catch (fallbackError) {
          print('Notification initialization failed: $fallbackError');
        }
      } else {
        print('Notification initialization failed: $e');
      }
    }
  }

  Future<void> _showSymptomNotification(String symptom, int count) async {
    final recommendation =
        _symptomRecommendations[symptom] ?? 'Monitor closely.';

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'symptom_alerts',
          'Symptom Alerts',
          channelDescription: 'Alerts when symptoms reach threshold',
          importance: Importance.max,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
        );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await _notificationsPlugin.show(
      symptom.hashCode,
      '[ALERT] $symptom Alert',
      'Total: $count cases\n\n[INFO] Recommendation:\n$recommendation',
      platformChannelSpecifics,
    );

    _notifiedSymptoms.add(symptom);
  }

  Future<void> _generateNotificationsPanel() async {
    if (!mounted) return;
    setState(() => _isLoadingNotificationsList = true);

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
        'color': Colors.green,
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
          'color': Colors.orange,
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
          'color': Color(0xFFD84315),
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
          'color': Color(0xFF4CAF50),
          'timestamp': DateTime.now().subtract(const Duration(hours: 1)),
        });
      }

      // High Risk Cases Alert
      if (_highRiskCases > 0) {
        notifications.add({
          'title': 'High Risk Cases',
          'message':
              '$_highRiskCases high-risk prenatal cases requiring attention',
          'type': 'critical',
          'icon': Icons.priority_high,
          'color': Colors.red,
          'timestamp': DateTime.now().subtract(const Duration(hours: 2)),
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
          'timestamp': DateTime.now().subtract(const Duration(hours: 3)),
        });
      }

      if (!mounted) return;
      setState(() {
        _notificationsList = notifications;
        _isLoadingNotificationsList = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingNotificationsList = false);
    }
  }

  void _showNotificationsPanel(BuildContext context) {
    _generateNotificationsPanel();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppDesign.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.notifications_active, color: _primaryAqua, size: 24),
            const SizedBox(width: 12),
            const Text(
              'Notifications',
              style: TextStyle(
                color: AppDesign.ink,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: _isLoadingNotificationsList
              ? const Center(
                  child: CircularProgressIndicator(color: _primaryAqua),
                )
              : _notificationsList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_off,
                        size: 64,
                        color: AppDesign.subtle,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No notifications',
                        style: TextStyle(color: AppDesign.muted),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _notificationsList.length,
                  itemBuilder: (context, index) {
                    final notif = _notificationsList[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: (notif['color'] as Color).withValues(
                            alpha: 0.3,
                          ),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: AppDesign.page,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: (notif['color'] as Color).withValues(
                                    alpha: 0.2,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  notif['icon'] as IconData,
                                  color: notif['color'] as Color,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  notif['title'] as String,
                                  style: const TextStyle(
                                    color: AppDesign.ink,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            notif['message'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppDesign.muted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatNotificationTime(
                              notif['timestamp'] as DateTime,
                            ),
                            style: TextStyle(
                              fontSize: 10,
                              color: AppDesign.subtle,
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
            onPressed: _generateNotificationsPanel,
            style: ElevatedButton.styleFrom(backgroundColor: _primaryAqua),
            child: const Text('Refresh', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatNotificationTime(DateTime dateTime) {
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

  Future<void> _loadMetrics() async {
    setState(() {
      _isLoadingMetrics = true;
    });

    try {
      // Load all database records
      final patients = await _patientHelper.getAllRecords();
      final checkups = await _checkupHelper.getAllRecords();
      final prenatal = await _prenatalHelper.getAllRecords();
      final immunizations = await _immunizationHelper.getAllRecords();

      // Calculate metrics
      final now = DateTime.now();
      final checkupsThisMonth = checkups.where((record) {
        try {
          final datetime = DateTime.parse(record['datetime'] ?? '');
          return datetime.year == now.year && datetime.month == now.month;
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

      // Count high risk cases from prenatal records
      final highRiskCount = prenatal.where((record) {
        final riskLevel = (record['riskLevel'] ?? '').toString().toLowerCase();
        return riskLevel == 'high' || riskLevel == 'very high';
      }).length;

      setState(() {
        _totalPatients = patients.length;
        _checkupsThisMonth = checkupsThisMonth;
        _prenatalRecords = prenatal.length;
        _immunizationRecords = immunizations.length;
        _highRiskCases = highRiskCount;
        _filteredPatientRegistrations = filteredPatientRegistrations;
        _filteredCheckupRecords = filteredCheckupRecords;
        _filteredPrenatalRecords = filteredPrenatalRecords;
        _filteredImmunizationRecords = filteredImmunizationRecords;
        _isLoadingMetrics = false;
      });
    } catch (e) {
      print('Error loading metrics: $e');
      setState(() {
        _isLoadingMetrics = false;
      });
    }
  }

  DateTime _normalizeToMonth(DateTime date) {
    return DateTime(date.year, date.month);
  }

  DateTime get _effectiveKeyMetricsSelectedDate {
    final selected = _keyMetricsSelectedDate;
    if (selected != null) {
      final normalized = _normalizeToMonth(selected);
      _keyMetricsSelectedDate = normalized;
      return normalized;
    }

    final fallback = _normalizeToMonth(DateTime.now());
    _keyMetricsSelectedDate = fallback;
    return fallback;
  }

  String _formatKeyMetricsSelectedMonth() {
    final selected = _effectiveKeyMetricsSelectedDate;
    return '${_getMonthName(selected.month)} ${selected.year}';
  }

  String _metricFilterScopeLabel() {
    return _formatKeyMetricsSelectedMonth();
  }

  bool _matchesKeyMetricFilter(DateTime? date) {
    if (date == null) return false;
    final selectedDate = _effectiveKeyMetricsSelectedDate;
    return date.year == selectedDate.year && date.month == selectedDate.month;
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
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is num) {
      final raw = value.toInt();
      if (raw <= 0) return null;
      final ms = raw > 100000000000 ? raw : raw * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    if (value is! String) return null;

    final text = value.trim();
    if (text.isEmpty) return null;

    final parsed = DateTime.tryParse(text);
    if (parsed != null) return parsed;

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
              brightness: Brightness.light,
              dialogTheme: Theme.of(context).dialogTheme.copyWith(
                backgroundColor: AppDesign.surface,
                surfaceTintColor: Colors.transparent,
              ),
              colorScheme: Theme.of(context).colorScheme.copyWith(
                brightness: Brightness.light,
                primary: _primaryAqua,
                onPrimary: Colors.white,
                surface: AppDesign.surface,
                onSurface: AppDesign.ink,
              ),
              inputDecorationTheme: Theme.of(context).inputDecorationTheme
                  .copyWith(
                    labelStyle: const TextStyle(color: AppDesign.muted),
                    hintStyle: const TextStyle(color: AppDesign.subtle),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppDesign.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: _primaryAqua.withValues(alpha: 0.8),
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppDesign.border),
                    ),
                  ),
            );

            return Theme(
              data: dialogTheme,
              child: AlertDialog(
                backgroundColor: AppDesign.surface,
                title: Text(
                  helpText,
                  style: const TextStyle(color: AppDesign.ink),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: tempMonth,
                      decoration: InputDecoration(
                        labelText: 'Month',
                        labelStyle: const TextStyle(color: AppDesign.muted),
                        floatingLabelStyle: const TextStyle(
                          color: AppDesign.blue,
                        ),
                        filled: true,
                        fillColor: _secondaryIceBlue.withValues(alpha: 0.22),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                      dropdownColor: AppDesign.surface,
                      style: const TextStyle(color: AppDesign.ink),
                      iconEnabledColor: AppDesign.muted,
                      iconDisabledColor: AppDesign.subtle,
                      items: availableMonths
                          .map(
                            (month) => DropdownMenuItem<int>(
                              value: month,
                              child: Text(
                                _getMonthName(month),
                                style: const TextStyle(color: AppDesign.ink),
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
                      decoration: InputDecoration(
                        labelText: 'Year',
                        labelStyle: const TextStyle(color: AppDesign.muted),
                        floatingLabelStyle: const TextStyle(
                          color: AppDesign.blue,
                        ),
                        filled: true,
                        fillColor: _secondaryIceBlue.withValues(alpha: 0.22),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                      dropdownColor: AppDesign.surface,
                      style: const TextStyle(color: AppDesign.ink),
                      iconEnabledColor: AppDesign.muted,
                      iconDisabledColor: AppDesign.subtle,
                      items: years
                          .map(
                            (year) => DropdownMenuItem<int>(
                              value: year,
                              child: Text(
                                year.toString(),
                                style: const TextStyle(color: AppDesign.ink),
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
                      foregroundColor: AppDesign.muted,
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

  Future<void> _pickKeyMetricsMonth() async {
    final selectedDate = _effectiveKeyMetricsSelectedDate;
    final picked = await _pickMonthYear(
      initialDate: selectedDate,
      helpText: 'Select month',
    );

    if (picked == null || !mounted) return;
    setState(() => _keyMetricsSelectedDate = _normalizeToMonth(picked));
    _loadMetrics();
  }

  Widget _buildKeyMetricsMonthPickerButton() {
    return OutlinedButton.icon(
      onPressed: _pickKeyMetricsMonth,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppDesign.navySoft,
        side: const BorderSide(color: AppDesign.border),
        backgroundColor: AppDesign.blueSoft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: const Icon(Icons.calendar_month_rounded, size: 14),
      label: Text(
        _formatKeyMetricsSelectedMonth(),
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _loadRecentActivities() async {
    setState(() {
      _isLoadingActivities = true;
    });

    try {
      List<Map<String, dynamic>> activities = [];

      // Load recent checkups
      final checkups = await _checkupHelper.getAllRecords();
      for (var record in checkups.take(5)) {
        activities.add({
          'title': 'Patient Check-up',
          'subtitle': '${record['patient']} - ${record['type']}',
          'timestamp': record['datetime'] ?? '',
          'icon': Icons.assignment_turned_in,
          'color': _primaryAqua,
          'type': 'checkup',
        });
      }

      // Load recent prenatal records
      final prenatal = await _prenatalHelper.getAllRecords();
      for (var record in prenatal.take(3)) {
        activities.add({
          'title': 'Prenatal Care',
          'subtitle': '${record['patientName']} - Risk: ${record['riskLevel']}',
          'timestamp': record['registrationDate'] ?? '',
          'icon': Icons.pregnant_woman,
          'color': Color(0xFFD84315),
          'type': 'prenatal',
        });
      }

      // Load recent immunizations
      final immunizations = await _immunizationHelper.getAllRecords();
      for (var record in immunizations.take(3)) {
        activities.add({
          'title': 'Immunization',
          'subtitle': '${record['patientName']} - ${record['vaccine']}',
          'timestamp': record['administrationDate'] ?? '',
          'icon': Icons.vaccines,
          'color': Color(0xFF4CAF50),
          'type': 'immunization',
        });
      }

      // Load recent patient registrations
      final patients = await _patientHelper.getAllRecords();
      for (var record in patients.take(3)) {
        activities.add({
          'title': 'New Patient Registration',
          'subtitle': '${record['firstName']} ${record['surname']}',
          'timestamp': record['registrationDate'] ?? '',
          'icon': Icons.person_add,
          'color': Color(0xFF0097A7),
          'type': 'patient',
        });
      }

      // Sort by timestamp (most recent first)
      activities.sort((a, b) {
        try {
          final dateA = DateTime.parse(a['timestamp'] ?? '');
          final dateB = DateTime.parse(b['timestamp'] ?? '');
          return dateB.compareTo(dateA);
        } catch (e) {
          return 0;
        }
      });

      setState(() {
        _recentActivities = activities.take(10).toList();
        _isLoadingActivities = false;
      });
    } catch (e) {
      print('Error loading recent activities: $e');
      setState(() {
        _isLoadingActivities = false;
      });
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inMinutes < 60) {
        return '${difference.inMinutes} min ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours} hours ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return '${date.month}/${date.day}/${date.year}';
      }
    } catch (e) {
      return timestamp;
    }
  }

  Future<void> _loadDiseaseTrends() async {
    setState(() {
      _isLoadingTrends = true;
    });

    try {
      final checkups = await _checkupHelper.getAllRecords();
      final symptomDateMap =
          <String, Map<String, int>>{}; // symptom -> date -> count
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));

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

      // Extract symptoms by date for each individual symptom
      for (var record in checkups) {
        try {
          final datetime = DateTime.parse(record['datetime'] ?? '');
          if (datetime.isAfter(thirtyDaysAgo)) {
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

      // Generate color for each symptom
      final colors = [
        AppDesign.teal,
        const Color(0xFFFF6B6B), // red
        const Color(0xFF4ECDC4), // teal
        const Color(0xFFFFE66D), // yellow
        const Color(0xFF95E1D3), // mint
        const Color(0xFFC7CEEA), // lavender
        const Color(0xFFFFB6C1), // pink
        const Color(0xFFA8E6CF), // green
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
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.5)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
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
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.2),
                  color.withValues(alpha: 0.02),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
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

        // Check for symptoms reaching 10+ threshold and send notifications
        for (var symptom in symptomsWithData) {
          final totalCount = symptomDateMap[symptom]!.values.fold<int>(
            0,
            (sum, val) => sum + val,
          );
          if (totalCount >= 10 && !_notifiedSymptoms.contains(symptom)) {
            await _showSymptomNotification(symptom, totalCount);
          }
        }
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

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppDesign.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border.all(color: AppDesign.border),
        boxShadow: [
          BoxShadow(
            color: AppDesign.navy.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: _selectedBottomNavIndex,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          backgroundColor: AppDesign.surface,
          selectedItemColor: _primaryAqua,
          unselectedItemColor: AppDesign.subtle,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
          onTap: (index) {
            if (index == 1) {
              Get.to(() => const AnalyticsPage());
              return;
            }
            setState(() {
              _selectedBottomNavIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded),
              activeIcon: _ActiveNavigationIcon(icon: Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.analytics_rounded),
              activeIcon: _ActiveNavigationIcon(icon: Icons.analytics_rounded),
              label: 'Analytics',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.hub_rounded),
              activeIcon: _ActiveNavigationIcon(icon: Icons.hub_rounded),
              label: 'Hub',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyForSelectedTab(BuildContext context) {
    switch (_selectedBottomNavIndex) {
      case 2:
        return _buildHubTab(context);
      case 0:
      default:
        return _buildDashboardContent(context);
    }
  }

  Widget _buildDashboardContent(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: Container(
          constraints: kIsWeb
              ? const BoxConstraints(maxWidth: 1400)
              : const BoxConstraints(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderCard(context),
              const SizedBox(height: 28),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: _getResponsiveHorizontalPadding(context),
                  vertical: 0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildKeyMetricsSection(context),
                    SizedBox(
                      height: _getResponsiveVerticalSpacing(context, 28),
                    ),
                    _buildDiseaseTrendSection(context),
                    SizedBox(
                      height: _getResponsiveVerticalSpacing(context, 28),
                    ),
                    Center(
                      child: Text(
                        '© 2026 Healthcare Monitoring System. All rights reserved.',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: _mutedCoolGray),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHubTab(BuildContext context) {
    final hubCategories = <Map<String, dynamic>>[
      {
        'title': 'Patient Management',
        'subtitle': 'Check Up, Morbidity, Prenatal Care, Immunization',
        'icon': Icons.local_hospital_rounded,
        'color': _primaryAqua,
        'buttons': <Map<String, dynamic>>[
          {
            'label': 'Check Up',
            'icon': Icons.medical_services,
            'onTap': () => Get.to(() => const CheckUpPage()),
          },
          {
            'label': 'Morbidity',
            'icon': Icons.healing,
            'onTap': () => Get.to(() => const MorbidityListPage()),
          },
          {
            'label': 'Prenatal Care',
            'icon': Icons.pregnant_woman,
            'onTap': () => Get.to(() => const PrenatalPage()),
          },
          {
            'label': 'Immunization',
            'icon': Icons.vaccines,
            'onTap': () => Get.to(() => const ImmunizationPage()),
          },
        ],
      },
      {
        'title': 'Records',
        'subtitle': 'Patient Records',
        'icon': Icons.folder_copy_rounded,
        'color': Colors.tealAccent,
        'buttons': <Map<String, dynamic>>[
          {
            'label': 'Patient Records',
            'icon': Icons.folder_special,
            'onTap': () => Get.to(() => const PatientRecordPage()),
          },
        ],
      },
      {
        'title': 'Disease Monitoring',
        'subtitle': 'Communicable Disease, Non Communicable Disease, Mortality',
        'icon': Icons.monitor_heart_rounded,
        'color': Colors.orangeAccent,
        'buttons': <Map<String, dynamic>>[
          {
            'label': 'Communicable Disease',
            'icon': Icons.coronavirus,
            'onTap': () => Get.to(() => const CommunicableListPage()),
          },
          {
            'label': 'Non Communicable Disease',
            'icon': Icons.sick,
            'onTap': () => Get.to(() => const NonCommunicablePage()),
          },
          {
            'label': 'Mortality',
            'icon': Icons.airline_seat_flat,
            'onTap': () => Get.to(() => const MortalityPage()),
          },
        ],
      },
      {
        'title': 'Coordination',
        'subtitle': 'Referrals',
        'icon': Icons.forward_to_inbox_rounded,
        'color': Colors.deepPurpleAccent,
        'buttons': <Map<String, dynamic>>[
          {
            'label': 'Referrals',
            'icon': Icons.forward_to_inbox_rounded,
            'onTap': () => Get.to(() => const ReferralsPage()),
          },
        ],
      },
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HUB',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: _darkDeepTeal,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap a category to open the related modules.',
            style: TextStyle(color: AppDesign.muted, fontSize: 14),
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: hubCategories.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final category = hubCategories[index];
              final buttons = category['buttons'] as List<Map<String, dynamic>>;
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppDesign.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppDesign.border),
                  boxShadow: [
                    BoxShadow(
                      color: AppDesign.navy.withValues(alpha: 0.05),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category['title'] as String,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 18,
                            mainAxisSpacing: 18,
                            childAspectRatio: 1.15,
                          ),
                      itemCount: buttons.length,
                      itemBuilder: (context, buttonIndex) {
                        final button = buttons[buttonIndex];
                        return _buildHubIconButton(
                          icon: button['icon'] as IconData,
                          label: button['label'] as String,
                          onTap: button['onTap'] as void Function(),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHubIconButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _primaryAqua.withValues(alpha: 0.45),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _primaryAqua.withValues(alpha: 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: _primaryAqua, size: 48),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _darkDeepTeal,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  height: 1.18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isLoggedIn = user != null;
    if (_isOfflineMode && !_offlineSnackbarShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('You are now in offline mode.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      });
      _offlineSnackbarShown = true;
    }
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppDesign.page,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(0),
        child: Container(),
      ),
      drawer: SizedBox(
        width: 350,
        child: Drawer(
          backgroundColor: Colors.white,
          elevation: 0,
          child: Container(
            decoration: const BoxDecoration(color: Colors.white),
            child: Stack(
              children: [
                Positioned(
                  top: -70,
                  right: -50,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _primaryAqua.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 90,
                  left: -40,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _secondaryIceBlue.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      _buildDrawerProfileCard(
                        context,
                        user: user,
                        isLoggedIn: isLoggedIn,
                      ),
                      const SizedBox(height: 20),
                      _buildDrawerSection(
                        icon: Icons.local_hospital_rounded,
                        title: 'Patient Management',
                        subtitle: 'Daily clinical workflows and care tracking',
                        child: GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.12,
                          children: [
                            _buildDrawerCardButton(
                              icon: Icons.medical_services,
                              label: 'Check Up',
                              onTap: () {
                                Navigator.of(context).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const CheckUpPage(),
                                  ),
                                );
                              },
                            ),
                            _buildDrawerCardButton(
                              icon: Icons.healing,
                              label: 'Morbidity',
                              onTap: () {
                                Navigator.of(context).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const MorbidityListPage(),
                                  ),
                                );
                              },
                            ),
                            _buildDrawerCardButton(
                              icon: Icons.pregnant_woman,
                              label: 'Prenatal Care',
                              onTap: () {
                                Navigator.of(context).pop();
                                Get.to(() => const PrenatalPage());
                              },
                            ),
                            _buildDrawerCardButton(
                              icon: Icons.vaccines,
                              label: 'Immunization',
                              onTap: () {
                                Navigator.of(context).pop();
                                Get.to(() => const ImmunizationPage());
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDrawerSection(
                        icon: Icons.folder_copy_rounded,
                        title: 'Records Hub',
                        subtitle: 'Community registries and patient files',
                        child: GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.12,
                          children: [
                            _buildDrawerCardButton(
                              icon: Icons.folder_special,
                              label: 'Patient Records',
                              onTap: () {
                                Navigator.of(context).pop();
                                Get.to(() => const PatientRecordPage());
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDrawerSection(
                        icon: Icons.monitor_heart_rounded,
                        title: 'Disease Monitoring',
                        subtitle: 'Population health surveillance and outcomes',
                        child: GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.12,
                          children: [
                            _buildDrawerCardButton(
                              icon: Icons.coronavirus,
                              label: 'Communicable Disease',
                              onTap: () {
                                Navigator.pop(context);
                                Get.to(() => const CommunicableListPage());
                              },
                            ),
                            _buildDrawerCardButton(
                              icon: Icons.sick,
                              label: 'Non Communicable Disease',
                              onTap: () {
                                Navigator.pop(context);
                                Get.to(() => const NonCommunicablePage());
                              },
                            ),
                            _buildDrawerCardButton(
                              icon: Icons.airline_seat_flat,
                              label: 'Mortality',
                              onTap: () {
                                Navigator.pop(context);
                                Get.to(() => const MortalityPage());
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDrawerSection(
                        icon: Icons.hub_rounded,
                        title: 'Insights & Coordination',
                        subtitle:
                            'Open mobile analytics and referral workflows',
                        child: GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.12,
                          children: [
                            _buildDrawerCardButton(
                              icon: Icons.analytics_rounded,
                              label: 'Analytics',
                              onTap: () {
                                Navigator.pop(context);
                                Get.to(() => const AnalyticsPage());
                              },
                            ),
                            _buildDrawerCardButton(
                              icon: Icons.forward_to_inbox_rounded,
                              label: 'Referrals',
                              onTap: () {
                                Navigator.pop(context);
                                Get.to(() => const ReferralsPage());
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDrawerSection(
                        icon: isLoggedIn
                            ? Icons.verified_user_rounded
                            : Icons.login_rounded,
                        title: isLoggedIn ? 'Account Access' : 'Ready To Sync',
                        subtitle: isLoggedIn
                            ? 'Manage your authenticated mobile session'
                            : _isOfflineMode
                            ? 'Sign in or create an account to upload offline records'
                            : 'Sign in or create an account to unlock synced cloud access',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  if (isLoggedIn) {
                                    await signout();
                                    if (mounted) {
                                      _openLoginScreen(
                                        replaceCurrentRoute: true,
                                      );
                                    }
                                    return;
                                  }

                                  _openLoginScreen(
                                    replaceCurrentRoute: !_isOfflineMode,
                                    syncOfflineAfterLogin: _isOfflineMode,
                                  );
                                },
                                icon: Icon(
                                  isLoggedIn ? Icons.logout : Icons.login,
                                  size: 20,
                                ),
                                label: Text(
                                  isLoggedIn ? 'Sign Out' : 'Sign In',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isLoggedIn
                                      ? Colors.red.shade700
                                      : _primaryAqua,
                                  foregroundColor: Colors.white,
                                  elevation: 6,
                                  shadowColor:
                                      (isLoggedIn
                                              ? Colors.red.shade700
                                              : _primaryAqua)
                                          .withValues(alpha: 0.35),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                            if (!isLoggedIn) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: OutlinedButton.icon(
                                  onPressed: _openSignupScreen,
                                  icon: const Icon(
                                    Icons.person_add_alt_1_rounded,
                                  ),
                                  label: const Text('Create Account'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _secondaryIceBlue,
                                    side: BorderSide(
                                      color: _primaryAqua.withValues(
                                        alpha: 0.55,
                                      ),
                                      width: 1.4,
                                    ),
                                    backgroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _buildBodyForSelectedTab(context),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  // Custom Header Card with Drawer, Notification, Greeting, Username, Date, System Status, and Search
  Future<void> _showDashboardProfileDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    final isLoggedIn = user != null;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDrawerProfileCard(
                  dialogContext,
                  user: user,
                  isLoggedIn: isLoggedIn,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();

                      if (isLoggedIn) {
                        await signout();
                        if (mounted) {
                          _openLoginScreen(replaceCurrentRoute: true);
                        }
                        return;
                      }

                      _openLoginScreen(
                        replaceCurrentRoute: !_isOfflineMode,
                        syncOfflineAfterLogin: _isOfflineMode,
                      );
                    },
                    icon: Icon(
                      isLoggedIn ? Icons.logout_rounded : Icons.login_rounded,
                    ),
                    label: Text(isLoggedIn ? 'Logout' : 'Login'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLoggedIn
                          ? Colors.red.shade700
                          : _primaryAqua,
                      foregroundColor: isLoggedIn
                          ? _lightOffWhite
                          : _darkDeepTeal,
                      elevation: 6,
                      shadowColor:
                          (isLoggedIn ? Colors.red.shade700 : _primaryAqua)
                              .withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    final authenticatedUser = FirebaseAuth.instance.currentUser ?? widget.user;
    final authDisplayName = authenticatedUser?.displayName?.trim() ?? '';
    final emailName = authenticatedUser?.email?.split('@').first.trim() ?? '';
    final userName =
        _dashboardUserName ??
        (authDisplayName.isNotEmpty
            ? authDisplayName
            : emailName.isNotEmpty
            ? emailName
            : 'BHW User');
    final assignedBarangay =
        _dashboardBarangayName ??
        (_isOfflineMode ? 'Unavailable offline' : 'Loading...');
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
        ? 'Good Afternoon'
        : 'Good Evening';

    final now = DateTime.now();
    final formattedDate = '${_getMonthName(now.month)} ${now.day}, ${now.year}';
    final dayOfWeek = _getDayOfWeek(now.weekday);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppDesign.navy,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: left-aligned title and notification icon
              Row(
                children: [
                  Material(
                    color: _lightOffWhite.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: _showDashboardProfileDialog,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _lightOffWhite.withValues(alpha: 0.2),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.account_circle_rounded,
                          color: _lightOffWhite,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'DSUHIS',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: _lightOffWhite,
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                    ),
                  ),
                  // Notification Icon
                  Container(
                    decoration: BoxDecoration(
                      color: _lightOffWhite.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _lightOffWhite.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                    ),
                    child: Stack(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.notifications_none,
                            color: _lightOffWhite,
                            size: 28,
                          ),
                          onPressed: () => _showNotificationsPanel(context),
                          tooltip: 'Notifications',
                          padding: const EdgeInsets.all(8),
                        ),
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Color(0xFFFF5252),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Greeting Message and User Info Card
              SizedBox(
                width: double.infinity,
                child: Card(
                  elevation: 0,
                  color: _primaryAqua.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: _primaryAqua.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Greeting and Username (Left side)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Greeting
                              Text(
                                greeting,
                                style: TextStyle(
                                  color: _lightOffWhite,
                                  fontSize: kIsWeb ? 24 : 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 6),
                              // Username
                              Text(
                                userName,
                                style: TextStyle(
                                  color: _lightOffWhite.withValues(alpha: 0.9),
                                  fontSize: kIsWeb ? 16 : 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.4,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.location_on_outlined,
                                    color: _primaryAqua,
                                    size: 17,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Assigned Barangay: $assignedBarangay',
                                      style: TextStyle(
                                        color: _lightOffWhite.withValues(
                                          alpha: 0.76,
                                        ),
                                        fontSize: kIsWeb ? 14 : 12.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Date (Right side)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _lightOffWhite.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _lightOffWhite.withValues(alpha: 0.25),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today,
                                color: _lightOffWhite,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$dayOfWeek, $formattedDate',
                                style: TextStyle(
                                  color: _lightOffWhite,
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
                ),
              ),
              const SizedBox(height: 16),

              // System Status Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _lightOffWhite.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _primaryAqua.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Color(0xFF4CAF50).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.check_circle,
                        color: Color(0xFF4CAF50),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'System Status: Online',
                            style: TextStyle(
                              color: _lightOffWhite,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'All systems operational',
                            style: TextStyle(
                              color: _lightOffWhite.withValues(alpha: 0.75),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
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
    return months[month - 1];
  }

  // Compatibility alias for stale hot-reload closures that may still
  // reference the previous month label helper name.
  String _monthLabelShort(int month) {
    return _getMonthName(month);
  }

  String _getDayOfWeek(int day) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[day - 1];
  }

  // Helper method for responsive horizontal padding
  double _getResponsiveHorizontalPadding(BuildContext context) {
    if (kIsWeb) return 32.0;
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 350) return 12.0;
    if (screenWidth < 400) return 14.0;
    return 16.0;
  }

  // Helper method for responsive chart height
  double _getChartHeight(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 350) return 220.0;
    if (screenWidth < 400) return 250.0;
    return 300.0;
  }

  // Helper method for responsive vertical spacing
  double _getResponsiveVerticalSpacing(
    BuildContext context,
    double defaultSpacing,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 350) return defaultSpacing * 0.6;
    if (screenWidth < 400) return defaultSpacing * 0.8;
    return defaultSpacing;
  }

  // Primary Action Button (Card-style)
  Widget _buildPrimaryActionButton({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: color.withValues(alpha: 0.2),
        highlightColor: color.withValues(alpha: 0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white, color.withValues(alpha: 0.03)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: color.withValues(alpha: 0.25),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.12),
                blurRadius: 15,
                offset: const Offset(0, 5),
                spreadRadius: 0,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: Icon(icon, size: 32, color: Colors.white),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _darkDeepTeal,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                  fontSize: 14,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 30,
                height: 3,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Disease Trend Section
  Widget _buildDiseaseTrendSection(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;
    final responsivePadding = isSmallScreen ? 16.0 : 24.0;
    final chartHeight = isSmallScreen ? 250.0 : 300.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: Card(
            elevation: 1,
            shadowColor: AppDesign.navy.withValues(alpha: 0.08),
            color: AppDesign.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppDesign.border),
            ),
            child: Padding(
              padding: EdgeInsets.all(responsivePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _primaryAqua,
                              _primaryAqua.withValues(alpha: 0.8),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: _primaryAqua.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.trending_up,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Disease Trend - Multiple Symptoms',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: kIsWeb ? 20 : 16,
                                fontWeight: FontWeight.bold,
                                color: _darkDeepTeal,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Individual symptom trends over the last 30 days',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isSmallScreen ? 12 : 15,
                                color: AppDesign.muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildTrendSummaryTile(
                        label: 'SERIES',
                        value: '${_allSymptoms.length}',
                        icon: Icons.stacked_line_chart_rounded,
                      ),
                      const SizedBox(width: 8),
                      _buildTrendSummaryTile(
                        label: 'DATA POINTS',
                        value: '${_allDates.length}',
                        icon: Icons.scatter_plot_rounded,
                      ),
                      const SizedBox(width: 8),
                      _buildTrendSummaryTile(
                        label: 'WINDOW',
                        value: '30 days',
                        icon: Icons.date_range_rounded,
                      ),
                    ],
                  ),
                  SizedBox(height: responsivePadding / 1.5),
                  // Instructions
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 10 : 12,
                      vertical: isSmallScreen ? 6 : 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppDesign.blueSoft,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppDesign.border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppDesign.blue,
                          size: isSmallScreen ? 16 : 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Pinch to zoom • Tap dots to see symptom details',
                            style: TextStyle(
                              color: AppDesign.ink,
                              fontSize: isSmallScreen ? 11 : 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: responsivePadding / 1.5),
                  SizedBox(
                    height: _getChartHeight(context),
                    child: _isLoadingTrends
                        ? Center(
                            child: CircularProgressIndicator(
                              color: _primaryAqua,
                            ),
                          )
                        : _chartLines.isEmpty
                        ? Center(
                            child: Text(
                              'No disease data available',
                              style: TextStyle(
                                color: AppDesign.muted,
                                fontSize: 14,
                              ),
                            ),
                          )
                        : GestureDetector(
                            onScaleUpdate: (details) {
                              setState(() {
                                _chartZoom *= details.scale;
                                _chartZoom = _chartZoom.clamp(1.0, 5.0);
                              });
                            },
                            child: LineChart(
                              LineChartData(
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: true,
                                  horizontalInterval: 1,
                                  verticalInterval: 1,
                                  getDrawingHorizontalLine: (value) {
                                    return FlLine(
                                      color: AppDesign.border,
                                      strokeWidth: 1,
                                    );
                                  },
                                  getDrawingVerticalLine: (value) {
                                    return FlLine(
                                      color: AppDesign.border,
                                      strokeWidth: 1,
                                    );
                                  },
                                ),
                                titlesData: FlTitlesData(
                                  show: true,
                                  rightTitles: AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  topTitles: AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 40,
                                      getTitlesWidget:
                                          (double value, TitleMeta meta) {
                                            if (value.toInt() <
                                                _allDates.length) {
                                              return Text(
                                                _allDates[value.toInt()],
                                                style: TextStyle(
                                                  color: AppDesign.muted,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              );
                                            }
                                            return const Text('');
                                          },
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      interval: 1,
                                      getTitlesWidget:
                                          (double value, TitleMeta meta) {
                                            return Text(
                                              '${value.toInt()}',
                                              style: TextStyle(
                                                color: AppDesign.muted,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            );
                                          },
                                      reservedSize: 32,
                                    ),
                                  ),
                                ),
                                borderData: FlBorderData(
                                  show: true,
                                  border: Border(
                                    bottom: BorderSide(color: AppDesign.border),
                                    left: BorderSide(color: AppDesign.border),
                                  ),
                                ),
                                minX: 0,
                                maxX: (_allDates.length - 1).toDouble(),
                                minY: 0,
                                maxY: _chartLines.isNotEmpty
                                    ? _chartLines
                                              .map(
                                                (line) => line.spots
                                                    .map((spot) => spot.y)
                                                    .reduce(
                                                      (a, b) => a > b ? a : b,
                                                    ),
                                              )
                                              .reduce((a, b) => a > b ? a : b) +
                                          2
                                    : 10,
                                lineBarsData: _chartLines,
                                lineTouchData: LineTouchData(
                                  enabled: true,
                                  touchTooltipData: LineTouchTooltipData(
                                    getTooltipItems:
                                        (List<LineBarSpot> touchedBarSpots) {
                                          if (touchedBarSpots.isEmpty) {
                                            return [];
                                          }

                                          final xIndex = touchedBarSpots.first.x
                                              .toInt();
                                          if (xIndex >= _allDates.length) {
                                            return [];
                                          }

                                          final date = _allDates[xIndex];
                                          return touchedBarSpots.map((barSpot) {
                                            final barIndex = barSpot.barIndex;
                                            if (barIndex >= 0 &&
                                                barIndex <
                                                    _allSymptoms.length) {
                                              final symptom =
                                                  _allSymptoms[barIndex];
                                              final count = barSpot.y.toInt();
                                              return LineTooltipItem(
                                                '$symptom: $count',
                                                TextStyle(
                                                  color:
                                                      _symptomColors[symptom] ??
                                                      Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                                children: [TextSpan(text: '')],
                                              );
                                            }
                                            return null;
                                          }).toList();
                                        },
                                    tooltipPadding: const EdgeInsets.all(8),
                                    tooltipMargin: 8,
                                  ),
                                  handleBuiltInTouches: true,
                                  touchCallback:
                                      (
                                        FlTouchEvent event,
                                        LineTouchResponse? response,
                                      ) {
                                        if (event is FlTapUpEvent) {
                                          if (response != null &&
                                              response.lineBarSpots != null &&
                                              response
                                                  .lineBarSpots!
                                                  .isNotEmpty) {
                                            final touchedSpot =
                                                response.lineBarSpots![0];
                                            final xIndex = touchedSpot.x
                                                .toInt();
                                            if (xIndex < _allDates.length) {
                                              final date = _allDates[xIndex];
                                              final symptom =
                                                  _allSymptoms[touchedSpot
                                                      .barIndex];
                                              final count = touchedSpot.y
                                                  .toInt();

                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    '$symptom on $date: $count cases',
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  backgroundColor:
                                                      _symptomColors[symptom] ??
                                                      _primaryAqua,
                                                  duration: const Duration(
                                                    seconds: 2,
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        }
                                      },
                                ),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  // Legend showing symptoms and their colors
                  if (_allSymptoms.isNotEmpty)
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: _allSymptoms.map((symptom) {
                        final color = _symptomColors[symptom] ?? _primaryAqua;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: color.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                symptom,
                                style: const TextStyle(
                                  color: AppDesign.ink,
                                  fontSize: 12,
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
          ),
        ),
      ],
    );
  }

  Widget _buildTrendSummaryTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppDesign.blueSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppDesign.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: _primaryAqua, size: 14),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppDesign.muted,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: const TextStyle(
                color: AppDesign.ink,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Key Metrics Section
  Widget _buildKeyMetricsSection(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;
    final responsivePadding = isSmallScreen ? 16.0 : 24.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: Card(
            elevation: 0,
            color: AppDesign.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppDesign.border),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppDesign.navy.withValues(alpha: 0.07),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: AppDesign.navy.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.all(responsivePadding),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      _primaryAqua,
                                      _primaryAqua.withValues(alpha: 0.8),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _primaryAqua.withValues(
                                        alpha: 0.4,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.dashboard,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Key Performance Metrics',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: kIsWeb ? 23 : 21,
                                        fontWeight: FontWeight.bold,
                                        color: AppDesign.ink,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Real-time system overview',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: AppDesign.muted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (_isLoadingMetrics)
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _primaryAqua,
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _primaryAqua.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _primaryAqua.withValues(alpha: 0.25),
                                width: 1.5,
                              ),
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.refresh_rounded,
                                color: _primaryAqua,
                                size: 24,
                              ),
                              onPressed: _loadMetrics,
                              tooltip: 'Refresh metrics',
                              padding: EdgeInsets.zero,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _buildKeyMetricsMonthPickerButton()),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Column(
                      children: [
                        _buildMetricCard(
                          title: 'Total Patients',
                          value: _isLoadingMetrics
                              ? '...'
                              : '$_filteredPatientRegistrations',
                          unit: _metricFilterScopeLabel(),
                          icon: Icons.people_rounded,
                          color: _primaryAqua,
                          trend: '+12%',
                          trendLabel: 'vs last month',
                          isPositiveTrend: true,
                        ),
                        const SizedBox(height: 10),
                        _buildMetricCard(
                          title: 'Check-ups',
                          value: _isLoadingMetrics
                              ? '...'
                              : '$_filteredCheckupRecords',
                          unit: _metricFilterScopeLabel(),
                          icon: Icons.assignment_turned_in_rounded,
                          color: _darkDeepTeal,
                          trend: '+8%',
                          trendLabel: 'from last month',
                          isPositiveTrend: true,
                        ),
                        const SizedBox(height: 10),
                        _buildMetricCard(
                          title: 'Prenatal Care',
                          value: _isLoadingMetrics
                              ? '...'
                              : '$_filteredPrenatalRecords',
                          unit: _metricFilterScopeLabel(),
                          icon: Icons.pregnant_woman_rounded,
                          color: _primaryAqua,
                          trend: '+15%',
                          trendLabel: 'new this week',
                          isPositiveTrend: true,
                        ),
                        const SizedBox(height: 10),
                        _buildMetricCard(
                          title: 'Immunizations',
                          value: _isLoadingMetrics
                              ? '...'
                              : '$_filteredImmunizationRecords',
                          unit: _metricFilterScopeLabel(),
                          icon: Icons.vaccines_rounded,
                          color: _darkDeepTeal,
                          trend: '+10%',
                          trendLabel: 'completion rate',
                          isPositiveTrend: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Individual Metric Card. It uses intrinsic height so narrow phones do not
  // receive a forced grid height that can overflow its content.
  Widget _buildMetricCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
    required String trend,
    String trendLabel = '',
    bool isPositiveTrend = true,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppDesign.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppDesign.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppDesign.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppDesign.navy,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  unit,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppDesign.subtle,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: AppDesign.blueSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPositiveTrend
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 13,
                  color: AppDesign.navy,
                ),
                const SizedBox(width: 2),
                Text(
                  trend,
                  style: const TextStyle(
                    color: AppDesign.navy,
                    fontSize: 10,
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

  // Recent Activity Section
  Widget _buildHealthMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: color.withValues(alpha: 0.2),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: _mutedCoolGray,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: color.withValues(alpha: 0.2),
          child: Icon(icon, size: 28, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 14, color: _mutedCoolGray),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          size: 24,
          color: _mutedCoolGray,
        ),
      ),
    );
  }

  String _getDrawerDisplayName(User? user, bool isLoggedIn) {
    final displayName = user?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final email = user?.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }

    if (isLoggedIn) {
      return 'Authenticated User';
    }

    return _isOfflineMode ? 'Offline Guest' : 'Guest User';
  }

  String _getDrawerInitials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return 'HG';
    }

    if (parts.length == 1) {
      final word = parts.first;
      return word.length >= 2
          ? word.substring(0, 2).toUpperCase()
          : word.toUpperCase();
    }

    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Widget _buildDrawerStatusChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerMetricBadge({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _lightOffWhite.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _primaryAqua, size: 16),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                color: _lightOffWhite,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: _lightOffWhite.withValues(alpha: 0.68),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerProfileCard(
    BuildContext context, {
    required User? user,
    required bool isLoggedIn,
  }) {
    final displayName = _getDrawerDisplayName(user, isLoggedIn);
    final email = user?.email?.trim();
    final subtitle = isLoggedIn
        ? (email != null && email.isNotEmpty
              ? email
              : 'Cloud access is active on this device')
        : _isOfflineMode
        ? 'Offline mode keeps records on this device until you sign in.'
        : 'Sign in to unlock synced cloud access and account tools.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF102C34),
            const Color(0xFF0B2027),
            _secondaryIceBlue.withValues(alpha: 0.44),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: _lightOffWhite.withValues(alpha: 0.12),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
            spreadRadius: -12,
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -12,
            top: -22,
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _primaryAqua.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            left: -18,
            bottom: -36,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _lightOffWhite.withValues(alpha: 0.04),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_primaryAqua, _secondaryIceBlue],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _primaryAqua.withValues(alpha: 0.30),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Text(
                      _getDrawerInitials(displayName),
                      style: const TextStyle(
                        color: _lightOffWhite,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: _lightOffWhite,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      color: _lightOffWhite.withValues(
                                        alpha: 0.76,
                                      ),
                                      fontSize: 12.5,
                                      height: 1.35,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Material(
                              color: Colors.white.withValues(alpha: 0.07),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => Navigator.of(context).pop(),
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.close_rounded,
                                    color: _lightOffWhite,
                                    size: 18,
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
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildDrawerStatusChip(
                    icon: isLoggedIn
                        ? Icons.verified_user_rounded
                        : Icons.person_outline_rounded,
                    label: isLoggedIn ? 'Signed In' : 'Guest Session',
                    color: isLoggedIn ? _primaryAqua : const Color(0xFFFFC857),
                  ),
                  _buildDrawerStatusChip(
                    icon: _isOfflineMode
                        ? Icons.cloud_off_rounded
                        : Icons.cloud_done_rounded,
                    label: _isOfflineMode ? 'Offline Mode' : 'Cloud Ready',
                    color: _isOfflineMode
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFF7ED957),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _buildDrawerMetricBadge(
                    icon: Icons.people_alt_rounded,
                    label: 'Patients',
                    value: _isLoadingMetrics ? '--' : '$_totalPatients',
                  ),
                  const SizedBox(width: 10),
                  _buildDrawerMetricBadge(
                    icon: Icons.sync_rounded,
                    label: 'Storage',
                    value: isLoggedIn
                        ? 'Firestore'
                        : _isOfflineMode
                        ? 'Local'
                        : 'Limited',
                  ),
                ],
              ),
              if (_isOfflineMode) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFFFB74D).withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFFFB74D,
                          ).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.wifi_find_rounded,
                          color: Color(0xFFFFCC80),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isLoggedIn
                              ? 'You can keep working offline. Any pending local records will sync again when connectivity is available.'
                              : 'Continue recording data offline. When internet returns, log in to upload saved records to Firestore automatically.',
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.78),
                            fontSize: 12.2,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppDesign.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppDesign.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 10),
            spreadRadius: -14,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _primaryAqua.withValues(alpha: 0.92),
                      _secondaryIceBlue.withValues(alpha: 0.92),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _darkDeepTeal,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppDesign.muted,
                        fontSize: 12.2,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // Helper method for user detail rows in drawer
  Widget _buildUserDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: _mutedCoolGray, size: 18),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: _mutedCoolGray,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: _darkDeepTeal,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        // Use WidgetsBinding.instance.addPostFrameCallback for safe navigation
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onTap();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        decoration: BoxDecoration(
          color: _primaryAqua,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _primaryAqua.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: _darkDeepTeal),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _darkDeepTeal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerMenuButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, color.withValues(alpha: 0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 5,
            offset: const Offset(0, 1),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: color.withValues(alpha: 0.15),
          highlightColor: color.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withValues(alpha: 0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: _darkDeepTeal,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: color.withValues(alpha: 0.5),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerCardButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.08),
                _primaryAqua.withValues(alpha: 0.12),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppDesign.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 10),
                spreadRadius: -10,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _primaryAqua.withValues(alpha: 0.95),
                            _secondaryIceBlue.withValues(alpha: 0.95),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: Colors.white, size: 18),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_outward_rounded,
                        color: AppDesign.muted,
                        size: 14,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: _darkDeepTeal,
                        fontSize: 12.8,
                        fontWeight: FontWeight.w800,
                        height: 1.18,
                        letterSpacing: 0.12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveNavigationIcon extends StatelessWidget {
  const _ActiveNavigationIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: AppDesign.blueSoft,
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
      child: Icon(icon, color: AppDesign.blue, size: 24),
    );
  }
}

// Data classes for community_charts_flutter
class BarData {
  final String label;
  final int value;
  BarData(this.label, this.value);
}

class LineData {
  final int day;
  final int value;
  LineData(this.day, this.value);
}

class PieData {
  final String label;
  final int value;
  final charts.Color color;
  PieData(this.label, this.value, this.color);
}

// Power BI-style graph card widget
Widget _buildGraphCard({required String title, required Widget child}) {
  return Card(
    elevation: 4,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _darkDeepTeal,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(borderRadius: BorderRadius.circular(12), child: child),
        ],
      ),
    ),
  );
}
