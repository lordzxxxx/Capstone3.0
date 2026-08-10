import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal_database_helper.dart';
import 'package:mycapstone_project/app/core/services/health_ai_classifier.dart';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/roles/bhw/dashboard/homepage.dart';
import 'package:mycapstone_project/web/roles/bhw/checkups/checkup.dart'
    as checkup_page;
import 'package:mycapstone_project/web/roles/bhw/analytics/health_metrics.dart';
import 'package:mycapstone_project/web/roles/cho/analytics/cho_analytics.dart';
import 'package:mycapstone_project/web/roles/bhw/immunization/immunization.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/communicable.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/non_communicable.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/mortality.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/shared/components/fullscreen_detail_table_dialog.dart';
import 'package:mycapstone_project/web/shared/components/module_view_components.dart';
import 'package:mycapstone_project/web/shared/utils/file_download.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_first_service_selector.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_identity_utils.dart';
import 'package:mycapstone_project/web/shared/utils/prenatal_pdf.dart';
import 'package:mycapstone_project/web/shared/utils/report_generation.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/shared_patient_search_panel.dart';
import 'package:mycapstone_project/shared/current_table_record_utils.dart';
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
  bool _isDeleteDialogShowing = false;
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

  // AI Classifier
  final HealthAIClassifier _aiClassifier = HealthAIClassifier.instance;
  final PatientCenteredHistoryService _patientHistoryService =
      PatientCenteredHistoryService();

  @override
  void initState() {
    super.initState();
    _activeView = healthModuleViewFromUrl();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => persistHealthModuleView('/prenatal', _activeView),
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
    persistHealthModuleView('/prenatal', view);
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
    final records = await _dbHelper.getAllRecords();

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
      drawer: WebAppSidebar(
        userName: userName,
        activeItem: WebSidebarItem.prenatalCare,
      ),
      body: Column(
        children: [
          // Web Header Bar
          _buildWebHeaderBar(context),

          // Content Area
          Expanded(
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
        ],
      ),
    );
  }

  // Drawer Navigation Widget
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
                            color: Colors.white,
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
                  const SizedBox(height: 4),
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
                  _buildSidebarItem(
                    icon: Icons.dashboard_rounded,
                    label: 'Dashboard',
                    onTap: () => Get.to(() => const HomePage()),
                  ),
                  _buildSidebarItem(
                    icon: Icons.assignment_turned_in_rounded,
                    label: 'Check-ups',
                    onTap: () => Get.to(() => const checkup_page.CheckUpPage()),
                  ),
                  _buildSidebarItem(
                    icon: Icons.favorite_rounded,
                    label: 'Summary Generation',
                    onTap: () => Get.to(() => const HealthMetricsPage()),
                  ),
                  _buildSidebarItem(
                    icon: Icons.analytics_rounded,
                    label: 'Analytics',
                    onTap: () => Get.to(() => const AnalyticsPage()),
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
                  _buildSidebarItem(
                    icon: Icons.pregnant_woman_rounded,
                    label: 'Prenatal Care',
                    isActive: true,
                    onTap: () {},
                  ),
                  _buildSidebarItem(
                    icon: Icons.vaccines_rounded,
                    label: 'Immunization',
                    onTap: () => Get.to(() => const ImmunizationPage()),
                  ),
                  _buildSidebarItem(
                    icon: Icons.person_rounded,
                    label: 'Patient Records',
                    onTap: () => Get.to(() => const PatientRecordPage()),
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
                  _buildSidebarItem(
                    icon: Icons.coronavirus_rounded,
                    label: 'Communicable',
                    onTap: () => Get.to(() => const CommunicablePage()),
                  ),
                  _buildSidebarItem(
                    icon: Icons.health_and_safety_rounded,
                    label: 'Non-Communicable',
                    onTap: () => Get.to(() => const NonCommunicablePage()),
                  ),
                  _buildSidebarItem(
                    icon: Icons.analytics_outlined,
                    label: 'Mortality',
                    onTap: () => Get.to(() => const MortalityPage()),
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
                    Get.offAll(() => const Login());
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
          hoverColor: Colors.white.withValues(alpha: 0.08),
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

  Widget _buildWebHeaderBar(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_darkDeepTeal, _darkDeepTeal.withValues(alpha: 0.95)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            color: Colors.white,
            iconSize: 36,
          ),
          const SizedBox(width: 12),
          Text(
            'Prenatal Dashboard',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _generatePrenatalReport,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
            label: const Text(
              'Generate',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          if (_isSelectionMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _primaryAqua.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _primaryAqua, width: 1),
              ),
              child: Text(
                '${_selectedIndices.length} selected',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(width: 12),
          // Three-dots menu for extra actions like seeding sample data
          PopupMenuButton<String>(
            color: _darkDeepTeal,
            icon: Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) async {
              if (value == 'seed_100') {
                await _confirmAndSeedSamples(context);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'seed_100',
                child: Text(
                  'Seed 100 sample records',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _generatePrenatalReport() {
    return generateReportPdf(
      context: context,
      moduleLabel: 'Prenatal',
      records: _getFilteredRecords(),
      dateResolver: (record) =>
          parseReportDateValue(record['registrationDate']) ??
          parseReportDateValue(record['dueDate']),
      columns: [
        ReportCsvColumn(
          'Patient ID',
          (record) => reportText(record['patientId']),
          flex: 0.85,
        ),
        ReportCsvColumn(
          'Patient Name',
          (record) => reportJoin([record['firstName'], record['surname']]),
          flex: 1.35,
        ),
        ReportCsvColumn(
          'Age',
          (record) => reportText(record['age']),
          flex: 0.55,
          center: true,
        ),
        ReportCsvColumn(
          'Registration Date',
          (record) => formatReportDateValue(record['registrationDate']),
          flex: 0.95,
          center: true,
        ),
        ReportCsvColumn(
          'Due Date',
          (record) => formatReportDateValue(record['dueDate']),
          flex: 0.95,
          center: true,
        ),
        ReportCsvColumn(
          'Gestational Age',
          (record) => reportText(record['gestationalAge']),
          flex: 0.85,
          center: true,
        ),
        ReportCsvColumn(
          'Gravida',
          (record) => reportText(record['gravida']),
          flex: 0.5,
          center: true,
        ),
        ReportCsvColumn(
          'Para',
          (record) => reportText(record['para']),
          flex: 0.5,
          center: true,
        ),
        ReportCsvColumn(
          'Risk Level',
          (record) => reportText(record['riskLevel']),
          flex: 0.9,
        ),
        ReportCsvColumn(
          'Status',
          (record) => reportText(record['status']),
          flex: 0.85,
        ),
        ReportCsvColumn(
          'Address / Barangay',
          (record) => reportText(record['address']),
          flex: 1.3,
        ),
        ReportCsvColumn(
          'Remarks',
          (record) => reportText(record['additionalNote']),
          flex: 1.15,
        ),
      ],
      accentColor: _primaryAqua,
      dialogColor: _sidebarDark,
      textColor: Colors.white,
      mutedColor: Colors.white70,
      sectionTitleBuilder: (record, index) =>
          'Record ${index + 1}: ${reportJoin([record['firstName'], record['surname']], fallback: 'Patient')}',
    );
  }

  List<Map<String, dynamic>> _getFilteredRecords() {
    final filtered = _prenatalRecords.where((record) {
      // Status filter
      bool statusMatch = true;
      if (_selectedStatusFilter != 'All Cases') {
        statusMatch = record['status'] == _selectedStatusFilter;
      }

      // Date range filter
      bool dateMatch = true;
      if (_fromDate != null || _toDate != null) {
        try {
          final dueDate = DateTime.parse(record['dueDate'] ?? '');
          if (_fromDate != null && dueDate.isBefore(_fromDate!)) {
            dateMatch = false;
          }
          if (_toDate != null && dueDate.isAfter(_toDate!)) {
            dateMatch = false;
          }
        } catch (e) {
          dateMatch = false;
        }
      }

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final name = (record['patientName'] ?? '').toString().toLowerCase();
        final age = (record['age'] ?? '').toString().toLowerCase();
        final contact = (record['contactNumber'] ?? '')
            .toString()
            .toLowerCase();
        final address = (record['address'] ?? '').toString().toLowerCase();
        if (!name.contains(query) &&
            !age.contains(query) &&
            !contact.contains(query) &&
            !address.contains(query)) {
          return false;
        }
      }

      return statusMatch && dateMatch;
    }).toList();

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

  Future<void> _selectDate(BuildContext context, bool isFromDate) async {
    final DateTime? picked = await showDatePicker(
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

    if (picked != null) {
      setState(() {
        if (isFromDate) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
        _currentPage = 1;
      });
    }
  }

  void _clearDateFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _currentPage = 1;
    });
  }

  // Show AI Classification modal with loading spinner for prenatal records
  Future<void> _showPrenatalAIModal(
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
                    'Analyzing Prenatal Data...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AI is classifying your prenatal record',
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
                      Row(
                        children: [
                          Expanded(
                            child: _prenatalAiInfoCard(
                              icon: Icons.speed_rounded,
                              label: 'Confidence',
                              value:
                                  '${(classification.confidence * 100).toStringAsFixed(1)}%',
                              color: Colors.blueAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _prenatalAiInfoCard(
                              icon: Icons.label_rounded,
                              label: 'Keywords',
                              value:
                                  classification.keywords?.join(', ') ?? 'None',
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
                      foregroundColor: _darkDeepTeal,
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
      if (!mounted || patientSeed == null) return;
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
    final modalTitle = patientSeed == null
        ? 'New Prenatal Registration'
        : 'Add Another Prenatal Visit';

    if (patientSeed != null) {
      final name = patientNameParts(patientSeed);
      firstNameController.text = name.firstName;
      surnameController.text = name.surname;
      ageController.text = (patientSeed['age'] ?? '').toString();
      addressController.text = (patientSeed['address'] ?? '').toString();
      patientIdController.text = (patientSeed['patientId'] ?? '').toString();
      contactNumberController.text = (patientSeed['contactNumber'] ?? '')
          .toString();
      civilStatusController.text = (patientSeed['civilStatus'] ?? '')
          .toString();
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
          (patientSeed['gestationalAge'] ?? patientSeed['aog'] ?? '')
              .toString();
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
      fhController.text =
          (patientSeed['fundalHeight'] ?? patientSeed['fh'] ?? '').toString();
      dhbController.text =
          (patientSeed['fetalHeartBeat'] ?? patientSeed['dhb'] ?? '')
              .toString();
      tcbController.text = (patientSeed['tcb'] ?? '').toString();
      registeredByController.text = (patientSeed['registeredBy'] ?? '')
          .toString();
      additionalNoteController.text =
          (patientSeed['additionalNotes'] ??
                  patientSeed['additionalNote'] ??
                  '')
              .toString();
      lmpDate = _parseDate(patientSeed['lmpDate']);
      eddDate = _parseDate(patientSeed['eddDate'] ?? patientSeed['dueDate']);
      lastDeliveryDate = _parseDate(patientSeed['lastDeliveryDate']);
      registrationDate = DateTime.now();
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
            decoration: BoxDecoration(
              color: _sidebarDark,
              border: Border.all(
                color: _primaryAqua.withValues(alpha: 0.2),
                width: 1.2,
              ),
            ),
            child: Column(
              children: [
                // Modal Header
                Container(
                  height: 86,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 12,
                  ),
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
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              'Maternal assessment and prenatal care planning',
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
                        child: IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ],
                  ),
                ),
                // Form Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Patient Information Area
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
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: surnameController,
                                  label: 'Surname',
                                  icon: Icons.person_outline,
                                  hintText: 'Enter surname',
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
                        const SizedBox(height: 14),

                        // Pregnancy Detail Area
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
                            dark: true,
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
                            dark: true,
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
                                setModalState(() => lastDeliveryDate = picked);
                              }
                            },
                            dark: true,
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
                                setModalState(() => selectedRiskLevel = value);
                              }
                            },
                            dark: true,
                          ),
                        ]),
                        const SizedBox(height: 14),

                        // Medical History Area
                        _buildSectionHeader(
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
                            hintText: 'e.g., Diabetes, Hypertension, Asthma',
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
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: wtController,
                                  label: 'WT (Weight)',
                                  icon: Icons.monitor_weight,
                                  hintText: 'e.g., 65 kg',
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
                                  hintText: 'e.g., 36.5Â°C',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: bpController,
                                  label: 'BP (Blood Pressure)',
                                  icon: Icons.favorite,
                                  hintText: 'e.g., 120/80',
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
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: fhController,
                                  label: 'FH (Fundal Height)',
                                  icon: Icons.straighten,
                                  hintText: 'e.g., 28 cm',
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
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: atController,
                                  label: 'AT (Abdominal Tenderness)',
                                  icon: Icons.touch_app,
                                  hintText: 'e.g., None, Mild',
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
                          ),
                        ]),
                        const SizedBox(height: 14),

                        // Registration Details Area
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
                                setModalState(() => registrationDate = picked);
                              }
                            },
                            dark: true,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: registeredByController,
                            label: 'Registered By',
                            icon: Icons.person_pin,
                            hintText: 'Enter staff name or ID',
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: additionalNoteController,
                            label: 'Additional Note',
                            icon: Icons.note,
                            hintText: 'Enter any additional notes or remarks',
                            maxLines: 4,
                          ),
                        ]),
                        const SizedBox(height: 32),

                        // Submit Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              // Create new prenatal record
                              final newRecord = {
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
                                'additionalNote': additionalNoteController.text,
                                'gestationalAge': aogController.text,
                                'dueDate': eddDate?.toIso8601String() ?? '',
                                'status': selectedRiskLevel,
                              };

                              // AI Classification
                              ClassificationResult? classification;
                              try {
                                print(
                                  'ðŸ¤– [AI] Starting prenatal classification...',
                                );
                                classification = await _aiClassifier.classify(
                                  newRecord,
                                );
                                print(
                                  'âœ… [AI] Prenatal classification complete: ${classification.category}',
                                );

                                newRecord['ai_category'] =
                                    classification.category;
                                newRecord['ai_severity'] =
                                    classification.severity;
                                newRecord['ai_confidence'] = classification
                                    .confidence
                                    .toString();
                                newRecord['ai_method'] = classification.method;
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
                                print(
                                  'âŒ AI prenatal classification failed: $e',
                                );
                              }

                              // Save to database (offline + Firebase sync)
                              await _dbHelper.insertRecord(newRecord);

                              // Reload records
                              await _loadRecords();

                              // Show AI Classification modal with loading spinner
                              if (context.mounted && classification != null) {
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
                                  SnackBar(
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
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryAqua,
                              foregroundColor: _darkDeepTeal,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            child: const Text(
                              'Register Prenatal Patient',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
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

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Dialog.fullscreen(
          backgroundColor: _darkDeepTeal,
          child: Scaffold(
            backgroundColor: _darkDeepTeal,
            appBar: AppBar(
              backgroundColor: _sidebarDark,
              foregroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                tooltip: 'Close editor',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Edit Prenatal Record',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Update maternal information and prenatal observations',
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final button = updateButtonKey.currentWidget;
                      if (button is ElevatedButton) {
                        button.onPressed?.call();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryAqua,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save Changes'),
                  ),
                ),
              ],
            ),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Form Content - Complete form with ALL fields
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Patient Information Section
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
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: surnameController,
                                  label: 'Surname',
                                  icon: Icons.person,
                                  hintText: 'Enter surname',
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
                        const SizedBox(height: 14),

                        // Pregnancy Detail Section
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
                                setModalState(() => lastDeliveryDate = picked);
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
                                setModalState(() => selectedRiskLevel = value);
                              }
                            },
                          ),
                        ]),
                        const SizedBox(height: 14),

                        // Medical History Section
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
                            hintText: 'e.g., Diabetes, Hypertension, Asthma',
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
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: wtController,
                                  label: 'WT (Weight)',
                                  icon: Icons.monitor_weight,
                                  hintText: 'e.g., 65 kg',
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
                                  hintText: 'e.g., 36.5Â°C',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: bpController,
                                  label: 'BP (Blood Pressure)',
                                  icon: Icons.favorite,
                                  hintText: 'e.g., 120/80',
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
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: fhController,
                                  label: 'FH (Fundal Height)',
                                  icon: Icons.straighten,
                                  hintText: 'e.g., 28 cm',
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
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: atController,
                                  label: 'AT (Abdominal Tenderness)',
                                  icon: Icons.touch_app,
                                  hintText: 'e.g., None, Mild',
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
                          ),
                        ]),
                        const SizedBox(height: 14),

                        // Registration Details Section
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
                                setModalState(() => registrationDate = picked);
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: registeredByController,
                            label: 'Registered By',
                            icon: Icons.person_pin,
                            hintText: 'Enter staff name or ID',
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: additionalNoteController,
                            label: 'Additional Note',
                            icon: Icons.note,
                            hintText: 'Enter any additional notes or remarks',
                            maxLines: 4,
                          ),
                        ]),
                        const SizedBox(height: 32),

                        Offstage(
                          offstage: true,
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              key: updateButtonKey,
                              onPressed: () async {
                                // Update prenatal record
                                final updatedRecord = {
                                  'id': record['id'], // Keep original ID
                                  'patientName':
                                      '${firstNameController.text} ${surnameController.text}',
                                  'age': ageController.text,
                                  'address': addressController.text,
                                  'patientId': patientIdController.text,
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

                                // AI Classification on edited record
                                ClassificationResult? classification;
                                try {
                                  print(
                                    'ðŸ¤– [AI] Starting prenatal re-classification...',
                                  );
                                  classification = await _aiClassifier.classify(
                                    updatedRecord,
                                  );
                                  print(
                                    'âœ… [AI] Prenatal re-classification complete: ${classification.category}',
                                  );

                                  updatedRecord['ai_category'] =
                                      classification.category;
                                  updatedRecord['ai_severity'] =
                                      classification.severity;
                                  updatedRecord['ai_confidence'] =
                                      classification.confidence.toString();
                                  updatedRecord['ai_method'] =
                                      classification.method;
                                  if (classification.keywords != null) {
                                    updatedRecord['ai_keywords'] =
                                        classification.keywords!.join(', ');
                                  }
                                  if (classification.recoveryPlan != null) {
                                    updatedRecord['ai_recovery_plan'] =
                                        jsonEncode(classification.recoveryPlan);
                                  }
                                } catch (e) {
                                  print(
                                    'âŒ AI prenatal re-classification failed: $e',
                                  );
                                }

                                // Update in database
                                final id = record['id']?.toString() ?? '';
                                if (id.isNotEmpty) {
                                  await _dbHelper.updateRecord(
                                    id,
                                    updatedRecord,
                                  );
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
                                      SnackBar(
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
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error: Record ID not found',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryAqua,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                              child: const Text(
                                'Update Prenatal Record',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
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
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  // Dark themed form card for modals that should remain dark
  Widget _buildDarkFormCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children.map((w) {
          return DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white),
            child: IconTheme.merge(
              data: const IconThemeData(color: Colors.white70),
              child: w,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
              fontWeight: FontWeight.normal,
            ),
            prefixIcon: Icon(icon, color: Colors.white, size: 20),
            filled: true,
            fillColor: const Color(0xFF0B1F3A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _primaryAqua, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
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
    bool dark = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: dark ? Colors.white : _mutedCoolGray,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: dark ? _darkDeepTeal : _lightOffWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: date != null
                    ? _primaryAqua
                    : (dark
                          ? Colors.white.withValues(alpha: 0.2)
                          : _mutedCoolGray.withValues(alpha: 0.3)),
                width: date != null ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: dark ? Colors.white : _primaryAqua, size: 20),
                const SizedBox(width: 12),
                Text(
                  date != null
                      ? '${date.day}/${date.month}/${date.year}'
                      : 'Select Date',
                  style: TextStyle(
                    color: dark
                        ? Colors.white
                        : (date != null ? _darkDeepTeal : _mutedCoolGray),
                    fontSize: 14,
                    fontWeight: date != null
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
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
    bool dark = false,
  }) {
    final dropdownItems = _uniqueDropdownItems(items);
    final safeValue = _resolveDropdownValue(value, dropdownItems);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: dark ? Colors.white : _mutedCoolGray,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: dark ? _darkDeepTeal : _lightOffWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: dark
                  ? Colors.white.withValues(alpha: 0.2)
                  : _mutedCoolGray.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: dark ? Colors.white : _primaryAqua, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: safeValue,
                    isExpanded: true,
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: dark ? Colors.white : _primaryAqua,
                    ),
                    style: TextStyle(
                      color: dark ? Colors.white : _darkDeepTeal,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    items: dropdownItems.map((String item) {
                      return DropdownMenuItem<String>(
                        value: item,
                        child: Text(item),
                      );
                    }).toList(),
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDateFilter() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Gradient Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _primaryAqua.withValues(alpha: 0.1),
                  _secondaryIceBlue.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_primaryAqua, _secondaryIceBlue],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: _primaryAqua.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.filter_alt_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Filter & Search',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _darkDeepTeal,
                  ),
                ),
              ],
            ),
          ),

          // Filter Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Status Filter
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _lightOffWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _primaryAqua.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.filter_list_rounded,
                        color: _primaryAqua,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedStatusFilter,
                            isExpanded: true,
                            icon: Icon(
                              Icons.arrow_drop_down,
                              color: _primaryAqua,
                            ),
                            style: TextStyle(
                              color: _darkDeepTeal,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            items: _statusFilterOptions.map((String option) {
                              return DropdownMenuItem<String>(
                                value: option,
                                child: Text(option),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedStatusFilter = newValue;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Date Range Header
                Row(
                  children: [
                    Icon(
                      Icons.date_range_rounded,
                      color: _primaryAqua,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Due Date Range',
                      style: TextStyle(
                        color: _darkDeepTeal,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (_fromDate != null || _toDate != null)
                      InkWell(
                        onTap: _clearDateFilters,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.clear, size: 14, color: Colors.red),
                              const SizedBox(width: 4),
                              Text(
                                'Clear',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildDatePickerButton(
                        context: context,
                        label: 'From Date',
                        date: _fromDate,
                        isFromDate: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDatePickerButton(
                        context: context,
                        label: 'To Date',
                        date: _toDate,
                        isFromDate: false,
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

  Widget _buildDatePickerButton({
    required BuildContext context,
    required String label,
    required DateTime? date,
    required bool isFromDate,
  }) {
    return InkWell(
      onTap: () => _selectDate(context, isFromDate),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _lightOffWhite,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: date != null
                ? _primaryAqua
                : _mutedCoolGray.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: _mutedCoolGray,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: date != null ? _primaryAqua : _mutedCoolGray,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    date != null
                        ? '${date.day}/${date.month}/${date.year}'
                        : 'Select Date',
                    style: TextStyle(
                      color: date != null ? _darkDeepTeal : _mutedCoolGray,
                      fontSize: 13,
                      fontWeight: date != null
                          ? FontWeight.bold
                          : FontWeight.normal,
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

  // Web-oriented Dashboard Card for larger screens
  Widget _buildWebDashboardCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _darkDeepTeal.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: color.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Active',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: _mutedCoolGray,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // Web Filter Bar - Horizontal layout for desktop
  Widget _buildWebFilterBar() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: _darkDeepTeal.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _primaryAqua.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.filter_list_rounded, color: _primaryAqua, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedStatusFilter,
                      isExpanded: true,
                      icon: Icon(
                        Icons.arrow_drop_down,
                        color: _primaryAqua,
                        size: 20,
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      dropdownColor: _darkDeepTeal,
                      items: _statusFilterOptions.map((String option) {
                        return DropdownMenuItem<String>(
                          value: option,
                          child: Text(option),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() => _selectedStatusFilter = newValue);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        InkWell(
          onTap: () => _selectDate(context, true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _fromDate != null
                  ? _primaryAqua.withValues(alpha: 0.2)
                  : _darkDeepTeal.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _fromDate != null
                    ? _primaryAqua
                    : _mutedCoolGray.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today, color: _primaryAqua, size: 16),
                const SizedBox(width: 6),
                Text(
                  _fromDate != null
                      ? '${_fromDate!.day}/${_fromDate!.month}'
                      : 'From',
                  style: TextStyle(
                    color: _fromDate != null ? _primaryAqua : _mutedCoolGray,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: () => _selectDate(context, false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _toDate != null
                  ? _primaryAqua.withValues(alpha: 0.2)
                  : _darkDeepTeal.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _toDate != null
                    ? _primaryAqua
                    : _mutedCoolGray.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today, color: _primaryAqua, size: 16),
                const SizedBox(width: 6),
                Text(
                  _toDate != null ? '${_toDate!.day}/${_toDate!.month}' : 'To',
                  style: TextStyle(
                    color: _toDate != null ? _primaryAqua : _mutedCoolGray,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_fromDate != null || _toDate != null) ...[
          const SizedBox(width: 8),
          InkWell(
            onTap: _clearDateFilters,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.red.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Icon(Icons.clear, color: Colors.red, size: 18),
            ),
          ),
        ],
      ],
    );
  }

  // Web Data Table view for patients - Card layout instead of DataTable
  Widget _buildPatientsDataTable() {
    final records = _getFilteredRecords();

    if (records.isEmpty) {
      return Center(
        child: Text(
          'No records found.',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    }

    return Column(
      children: List.generate(records.length, (index) {
        final isSelected = _selectedIndices.contains(index);
        return _PrenatalCard(
          record: records[index],
          isSelectionMode: _isSelectionMode,
          isSelected: isSelected,
          index: index,
          onSelectionChanged: (idx, selected) {
            setState(() {
              if (selected) {
                _selectedIndices.add(idx);
              } else {
                _selectedIndices.remove(idx);
              }
            });
          },
          onEdit: (record) => _showEditPrenatalModal(context, record),
          onView: (record) => _onViewButtonPressed(context, record),
        );
      }),
    );
  }

  Color _getStatusColor(String status) {
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

  void _showDeleteConfirm(
    BuildContext context,
    int index,
    Map<String, dynamic> record,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Delete prenatal record for ${record['patientName']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final id = record['id']?.toString() ?? '';
              if (id.isNotEmpty) {
                await _dbHelper.deleteRecord(id);
                await _loadRecords();
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String trend,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: color.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  trend,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              color: _mutedCoolGray,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientCard({
    required BuildContext context,
    required int index,
    required Map<String, dynamic> record,
  }) {
    final isSelected = _selectedIndices.contains(index);
    final patientName = record['patientName'] ?? 'Unknown';
    final nameParts = patientName.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts[0] : 'N/A';
    final surname = nameParts.length > 1
        ? nameParts.sublist(1).join(' ')
        : 'N/A';
    final gestationalAge = record['gestationalAge'] ?? 'N/A';
    final dueDate = record['dueDate'] ?? 'N/A';
    final status = record['status'] ?? 'Active';
    final age = record['age'] ?? 'N/A';
    final address = record['address'] ?? 'N/A';
    final contactNumber = record['contactNumber'] ?? 'N/A';
    final riskLevel = record['riskLevel'] ?? status;

    return GestureDetector(
      onTap: _isSelectionMode
          ? () {
              setState(() {
                if (isSelected) {
                  _selectedIndices.remove(index);
                } else {
                  _selectedIndices.add(index);
                }
              });
            }
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? _primaryAqua
                : _primaryAqua.withValues(alpha: 0.2),
            width: isSelected ? 2.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? _primaryAqua.withValues(alpha: 0.2)
                  : _mutedCoolGray.withValues(alpha: 0.08),
              blurRadius: isSelected ? 12 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Patient Name Header with Checkbox
              Row(
                children: [
                  if (_isSelectionMode) ...[
                    Checkbox(
                      value: isSelected,
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            _selectedIndices.add(index);
                          } else {
                            _selectedIndices.remove(index);
                          }
                        });
                      },
                      activeColor: _primaryAqua,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.pregnant_woman,
                      color: _primaryAqua,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      patientName,
                      style: TextStyle(
                        color: _darkDeepTeal,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildStatusChip(status),
                ],
              ),
              const SizedBox(height: 16),

              // Patient Details
              Row(
                children: [
                  Expanded(
                    child: _buildInfoRow(
                      icon: Icons.person_outline,
                      label: 'First Name',
                      value: firstName,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInfoRow(
                      icon: Icons.person,
                      label: 'Surname',
                      value: surname,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoRow(
                      icon: Icons.cake,
                      label: 'Age',
                      value: age,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInfoRow(
                      icon: Icons.location_on,
                      label: 'Address',
                      value: address,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Action Buttons
              if (!_isSelectionMode)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _onViewButtonPressed(context, record),
                        icon: Icon(Icons.visibility, size: 18),
                        label: Text(
                          'View History',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryAqua,
                          foregroundColor: _darkDeepTeal,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _showEditPrenatalModal(context, record);
                        },
                        icon: Icon(Icons.edit, size: 18),
                        label: Text(
                          'Edit',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _secondaryIceBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
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
            Icon(icon, size: 16, color: _mutedCoolGray),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: _mutedCoolGray,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: _darkDeepTeal,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String status) {
    Color statusColor;
    switch (status) {
      case 'Active':
        statusColor = Colors.green;
        break;
      case 'Follow Up':
        statusColor = Colors.orange;
        break;
      case 'High Risk':
        statusColor = Colors.red;
        break;
      case 'Completed':
        statusColor = Colors.blue;
        break;
      default:
        statusColor = _mutedCoolGray;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: statusColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

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
    final statusColor = _getStatusColor(riskLevel);
    final initials = nameParts
        .where((part) => part.trim().isNotEmpty)
        .take(2)
        .map((part) => part.trim().substring(0, 1).toUpperCase())
        .join();

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

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.74),
      builder: (dialogContext) {
        final screenSize = MediaQuery.of(dialogContext).size;
        final isCompact = screenSize.width < 760;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: SizedBox(
            width: screenSize.width,
            height: screenSize.height,
            child: Container(
              decoration: BoxDecoration(
                color: _darkDeepTeal,
                border: Border.all(
                  color: _primaryAqua.withValues(alpha: 0.16),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 36,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: ClipRect(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: EdgeInsets.all(isCompact ? 20 : 24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _sidebarDark,
                              _secondaryIceBlue.withValues(alpha: 0.88),
                              _primaryAqua.withValues(alpha: 0.72),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      initials.isEmpty ? 'PN' : initials,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        patientName,
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Prenatal record overview with patient profile, pregnancy details, risk indicators, and registration history.',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.74,
                                          ),
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          height: 1.38,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () =>
                                        Navigator.of(dialogContext).pop(),
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.12,
                                          ),
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    statusColor.withValues(alpha: 0.18),
                                    Colors.white.withValues(alpha: 0.04),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(
                                        alpha: 0.16,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      Icons.pregnant_woman_rounded,
                                      color: statusColor,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Current prenatal status',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'This case is tagged as $riskLevel with a current record status of $status.',
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.7,
                                            ),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      riskLevel,
                                      style: TextStyle(
                                        color: statusColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _buildPrenatalDetailMetaChip(
                                  icon: Icons.badge_outlined,
                                  label: 'Patient ID',
                                  value: patientId,
                                  accentColor: const Color(0xFF64B5F6),
                                ),
                                _buildPrenatalDetailMetaChip(
                                  icon: Icons.timelapse_rounded,
                                  label: 'Gestational Age',
                                  value: gestationalAge,
                                  accentColor: const Color(0xFFFFB74D),
                                ),
                                _buildPrenatalDetailMetaChip(
                                  icon: Icons.event_available_outlined,
                                  label: 'Due Date',
                                  value: dueDate,
                                  accentColor: const Color(0xFF81C784),
                                ),
                                _buildPrenatalDetailMetaChip(
                                  icon: Icons.phone_outlined,
                                  label: 'Contact',
                                  value: contactNumber,
                                  accentColor: const Color(0xFFE57373),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(isCompact ? 18 : 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailSectionDark('Personal Information', [
                              _buildDetailRowDark('First Name', firstName),
                              _buildDetailRowDark('Surname', surname),
                              _buildDetailRowDark(
                                'Patient ID',
                                record['patientId'],
                              ),
                              _buildDetailRowDark('Age', record['age']),
                              _buildDetailRowDark('Address', record['address']),
                              _buildDetailRowDark(
                                'Contact Number',
                                record['contactNumber'],
                              ),
                              _buildDetailRowDark(
                                'Civil Status',
                                record['civilStatus'],
                              ),
                              _buildDetailRowDark(
                                'Religion',
                                record['religion'],
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildDetailSectionDark('Philhealth Information', [
                              _buildDetailRowDark(
                                'Philhealth Number',
                                record['philhealthNumber'],
                              ),
                              _buildDetailRowDark(
                                'Philhealth Member',
                                record['philhealthMember'],
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildDetailSectionDark('Pregnancy Details', [
                              _buildDetailRowDark(
                                'Gestational Age',
                                record['gestationalAge'],
                              ),
                              _buildDetailRowDark(
                                'LMP Date',
                                _formatDate(record['lmpDate']),
                              ),
                              _buildDetailRowDark(
                                'EDD Date',
                                _formatDate(record['eddDate']),
                              ),
                              _buildDetailRowDark(
                                'Due Date',
                                _formatDate(record['dueDate']),
                              ),
                              _buildDetailRowDark(
                                'Last Delivery',
                                _formatDate(record['lastDeliveryDate']),
                              ),
                              _buildDetailRowDark('Gravida', record['gravida']),
                              _buildDetailRowDark('Para', record['para']),
                              _buildDetailRowDark(
                                'Risk Level',
                                record['riskLevel'],
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildDetailSectionDark('Medical History', [
                              _buildDetailRowDark(
                                'Blood Type',
                                record['bloodType'],
                              ),
                              _buildDetailRowDark(
                                'Allergies',
                                record['allergies'],
                              ),
                              _buildDetailRowDark(
                                'Pre-existing Conditions',
                                record['preExistingConditions'],
                              ),
                              _buildDetailRowDark(
                                'Previous Complications',
                                record['previousComplications'],
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildDetailSectionDark(
                              'Vital Signs & Measurements',
                              [
                                _buildDetailRowDark(
                                  'Age of Gestation (AOG)',
                                  record['aog'],
                                ),
                                _buildDetailRowDark(
                                  'Weight (WT)',
                                  record['wt'],
                                ),
                                _buildDetailRowDark(
                                  'Abdominal Tenderness (AT)',
                                  record['at'],
                                ),
                                _buildDetailRowDark(
                                  'Temperature',
                                  record['temp'],
                                ),
                                _buildDetailRowDark(
                                  'Blood Pressure (BP)',
                                  record['bp'],
                                ),
                                _buildDetailRowDark('BMI', record['bmi']),
                                _buildDetailRowDark(
                                  'Fundal Height (FH)',
                                  record['fh'],
                                ),
                                _buildDetailRowDark(
                                  'Fetal Heart Beat (DHB)',
                                  record['dhb'],
                                ),
                                _buildDetailRowDark(
                                  'Total Bilirubin (TCB)',
                                  record['tcb'],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildDetailSectionDark('Registration Details', [
                              _buildDetailRowDark(
                                'Registration Date',
                                _formatDate(record['registrationDate']),
                              ),
                              _buildDetailRowDark(
                                'Registered By',
                                record['registeredBy'],
                              ),
                              _buildDetailRowDark('Status', record['status']),
                            ]),
                            if (record['additionalNote'] != null &&
                                record['additionalNote']
                                    .toString()
                                    .isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _buildDetailSectionDark('Additional Notes', [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _darkDeepTeal,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    record['additionalNote'] ?? '',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ]),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.fromLTRB(
                          isCompact ? 18 : 22,
                          10,
                          isCompact ? 18 : 22,
                          isCompact ? 18 : 22,
                        ),
                        decoration: BoxDecoration(
                          color: _sidebarDark.withValues(alpha: 0.82),
                          border: Border(
                            top: BorderSide(
                              color: Colors.white.withValues(alpha: 0.06),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.03,
                                ),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.16),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text('Close'),
                            ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [_primaryAqua, _secondaryIceBlue],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: _primaryAqua.withValues(alpha: 0.22),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  Navigator.of(dialogContext).pop();
                                  await _generatePrenatalPdf(context, record);
                                },
                                icon: const Icon(
                                  Icons.picture_as_pdf_rounded,
                                  size: 18,
                                ),
                                label: const Text('Generate PDF'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 15,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
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
          ),
        );
      },
    );
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
    if (!mounted) {
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

  Future<void> _confirmAndSeedSamples(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seed Sample Data'),
        content: const Text(
          'Insert 100 complete sample prenatal records into the database?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Seed'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _seedSampleData(context);
    }
  }

  Future<void> _seedSampleData(BuildContext context) async {
    // Show progress dialog
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _darkDeepTeal,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(color: _primaryAqua),
                SizedBox(height: 12),
                Text(
                  'Seeding 100 records...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final now = DateTime.now();
      for (var i = 1; i <= 100; i++) {
        final idSuffix = i.toString().padLeft(3, '0');
        final ms = now.millisecondsSinceEpoch.toString();
        final shortMs = ms.substring(
          ms.length - 6,
        ); // use last 6 digits for readability
        final uniqueCode = 'SMP$shortMs${i.toString().padLeft(3, '0')}';
        final lmp = now.subtract(Duration(days: 14 * (i % 6) + i));
        final edd = lmp.add(const Duration(days: 280));
        final registration = now.subtract(Duration(days: i % 30));

        final sample = {
          'patientName': 'Sample Patient $uniqueCode',
          'age': (20 + (i % 15)).toString(),
          'address': '123 Sample Street, Barangay ${(i % 20) + 1}, Cityville',
          'patientId': 'PAT-$uniqueCode',
          'contactNumber': '+63 900 $shortMs${i.toString().padLeft(3, '0')}',
          'civilStatus': i % 2 == 0 ? 'Married' : 'Single',
          'religion': 'Religion ${i % 5 + 1}',
          'philhealthNumber': 'PH-${now.year}-$uniqueCode',
          'philhealthMember': 'Member $uniqueCode',
          'lmpDate': lmp.toIso8601String(),
          'eddDate': edd.toIso8601String(),
          'lastDeliveryDate': lmp
              .subtract(const Duration(days: 365))
              .toIso8601String(),
          'gravida': ((i % 4) + 1).toString(),
          'para': (i % 3).toString(),
          'riskLevel': (i % 10 == 0)
              ? 'High Risk'
              : (i % 3 == 0)
              ? 'Follow Up'
              : 'Active',
          'bloodType': ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+'][i % 7],
          'allergies': 'None',
          'preExistingConditions': 'None',
          'previousComplications': 'None',
          'aog': '${(i % 40) + 1} weeks',
          'wt': '${50 + (i % 20)} kg',
          'at': 'None',
          'temp': '36.${i % 9}Â°C',
          'bp': '${110 + (i % 30)}/${70 + (i % 10)}',
          'bmi': '${18 + (i % 10)}',
          'fh': '${20 + (i % 12)} cm',
          'dhb': '${120 + (i % 40)} bpm',
          'tcb': '${0.5 + (i % 5) * 0.1}',
          'registrationDate': registration.toIso8601String(),
          'registeredBy': 'Seeder',
          'additionalNote': 'Auto-generated sample record #$idSuffix',
          'gestationalAge': '${(i % 40) + 1} weeks',
          'dueDate': edd.toIso8601String(),
          'status': (i % 10 == 0) ? 'High Risk' : 'Active',
        };

        await _dbHelper.insertRecord(sample);
      }

      await _loadRecords();
      if (context.mounted) {
        Navigator.of(context).pop(); // close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seeded 100 sample prenatal records'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Seeding failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header with Icon
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.info_outline, color: _primaryAqua, size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _darkDeepTeal,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _primaryAqua.withValues(alpha: 0.15),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: _mutedCoolGray.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: _mutedCoolGray,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              value?.toString() ?? 'N/A',
              style: TextStyle(
                color: _darkDeepTeal,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _safePrenatalDetailText(
    dynamic value, {
    String fallback = 'Not recorded',
  }) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  Widget _buildPrenatalDetailMetaChip({
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

  Widget _buildSectionHeaderDark(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _primaryAqua.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _primaryAqua, size: 20),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRowDark(
    String label,
    dynamic value, {
    IconData icon = Icons.info_outline_rounded,
  }) {
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
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _safePrenatalDetailText(value),
                    style: const TextStyle(
                      color: Colors.white,
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

  Widget _buildDetailSectionDark(String title, List<Widget> children) {
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
                    child: const Icon(
                      Icons.info_outline_rounded,
                      color: _primaryAqua,
                      size: 20,
                    ),
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

  String _formatDate(dynamic date) {
    if (date == null || date.toString().isEmpty) return 'N/A';
    try {
      final dateTime = DateTime.parse(date.toString());
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return date.toString();
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

    setState(() {
      _isDeleteDialogShowing = true;
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            const SizedBox(width: 8),
            Text('Confirm Delete'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${_selectedIndices.length} selected record(s)? This action cannot be undone.',
          style: TextStyle(color: _darkDeepTeal),
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
                color: _mutedCoolGray,
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
    await _dbHelper.deleteRecords(idsToDelete);

    setState(() {
      _selectedIndices.clear();
      _isSelectionMode = false;
    });

    // Reload records
    await _loadRecords();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Successfully deleted $count record(s)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
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
        subtitle: 'Visits recorded during the last six months',
        icon: Icons.show_chart_rounded,
        child: _buildPrenatalMonthlyLineChart(),
      ),
      _buildPrenatalChartCard(
        title: 'Pregnancy Risk Distribution',
        subtitle: 'Current maternal risk classification',
        icon: Icons.health_and_safety_outlined,
        child: _buildPrenatalRiskPieChart(),
      ),
      _buildPrenatalChartCard(
        title: 'High-Risk Pregnancies by Barangay',
        subtitle: 'Location of records requiring closer monitoring',
        icon: Icons.location_on_outlined,
        child: _buildPrenatalBarChart(
          _highRiskByBarangay(),
          emptyMessage: 'No high-risk pregnancies are currently recorded.',
          tooltipUnit: 'case',
          colors: const [Color(0xFFB3261E), Color(0xFFFF6B61)],
        ),
      ),
      _buildPrenatalChartCard(
        title: 'Gestational Age Distribution',
        subtitle: 'Pregnancies grouped by trimester',
        icon: Icons.calendar_view_month_rounded,
        child: _buildPrenatalBarChart(
          _gestationalAgeDistribution(),
          emptyMessage: 'Gestational-age data has not been recorded yet.',
          tooltipUnit: 'pregnancy',
          colors: const [Color(0xFF5B5FEF), Color(0xFF9B8AFB)],
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
        subtitle: 'Prenatal patients grouped by maternal age',
        icon: Icons.groups_2_outlined,
        child: _buildPrenatalBarChart(
          _maternalAgeDistribution(),
          emptyMessage: 'Maternal-age data has not been recorded yet.',
          tooltipUnit: 'patient',
          colors: const [Color(0xFF008895), Color(0xFF35D4DE)],
        ),
      ),
      _buildPrenatalChartCard(
        title: 'Pregnancy Complications',
        subtitle: 'Most frequently recorded previous complications',
        icon: Icons.monitor_heart_outlined,
        child: _buildPrenatalBarChart(
          _pregnancyComplicationDistribution(),
          emptyMessage: 'No pregnancy complications are currently recorded.',
          tooltipUnit: 'case',
          colors: const [Color(0xFFCC6B00), Color(0xFFFFB547)],
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                title: 'Total Prenatal',
                value: '$total',
                icon: Icons.pregnant_woman_rounded,
                color: _primaryAqua,
              ),
              _buildWebMetricCard(
                title: 'Active',
                value: '$active',
                icon: Icons.favorite_rounded,
                color: const Color(0xFF4CAF50),
              ),
              _buildWebMetricCard(
                title: 'High Risk',
                value: '$highRisk',
                icon: Icons.warning_rounded,
                color: const Color(0xFFFF9800),
              ),
              _buildWebMetricCard(
                title: 'Completed',
                value: '$completed',
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF2196F3),
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
    return CurrentTableRecordUtils.collapseToLatestPerEntity(
      _prenatalRecords,
      idKeys: const ['linkedPatientId', 'patientId', 'patientCode'],
      nameKeys: const ['patientName', 'patient'],
      dateKeys: const ['registrationDate', 'updatedAt', 'createdAt'],
    );
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
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _primaryAqua.withValues(alpha: 0.28),
                  _primaryAqua.withValues(alpha: 0.02),
                ],
              ),
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
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: colors,
                ),
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
      'High Risk': Color(0xFFEF5350),
      'Follow Up': Color(0xFFFFB547),
      'Active': Color(0xFF35C58A),
      'Completed': Color(0xFF4AA3FF),
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
      const [Color(0xFF35C58A), Color(0xFF39545A)],
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
        border: Border.all(
          color: const Color(0xFFFFB547).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.notification_important_outlined,
                color: Color(0xFFFFB547),
              ),
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
                color: const Color(0xFF35C58A).withValues(alpha: 0.08),
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
              final color = highRisk
                  ? const Color(0xFFEF5350)
                  : const Color(0xFFFFB547);
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

  // Metric card - matches patient.dart dark style with hover shadow
  Widget _buildWebMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: color.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Live',
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF4B6075),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
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
            gradient: const LinearGradient(
              colors: [Color(0xFF00E5FF), Color(0xFF2F80ED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
                blurRadius: 14,
                spreadRadius: 1.5,
                offset: const Offset(0, 5),
              ),
            ],
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
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00E5FF).withValues(alpha: 0.18),
            _primaryAqua.withValues(alpha: 0.2),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.55),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.18),
            blurRadius: 14,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _buildHighlightedPrenatalAddButton(context),
    );
  }

  Widget _buildPrenatalCardHeader() {
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
          _buildPrenatalHeaderCell('Date/Time', flex: 14),
          _buildPrenatalHeaderDivider(),
          _buildPrenatalHeaderCell('Type', flex: 22),
          _buildPrenatalHeaderDivider(),
          _buildPrenatalHeaderCell('Patient', flex: 26),
          _buildPrenatalHeaderDivider(),
          _buildPrenatalHeaderCell('Assessment', flex: 42),
          if (!_isSelectionMode) ...[
            _buildPrenatalHeaderDivider(),
            const SizedBox(
              width: 112,
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
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
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

          // Filters row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Status filter dropdown
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _darkDeepTeal,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _primaryAqua.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.filter_list_rounded,
                          color: _primaryAqua,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedStatusFilter,
                              isExpanded: true,
                              icon: Icon(
                                Icons.arrow_drop_down,
                                color: _primaryAqua,
                                size: 20,
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              dropdownColor: _darkDeepTeal,
                              items: _statusFilterOptions.map((String option) {
                                return DropdownMenuItem<String>(
                                  value: option,
                                  child: Text(option),
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
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // From date
                InkWell(
                  onTap: () => _selectDate(context, true),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _fromDate != null
                          ? _primaryAqua.withValues(alpha: 0.15)
                          : _darkDeepTeal,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _fromDate != null
                            ? _primaryAqua
                            : _mutedCoolGray.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: _primaryAqua,
                          size: 15,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _fromDate != null
                              ? '${_fromDate!.day}/${_fromDate!.month}/${_fromDate!.year}'
                              : 'From',
                          style: TextStyle(
                            color: _fromDate != null
                                ? _primaryAqua
                                : _mutedCoolGray,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // To date
                InkWell(
                  onTap: () => _selectDate(context, false),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _toDate != null
                          ? _primaryAqua.withValues(alpha: 0.15)
                          : _darkDeepTeal,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _toDate != null
                            ? _primaryAqua
                            : _mutedCoolGray.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: _primaryAqua,
                          size: 15,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _toDate != null
                              ? '${_toDate!.day}/${_toDate!.month}/${_toDate!.year}'
                              : 'To',
                          style: TextStyle(
                            color: _toDate != null
                                ? _primaryAqua
                                : _mutedCoolGray,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_fromDate != null || _toDate != null) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _clearDateFilters,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.clear,
                        color: Colors.red,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),

          // Record count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              '${records.length} prenatal record${records.length != 1 ? 's' : ''} found',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
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

          if (records.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: _buildPrenatalCardHeader(),
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
                children: List.generate(pagedRecords.length, (index) {
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
                    onEdit: (record) => _showEditPrenatalModal(context, record),
                    onView: (record) => _onViewButtonPressed(context, record),
                  );
                }),
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
                        color: Colors.white.withValues(alpha: 0.72),
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
                      color: _darkDeepTeal,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _primaryAqua.withValues(alpha: 0.25),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        dropdownColor: _darkDeepTeal,
                        value: effectiveRowsPerPage,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        iconEnabledColor: Colors.white,
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
                    color: Colors.white,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _darkDeepTeal,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _primaryAqua.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      '$currentPage / $totalPages',
                      style: const TextStyle(
                        color: Colors.white,
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
                    color: Colors.white,
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: _lightOffWhite, fontSize: 14),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
            _currentPage = 1;
          });
          _scheduleSharedPatientSearch(value);
        },
        decoration: InputDecoration(
          hintText: 'Search by name, age, contact, address...',
          hintStyle: const TextStyle(color: _mutedCoolGray, fontSize: 13),
          prefixIcon: Icon(Icons.search_rounded, color: _primaryAqua, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.clear,
                    color: _mutedCoolGray,
                    size: 18,
                  ),
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
          filled: true,
          fillColor: Colors.white,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _lightOffWhite.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Title Section
          Icon(Icons.tune_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Text(
            'Filter Results',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 32),

          // Status Filter
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _lightOffWhite.withValues(alpha: 0.3),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: _darkDeepTeal,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedStatusFilter,
                      isExpanded: true,
                      icon: Icon(
                        Icons.arrow_drop_down,
                        color: Colors.white,
                        size: 20,
                      ),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      dropdownColor: _darkDeepTeal,
                      items: _statusFilterOptions.map((String option) {
                        return DropdownMenuItem<String>(
                          value: option,
                          child: Text(option),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() => _selectedStatusFilter = newValue);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 32),

          // Date Picker - From
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From Date',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Material(
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
                      if (picked != null) {
                        setState(() => _fromDate = picked);
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
                          color: _lightOffWhite.withValues(alpha: 0.3),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: _darkDeepTeal,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _fromDate != null
                                  ? '${_fromDate!.day}/${_fromDate!.month}/${_fromDate!.year}'
                                  : 'Select Date',
                              style: TextStyle(
                                color: _fromDate != null
                                    ? Colors.white
                                    : _mutedCoolGray,
                                fontSize: 12,
                                fontWeight: _fromDate != null
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Date Picker - To
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'To Date',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _toDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
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
                      if (picked != null) {
                        setState(() => _toDate = picked);
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
                          color: _lightOffWhite.withValues(alpha: 0.3),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: _darkDeepTeal,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _toDate != null
                                  ? '${_toDate!.day}/${_toDate!.month}/${_toDate!.year}'
                                  : 'Select Date',
                              style: TextStyle(
                                color: _toDate != null
                                    ? Colors.white
                                    : _mutedCoolGray,
                                fontSize: 12,
                                fontWeight: _toDate != null
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_fromDate != null || _toDate != null) ...[
            const SizedBox(width: 16),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _clearDateFilters,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.clear, color: Colors.red, size: 18),
                ),
              ),
            ),
          ],
        ],
      ),
    );
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
    return Container(width: 1, height: 70, color: const Color(0xFFD9E5F2));
  }

  Widget _buildIconActionButton({
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

  String _formatDate(dynamic date) {
    if (date == null || date.toString().trim().isEmpty) return 'N/A';
    try {
      final dateTime = DateTime.parse(date.toString());
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return date.toString();
    }
  }

  Map<String, String> _formatDateTimeParts(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return {'date': 'N/A', 'time': ''};
    }

    try {
      final dt = DateTime.parse(value.toString());
      final date =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final time =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      return {'date': date, 'time': time};
    } catch (e) {
      return {'date': _formatDate(value), 'time': ''};
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientName = _safe(record['patientName'], 'Unknown');
    final age = _safe(record['age']);
    final patientId = _safe(record['patientId'], '-');
    final contactNumber = _safe(record['contactNumber']);
    final gestationalAge = _safe(
      record['gestationalAge'],
      _safe(record['aog']),
    );
    final dueDate = _formatDate(record['dueDate']);
    final status = _safe(
      record['status'],
      _safe(record['riskLevel'], 'Active'),
    );
    final registration = _formatDateTimeParts(record['registrationDate']);

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
              Expanded(
                flex: 14,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          color: rowText,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (timeLabel.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          timeLabel,
                          style: const TextStyle(
                            color: mutedText,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              _buildDivider(),
              Expanded(
                flex: 22,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9D6E0),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Prenatal Care',
                        style: TextStyle(
                          color: Color(0xFF163B66),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
              _buildDivider(),
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
                    Text(
                      'Female, $age years',
                      style: const TextStyle(
                        color: mutedText,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: $patientId',
                      style: const TextStyle(
                        color: Color(0xFF8BDCF0),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _buildDivider(),
              Expanded(
                flex: 42,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Gestational Age: $gestationalAge',
                      style: const TextStyle(
                        color: rowText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Due: $dueDate   Contact: $contactNumber',
                      style: const TextStyle(
                        color: mutedText,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Mont',
                      ),
                      maxLines: 2,
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
                        _buildIconActionButton(
                          icon: Icons.visibility_rounded,
                          onTap: onView != null ? () => onView!(record) : () {},
                        ),
                        const SizedBox(width: 6),
                        _buildIconActionButton(
                          icon: Icons.edit_rounded,
                          onTap: () => onEdit(record),
                        ),
                        const SizedBox(width: 6),
                        _buildIconActionButton(
                          icon: Icons.picture_as_pdf_rounded,
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
class _PrenatalDashboardHeader extends StatelessWidget {
  final int totalPatients;
  final int highRiskCount;
  final int completedCount;

  const _PrenatalDashboardHeader({
    required this.totalPatients,
    required this.highRiskCount,
    required this.completedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title Section
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Prenatal Care Dashboard',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 28,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _primaryAqua.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _lightOffWhite.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Text(
                'Live',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const Spacer(),
            Text(
              'Maternal health tracking & management system',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),

        // Metrics Grid - 4 columns for web with better spacing
        Row(
          children: [
            Expanded(
              child: _buildWebMetricCard(
                title: 'Total Patients',
                value: '$totalPatients',
                icon: Icons.group_rounded,
                color: Color(0xFF4CAF50),
                bgColor: Color(0xFF4CAF50).withValues(alpha: 0.08),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildWebMetricCard(
                title: 'High Risk',
                value: '$highRiskCount',
                icon: Icons.warning_rounded,
                color: Color(0xFFFF9800),
                bgColor: Color(0xFFFF9800).withValues(alpha: 0.08),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildWebMetricCard(
                title: 'Completed',
                value: '$completedCount',
                icon: Icons.check_circle_rounded,
                color: Color(0xFF2196F3),
                bgColor: Color(0xFF2196F3).withValues(alpha: 0.08),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildWebMetricCard(
                title: 'Status',
                value:
                    '${((completedCount / (totalPatients > 0 ? totalPatients : 1)) * 100).toStringAsFixed(0)}%',
                icon: Icons.trending_up_rounded,
                color: _primaryAqua,
                bgColor: _primaryAqua.withValues(alpha: 0.08),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWebMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _lightOffWhite.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _primaryAqua.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}
