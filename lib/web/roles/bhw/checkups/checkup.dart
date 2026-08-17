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
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/roles/bhw/analytics/health_metrics.dart';
import 'package:mycapstone_project/web/roles/cho/analytics/analytics.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal.dart';
import 'package:mycapstone_project/web/roles/bhw/immunization/immunization.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/communicable.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/non_communicable.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/mortality.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
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
import 'package:mycapstone_project/shared/current_table_record_utils.dart';
import 'package:mycapstone_project/web/shared/utils/checkup_pdf.dart';
import 'package:mycapstone_project/web/shared/utils/file_download.dart';
import 'package:mycapstone_project/web/shared/utils/report_generation.dart';
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
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _NewCheckUpFullScreenModal(
        onSave: (record) => _dbHelper.insertRecord(record),
        guidanceApi: _guidanceApi,
        patientSeed: patientSeed,
      ),
    );

    if (result != null) {
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
      drawer: WebAppSidebar(
        userName: userName,
        activeItem: WebSidebarItem.checkups,
      ),
      body: Column(
        children: [
          // Main Content Area
          Expanded(
            child: Column(
              children: [
                // Top Bar
                _buildTopBar(context),
                // Main scrollable content
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
                                        color: _sidebarDark,
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
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(color: _darkDeepTeal),
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
            'Check-up Dashboard',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _isLoading ? null : _generateCheckupReport,
            style: AppButtonStyles.report(),
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
            label: const Text(
              'Generate',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Data',
            onPressed: () => _loadRecords(),
            color: Colors.white70,
          ),
          const SizedBox(width: 12),
          if (kDebugMode)
            PopupMenuButton(
              icon: const Icon(Icons.more_vert_outlined, color: Colors.white),
              color: _mutedCoolGray,
              itemBuilder: (context) => [
                PopupMenuItem(
                  child: const Text('Seed Sample Data'),
                  onTap: () => _seedSampleData(),
                ),
                PopupMenuItem(
                  child: const Text('View Data in Console'),
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Data printed to console! Check Debug Console.',
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
        ],
      ),
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
              width: 112,
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
    return WebSearchField(
      controller: _effectiveSearchController,
      hintText: 'Search by patient name, address, age, symptoms, or status...',
      onChanged: (value) {
        setState(() {
          _searchQuery = value.trim();
          _currentPage = 1;
          _selectedIndices.clear();
        });
        _scheduleSharedPatientSearch(value);
      },
      onClear: () {
        _effectiveSearchController.clear();
        setState(() {
          _searchQuery = '';
          _currentPage = 1;
          _selectedIndices.clear();
        });
        _scheduleSharedPatientSearch('');
      },
    );
  }

  Widget _buildFilterSection() {
    return WebFilterSurface(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final dateWidth = math.min(
              440.0,
              math.max(260.0, constraints.maxWidth - 40),
            );
            return Wrap(
              spacing: 20,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Title Section
                Icon(Icons.tune_rounded, color: _primaryAqua, size: 20),
                const SizedBox(width: 12),
                Text(
                  'Filter Results',
                  style: TextStyle(
                    color: _lightOffWhite,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 8),

                // Date Range Picker (From - To)
                SizedBox(
                  width: dateWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Date Range',
                        style: TextStyle(
                          fontSize: 11,
                          color: _mutedCoolGray,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          // From Date Picker
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _fromDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                    builder: (context, child) {
                                      return Theme(
                                        data: _buildDarkDatePickerTheme(
                                          context,
                                        ),
                                        child: child!,
                                      );
                                    },
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _fromDate = picked;
                                      // Ensure toDate is not before fromDate
                                      if (_toDate != null &&
                                          _toDate!.isBefore(picked)) {
                                        _toDate = picked;
                                      }
                                      _currentPage = 1;
                                    });
                                  }
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: _primaryAqua.withValues(
                                        alpha: 0.2,
                                      ),
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    color: const Color(0xFFF7FAFD),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.calendar_today_rounded,
                                        color: _primaryAqua,
                                        size: 12,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          _fromDate != null
                                              ? "${_fromDate!.year}-${_fromDate!.month.toString().padLeft(2, '0')}-${_fromDate!.day.toString().padLeft(2, '0')}"
                                              : 'From',
                                          style: TextStyle(
                                            color: _lightOffWhite,
                                            fontWeight: FontWeight.w500,
                                            fontSize: 12,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('-', style: TextStyle(color: _mutedCoolGray)),
                          const SizedBox(width: 8),
                          // To Date Picker
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _toDate ?? DateTime.now(),
                                    firstDate: _fromDate ?? DateTime(2020),
                                    lastDate: DateTime.now(),
                                    builder: (context, child) {
                                      return Theme(
                                        data: _buildDarkDatePickerTheme(
                                          context,
                                        ),
                                        child: child!,
                                      );
                                    },
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _toDate = picked;
                                      _currentPage = 1;
                                    });
                                  }
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: _primaryAqua.withValues(
                                        alpha: 0.2,
                                      ),
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    color: const Color(0xFFF7FAFD),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.calendar_today_rounded,
                                        color: _primaryAqua,
                                        size: 12,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          _toDate != null
                                              ? "${_toDate!.year}-${_toDate!.month.toString().padLeft(2, '0')}-${_toDate!.day.toString().padLeft(2, '0')}"
                                              : 'To',
                                          style: TextStyle(
                                            color: _lightOffWhite,
                                            fontWeight: FontWeight.w500,
                                            fontSize: 12,
                                          ),
                                          overflow: TextOverflow.ellipsis,
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
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Status Filter
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _primaryAqua.withValues(alpha: 0.2),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: const Color(0xFFF7FAFD),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.flag_outlined, color: _primaryAqua, size: 12),
                      const SizedBox(width: 6),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _statusFilter,
                          dropdownColor: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          isDense: true,
                          iconSize: 18,
                          style: const TextStyle(
                            color: _lightOffWhite,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          iconEnabledColor: _primaryAqua,
                          items: const [
                            DropdownMenuItem(
                              value: 'All',
                              child: Text('All Status'),
                            ),
                            DropdownMenuItem(
                              value: 'Pending',
                              child: Text('Pending'),
                            ),
                            DropdownMenuItem(
                              value: 'Completed',
                              child: Text('Completed'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _statusFilter = value;
                              _currentPage = 1;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),

                // Clear Filter Button
                if (_fromDate != null ||
                    _toDate != null ||
                    _statusFilter != 'All' ||
                    _effectiveSearchQuery.isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: _primaryAqua,
                      ),
                      iconSize: 18,
                      onPressed: () {
                        setState(() {
                          _fromDate = null;
                          _toDate = null;
                          _statusFilter = 'All';
                          _effectiveSearchController.clear();
                          _searchQuery = '';
                          _currentPage = 1;
                        });
                      },
                      tooltip: 'Clear filters',
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
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

class _CheckUpDashboardHeader extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final monthlyTrend = _buildMonthlyTrend();
    final categoryDistribution = _buildCategoryDistribution();
    final symptomDistribution = _buildSymptomDistribution();
    final ageDistribution = _buildAgeDistribution();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

  DateTime? _recordDate(Map<String, dynamic> record) {
    final raw = record['datetime'] ?? record['createdAt'] ?? record['date'];
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    try {
      final dynamic converted = raw.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      // The web cache commonly stores Firestore dates as strings.
    }
    return DateTime.tryParse(raw.toString().trim());
  }

  List<MapEntry<String, int>> _buildMonthlyTrend() {
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

  List<MapEntry<String, int>> _buildCategoryDistribution() {
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

  List<MapEntry<String, int>> _buildSymptomDistribution() {
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

  List<MapEntry<String, int>> _buildAgeDistribution() {
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

  const _CheckUpTable({
    required this.records,
    required this.startIndex,
    required this.isSelectionMode,
    required this.selectedIndices,
    required this.onSelectionChanged,
    required this.onEdit,
    required this.onViewHistory,
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
  if (vitalsString.isEmpty || vitalsString == 'N/A') {
    return Text(
      vitalsString,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10.5,
        fontWeight: FontWeight.w900,
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
            fontSize: 10.5,
            color: Color(0xFF60A5FA),
            fontWeight: FontWeight.w900,
          ),
        ),
      );

      // Add space and value
      textSpans.add(
        TextSpan(
          text: ' $vitalValue',
          style: const TextStyle(
            fontSize: 10.5,
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      );

      // Add separator if not last item
      if (i < parts.length - 1) {
        textSpans.add(
          TextSpan(
            text: ', ',
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        );
      }
    } else {
      textSpans.add(
        TextSpan(
          text: part,
          style: const TextStyle(
            fontSize: 10.5,
            color: Colors.white,
            fontWeight: FontWeight.w900,
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

  const _CheckUpCard({
    required this.record,
    required this.isSelectionMode,
    required this.isSelected,
    required this.index,
    required this.onSelectionChanged,
    required this.onEdit,
    required this.onViewHistory,
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
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF163B66),
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF163B66).withValues(alpha: 0.28),
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
  }

  @override
  Widget build(BuildContext context) {
    final patientName = _safe(record['patient'], 'Unknown');
    final age = _safe(record['age']);
    final gender = _safe(record['gender'], 'Patient');
    final recordId = _safe(record['id'], '-');
    final dateTime = _safe(record['datetime'], 'N/A');
    final dateLabel = dateTime.contains('T')
        ? dateTime.split('T').first
        : dateTime.split(' ').first;
    final symptoms = _safe(record['symptoms'], 'No symptoms recorded');
    final vitals = _safe(record['vitalsigns'], 'No vitals recorded');

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
                    const SizedBox(height: 2),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'Age: ',
                            style: const TextStyle(
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
                    const SizedBox(height: 4),
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
                    width: 112,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildActionButton(
                          icon: Icons.history_rounded,
                          onTap: () => onViewHistory(record),
                        ),
                        const SizedBox(width: 6),
                        _buildActionButton(
                          icon: Icons.edit_rounded,
                          onTap: () => onEdit(record),
                        ),
                        const SizedBox(width: 6),
                        _buildActionButton(
                          icon: Icons.picture_as_pdf_rounded,
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
    final isWeb = screenSize.width > 800;
    final isFollowUpVisit = widget.patientSeed != null;
    final modalTitle = isFollowUpVisit
        ? 'Add Another Check-Up'
        : 'New Check-Up Record';
    final modalSubtitle = isFollowUpVisit
        ? 'Continue care for the same patient while keeping previous check-up history visible.'
        : 'Assessment intake and follow-up planning';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Container(
        width: screenSize.width,
        height: screenSize.height,
        decoration: BoxDecoration(
          color: _sidebarDark,
          border: Border.all(
            color: _primaryAqua.withValues(alpha: 0.2),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Web Header Bar
            Container(
              height: 86,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_sidebarDark, _darkDeepTeal],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                border: Border(
                  bottom: BorderSide(
                    color: _primaryAqua.withValues(alpha: 0.28),
                    width: 1.2,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
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
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                        ),
                        Text(
                          modalSubtitle,
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.72),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _primaryAqua.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        hoverColor: _primaryAqua.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content Area
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isWeb ? 16 : 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Form sections
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // Patient Information Section
                          _buildSectionCard(
                            context: context,
                            title: 'Patient Information',
                            icon: Icons.person,
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _firstNameController,
                                        decoration: _buildInputDecoration(
                                          'First Name',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _surnameController,
                                        decoration: _buildInputDecoration(
                                          'Surname',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 1,
                                      child: TextFormField(
                                        controller: _ageController,
                                        decoration: _buildInputDecoration(
                                          'Age',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        keyboardType: TextInputType.number,
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: _addressController,
                                        decoration: _buildInputDecoration(
                                          'Address',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Vital Signs Section (Separated)
                          _buildSectionCard(
                            context: context,
                            title: 'Vital Signs',
                            icon: Icons.monitor_heart,
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _bloodPressureController,
                                        decoration: _buildInputDecoration(
                                          'Blood Pressure (e.g., 120/80)',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _temperatureController,
                                        decoration: _buildInputDecoration(
                                          'Temperature (°C)',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        keyboardType:
                                            TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _heartRateController,
                                        decoration: _buildInputDecoration(
                                          'Heart Rate (bpm)',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        keyboardType: TextInputType.number,
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _respiratoryRateController,
                                        decoration: _buildInputDecoration(
                                          'Respiratory Rate (brpm)',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        keyboardType: TextInputType.number,
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _oxygenSaturationController,
                                        decoration: _buildInputDecoration(
                                          'Oxygen Saturation (%)',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        keyboardType: TextInputType.number,
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _weightController,
                                        decoration: _buildInputDecoration(
                                          'Weight (kg)',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        keyboardType:
                                            TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _heightController,
                                  decoration: _buildInputDecoration(
                                    'Height (cm)',
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                  keyboardType: TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Clinical Details Section
                          _buildSectionCard(
                            context: context,
                            title: 'Clinical Details',
                            icon: Icons.medical_services,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _symptomsController,
                                  decoration: _buildInputDecoration(
                                    'Symptoms / Known Conditions',
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                  maxLines: 3,
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Required'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Follow-up Section
                          _buildSectionCard(
                            context: context,
                            title: 'Follow-up',
                            icon: Icons.schedule,
                            child: Column(
                              children: [
                                InkWell(
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate:
                                          _followUpDate ?? DateTime.now(),
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime.now().add(
                                        const Duration(days: 365),
                                      ),
                                      builder: (context, child) {
                                        return Theme(
                                          data: _buildDarkDatePickerTheme(
                                            context,
                                          ),
                                          child: child!,
                                        );
                                      },
                                    );
                                    if (picked != null) {
                                      setState(() {
                                        _followUpDate = picked;
                                      });
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: _buildInputDecoration(
                                      'Follow-up Date',
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.calendar_today,
                                          color: _primaryAqua,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            _followUpDate != null
                                                ? "${_followUpDate!.year}-${_followUpDate!.month.toString().padLeft(2, '0')}-${_followUpDate!.day.toString().padLeft(2, '0')}"
                                                : 'Tap to select date',
                                            style: TextStyle(
                                              color: _followUpDate != null
                                                  ? Colors.white
                                                  : _lightOffWhite.withValues(
                                                      alpha: 0.45,
                                                    ),
                                              fontWeight: FontWeight.w500,
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
                          const SizedBox(height: 16),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: _fieldSurface,
                                  foregroundColor: _lightOffWhite,
                                  side: BorderSide(
                                    color: _primaryAqua.withValues(alpha: 0.26),
                                    width: 1.2,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryAqua,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                    vertical: 12,
                                  ),
                                  elevation: 0,
                                ),
                                icon: _isSaving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : const Icon(Icons.check_circle),
                                label: Text(
                                  _isSaving ? 'Saving...' : 'Save Record',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                onPressed: _isSaving
                                    ? null
                                    : () async {
                                        print(
                                          '🔘 [CHECKUP MODAL] Save button pressed',
                                        );

                                        if (_formKey.currentState?.validate() ??
                                            false) {
                                          print(
                                            '✅ [CHECKUP MODAL] Form validation passed',
                                          );
                                          setState(() => _isSaving = true);
                                          print(
                                            '🔄 [CHECKUP MODAL] Loading state set to true',
                                          );

                                          try {
                                            print(
                                              '📋 [CHECKUP MODAL] Building vital signs string...',
                                            );
                                            // Combine all vital signs into one string
                                            List<String> vitalSignsParts = [];

                                            if (_bloodPressureController
                                                .text
                                                .isNotEmpty) {
                                              vitalSignsParts.add(
                                                'BP: ${_bloodPressureController.text}',
                                              );
                                            }
                                            if (_temperatureController
                                                .text
                                                .isNotEmpty) {
                                              vitalSignsParts.add(
                                                'Temp: ${_temperatureController.text}°C',
                                              );
                                            }
                                            if (_heartRateController
                                                .text
                                                .isNotEmpty) {
                                              vitalSignsParts.add(
                                                'HR: ${_heartRateController.text} bpm',
                                              );
                                            }
                                            if (_respiratoryRateController
                                                .text
                                                .isNotEmpty) {
                                              vitalSignsParts.add(
                                                'RR: ${_respiratoryRateController.text} brpm',
                                              );
                                            }
                                            if (_oxygenSaturationController
                                                .text
                                                .isNotEmpty) {
                                              vitalSignsParts.add(
                                                'O2: ${_oxygenSaturationController.text}%',
                                              );
                                            }
                                            if (_weightController
                                                .text
                                                .isNotEmpty) {
                                              vitalSignsParts.add(
                                                'Weight: ${_weightController.text} kg',
                                              );
                                            }
                                            if (_heightController
                                                .text
                                                .isNotEmpty) {
                                              vitalSignsParts.add(
                                                'Height: ${_heightController.text} cm',
                                              );
                                            }

                                            String vitalSignsString =
                                                vitalSignsParts.join(', ');

                                            print(
                                              '✅ [CHECKUP MODAL] Vital signs built: $vitalSignsString',
                                            );

                                            // Create new record
                                            print(
                                              '📝 [CHECKUP MODAL] Creating new record object...',
                                            );
                                            final now = DateTime.now();
                                            final linkedPatientId =
                                                widget
                                                    .patientSeed?['linkedPatientId']
                                                    ?.toString()
                                                    .trim() ??
                                                '';
                                            final patientId =
                                                widget.patientSeed?['patientId']
                                                    ?.toString()
                                                    .trim() ??
                                                '';
                                            final Map<String, dynamic>
                                            newRecord = {
                                              if (linkedPatientId.isNotEmpty)
                                                'linkedPatientId':
                                                    linkedPatientId,
                                              if (patientId.isNotEmpty)
                                                'patientId': patientId,
                                              'datetime':
                                                  '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                                              'status': 'Completed',
                                              'type': 'General',
                                              'diseaseType': _diseaseType,
                                              'patient':
                                                  '${_firstNameController.text} ${_surnameController.text}',
                                              'age': _ageController.text,
                                              'address':
                                                  _addressController.text,
                                              'vitalsigns': vitalSignsString,
                                              'symptoms':
                                                  _symptomsController.text,
                                              'details':
                                                  vitalSignsString.isNotEmpty
                                                  ? '$vitalSignsString | ${_symptomsController.text}'
                                                  : 'Age: ${_ageController.text}, ${_symptomsController.text}',
                                              'followup': _followUpDate != null
                                                  ? '${_followUpDate!.year}-${_followUpDate!.month.toString().padLeft(2, '0')}-${_followUpDate!.day.toString().padLeft(2, '0')}'
                                                  : 'N/A',
                                            };

                                            print(
                                              '✅ [CHECKUP MODAL] Record created for: ${newRecord['patient']}',
                                            );

                                            // AI Classification
                                            SymptomGuidanceResult?
                                            classification;
                                            try {
                                              print(
                                                '🤖 [AI] Starting classification...',
                                              );
                                              classification = await widget
                                                  .guidanceApi
                                                  .getGuidanceFromText(
                                                    _symptomsController.text,
                                                  );
                                              newRecord.addAll(
                                                classification.toRecordFields(),
                                              );

                                              print(
                                                '✅ [AI] Classification complete:',
                                              );
                                              print(
                                                '  Category: ${classification.category}',
                                              );
                                              print(
                                                '  Severity: ${classification.severity}',
                                              );
                                              print(
                                                '  Confidence: ${classification.confidence}',
                                              );

                                              newRecord['ai_category'] =
                                                  classification.category;
                                              newRecord['ai_severity'] =
                                                  classification.severity;
                                              newRecord['ai_confidence'] =
                                                  classification.confidence
                                                      .toString();
                                              newRecord['ai_method'] =
                                                  classification.method;
                                              if (classification.keywords !=
                                                  null) {
                                                newRecord['ai_keywords'] =
                                                    classification.keywords!
                                                        .join(', ');
                                              }
                                              if (classification.recoveryPlan !=
                                                  null) {
                                                newRecord['ai_recovery_plan'] =
                                                    jsonEncode(
                                                      classification
                                                          .recoveryPlan,
                                                    );
                                                print(
                                                  '✅ Recovery plan stored in record',
                                                );
                                              }
                                            } catch (e) {
                                              print(
                                                '❌ AI classification failed: $e',
                                              );
                                              newRecord.addAll(
                                                _localHealthCategoryFallback(
                                                  _symptomsController.text,
                                                ),
                                              );
                                            }

                                            print(
                                              '🚀 [CHECKUP MODAL] Calling parent onSave callback...',
                                            );

                                            // Call the callback to save the record
                                            await widget.onSave(newRecord);

                                            print(
                                              '✅ [CHECKUP MODAL] onSave callback completed successfully',
                                            );

                                            // Show AI Classification modal
                                            if (context.mounted &&
                                                classification != null) {
                                              setState(() => _isSaving = false);
                                              newRecord.remove('ai_confidence');
                                              await _showSymptomGuidanceModal(
                                                context,
                                                classification,
                                              );
                                            }

                                            if (context.mounted) {
                                              print(
                                                '🚪 [CHECKUP MODAL] Closing modal with disease type...',
                                              );
                                              Navigator.of(
                                                context,
                                              ).pop(_diseaseType);
                                              print(
                                                '✅ [CHECKUP MODAL] Modal closed',
                                              );
                                            }
                                          } catch (e, stackTrace) {
                                            print(
                                              '❌ [CHECKUP MODAL] Error caught: $e',
                                            );
                                            print(
                                              '📍 [CHECKUP MODAL] Stack trace: $stackTrace',
                                            );
                                            setState(() => _isSaving = false);

                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Error saving record: $e',
                                                  ),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            }
                                          }
                                        } else {
                                          print(
                                            '❌ [CHECKUP MODAL] Form validation failed',
                                          );
                                        }
                                      },
                              ),
                            ],
                          ),
                        ],
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
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  '• $item',
                  style: const TextStyle(color: _lightOffWhite, height: 1.35),
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
        backgroundColor: _darkDeepTeal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 780),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: const BoxDecoration(
                  color: _secondaryIceBlue,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.health_and_safety_outlined,
                      color: Colors.white,
                      size: 30,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'AI Symptom Guidance',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
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
                        style: const TextStyle(color: _lightOffWhite),
                      ),
                      if (result.recognizedConditions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Entered conditions (not AI predictions): '
                          '${result.recognizedConditions.join(', ')}',
                          style: const TextStyle(
                            color: Colors.lightBlueAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _primaryAqua.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _primaryAqua.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Suggested Health Category',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              result.suggestedHealthCategory,
                              style: const TextStyle(
                                color: _primaryAqua,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'Rule-based suggestion from explicitly entered conditions. Symptoms alone remain Needs Clinical Review.',
                              style: TextStyle(
                                color: Colors.white60,
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
                        Colors.green,
                        result.homeCare,
                      ),
                      section(
                        'Important Precautions',
                        Icons.warning_amber_rounded,
                        Colors.orange,
                        result.precautions,
                      ),
                      section(
                        'When to Seek Medical Care',
                        Icons.medical_services_outlined,
                        Colors.blue,
                        result.whenToSeekCare,
                      ),
                      section(
                        'Emergency Warning Signs',
                        Icons.emergency_outlined,
                        Colors.red,
                        result.emergencyWarningSigns,
                      ),
                      if (result.ignoredSymptoms.isNotEmpty)
                        section(
                          'Not Recognized',
                          Icons.help_outline,
                          Colors.orange,
                          result.ignoredSymptoms,
                        ),
                      const SizedBox(height: 18),
                      Text(
                        result.disclaimer,
                        style: TextStyle(
                          color: _lightOffWhite.withValues(alpha: 0.75),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.check),
                    label: const Text('Got It'),
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
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _primaryAqua.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.smart_toy_rounded,
                        color: _primaryAqua,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  // Helper method for input decoration
  InputDecoration _buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryAqua, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      filled: true,
      fillColor: _darkDeepTeal,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
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
    return Dialog.fullscreen(
      backgroundColor: _darkDeepTeal,
      child: Scaffold(
        backgroundColor: _darkDeepTeal,
        appBar: AppBar(
          backgroundColor: _sidebarDark,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            tooltip: 'Close editor',
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit Check-Up Record',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                'Update the patient check-up and clinical observations',
                style: TextStyle(fontSize: 12, color: Colors.white60),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryAqua,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // Content Area
            Expanded(
              child: SingleChildScrollView(
                // Dense editor spacing keeps every section easy to scan.
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Form sections
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // Patient Information Section
                          _buildSectionCard(
                            context: context,
                            title: 'Patient Information',
                            icon: Icons.person,
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _firstNameController,
                                        decoration: _buildInputDecoration(
                                          'First Name',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _surnameController,
                                        decoration: _buildInputDecoration(
                                          'Surname',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 1,
                                      child: TextFormField(
                                        controller: _ageController,
                                        decoration: _buildInputDecoration(
                                          'Age',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        keyboardType: TextInputType.number,
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: _addressController,
                                        decoration: _buildInputDecoration(
                                          'Address',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Vital Signs Section
                          _buildSectionCard(
                            context: context,
                            title: 'Vital Signs',
                            icon: Icons.monitor_heart,
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _bloodPressureController,
                                        decoration: _buildInputDecoration(
                                          'Blood Pressure (e.g., 120/80)',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _temperatureController,
                                        decoration: _buildInputDecoration(
                                          'Temperature (°C)',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        keyboardType:
                                            TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _heartRateController,
                                        decoration: _buildInputDecoration(
                                          'Heart Rate (bpm)',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        keyboardType: TextInputType.number,
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _respiratoryRateController,
                                        decoration: _buildInputDecoration(
                                          'Respiratory Rate (brpm)',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        keyboardType: TextInputType.number,
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _oxygenSaturationController,
                                        decoration: _buildInputDecoration(
                                          'Oxygen Saturation (%)',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        keyboardType: TextInputType.number,
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _weightController,
                                        decoration: _buildInputDecoration(
                                          'Weight (kg)',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        keyboardType:
                                            TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _heightController,
                                  decoration: _buildInputDecoration(
                                    'Height (cm)',
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                  keyboardType: TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Clinical Details Section
                          _buildSectionCard(
                            context: context,
                            title: 'Clinical Details',
                            icon: Icons.medical_services,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _symptomsController,
                                  decoration: _buildInputDecoration(
                                    'Symptoms / Complaints',
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                  maxLines: 3,
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Required'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Follow-up Section
                          _buildSectionCard(
                            context: context,
                            title: 'Follow-up',
                            icon: Icons.schedule,
                            child: Column(
                              children: [
                                InkWell(
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate:
                                          _followUpDate ?? DateTime.now(),
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime.now().add(
                                        const Duration(days: 365),
                                      ),
                                      builder: (context, child) {
                                        return Theme(
                                          data: _buildDarkDatePickerTheme(
                                            context,
                                          ),
                                          child: child!,
                                        );
                                      },
                                    );
                                    if (picked != null) {
                                      setState(() {
                                        _followUpDate = picked;
                                      });
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: _buildInputDecoration(
                                      'Follow-up Date',
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.calendar_today,
                                          color: _primaryAqua,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            _followUpDate != null
                                                ? "${_followUpDate!.year}-${_followUpDate!.month.toString().padLeft(2, '0')}-${_followUpDate!.day.toString().padLeft(2, '0')}"
                                                : 'Tap to select date',
                                            style: TextStyle(
                                              color: _followUpDate != null
                                                  ? Colors.white
                                                  : Colors.white54,
                                              fontWeight: FontWeight.w500,
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
                          const SizedBox(height: 16),

                          Offstage(
                            offstage: true,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _primaryAqua,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 32,
                                      vertical: 12,
                                    ),
                                    elevation: 4,
                                  ),
                                  icon: const Icon(Icons.check_circle),
                                  label: const Text(
                                    'Update Record',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  onPressed: () async {
                                    if (_formKey.currentState!.validate()) {
                                      final patientName =
                                          '${_firstNameController.text} ${_surnameController.text}';

                                      // Build vital signs string
                                      List<String> vitalsList = [];
                                      if (_bloodPressureController
                                          .text
                                          .isNotEmpty) {
                                        vitalsList.add(
                                          'BP: ${_bloodPressureController.text}',
                                        );
                                      }
                                      if (_temperatureController
                                          .text
                                          .isNotEmpty) {
                                        vitalsList.add(
                                          'Temp: ${_temperatureController.text}°C',
                                        );
                                      }
                                      if (_heartRateController
                                          .text
                                          .isNotEmpty) {
                                        vitalsList.add(
                                          'HR: ${_heartRateController.text} bpm',
                                        );
                                      }
                                      if (_respiratoryRateController
                                          .text
                                          .isNotEmpty) {
                                        vitalsList.add(
                                          'RR: ${_respiratoryRateController.text} brpm',
                                        );
                                      }
                                      if (_oxygenSaturationController
                                          .text
                                          .isNotEmpty) {
                                        vitalsList.add(
                                          'O2: ${_oxygenSaturationController.text}%',
                                        );
                                      }
                                      if (_weightController.text.isNotEmpty) {
                                        vitalsList.add(
                                          'Weight: ${_weightController.text} kg',
                                        );
                                      }
                                      if (_heightController.text.isNotEmpty) {
                                        vitalsList.add(
                                          'Height: ${_heightController.text} cm',
                                        );
                                      }

                                      final vitalSigns = vitalsList.join(', ');

                                      final updatedRecord = {
                                        'id': widget
                                            .record['id'], // Keep the original ID
                                        'patient': patientName,
                                        'age': _ageController.text,
                                        'address': _addressController.text,
                                        'type': 'General',
                                        'datetime': widget
                                            .record['datetime'], // Keep original datetime
                                        'vitalsigns': vitalSigns,
                                        'symptoms': _symptomsController.text,
                                        'followup': _followUpDate != null
                                            ? '${_followUpDate!.year}-${_followUpDate!.month.toString().padLeft(2, '0')}-${_followUpDate!.day.toString().padLeft(2, '0')}'
                                            : 'N/A',
                                      };

                                      // AI Classification on edited record
                                      ClassificationResult? classification;
                                      try {
                                        print(
                                          '🤖 [AI] Starting classification on edited record...',
                                        );
                                        classification = await widget
                                            .aiClassifier
                                            .classify(updatedRecord);
                                        print(
                                          '✅ [AI] Classification complete: ${classification.category}',
                                        );

                                        updatedRecord['ai_category'] =
                                            classification.category;
                                        updatedRecord['ai_severity'] =
                                            classification.severity;
                                        updatedRecord['ai_confidence'] =
                                            classification.confidence
                                                .toString();
                                        updatedRecord['ai_method'] =
                                            classification.method;
                                        if (classification.keywords != null) {
                                          updatedRecord['ai_keywords'] =
                                              classification.keywords!.join(
                                                ', ',
                                              );
                                        }
                                        if (classification.recoveryPlan !=
                                            null) {
                                          updatedRecord['ai_recovery_plan'] =
                                              jsonEncode(
                                                classification.recoveryPlan,
                                              );
                                        }
                                      } catch (e) {
                                        print(
                                          '❌ AI classification failed on edit: $e',
                                        );
                                      }

                                      final recordId =
                                          updatedRecord['id']?.toString() ?? '';
                                      await widget.onSave(
                                        recordId,
                                        updatedRecord,
                                      );

                                      // Show AI Classification modal with loading spinner
                                      if (context.mounted &&
                                          classification != null) {
                                        await _showEditAIClassificationModal(
                                          context,
                                          classification,
                                        );
                                      }

                                      if (context.mounted) {
                                        Navigator.pop(context);
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
                  ],
                ),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _primaryAqua, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryAqua, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: _primaryAqua.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryAqua, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      filled: true,
      fillColor: const Color(0xFF0B1F3A),
      hintStyle: const TextStyle(color: Colors.white54),
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
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _primaryAqua.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.smart_toy_rounded,
                        color: _primaryAqua,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
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
