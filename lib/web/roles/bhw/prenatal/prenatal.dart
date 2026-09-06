import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal_database_helper.dart';
import 'package:mycapstone_project/app/core/services/health_ai_classifier.dart';
import 'package:mycapstone_project/app/core/services/health_screening_engine.dart';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mycapstone_project/web/roles/bhw/dashboard/homepage.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/shared/components/app_metric_card.dart';
import 'package:mycapstone_project/web/shared/components/fullscreen_detail_table_dialog.dart';
import 'package:mycapstone_project/web/shared/components/module_view_components.dart';
import 'package:mycapstone_project/web/shared/components/web_responsive_body.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/shared/utils/file_download.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_first_service_selector.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_identity_utils.dart';
import 'package:mycapstone_project/web/shared/utils/prenatal_pdf.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/shared_patient_search_panel.dart';
import 'package:mycapstone_project/shared/current_table_record_utils.dart';
import 'package:mycapstone_project/web/shared/widgets/web_sync_status_badge.dart';
import 'dart:math' as math;

const Color _primaryAqua = Color(0xFF2F80ED);
const Color _secondaryIceBlue = Color(0xFF163B66);
const Color _darkDeepTeal = Color(0xFF071A33);
const Color _mutedCoolGray = Color(0xFF4B6075);
const Color _lightOffWhite = Color(0xFF0B1F3A);
const Color _sidebarDark = Colors.white;

class PrenatalPage extends StatefulWidget {
  const PrenatalPage({super.key, this.initialPatient});

  final Map<String, dynamic>? initialPatient;

  @override
  State<PrenatalPage> createState() => _PrenatalPageState();
}

class _PrenatalPageState extends State<PrenatalPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  static const List<String> _prenatalRiskLevelOptions = [
    'Active',
    'Follow Up',
    'High Risk',
    'Completed',
  ];

  String _selectedStatusFilter = 'All Cases';
  String _selectedBarangay = 'All';
  String _selectedRiskLevel = 'All';
  String _selectedAgeGroup = 'All';
  String _sortField = 'Name';
  bool _sortAscending = true;
  final List<String> _statusFilterOptions = [
    'All Cases',
    'Active',
    'High Risk',
    'Follow Up',
    'Completed',
  ];

  DateTime? _fromDate;
  DateTime? _toDate;

  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};
  bool _isLoading = true;
  int _currentPage = 1;
  int _rowsPerPage = 10;

  // Search state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _sharedPatientMatches = [];
  bool _isSearchingSharedPatients = false;
  Timer? _sharedPatientSearchDebounce;
  late HealthModuleView _activeView;

  // Database-backed prenatal records
  List<Map<String, dynamic>> _prenatalRecords = [];
  final PrenatalDatabaseHelper _dbHelper = PrenatalDatabaseHelper.instance;

  // Insights Date Filter State
  DashboardDateFilterMode _insightsDateFilterMode =
      DashboardDateFilterMode.allTime;
  DateTime? _insightsCustomDate;
  DateTime? _insightsSelectedMonth;
  DateTime _insightsRangeStart = DateTime.now().subtract(
    const Duration(days: 6),
  );
  DateTime _insightsRangeEnd = DateTime.now();

  // AI Classifier
  final HealthAIClassifier _aiClassifier = HealthAIClassifier.instance;
  final PatientCenteredHistoryService _patientHistoryService =
      PatientCenteredHistoryService();

  @override
  void initState() {
    super.initState();
    _insightsSelectedMonth ??= DateTime.now();
    _insightsRangeStart = DateTime.now().subtract(const Duration(days: 6));
    _insightsRangeEnd = DateTime.now();
    _activeView = healthModuleViewFromUrl();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => persistHealthModuleView(WebRoutes.bhwPrenatal, _activeView),
    );
    _loadRecords();
    _dbHelper.startConnectivityListener();
    _initializeAI();
    if (widget.initialPatient != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showNewPrenatalModal(context, patientSeed: widget.initialPatient);
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
    persistHealthModuleView(WebRoutes.bhwPrenatal, view);
  }

  Future<void> _initializeAI() async {
    await _aiClassifier.initialize();
  }

  @override
  void dispose() {
    _sharedPatientSearchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);

    // Load from local database
    // Try to sync from Firebase
    await _dbHelper.syncFromFirebase();

    // Reload after sync
    final updatedRecords = await _dbHelper.getAllRecords();

    setState(() {
      _prenatalRecords = updatedRecords;
      _isLoading = false;
    });
  }

  String _normalizePrenatalRiskLevel(dynamic rawValue) {
    final text = rawValue?.toString().trim() ?? '';
    if (text.isEmpty) {
      return _prenatalRiskLevelOptions.first;
    }

    final normalized = text.toLowerCase();
    switch (normalized) {
      case 'active':
      case 'pending':
      case 'process':
      case 'processing':
      case 'ongoing':
      case 'under observation':
        return 'Active';
      case 'follow up':
      case 'follow-up':
      case 'followup':
      case 'monitoring':
        return 'Follow Up';
      case 'high risk':
      case 'high-risk':
      case 'highrisk':
      case 'critical':
        return 'High Risk';
      case 'completed':
      case 'complete':
      case 'closed':
      case 'delivered':
        return 'Completed';
      default:
        for (final option in _prenatalRiskLevelOptions) {
          if (option.toLowerCase() == normalized) {
            return option;
          }
        }
        return _prenatalRiskLevelOptions.first;
    }
  }

  List<String> _uniqueDropdownItems(List<String> items) {
    final uniqueItems = <String>[];
    final seen = <String>{};

    for (final rawItem in items) {
      final item = rawItem.trim();
      if (item.isEmpty) {
        continue;
      }
      if (seen.add(item)) {
        uniqueItems.add(item);
      }
    }

    return uniqueItems;
  }

  String? _resolveDropdownValue(String value, List<String> items) {
    if (items.isEmpty) {
      return null;
    }

    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      return items.first;
    }

    for (final item in items) {
      if (item == trimmedValue) {
        return item;
      }
    }

    for (final item in items) {
      if (item.toLowerCase() == trimmedValue.toLowerCase()) {
        return item;
      }
    }

    return items.first;
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
            _searchQuery.trim().toLowerCase() !=
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.email?.split('@')[0] ?? 'User';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F7FA),
      body: WebResponsiveBody(
        sidebar: WebAppSidebar(
          userName: userName,
          activeItem: WebSidebarItem.prenatalCare,
        ),
        title: 'Prenatal Care',
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: _primaryAqua),
              )
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
                          title: 'Prenatal Care',
                          description:
                              'Monitor maternal-care coverage and risk indicators, or manage prenatal records.',
                          activeView: _activeView,
                          onViewChanged: _setActiveView,
                          primaryColor: _primaryAqua,
                        ),
                        const SizedBox(height: 16),
                        // Statistics Dashboard
                        if (_activeView == HealthModuleView.insights) ...[
                          if (_prenatalRecords.isEmpty)
                            const ModuleEmptyState(
                              title: 'No prenatal insights yet',
                              message:
                                  'Add a prenatal record to begin monitoring maternal-care coverage and risk indicators.',
                              icon: Icons.pregnant_woman_rounded,
                            )
                          else
                            _buildStatisticsDashboard(),
                          const SizedBox(height: 16),
                        ],

                        // Prenatal Records Table with integrated filters
                        if (_activeView == HealthModuleView.records)
                          _buildPrenatalTable(),
                        const SizedBox(
                          height: 80,
                        ), // Space for floating action card
                      ],
                    ),
                  ),
                  if (_activeView == HealthModuleView.records)
                    _buildSelectionActionCard(),
                ],
              ),
      ),
    );
  }

  // Drawer Navigation Widget

  List<Map<String, dynamic>> _getFilteredRecords() {
    final filtered = _prenatalRecords.where((record) {
      // Status filter
      if (_selectedStatusFilter != 'All Cases' &&
          _selectedStatusFilter != 'All') {
        final status = (record['status'] ?? '').toString().trim().toLowerCase();
        if (status != _selectedStatusFilter.toLowerCase()) {
          return false;
        }
      }

      // Barangay filter
      if (_selectedBarangay != 'All') {
        final barangay = (record['address'] ?? record['barangay'] ?? '')
            .toString()
            .toLowerCase();
        if (!barangay.contains(_selectedBarangay.toLowerCase())) {
          return false;
        }
      }

      // Risk Level filter
      if (_selectedRiskLevel != 'All') {
        final risk = (record['riskLevel'] ?? record['risk'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (risk != _selectedRiskLevel.toLowerCase()) {
          return false;
        }
      }

      // Age Group filter
      if (_selectedAgeGroup != 'All') {
        final age = int.tryParse(record['age']?.toString() ?? '') ?? -1;
        if (age >= 0) {
          switch (_selectedAgeGroup) {
            case '0–17':
              if (age > 17) return false;
              break;
            case '18–34':
              if (age < 18 || age > 34) return false;
              break;
            case '35+':
              if (age < 35) return false;
              break;
          }
        }
      }

      // Date range filter
      if (_fromDate != null || _toDate != null) {
        try {
          final rawDate =
              record['registrationDate'] ??
              record['dueDate'] ??
              record['date'] ??
              record['createdAt'];
          final parsedDate = DateTime.tryParse(
            rawDate?.toString().split(' ')[0] ?? '',
          );
          if (parsedDate != null) {
            if (_fromDate != null && parsedDate.isBefore(_fromDate!)) {
              return false;
            }
            if (_toDate != null && parsedDate.isAfter(_toDate!)) {
              return false;
            }
          }
        } catch (e) {
          // continue
        }
      }

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final name =
            (record['patientName'] ??
                    '${record['firstName'] ?? ''} ${record['surname'] ?? ''}')
                .toString()
                .toLowerCase();
        final id = (record['patientId'] ?? record['id'] ?? '')
            .toString()
            .toLowerCase();
        final age = (record['age'] ?? '').toString().toLowerCase();
        final contact = (record['contactNumber'] ?? '')
            .toString()
            .toLowerCase();
        final address = (record['address'] ?? '').toString().toLowerCase();
        final risk = (record['riskLevel'] ?? '').toString().toLowerCase();
        if (!name.contains(query) &&
            !id.contains(query) &&
            !age.contains(query) &&
            !contact.contains(query) &&
            !address.contains(query) &&
            !risk.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();

    // Sort records based on _sortField and _sortAscending
    filtered.sort((a, b) {
      int comparison = 0;
      switch (_sortField) {
        case 'Registration Date':
          final aDate = (a['registrationDate'] ?? a['createdAt'] ?? '')
              .toString();
          final bDate = (b['registrationDate'] ?? b['createdAt'] ?? '')
              .toString();
          comparison = aDate.compareTo(bDate);
          break;
        case 'Due Date':
          final aDate = (a['dueDate'] ?? a['eddDate'] ?? '').toString();
          final bDate = (b['dueDate'] ?? b['eddDate'] ?? '').toString();
          comparison = aDate.compareTo(bDate);
          break;
        case 'Age':
          final aAge = int.tryParse(a['age']?.toString() ?? '') ?? 0;
          final bAge = int.tryParse(b['age']?.toString() ?? '') ?? 0;
          comparison = aAge.compareTo(bAge);
          break;
        case 'Name':
        default:
          final aName =
              (a['patientName'] ??
                      '${a['firstName'] ?? ''} ${a['surname'] ?? ''}')
                  .toString()
                  .toLowerCase();
          final bName =
              (b['patientName'] ??
                      '${b['firstName'] ?? ''} ${b['surname'] ?? ''}')
                  .toString()
                  .toLowerCase();
          comparison = aName.compareTo(bName);
          break;
      }
      return _sortAscending ? comparison : -comparison;
    });

    return CurrentTableRecordUtils.collapseToLatestPerEntity(
      filtered,
      idKeys: const [
        'patientId',
        'linkedPatientId',
        'patientCode',
        'philhealthNumber',
      ],
      nameKeys: const ['patientName'],
      dateKeys: const ['registrationDate', 'dueDate', 'lmpDate'],
    );
  }

  // Show AI Classification results for a prenatal record. The classification
  // itself has already finished by the time this is called, so this opens
  // straight to the results — no artificial "Analyzing..." wait.
  Future<void> _showPrenatalAIModal(
    BuildContext context,
    ClassificationResult classification,
  ) async {
    final recoveryPlan = classification.recoveryPlan;

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
                            'AI Prenatal Analysis Complete',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Prenatal record analyzed successfully',
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
                            child: _prenatalAiInfoCard(
                              icon: Icons.category_rounded,
                              label: 'Category',
                              value: classification.category,
                              color: _prenatalGetCategoryColor(
                                classification.category,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _prenatalAiInfoCard(
                              icon: Icons.warning_amber_rounded,
                              label: 'Severity',
                              value: classification.severity,
                              color: _prenatalGetSeverityColor(
                                classification.severity,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _prenatalAiInfoCard(
                        icon: Icons.label_rounded,
                        label: 'Information used',
                        value: classification.keywords?.join(', ') ?? 'None',
                        color: Colors.orangeAccent,
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
                        if (recoveryPlan['home_care'] != null)
                          _prenatalRecoverySection(
                            icon: Icons.home_rounded,
                            title: 'Home Care',
                            items: List<String>.from(recoveryPlan['home_care']),
                            color: Colors.tealAccent,
                          ),
                        if (recoveryPlan['precautions'] != null)
                          _prenatalRecoverySection(
                            icon: Icons.shield_rounded,
                            title: 'Precautions',
                            items: List<String>.from(
                              recoveryPlan['precautions'],
                            ),
                            color: Colors.amberAccent,
                          ),
                        if (recoveryPlan['estimated_recovery'] != null)
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
                                    recoveryPlan['estimated_recovery']
                                        .toString(),
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
                        if (recoveryPlan['general_advice'] != null)
                          _prenatalRecoverySection(
                            icon: Icons.tips_and_updates_rounded,
                            title: 'General Advice',
                            items: List<String>.from(
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

  Widget _prenatalAiInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
            value,
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

  Widget _prenatalRecoverySection({
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
          border: Border.all(color: color.withValues(alpha: 0.2)),
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

  Color _prenatalGetCategoryColor(String category) {
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

  Color _prenatalGetSeverityColor(String severity) {
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

  Future<void> _showNewPrenatalModal(
    BuildContext context, {
    Map<String, dynamic>? patientSeed,
  }) async {
    patientSeed = await _patientHistoryService.resolveRegisteredPatient(
      patientSeed,
    );
    if (!context.mounted) return;
    if (patientSeed == null) {
      patientSeed = await PatientFirstServiceSelector.selectRegisteredPatient(
        context,
        serviceLabel: 'Prenatal',
        patientService: _patientHistoryService,
        onRegisterPatient: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const PatientRecordPage(openRegistrationOnLoad: true),
          ),
        ),
      );
      if (!context.mounted || patientSeed == null) return;
    }
    // Text editing controllers
    final firstNameController = TextEditingController();
    final surnameController = TextEditingController();
    final ageController = TextEditingController();
    final addressController = TextEditingController();
    final patientIdController = TextEditingController();
    final contactNumberController = TextEditingController();
    final civilStatusController = TextEditingController();
    final philhealthNumberController = TextEditingController();
    final philhealthMemberController = TextEditingController();
    final religionController = TextEditingController();

    DateTime? lmpDate;
    DateTime? eddDate;
    DateTime? lastDeliveryDate;
    DateTime? registrationDate = DateTime.now();
    bool isSaving = false;

    final gravidaController = TextEditingController();
    final paraController = TextEditingController();
    String selectedRiskLevel = 'Active';

    final bloodTypeController = TextEditingController();
    final allergiesController = TextEditingController();
    final preExistingConditionsController = TextEditingController();
    final previousComplicationsController = TextEditingController();

    // Medical measurements controllers
    final aogController = TextEditingController(); // Age of Gestation
    final wtController = TextEditingController(); // Weight
    final atController = TextEditingController(); // Abdominal Tenderness
    final tempController = TextEditingController(); // Temperature
    final bpController = TextEditingController(); // Blood Pressure
    final bmiController = TextEditingController(); // Body Mass Index
    final fhController = TextEditingController(); // Fundal Height
    final dhbController = TextEditingController(); // Fetal Heart Beat
    final tcbController = TextEditingController(); // Total Bilirubin

    final registeredByController = TextEditingController();
    final additionalNoteController = TextEditingController();

    // Gates the Save action so a patient record cannot be registered blank.
    final formKey = GlobalKey<FormState>();

    String? requiredValidator(String? value) {
      return (value == null || value.trim().isEmpty) ? 'Required' : null;
    }

    String? ageValidator(String? value) {
      if (value == null || value.trim().isEmpty) {
        return 'Required';
      }
      final age = int.tryParse(value.trim());
      if (age == null || age < 0 || age > 130) {
        return 'Enter a valid age (0-130)';
      }
      return null;
    }

    final modalTitle = 'Add Another Prenatal Visit';

    final name = patientNameParts(patientSeed);
    firstNameController.text = name.firstName;
    surnameController.text = name.surname;
    ageController.text = (patientSeed['age'] ?? '').toString();
    addressController.text = (patientSeed['address'] ?? '').toString();
    patientIdController.text = (patientSeed['patientId'] ?? '').toString();
    contactNumberController.text = (patientSeed['contactNumber'] ?? '')
        .toString();
    civilStatusController.text = (patientSeed['civilStatus'] ?? '').toString();
    philhealthNumberController.text = (patientSeed['philhealthNumber'] ?? '')
        .toString();
    philhealthMemberController.text = (patientSeed['philhealthMember'] ?? '')
        .toString();
    religionController.text = (patientSeed['religion'] ?? '').toString();
    gravidaController.text = (patientSeed['gravida'] ?? '').toString();
    paraController.text = (patientSeed['para'] ?? '').toString();
    selectedRiskLevel = _normalizePrenatalRiskLevel(
      patientSeed['riskLevel'] ?? patientSeed['status'] ?? 'Active',
    );
    bloodTypeController.text = (patientSeed['bloodType'] ?? '').toString();
    allergiesController.text = (patientSeed['allergies'] ?? '').toString();
    preExistingConditionsController.text =
        (patientSeed['preExistingConditions'] ?? '').toString();
    previousComplicationsController.text =
        (patientSeed['previousComplications'] ?? '').toString();
    aogController.text =
        (patientSeed['gestationalAge'] ?? patientSeed['aog'] ?? '').toString();
    wtController.text = (patientSeed['weight'] ?? patientSeed['wt'] ?? '')
        .toString();
    atController.text =
        (patientSeed['abdominalTenderness'] ?? patientSeed['at'] ?? '')
            .toString();
    tempController.text =
        (patientSeed['temperature'] ?? patientSeed['temp'] ?? '').toString();
    bpController.text =
        (patientSeed['bloodPressure'] ?? patientSeed['bp'] ?? '').toString();
    bmiController.text = (patientSeed['bmi'] ?? '').toString();
    fhController.text = (patientSeed['fundalHeight'] ?? patientSeed['fh'] ?? '')
        .toString();
    dhbController.text =
        (patientSeed['fetalHeartBeat'] ?? patientSeed['dhb'] ?? '').toString();
    tcbController.text = (patientSeed['tcb'] ?? '').toString();
    registeredByController.text = (patientSeed['registeredBy'] ?? '')
        .toString();
    additionalNoteController.text =
        (patientSeed['additionalNotes'] ?? patientSeed['additionalNote'] ?? '')
            .toString();
    lmpDate = _parseDate(patientSeed['lmpDate']);
    eddDate = _parseDate(patientSeed['eddDate'] ?? patientSeed['dueDate']);
    lastDeliveryDate = _parseDate(patientSeed['lastDeliveryDate']);
    registrationDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            color: const Color(0xFFF5F7FA),
            child: Column(
              children: [
                // Modal Header Bar
                Container(
                  height: 76,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    color: _darkDeepTeal,
                    border: Border(
                      bottom: BorderSide(color: Color(0x20FFFFFF), width: 1),
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
                            const Text(
                              'Maternal assessment and prenatal care planning',
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
                        onPressed: () => Navigator.pop(context),
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
                // Form Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    child: Form(
                      key: formKey,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 900;

                          final patientInfoSection = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (patientSeed != null)
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
                                          'Linked to registered patient record (${firstNameController.text} ${surnameController.text})',
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
                              _buildSectionHeader(
                                'Patient Information',
                                Icons.person,
                              ),
                              _buildDarkFormCard([
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: firstNameController,
                                        label: 'First Name',
                                        icon: Icons.person_outline,
                                        hintText: 'Enter first name',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: surnameController,
                                        label: 'Surname',
                                        icon: Icons.person_outline,
                                        hintText: 'Enter surname',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: ageController,
                                        label: 'Age',
                                        icon: Icons.cake,
                                        hintText: 'Enter age',
                                        keyboardType: TextInputType.number,
                                        validator: ageValidator,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: patientIdController,
                                        label: 'Patient ID',
                                        icon: Icons.badge,
                                        hintText: 'e.g., PAT-2026-001',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: addressController,
                                  label: 'Address',
                                  icon: Icons.home,
                                  hintText: 'Enter complete address',
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: contactNumberController,
                                  label: 'Contact Number',
                                  icon: Icons.phone,
                                  hintText: 'e.g., +63 912 345 6789',
                                  keyboardType: TextInputType.phone,
                                  validator: requiredValidator,
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: civilStatusController,
                                        label: 'Civil Status',
                                        icon: Icons.favorite,
                                        hintText: 'e.g., Single, Married',
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: religionController,
                                        label: 'Religion',
                                        icon: Icons.church,
                                        hintText: 'Enter religion',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: philhealthNumberController,
                                        label: 'Philhealth Number',
                                        icon: Icons.medical_information,
                                        hintText: 'Enter Philhealth #',
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: philhealthMemberController,
                                        label: 'Philhealth Member',
                                        icon: Icons.card_membership,
                                        hintText: 'Member name',
                                      ),
                                    ),
                                  ],
                                ),
                              ]),
                            ],
                          );

                          final pregnancyDetailSection = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(
                                'Pregnancy Detail',
                                Icons.child_care,
                              ),
                              _buildDarkFormCard([
                                _buildDatePickerField(
                                  context: context,
                                  label: 'Last Menstrual Period (LMP)',
                                  date: lmpDate,
                                  icon: Icons.calendar_today,
                                  onTap: () async {
                                    final picked = await _showDatePickerModal(
                                      context,
                                    );
                                    if (picked != null) {
                                      setModalState(() => lmpDate = picked);
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildDatePickerField(
                                  context: context,
                                  label: 'Estimated Due Date (EDD)',
                                  date: eddDate,
                                  icon: Icons.event,
                                  onTap: () async {
                                    final picked = await _showDatePickerModal(
                                      context,
                                    );
                                    if (picked != null) {
                                      setModalState(() => eddDate = picked);
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildDatePickerField(
                                  context: context,
                                  label: 'Last Date of Delivery',
                                  date: lastDeliveryDate,
                                  icon: Icons.child_friendly,
                                  onTap: () async {
                                    final picked = await _showDatePickerModal(
                                      context,
                                    );
                                    if (picked != null) {
                                      setModalState(
                                        () => lastDeliveryDate = picked,
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: gravidaController,
                                        label: 'Gravida (Number of Pregnancy)',
                                        icon: Icons.numbers,
                                        hintText: 'e.g., 1, 2, 3',
                                        keyboardType: TextInputType.number,
                                        validator: requiredValidator,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: paraController,
                                        label: 'Para (Number of Live Births)',
                                        icon: Icons.numbers,
                                        hintText: 'e.g., 0, 1, 2',
                                        keyboardType: TextInputType.number,
                                        validator: requiredValidator,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildDropdownField(
                                  label: 'Risk Level',
                                  value: selectedRiskLevel,
                                  icon: Icons.warning_amber,
                                  items: _prenatalRiskLevelOptions,
                                  onChanged: (value) {
                                    if (value != null) {
                                      setModalState(
                                        () => selectedRiskLevel = value,
                                      );
                                    }
                                  },
                                ),
                              ]),
                            ],
                          );

                          final medicalHistorySection = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(
                                'Medical History & Vitals',
                                Icons.medical_services,
                              ),
                              _buildDarkFormCard([
                                _buildTextField(
                                  controller: bloodTypeController,
                                  label: 'Blood Type',
                                  icon: Icons.bloodtype,
                                  hintText: 'e.g., A+, B-, O+, AB+',
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: allergiesController,
                                  label: 'Allergies',
                                  icon: Icons.health_and_safety,
                                  hintText: 'List any known allergies',
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: preExistingConditionsController,
                                  label: 'Pre-existing Medical Conditions',
                                  icon: Icons.local_hospital,
                                  hintText:
                                      'e.g., Diabetes, Hypertension, Asthma',
                                  maxLines: 3,
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: previousComplicationsController,
                                  label: 'Previous Pregnancy Complications',
                                  icon: Icons.warning,
                                  hintText:
                                      'List any complications from previous pregnancies',
                                  maxLines: 3,
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: aogController,
                                        label: 'AOG (Age of Gestation)',
                                        icon: Icons.calendar_view_week,
                                        hintText: 'e.g., 28 weeks',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: wtController,
                                        label: 'WT (Weight)',
                                        icon: Icons.monitor_weight,
                                        hintText: 'e.g., 65 kg',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: tempController,
                                        label: 'TEMP (Temperature)',
                                        icon: Icons.thermostat,
                                        hintText: 'e.g., 36.5°C',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: bpController,
                                        label: 'BP (Blood Pressure)',
                                        icon: Icons.favorite,
                                        hintText: 'e.g., 120/80',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: bmiController,
                                        label: 'BMI (Body Mass Index)',
                                        icon: Icons.assessment,
                                        hintText: 'e.g., 22.5',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: fhController,
                                        label: 'FH (Fundal Height)',
                                        icon: Icons.straighten,
                                        hintText: 'e.g., 28 cm',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: dhbController,
                                        label: 'DHB (Fetal Heart Beat)',
                                        icon: Icons.favorite_border,
                                        hintText: 'e.g., 140 bpm',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: atController,
                                        label: 'AT (Abdominal Tenderness)',
                                        icon: Icons.touch_app,
                                        hintText: 'e.g., None, Mild',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: tcbController,
                                  label: 'TCB (Total Bilirubin)',
                                  icon: Icons.science,
                                  hintText: 'e.g., 0.8 mg/dL',
                                  validator: requiredValidator,
                                ),
                              ]),
                            ],
                          );

                          final registrationDetailsSection = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(
                                'Registration Details',
                                Icons.app_registration,
                              ),
                              _buildDarkFormCard([
                                _buildDatePickerField(
                                  context: context,
                                  label: 'Registration Date',
                                  date: registrationDate,
                                  icon: Icons.calendar_month,
                                  onTap: () async {
                                    final picked = await _showDatePickerModal(
                                      context,
                                    );
                                    if (picked != null) {
                                      setModalState(
                                        () => registrationDate = picked,
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: registeredByController,
                                  label: 'Registered By',
                                  icon: Icons.person_pin,
                                  hintText: 'Enter staff name or ID',
                                  validator: requiredValidator,
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: additionalNoteController,
                                  label: 'Additional Note',
                                  icon: Icons.note,
                                  hintText:
                                      'Enter any additional notes or remarks',
                                  maxLines: 4,
                                ),
                              ]),
                            ],
                          );

                          if (isWide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      patientInfoSection,
                                      const SizedBox(height: 16),
                                      pregnancyDetailSection,
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      medicalHistorySection,
                                      const SizedBox(height: 16),
                                      registrationDetailsSection,
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              patientInfoSection,
                              const SizedBox(height: 16),
                              pregnancyDetailSection,
                              const SizedBox(height: 16),
                              medicalHistorySection,
                              const SizedBox(height: 16),
                              registrationDetailsSection,
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                // Bottom Action Bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
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
                        onPressed: () => Navigator.pop(context),
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
                        icon: isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(Icons.check_circle_rounded, size: 18),
                        label: Text(
                          isSaving ? 'Saving...' : 'Register Prenatal Patient',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        onPressed: isSaving
                            ? null
                            : () async {
                                final isFormValid =
                                    formKey.currentState?.validate() ?? false;
                                final isLmpDateValid = lmpDate != null;
                                final isLmpDateNotFuture =
                                    lmpDate == null ||
                                    !lmpDate!.isAfter(DateTime.now());
                                if (!isLmpDateValid) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('LMP date is required'),
                                      backgroundColor: Colors.red,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                } else if (!isLmpDateNotFuture) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'LMP date cannot be in the future',
                                      ),
                                      backgroundColor: Colors.red,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                                if (!isFormValid ||
                                    !isLmpDateValid ||
                                    !isLmpDateNotFuture) {
                                  return;
                                }

                                setModalState(() => isSaving = true);

                                // Create new prenatal record
                                final Map<String, dynamic> newRecord = {
                                  'patientName':
                                      '${firstNameController.text} ${surnameController.text}',
                                  'age': ageController.text,
                                  'address': addressController.text,
                                  'patientId':
                                      (patientSeed?['patientId'] ??
                                              patientSeed?['id'] ??
                                              patientIdController.text)
                                          .toString(),
                                  'linkedPatientId':
                                      (patientSeed?['linkedPatientId'] ??
                                              patientSeed?['patientId'] ??
                                              patientSeed?['id'] ??
                                              '')
                                          .toString(),
                                  'contactNumber': contactNumberController.text,
                                  'civilStatus': civilStatusController.text,
                                  'religion': religionController.text,
                                  'philhealthNumber':
                                      philhealthNumberController.text,
                                  'philhealthMember':
                                      philhealthMemberController.text,
                                  'lmpDate': lmpDate?.toIso8601String() ?? '',
                                  'eddDate': eddDate?.toIso8601String() ?? '',
                                  'lastDeliveryDate':
                                      lastDeliveryDate?.toIso8601String() ?? '',
                                  'gravida': gravidaController.text,
                                  'para': paraController.text,
                                  'riskLevel': selectedRiskLevel,
                                  'bloodType': bloodTypeController.text,
                                  'allergies': allergiesController.text,
                                  'preExistingConditions':
                                      preExistingConditionsController.text,
                                  'previousComplications':
                                      previousComplicationsController.text,
                                  'aog': aogController.text,
                                  'wt': wtController.text,
                                  'at': atController.text,
                                  'temp': tempController.text,
                                  'bp': bpController.text,
                                  'bmi': bmiController.text,
                                  'fh': fhController.text,
                                  'dhb': dhbController.text,
                                  'tcb': tcbController.text,
                                  'registrationDate':
                                      registrationDate?.toIso8601String() ?? '',
                                  'registeredBy': registeredByController.text,
                                  'additionalNote':
                                      additionalNoteController.text,
                                  'gestationalAge': aogController.text,
                                  'dueDate': eddDate?.toIso8601String() ?? '',
                                  'status': selectedRiskLevel,
                                };

                                // AI Classification
                                ClassificationResult? classification;
                                try {
                                  classification = await _aiClassifier.classify(
                                    newRecord,
                                  );

                                  newRecord['ai_category'] =
                                      classification.category;
                                  newRecord['ai_severity'] =
                                      classification.severity;
                                  newRecord['ai_method'] =
                                      classification.method;
                                  if (classification.keywords != null) {
                                    newRecord['ai_keywords'] = classification
                                        .keywords!
                                        .join(', ');
                                  }
                                  if (classification.recoveryPlan != null) {
                                    newRecord['ai_recovery_plan'] = jsonEncode(
                                      classification.recoveryPlan,
                                    );
                                  }
                                } catch (e) {
                                  // ignore
                                }

                                newRecord.addAll(
                                  HealthScreeningEngine.attachToRecord(
                                    newRecord,
                                    HealthScreeningEngine.evaluate({
                                      ...newRecord,
                                      'pregnant': true,
                                    }),
                                  ),
                                );

                                // Save to database (offline + Firebase sync)
                                try {
                                  await _dbHelper.insertRecord(newRecord);

                                  // Reload records
                                  await _loadRecords();

                                  // Show AI Classification modal with loading spinner
                                  if (context.mounted &&
                                      classification != null) {
                                    await _showPrenatalAIModal(
                                      context,
                                      classification,
                                    );
                                  }

                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Prenatal registration saved successfully!',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        backgroundColor: Colors.green,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Failed to save prenatal record: $e',
                                        ),
                                        backgroundColor: Colors.red,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                  setModalState(() => isSaving = false);
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditPrenatalModal(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    // Parse existing data
    final patientName = record['patientName'] ?? '';
    final nameParts = patientName.split(' ');

    // Text editing controllers with existing data
    final firstNameController = TextEditingController(
      text: nameParts.isNotEmpty ? nameParts[0] : '',
    );
    final surnameController = TextEditingController(
      text: nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '',
    );
    final ageController = TextEditingController(
      text: record['age']?.toString() ?? '',
    );
    final addressController = TextEditingController(
      text: record['address']?.toString() ?? '',
    );
    final patientIdController = TextEditingController(
      text: record['patientId']?.toString() ?? '',
    );
    final contactNumberController = TextEditingController(
      text: record['contactNumber']?.toString() ?? '',
    );
    final civilStatusController = TextEditingController(
      text: record['civilStatus']?.toString() ?? '',
    );
    final philhealthNumberController = TextEditingController(
      text: record['philhealthNumber']?.toString() ?? '',
    );
    final philhealthMemberController = TextEditingController(
      text: record['philhealthMember']?.toString() ?? '',
    );
    final religionController = TextEditingController(
      text: record['religion']?.toString() ?? '',
    );

    DateTime? lmpDate = _parseDate(record['lmpDate']);
    DateTime? eddDate = _parseDate(record['eddDate']);
    DateTime? lastDeliveryDate = _parseDate(record['lastDeliveryDate']);
    DateTime? registrationDate =
        _parseDate(record['registrationDate']) ?? DateTime.now();

    final gravidaController = TextEditingController(
      text: record['gravida']?.toString() ?? '',
    );
    final paraController = TextEditingController(
      text: record['para']?.toString() ?? '',
    );
    String selectedRiskLevel = _normalizePrenatalRiskLevel(
      record['riskLevel']?.toString() ??
          record['status']?.toString() ??
          'Active',
    );

    final bloodTypeController = TextEditingController(
      text: record['bloodType']?.toString() ?? '',
    );
    final allergiesController = TextEditingController(
      text: record['allergies']?.toString() ?? '',
    );
    final preExistingConditionsController = TextEditingController(
      text: record['preExistingConditions']?.toString() ?? '',
    );
    final previousComplicationsController = TextEditingController(
      text: record['previousComplications']?.toString() ?? '',
    );

    // Medical measurements controllers
    final aogController = TextEditingController(
      text: record['aog']?.toString() ?? '',
    );
    final wtController = TextEditingController(
      text: record['wt']?.toString() ?? '',
    );
    final atController = TextEditingController(
      text: record['at']?.toString() ?? '',
    );
    final tempController = TextEditingController(
      text: record['temp']?.toString() ?? '',
    );
    final bpController = TextEditingController(
      text: record['bp']?.toString() ?? '',
    );
    final bmiController = TextEditingController(
      text: record['bmi']?.toString() ?? '',
    );
    final fhController = TextEditingController(
      text: record['fh']?.toString() ?? '',
    );
    final dhbController = TextEditingController(
      text: record['dhb']?.toString() ?? '',
    );
    final tcbController = TextEditingController(
      text: record['tcb']?.toString() ?? '',
    );

    final registeredByController = TextEditingController(
      text: record['registeredBy']?.toString() ?? '',
    );
    final additionalNoteController = TextEditingController(
      text: record['additionalNote']?.toString() ?? '',
    );
    final updateButtonKey = GlobalKey();

    // Gates the Save action so an update cannot be submitted blank.
    final formKey = GlobalKey<FormState>();

    String? requiredValidator(String? value) {
      return (value == null || value.trim().isEmpty) ? 'Required' : null;
    }

    String? ageValidator(String? value) {
      if (value == null || value.trim().isEmpty) {
        return 'Required';
      }
      final age = int.tryParse(value.trim());
      if (age == null || age < 0 || age > 130) {
        return 'Enter a valid age (0-130)';
      }
      return null;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            color: const Color(0xFFF5F7FA),
            child: Column(
              children: [
                // Modal Header Bar
                Container(
                  height: 76,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    color: _darkDeepTeal,
                    border: Border(
                      bottom: BorderSide(color: Color(0x20FFFFFF), width: 1),
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
                              'Edit Prenatal Record',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Update maternal information and clinical measurements',
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
                        onPressed: () => Navigator.pop(context),
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
                // Form Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    child: Form(
                      key: formKey,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 900;

                          final patientInfoSection = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeaderDark(
                                'Patient Information',
                                Icons.person,
                              ),
                              _buildDarkFormCard([
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: firstNameController,
                                        label: 'First Name',
                                        icon: Icons.person_outline,
                                        hintText: 'Enter first name',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: surnameController,
                                        label: 'Surname',
                                        icon: Icons.person_outline,
                                        hintText: 'Enter surname',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: ageController,
                                        label: 'Age',
                                        icon: Icons.cake,
                                        hintText: 'Enter age',
                                        keyboardType: TextInputType.number,
                                        validator: ageValidator,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: patientIdController,
                                        label: 'Patient ID',
                                        icon: Icons.badge,
                                        hintText: 'e.g., PAT-2026-001',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: addressController,
                                  label: 'Address',
                                  icon: Icons.home,
                                  hintText: 'Enter complete address',
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: contactNumberController,
                                  label: 'Contact Number',
                                  icon: Icons.phone,
                                  hintText: 'e.g., +63 912 345 6789',
                                  keyboardType: TextInputType.phone,
                                  validator: requiredValidator,
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: civilStatusController,
                                        label: 'Civil Status',
                                        icon: Icons.favorite,
                                        hintText: 'e.g., Single, Married',
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: religionController,
                                        label: 'Religion',
                                        icon: Icons.church,
                                        hintText: 'Enter religion',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: philhealthNumberController,
                                        label: 'Philhealth Number',
                                        icon: Icons.medical_information,
                                        hintText: 'Enter Philhealth #',
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: philhealthMemberController,
                                        label: 'Philhealth Member',
                                        icon: Icons.card_membership,
                                        hintText: 'Member name',
                                      ),
                                    ),
                                  ],
                                ),
                              ]),
                            ],
                          );

                          final pregnancyDetailSection = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeaderDark(
                                'Pregnancy Detail',
                                Icons.child_care,
                              ),
                              _buildDarkFormCard([
                                _buildDatePickerField(
                                  context: context,
                                  label: 'Last Menstrual Period (LMP)',
                                  date: lmpDate,
                                  icon: Icons.calendar_today,
                                  onTap: () async {
                                    final picked = await _showDatePickerModal(
                                      context,
                                    );
                                    if (picked != null) {
                                      setModalState(() => lmpDate = picked);
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildDatePickerField(
                                  context: context,
                                  label: 'Estimated Due Date (EDD)',
                                  date: eddDate,
                                  icon: Icons.event,
                                  onTap: () async {
                                    final picked = await _showDatePickerModal(
                                      context,
                                    );
                                    if (picked != null) {
                                      setModalState(() => eddDate = picked);
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildDatePickerField(
                                  context: context,
                                  label: 'Last Date of Delivery',
                                  date: lastDeliveryDate,
                                  icon: Icons.child_friendly,
                                  onTap: () async {
                                    final picked = await _showDatePickerModal(
                                      context,
                                    );
                                    if (picked != null) {
                                      setModalState(
                                        () => lastDeliveryDate = picked,
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: gravidaController,
                                        label: 'Gravida (Number of Pregnancy)',
                                        icon: Icons.numbers,
                                        hintText: 'e.g., 1, 2, 3',
                                        keyboardType: TextInputType.number,
                                        validator: requiredValidator,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: paraController,
                                        label: 'Para (Number of Live Births)',
                                        icon: Icons.numbers,
                                        hintText: 'e.g., 0, 1, 2',
                                        keyboardType: TextInputType.number,
                                        validator: requiredValidator,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildDropdownField(
                                  label: 'Risk Level',
                                  value: selectedRiskLevel,
                                  icon: Icons.warning_amber,
                                  items: _prenatalRiskLevelOptions,
                                  onChanged: (value) {
                                    if (value != null) {
                                      setModalState(
                                        () => selectedRiskLevel = value,
                                      );
                                    }
                                  },
                                ),
                              ]),
                            ],
                          );

                          final medicalHistorySection = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeaderDark(
                                'Medical History',
                                Icons.medical_services,
                              ),
                              _buildDarkFormCard([
                                _buildTextField(
                                  controller: bloodTypeController,
                                  label: 'Blood Type',
                                  icon: Icons.bloodtype,
                                  hintText: 'e.g., A+, B-, O+, AB+',
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: allergiesController,
                                  label: 'Allergies',
                                  icon: Icons.health_and_safety,
                                  hintText: 'List any known allergies',
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: preExistingConditionsController,
                                  label: 'Pre-existing Medical Conditions',
                                  icon: Icons.local_hospital,
                                  hintText:
                                      'e.g., Diabetes, Hypertension, Asthma',
                                  maxLines: 3,
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: previousComplicationsController,
                                  label: 'Previous Pregnancy Complications',
                                  icon: Icons.warning,
                                  hintText:
                                      'List any complications from previous pregnancies',
                                  maxLines: 3,
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: aogController,
                                        label: 'AOG (Age of Gestation)',
                                        icon: Icons.calendar_view_week,
                                        hintText: 'e.g., 28 weeks',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: wtController,
                                        label: 'WT (Weight)',
                                        icon: Icons.monitor_weight,
                                        hintText: 'e.g., 65 kg',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: tempController,
                                        label: 'TEMP (Temperature)',
                                        icon: Icons.thermostat,
                                        hintText: 'e.g., 36.5°C',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: bpController,
                                        label: 'BP (Blood Pressure)',
                                        icon: Icons.favorite,
                                        hintText: 'e.g., 120/80',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: bmiController,
                                        label: 'BMI (Body Mass Index)',
                                        icon: Icons.assessment,
                                        hintText: 'e.g., 22.5',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: fhController,
                                        label: 'FH (Fundal Height)',
                                        icon: Icons.straighten,
                                        hintText: 'e.g., 28 cm',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: dhbController,
                                        label: 'DHB (Fetal Heart Beat)',
                                        icon: Icons.favorite_border,
                                        hintText: 'e.g., 140 bpm',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: atController,
                                        label: 'AT (Abdominal Tenderness)',
                                        icon: Icons.touch_app,
                                        hintText: 'e.g., None, Mild',
                                        validator: requiredValidator,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: tcbController,
                                  label: 'TCB (Total Bilirubin)',
                                  icon: Icons.science,
                                  hintText: 'e.g., 0.8 mg/dL',
                                  validator: requiredValidator,
                                ),
                              ]),
                            ],
                          );

                          final registrationDetailsSection = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeaderDark(
                                'Registration Details',
                                Icons.app_registration,
                              ),
                              _buildDarkFormCard([
                                _buildDatePickerField(
                                  context: context,
                                  label: 'Registration Date',
                                  date: registrationDate,
                                  icon: Icons.calendar_month,
                                  onTap: () async {
                                    final picked = await _showDatePickerModal(
                                      context,
                                    );
                                    if (picked != null) {
                                      setModalState(
                                        () => registrationDate = picked,
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: registeredByController,
                                  label: 'Registered By',
                                  icon: Icons.person_pin,
                                  hintText: 'Enter staff name or ID',
                                  validator: requiredValidator,
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: additionalNoteController,
                                  label: 'Additional Note',
                                  icon: Icons.note,
                                  hintText:
                                      'Enter any additional notes or remarks',
                                  maxLines: 4,
                                ),
                              ]),
                            ],
                          );

                          if (isWide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      patientInfoSection,
                                      const SizedBox(height: 16),
                                      pregnancyDetailSection,
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      medicalHistorySection,
                                      const SizedBox(height: 16),
                                      registrationDetailsSection,
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              patientInfoSection,
                              const SizedBox(height: 16),
                              pregnancyDetailSection,
                              const SizedBox(height: 16),
                              medicalHistorySection,
                              const SizedBox(height: 16),
                              registrationDetailsSection,
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                // Bottom Action Bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
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
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        key: updateButtonKey,
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
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        onPressed: () async {
                          final isFormValid =
                              formKey.currentState?.validate() ?? false;
                          final isLmpDateValid = lmpDate != null;
                          final isLmpDateNotFuture =
                              lmpDate == null ||
                              !lmpDate!.isAfter(DateTime.now());
                          if (!isLmpDateValid) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('LMP date is required'),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } else if (!isLmpDateNotFuture) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'LMP date cannot be in the future',
                                ),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                          if (!isFormValid ||
                              !isLmpDateValid ||
                              !isLmpDateNotFuture) {
                            return;
                          }

                          final updatedRecord = {
                            'id': record['id'],
                            'patientName':
                                '${firstNameController.text} ${surnameController.text}',
                            'age': ageController.text,
                            'address': addressController.text,
                            'patientId': patientIdController.text,
                            'contactNumber': contactNumberController.text,
                            'civilStatus': civilStatusController.text,
                            'religion': religionController.text,
                            'philhealthNumber': philhealthNumberController.text,
                            'philhealthMember': philhealthMemberController.text,
                            'lmpDate': lmpDate?.toIso8601String() ?? '',
                            'eddDate': eddDate?.toIso8601String() ?? '',
                            'lastDeliveryDate':
                                lastDeliveryDate?.toIso8601String() ?? '',
                            'gravida': gravidaController.text,
                            'para': paraController.text,
                            'riskLevel': selectedRiskLevel,
                            'bloodType': bloodTypeController.text,
                            'allergies': allergiesController.text,
                            'preExistingConditions':
                                preExistingConditionsController.text,
                            'previousComplications':
                                previousComplicationsController.text,
                            'aog': aogController.text,
                            'wt': wtController.text,
                            'at': atController.text,
                            'temp': tempController.text,
                            'bp': bpController.text,
                            'bmi': bmiController.text,
                            'fh': fhController.text,
                            'dhb': dhbController.text,
                            'tcb': tcbController.text,
                            'registrationDate':
                                registrationDate?.toIso8601String() ?? '',
                            'registeredBy': registeredByController.text,
                            'additionalNote': additionalNoteController.text,
                            'gestationalAge': aogController.text,
                            'dueDate': eddDate?.toIso8601String() ?? '',
                            'status': selectedRiskLevel,
                          };

                          if (record['id'] != null) {
                            try {
                              await _dbHelper.updateRecord(
                                record['id'].toString(),
                                updatedRecord,
                              );
                              await _loadRecords();

                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Prenatal record updated successfully!',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    backgroundColor: Colors.green,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Failed to update prenatal record: $e',
                                    ),
                                    backgroundColor: Colors.red,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Error: Record ID not found'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DateTime? _parseDate(dynamic dateValue) {
    if (dateValue == null || dateValue.toString().isEmpty) return null;
    try {
      return DateTime.parse(dateValue.toString());
    } catch (e) {
      return null;
    }
  }

  Future<DateTime?> _showDatePickerModal(BuildContext context) async {
    return await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _primaryAqua,
              onPrimary: Colors.white,
              onSurface: _darkDeepTeal,
            ),
          ),
          child: child!,
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primaryAqua.withValues(alpha: 0.12),
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
    );
  }

  Widget _buildFormCard(List<Widget> children) {
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
        children: children,
      ),
    );
  }

  // Modern clean form card for modals
  Widget _buildDarkFormCard(List<Widget> children) {
    return _buildFormCard(children);
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _mutedCoolGray,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          style: const TextStyle(
            color: _lightOffWhite,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: _mutedCoolGray.withValues(alpha: 0.55),
              fontSize: 13.5,
              fontWeight: FontWeight.normal,
            ),
            prefixIcon: Icon(icon, color: _primaryAqua, size: 20),
            filled: true,
            fillColor: Colors.white,
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePickerField({
    required BuildContext context,
    required String label,
    required DateTime? date,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _mutedCoolGray,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: date != null
                    ? _primaryAqua.withValues(alpha: 0.5)
                    : Colors.black.withValues(alpha: 0.12),
                width: date != null ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: _primaryAqua, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    date != null
                        ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'
                        : 'Select Date',
                    style: TextStyle(
                      color: date != null
                          ? _lightOffWhite
                          : _mutedCoolGray.withValues(alpha: 0.6),
                      fontSize: 14,
                      fontWeight: date != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (date != null)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: _primaryAqua,
                    size: 16,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required IconData icon,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    final dropdownItems = _uniqueDropdownItems(items);
    final safeValue = _resolveDropdownValue(value, dropdownItems);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _mutedCoolGray,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: safeValue,
          icon: const Icon(Icons.arrow_drop_down_rounded, color: _primaryAqua),
          dropdownColor: Colors.white,
          style: const TextStyle(
            color: _lightOffWhite,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: _primaryAqua, size: 20),
            filled: true,
            fillColor: Colors.white,
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          items: dropdownItems.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                style: const TextStyle(
                  color: _lightOffWhite,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  // Web-oriented Dashboard Card for larger screens

  // Web Filter Bar - Horizontal layout for desktop

  // Web Data Table view for patients - Card layout instead of DataTable

  void _showPatientDetails(BuildContext context, Map<String, dynamic> record) {
    final patientName = _safePrenatalDetailText(
      record['patientName'],
      fallback: 'Unknown Patient',
    );
    final nameParts = patientName.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts[0] : '';
    final surname = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
    final status = _safePrenatalDetailText(
      record['status'],
      fallback: 'Active',
    );
    final riskLevel = _safePrenatalDetailText(
      record['riskLevel'],
      fallback: status,
    );
    final gestationalAge = _safePrenatalDetailText(record['gestationalAge']);
    final dueDate = _formatDate(record['dueDate']);
    final contactNumber = _safePrenatalDetailText(record['contactNumber']);
    final patientId = _safePrenatalDetailText(record['patientId']);
    showFullscreenDetailTableDialog(
      context: context,
      title: 'Prenatal Details',
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
        DetailTableItem(
          icon: Icons.credit_card_outlined,
          label: 'Patient ID',
          value: patientId,
        ),
        DetailTableItem(
          icon: Icons.cake_outlined,
          label: 'Age',
          value: _safePrenatalDetailText(record['age']),
        ),
        DetailTableItem(
          icon: Icons.location_on_outlined,
          label: 'Address',
          value: _safePrenatalDetailText(record['address']),
        ),
        DetailTableItem(
          icon: Icons.phone_outlined,
          label: 'Contact Number',
          value: contactNumber,
        ),
        DetailTableItem(
          icon: Icons.favorite_outline_rounded,
          label: 'Status',
          value: status,
        ),
        DetailTableItem(
          icon: Icons.warning_amber_rounded,
          label: 'Risk Level',
          value: riskLevel,
        ),
        DetailTableItem(
          icon: Icons.timelapse_rounded,
          label: 'Gestational Age',
          value: gestationalAge,
        ),
        DetailTableItem(
          icon: Icons.event_available_outlined,
          label: 'Due Date',
          value: dueDate,
        ),
        DetailTableItem(
          icon: Icons.calendar_today_outlined,
          label: 'Registration Date',
          value: _formatDate(record['registrationDate']),
        ),
        DetailTableItem(
          icon: Icons.bloodtype_outlined,
          label: 'Blood Type',
          value: _safePrenatalDetailText(record['bloodType']),
        ),
        DetailTableItem(
          icon: Icons.health_and_safety_outlined,
          label: 'Allergies',
          value: _safePrenatalDetailText(record['allergies']),
        ),
        DetailTableItem(
          icon: Icons.warning_outlined,
          label: 'Pre-existing Conditions',
          value: _safePrenatalDetailText(record['preExistingConditions']),
        ),
        DetailTableItem(
          icon: Icons.history_edu_outlined,
          label: 'Previous Complications',
          value: _safePrenatalDetailText(record['previousComplications']),
        ),
        DetailTableItem(
          icon: Icons.monitor_weight_outlined,
          label: 'Weight',
          value: _safePrenatalDetailText(record['wt'] ?? record['weight']),
        ),
        DetailTableItem(
          icon: Icons.device_thermostat_outlined,
          label: 'Temperature',
          value: _safePrenatalDetailText(
            record['temp'] ?? record['temperature'],
          ),
        ),
        DetailTableItem(
          icon: Icons.favorite_border_rounded,
          label: 'Blood Pressure',
          value: _safePrenatalDetailText(
            record['bp'] ?? record['bloodPressure'],
          ),
        ),
        DetailTableItem(
          icon: Icons.straighten_rounded,
          label: 'Fundal Height',
          value: _safePrenatalDetailText(
            record['fh'] ?? record['fundalHeight'],
          ),
        ),
        DetailTableItem(
          icon: Icons.monitor_heart_outlined,
          label: 'Fetal Heart Beat',
          value: _safePrenatalDetailText(
            record['dhb'] ?? record['fetalHeartBeat'],
          ),
        ),
        DetailTableItem(
          icon: Icons.medical_information_outlined,
          label: 'Additional Notes',
          value: _safePrenatalDetailText(
            record['additionalNote'] ?? record['additionalNotes'],
            fallback: '',
          ),
        ),
      ],
    );
    return;
  }

  List<Map<String, dynamic>> _getPrenatalHistory(Map<String, dynamic> record) {
    return PatientHistoryDialogs.collectHistory(
      seedRecord: record,
      records: _prenatalRecords,
      idKeys: const ['linkedPatientId', 'patientId'],
      nameKeys: const ['patientName', 'patient'],
      sortDateKeys: const ['registrationDate', 'dueDate', 'lmpDate'],
    );
  }

  Map<String, dynamic> _buildPatientHistorySeed(Map<String, dynamic> record) {
    final patientName =
        (record['patientName'] ?? record['patient'] ?? record['name'] ?? '')
            .toString()
            .trim();
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
    if (!context.mounted) {
      return;
    }

    await PatientHistoryDialogs.showPatientTimelineDialog(
      context: context,
      patient: patient,
      snapshot: snapshot,
    );
  }

  void _showPrenatalHistory(BuildContext context, Map<String, dynamic> record) {
    final history = _getPrenatalHistory(record);
    PatientHistoryDialogs.showModuleHistoryDialog(
      context: context,
      moduleTitle: 'Prenatal',
      seedRecord: record,
      history: history,
      description:
          'Review previous prenatal visits before recording the next maternal check-in for the same patient.',
      addButtonLabel: 'Add Another Prenatal Visit',
      titleBuilder: (entry) =>
          (entry['riskLevel'] ?? entry['status'] ?? 'Prenatal visit')
              .toString(),
      subtitleBuilder: (entry) =>
          'Gestational age: ${(entry['gestationalAge'] ?? entry['aog'] ?? 'N/A').toString()}',
      metaBuilder: (entry) =>
          'Due: ${_formatDate(entry['dueDate'])} | Contact: ${(entry['contactNumber'] ?? 'N/A').toString()}',
      dateKeys: const ['registrationDate', 'dueDate', 'lmpDate'],
      secondaryActionLabel: 'Medical History',
      onSecondaryAction: () => _showPatientMedicalHistory(context, record),
      onAddAnother: () => _showNewPrenatalModal(
        context,
        patientSeed: history.isNotEmpty ? history.first : record,
      ),
      onOpenRecord: (entry) => _showPatientDetails(context, entry),
    );
  }

  void _onViewButtonPressed(BuildContext context, Map<String, dynamic> record) {
    _showPrenatalHistory(context, record);
  }

  String _safePrenatalDetailText(
    dynamic value, {
    String fallback = 'Not recorded',
  }) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  Widget _buildSectionHeaderDark(String title, IconData icon) {
    return _buildSectionHeader(title, icon);
  }

  String _formatDate(dynamic date) {
    if (date == null || date.toString().isEmpty) return 'N/A';
    try {
      final dateTime = DateTime.parse(date.toString());
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return date.toString();
    }
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _darkDeepTeal,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _primaryAqua, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
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
                    color: _primaryAqua.withValues(alpha: 0.25),
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(_selectedIndices.length / (_getFilteredRecords().isNotEmpty ? _getFilteredRecords().length : 1) * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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
                          _getFilteredRecords().length,
                          (index) => index,
                        );
                        _selectedIndices.addAll(allIndices);
                      });
                    },
                    icon: const Icon(Icons.select_all, size: 18),
                    label: const Text('Select All'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryAqua,
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
                    icon: const Icon(Icons.delete, size: 18),
                    label: const Text('Delete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[600],
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
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white30, width: 1.5),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No records selected'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [Text('Confirm Delete')]),
        content: Text(
          'Are you sure you want to delete ${_selectedIndices.length} selected record(s)? This action cannot be undone.',
          style: TextStyle(color: _darkDeepTeal),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text(
              'Cancel',
              style: TextStyle(
                color: _mutedCoolGray,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteSelectedRecords();
            },
            child: Text(
              'Delete',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _deleteSelectedRecords() async {
    final count = _selectedIndices.length;

    // Get IDs of records to delete
    final filteredRecords = _getFilteredRecords();
    final idsToDelete = _selectedIndices
        .map(
          (index) => index < filteredRecords.length
              ? filteredRecords[index]['id'] as String?
              : null,
        )
        .whereType<String>()
        .toList();

    // Delete from database
    final succeededIds = await _dbHelper.deleteRecords(idsToDelete);
    final failedCount = idsToDelete.length - succeededIds.length;

    setState(() {
      _selectedIndices.clear();
      _isSelectionMode = false;
    });

    // Reload records
    await _loadRecords();

    if (!mounted) return;
    final message = failedCount == 0
        ? 'Successfully deleted $count record(s)'
        : succeededIds.isEmpty
        ? 'Failed to delete $count record(s)'
        : 'Deleted ${succeededIds.length} of $count record(s); $failedCount failed';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: failedCount == 0 ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  DateTime? _coercePrenatalRecordDate(Map<String, dynamic> record) {
    return _prenatalDate(record['registrationDate']) ??
        _prenatalDate(record['lmpDate']) ??
        _prenatalDate(record['dueDate']) ??
        _prenatalDate(record['createdAt']) ??
        _prenatalDate(record['updatedAt']) ??
        _prenatalDate(record['date']) ??
        _prenatalDate(record['consultationDate']) ??
        _prenatalDate(record['timestamp']);
  }

  bool _matchesInsightsDateFilter(DateTime? date) {
    if (_insightsDateFilterMode == DashboardDateFilterMode.allTime) return true;
    if (date == null) return false;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (_insightsDateFilterMode) {
      case DashboardDateFilterMode.today:
        return !date.isBefore(todayStart) && !date.isAfter(todayEnd);
      case DashboardDateFilterMode.last7Days:
        final start = todayStart.subtract(const Duration(days: 6));
        return !date.isBefore(start) && !date.isAfter(todayEnd);
      case DashboardDateFilterMode.last30Days:
        final start = todayStart.subtract(const Duration(days: 29));
        return !date.isBefore(start) && !date.isAfter(todayEnd);
      case DashboardDateFilterMode.thisMonth:
        final targetMonth = _insightsSelectedMonth ?? now;
        return date.year == targetMonth.year && date.month == targetMonth.month;
      case DashboardDateFilterMode.last6Months:
        final start = DateTime(now.year, now.month - 5, 1);
        return !date.isBefore(start) && !date.isAfter(todayEnd);
      case DashboardDateFilterMode.customDay:
        final target = _insightsCustomDate ?? now;
        final start = DateTime(target.year, target.month, target.day);
        final end = DateTime(target.year, target.month, target.day, 23, 59, 59);
        return !date.isBefore(start) && !date.isAfter(end);
      case DashboardDateFilterMode.customRange:
        final start = DateTime(
          _insightsRangeStart.year,
          _insightsRangeStart.month,
          _insightsRangeStart.day,
        );
        final end = DateTime(
          _insightsRangeEnd.year,
          _insightsRangeEnd.month,
          _insightsRangeEnd.day,
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

  String _activeInsightsWindowLabel([DashboardDateFilterMode? mode]) {
    final activeMode = mode ?? _insightsDateFilterMode;
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
          final target = _insightsSelectedMonth ?? now;
          return '${_monthLabelLong(target.month)} ${target.year}';
        case DashboardDateFilterMode.last6Months:
          final start = DateTime(now.year, now.month - 5, 1);
          return 'Last 6 Months (${_monthLabelShort(start.month)} ${start.year} - ${_monthLabelShort(now.month)} ${now.year})';
        case DashboardDateFilterMode.customDay:
          final d = _insightsCustomDate ?? now;
          return '${_monthLabelLong(d.month)} ${d.day}, ${d.year}';
        case DashboardDateFilterMode.customRange:
          final s = _insightsRangeStart;
          final e = _insightsRangeEnd;
          return '${_monthLabelShort(s.month)} ${s.day} - ${_monthLabelShort(e.month)} ${e.day}, ${e.year}';
        case DashboardDateFilterMode.allTime:
          return 'All Time History';
      }
    } catch (_) {}
    return 'All Time History';
  }

  Widget _buildInsightsFilterBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideHeader = constraints.maxWidth > 760;
        final filterBorderColor = Colors.black.withValues(alpha: 0.12);

        final headerCopy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Maternal & Prenatal Insights Filter',
              style: TextStyle(
                color: _lightOffWhite,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Filter pregnancy cohorts, risk distributions, visits, and complications by date. Currently showing ${_activeInsightsWindowLabel().toLowerCase()}.',
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
                _activeInsightsWindowLabel(),
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
                'Charts & counts auto-synced',
                style: TextStyle(color: _mutedCoolGray, fontSize: 9.5),
              ),
            ],
          ),
        );

        final filterChips = <Widget>[
          _buildInsightsFilterChip(
            'All Time',
            Icons.all_inclusive_rounded,
            DashboardDateFilterMode.allTime,
          ),
          _buildInsightsFilterChip(
            'Today',
            Icons.today_rounded,
            DashboardDateFilterMode.today,
          ),
          _buildInsightsFilterChip(
            'Last 7 Days',
            Icons.calendar_view_week_rounded,
            DashboardDateFilterMode.last7Days,
          ),
          _buildInsightsFilterChip(
            'Last 30 Days',
            Icons.date_range_rounded,
            DashboardDateFilterMode.last30Days,
          ),
          _buildInsightsFilterChip(
            'This Month',
            Icons.calendar_month_rounded,
            DashboardDateFilterMode.thisMonth,
          ),
          _buildInsightsFilterChip(
            'Last 6 Months',
            Icons.stacked_bar_chart_rounded,
            DashboardDateFilterMode.last6Months,
          ),
          OutlinedButton.icon(
            onPressed: _showInsightsDateFilterPickerModal,
            icon: const Icon(Icons.tune_rounded, size: 14),
            label: Text(
              _insightsDateFilterMode == DashboardDateFilterMode.customDay ||
                      _insightsDateFilterMode ==
                          DashboardDateFilterMode.customRange
                  ? 'Custom (${_activeInsightsWindowLabel()})'
                  : 'Pick Date / Range...',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  (_insightsDateFilterMode ==
                          DashboardDateFilterMode.customDay ||
                      _insightsDateFilterMode ==
                          DashboardDateFilterMode.customRange)
                  ? _primaryAqua
                  : _lightOffWhite,
              backgroundColor:
                  (_insightsDateFilterMode ==
                          DashboardDateFilterMode.customDay ||
                      _insightsDateFilterMode ==
                          DashboardDateFilterMode.customRange)
                  ? _primaryAqua.withValues(alpha: 0.12)
                  : Colors.white,
              side: BorderSide(
                color:
                    (_insightsDateFilterMode ==
                            DashboardDateFilterMode.customDay ||
                        _insightsDateFilterMode ==
                            DashboardDateFilterMode.customRange)
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

  Widget _buildInsightsFilterChip(
    String label,
    IconData icon,
    DashboardDateFilterMode mode,
  ) {
    final isSelected = _insightsDateFilterMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        if (isSelected) return;
        setState(() {
          _insightsDateFilterMode = mode;
          if (mode == DashboardDateFilterMode.thisMonth) {
            _insightsSelectedMonth = DateTime.now();
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

  Future<void> _showInsightsDateFilterPickerModal() async {
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
                'Filter Prenatal Insights',
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
                    initialDate: _insightsCustomDate ?? now,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _insightsDateFilterMode = DashboardDateFilterMode.customDay;
                    _insightsCustomDate = picked;
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
                  'Pick target month (Current: ${_monthLabelLong((_insightsSelectedMonth ?? DateTime.now()).month)})',
                ),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  final target = _insightsSelectedMonth ?? DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: target,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                    initialDatePickerMode: DatePickerMode.year,
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _insightsDateFilterMode = DashboardDateFilterMode.thisMonth;
                    _insightsSelectedMonth = DateTime(
                      picked.year,
                      picked.month,
                    );
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
                      start: _insightsRangeStart,
                      end: _insightsRangeEnd,
                    ),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _insightsDateFilterMode =
                        DashboardDateFilterMode.customRange;
                    _insightsRangeStart = picked.start;
                    _insightsRangeEnd = picked.end;
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
                    _insightsDateFilterMode = DashboardDateFilterMode.allTime;
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Statistics Dashboard - matches patient.dart style
  Widget _buildStatisticsDashboard() {
    final latestPregnancies = _latestPregnancyRecords();
    final total = latestPregnancies.length;
    final highRisk = latestPregnancies.where(_isHighRiskPregnancy).length;
    final completed = latestPregnancies.where(_isCompletedPregnancy).length;
    final active = total - completed;

    final charts = <Widget>[
      _buildPrenatalChartCard(
        title: 'Monthly Prenatal Visits',
        subtitle:
            'Visits recorded during ${_activeInsightsWindowLabel().toLowerCase()}',
        icon: Icons.show_chart_rounded,
        child: _buildPrenatalMonthlyLineChart(),
      ),
      _buildPrenatalChartCard(
        title: 'Pregnancy Risk Distribution',
        subtitle:
            'Current maternal risk classification for ${_activeInsightsWindowLabel().toLowerCase()}',
        icon: Icons.health_and_safety_outlined,
        child: _buildPrenatalRiskPieChart(),
      ),
      _buildPrenatalChartCard(
        title: 'High-Risk Pregnancies by Barangay',
        subtitle: 'Location of records requiring closer monitoring',
        icon: Icons.location_on_outlined,
        child: _buildPrenatalBarChart(
          _highRiskByBarangay(),
          emptyMessage:
              'No high-risk pregnancies are currently recorded for this period.',
          tooltipUnit: 'case',
          colors: const [_secondaryIceBlue, _primaryAqua],
        ),
      ),
      _buildPrenatalChartCard(
        title: 'Gestational Age Distribution',
        subtitle:
            'Pregnancies grouped by trimester in ${_activeInsightsWindowLabel().toLowerCase()}',
        icon: Icons.calendar_view_month_rounded,
        child: _buildPrenatalBarChart(
          _gestationalAgeDistribution(),
          emptyMessage: 'Gestational-age data has not been recorded yet.',
          tooltipUnit: 'pregnancy',
          colors: const [_secondaryIceBlue, Color(0xFF5B8CC9)],
        ),
      ),
      _buildPrenatalChartCard(
        title: 'Prenatal Completion Rate',
        subtitle: 'Completed prenatal records compared with ongoing care',
        icon: Icons.task_alt_rounded,
        child: _buildPrenatalCompletionChart(),
      ),
      _buildPrenatalChartCard(
        title: 'Maternal Age Distribution',
        subtitle:
            'Prenatal patients grouped by maternal age in ${_activeInsightsWindowLabel().toLowerCase()}',
        icon: Icons.groups_2_outlined,
        child: _buildPrenatalBarChart(
          _maternalAgeDistribution(),
          emptyMessage: 'Maternal-age data has not been recorded yet.',
          tooltipUnit: 'patient',
          colors: const [_primaryAqua, _secondaryIceBlue],
        ),
      ),
      _buildPrenatalChartCard(
        title: 'Pregnancy Complications',
        subtitle: 'Most frequently recorded previous complications',
        icon: Icons.monitor_heart_outlined,
        child: _buildPrenatalBarChart(
          _pregnancyComplicationDistribution(),
          emptyMessage:
              'No pregnancy complications are currently recorded for this period.',
          tooltipUnit: 'case',
          colors: const [_primaryAqua, Color(0xFF8FAFD6)],
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInsightsFilterBar(),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100
                ? 4
                : constraints.maxWidth >= 680
                ? 2
                : 1;
            const spacing = 12.0;
            final cardWidth = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - spacing * (columns - 1)) / columns;
            final cards = <Widget>[
              _buildWebMetricCard(
                title:
                    _insightsDateFilterMode == DashboardDateFilterMode.allTime
                    ? 'Total Prenatal'
                    : 'Prenatal Cases',
                value: '$total',
                icon: Icons.pregnant_woman_outlined,
              ),
              _buildWebMetricCard(
                title: 'Active',
                value: '$active',
                icon: Icons.monitor_heart_outlined,
              ),
              _buildWebMetricCard(
                title: 'High Risk',
                value: '$highRisk',
                icon: Icons.warning_amber_outlined,
              ),
              _buildWebMetricCard(
                title: 'Completed',
                value: '$completed',
                icon: Icons.check_circle_outline,
              ),
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
            final columns = constraints.maxWidth >= 1050 ? 2 : 1;
            final cardWidth = columns == 2
                ? (constraints.maxWidth - 20) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 20,
              runSpacing: 20,
              children: charts
                  .map((chart) => SizedBox(width: cardWidth, child: chart))
                  .toList(growable: false),
            );
          },
        ),
        const SizedBox(height: 20),
        _buildCareTeamAttentionPanel(),
      ],
    );
  }

  List<Map<String, dynamic>> _latestPregnancyRecords() {
    final collapsed = CurrentTableRecordUtils.collapseToLatestPerEntity(
      _prenatalRecords,
      idKeys: const ['linkedPatientId', 'patientId', 'patientCode'],
      nameKeys: const ['patientName', 'patient'],
      dateKeys: const [
        'registrationDate',
        'updatedAt',
        'createdAt',
        'lmpDate',
        'dueDate',
        'date',
      ],
    );
    if (_insightsDateFilterMode == DashboardDateFilterMode.allTime) {
      return collapsed;
    }
    return collapsed
        .where((record) {
          final date = _coercePrenatalRecordDate(record);
          return _matchesInsightsDateFilter(date);
        })
        .toList(growable: false);
  }

  DateTime? _prenatalDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    try {
      final dynamic converted = raw.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      // Firestore timestamps may already be converted to strings by the cache.
    }
    return DateTime.tryParse(raw.toString().trim());
  }

  int? _firstInteger(dynamic raw) {
    final match = RegExp(r'\d+').firstMatch(raw?.toString() ?? '');
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  String _riskStatus(Map<String, dynamic> record) {
    return (record['riskLevel'] ?? record['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
  }

  bool _isHighRiskPregnancy(Map<String, dynamic> record) {
    final risk = _riskStatus(record);
    final severity = (record['ai_severity'] ?? '').toString().toLowerCase();
    return risk.contains('high') ||
        risk.contains('critical') ||
        severity == 'high' ||
        severity == 'critical';
  }

  bool _isCompletedPregnancy(Map<String, dynamic> record) {
    final status = _riskStatus(record);
    return status.contains('completed') ||
        status.contains('closed') ||
        status.contains('delivered');
  }

  List<MapEntry<String, int>> _monthlyPrenatalVisits() {
    final now = DateTime.now();
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
    return List<MapEntry<String, int>>.generate(6, (index) {
      final month = DateTime(now.year, now.month - (5 - index));
      final count = _prenatalRecords.where((record) {
        final date = _prenatalDate(
          record['registrationDate'] ?? record['createdAt'],
        );
        return date != null &&
            date.year == month.year &&
            date.month == month.month;
      }).length;
      return MapEntry(
        '${monthNames[month.month - 1]} ${month.year % 100}',
        count,
      );
    });
  }

  List<MapEntry<String, int>> _riskDistribution() {
    final counts = <String, int>{
      'High Risk': 0,
      'Follow Up': 0,
      'Active': 0,
      'Completed': 0,
    };
    for (final record in _latestPregnancyRecords()) {
      final risk = _riskStatus(record);
      final label = _isHighRiskPregnancy(record)
          ? 'High Risk'
          : _isCompletedPregnancy(record)
          ? 'Completed'
          : risk.contains('follow') || risk.contains('monitor')
          ? 'Follow Up'
          : 'Active';
      counts[label] = counts[label]! + 1;
    }
    return counts.entries.where((entry) => entry.value > 0).toList();
  }

  String _recordBarangay(Map<String, dynamic> record) {
    for (final key in const [
      'barangayName',
      'barangay',
      'assignedBarangay',
      'barangayId',
    ]) {
      final value = record[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    final address = record['address']?.toString().trim() ?? '';
    final match = RegExp(
      r'\bbarangay\s+([^,;]+)',
      caseSensitive: false,
    ).firstMatch(address);
    if (match != null && (match.group(1)?.trim().isNotEmpty ?? false)) {
      return 'Barangay ${match.group(1)!.trim()}';
    }
    return 'Unspecified';
  }

  List<MapEntry<String, int>> _highRiskByBarangay() {
    final counts = <String, int>{};
    for (final record in _latestPregnancyRecords().where(
      _isHighRiskPregnancy,
    )) {
      final barangay = _recordBarangay(record);
      counts[barangay] = (counts[barangay] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(6).toList(growable: false);
  }

  List<MapEntry<String, int>> _gestationalAgeDistribution() {
    final counts = <String, int>{
      '1st (1–13w)': 0,
      '2nd (14–27w)': 0,
      '3rd (28–42w)': 0,
      'Not recorded': 0,
    };
    for (final record in _latestPregnancyRecords()) {
      final weeks = _firstInteger(record['gestationalAge'] ?? record['aog']);
      final label = weeks == null || weeks < 1 || weeks > 45
          ? 'Not recorded'
          : weeks <= 13
          ? '1st (1–13w)'
          : weeks <= 27
          ? '2nd (14–27w)'
          : '3rd (28–42w)';
      counts[label] = counts[label]! + 1;
    }
    return counts.entries.where((entry) => entry.value > 0).toList();
  }

  List<MapEntry<String, int>> _maternalAgeDistribution() {
    final counts = <String, int>{
      '<20': 0,
      '20–24': 0,
      '25–29': 0,
      '30–34': 0,
      '35+': 0,
    };
    for (final record in _latestPregnancyRecords()) {
      final age = _firstInteger(record['age']);
      if (age == null || age < 10 || age > 65) continue;
      final label = age < 20
          ? '<20'
          : age <= 24
          ? '20–24'
          : age <= 29
          ? '25–29'
          : age <= 34
          ? '30–34'
          : '35+';
      counts[label] = counts[label]! + 1;
    }
    return counts.entries.where((entry) => entry.value > 0).toList();
  }

  Set<String> _recordComplications(Map<String, dynamic> record) {
    final raw = record['previousComplications']?.toString().trim() ?? '';
    if (raw.isEmpty) return <String>{};
    const ignored = <String>{
      'none',
      'n/a',
      'na',
      'no',
      'no complications',
      'not applicable',
    };
    final values = raw.split(
      RegExp(r'[,;|\n]+|\s+and\s+', caseSensitive: false),
    );
    final result = <String>{};
    for (final value in values) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty || ignored.contains(normalized)) continue;
      result.add(
        normalized
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
            .join(' '),
      );
    }
    return result;
  }

  List<MapEntry<String, int>> _pregnancyComplicationDistribution() {
    final counts = <String, int>{};
    for (final record in _latestPregnancyRecords()) {
      for (final complication in _recordComplications(record)) {
        counts[complication] = (counts[complication] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final countOrder = b.value.compareTo(a.value);
        return countOrder != 0 ? countOrder : a.key.compareTo(b.key);
      });
    return entries.take(6).toList(growable: false);
  }

  double _prenatalChartMax(Iterable<int> values) {
    final largest = values.fold<int>(0, math.max);
    return math
        .max(4, largest + math.max(1, (largest * 0.25).ceil()))
        .toDouble();
  }

  FlTitlesData _prenatalChartTitles(List<String> labels, double interval) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: interval,
          reservedSize: 32,
          getTitlesWidget: (value, _) => Text(
            value.toInt().toString(),
            style: const TextStyle(color: _mutedCoolGray, fontSize: 10),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 38,
          getTitlesWidget: (value, _) {
            final index = value.toInt();
            if (value != index || index < 0 || index >= labels.length) {
              return const SizedBox.shrink();
            }
            final label = labels[index];
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                label.length > 13 ? '${label.substring(0, 11)}…' : label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _mutedCoolGray, fontSize: 9.5),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPrenatalChartCard({
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
            color: Colors.black.withValues(alpha: 0.15),
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

  Widget _buildPrenatalMonthlyLineChart() {
    final values = _monthlyPrenatalVisits();
    final maxY = _prenatalChartMax(values.map((entry) => entry.value));
    final interval = math.max(1, (maxY / 4).ceil()).toDouble();
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (values.length - 1).toDouble(),
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
        titlesData: _prenatalChartTitles(
          values.map((entry) => entry.key).toList(),
          interval,
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF163B66),
            getTooltipItems: (spots) => spots
                .map(
                  (spot) => LineTooltipItem(
                    '${values[spot.x.toInt()].key}\n${spot.y.toInt()} visit${spot.y == 1 ? '' : 's'}',
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
            spots: List.generate(
              values.length,
              (index) =>
                  FlSpot(index.toDouble(), values[index].value.toDouble()),
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

  Widget _buildPrenatalBarChart(
    List<MapEntry<String, int>> entries, {
    required String emptyMessage,
    required String tooltipUnit,
    required List<Color> colors,
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
    final maxY = _prenatalChartMax(entries.map((entry) => entry.value));
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
        titlesData: _prenatalChartTitles(
          entries.map((entry) => entry.key).toList(),
          interval,
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF163B66),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final entry = entries[group.x];
              return BarTooltipItem(
                '${entry.key}\n${entry.value} $tooltipUnit${entry.value == 1 ? '' : 's'}',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
        ),
        barGroups: List.generate(entries.length, (index) {
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

  Widget _buildPrenatalRiskPieChart() {
    final entries = _riskDistribution();
    const colorByRisk = <String, Color>{
      'High Risk': _secondaryIceBlue,
      'Follow Up': Color(0xFF5B8CC9),
      'Active': _primaryAqua,
      'Completed': Color(0xFF8FAFD6),
    };
    return _buildPrenatalPieChart(
      entries,
      entries
          .map((entry) => colorByRisk[entry.key] ?? _mutedCoolGray)
          .toList(growable: false),
      centerLabel: '${entries.fold<int>(0, (sum, entry) => sum + entry.value)}',
      centerSubtitle: 'cases',
    );
  }

  Widget _buildPrenatalCompletionChart() {
    final records = _latestPregnancyRecords();
    final completed = records.where(_isCompletedPregnancy).length;
    final entries = <MapEntry<String, int>>[
      MapEntry('Completed', completed),
      MapEntry('Ongoing', records.length - completed),
    ];
    final percentage = records.isEmpty ? 0 : (completed * 100 / records.length);
    return _buildPrenatalPieChart(
      entries.where((entry) => entry.value > 0).toList(),
      const [_primaryAqua, _secondaryIceBlue],
      centerLabel: '${percentage.toStringAsFixed(0)}%',
      centerSubtitle: 'complete',
    );
  }

  Widget _buildPrenatalPieChart(
    List<MapEntry<String, int>> entries,
    List<Color> colors, {
    String? centerLabel,
    String? centerSubtitle,
  }) {
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          'No data available yet.',
          style: TextStyle(color: _mutedCoolGray, fontSize: 13),
        ),
      );
    }
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  centerSpaceRadius: 52,
                  sectionsSpace: 3,
                  sections: List.generate(entries.length, (index) {
                    final entry = entries[index];
                    final percent = total == 0 ? 0 : entry.value * 100 / total;
                    return PieChartSectionData(
                      value: entry.value.toDouble(),
                      color: colors[index % colors.length],
                      radius: 45,
                      title: percent >= 8
                          ? '${percent.toStringAsFixed(0)}%'
                          : '',
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  }),
                  centerSpaceColor: Colors.transparent,
                ),
              ),
              if (centerLabel != null)
                IgnorePointer(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        centerLabel,
                        style: const TextStyle(
                          color: _lightOffWhite,
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (centerSubtitle != null)
                        Text(
                          centerSubtitle,
                          style: const TextStyle(
                            color: _mutedCoolGray,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(entries.length, (index) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: colors[index % colors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${entries[index].key} (${entries[index].value})',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _mutedCoolGray,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  List<MapEntry<Map<String, dynamic>, List<String>>> _careTeamHighlights() {
    final highlights = <MapEntry<Map<String, dynamic>, List<String>>>[];
    final now = DateTime.now();
    for (final record in _latestPregnancyRecords()) {
      if (_isCompletedPregnancy(record)) continue;
      final reasons = <String>[];
      if (_isHighRiskPregnancy(record)) reasons.add('High-risk classification');
      final complications = _recordComplications(record);
      if (complications.isNotEmpty) {
        reasons.add('Complications: ${complications.take(2).join(', ')}');
      }
      final age = _firstInteger(record['age']);
      if (age != null && (age < 18 || age >= 35)) {
        reasons.add('Maternal age requires closer monitoring');
      }
      final gestationalWeeks = _firstInteger(
        record['gestationalAge'] ?? record['aog'],
      );
      if (gestationalWeeks != null && gestationalWeeks > 40) {
        reasons.add('Gestational age exceeds 40 weeks');
      }
      final dueDate = _prenatalDate(record['eddDate'] ?? record['dueDate']);
      if (dueDate != null && dueDate.isBefore(now)) {
        reasons.add('Expected delivery date has passed');
      }
      final bp = record['bp']?.toString() ?? '';
      final bpParts = RegExp(r'(\d{2,3})\s*/\s*(\d{2,3})').firstMatch(bp);
      if (bpParts != null) {
        final systolic = int.tryParse(bpParts.group(1)!);
        final diastolic = int.tryParse(bpParts.group(2)!);
        if ((systolic ?? 0) >= 140 || (diastolic ?? 0) >= 90) {
          reasons.add('Elevated recorded blood pressure');
        }
      }
      if (reasons.isNotEmpty) highlights.add(MapEntry(record, reasons));
    }
    highlights.sort((a, b) {
      final riskOrder = (_isHighRiskPregnancy(b.key) ? 1 : 0).compareTo(
        _isHighRiskPregnancy(a.key) ? 1 : 0,
      );
      return riskOrder != 0
          ? riskOrder
          : b.value.length.compareTo(a.value.length);
    });
    return highlights.take(8).toList(growable: false);
  }

  Widget _buildCareTeamAttentionPanel() {
    final highlights = _careTeamHighlights();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.notification_important_outlined, color: _primaryAqua),
              SizedBox(width: 10),
              Text(
                'Highlights Requiring Care-Team Attention',
                style: TextStyle(
                  color: _lightOffWhite,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Decision-support highlights from recorded data. Review and confirm each case clinically.',
            style: TextStyle(color: _mutedCoolGray, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (highlights.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _primaryAqua.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'No prenatal records currently meet the configured attention indicators.',
                style: TextStyle(color: _mutedCoolGray, fontSize: 13),
              ),
            )
          else
            ...highlights.map((highlight) {
              final record = highlight.key;
              final patient = (record['patientName'] ?? 'Unknown patient')
                  .toString();
              final highRisk = _isHighRiskPregnancy(record);
              final color = highRisk ? _secondaryIceBlue : _primaryAqua;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.22)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      highRisk
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline,
                      color: color,
                      size: 21,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patient,
                            style: const TextStyle(
                              color: _lightOffWhite,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${_recordBarangay(record)} • ${highlight.value.join(' • ')}',
                            style: const TextStyle(
                              color: _mutedCoolGray,
                              fontSize: 11.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // Keep this compatibility wrapper for the older prenatal view while using
  // the same metric card as every other CHO/BHW operational page.
  Widget _buildWebMetricCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return AppMetricCard(label: title, value: value, icon: icon);
  }

  Widget _buildPrenatalHeaderCell(String label, {required int flex}) {
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

  Widget _buildPrenatalHeaderDivider() {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white.withValues(alpha: 0.2),
    );
  }

  Widget _buildHighlightedPrenatalAddButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showNewPrenatalModal(context),
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
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pregnant_woman_rounded, color: Colors.white, size: 18),
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

  Widget _buildHighlightedPrenatalAddButtonContainer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _primaryAqua.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: _buildHighlightedPrenatalAddButton(context),
    );
  }

  Widget _buildPrenatalCardHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _secondaryIceBlue,
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
              width: 30,
              child: Text(
                'Sel',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          _buildPrenatalHeaderCell('Date / Time', flex: 15),
          _buildPrenatalHeaderDivider(),
          _buildPrenatalHeaderCell('Patient Info', flex: 23),
          _buildPrenatalHeaderDivider(),
          _buildPrenatalHeaderCell('Pregnancy & Gestation', flex: 25),
          _buildPrenatalHeaderDivider(),
          _buildPrenatalHeaderCell('Clinical & Vitals', flex: 21),
          _buildPrenatalHeaderDivider(),
          _buildPrenatalHeaderCell('Risk & Status', flex: 16),
          if (!_isSelectionMode) ...[
            _buildPrenatalHeaderDivider(),
            const SizedBox(
              width: 140,
              child: Text(
                'Actions',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
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

  // Prenatal Table - matches patient.dart _buildPatientTable() structure
  Widget _buildPrenatalTable() {
    final records = _getFilteredRecords();
    final effectiveRowsPerPage = _rowsPerPage > 0 ? _rowsPerPage : 10;
    final totalPages = records.isEmpty
        ? 1
        : ((records.length + effectiveRowsPerPage - 1) ~/ effectiveRowsPerPage);
    final currentPage = _currentPage < 1
        ? 1
        : (_currentPage > totalPages ? totalPages : _currentPage);
    final pageStartIndex = records.isEmpty
        ? 0
        : (currentPage - 1) * effectiveRowsPerPage;
    final pageEndIndex = records.isEmpty
        ? 0
        : math.min(pageStartIndex + effectiveRowsPerPage, records.length);
    final pagedRecords = records.isEmpty
        ? <Map<String, dynamic>>[]
        : records.sublist(pageStartIndex, pageEndIndex);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _buildSearchBar(),
          ),
          if (_searchQuery.trim().isNotEmpty || _isSearchingSharedPatients)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SharedPatientSearchPanel(
                query: _searchQuery,
                results: _sharedPatientMatches,
                isLoading: _isSearchingSharedPatients,
                primaryActionLabel: 'View Medical History',
                onPrimaryAction: _showSharedPatientTimeline,
                secondaryActionLabel: 'Start Prenatal Visit',
                onSecondaryAction: (patient) =>
                    _showNewPrenatalModal(context, patientSeed: patient),
              ),
            ),

          // Unified Filter Section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _buildFilterSection(),
          ),

          const Divider(color: AppColors.border, height: 1),

          // Record count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              '${records.length} prenatal record${records.length != 1 ? 's' : ''} found',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                if (!_isSelectionMode)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _isSelectionMode = true;
                          _selectedIndices.clear();
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _primaryAqua.withValues(alpha: 0.3),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Select',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
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
                          _isSelectionMode = false;
                          _selectedIndices.clear();
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _primaryAqua.withValues(alpha: 0.2),
                          border: Border.all(
                            color: _primaryAqua.withValues(alpha: 0.5),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: _primaryAqua,
                              size: 18,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Done',
                              style: TextStyle(
                                color: _primaryAqua,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                _buildHighlightedPrenatalAddButtonContainer(context),
              ],
            ),
          ),

          // Records list
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.pregnant_woman_rounded,
                      color: _mutedCoolGray,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No prenatal records found',
                      style: TextStyle(color: _mutedCoolGray, fontSize: 15),
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  _buildPrenatalCardHeader(),
                  ...List.generate(pagedRecords.length, (index) {
                    final absoluteIndex = pageStartIndex + index;
                    final isSelected = _selectedIndices.contains(absoluteIndex);
                    return _PrenatalCard(
                      record: pagedRecords[index],
                      isSelectionMode: _isSelectionMode,
                      isSelected: isSelected,
                      index: absoluteIndex,
                      onSelectionChanged: (idx, selected) {
                        setState(() {
                          if (selected) {
                            _selectedIndices.add(idx);
                          } else {
                            _selectedIndices.remove(idx);
                          }
                        });
                      },
                      onEdit: (record) =>
                          _showEditPrenatalModal(context, record),
                      onView: (record) => _onViewButtonPressed(context, record),
                    );
                  }),
                ],
              ),
            ),
          if (records.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Showing ${pageStartIndex + 1}-$pageEndIndex of ${records.length} records',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _primaryAqua.withValues(alpha: 0.25),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        dropdownColor: AppColors.surfaceLight,
                        value: effectiveRowsPerPage,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        iconEnabledColor: AppColors.textSecondary,
                        items: const [
                          DropdownMenuItem(value: 10, child: Text('10 / page')),
                          DropdownMenuItem(value: 20, child: Text('20 / page')),
                          DropdownMenuItem(value: 50, child: Text('50 / page')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _rowsPerPage = value > 0 ? value : 10;
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
                              _currentPage = currentPage - 1;
                            });
                          }
                        : null,
                    icon: const Icon(Icons.chevron_left),
                    color: AppColors.textSecondary,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _primaryAqua.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      '$currentPage / $totalPages',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: currentPage < totalPages
                        ? () {
                            setState(() {
                              _currentPage = currentPage + 1;
                            });
                          }
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Search bar - matches patient.dart style
  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13),
        decoration: InputDecoration(
          hintText:
              'Search by name, Patient ID, barangay, risk level, or contact...',
          hintStyle: TextStyle(
            color: const Color(0xFF0F172A).withValues(alpha: 0.5),
            fontSize: 13,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: _primaryAqua.withValues(alpha: 0.8),
            size: 18,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _currentPage = 1;
                    });
                    _scheduleSharedPatientSearch('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
            _currentPage = 1;
          });
          _scheduleSharedPatientSearch(value);
        },
      ),
    );
  }

  Widget _buildFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Primary Filter Bar - Status + Date Range
        Row(
          children: [
            // Status Dropdown Container
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF3FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF2F80ED).withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedStatusFilter,
                    icon: const Icon(
                      Icons.filter_list,
                      color: Color(0xFF2F80ED),
                      size: 20,
                    ),
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    items: _statusFilterOptions.map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedStatusFilter = newValue;
                          _currentPage = 1;
                        });
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Date Range Container
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2F80ED).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF2F80ED).withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.date_range,
                      size: 16,
                      color: Color(0xFF2F80ED),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDatePickerButton(
                        label: 'From',
                        date: _fromDate,
                        onTap: () => _selectDateForPrenatal(true),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildDatePickerButton(
                        label: 'To',
                        date: _toDate,
                        onTap: () => _selectDateForPrenatal(false),
                      ),
                    ),
                    if (_fromDate != null || _toDate != null)
                      IconButton(
                        icon: const Icon(
                          Icons.clear,
                          size: 16,
                          color: Colors.red,
                        ),
                        tooltip: 'Clear dates',
                        onPressed: () {
                          setState(() {
                            _fromDate = null;
                            _toDate = null;
                            _currentPage = 1;
                          });
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Advanced Filters
        _buildPrenatalAdvancedFilters(),
      ],
    );
  }

  Widget _buildPrenatalAdvancedFilters() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double itemWidth = constraints.maxWidth < 700
            ? (constraints.maxWidth - 24) / 2
            : constraints.maxWidth < 1100
            ? (constraints.maxWidth - 48) / 4
            : (constraints.maxWidth - 64) / 5;
        final responsiveWidth = itemWidth.clamp(140.0, 185.0);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _registryDropdown(
                label: 'Barangay',
                value: _selectedBarangay,
                items: const [
                  'All',
                  'Barangay 1',
                  'Barangay 2',
                  'Barangay 3',
                  'Barangay 4',
                  'Barangay 5',
                  'Barangay 6',
                  'Barangay 7',
                  'Barangay 8',
                ],
                width: responsiveWidth,
                onChanged: (val) => setState(() {
                  _selectedBarangay = val ?? 'All';
                  _currentPage = 1;
                }),
              ),
              _registryDropdown(
                label: 'Risk Level',
                value: _selectedRiskLevel,
                items: const [
                  'All',
                  'Active',
                  'High Risk',
                  'Follow Up',
                  'Completed',
                ],
                width: responsiveWidth,
                onChanged: (val) => setState(() {
                  _selectedRiskLevel = val ?? 'All';
                  _currentPage = 1;
                }),
              ),
              _registryDropdown(
                label: 'Age Group',
                value: _selectedAgeGroup,
                items: const ['All', '0–17', '18–34', '35+'],
                width: responsiveWidth,
                onChanged: (val) => setState(() {
                  _selectedAgeGroup = val ?? 'All';
                  _currentPage = 1;
                }),
              ),
              _registryDropdown(
                label: 'Sort By',
                value: _sortField,
                items: const ['Name', 'Registration Date', 'Due Date', 'Age'],
                width: responsiveWidth,
                onChanged: (val) => setState(() {
                  _sortField = val ?? 'Name';
                  _currentPage = 1;
                }),
              ),
              IconButton.filledTonal(
                tooltip: _sortAscending ? 'Ascending' : 'Descending',
                icon: Icon(
                  _sortAscending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 18,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFEDF3FA),
                  foregroundColor: const Color(0xFF2F80ED),
                  padding: const EdgeInsets.all(10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                onPressed: () =>
                    setState(() => _sortAscending = !_sortAscending),
              ),
              if (_selectedBarangay != 'All' ||
                  _selectedRiskLevel != 'All' ||
                  _selectedAgeGroup != 'All' ||
                  _sortField != 'Name' ||
                  !_sortAscending ||
                  _selectedStatusFilter != 'All Cases' ||
                  _fromDate != null ||
                  _toDate != null)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedBarangay = 'All';
                      _selectedRiskLevel = 'All';
                      _selectedAgeGroup = 'All';
                      _sortField = 'Name';
                      _sortAscending = true;
                      _selectedStatusFilter = 'All Cases';
                      _fromDate = null;
                      _toDate = null;
                      _currentPage = 1;
                    });
                  },
                  icon: const Icon(
                    Icons.filter_alt_off_outlined,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                  label: const Text(
                    'Clear Filters',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _registryDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    double width = 140,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$value'),
        initialValue: items.contains(value) ? value : items.first,
        isExpanded: true,
        isDense: true,
        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
          floatingLabelStyle: const TextStyle(
            fontSize: 12,
            color: Color(0xFF2F80ED),
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: Color(0xFF2F80ED), width: 1.5),
          ),
        ),
        items: items
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Text(
                  item,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildDatePickerButton({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF2F80ED).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              date == null ? label : '${date.day}/${date.month}',
              style: TextStyle(
                color: date == null
                    ? const Color(0xFF0F172A).withValues(alpha: 0.6)
                    : const Color(0xFF0F172A),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Icon(
              Icons.calendar_today,
              size: 12,
              color: Color(0xFF2F80ED),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDateForPrenatal(bool isFromDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primaryAqua,
              onPrimary: Colors.white,
              onSurface: _darkDeepTeal,
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
          if (_toDate != null && _toDate!.isBefore(_fromDate!)) {
            _toDate = picked;
          }
        } else {
          _toDate = picked;
        }
        _currentPage = 1;
      });
    }
  }
}

// Helper function for status color
Color _getPrenatalStatusColor(String status) {
  switch (status) {
    case 'High Risk':
      return Colors.red;
    case 'Follow Up':
      return Colors.orange;
    case 'Completed':
      return Colors.green;
    default:
      return _primaryAqua;
  }
}

// Prenatal Card Widget - Checkup style
class _PrenatalCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final bool isSelectionMode;
  final bool isSelected;
  final int index;
  final Function(int, bool) onSelectionChanged;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>)? onView;

  const _PrenatalCard({
    required this.record,
    required this.isSelectionMode,
    required this.isSelected,
    required this.index,
    required this.onSelectionChanged,
    required this.onEdit,
    this.onView,
  });

  String _safe(dynamic value, [String fallback = 'N/A']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: const Color(0xFFD9E5F2),
    );
  }

  Widget _buildIconActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        decoration: BoxDecoration(
          color: color ?? const Color(0xFF163B66),
          borderRadius: BorderRadius.circular(7),
          boxShadow: [
            BoxShadow(
              color: (color ?? const Color(0xFF163B66)).withValues(alpha: 0.25),
              blurRadius: 4,
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
      ),
    );
  }

  String _formatWithUnit(dynamic raw, String unit, [String fallback = 'N/A']) {
    if (raw == null) return fallback;
    var text = raw.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'n/a' || text == '-') {
      return fallback;
    }
    final unitPattern = RegExp(
      '\\s*${RegExp.escape(unit)}\\.?',
      caseSensitive: false,
    );
    text = text.replaceAll(unitPattern, '').trim();
    if (text.isEmpty) return fallback;
    return '$text $unit';
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;

    try {
      final dynamic converted = (value as dynamic).toDate();
      if (converted is DateTime) return converted;
    } catch (_) {}

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

  String _formatDate(dynamic value) {
    final parsed = _parseDateTime(value);
    if (parsed == null) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && !text.toLowerCase().contains('timestamp')) {
        return text;
      }
      return 'N/A';
    }
    return DateFormat('MMMM d, yyyy').format(parsed.toLocal());
  }

  Map<String, String> _formatDateTimeParts(dynamic value) {
    final parsed = _parseDateTime(value);
    if (parsed == null) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && !text.toLowerCase().contains('timestamp')) {
        return {'date': text, 'time': ''};
      }
      return {'date': 'N/A', 'time': ''};
    }
    final local = parsed.toLocal();
    return {
      'date': DateFormat('MMMM d, yyyy').format(local),
      'time': DateFormat('h:mm a').format(local),
    };
  }

  @override
  Widget build(BuildContext context) {
    final rawFirst = record['firstName']?.toString().trim() ?? '';
    final rawSurname = record['surname']?.toString().trim() ?? '';
    final combinedName =
        [rawFirst, rawSurname].where((s) => s.isNotEmpty).join(' ');
    final patientName = combinedName.isNotEmpty
        ? combinedName
        : _safe(
            record['patientName'] ?? record['patient'] ?? record['name'],
            'Unknown Patient',
          );
    final age = _safe(record['age'], 'N/A');
    final patientId = _safe(
      record['patientId'] ?? record['id'] ?? record['linkedPatientId'],
      '-',
    );
    final contactNumber = _safe(
      record['contactNumber'] ?? record['phone'] ?? record['contact'],
    );
    final gestationalAge = _safe(
      record['gestationalAge'] ?? record['aog'],
      'N/A',
    );
    final dueDate = _formatDate(
      record['dueDate'] ?? record['eddDate'] ?? record['edd'],
    );
    final lmpDate = _formatDate(record['lmpDate'] ?? record['lmp']);
    final gravida = _safe(record['gravida'], '');
    final para = _safe(record['para'], '');
    final bp = _safe(record['bp'] ?? record['bloodPressure'], '');
    final weight = _safe(record['wt'] ?? record['weight'], '');
    final fh = _safe(record['fh'] ?? record['fundalHeight'], '');
    final fhb = _safe(
      record['dhb'] ?? record['fetalHeartBeat'] ?? record['fhb'],
      '',
    );
    final weightStr = _formatWithUnit(weight, 'kg');
    final fhStr = _formatWithUnit(fh, 'cm');
    final fhbStr = _formatWithUnit(fhb, 'bpm');
    final status = _safe(record['riskLevel'] ?? record['status'], 'Active');
    final registration = _formatDateTimeParts(
      record['registrationDate'] ??
          record['createdAt'] ??
          record['date'] ??
          record['timestamp'],
    );

    final dateLabel = registration['date'] ?? 'N/A';
    final timeLabel = registration['time'] ?? '';

    final statusColor = _getPrenatalStatusColor(status);
    const rowBg = Colors.white;
    const rowText = Color(0xFF0B1F3A);
    const mutedText = Color(0xFF546E7A);

    return GestureDetector(
      onTap: isSelectionMode
          ? () => onSelectionChanged(index, !isSelected)
          : null,
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
              // 1. Date / Time (flex: 15)
              Expanded(
                flex: 15,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 13,
                            color: _primaryAqua,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              dateLabel,
                              style: const TextStyle(
                                color: rowText,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (timeLabel.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              size: 13,
                              color: mutedText,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              timeLabel,
                              style: const TextStyle(
                                color: mutedText,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              _buildDivider(),

              // 2. Patient Info (flex: 23)
              Expanded(
                flex: 23,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
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
                      const SizedBox(height: 3),
                      Text(
                        'Female • $age yrs',
                        style: const TextStyle(
                          color: mutedText,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (patientId != '-') ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _primaryAqua.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'ID: $patientId',
                                style: const TextStyle(
                                  color: _primaryAqua,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (contactNumber != 'N/A' &&
                              contactNumber.isNotEmpty)
                            Flexible(
                              child: Text(
                                contactNumber,
                                style: const TextStyle(
                                  color: mutedText,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              _buildDivider(),

              // 3. Pregnancy & Gestation (flex: 25)
              Expanded(
                flex: 25,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (gravida.isNotEmpty || para.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF163B66)
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: const Color(0xFF163B66)
                                      .withValues(alpha: 0.2),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                'G$gravida P$para',
                                style: const TextStyle(
                                  color: Color(0xFF163B66),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              gestationalAge != 'N/A'
                                  ? 'AOG: $gestationalAge'
                                  : 'AOG: N/A',
                              style: const TextStyle(
                                color: rowText,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'LMP: $lmpDate',
                        style: const TextStyle(
                          color: mutedText,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'EDD: $dueDate',
                        style: const TextStyle(
                          color: Color(0xFF0B1F3A),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              _buildDivider(),

              // 4. Clinical & Vitals (flex: 21)
              Expanded(
                flex: 21,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.favorite_outline_rounded,
                            size: 13,
                            color: Color(0xFFE53935),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'BP: ${bp.isNotEmpty ? bp : 'N/A'}',
                            style: const TextStyle(
                              color: rowText,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        weightStr != 'N/A'
                            ? 'Weight: $weightStr'
                            : 'Weight: N/A',
                        style: const TextStyle(
                          color: mutedText,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (fhStr != 'N/A' || fhbStr != 'N/A') ...[
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (fhStr != 'N/A') 'FH: $fhStr',
                            if (fhbStr != 'N/A') 'FHB: $fhbStr',
                          ].join(' • '),
                          style: const TextStyle(
                            color: mutedText,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              _buildDivider(),

              // 5. Risk & Status (flex: 16)
              Expanded(
                flex: 16,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 6),
                      WebSyncStatusBadge(record: record),
                    ],
                  ),
                ),
              ),

              // 6. Actions (fixed 140)
              if (!isSelectionMode) ...[
                _buildDivider(),
                SizedBox(
                  width: 140,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildIconActionButton(
                          icon: Icons.visibility_rounded,
                          tooltip: 'View Details',
                          color: const Color(0xFF163B66),
                          onTap: onView != null ? () => onView!(record) : () {},
                        ),
                        const SizedBox(width: 8),
                        _buildIconActionButton(
                          icon: Icons.edit_rounded,
                          tooltip: 'Edit Record',
                          color: _primaryAqua,
                          onTap: () => onEdit(record),
                        ),
                        const SizedBox(width: 8),
                        _buildIconActionButton(
                          icon: Icons.picture_as_pdf_rounded,
                          tooltip: 'Export PDF',
                          color: const Color(0xFFD32F2F),
                          onTap: () => _generatePrenatalPdf(context, record),
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

Future<void> _generatePrenatalPdf(
  BuildContext context,
  Map<String, dynamic> record,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final patientName = '${record['firstName'] ?? ''} ${record['surname'] ?? ''}'
      .trim();

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
    final pdfBytes = await buildPrenatalPdfBytes(record);
    final filename = buildPrenatalPdfFilename(record);
    final downloaded = downloadFile(
      bytes: pdfBytes,
      filename: filename,
      mimeType: 'application/pdf',
    );

    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          downloaded
              ? 'PDF generated for ${patientName.isEmpty ? 'this record' : patientName}.'
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

// Prenatal Dashboard Header Widget - Checkup style
