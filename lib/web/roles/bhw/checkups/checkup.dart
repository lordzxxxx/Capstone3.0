import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/shared/components/app_buttons.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mycapstone_project/web/roles/bhw/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/app/core/services/health_ai_classifier.dart';
import 'package:mycapstone_project/app/core/services/disease_prediction_api_service.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:mycapstone_project/web/roles/bhw/dashboard/homepage.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/roles/bhw/analytics/health_metrics.dart';
import 'package:mycapstone_project/web/roles/cho/analytics/analytics.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal.dart';
import 'package:mycapstone_project/web/roles/bhw/immunization/immunization.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/communicable.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/non_communicable.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/mortality.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/shared/components/app_top_bar.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/shared/components/app_metric_card.dart';
import 'package:mycapstone_project/web/shared/components/web_data_components.dart';
import 'package:mycapstone_project/web/shared/components/fullscreen_detail_table_dialog.dart';
import 'package:mycapstone_project/web/shared/components/module_view_components.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_first_service_selector.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_identity_utils.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/shared_patient_search_panel.dart';
import 'package:mycapstone_project/web/roles/bhw/referrals/bhw_referral_management.dart';
import 'package:mycapstone_project/shared/current_table_record_utils.dart';
import 'package:mycapstone_project/web/shared/utils/checkup_pdf.dart';
import 'package:mycapstone_project/web/shared/utils/file_download.dart';
import 'package:mycapstone_project/web/shared/utils/report_generation.dart';
import 'package:mycapstone_project/web/shared/utils/vital_risk_flags.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

const Color _primaryAqua = Color(0xFF2F80ED);
const Color _secondaryIceBlue = Color(0xFF163B66);
const Color _darkDeepTeal = Color(0xFF071A33);
const Color _mutedCoolGray = Color(0xFF4B6075);
const Color _lightOffWhite = Color(0xFF0B1F3A);
const Color _sidebarDark = Colors.white;

ThemeData _buildDarkDatePickerTheme(BuildContext context) {
  return Theme.of(context).copyWith(
    // The rest of the module uses the light, high-contrast records surface.
    // Keep the picker on that same surface so dates and controls never become
    // white-on-white or inherit the old teal dark theme.
    colorScheme: const ColorScheme.light(
      primary: _primaryAqua,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: _lightOffWhite,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
  );
}

class CheckUpPage extends StatefulWidget {
  const CheckUpPage({super.key, this.initialPatient});

  final Map<String, dynamic>? initialPatient;

  @override
  State<CheckUpPage> createState() => _CheckUpPageState();
}

class _CheckUpPageState extends State<CheckUpPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  DateTime? _fromDate;
  DateTime? _toDate;

  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};
  bool _isDeleteDialogShowing = false;
  bool _isLoading = true;
  String? _loadErrorMessage;
  int _currentPage = 1;
  int _rowsPerPage = 10;
  String _statusFilter = 'All';
  String _selectedBarangay = 'All';
  String _selectedAgeGroup = 'All';
  String _selectedSex = 'All';
  String _sortField = 'Name';
  bool _sortAscending = true;
  String? _searchQuery;
  TextEditingController? _searchController;

  // Database-backed records
  List<Map<String, dynamic>> _records = [];
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  StreamSubscription<List<Map<String, dynamic>>>? _recordsSubscription;

  // Dashboard metrics
  int _totalCheckups = 0;
  int _thisMonthCheckups = 0;
  int _vitalRecordsCount = 0;
  List<Map<String, dynamic>> _sharedPatientMatches = [];
  bool _isSearchingSharedPatients = false;
  Timer? _sharedPatientSearchDebounce;
  late HealthModuleView _activeView;

  // AI Classifier
  final HealthAIClassifier _aiClassifier = HealthAIClassifier.instance;
  final SymptomGuidanceApiService _guidanceApi = SymptomGuidanceApiService();
  final PatientCenteredHistoryService _patientHistoryService =
      PatientCenteredHistoryService();

  @override
  void initState() {
    super.initState();
    _activeView = healthModuleViewFromUrl();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => persistHealthModuleView(WebRoutes.bhwCheckups, _activeView),
    );
    _setupRealtimeListener();
    _dbHelper.startConnectivityListener();
    _initializeAI();
    if (widget.initialPatient != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openAddCheckUpModal(patientSeed: widget.initialPatient);
        }
      });
    }
  }

  void _setActiveView(HealthModuleView view) {
    if (_activeView == view) return;
    setState(() {
      _activeView = view;
      _isSelectionMode = false;
      _selectedIndices.clear();
    });
    persistHealthModuleView(WebRoutes.bhwCheckups, view);
  }

  Future<void> _initializeAI() async {
    await _aiClassifier.initialize();
  }

  void _setupRealtimeListener() {
    // Listen to real-time updates from Firestore
    _recordsSubscription?.cancel();
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadErrorMessage = null;
      });
    }
    _recordsSubscription = _dbHelper.getRecordsStream().listen(
      (records) {
        _updateRecordsWithMetrics(records);
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _loadErrorMessage = error.toString();
        });
      },
    );
  }

  void _updateRecordsWithMetrics(List<Map<String, dynamic>> records) {
    // Calculate metrics
    final now = DateTime.now();
    final thisMonthCount = records.where((record) {
      try {
        final datetime = DateTime.parse(record['datetime'] ?? '');
        return datetime.year == now.year && datetime.month == now.month;
      } catch (e) {
        return false;
      }
    }).length;

    // Count records with vital signs
    final vitalRecords = records.where((record) {
      final details = record['details']?.toString() ?? '';
      return details.contains('BP:') ||
          details.contains('Temp:') ||
          details.contains('HR:');
    }).length;

    if (mounted) {
      setState(() {
        _records = records;
        _totalCheckups = records.length;
        _thisMonthCheckups = thisMonthCount;
        _vitalRecordsCount = vitalRecords;
        _isLoading = false;
        _loadErrorMessage = null;
      });
    }
  }

  @override
  void dispose() {
    _recordsSubscription?.cancel();
    _sharedPatientSearchDebounce?.cancel();
    _searchController?.dispose();
    _guidanceApi.close();
    super.dispose();
  }

  String get _effectiveSearchQuery {
    try {
      final value = _searchQuery;
      return value?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  TextEditingController get _effectiveSearchController {
    try {
      return _searchController ??= TextEditingController(
        text: _effectiveSearchQuery,
      );
    } catch (_) {
      final controller = TextEditingController(text: _effectiveSearchQuery);
      _searchController = controller;
      return controller;
    }
  }

  Future<void> _seedSampleData() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sample data initialization is disabled. Records now appear only from actual barangay transactions.',
        ),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _loadRecords() async {
    // This method is kept for compatibility but real-time listener
    // will automatically update the UI
    print('🔄 [CHECKUP] Manual load requested...');
    await _dbHelper.syncFromFirebase();
  }

  Widget _buildLoadErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.orange,
                size: 54,
              ),
              const SizedBox(height: 16),
              const Text(
                'Check-up records could not be loaded.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _lightOffWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _loadErrorMessage ??
                    'The signed-in account may still be syncing its barangay scope. Try signing out and signing in again.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _mutedCoolGray,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _setupRealtimeListener,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryAqua,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSharedPatientTimeline(Map<String, dynamic> patient) async {
    final snapshot = await _patientHistoryService.loadPatientHistory(patient);
    if (!mounted) {
      return;
    }

    await PatientHistoryDialogs.showPatientTimelineDialog(
      context: context,
      patient: patient,
      snapshot: snapshot,
    );
  }

  void _scheduleSharedPatientSearch(String query) {
    _sharedPatientSearchDebounce?.cancel();
    final normalizedQuery = query.trim();

    if (normalizedQuery.isEmpty) {
      if (!mounted) {
        return;
      }

      setState(() {
        _sharedPatientMatches = [];
        _isSearchingSharedPatients = false;
      });
      return;
    }

    setState(() {
      _isSearchingSharedPatients = true;
    });

    _sharedPatientSearchDebounce = Timer(
      const Duration(milliseconds: 250),
      () async {
        final results = await _patientHistoryService.searchPatients(
          normalizedQuery,
        );
        if (!mounted ||
            _effectiveSearchQuery.toLowerCase() !=
                normalizedQuery.toLowerCase()) {
          return;
        }

        setState(() {
          _sharedPatientMatches = results;
          _isSearchingSharedPatients = false;
        });
      },
    );
  }

  Future<void> _openAddCheckUpModal({Map<String, dynamic>? patientSeed}) async {
    patientSeed = await _patientHistoryService.resolveRegisteredPatient(
      patientSeed,
    );
    if (patientSeed == null) {
      patientSeed = await PatientFirstServiceSelector.selectRegisteredPatient(
        context,
        serviceLabel: 'Check-up',
        patientService: _patientHistoryService,
        onRegisterPatient: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const PatientRecordPage(openRegistrationOnLoad: true),
          ),
        ),
      );
      if (!mounted || patientSeed == null) return;
    }
    print('➕ [CHECKUP] Add new check-up button pressed');
    final result = await showDialog<Object>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _NewCheckUpFullScreenModal(
        onSave: (record) => _dbHelper.insertRecord(record),
        guidanceApi: _guidanceApi,
        patientSeed: patientSeed,
      ),
    );

    if (result is _ReferralHandoff) {
      print('✅ [CHECKUP] New record added, opening referral for it');
      if (mounted) _openReferralAfterSave(result.record);
    } else if (result != null) {
      print('✅ [CHECKUP] New record added for disease type: $result');
    }
  }

  List<Map<String, dynamic>> _getCheckUpHistory(Map<String, dynamic> record) {
    return PatientHistoryDialogs.collectHistory(
      seedRecord: record,
      records: _records,
      idKeys: const ['linkedPatientId', 'patientId'],
      nameKeys: const ['patient', 'patientName'],
      sortDateKeys: const ['datetime', 'followup'],
    );
  }

  Map<String, dynamic> _buildPatientHistorySeed(Map<String, dynamic> record) {
    final patientName = _safeCheckUpText(
      record['patientName'] ?? record['patient'] ?? record['name'],
      fallback: '',
    );
    final nameParts = patientName.isEmpty
        ? <String>[]
        : patientName.split(RegExp(r'\s+'));

    return {
      'id': record['linkedPatientId'] ?? record['patientId'] ?? record['id'],
      'patientId': record['patientId'] ?? record['linkedPatientId'] ?? '',
      'patientCode': record['patientCode'] ?? '',
      'patientName': patientName,
      'firstName': nameParts.isNotEmpty ? nameParts.first : '',
      'surname': nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '',
    };
  }

  Future<void> _showPatientMedicalHistory(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    final patient = _buildPatientHistorySeed(record);
    final snapshot = await _patientHistoryService.loadPatientHistory(patient);
    if (!mounted) {
      return;
    }

    await PatientHistoryDialogs.showPatientTimelineDialog(
      context: context,
      patient: patient,
      snapshot: snapshot,
    );
  }

  void _showCheckUpHistory(BuildContext context, Map<String, dynamic> record) {
    final history = _getCheckUpHistory(record);
    PatientHistoryDialogs.showModuleHistoryDialog(
      context: context,
      moduleTitle: 'Check Up',
      seedRecord: record,
      history: history,
      description:
          'Review the patient\'s previous check-up visits before recording the next visit for the same patient.',
      addButtonLabel: 'Add Another Check-Up',
      titleBuilder: (entry) => _safeCheckUpText(
        entry['ai_category'],
        fallback: _safeCheckUpText(entry['status'], fallback: 'Check-up visit'),
      ),
      subtitleBuilder: (entry) =>
          'Symptoms: ${_safeCheckUpText(entry['symptoms'], fallback: 'No symptoms recorded')}',
      metaBuilder: (entry) {
        final visit = _formatCheckUpDateTime(entry['datetime']);
        final followUp = _formatCheckUpDate(entry['followup'], fallback: 'N/A');
        return 'Visit: $visit | Follow-up: $followUp';
      },
      dateKeys: const ['datetime', 'followup'],
      secondaryActionLabel: 'Medical History',
      onSecondaryAction: () => _showPatientMedicalHistory(context, record),
      onAddAnother: () => _openAddCheckUpModal(
        patientSeed: history.isNotEmpty ? history.first : record,
      ),
      onOpenRecord: (entry) => _showCheckUpDetails(context, entry),
    );
  }

  void _openReferralForRecord(Map<String, dynamic> record) {
    final patientSeed = _buildPatientHistorySeed(record);
    final hasLinkedPatient =
        (patientSeed['patientId'] as String?)?.isNotEmpty == true ||
        (patientSeed['id']?.toString().isNotEmpty ?? false);

    if (!hasLinkedPatient) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "This check-up isn't linked to a registered patient. Search for the patient to continue.",
          ),
        ),
      );
      _openReferralOverlay();
      return;
    }

    final referralSeed = <String, dynamic>{
      ...patientSeed,
      'age': record['age'],
      'address': record['address'],
      'barangay': record['barangay'],
    };

    final vitals = _safeCheckUpText(record['vitalsigns'], fallback: '');
    final symptoms = _safeCheckUpText(record['symptoms'], fallback: '');
    final observationsParts = <String>[
      if (vitals.isNotEmpty) 'Vitals: $vitals',
      if (symptoms.isNotEmpty) 'Symptoms: $symptoms',
    ];

    _openReferralOverlay(
      initialPatient: referralSeed,
      initialObservations: observationsParts.join('. '),
    );
  }

  /// Opens referral creation as a full-screen dialog over this page instead
  /// of navigating to /bhw/referrals — the BHW stays on Check-ups the whole
  /// time and the dialog just closes when the referral is submitted or
  /// cancelled, so there's nothing to "go back" from.
  void _openReferralOverlay({
    Map<String, dynamic>? initialPatient,
    String? initialObservations,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BhwReferralPage(
        embedded: true,
        initialPatient: initialPatient,
        initialObservations: initialObservations,
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  /// Opens the referral overlay for a check-up record that was just saved
  /// from the "Add Another Check-Up" modal (see [_ReferralHandoff]).
  void _openReferralAfterSave(Map<String, dynamic> savedRecord) {
    final patientId = (savedRecord['patientId'] ?? '').toString().trim();
    final linkedPatientId = (savedRecord['linkedPatientId'] ?? '')
        .toString()
        .trim();
    if (patientId.isEmpty && linkedPatientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "This check-up isn't linked to a registered patient. Search for the patient to continue.",
          ),
        ),
      );
      _openReferralOverlay();
      return;
    }

    final referralSeed = <String, dynamic>{
      'patientId': patientId.isNotEmpty ? patientId : linkedPatientId,
      'linkedPatientId': linkedPatientId.isNotEmpty
          ? linkedPatientId
          : patientId,
      'patientName': savedRecord['patientName'],
      'age': savedRecord['age'],
      'address': savedRecord['address'],
    };

    final vitals = (savedRecord['vitalsigns'] ?? '').toString();
    final symptoms = (savedRecord['symptoms'] ?? '').toString();
    final observationsParts = <String>[
      if (vitals.isNotEmpty) 'Vitals: $vitals',
      if (symptoms.isNotEmpty) 'Symptoms: $symptoms',
    ];

    _openReferralOverlay(
      initialPatient: referralSeed,
      initialObservations: observationsParts.join('. '),
    );
  }

  List<Map<String, dynamic>> get _filteredRecords {
    List<Map<String, dynamic>> filtered;

    if (_fromDate == null && _toDate == null) {
      filtered = List<Map<String, dynamic>>.from(_records);
    } else {
      filtered = _records.where((record) {
        try {
          final recordDate = DateTime.parse(
            record['datetime']?.split(' ')[0] ?? '',
          );

          // Check if record is within date range
          if (_fromDate != null && recordDate.isBefore(_fromDate!)) {
            return false;
          }
          if (_toDate != null && recordDate.isAfter(_toDate!)) {
            return false;
          }

          return true;
        } catch (e) {
          return false;
        }
      }).toList();
    }

    if (_statusFilter != 'All') {
      final targetStatus = _statusFilter.toLowerCase();
      filtered = filtered.where((record) {
        final status = (record['status'] ?? '').toString().trim().toLowerCase();
        return status == targetStatus;
      }).toList();
    }

    final searchQuery = _effectiveSearchQuery;
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      filtered = filtered.where((record) {
        final patientName = (record['patient'] ?? record['patientName'] ?? '')
            .toString()
            .toLowerCase();
        final address = (record['address'] ?? '').toString().toLowerCase();
        final age = (record['age'] ?? '').toString().toLowerCase();
        final symptoms = (record['symptoms'] ?? '').toString().toLowerCase();
        final status = (record['status'] ?? '').toString().toLowerCase();
        final diagnosis = (record['ai_category'] ?? record['diseaseType'] ?? '')
            .toString()
            .toLowerCase();

        return patientName.contains(query) ||
            address.contains(query) ||
            age.contains(query) ||
            symptoms.contains(query) ||
            status.contains(query) ||
            diagnosis.contains(query);
      }).toList();
    }

    if (_selectedBarangay != 'All') {
      final targetBarangay = _selectedBarangay.toLowerCase();
      filtered = filtered.where((record) {
        final address = (record['address'] ?? record['barangay'] ?? '')
            .toString()
            .toLowerCase();
        return address.contains(targetBarangay);
      }).toList();
    }

    if (_selectedAgeGroup != 'All') {
      filtered = filtered.where((record) {
        final age = int.tryParse(record['age']?.toString() ?? '') ?? -1;
        if (age < 0) return true;
        switch (_selectedAgeGroup) {
          case '0–5':
            return age >= 0 && age <= 5;
          case '6–17':
            return age >= 6 && age <= 17;
          case '18–59':
            return age >= 18 && age <= 59;
          case '60+':
            return age >= 60;
          default:
            return true;
        }
      }).toList();
    }

    if (_selectedSex != 'All') {
      final targetSex = _selectedSex.toLowerCase();
      filtered = filtered.where((record) {
        final sex = (record['gender'] ?? record['sex'] ?? '')
            .toString()
            .toLowerCase();
        return sex == targetSex ||
            (targetSex == 'male' && sex.startsWith('m')) ||
            (targetSex == 'female' && sex.startsWith('f'));
      }).toList();
    }

    // Sort records based on _sortField and _sortAscending
    filtered.sort((a, b) {
      int comparison = 0;
      switch (_sortField) {
        case 'Date':
          final aDate = (a['datetime'] ?? a['date'] ?? a['createdAt'] ?? '')
              .toString();
          final bDate = (b['datetime'] ?? b['date'] ?? b['createdAt'] ?? '')
              .toString();
          comparison = aDate.compareTo(bDate);
          break;
        case 'Age':
          final aAge = int.tryParse(a['age']?.toString() ?? '') ?? 0;
          final bAge = int.tryParse(b['age']?.toString() ?? '') ?? 0;
          comparison = aAge.compareTo(bAge);
          break;
        case 'Status':
          final aStatus = (a['status'] ?? '').toString();
          final bStatus = (b['status'] ?? '').toString();
          comparison = aStatus.compareTo(bStatus);
          break;
        case 'Name':
        default:
          final aName = (a['patient'] ?? a['patientName'] ?? a['name'] ?? '')
              .toString()
              .toLowerCase();
          final bName = (b['patient'] ?? b['patientName'] ?? b['name'] ?? '')
              .toString()
              .toLowerCase();
          comparison = aName.compareTo(bName);
          break;
      }
      return _sortAscending ? comparison : -comparison;
    });

    // Keep original order but prioritize pending records at the top.
    final pending = <Map<String, dynamic>>[];
    final others = <Map<String, dynamic>>[];

    for (final record in filtered) {
      final status = (record['status'] ?? '').toString().trim().toLowerCase();
      if (status == 'pending') {
        pending.add(record);
      } else {
        others.add(record);
      }
    }

    final collapsed = CurrentTableRecordUtils.collapseToLatestPerEntity(
      [...pending, ...others],
      idKeys: const ['linkedPatientId', 'patientId', 'patientCode'],
      nameKeys: const ['patient', 'patientName'],
      dateKeys: const ['datetime', 'followup', 'updatedAt', 'createdAt'],
    );

    final pendingCollapsed = <Map<String, dynamic>>[];
    final otherCollapsed = <Map<String, dynamic>>[];
    for (final record in collapsed) {
      final status = (record['status'] ?? '').toString().trim().toLowerCase();
      if (status == 'pending') {
        pendingCollapsed.add(record);
      } else {
        otherCollapsed.add(record);
      }
    }

    return [...pendingCollapsed, ...otherCollapsed];
  }

  Future<void> _generateCheckupReport() {
    return generateReportPdf(
      context: context,
      moduleLabel: 'Check-up',
      records: _filteredRecords,
      dateResolver: (record) => parseReportDateValue(record['datetime']),
      columns: [
        ReportCsvColumn(
          'Patient Name',
          (record) => reportText(record['patient']),
          flex: 1.4,
        ),
        ReportCsvColumn(
          'Age',
          (record) => reportText(record['age']),
          flex: 0.55,
          center: true,
        ),
        ReportCsvColumn(
          'Sex',
          (record) => reportText(record['gender'] ?? record['sex']),
          flex: 0.55,
          center: true,
        ),
        ReportCsvColumn(
          'Address / Barangay',
          (record) => reportText(record['address']),
          flex: 1.35,
        ),
        ReportCsvColumn(
          'Date of Check-up',
          (record) => formatReportDateValue(record['datetime']),
          flex: 0.95,
          center: true,
        ),
        ReportCsvColumn(
          'Chief Complaint',
          (record) => reportText(record['symptoms']),
          flex: 1.25,
        ),
        ReportCsvColumn(
          'Findings',
          (record) => reportText(
            record['details'],
            fallback: reportText(record['vitalsigns']),
          ),
          flex: 1.35,
        ),
        ReportCsvColumn(
          'Diagnosis',
          (record) => reportText(
            record['diagnosis'],
            fallback: reportText(
              record['diseaseType'],
              fallback: reportText(record['ai_category']),
            ),
          ),
          flex: 1.05,
        ),
        ReportCsvColumn(
          'Treatment / Action Taken',
          (record) => reportText(record['plan']),
          flex: 1.35,
        ),
        ReportCsvColumn('Remarks', (record) {
          final followup = reportText(record['followup'], fallback: '');
          final parts = <String>[
            'Status: ${reportText(record['status'], fallback: 'Completed')}',
          ];
          if (followup.isNotEmpty) {
            parts.add('Follow-up: $followup');
          }
          return reportJoin(
            parts,
            separator: ' | ',
            fallback: reportText(record['remarks']),
          );
        }, flex: 1.1),
      ],
      accentColor: _primaryAqua,
      dialogColor: _sidebarDark,
      textColor: Colors.white,
      mutedColor: Colors.white70,
      sectionTitleBuilder: (record, index) =>
          'Record ${index + 1}: ${reportText(record['patient'], fallback: 'Unknown patient')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.email?.split('@')[0] ?? 'User';
    final filteredRecords = _filteredRecords;
    final effectiveRowsPerPage = _rowsPerPage > 0 ? _rowsPerPage : 10;
    final totalPages = filteredRecords.isEmpty
        ? 1
        : ((filteredRecords.length + effectiveRowsPerPage - 1) ~/
              effectiveRowsPerPage);
    final currentPage = _currentPage < 1
        ? 1
        : (_currentPage > totalPages ? totalPages : _currentPage);
    final pageStartIndex = filteredRecords.isEmpty
        ? 0
        : (currentPage - 1) * effectiveRowsPerPage;
    final pageEndIndex = filteredRecords.isEmpty
        ? 0
        : math.min(
            pageStartIndex + effectiveRowsPerPage,
            filteredRecords.length,
          );
    final pagedRecords = filteredRecords.isEmpty
        ? <Map<String, dynamic>>[]
        : filteredRecords.sublist(pageStartIndex, pageEndIndex);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F7FA),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WebAppSidebar(
            userName: userName,
            activeItem: WebSidebarItem.checkups,
          ),
          Expanded(
            child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                              CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _primaryAqua,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Loading check-up records...',
                                style: TextStyle(
                                  color: _lightOffWhite,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _loadErrorMessage != null
                      ? _buildLoadErrorState()
                      : Stack(
                          children: [
                            SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 12.0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  HealthModuleViewHeader(
                                    title: 'Check-up Management',
                                    description:
                                        'Review service activity and vital-sign coverage, or manage individual check-up records.',
                                    activeView: _activeView,
                                    onViewChanged: _setActiveView,
                                    primaryColor: _primaryAqua,
                                  ),
                                  const SizedBox(height: 16),
                                  // Dashboard Header with Metrics
                                  if (_activeView ==
                                      HealthModuleView.insights) ...[
                                    if (_records.isEmpty)
                                      const ModuleEmptyState(
                                        title: 'No check-up insights yet',
                                        message:
                                            'Add a check-up record to begin monitoring service activity and vital-sign coverage.',
                                        icon: Icons.monitor_heart_outlined,
                                      )
                                    else
                                      _CheckUpDashboardHeader(
                                        totalCheckups: _totalCheckups,
                                        thisMonthCheckups: _thisMonthCheckups,
                                        vitalRecordsCount: _vitalRecordsCount,
                                        records: _records,
                                      ),
                                    const SizedBox(height: 16),
                                  ],

                                  // Records Section - Merged with Add, Filter, and Selection Controls
                                  if (_activeView == HealthModuleView.records)
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: _primaryAqua.withValues(
                                            alpha: 0.3,
                                          ),
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Top Control Bar - Filter, Add Button, Mode Toggle
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              _buildSearchBar(),
                                              if (_effectiveSearchQuery
                                                      .isNotEmpty ||
                                                  _isSearchingSharedPatients) ...[
                                                const SizedBox(height: 12),
                                                SharedPatientSearchPanel(
                                                  query: _effectiveSearchQuery,
                                                  results:
                                                      _sharedPatientMatches,
                                                  isLoading:
                                                      _isSearchingSharedPatients,
                                                  primaryActionLabel:
                                                      'View Medical History',
                                                  onPrimaryAction:
                                                      _showSharedPatientTimeline,
                                                  secondaryActionLabel:
                                                      'Start Check-Up',
                                                  onSecondaryAction:
                                                      (patient) =>
                                                          _openAddCheckUpModal(
                                                            patientSeed:
                                                                patient,
                                                          ),
                                                ),
                                              ],
                                              const SizedBox(height: 12),

                                              // Filter Section
                                              _buildFilterSection(),
                                              const SizedBox(height: 12),

                                              // Row with Selection Mode Toggle Button (from _buildActionMenuButton)
                                              Row(
                                                children: [
                                                  // Selection Mode Toggle Button
                                                  if (!_isSelectionMode)
                                                    Material(
                                                      color: Colors.transparent,
                                                      child: InkWell(
                                                        onTap: () {
                                                          setState(() {
                                                            _isSelectionMode =
                                                                true;
                                                            _selectedIndices
                                                                .clear();
                                                          });
                                                        },
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 12,
                                                                vertical: 10,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            border: Border.all(
                                                              color: _primaryAqua
                                                                  .withValues(
                                                                    alpha: 0.3,
                                                                  ),
                                                              width: 1,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  10,
                                                                ),
                                                          ),
                                                          child: Row(
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .check_circle_outline,
                                                                color:
                                                                    _primaryAqua,
                                                                size: 18,
                                                              ),
                                                              const SizedBox(
                                                                width: 6,
                                                              ),
                                                              const Text(
                                                                'Select',
                                                                style: TextStyle(
                                                                  color:
                                                                      _lightOffWhite,
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    )
                                                  else
                                                    Material(
                                                      color: Colors.transparent,
                                                      child: InkWell(
                                                        onTap: () {
                                                          setState(() {
                                                            _isSelectionMode =
                                                                false;
                                                            _selectedIndices
                                                                .clear();
                                                          });
                                                        },
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 12,
                                                                vertical: 10,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: _primaryAqua
                                                                .withValues(
                                                                  alpha: 0.2,
                                                                ),
                                                            border: Border.all(
                                                              color: _primaryAqua
                                                                  .withValues(
                                                                    alpha: 0.5,
                                                                  ),
                                                              width: 1,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  10,
                                                                ),
                                                          ),
                                                          child: const Row(
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .check_circle,
                                                                color:
                                                                    _primaryAqua,
                                                                size: 18,
                                                              ),
                                                              SizedBox(
                                                                width: 6,
                                                              ),
                                                              Text(
                                                                'Done',
                                                                style: TextStyle(
                                                                  color:
                                                                      _primaryAqua,
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  const Spacer(),
                                                  _buildHighlightedAddButtonContainer(),
                                                ],
                                              ),
                                              const SizedBox(height: 16),
                                            ],
                                          ),

                                          // Records Display
                                          if (filteredRecords.isEmpty)
                                            Center(
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  40,
                                                ),
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            20,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: _primaryAqua
                                                            .withValues(
                                                              alpha: 0.2,
                                                            ),
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Icon(
                                                        Icons.inbox_rounded,
                                                        color: _primaryAqua,
                                                        size: 48,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 16),
                                                    Text(
                                                      'No records found',
                                                      style: TextStyle(
                                                        color: _lightOffWhite,
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      'Try adjusting your filters or add a new check-up record',
                                                      style: TextStyle(
                                                        color: _mutedCoolGray,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            )
                                          else
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                _buildCheckUpCardHeader(),
                                                _CheckUpTable(
                                                  records: pagedRecords,
                                                  startIndex: pageStartIndex,
                                                  isSelectionMode:
                                                      _isSelectionMode,
                                                  selectedIndices:
                                                      _selectedIndices,
                                                  onSelectionChanged:
                                                      (index, selected) {
                                                        setState(() {
                                                          if (selected) {
                                                            _selectedIndices
                                                                .add(index);
                                                          } else {
                                                            _selectedIndices
                                                                .remove(index);
                                                          }
                                                        });
                                                      },
                                                  onEdit: (record) async {
                                                    await showDialog<void>(
                                                      context: context,
                                                      builder: (context) =>
                                                          _EditCheckUpFullScreenModal(
                                                            record: record,
                                                            onSave:
                                                                (
                                                                  id,
                                                                  updatedRecord,
                                                                ) => _dbHelper
                                                                    .updateRecord(
                                                                      id,
                                                                      updatedRecord,
                                                                    ),
                                                            aiClassifier:
                                                                _aiClassifier,
                                                            guidanceApi:
                                                                _guidanceApi,
                                                          ),
                                                    );
                                                  },
                                                  onViewHistory: (record) =>
                                                      _showCheckUpHistory(
                                                        context,
                                                        record,
                                                      ),
                                                  onRefer: (record) =>
                                                      _openReferralForRecord(
                                                        record,
                                                      ),
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        'Showing ${pageStartIndex + 1}-$pageEndIndex of ${filteredRecords.length} records',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: _mutedCoolGray,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        border: Border.all(
                                                          color: _primaryAqua
                                                              .withValues(
                                                                alpha: 0.25,
                                                              ),
                                                        ),
                                                      ),
                                                      child: DropdownButtonHideUnderline(
                                                        child: DropdownButton<int>(
                                                          dropdownColor:
                                                              Colors.white,
                                                          value:
                                                              effectiveRowsPerPage,
                                                          style: const TextStyle(
                                                            color:
                                                                _lightOffWhite,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                          iconEnabledColor:
                                                              _primaryAqua,
                                                          items: const [
                                                            DropdownMenuItem(
                                                              value: 10,
                                                              child: Text(
                                                                '10 / page',
                                                              ),
                                                            ),
                                                            DropdownMenuItem(
                                                              value: 20,
                                                              child: Text(
                                                                '20 / page',
                                                              ),
                                                            ),
                                                            DropdownMenuItem(
                                                              value: 50,
                                                              child: Text(
                                                                '50 / page',
                                                              ),
                                                            ),
                                                          ],
                                                          onChanged: (value) {
                                                            if (value == null) {
                                                              return;
                                                            }
                                                            setState(() {
                                                              _rowsPerPage =
                                                                  value > 0
                                                                  ? value
                                                                  : 10;
                                                              _currentPage = 1;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    IconButton(
                                                      tooltip: 'Previous page',
                                                      onPressed: currentPage > 1
                                                          ? () {
                                                              setState(() {
                                                                _currentPage =
                                                                    currentPage -
                                                                    1;
                                                              });
                                                            }
                                                          : null,
                                                      icon: const Icon(
                                                        Icons.chevron_left,
                                                      ),
                                                      color: _mutedCoolGray,
                                                    ),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 6,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        border: Border.all(
                                                          color: _primaryAqua
                                                              .withValues(
                                                                alpha: 0.25,
                                                              ),
                                                        ),
                                                      ),
                                                      child: Text(
                                                        '$currentPage / $totalPages',
                                                        style: const TextStyle(
                                                          color: _lightOffWhite,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                    IconButton(
                                                      tooltip: 'Next page',
                                                      onPressed:
                                                          currentPage <
                                                              totalPages
                                                          ? () {
                                                              setState(() {
                                                                _currentPage =
                                                                    currentPage +
                                                                    1;
                                                              });
                                                            }
                                                          : null,
                                                      icon: const Icon(
                                                        Icons.chevron_right,
                                                      ),
                                                      color: _lightOffWhite,
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(height: 32),
                                ],
                              ),
                            ),
                            // Bulk Selection Action Card - Floating at bottom
                            if (_activeView == HealthModuleView.records)
                              _buildSelectionActionCard(),
                          ],
                        ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, String userName) {
    final user = FirebaseAuth.instance.currentUser;
    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_sidebarDark, _sidebarDark.withValues(alpha: 0.95)],
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: 20.0,
                horizontal: 16.0,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_primaryAqua, _secondaryIceBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _primaryAqua.withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/bg3.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: _mutedCoolGray,
                            child: Icon(
                              Icons.person,
                              size: 35,
                              color: _primaryAqua,
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
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    user?.email ?? '',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
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
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
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
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.greenAccent,
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Online',
                          style: TextStyle(
                            color: Colors.white,
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
                      color: Colors.white.withValues(alpha: 0.5),
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
                    isActive: true,
                    onTap: () {
                      Navigator.pop(context);
                    },
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
                            color: Colors.white.withValues(alpha: 0.5),
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
                            color: Colors.white.withValues(alpha: 0.5),
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
                    color: Colors.white.withValues(alpha: 0.1),
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
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Logout',
                          style: TextStyle(
                            color: Colors.white,
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
          hoverColor: Colors.white.withValues(alpha: 0.08),
          splashColor: _primaryAqua.withValues(alpha: 0.2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: isActive ? _primaryAqua.withValues(alpha: 0.18) : null,
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
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    icon,
                    color: isActive
                        ? _primaryAqua
                        : Colors.white.withValues(alpha: 0.8),
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
                          : Colors.white.withValues(alpha: 0.8),
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
                      color: Colors.white,
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

  Widget _buildTopBar(BuildContext context) {
    return WebAppTopBar(
      title: 'Check-up Dashboard',
      scaffoldKey: _scaffoldKey,
      isLoading: _isLoading,
      onGenerateReport: _generateCheckupReport,
      onRefresh: () => _loadRecords(),
      actions: [
        if (kDebugMode) ...[
          const SizedBox(width: 4),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert_outlined, color: Colors.white),
            color: _darkDeepTeal,
            itemBuilder: (context) => [
              PopupMenuItem(
                child: const Text('Seed Sample Data', style: TextStyle(color: Colors.white)),
                onTap: () => _seedSampleData(),
              ),
              PopupMenuItem(
                child: const Text('View Data in Console', style: TextStyle(color: Colors.white)),
                onTap: () {
                  print('=== CHECK-UP RECORDS DATA ===');
                  print('Total Records: ${_records.length}');
                  for (var i = 0; i < _records.length; i++) {
                    print('\nRecord ${i + 1}:');
                    _records[i].forEach((key, value) {
                      print('  $key: $value');
                    });
                  }
                  print('=============================');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Data printed to console! Check Debug Console.',
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildHighlightedAddButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openAddCheckUpModal,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _primaryAqua,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.add_circle_outline_rounded,
                color: Colors.white,
                size: 18,
              ),
              SizedBox(width: 6),
              Text(
                'Add Record',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedAddButtonContainer() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _primaryAqua.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
      child: _buildHighlightedAddButton(),
    );
  }

  Widget _buildHeaderCell(String label, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildHeaderDivider() {
    return Container(
      width: 1,
      height: 18,
      color: Colors.white.withValues(alpha: 0.2),
    );
  }

  Widget _buildCheckUpCardHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF163B66),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          if (_isSelectionMode) ...[
            SizedBox(
              width: 38,
              child: Text(
                'Sel',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          _buildHeaderCell('Patient', flex: 26),
          _buildHeaderDivider(),
          _buildHeaderCell('Vital Signs', flex: 28),
          _buildHeaderDivider(),
          _buildHeaderCell('Symptoms', flex: 28),
          _buildHeaderDivider(),
          _buildHeaderCell('Date', flex: 18),
          if (!_isSelectionMode) ...[
            _buildHeaderDivider(),
            SizedBox(
              width: 150,
              child: Text(
                'Actions',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _mutedCoolGray.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _effectiveSearchController,
        onChanged: (value) {
          setState(() {
            _searchQuery = value.trim();
            _currentPage = 1;
            _selectedIndices.clear();
          });
          _scheduleSharedPatientSearch(value);
        },
        style: const TextStyle(color: Color(0xFF0B1F3A)),
        cursorColor: _primaryAqua,
        decoration: InputDecoration(
          hintText:
              'Search by name, Patient ID, barangay, symptoms, or vitals...',
          hintStyle: const TextStyle(color: Color(0xFF4B6075)),
          prefixIcon: const Icon(Icons.search, color: _primaryAqua),
          suffixIcon: _effectiveSearchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Color(0xFF4B6075)),
                  onPressed: () {
                    _effectiveSearchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _currentPage = 1;
                      _selectedIndices.clear();
                    });
                    _scheduleSharedPatientSearch('');
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD9E5F2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD9E5F2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _primaryAqua, width: 2),
          ),
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filters Row
        Row(
          children: [
            // Status Dropdown
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF3FA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _primaryAqua.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.filter_list,
                      color: _primaryAqua,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _statusFilter,
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          isDense: true,
                          iconSize: 18,
                          icon: const Icon(
                            Icons.arrow_drop_down,
                            color: _primaryAqua,
                            size: 18,
                          ),
                          style: const TextStyle(
                            color: _darkDeepTeal,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          items: const [
                            DropdownMenuItem(value: 'All', child: Text('All')),
                            DropdownMenuItem(
                              value: 'Pending',
                              child: Text('Pending'),
                            ),
                            DropdownMenuItem(
                              value: 'Completed',
                              child: Text('Completed'),
                            ),
                          ],
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _statusFilter = newValue;
                                _currentPage = 1;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Date Range
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _primaryAqua.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.date_range,
                      color: _primaryAqua,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildDatePickerButton(
                              context: context,
                              label: 'From',
                              date: _fromDate,
                              isFromDate: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildDatePickerButton(
                              context: context,
                              label: 'To',
                              date: _toDate,
                              isFromDate: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_fromDate != null || _toDate != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _fromDate = null;
                              _toDate = null;
                              _currentPage = 1;
                            });
                          },
                          child: const Icon(
                            Icons.clear,
                            size: 18,
                            color: Colors.red,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildCheckUpAdvancedFilters(),
      ],
    );
  }

  Widget _buildCheckUpAdvancedFilters() {
    final barangays = _records
        .map((r) => (r['address'] ?? r['barangay'] ?? '').toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return Semantics(
      label: 'Check-up filters and sorting',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _registryDropdown(
            label: 'Barangay',
            value: _selectedBarangay,
            options: ['All', ...barangays],
            onChanged: (value) => setState(() {
              _selectedBarangay = value;
              _currentPage = 1;
            }),
          ),
          _registryDropdown(
            label: 'Age Group',
            value: _selectedAgeGroup,
            options: const ['All', '0–5', '6–17', '18–59', '60+'],
            onChanged: (value) => setState(() {
              _selectedAgeGroup = value;
              _currentPage = 1;
            }),
          ),
          _registryDropdown(
            label: 'Sex',
            value: _selectedSex,
            options: const ['All', 'Male', 'Female'],
            onChanged: (value) => setState(() {
              _selectedSex = value;
              _currentPage = 1;
            }),
          ),
          _registryDropdown(
            label: 'Sort By',
            value: _sortField,
            options: const ['Name', 'Date', 'Age', 'Status'],
            onChanged: (value) => setState(() {
              _sortField = value;
              _currentPage = 1;
            }),
          ),
          Tooltip(
            message: _sortAscending ? 'Sort descending' : 'Sort ascending',
            child: IconButton.filledTonal(
              onPressed: () => setState(() => _sortAscending = !_sortAscending),
              icon: Icon(
                _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              ),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFEDF3FA),
                foregroundColor: const Color(0xFF2F80ED),
                padding: const EdgeInsets.all(10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(() {
              _statusFilter = 'All';
              _selectedBarangay = 'All';
              _selectedAgeGroup = 'All';
              _selectedSex = 'All';
              _fromDate = null;
              _toDate = null;
              _effectiveSearchController.clear();
              _searchQuery = '';
              _currentPage = 1;
            }),
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: const Text('Clear Filters'),
          ),
        ],
      ),
    );
  }

  Widget _registryDropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    final responsiveWidth = math.min(
      178.0,
      math.max(132.0, MediaQuery.sizeOf(context).width - 56),
    );
    return SizedBox(
      width: responsiveWidth,
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$value'),
        initialValue: options.contains(value) ? value : options.first,
        isExpanded: true,
        dropdownColor: AppColors.surfaceLight,
        iconEnabledColor: AppColors.textSecondary,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          floatingLabelStyle: const TextStyle(
            color: AppColors.primary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: AppColors.surfaceLight,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: AppColors.borderStrong),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: AppColors.borderStrong),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
        ),
        items: options
            .map(
              (option) => DropdownMenuItem(
                value: option,
                child: Text(
                  option,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
            .toList(growable: false),
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }

  Widget _buildDatePickerButton({
    required BuildContext context,
    required String label,
    required DateTime? date,
    required bool isFromDate,
  }) {
    return InkWell(
      onTap: () => _selectDateForCheckUp(context, isFromDate),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _primaryAqua.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              date != null ? '${date.day}/${date.month}' : label,
              style: const TextStyle(
                color: _darkDeepTeal,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Icon(Icons.calendar_today, color: _primaryAqua, size: 14),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDateForCheckUp(
    BuildContext context,
    bool isFromDate,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFromDate
          ? (_fromDate ?? DateTime.now())
          : (_toDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primaryAqua,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: _darkDeepTeal,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: _primaryAqua),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isFromDate) {
          _fromDate = picked;
          if (_toDate != null && _toDate!.isBefore(picked)) {
            _toDate = picked;
          }
        } else {
          _toDate = picked;
        }
        _currentPage = 1;
      });
    }
  }

  Widget _buildActionMenuButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _lightOffWhite.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                _isSelectionMode = !_isSelectionMode;
                if (!_isSelectionMode) {
                  _selectedIndices.clear();
                }
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isSelectionMode
                          ? [Color(0xFFFF5252), Color(0xFFE53935)]
                          : [Color(0xFF4CAF50), Color(0xFF388E3C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _isSelectionMode
                        ? Icons.close_rounded
                        : Icons.check_circle_outline_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isSelectionMode
                            ? 'Exit Selection Mode'
                            : 'Enter Selection Mode',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _isSelectionMode
                            ? 'Tap to deactivate bulk operations'
                            : 'Tap to enable bulk operations',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isSelectionMode && _selectedIndices.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Color(0xFFFF5252),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFFFF5252).withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '${_selectedIndices.length} selected',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: _mutedCoolGray,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionActionCard() {
    if (!_isSelectionMode || _selectedIndices.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _sidebarDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _primaryAqua.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Selection count header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _primaryAqua.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.check_circle,
                    color: _primaryAqua,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${_selectedIndices.length} record(s) selected',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        final allIndices = List.generate(
                          _filteredRecords.length,
                          (index) => index,
                        );
                        _selectedIndices.addAll(allIndices);
                      });
                    },
                    icon: Icon(Icons.select_all, size: 18),
                    label: Text('Select All'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryAqua.withValues(alpha: 0.2),
                      side: BorderSide(
                        color: _primaryAqua.withValues(alpha: 0.45),
                        width: 1.2,
                      ),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _confirmDelete,
                    icon: Icon(Icons.delete, size: 18),
                    label: Text('Delete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: 0.2),
                      side: BorderSide(
                        color: Colors.red.withValues(alpha: 0.45),
                        width: 1.2,
                      ),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isSelectionMode = false;
                        _selectedIndices.clear();
                      });
                    },
                    icon: Icon(Icons.close, size: 18),
                    label: Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.55),
                        width: 1.2,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete() {
    if (_selectedIndices.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No records selected'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() {
      _isDeleteDialogShowing = true;
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _sidebarDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            const SizedBox(width: 8),
            Text(
              'Confirm Delete',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${_selectedIndices.length} selected record(s)? This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _isDeleteDialogShowing = false;
              });
              Navigator.pop(context);
            },
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteSelectedRecords();
              setState(() {
                _isDeleteDialogShowing = false;
              });
            },
            child: Text(
              'Delete',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ).then((_) {
      // Ensure the state is reset if dialog is dismissed by tapping outside
      setState(() {
        _isDeleteDialogShowing = false;
      });
    });
  }

  void _deleteSelectedRecords() async {
    // Get IDs of records to delete
    final idsToDelete = _selectedIndices
        .map(
          (index) => index < _filteredRecords.length
              ? _filteredRecords[index]['id'] as String?
              : null,
        )
        .whereType<String>()
        .toList();

    try {
      // Delete from database, tracking any per-record failures
      final failedIds = await _dbHelper.deleteRecords(idsToDelete);

      // Reload records to reflect the actual database state
      await _loadRecords();

      final failedCount = failedIds.length;
      final succeededCount = idsToDelete.length - failedCount;

      if (mounted) {
        setState(() {
          if (failedIds.isEmpty) {
            _selectedIndices.clear();
            _isSelectionMode = false;
          } else {
            // Keep the still-undeleted records selected so the user can
            // retry without having to re-select everything.
            final retryIndices = _filteredRecords
                .asMap()
                .entries
                .where((entry) => failedIds.contains(entry.value['id']))
                .map((entry) => entry.key);
            _selectedIndices
              ..clear()
              ..addAll(retryIndices);
          }
        });
      }

      if (mounted) {
        if (failedIds.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Successfully deleted $succeededCount record(s)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                succeededCount > 0
                    ? 'Deleted $succeededCount of ${idsToDelete.length} records; $failedCount failed'
                    : 'Failed to delete $failedCount record(s)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      print('Error deleting records: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting records: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _CheckUpDashboardHeader extends StatefulWidget {
  final int totalCheckups;
  final int thisMonthCheckups;
  final int vitalRecordsCount;
  final List<Map<String, dynamic>> records;

  const _CheckUpDashboardHeader({
    required this.totalCheckups,
    required this.thisMonthCheckups,
    required this.vitalRecordsCount,
    required this.records,
  });

  @override
  State<_CheckUpDashboardHeader> createState() => _CheckUpDashboardHeaderState();
}

class _CheckUpDashboardHeaderState extends State<_CheckUpDashboardHeader> {
  DashboardDateFilterMode _dateFilterMode = DashboardDateFilterMode.allTime;
  DateTime? _customDate;
  DateTime? _selectedMonth;
  DateTime _rangeStart = DateTime.now().subtract(const Duration(days: 6));
  DateTime _rangeEnd = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedMonth ??= DateTime.now();
    _rangeStart = DateTime.now().subtract(const Duration(days: 6));
    _rangeEnd = DateTime.now();
  }

  DateTime? _recordDate(Map<String, dynamic> record) {
    final raw = record['datetime'] ??
        record['createdAt'] ??
        record['date'] ??
        record['consultationDate'] ??
        record['timestamp'];
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    try {
      final dynamic converted = (raw as dynamic).toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      // The web cache commonly stores Firestore dates as strings.
    }
    return DateTime.tryParse(raw.toString().trim());
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
        final targetMonth = _selectedMonth ?? now;
        return date.year == targetMonth.year && date.month == targetMonth.month;
      case DashboardDateFilterMode.last6Months:
        final start = DateTime(now.year, now.month - 5, 1);
        return !date.isBefore(start) && !date.isAfter(todayEnd);
      case DashboardDateFilterMode.customDay:
        final target = _customDate ?? now;
        final start = DateTime(target.year, target.month, target.day);
        final end = DateTime(target.year, target.month, target.day, 23, 59, 59);
        return !date.isBefore(start) && !date.isAfter(end);
      case DashboardDateFilterMode.customRange:
        final start = DateTime(
          _rangeStart.year,
          _rangeStart.month,
          _rangeStart.day,
        );
        final end = DateTime(
          _rangeEnd.year,
          _rangeEnd.month,
          _rangeEnd.day,
          23,
          59,
          59,
        );
        return !date.isBefore(start) && !date.isAfter(end);
      case DashboardDateFilterMode.allTime:
        return true;
    }
  }

  String _monthLabelShort(int month) {
    const labels = [
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
    if (month < 1 || month > 12) return '';
    return labels[month - 1];
  }

  String _monthLabelLong(int month) {
    const labels = [
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
    if (month < 1 || month > 12) return '';
    return labels[month - 1];
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
          final target = _selectedMonth ?? now;
          return '${_monthLabelLong(target.month)} ${target.year}';
        case DashboardDateFilterMode.last6Months:
          final start = DateTime(now.year, now.month - 5, 1);
          return 'Last 6 Months (${_monthLabelShort(start.month)} ${start.year} - ${_monthLabelShort(now.month)} ${now.year})';
        case DashboardDateFilterMode.customDay:
          final d = _customDate ?? now;
          return '${_monthLabelLong(d.month)} ${d.day}, ${d.year}';
        case DashboardDateFilterMode.customRange:
          final s = _rangeStart;
          final e = _rangeEnd;
          return '${_monthLabelShort(s.month)} ${s.day} - ${_monthLabelShort(e.month)} ${e.day}, ${e.year}';
        case DashboardDateFilterMode.allTime:
          return 'All Time History';
      }
    } catch (_) {}
    return 'All Time History';
  }

  Widget _buildFilterBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideHeader = constraints.maxWidth > 760;
        final filterBorderColor = Colors.black.withValues(alpha: 0.12);

        final headerCopy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Check-up Clinical Insights & Filter',
              style: TextStyle(
                color: _lightOffWhite,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Filter consultation volumes, category breakdowns, symptom trends, and patient age demographics by date. Currently showing ${_activeWindowLabel().toLowerCase()}.',
              maxLines: isWideHeader ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _mutedCoolGray,
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
              const Row(
                children: [
                  Icon(Icons.filter_alt_rounded, size: 13, color: _primaryAqua),
                  SizedBox(width: 5),
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
              const Text(
                'Insights & charts auto-synced',
                style: TextStyle(color: _mutedCoolGray, fontSize: 9.5),
              ),
            ],
          ),
        );

        final filterChips = <Widget>[
          _buildFilterChip(
            'All Time',
            Icons.all_inclusive_rounded,
            DashboardDateFilterMode.allTime,
          ),
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
              foregroundColor: (_dateFilterMode ==
                          DashboardDateFilterMode.customDay ||
                      _dateFilterMode == DashboardDateFilterMode.customRange)
                  ? _primaryAqua
                  : _lightOffWhite,
              backgroundColor: (_dateFilterMode ==
                          DashboardDateFilterMode.customDay ||
                      _dateFilterMode == DashboardDateFilterMode.customRange)
                  ? _primaryAqua.withValues(alpha: 0.12)
                  : Colors.white,
              side: BorderSide(
                color: (_dateFilterMode == DashboardDateFilterMode.customDay ||
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
                color: Colors.black.withValues(alpha: 0.03),
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
            _selectedMonth = DateTime.now();
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _primaryAqua : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? _primaryAqua
                : Colors.black.withValues(alpha: 0.12),
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
                'Filter Check-up Insights',
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
                subtitle: const Text('Filter records for a specific day'),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _customDate ?? now,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _dateFilterMode = DashboardDateFilterMode.customDay;
                    _customDate = picked;
                  });
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
                  'Pick target month (Current: ${_monthLabelLong((_selectedMonth ?? DateTime.now()).month)})',
                ),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  final target = _selectedMonth ?? DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: target,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                    initialDatePickerMode: DatePickerMode.year,
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _dateFilterMode = DashboardDateFilterMode.thisMonth;
                    _selectedMonth = DateTime(picked.year, picked.month);
                  });
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
                      start: _rangeStart,
                      end: _rangeEnd,
                    ),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _dateFilterMode = DashboardDateFilterMode.customRange;
                    _rangeStart = picked.start;
                    _rangeEnd = picked.end;
                  });
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(
                  Icons.all_inclusive_rounded,
                  color: _primaryAqua,
                ),
                title: const Text(
                  'Quick: All Time Records',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(dialogContext);
                  setState(() {
                    _dateFilterMode = DashboardDateFilterMode.allTime;
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.records
        .where((r) => _matchesDateFilter(_recordDate(r)))
        .toList(growable: false);
    final totalCheckups = filtered.length;
    final now = DateTime.now();
    final thisMonthCheckups = filtered.where((r) {
      final d = _recordDate(r);
      return d != null && d.year == now.year && d.month == now.month;
    }).length;
    final vitalRecordsCount = filtered.where((record) {
      final details = record['details']?.toString() ?? '';
      return details.contains('BP:') ||
          details.contains('Temp:') ||
          details.contains('HR:');
    }).length;

    final monthlyTrend = _buildMonthlyTrend(filtered);
    final categoryDistribution = _buildCategoryDistribution(filtered);
    final symptomDistribution = _buildSymptomDistribution(filtered);
    final ageDistribution = _buildAgeDistribution(filtered);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFilterBar(),
        const SizedBox(height: 20),
        // Metrics stay in one row on wide screens and become a compact,
        // evenly spaced grid on tablets and phones.
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100
                ? 4
                : constraints.maxWidth >= 680
                ? 2
                : 1;
            const spacing = 16.0;
            final cardWidth = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - spacing * (columns - 1)) / columns;
            final cards = <Widget>[
              _buildTotalCheckupsCard(totalCheckups),
              _buildThisMonthCard(thisMonthCheckups),
              _buildWithVitalsCard(vitalRecordsCount),
              _buildStatusCard(vitalRecordsCount, totalCheckups),
            ];
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: cards
                  .map((card) => SizedBox(width: cardWidth, child: card))
                  .toList(growable: false),
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final stackCharts = constraints.maxWidth < 980;
            final trendChart = _buildChartPanel(
              title: 'Monthly Check-up Trend',
              subtitle: 'Consultations recorded during the last six months',
              icon: Icons.show_chart_rounded,
              child: _buildMonthlyTrendChart(monthlyTrend),
            );
            final categoryChart = _buildChartPanel(
              title: 'Check-ups by Category',
              subtitle: 'Distribution based on saved check-up classifications',
              icon: Icons.bar_chart_rounded,
              child: _buildDistributionBarChart(
                categoryDistribution,
                emptyMessage:
                    'Category data will appear after the first check-up is saved.',
                tooltipUnit: 'record',
              ),
            );
            final symptomsChart = _buildChartPanel(
              title: 'Symptoms Trends',
              subtitle: 'Most frequently reported symptoms in check-up records',
              icon: Icons.sick_outlined,
              child: _buildDistributionBarChart(
                symptomDistribution,
                emptyMessage:
                    'Reported symptoms will appear after symptom data is saved.',
                tooltipUnit: 'report',
                colors: const [_primaryAqua, _secondaryIceBlue],
              ),
            );
            final ageChart = _buildChartPanel(
              title: 'Patient Age Range',
              subtitle: 'Check-up records grouped by patient age',
              icon: Icons.groups_2_outlined,
              child: _buildDistributionBarChart(
                ageDistribution,
                emptyMessage:
                    'Age-range data will appear after patient ages are saved.',
                tooltipUnit: 'patient',
                colors: const [_secondaryIceBlue, Color(0xFF8FAFD6)],
              ),
            );

            if (stackCharts) {
              return Column(
                children: [
                  trendChart,
                  const SizedBox(height: 16),
                  categoryChart,
                  const SizedBox(height: 16),
                  symptomsChart,
                  const SizedBox(height: 16),
                  ageChart,
                ],
              );
            }
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: trendChart),
                    const SizedBox(width: 20),
                    Expanded(child: categoryChart),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: symptomsChart),
                    const SizedBox(width: 20),
                    Expanded(child: ageChart),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  List<MapEntry<String, int>> _buildMonthlyTrend(
    List<Map<String, dynamic>> records,
  ) {
    final now = DateTime.now();
    final months = List<DateTime>.generate(6, (index) {
      final offset = 5 - index;
      return DateTime(now.year, now.month - offset);
    });
    const monthNames = <String>[
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

    return months
        .map((month) {
          final count = records.where((record) {
            final date = _recordDate(record);
            return date != null &&
                date.year == month.year &&
                date.month == month.month;
          }).length;
          return MapEntry(
            '${monthNames[month.month - 1]} ${month.year % 100}',
            count,
          );
        })
        .toList(growable: false);
  }

  List<MapEntry<String, int>> _buildCategoryDistribution(
    List<Map<String, dynamic>> records,
  ) {
    final counts = <String, int>{};
    for (final record in records) {
      final candidates = <dynamic>[
        record['healthCategory'],
        record['ai_suggested_health_category'],
        record['diseaseType'],
        record['ai_category'],
        record['type'],
      ];
      var category = '';
      for (final candidate in candidates) {
        final value = candidate?.toString().trim() ?? '';
        if (value.isNotEmpty && value.toLowerCase() != 'null') {
          category = value;
          break;
        }
      }
      category = category.isEmpty ? 'General' : category;
      counts[category] = (counts[category] ?? 0) + 1;
    }

    final entries = counts.entries.toList()
      ..sort((a, b) {
        final countOrder = b.value.compareTo(a.value);
        return countOrder != 0 ? countOrder : a.key.compareTo(b.key);
      });
    return entries.take(6).toList(growable: false);
  }

  List<MapEntry<String, int>> _buildSymptomDistribution(
    List<Map<String, dynamic>> records,
  ) {
    final counts = <String, int>{};
    final separators = RegExp(r'[,;|\n]+|\s+and\s+', caseSensitive: false);
    const ignoredValues = <String>{
      'none',
      'n/a',
      'na',
      'no symptoms',
      'not available',
    };

    for (final record in records) {
      final detectedKeywords = record['ai_keywords'];
      final rawSymptoms = detectedKeywords?.toString().trim().isNotEmpty == true
          ? detectedKeywords
          : record['symptoms'];
      final values = rawSymptoms is Iterable
          ? rawSymptoms.map((value) => value.toString())
          : (rawSymptoms?.toString() ?? '').split(separators);
      final symptomsForRecord = <String>{};
      for (final value in values) {
        final normalized = value.trim().toLowerCase().replaceAll(
          RegExp(r'^[^a-z0-9]+|[^a-z0-9]+$'),
          '',
        );
        if (normalized.isEmpty || ignoredValues.contains(normalized)) continue;
        symptomsForRecord.add(_titleCase(normalized));
      }
      for (final symptom in symptomsForRecord) {
        counts[symptom] = (counts[symptom] ?? 0) + 1;
      }
    }

    final entries = counts.entries.toList()
      ..sort((a, b) {
        final countOrder = b.value.compareTo(a.value);
        return countOrder != 0 ? countOrder : a.key.compareTo(b.key);
      });
    return entries.take(6).toList(growable: false);
  }

  List<MapEntry<String, int>> _buildAgeDistribution(
    List<Map<String, dynamic>> records,
  ) {
    final counts = <String, int>{
      '0–5': 0,
      '6–12': 0,
      '13–17': 0,
      '18–35': 0,
      '36–59': 0,
      '60+': 0,
    };
    for (final record in records) {
      final match = RegExp(r'\d+').firstMatch(record['age']?.toString() ?? '');
      final age = match == null ? null : int.tryParse(match.group(0)!);
      if (age == null || age < 0 || age > 130) continue;
      final range = age <= 5
          ? '0–5'
          : age <= 12
          ? '6–12'
          : age <= 17
          ? '13–17'
          : age <= 35
          ? '18–35'
          : age <= 59
          ? '36–59'
          : '60+';
      counts[range] = counts[range]! + 1;
    }
    if (counts.values.every((count) => count == 0)) {
      return const <MapEntry<String, int>>[];
    }
    return counts.entries.toList(growable: false);
  }

  String _titleCase(String value) {
    return value
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Widget _buildChartPanel({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      height: 360,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _primaryAqua, size: 21),
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
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(color: _mutedCoolGray, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: child),
        ],
      ),
    );
  }

  double _chartMax(Iterable<int> values) {
    final largest = values.fold<int>(0, math.max);
    return math
        .max(4, largest + math.max(1, (largest * 0.25).ceil()))
        .toDouble();
  }

  Widget _buildMonthlyTrendChart(List<MapEntry<String, int>> trend) {
    final maxY = _chartMax(trend.map((entry) => entry.value));
    final interval = math.max(1, (maxY / 4).ceil()).toDouble();
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (trend.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: const Color(0xFFD9E5F2), strokeWidth: 1),
        ),
        titlesData: _chartTitles(
          labels: trend.map((entry) => entry.key).toList(growable: false),
          interval: interval,
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF163B66),
            getTooltipItems: (spots) => spots
                .map(
                  (spot) => LineTooltipItem(
                    '${trend[spot.x.toInt()].key}\n${spot.y.toInt()} check-up${spot.y == 1 ? '' : 's'}',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            color: _primaryAqua,
            barWidth: 3,
            spots: List<FlSpot>.generate(
              trend.length,
              (index) =>
                  FlSpot(index.toDouble(), trend[index].value.toDouble()),
            ),
            dotData: FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: _primaryAqua.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionBarChart(
    List<MapEntry<String, int>> entries, {
    required String emptyMessage,
    required String tooltipUnit,
    List<Color> colors = const [_primaryAqua, _secondaryIceBlue],
  }) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _mutedCoolGray, fontSize: 13),
        ),
      );
    }
    final maxY = _chartMax(entries.map((entry) => entry.value));
    final interval = math.max(1, (maxY / 4).ceil()).toDouble();
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: const Color(0xFFD9E5F2), strokeWidth: 1),
        ),
        titlesData: _chartTitles(
          labels: entries.map((entry) => _shortLabel(entry.key)).toList(),
          interval: interval,
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF163B66),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final item = entries[group.x];
              return BarTooltipItem(
                '${item.key}\n${item.value} $tooltipUnit${item.value == 1 ? '' : 's'}',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
        ),
        barGroups: List<BarChartGroupData>.generate(entries.length, (index) {
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: entries[index].value.toDouble(),
                width: 24,
                color: colors[index % colors.length],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  FlTitlesData _chartTitles({
    required List<String> labels,
    required double interval,
  }) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32,
          interval: interval,
          getTitlesWidget: (value, _) => Text(
            value.toInt().toString(),
            style: const TextStyle(color: _mutedCoolGray, fontSize: 10),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 34,
          getTitlesWidget: (value, _) {
            final index = value.toInt();
            if (value != index || index < 0 || index >= labels.length) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                labels[index],
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _mutedCoolGray, fontSize: 10),
              ),
            );
          },
        ),
      ),
    );
  }

  String _shortLabel(String value) {
    final cleaned = value.trim();
    if (cleaned.length <= 11) return cleaned;
    return '${cleaned.substring(0, 9)}…';
  }

  Widget _buildWebMetricCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return AppMetricCard(label: title, value: value, icon: icon);
  }

  /// Builds the Total Check-ups metric card
  Widget _buildTotalCheckupsCard(int totalCheckups) {
    return _buildWebMetricCard(
      title: 'Total Check-ups',
      value: '$totalCheckups',
      icon: Icons.assignment_outlined,
    );
  }

  /// Builds the This Month metric card
  Widget _buildThisMonthCard(int thisMonthCheckups) {
    return _buildWebMetricCard(
      title: 'This Month',
      value: '$thisMonthCheckups',
      icon: Icons.calendar_month_outlined,
    );
  }

  /// Builds the With Vitals metric card
  Widget _buildWithVitalsCard(int vitalRecordsCount) {
    return _buildWebMetricCard(
      title: 'With Vitals',
      value: '$vitalRecordsCount',
      icon: Icons.monitor_heart_outlined,
    );
  }

  /// Builds the Status metric card showing completion percentage
  Widget _buildStatusCard(int vitalRecordsCount, int totalCheckups) {
    final percentage =
        ((vitalRecordsCount / (totalCheckups > 0 ? totalCheckups : 1)) * 100)
            .toStringAsFixed(0);
    return _buildWebMetricCard(
      title: 'Status',
      value: '$percentage%',
      icon: Icons.trending_up_outlined,
    );
  }
}

// CheckUp Table Widget
class _CheckUpTable extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final int startIndex;
  final bool isSelectionMode;
  final Set<int> selectedIndices;
  final Function(int, bool) onSelectionChanged;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>) onViewHistory;
  final Function(Map<String, dynamic>) onRefer;

  const _CheckUpTable({
    required this.records,
    required this.startIndex,
    required this.isSelectionMode,
    required this.selectedIndices,
    required this.onSelectionChanged,
    required this.onEdit,
    required this.onViewHistory,
    required this.onRefer,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Center(
        child: Text(
          'No records found.',
          style: TextStyle(color: _lightOffWhite, fontSize: 16),
        ),
      );
    }

    return Column(
      children: List.generate(records.length, (index) {
        final absoluteIndex = startIndex + index;
        final isSelected = selectedIndices.contains(absoluteIndex);
        return _CheckUpCard(
          record: records[index],
          isSelectionMode: isSelectionMode,
          isSelected: isSelected,
          index: absoluteIndex,
          onSelectionChanged: onSelectionChanged,
          onEdit: onEdit,
          onViewHistory: onViewHistory,
          onRefer: onRefer,
        );
      }),
    );
  }
}

// Helper function to show checkup details
void _showCheckUpDetails(BuildContext context, Map<String, dynamic> record) {
  final patientName = _safeCheckUpText(
    record['patient'],
    fallback: 'Unknown Patient',
  );
  final nameParts = patientName.split(' ');
  final firstName = nameParts.isNotEmpty ? nameParts[0] : '';
  final surname = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
  final age = _safeCheckUpText(record['age']);
  final address = _safeCheckUpText(record['address']);
  final dateTime = _formatCheckUpDateTime(record['datetime']);
  final status = _safeCheckUpText(record['status'], fallback: 'Completed');
  final followUp = _safeCheckUpText(
    record['followup'],
    fallback: 'No follow-up scheduled',
  );
  final vitalSigns = _safeCheckUpText(
    record['vitalsigns'],
    fallback: 'No vital signs recorded',
  );
  final symptoms = _safeCheckUpText(
    record['symptoms'],
    fallback: 'No symptoms recorded',
  );
  showFullscreenDetailTableDialog(
    context: context,
    title: 'Check-Up Details',
    subject: patientName,
    items: [
      DetailTableItem(
        icon: Icons.person_outline_rounded,
        label: 'Patient Name',
        value: patientName,
      ),
      DetailTableItem(
        icon: Icons.badge_outlined,
        label: 'First Name',
        value: firstName,
      ),
      DetailTableItem(
        icon: Icons.badge_rounded,
        label: 'Surname',
        value: surname,
      ),
      DetailTableItem(icon: Icons.cake_outlined, label: 'Age', value: age),
      DetailTableItem(
        icon: Icons.location_on_outlined,
        label: 'Address',
        value: address,
      ),
      DetailTableItem(
        icon: Icons.event_note_outlined,
        label: 'Date & Time',
        value: dateTime,
      ),
      DetailTableItem(
        icon: Icons.verified_outlined,
        label: 'Status',
        value: status,
      ),
      DetailTableItem(
        icon: Icons.update_outlined,
        label: 'Follow-up Date',
        value: followUp,
      ),
      DetailTableItem(
        icon: Icons.favorite_outline_rounded,
        label: 'Vital Signs',
        value: vitalSigns,
        labelColor: const Color(0xFF60A5FA),
      ),
      DetailTableItem(
        icon: Icons.sick_outlined,
        label: 'Symptoms',
        value: symptoms,
      ),
      DetailTableItem(
        icon: Icons.smart_toy_outlined,
        label: 'Health Category',
        value: _safeCheckUpText(
          record['healthCategory'] ??
              record['ai_suggested_health_category'] ??
              record['diseaseType'],
          fallback: 'Needs Clinical Review',
        ),
      ),
      DetailTableItem(
        icon: Icons.analytics_outlined,
        label: 'AI Severity',
        value: _safeCheckUpText(record['ai_severity'], fallback: ''),
      ),
      DetailTableItem(
        icon: Icons.insights_outlined,
        label: 'AI Confidence',
        value: _safeCheckUpText(record['ai_confidence'], fallback: ''),
      ),
    ],
  );
}

Future<void> _generateCheckupPdf(
  BuildContext context,
  Map<String, dynamic> record,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) =>
        const Center(child: CircularProgressIndicator(color: _primaryAqua)),
  );

  // Let the loading dialog paint before running synchronous PDF work.
  await Future<void>.delayed(const Duration(milliseconds: 16));

  try {
    final pdfBytes = await buildCheckupPdfBytes(record);
    final filename = buildCheckupPdfFilename(record);
    final downloaded = downloadFile(
      bytes: pdfBytes,
      filename: filename,
      mimeType: 'application/pdf',
    );

    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          downloaded
              ? 'PDF generated for ${record['patient'] ?? 'this record'}.'
              : 'PDF generation is not supported on this platform.',
        ),
        backgroundColor: downloaded ? _primaryAqua : Colors.orange,
        duration: const Duration(seconds: 2),
      ),
    );
  } catch (e) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Failed to generate PDF: $e'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}

String _safeCheckUpText(dynamic value, {String fallback = 'Not recorded'}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String _formatCheckUpDateTime(dynamic value) {
  final parsed = _parseCheckUpDateTime(value);
  if (parsed == null) {
    return 'Date and time not recorded';
  }
  return DateFormat('MMMM d, yyyy • h:mm a').format(parsed.toLocal());
}

String _formatCheckUpDate(dynamic value, {String fallback = 'Not recorded'}) {
  final parsed = _parseCheckUpDateTime(value);
  if (parsed == null) return fallback;
  return DateFormat('MMMM d, yyyy').format(parsed.toLocal());
}

Map<String, dynamic> _localHealthCategoryFallback(String input) {
  final normalized = input
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  final searchable = ' $normalized ';
  const communicableKeywords = <String>[
    'influenza',
    'common cold',
    'covid 19',
    'tuberculosis',
    'dengue fever',
    'dengue',
    'malaria',
    'measles',
    'chickenpox',
    'cholera',
    'typhoid fever',
    'pertussis',
    'diphtheria',
    'hepatitis a',
    'hepatitis b',
    'hepatitis c',
    'hiv infection',
    'hand foot and mouth disease',
    'fever',
    'cough',
    'sore throat',
    'runny nose',
    'nasal congestion',
    'chills',
    'diarrhea',
    'skin rash',
    'loss of smell',
    'loss of taste',
  ];
  const nonCommunicableKeywords = <String>[
    'hypertension',
    'high blood pressure',
    'elevated blood pressure',
    'type 1 diabetes',
    'type 2 diabetes',
    'diabetes mellitus',
    'asthma',
    'chronic obstructive pulmonary disease',
    'coronary artery disease',
    'heart failure',
    'stroke',
    'chronic kidney disease',
    'arthritis',
    'osteoarthritis',
    'migraine',
    'anxiety',
    'depression',
    'spinal stenosis',
    'chronic joint pain',
    'chronic back pain',
    'frequent urination',
    'excessive thirst',
    'persistent migraine',
  ];

  final communicableMatches = communicableKeywords
      .where((keyword) => searchable.contains(' $keyword '))
      .toList();
  final nonCommunicableMatches = nonCommunicableKeywords
      .where((keyword) => searchable.contains(' $keyword '))
      .toList();
  final category =
      communicableMatches.isNotEmpty && nonCommunicableMatches.isNotEmpty
      ? 'Mixed'
      : communicableMatches.isNotEmpty
      ? 'Communicable'
      : nonCommunicableMatches.isNotEmpty
      ? 'Non-Communicable'
      : 'Needs Clinical Review';
  final matches = <String>[...communicableMatches, ...nonCommunicableMatches];

  return <String, dynamic>{
    'healthCategory': category,
    'healthCategoryBasis': matches.isEmpty
        ? 'unrecognized_local_keyword'
        : 'local_keyword_fallback',
    'healthCategoryRequiresReview': true,
    'healthCategoryRuleVersion': 'condition-category-rules-v2-local',
    'healthCategoryKeywords': matches,
    'ai_suggested_health_category': category,
    'ai_category_requires_review': true,
    'ai_category_matched_symptoms': matches,
    'diseaseType': category,
  };
}

DateTime? _parseCheckUpDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;

  // Firestore Timestamp exposes toDate() on mobile and web.
  try {
    final dynamic converted = value.toDate();
    if (converted is DateTime) return converted;
  } catch (_) {
    // Continue with serialized timestamp and ISO-date fallbacks.
  }

  if (value is num) {
    final integer = value.toInt();
    return integer.abs() > 100000000000
        ? DateTime.fromMillisecondsSinceEpoch(integer)
        : DateTime.fromMillisecondsSinceEpoch(integer * 1000);
  }

  if (value is Map) {
    final seconds = value['seconds'] ?? value['_seconds'];
    final nanoseconds = value['nanoseconds'] ?? value['_nanoseconds'] ?? 0;
    if (seconds is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        (seconds * 1000).round() +
            (nanoseconds is num ? (nanoseconds / 1000000).round() : 0),
      );
    }
  }

  final text = value.toString().trim();
  if (text.isEmpty) return null;
  final isoDate = DateTime.tryParse(text);
  if (isoDate != null) return isoDate;

  final firestoreTimestamp = RegExp(
    r'seconds\s*[=:]\s*(-?\d+)(?:.*nanoseconds\s*[=:]\s*(\d+))?',
    caseSensitive: false,
  ).firstMatch(text);
  if (firestoreTimestamp == null) return null;

  final seconds = int.tryParse(firestoreTimestamp.group(1) ?? '');
  final nanoseconds = int.tryParse(firestoreTimestamp.group(2) ?? '') ?? 0;
  if (seconds == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(
    (seconds * 1000) + (nanoseconds ~/ 1000000),
  );
}

Color _getCheckUpStatusColor(String status) {
  final lower = status.toLowerCase();

  if (lower.contains('complete') || lower.contains('done')) {
    return const Color(0xFF66BB6A);
  }
  if (lower.contains('progress') || lower.contains('ongoing')) {
    return const Color(0xFFFFB74D);
  }
  if (lower.contains('follow') || lower.contains('review')) {
    return const Color(0xFF64B5F6);
  }
  if (lower.contains('pending') || lower.contains('scheduled')) {
    return const Color(0xFF4DD0E1);
  }
  return _primaryAqua;
}

Widget _buildCheckUpMetaChip({
  required IconData icon,
  required String label,
  required String value,
  required Color accentColor,
  Color? valueColor,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: accentColor.withValues(alpha: 0.18)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: accentColor, size: 18),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: valueColor ?? Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _buildDetailSection({
  required String title,
  required String subtitle,
  required IconData icon,
  required Color accentColor,
  required List<Widget> children,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _sidebarDark.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _primaryAqua.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: _primaryAqua, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    ],
  );
}

Widget _buildDetailRow({
  required String label,
  required dynamic value,
  required IconData icon,
  required Color accentColor,
  Color? valueColor,
  Widget? content,
}) {
  final valueString = _safeCheckUpText(value);

  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _primaryAqua.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _primaryAqua, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                content ??
                    Text(
                      valueString,
                      style: TextStyle(
                        color: valueColor ?? Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildHighlightedVitalSignsWeb(String vitalsString) {
  const rowText = Color(0xFF0B1F3A);
  const labelColor = Color(0xFF2F80ED);

  if (vitalsString.isEmpty || vitalsString == 'N/A') {
    return Text(
      vitalsString.isEmpty ? 'No vitals recorded' : vitalsString,
      style: const TextStyle(
        color: Color(0xFF546E7A),
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  final parts = vitalsString.split(', ');
  final textSpans = <TextSpan>[];

  for (int i = 0; i < parts.length; i++) {
    final part = parts[i].trim();
    if (part.isEmpty) continue;

    // Extract label and value
    final colonIndex = part.indexOf(':');
    if (colonIndex != -1) {
      final vitalLabel = part.substring(
        0,
        colonIndex + 1,
      ); // includes the colon
      final vitalValue = part.substring(colonIndex + 1).trim();

      // Add highlighted label
      textSpans.add(
        TextSpan(
          text: vitalLabel,
          style: const TextStyle(
            fontSize: 11,
            color: labelColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

      // Add space and value
      textSpans.add(
        TextSpan(
          text: ' $vitalValue',
          style: const TextStyle(
            fontSize: 11,
            color: rowText,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

      // Add separator if not last item
      if (i < parts.length - 1) {
        textSpans.add(
          const TextSpan(
            text: '   ',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFFB0BEC5),
            ),
          ),
        );
      }
    } else {
      textSpans.add(
        TextSpan(
          text: part,
          style: const TextStyle(
            fontSize: 11,
            color: rowText,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
  }

  return RichText(
    text: TextSpan(children: textSpans),
    maxLines: 4,
    overflow: TextOverflow.ellipsis,
  );
}

Widget _buildInfoRow({
  required IconData icon,
  required String label,
  required String value,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.7)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      const SizedBox(width: 6),
      Text(
        value,
        style: TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );
}

class _CheckUpCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final bool isSelectionMode;
  final bool isSelected;
  final int index;
  final Function(int, bool) onSelectionChanged;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>) onViewHistory;
  final Function(Map<String, dynamic>) onRefer;

  const _CheckUpCard({
    required this.record,
    required this.isSelectionMode,
    required this.isSelected,
    required this.index,
    required this.onSelectionChanged,
    required this.onEdit,
    required this.onViewHistory,
    required this.onRefer,
  });

  String _safe(dynamic value, [String fallback = 'N/A']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    final normalized = text.toLowerCase();
    if (text.isEmpty || normalized == 'undefined' || normalized == 'null') {
      return fallback;
    }
    return text;
  }

  Widget _buildDivider() {
    return Container(width: 1, height: 70, color: const Color(0xFFD9E5F2));
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    Color accent = const Color(0xFF163B66),
  }) {
    final button = Container(
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.28),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, color: Colors.white, size: 15),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }

  @override
  Widget build(BuildContext context) {
    final patientName = _safe(
      record['patient'] ?? record['patientName'] ?? record['name'],
      'Unknown Patient',
    );
    final age = _safe(record['age'], 'N/A');
    final recordId = _safe(
      record['patientId'] ?? record['linkedPatientId'] ?? record['id'],
      '-',
    );
    final dateTime = _safe(
      record['datetime'] ??
          record['date'] ??
          record['consultationDate'] ??
          record['createdAt'] ??
          record['timestamp'],
      'N/A',
    );
    final dateLabel = dateTime.contains('T')
        ? dateTime.split('T').first
        : dateTime.split(' ').first;
    final symptoms = _safe(
      record['symptoms'] ??
          record['chief_complaint'] ??
          record['chiefComplaint'] ??
          record['diagnosis'] ??
          record['clinicalObservations'],
      'No symptoms recorded',
    );
    final vitals = _safe(
      record['vitalsigns'] ??
          record['vitalSigns'] ??
          record['vitals'] ??
          record['vital_signs'],
      'No vitals recorded',
    );
    final abnormalVitalFlags = detectAbnormalVitalFlags(vitals);

    const rowBg = Colors.white;
    const rowText = Color(0xFF0B1F3A);
    const mutedText = Color(0xFF546E7A);

    return GestureDetector(
      onTap: isSelectionMode
          ? () => onSelectionChanged(index, !isSelected)
          : () => onViewHistory(record),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: rowBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? _primaryAqua.withValues(alpha: 0.85)
                : const Color(0xFFD9E5F2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (value) =>
                        onSelectionChanged(index, value ?? false),
                    activeColor: _primaryAqua,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: BorderSide(
                      color: const Color(0xFFB1C4D5).withValues(alpha: 0.8),
                      width: 1.2,
                    ),
                  ),
                ),
              Expanded(
                flex: 26,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patientName,
                      style: const TextStyle(
                        color: rowText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (abnormalVitalFlags.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Tooltip(
                        message: abnormalVitalFlags.join(', '),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.referralTint,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppColors.referral.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 12,
                                color: AppColors.referral,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Suggested Referral',
                                style: TextStyle(
                                  color: AppColors.referralStrong,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    RichText(
                      text: TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Age: ',
                            style: TextStyle(
                              color: mutedText,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextSpan(
                            text: '$age years',
                            style: const TextStyle(
                              color: rowText,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (recordId != '-') ...[
                      const SizedBox(height: 3),
                      Text(
                        'ID: $recordId',
                        style: const TextStyle(
                          color: _primaryAqua,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              _buildDivider(),
              Expanded(
                flex: 28,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [_buildHighlightedVitalSignsWeb(vitals)],
                ),
              ),
              _buildDivider(),
              Expanded(
                flex: 28,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      symptoms,
                      style: const TextStyle(
                        color: rowText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _buildDivider(),
              Expanded(
                flex: 18,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        color: rowText,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!isSelectionMode) ...[
                _buildDivider(),
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 2),
                  child: SizedBox(
                    width: 150,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildActionButton(
                          icon: Icons.history_rounded,
                          tooltip: 'View history',
                          onTap: () => onViewHistory(record),
                        ),
                        const SizedBox(width: 6),
                        _buildActionButton(
                          icon: Icons.edit_rounded,
                          tooltip: 'Edit record',
                          onTap: () => onEdit(record),
                        ),
                        const SizedBox(width: 6),
                        _buildActionButton(
                          icon: Icons.local_hospital_outlined,
                          tooltip: 'Refer to CHO',
                          accent: AppColors.referral,
                          onTap: () => onRefer(record),
                        ),
                        const SizedBox(width: 6),
                        _buildActionButton(
                          icon: Icons.picture_as_pdf_rounded,
                          tooltip: 'Download PDF',
                          onTap: () => _generateCheckupPdf(context, record),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog result for "Save & Refer to CHO": tells the page that opened this
/// modal to save succeeded and it should now open the referral overlay for
/// [record], instead of the modal reaching for a context that's mid-pop.
class _ReferralHandoff {
  const _ReferralHandoff(this.record);
  final Map<String, dynamic> record;
}

class _NewCheckUpFullScreenModal extends StatefulWidget {
  final Future<String> Function(Map<String, dynamic>) onSave;
  final SymptomGuidanceApiService guidanceApi;
  final Map<String, dynamic>? patientSeed;

  const _NewCheckUpFullScreenModal({
    required this.onSave,
    required this.guidanceApi,
    this.patientSeed,
  });

  @override
  State<_NewCheckUpFullScreenModal> createState() =>
      _NewCheckUpFullScreenModalState();
}

class _NewCheckUpFullScreenModalState
    extends State<_NewCheckUpFullScreenModal> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  // Separate vital sign controllers
  final TextEditingController _bloodPressureController =
      TextEditingController();
  final TextEditingController _temperatureController = TextEditingController();
  final TextEditingController _heartRateController = TextEditingController();
  final TextEditingController _respiratoryRateController =
      TextEditingController();
  final TextEditingController _oxygenSaturationController =
      TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();

  final TextEditingController _symptomsController = TextEditingController();
  DateTime? _followUpDate;
  final String _recordType = 'General';
  final String _diseaseType = 'General';
  bool _isSaving = false;
  static const Color _panelSurface = Color(0xFF163B66);
  static const Color _fieldSurface = Color(0xFF0B1F3A);

  @override
  void initState() {
    super.initState();
    final patientSeed = widget.patientSeed;
    if (patientSeed == null) {
      return;
    }

    final name = patientNameParts(patientSeed);
    _firstNameController.text = name.firstName;
    _surnameController.text = name.surname;
    _ageController.text = (patientSeed['age'] ?? '').toString();
    _addressController.text = (patientSeed['address'] ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isFollowUpVisit = widget.patientSeed != null;
    final modalTitle = isFollowUpVisit
        ? 'Add Another Check-Up'
        : 'New Check-Up Record';
    final modalSubtitle = isFollowUpVisit
        ? 'Continue care for the same patient while keeping previous check-up history visible.'
        : 'Patient assessment intake and clinical follow-up planning';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Container(
        width: screenSize.width,
        height: screenSize.height,
        color: const Color(0xFFF5F7FA),
        child: Column(
          children: [
            // Header Bar
            Container(
              height: 76,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: const BoxDecoration(
                color: _darkDeepTeal,
                border: Border(
                  bottom: BorderSide(
                    color: Color(0x20FFFFFF),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          modalTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          modalSubtitle,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close modal',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            // Form Content Area
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Form(
                  key: _formKey,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 900;

                      final patientInfoCard = _buildSectionCard(
                        context: context,
                        title: 'Patient Information',
                        icon: Icons.person_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.patientSeed != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: _primaryAqua.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _primaryAqua.withValues(
                                      alpha: 0.25,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.verified_user_rounded,
                                      color: _primaryAqua,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Linked to registered patient record (${_firstNameController.text} ${_surnameController.text})',
                                        style: const TextStyle(
                                          color: _lightOffWhite,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _firstNameController,
                                    decoration: _buildInputDecoration(
                                      'First Name',
                                      hintText: 'Enter given name',
                                      prefixIcon: const Icon(
                                        Icons.badge_outlined,
                                        size: 18,
                                        color: _primaryAqua,
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: _lightOffWhite,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    validator: (v) => v == null || v.isEmpty
                                        ? 'First name is required'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: TextFormField(
                                    controller: _surnameController,
                                    decoration: _buildInputDecoration(
                                      'Surname',
                                      hintText: 'Enter family name',
                                      prefixIcon: const Icon(
                                        Icons.badge_outlined,
                                        size: 18,
                                        color: _primaryAqua,
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: _lightOffWhite,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    validator: (v) => v == null || v.isEmpty
                                        ? 'Surname is required'
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                SizedBox(
                                  width: 130,
                                  child: TextFormField(
                                    controller: _ageController,
                                    decoration: _buildInputDecoration(
                                      'Age',
                                      hintText: '25',
                                      prefixIcon: const Icon(
                                        Icons.cake_outlined,
                                        size: 18,
                                        color: _primaryAqua,
                                      ),
                                      suffix: const Text(
                                        'yrs',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _mutedCoolGray,
                                        ),
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: _lightOffWhite,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: (v) =>
                                        v == null || v.isEmpty
                                            ? 'Age required'
                                            : null,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: TextFormField(
                                    controller: _addressController,
                                    decoration: _buildInputDecoration(
                                      'Residential Address',
                                      hintText:
                                          'Purok, Barangay, City/Municipality',
                                      prefixIcon: const Icon(
                                        Icons.home_outlined,
                                        size: 18,
                                        color: _primaryAqua,
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: _lightOffWhite,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );

                      final vitalSignsCard = _buildSectionCard(
                        context: context,
                        title: 'Vital Signs & Physical Measurements',
                        icon: Icons.monitor_heart_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _bloodPressureController,
                                    decoration: _buildInputDecoration(
                                      'Blood Pressure',
                                      hintText: '120/80',
                                      prefixIcon: const Icon(
                                        Icons.speed_rounded,
                                        size: 18,
                                        color: _primaryAqua,
                                      ),
                                      suffix: const Text(
                                        'mmHg',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _mutedCoolGray,
                                        ),
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: _lightOffWhite,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: TextFormField(
                                    controller: _temperatureController,
                                    decoration: _buildInputDecoration(
                                      'Body Temperature',
                                      hintText: '36.5',
                                      prefixIcon: const Icon(
                                        Icons.thermostat_rounded,
                                        size: 18,
                                        color: _primaryAqua,
                                      ),
                                      suffix: const Text(
                                        '°C',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _mutedCoolGray,
                                        ),
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: _lightOffWhite,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _heartRateController,
                                    decoration: _buildInputDecoration(
                                      'Heart Rate / Pulse',
                                      hintText: '75',
                                      prefixIcon: const Icon(
                                        Icons.favorite_rounded,
                                        size: 18,
                                        color: _primaryAqua,
                                      ),
                                      suffix: const Text(
                                        'bpm',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _mutedCoolGray,
                                        ),
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: _lightOffWhite,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: TextFormField(
                                    controller: _respiratoryRateController,
                                    decoration: _buildInputDecoration(
                                      'Respiratory Rate',
                                      hintText: '18',
                                      prefixIcon: const Icon(
                                        Icons.air_rounded,
                                        size: 18,
                                        color: _primaryAqua,
                                      ),
                                      suffix: const Text(
                                        'brpm',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _mutedCoolGray,
                                        ),
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: _lightOffWhite,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _oxygenSaturationController,
                                    decoration: _buildInputDecoration(
                                      'Oxygen Saturation (SpO2)',
                                      hintText: '98',
                                      prefixIcon: const Icon(
                                        Icons.water_drop_rounded,
                                        size: 18,
                                        color: _primaryAqua,
                                      ),
                                      suffix: const Text(
                                        '%',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _mutedCoolGray,
                                        ),
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: _lightOffWhite,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: TextFormField(
                                    controller: _weightController,
                                    decoration: _buildInputDecoration(
                                      'Weight',
                                      hintText: '60',
                                      prefixIcon: const Icon(
                                        Icons.scale_rounded,
                                        size: 18,
                                        color: _primaryAqua,
                                      ),
                                      suffix: const Text(
                                        'kg',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _mutedCoolGray,
                                        ),
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: _lightOffWhite,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: TextFormField(
                                    controller: _heightController,
                                    decoration: _buildInputDecoration(
                                      'Height',
                                      hintText: '165',
                                      prefixIcon: const Icon(
                                        Icons.height_rounded,
                                        size: 18,
                                        color: _primaryAqua,
                                      ),
                                      suffix: const Text(
                                        'cm',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _mutedCoolGray,
                                        ),
                                      ),
                                    ),
                                    style: const TextStyle(
                                      color: _lightOffWhite,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );

                      final clinicalObsCard = _buildSectionCard(
                        context: context,
                        title: 'Clinical Observations & Symptoms',
                        icon: Icons.medical_information_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _symptomsController,
                              decoration: _buildInputDecoration(
                                'Symptoms / Known Conditions / Chief Complaint',
                                hintText:
                                    'Describe the primary symptoms, complaints, onset, duration, and clinical observations...',
                              ),
                              style: const TextStyle(
                                color: _lightOffWhite,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 4,
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Symptoms / observations are required'
                                  : null,
                            ),
                          ],
                        ),
                      );

                      final followUpCard = _buildSectionCard(
                        context: context,
                        title: 'Next Follow-up Consultation',
                        icon: Icons.event_available_rounded,
                        child: InkWell(
                          onTap: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate:
                                  _followUpDate ??
                                  now.add(const Duration(days: 7)),
                              firstDate: now,
                              lastDate: now.add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setState(() {
                                _followUpDate = picked;
                              });
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _followUpDate != null
                                    ? _primaryAqua.withValues(alpha: 0.5)
                                    : Colors.black.withValues(alpha: 0.12),
                                width: _followUpDate != null ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _primaryAqua.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.calendar_month_rounded,
                                    color: _primaryAqua,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Scheduled Follow-up Date',
                                        style: TextStyle(
                                          color: _mutedCoolGray,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _followUpDate != null
                                            ? DateFormat(
                                                'EEEE, MMMM d, yyyy',
                                              ).format(_followUpDate!)
                                            : 'Tap to schedule next clinical consultation',
                                        style: TextStyle(
                                          color: _followUpDate != null
                                              ? _lightOffWhite
                                              : _mutedCoolGray.withValues(
                                                  alpha: 0.7,
                                                ),
                                          fontSize: 14,
                                          fontWeight: _followUpDate != null
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_followUpDate != null)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.clear_rounded,
                                      size: 18,
                                      color: _mutedCoolGray,
                                    ),
                                    tooltip: 'Clear date',
                                    onPressed: () => setState(
                                      () => _followUpDate = null,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );

                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  patientInfoCard,
                                  const SizedBox(height: 16),
                                  followUpCard,
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  vitalSignsCard,
                                  const SizedBox(height: 16),
                                  clinicalObsCard,
                                ],
                              ),
                            ),
                          ],
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          patientInfoCard,
                          const SizedBox(height: 16),
                          vitalSignsCard,
                          const SizedBox(height: 16),
                          clinicalObsCard,
                          const SizedBox(height: 16),
                          followUpCard,
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            // Bottom Action Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _lightOffWhite,
                      side: BorderSide(
                        color: Colors.black.withValues(alpha: 0.18),
                        width: 1.2,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.referralStrong,
                      side: const BorderSide(
                        color: AppColors.referral,
                        width: 1.2,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.local_hospital_outlined, size: 18),
                    label: const Text(
                      'Save & Refer to CHO',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    onPressed: _isSaving
                        ? null
                        : () async {
                            if (_formKey.currentState?.validate() ?? false) {
                              final saved = await _buildAndSaveCheckupRecord();
                              if (saved != null && context.mounted) {
                                Navigator.of(
                                  context,
                                ).pop(_ReferralHandoff(saved));
                              }
                            }
                          },
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _primaryAqua,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.check_circle_rounded, size: 18),
                    label: Text(
                      _isSaving ? 'Saving...' : 'Save Record',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    onPressed: _isSaving
                        ? null
                        : () async {
                            if (_formKey.currentState?.validate() ?? false) {
                              final saved = await _buildAndSaveCheckupRecord();
                              if (saved != null && context.mounted) {
                                Navigator.of(context).pop(_diseaseType);
                              }
                            }
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the check-up record from the current form state, saves it, and
  /// runs the same AI-classification flow as the primary Save button. Shared
  /// by "Save Record" and "Save & Refer to CHO" so both buttons behave
  /// identically up to the point where the modal closes.
  Future<Map<String, dynamic>?> _buildAndSaveCheckupRecord() async {
    setState(() => _isSaving = true);
    try {
      List<String> vitalSignsParts = [];

      if (_bloodPressureController.text.isNotEmpty) {
        vitalSignsParts.add('BP: ${_bloodPressureController.text}');
      }
      if (_temperatureController.text.isNotEmpty) {
        vitalSignsParts.add('Temp: ${_temperatureController.text}°C');
      }
      if (_heartRateController.text.isNotEmpty) {
        vitalSignsParts.add('HR: ${_heartRateController.text} bpm');
      }
      if (_respiratoryRateController.text.isNotEmpty) {
        vitalSignsParts.add('RR: ${_respiratoryRateController.text} brpm');
      }
      if (_oxygenSaturationController.text.isNotEmpty) {
        vitalSignsParts.add('O2: ${_oxygenSaturationController.text}%');
      }
      if (_weightController.text.isNotEmpty) {
        vitalSignsParts.add('Weight: ${_weightController.text} kg');
      }
      if (_heightController.text.isNotEmpty) {
        vitalSignsParts.add('Height: ${_heightController.text} cm');
      }

      String vitalSignsString = vitalSignsParts.join(', ');

      final now = DateTime.now();
      final linkedPatientId =
          widget.patientSeed?['linkedPatientId']?.toString().trim() ?? '';
      final patientId =
          widget.patientSeed?['patientId']?.toString().trim() ?? '';
      final Map<String, dynamic> newRecord = {
        if (linkedPatientId.isNotEmpty) 'linkedPatientId': linkedPatientId,
        if (patientId.isNotEmpty) 'patientId': patientId,
        'datetime':
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        'status': 'Completed',
        'type': 'General',
        'diseaseType': _diseaseType,
        'patient': '${_firstNameController.text} ${_surnameController.text}',
        'patientName':
            '${_firstNameController.text} ${_surnameController.text}',
        'age': _ageController.text,
        'address': _addressController.text,
        'vitalsigns': vitalSignsString,
        'symptoms': _symptomsController.text,
        'details': vitalSignsString.isNotEmpty
            ? '$vitalSignsString | ${_symptomsController.text}'
            : 'Age: ${_ageController.text}, ${_symptomsController.text}',
        'followup': _followUpDate != null
            ? '${_followUpDate!.year}-${_followUpDate!.month.toString().padLeft(2, '0')}-${_followUpDate!.day.toString().padLeft(2, '0')}'
            : 'N/A',
      };

      // AI Classification
      SymptomGuidanceResult? classification;
      try {
        classification = await widget.guidanceApi.getGuidanceFromText(
          _symptomsController.text,
        );
        newRecord.addAll(classification.toRecordFields());
        newRecord['ai_category'] = classification.category;
        newRecord['ai_severity'] = classification.severity;
        newRecord['ai_confidence'] = classification.confidence.toString();
        newRecord['ai_method'] = classification.method;
        if (classification.keywords != null) {
          newRecord['ai_keywords'] = classification.keywords!.join(', ');
        }
        if (classification.recoveryPlan != null) {
          newRecord['ai_recovery_plan'] = jsonEncode(
            classification.recoveryPlan,
          );
        }
      } catch (e) {
        newRecord.addAll(
          _localHealthCategoryFallback(_symptomsController.text),
        );
      }

      // Call the callback to save the record
      await widget.onSave(newRecord);

      // Show AI Classification modal
      if (context.mounted && classification != null) {
        setState(() => _isSaving = false);
        newRecord.remove('ai_confidence');
        await _showSymptomGuidanceModal(context, classification);
      }

      return newRecord;
    } catch (e) {
      setState(() => _isSaving = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving record: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  Future<void> _showSymptomGuidanceModal(
    BuildContext context,
    SymptomGuidanceResult result,
  ) async {
    Widget section(
      String title,
      IconData icon,
      Color color,
      List<String> items,
    ) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• $item',
                  style: const TextStyle(
                    color: _lightOffWhite,
                    fontSize: 13.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 780),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                decoration: const BoxDecoration(
                  color: _darkDeepTeal,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.health_and_safety_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'AI Symptom Guidance',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recognized symptoms: '
                        '${result.recognizedSymptoms.isEmpty ? 'None' : result.recognizedSymptoms.join(', ')}',
                        style: const TextStyle(
                          color: _lightOffWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (result.recognizedConditions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Entered conditions (not AI predictions): '
                          '${result.recognizedConditions.join(', ')}',
                          style: const TextStyle(
                            color: _primaryAqua,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _primaryAqua.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _primaryAqua.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Suggested Health Category',
                              style: TextStyle(
                                color: _mutedCoolGray,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              result.suggestedHealthCategory,
                              style: const TextStyle(
                                color: _primaryAqua,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Rule-based suggestion from explicitly entered conditions. Symptoms alone remain Needs Clinical Review.',
                              style: TextStyle(
                                color: _mutedCoolGray,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      section(
                        'Home Care / Self-Care',
                        Icons.home_outlined,
                        Colors.teal,
                        result.homeCare,
                      ),
                      section(
                        'Important Precautions',
                        Icons.warning_amber_rounded,
                        Colors.orange.shade800,
                        result.precautions,
                      ),
                      section(
                        'When to Seek Medical Care',
                        Icons.medical_services_outlined,
                        _primaryAqua,
                        result.whenToSeekCare,
                      ),
                      section(
                        'Emergency Warning Signs',
                        Icons.emergency_outlined,
                        Colors.red.shade700,
                        result.emergencyWarningSigns,
                      ),
                      if (result.ignoredSymptoms.isNotEmpty)
                        section(
                          'Not Recognized',
                          Icons.help_outline,
                          Colors.amber.shade900,
                          result.ignoredSymptoms,
                        ),
                      const SizedBox(height: 18),
                      Text(
                        result.disclaimer,
                        style: const TextStyle(
                          color: _mutedCoolGray,
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FA),
                  border: Border(
                    top: BorderSide(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _primaryAqua,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text(
                      'Got It',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Legacy classifier modal retained for editing older records.
  Future<void> _showAIClassificationModal(
    BuildContext context,
    ClassificationResult classification,
  ) async {
    // Show loading spinner dialog for 3 seconds
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (loadingContext) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Center(
            child: Container(
              width: 280,
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0D274D), Color(0xFF163B66)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _primaryAqua.withValues(alpha: 0.3),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      valueColor: AlwaysStoppedAnimation<Color>(_primaryAqua),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Analyzing Health Data...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AI is classifying your record',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Wait 3 seconds then dismiss the loading dialog
      await Future.delayed(const Duration(seconds: 3));
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }

    final recoveryPlan = _parseAiRecoveryPlan(classification.recoveryPlan);
    final modalKeywords = _safeAiKeywords(classification.keywords?.join(', '));
    final modalKeywordText = modalKeywords.isEmpty
        ? 'No matching keyword found'
        : modalKeywords.join(', ');

    // Show the actual AI classification result modal
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 520,
          constraints: const BoxConstraints(maxHeight: 650),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0D274D), Color(0xFF163B66)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Classification Complete',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Health record analyzed successfully',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.check_circle,
                      color: Colors.greenAccent,
                      size: 28,
                    ),
                  ],
                ),
              ),

              // Body - scrollable
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category & Severity Row
                      Row(
                        children: [
                          Expanded(
                            child: _aiInfoCard(
                              icon: Icons.category_rounded,
                              label: 'Category',
                              value: classification.category,
                              color: _getCategoryColor(classification.category),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _aiInfoCard(
                              icon: Icons.warning_amber_rounded,
                              label: 'Severity',
                              value: classification.severity,
                              color: _getSeverityColor(classification.severity),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Confidence & Keywords Row
                      Row(
                        children: [
                          Expanded(
                            child: _aiInfoCard(
                              icon: Icons.speed_rounded,
                              label: 'Confidence',
                              value:
                                  '${(classification.confidence * 100).toStringAsFixed(1)}%',
                              color: Colors.blueAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _aiInfoCard(
                              icon: Icons.label_rounded,
                              label: 'Keywords',
                              value: modalKeywordText,
                              color: Colors.orangeAccent,
                            ),
                          ),
                        ],
                      ),

                      // Recovery Plan
                      if (recoveryPlan != null) ...[
                        const SizedBox(height: 18),
                        const Text(
                          'Recovery Plan',
                          style: TextStyle(
                            color: _primaryAqua,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Home Care
                        if (_safeAiStringList(
                          recoveryPlan['home_care'],
                        ).isNotEmpty)
                          _recoverySection(
                            icon: Icons.home_rounded,
                            title: 'Home Care',
                            items: _safeAiStringList(recoveryPlan['home_care']),
                            color: Colors.tealAccent,
                          ),

                        // Precautions
                        if (_safeAiStringList(
                          recoveryPlan['precautions'],
                        ).isNotEmpty)
                          _recoverySection(
                            icon: Icons.shield_rounded,
                            title: 'Precautions',
                            items: _safeAiStringList(
                              recoveryPlan['precautions'],
                            ),
                            color: Colors.amberAccent,
                          ),

                        // Estimated Recovery
                        if (_safeAiText(
                          recoveryPlan['estimated_recovery'],
                          fallback: '',
                        ).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _primaryAqua.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.schedule,
                                    color: _primaryAqua,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Estimated Recovery: ',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    _safeAiText(
                                      recoveryPlan['estimated_recovery'],
                                      fallback: '',
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // General Advice
                        if (_safeAiStringList(
                          recoveryPlan['general_advice'],
                        ).isNotEmpty)
                          _recoverySection(
                            icon: Icons.tips_and_updates_rounded,
                            title: 'General Advice',
                            items: _safeAiStringList(
                              recoveryPlan['general_advice'],
                            ),
                            color: Colors.lightGreenAccent,
                          ),
                      ],
                    ],
                  ),
                ),
              ),

              // Footer Button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryAqua,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text(
                      'Done',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aiInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final safeValue = _safeAiText(value, fallback: 'N/A');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            safeValue,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _recoverySection({
    required IconData icon,
    required String title,
    required List<String> items,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _primaryAqua.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.circle,
                        color: color.withValues(alpha: 0.6),
                        size: 6,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Communicable Disease':
        return Colors.orangeAccent;
      case 'Non-Communicable Disease':
        return Colors.purpleAccent;
      case 'Emergency':
        return Colors.redAccent;
      case 'Prenatal Care':
        return Colors.pinkAccent;
      case 'Pediatric Care':
        return Colors.cyanAccent;
      case 'Routine Checkup':
        return Colors.greenAccent;
      default:
        return _primaryAqua;
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'Critical':
        return Colors.red;
      case 'High':
        return Colors.deepOrange;
      case 'Medium':
        return Colors.amber;
      case 'Low':
        return Colors.greenAccent;
      default:
        return Colors.white70;
    }
  }

  // Helper method to build section cards
  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.16),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _primaryAqua, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: _lightOffWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
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

  // Helper method for input decoration
  InputDecoration _buildInputDecoration(
    String label, {
    String? hintText,
    Widget? prefixIcon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffix: suffix,
      labelStyle: const TextStyle(
        color: _mutedCoolGray,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: _mutedCoolGray.withValues(alpha: 0.6),
        fontSize: 13,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.black.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.black.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryAqua, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      filled: true,
      fillColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _surnameController.dispose();
    _ageController.dispose();
    _addressController.dispose();

    // Dispose all vital sign controllers
    _bloodPressureController.dispose();
    _temperatureController.dispose();
    _heartRateController.dispose();
    _respiratoryRateController.dispose();
    _oxygenSaturationController.dispose();
    _weightController.dispose();
    _heightController.dispose();

    _symptomsController.dispose();
    super.dispose();
  }
}

// Edit Check Up Modal
class _EditCheckUpFullScreenModal extends StatefulWidget {
  final Map<String, dynamic> record;
  final Future<int> Function(String, Map<String, dynamic>) onSave;
  final HealthAIClassifier aiClassifier;
  final SymptomGuidanceApiService guidanceApi;

  const _EditCheckUpFullScreenModal({
    required this.record,
    required this.onSave,
    required this.aiClassifier,
    required this.guidanceApi,
  });

  @override
  State<_EditCheckUpFullScreenModal> createState() =>
      _EditCheckUpFullScreenModalState();
}

class _EditCheckUpFullScreenModalState
    extends State<_EditCheckUpFullScreenModal> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _surnameController;
  late final TextEditingController _ageController;
  late final TextEditingController _addressController;

  // Separate vital sign controllers
  late final TextEditingController _bloodPressureController;
  late final TextEditingController _temperatureController;
  late final TextEditingController _heartRateController;
  late final TextEditingController _respiratoryRateController;
  late final TextEditingController _oxygenSaturationController;
  late final TextEditingController _weightController;
  late final TextEditingController _heightController;

  late final TextEditingController _symptomsController;
  DateTime? _followUpDate;
  final String _recordType = 'General';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    // Initialize controllers with existing data
    final patientName = widget.record['patient'] ?? '';
    final nameParts = patientName.split(' ');
    _firstNameController = TextEditingController(
      text: nameParts.isNotEmpty ? nameParts[0] : '',
    );
    _surnameController = TextEditingController(
      text: nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '',
    );
    _ageController = TextEditingController(
      text: widget.record['age']?.toString() ?? '',
    );
    _addressController = TextEditingController(
      text: widget.record['address'] ?? '',
    );

    // Parse vital signs from the record
    final vitalSigns = widget.record['vitalsigns'] ?? '';
    final vitalParts = vitalSigns.split(', ');
    _bloodPressureController = TextEditingController(
      text: _extractVital(vitalParts, 'BP:'),
    );
    _temperatureController = TextEditingController(
      text: _extractVital(vitalParts, 'Temp:'),
    );
    _heartRateController = TextEditingController(
      text: _extractVital(vitalParts, 'HR:'),
    );
    _respiratoryRateController = TextEditingController(
      text: _extractVital(vitalParts, 'RR:'),
    );
    _oxygenSaturationController = TextEditingController(
      text: _extractVital(vitalParts, 'O2:'),
    );
    _weightController = TextEditingController(
      text: _extractVital(vitalParts, 'Weight:'),
    );
    _heightController = TextEditingController(
      text: _extractVital(vitalParts, 'Height:'),
    );

    _symptomsController = TextEditingController(
      text: widget.record['symptoms'] ?? '',
    );

    if (widget.record['followup'] != null &&
        widget.record['followup'] != 'N/A') {
      try {
        _followUpDate = DateTime.parse(widget.record['followup']);
      } catch (e) {
        _followUpDate = null;
      }
    }
  }

  String _extractVital(List<String> parts, String prefix) {
    for (var part in parts) {
      if (part.trim().startsWith(prefix)) {
        String value = part.trim().substring(prefix.length).trim();
        // Remove unit suffixes to prevent duplication on re-save
        value = value
            .replaceAll(RegExp(r'°C$'), '')
            .replaceAll(RegExp(r'\s*brpm$', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s*bpm$', caseSensitive: false), '')
            .replaceAll(RegExp(r'%$'), '')
            .replaceAll(RegExp(r'\s*kg$', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s*cm$', caseSensitive: false), '')
            .trim();
        return value;
      }
    }
    return '';
  }

  Future<void> _saveChanges() async {
    if (_isSaving || _formKey.currentState?.validate() != true) return;
    setState(() => _isSaving = true);

    try {
      final patientName =
          '${_firstNameController.text} ${_surnameController.text}';
      final vitalsList = <String>[];
      if (_bloodPressureController.text.isNotEmpty) {
        vitalsList.add('BP: ${_bloodPressureController.text}');
      }
      if (_temperatureController.text.isNotEmpty) {
        vitalsList.add('Temp: ${_temperatureController.text}°C');
      }
      if (_heartRateController.text.isNotEmpty) {
        vitalsList.add('HR: ${_heartRateController.text} bpm');
      }
      if (_respiratoryRateController.text.isNotEmpty) {
        vitalsList.add('RR: ${_respiratoryRateController.text} brpm');
      }
      if (_oxygenSaturationController.text.isNotEmpty) {
        vitalsList.add('O2: ${_oxygenSaturationController.text}%');
      }
      if (_weightController.text.isNotEmpty) {
        vitalsList.add('Weight: ${_weightController.text} kg');
      }
      if (_heightController.text.isNotEmpty) {
        vitalsList.add('Height: ${_heightController.text} cm');
      }

      final updatedRecord = <String, dynamic>{
        'id': widget.record['id'],
        // Preserve the exact source document and its authorization scope.
        // The database helper removes `_firestorePath` before writing.
        '_firestorePath': widget.record['_firestorePath'],
        'barangay': widget.record['barangay'],
        'barangayCode': widget.record['barangayCode'],
        'barangayDistrict': widget.record['barangayDistrict'],
        'patient': patientName,
        'age': _ageController.text,
        'address': _addressController.text,
        'type': 'General',
        'datetime': widget.record['datetime'],
        'vitalsigns': vitalsList.join(', '),
        'symptoms': _symptomsController.text,
        'followup': _followUpDate != null
            ? '${_followUpDate!.year}-${_followUpDate!.month.toString().padLeft(2, '0')}-${_followUpDate!.day.toString().padLeft(2, '0')}'
            : 'N/A',
      };

      SymptomGuidanceResult? classification;
      try {
        classification = await widget.guidanceApi.getGuidanceFromText(
          _symptomsController.text,
        );
        updatedRecord.addAll(classification.toRecordFields());
      } catch (error) {
        debugPrint('Health-category classification failed on edit: $error');
        updatedRecord.addAll(
          _localHealthCategoryFallback(_symptomsController.text),
        );
      }

      final recordId = updatedRecord['id']?.toString() ?? '';
      if (recordId.isEmpty) {
        throw StateError('This check-up record has no document ID.');
      }
      final saved = await widget.onSave(recordId, updatedRecord);
      if (saved != 1) {
        throw StateError('The check-up record was not updated.');
      }
      if (!mounted) return;

      if (classification != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved as ${classification.suggestedHealthCategory}.',
            ),
            backgroundColor: const Color(0xFF087F5B),
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      final message =
          error is FirebaseException && error.code == 'permission-denied'
          ? 'You do not have permission to edit this check-up record. Verify that it belongs to your assigned barangay and that the latest Firestore rules are deployed.'
          : 'Could not save changes: $error';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red.shade700,
          ),
        );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Container(
        width: screenSize.width,
        height: screenSize.height,
        color: const Color(0xFFF5F7FA),
        child: Column(
          children: [
            // Header Bar
            Container(
              height: 76,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: const BoxDecoration(
                color: _darkDeepTeal,
                border: Border(
                  bottom: BorderSide(
                    color: Color(0x20FFFFFF),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Check-Up Record',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Update patient clinical assessment, vitals, and follow-up notes',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                    tooltip: 'Close editor',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            // Form Content Area
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Patient Information Section
                          _buildSectionCard(
                            context: context,
                            title: 'Patient Information',
                            icon: Icons.person_rounded,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _firstNameController,
                                        decoration: _buildInputDecoration(
                                          'First Name',
                                          hintText: 'Enter given name',
                                          prefixIcon: const Icon(
                                            Icons.badge_outlined,
                                            size: 18,
                                            color: _primaryAqua,
                                          ),
                                        ),
                                        style: const TextStyle(
                                          color: _lightOffWhite,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'First name is required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _surnameController,
                                        decoration: _buildInputDecoration(
                                          'Surname',
                                          hintText: 'Enter family name',
                                          prefixIcon: const Icon(
                                            Icons.badge_outlined,
                                            size: 18,
                                            color: _primaryAqua,
                                          ),
                                        ),
                                        style: const TextStyle(
                                          color: _lightOffWhite,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Surname is required'
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 160,
                                      child: TextFormField(
                                        controller: _ageController,
                                        decoration: _buildInputDecoration(
                                          'Age (yrs)',
                                          hintText: 'e.g. 35',
                                          prefixIcon: const Icon(
                                            Icons.cake_outlined,
                                            size: 18,
                                            color: _primaryAqua,
                                          ),
                                        ),
                                        style: const TextStyle(
                                          color: _lightOffWhite,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        keyboardType: TextInputType.number,
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Age is required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _addressController,
                                        decoration: _buildInputDecoration(
                                          'Residential Address',
                                          hintText: 'House / Street / Barangay / Municipality',
                                          prefixIcon: const Icon(
                                            Icons.home_outlined,
                                            size: 18,
                                            color: _primaryAqua,
                                          ),
                                        ),
                                        style: const TextStyle(
                                          color: _lightOffWhite,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Address is required'
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Vital Signs & Measurements Section
                          _buildSectionCard(
                            context: context,
                            title: 'Vital Signs & Physical Measurements',
                            icon: Icons.monitor_heart_rounded,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _bloodPressureController,
                                        decoration: _buildInputDecoration(
                                          'Blood Pressure',
                                          hintText: '120/80',
                                          prefixIcon: const Icon(
                                            Icons.speed_rounded,
                                            size: 18,
                                            color: _primaryAqua,
                                          ),
                                          suffix: const Text(
                                            'mmHg',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _mutedCoolGray,
                                            ),
                                          ),
                                        ),
                                        style: const TextStyle(
                                          color: _lightOffWhite,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _temperatureController,
                                        decoration: _buildInputDecoration(
                                          'Body Temperature',
                                          hintText: '36.5',
                                          prefixIcon: const Icon(
                                            Icons.thermostat_rounded,
                                            size: 18,
                                            color: _primaryAqua,
                                          ),
                                          suffix: const Text(
                                            '°C',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _mutedCoolGray,
                                            ),
                                          ),
                                        ),
                                        style: const TextStyle(
                                          color: _lightOffWhite,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _heartRateController,
                                        decoration: _buildInputDecoration(
                                          'Heart Rate',
                                          hintText: '75',
                                          prefixIcon: const Icon(
                                            Icons.favorite_rounded,
                                            size: 18,
                                            color: _primaryAqua,
                                          ),
                                          suffix: const Text(
                                            'bpm',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _mutedCoolGray,
                                            ),
                                          ),
                                        ),
                                        style: const TextStyle(
                                          color: _lightOffWhite,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        keyboardType: TextInputType.number,
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _respiratoryRateController,
                                        decoration: _buildInputDecoration(
                                          'Respiratory Rate',
                                          hintText: '18',
                                          prefixIcon: const Icon(
                                            Icons.air_rounded,
                                            size: 18,
                                            color: _primaryAqua,
                                          ),
                                          suffix: const Text(
                                            'brpm',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _mutedCoolGray,
                                            ),
                                          ),
                                        ),
                                        style: const TextStyle(
                                          color: _lightOffWhite,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        keyboardType: TextInputType.number,
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _oxygenSaturationController,
                                        decoration: _buildInputDecoration(
                                          'Oxygen Saturation',
                                          hintText: '98',
                                          prefixIcon: const Icon(
                                            Icons.water_drop_rounded,
                                            size: 18,
                                            color: _primaryAqua,
                                          ),
                                          suffix: const Text(
                                            '%',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _mutedCoolGray,
                                            ),
                                          ),
                                        ),
                                        style: const TextStyle(
                                          color: _lightOffWhite,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        keyboardType: TextInputType.number,
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _weightController,
                                        decoration: _buildInputDecoration(
                                          'Weight',
                                          hintText: '60',
                                          prefixIcon: const Icon(
                                            Icons.fitness_center_rounded,
                                            size: 18,
                                            color: _primaryAqua,
                                          ),
                                          suffix: const Text(
                                            'kg',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _mutedCoolGray,
                                            ),
                                          ),
                                        ),
                                        style: const TextStyle(
                                          color: _lightOffWhite,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _heightController,
                                        decoration: _buildInputDecoration(
                                          'Height',
                                          hintText: '165',
                                          prefixIcon: const Icon(
                                            Icons.height_rounded,
                                            size: 18,
                                            color: _primaryAqua,
                                          ),
                                          suffix: const Text(
                                            'cm',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _mutedCoolGray,
                                            ),
                                          ),
                                        ),
                                        style: const TextStyle(
                                          color: _lightOffWhite,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Clinical Details Section
                          _buildSectionCard(
                            context: context,
                            title: 'Clinical Observations & Symptoms',
                            icon: Icons.medical_information_rounded,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextFormField(
                                  controller: _symptomsController,
                                  decoration: _buildInputDecoration(
                                    'Symptoms / Known Conditions / Chief Complaint',
                                    hintText:
                                        'Describe the primary symptoms, complaints, onset, duration, and clinical observations...',
                                  ),
                                  style: const TextStyle(
                                    color: _lightOffWhite,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 4,
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Symptoms / observations are required'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Follow-up Section
                          _buildSectionCard(
                            context: context,
                            title: 'Next Follow-up Consultation',
                            icon: Icons.event_available_rounded,
                            child: InkWell(
                              onTap: () async {
                                final now = DateTime.now();
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _followUpDate ??
                                      now.add(const Duration(days: 7)),
                                  firstDate: now.subtract(const Duration(days: 30)),
                                  lastDate: now.add(const Duration(days: 365)),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _followUpDate = picked;
                                  });
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _followUpDate != null
                                        ? _primaryAqua.withValues(alpha: 0.5)
                                        : Colors.black.withValues(alpha: 0.12),
                                    width: _followUpDate != null ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color:
                                            _primaryAqua.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.calendar_month_rounded,
                                        color: _primaryAqua,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Scheduled Follow-up Date',
                                            style: TextStyle(
                                              color: _mutedCoolGray,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _followUpDate != null
                                                ? DateFormat(
                                                    'EEEE, MMMM d, yyyy',
                                                  ).format(_followUpDate!)
                                                : 'Tap to schedule next clinical consultation',
                                            style: TextStyle(
                                              color: _followUpDate != null
                                                  ? _lightOffWhite
                                                  : _mutedCoolGray.withValues(
                                                      alpha: 0.7,
                                                    ),
                                              fontSize: 14,
                                              fontWeight: _followUpDate != null
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_followUpDate != null)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.clear_rounded,
                                          size: 18,
                                          color: _mutedCoolGray,
                                        ),
                                        tooltip: 'Clear date',
                                        onPressed: () => setState(
                                          () => _followUpDate = null,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Bottom Action Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _lightOffWhite,
                      side: BorderSide(
                        color: Colors.black.withValues(alpha: 0.18),
                        width: 1.2,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _primaryAqua,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(
                      _isSaving ? 'Saving...' : 'Save Changes',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    onPressed: _isSaving ? null : _saveChanges,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.16),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _primaryAqua, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: _lightOffWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
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

  InputDecoration _buildInputDecoration(
    String label, {
    String? hintText,
    Widget? prefixIcon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffix: suffix,
      labelStyle: const TextStyle(
        color: _mutedCoolGray,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: _mutedCoolGray.withValues(alpha: 0.6),
        fontSize: 13,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.black.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.black.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryAqua, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      filled: true,
      fillColor: Colors.white,
    );
  }

  // Show AI Classification result modal with loading spinner for edited records
  Future<void> _showEditAIClassificationModal(
    BuildContext context,
    ClassificationResult classification,
  ) async {
    // Show loading spinner dialog for 3 seconds
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (loadingContext) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Center(
            child: Container(
              width: 280,
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0D274D), Color(0xFF163B66)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _primaryAqua.withValues(alpha: 0.3),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      valueColor: AlwaysStoppedAnimation<Color>(_primaryAqua),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Re-analyzing Health Data...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AI is re-classifying your updated record',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await Future.delayed(const Duration(seconds: 3));
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }

    final recoveryPlan = _parseAiRecoveryPlan(classification.recoveryPlan);
    final modalKeywords = _safeAiKeywords(classification.keywords?.join(', '));
    final modalKeywordText = modalKeywords.isEmpty
        ? 'No matching keyword found'
        : modalKeywords.join(', ');

    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 520,
          constraints: const BoxConstraints(maxHeight: 650),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0D274D), Color(0xFF163B66)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Re-Classification Complete',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Updated record analyzed successfully',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.check_circle,
                      color: Colors.greenAccent,
                      size: 28,
                    ),
                  ],
                ),
              ),

              // Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _editAiInfoCard(
                              icon: Icons.category_rounded,
                              label: 'Category',
                              value: classification.category,
                              color: _editGetCategoryColor(
                                classification.category,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _editAiInfoCard(
                              icon: Icons.warning_amber_rounded,
                              label: 'Severity',
                              value: classification.severity,
                              color: _editGetSeverityColor(
                                classification.severity,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _editAiInfoCard(
                              icon: Icons.speed_rounded,
                              label: 'Confidence',
                              value:
                                  '${(classification.confidence * 100).toStringAsFixed(1)}%',
                              color: Colors.blueAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _editAiInfoCard(
                              icon: Icons.label_rounded,
                              label: 'Keywords',
                              value: modalKeywordText,
                              color: Colors.orangeAccent,
                            ),
                          ),
                        ],
                      ),

                      if (recoveryPlan != null) ...[
                        const SizedBox(height: 18),
                        const Text(
                          'Recovery Plan',
                          style: TextStyle(
                            color: _primaryAqua,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_safeAiStringList(
                          recoveryPlan['home_care'],
                        ).isNotEmpty)
                          _editRecoverySection(
                            icon: Icons.home_rounded,
                            title: 'Home Care',
                            items: _safeAiStringList(recoveryPlan['home_care']),
                            color: Colors.tealAccent,
                          ),
                        if (_safeAiStringList(
                          recoveryPlan['precautions'],
                        ).isNotEmpty)
                          _editRecoverySection(
                            icon: Icons.shield_rounded,
                            title: 'Precautions',
                            items: _safeAiStringList(
                              recoveryPlan['precautions'],
                            ),
                            color: Colors.amberAccent,
                          ),
                        if (_safeAiText(
                          recoveryPlan['estimated_recovery'],
                          fallback: '',
                        ).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _primaryAqua.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.schedule,
                                    color: _primaryAqua,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Estimated Recovery: ',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    _safeAiText(
                                      recoveryPlan['estimated_recovery'],
                                      fallback: '',
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_safeAiStringList(
                          recoveryPlan['general_advice'],
                        ).isNotEmpty)
                          _editRecoverySection(
                            icon: Icons.tips_and_updates_rounded,
                            title: 'General Advice',
                            items: _safeAiStringList(
                              recoveryPlan['general_advice'],
                            ),
                            color: Colors.lightGreenAccent,
                          ),
                      ],
                    ],
                  ),
                ),
              ),

              // Footer
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryAqua,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text(
                      'Done',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editAiInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final safeValue = _safeAiText(value, fallback: 'N/A');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            safeValue,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _editRecoverySection({
    required IconData icon,
    required String title,
    required List<String> items,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _primaryAqua.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.circle,
                        color: color.withValues(alpha: 0.6),
                        size: 6,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _editGetCategoryColor(String category) {
    switch (category) {
      case 'Communicable Disease':
        return Colors.orangeAccent;
      case 'Non-Communicable Disease':
        return Colors.purpleAccent;
      case 'Emergency':
        return Colors.redAccent;
      case 'Prenatal Care':
        return Colors.pinkAccent;
      case 'Pediatric Care':
        return Colors.cyanAccent;
      case 'Routine Checkup':
        return Colors.greenAccent;
      default:
        return _primaryAqua;
    }
  }

  Color _editGetSeverityColor(String severity) {
    switch (severity) {
      case 'Critical':
        return Colors.red;
      case 'High':
        return Colors.deepOrange;
      case 'Medium':
        return Colors.amber;
      case 'Low':
        return Colors.greenAccent;
      default:
        return Colors.white70;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _surnameController.dispose();
    _ageController.dispose();
    _addressController.dispose();
    _bloodPressureController.dispose();
    _temperatureController.dispose();
    _heartRateController.dispose();
    _respiratoryRateController.dispose();
    _oxygenSaturationController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _symptomsController.dispose();
    super.dispose();
  }
}

// AI Classification Display Methods
bool _isInvalidAiText(String? value) {
  if (value == null) return true;
  final normalized = value.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == 'undefined' ||
      normalized == 'null';
}

String _safeAiText(dynamic value, {String fallback = 'N/A'}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return _isInvalidAiText(text) ? fallback : text;
}

List<String> _safeAiStringList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => _safeAiText(item, fallback: '').trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const <String>[];
}

double _safeAiConfidence(dynamic value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  final confidence = parsed ?? 0.0;
  if (confidence.isNaN) return 0.0;
  if (confidence < 0) return 0.0;
  if (confidence > 1) return 1.0;
  return confidence;
}

List<String> _safeAiKeywords(dynamic rawKeywords) {
  final text = _safeAiText(rawKeywords, fallback: '');
  if (text.isEmpty) return const <String>[];

  final seen = <String>{};
  final keywords = <String>[];
  for (final raw in text.split(',')) {
    final keyword = _safeAiText(raw, fallback: '').trim();
    if (keyword.isEmpty) continue;
    final key = keyword.toLowerCase();
    if (seen.add(key)) {
      keywords.add(keyword);
    }
  }
  return keywords;
}

Map<String, dynamic>? _parseAiRecoveryPlan(dynamic recoveryData) {
  try {
    Map<String, dynamic>? plan;
    if (recoveryData is Map) {
      plan = Map<String, dynamic>.from(recoveryData);
    } else if (recoveryData is String && !_isInvalidAiText(recoveryData)) {
      final decoded = jsonDecode(recoveryData);
      if (decoded is Map) {
        plan = Map<String, dynamic>.from(decoded);
      }
    }

    if (plan == null) return null;

    final homeCare = _safeAiStringList(plan['home_care']);
    final precautions = _safeAiStringList(plan['precautions']);
    final generalAdvice = _safeAiStringList(plan['general_advice']);
    final estimatedRecovery = _safeAiText(
      plan['estimated_recovery'],
      fallback: '',
    );

    if (homeCare.isEmpty &&
        precautions.isEmpty &&
        generalAdvice.isEmpty &&
        estimatedRecovery.isEmpty) {
      return null;
    }

    return {
      'home_care': homeCare,
      'precautions': precautions,
      'general_advice': generalAdvice,
      'estimated_recovery': estimatedRecovery,
    };
  } catch (e) {
    print('Error parsing recovery plan: $e');
    return null;
  }
}

Widget _buildAIClassificationSection(Map<String, dynamic> record) {
  final category = _safeAiText(record['ai_category'], fallback: 'Unknown');
  final severity = _safeAiText(record['ai_severity'], fallback: 'Unknown');
  final confidence = _safeAiConfidence(record['ai_confidence']);
  final method = _safeAiText(
    record['ai_method'],
    fallback: 'unknown',
  ).toLowerCase();
  final keywords = _safeAiKeywords(record['ai_keywords']);

  final recoveryPlan = _parseAiRecoveryPlan(record['ai_recovery_plan']);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _sidebarDark.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFBA68C8).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.psychology_outlined,
                    color: Color(0xFFBA68C8),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Classification',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Machine-assisted interpretation attached to this check-up record.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (method == 'ml_model'
                                ? const Color(0xFFBA68C8)
                                : const Color(0xFF64B5F6))
                            .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color:
                          (method == 'ml_model'
                                  ? const Color(0xFFBA68C8)
                                  : const Color(0xFF64B5F6))
                              .withValues(alpha: 0.24),
                    ),
                  ),
                  child: Text(
                    method == 'ml_model' ? 'ML Model' : 'Rule-Based',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: method == 'ml_model'
                          ? const Color(0xFFCE93D8)
                          : const Color(0xFF90CAF9),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildAIBadge(
                    label: 'Category',
                    value: category,
                    icon: Icons.category,
                    color: _getCategoryColor(category),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildAIBadge(
                    label: 'Severity',
                    value: severity,
                    icon: Icons.warning_amber,
                    color: _getSeverityColor(severity),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.speed, size: 16, color: Color(0xFF90A4AE)),
                  const SizedBox(width: 8),
                  const Text(
                    'Confidence',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: confidence,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        confidence > 0.7
                            ? const Color(0xFF66BB6A)
                            : confidence > 0.4
                            ? const Color(0xFFFFB74D)
                            : const Color(0xFFE57373),
                      ),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(confidence * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (keywords.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: keywords.take(5).map((keyword) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _primaryAqua.withValues(alpha: 0.24),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      keyword,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
      if (recoveryPlan != null) ...[
        const SizedBox(height: 16),
        _buildRecoveryRecommendations(recoveryPlan),
      ],
    ],
  );
}

Widget _buildRecoveryRecommendations(Map<String, dynamic> recoveryPlan) {
  final homeCare = _safeAiStringList(recoveryPlan['home_care']);
  final precautions = _safeAiStringList(recoveryPlan['precautions']);
  final estimatedRecovery = _safeAiText(
    recoveryPlan['estimated_recovery'],
    fallback: '',
  );
  final generalAdvice = _safeAiStringList(recoveryPlan['general_advice']);

  return Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _sidebarDark.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF81C784).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.healing_outlined,
                color: Color(0xFF81C784),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'AI-Assisted Home-Care Recommendation',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (estimatedRecovery.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _primaryAqua.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.schedule_outlined,
                  color: Color(0xFF64B5F6),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Estimated Recovery: $estimatedRecovery',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Home Care
        if (homeCare.isNotEmpty) ...[
          _buildRecommendationSection(
            'Home Care Instructions',
            Icons.home_outlined,
            homeCare,
            Colors.orange.shade700,
            Colors.orange.shade50,
          ),
          const SizedBox(height: 10),
        ],

        // Precautions
        if (precautions.isNotEmpty) ...[
          _buildRecommendationSection(
            'Important Precautions',
            Icons.warning_amber_rounded,
            precautions,
            Colors.red.shade700,
            Colors.red.shade50,
          ),
          const SizedBox(height: 10),
        ],

        // General Advice
        if (generalAdvice.isNotEmpty) ...[
          _buildRecommendationSection(
            'General Advice',
            Icons.info_outline,
            generalAdvice,
            Colors.teal.shade700,
            Colors.teal.shade50,
          ),
        ],

        // Disclaimer
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFFFB74D).withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFFFFB74D),
                size: 14,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: const Text(
                  'AI-generated information provides supportive home-care '
                  'guidance only. Medication and clinical decisions remain '
                  'under the attending physician.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white70,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildRecommendationSection(
  String title,
  IconData icon,
  List<String> items,
  Color textColor,
  Color bgColor,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: textColor.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: textColor),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: textColor.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.white70,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _buildAIBadge({
  required String label,
  required String value,
  required IconData icon,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withValues(alpha: 0.22), width: 1.2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            color: color,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

Color _getCategoryColor(String category) {
  switch (category.toLowerCase()) {
    case 'emergency':
      return Colors.red;
    case 'communicable disease':
      return Colors.orange;
    case 'non-communicable disease':
      return Colors.blue;
    case 'prenatal care':
      return Colors.pink;
    case 'pediatric care':
      return Colors.purple;
    default:
      return Colors.green;
  }
}

Color _getSeverityColor(String severity) {
  switch (severity.toLowerCase()) {
    case 'critical':
      return Colors.red.shade700;
    case 'high':
      return Colors.orange.shade700;
    case 'medium':
      return Colors.yellow.shade700;
    default:
      return Colors.green.shade600;
  }
}
