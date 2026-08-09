import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart'
    as charts;
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/roles/bhw/dashboard/homepage.dart';
import 'package:mycapstone_project/web/roles/bhw/checkups/checkup.dart'
    as checkup_page;
import 'package:mycapstone_project/web/roles/bhw/analytics/health_metrics.dart';
import 'package:mycapstone_project/web/roles/cho/analytics/cho_analytics.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal.dart';
import 'package:mycapstone_project/web/roles/bhw/immunization/immunization.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/communicable.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/non_communicable.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/mortality_database_helper.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/shared/components/fullscreen_detail_table_dialog.dart';
import 'package:mycapstone_project/web/shared/components/module_view_components.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_first_service_selector.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_identity_utils.dart';
import 'package:mycapstone_project/web/shared/utils/file_download.dart';
import 'package:mycapstone_project/web/shared/utils/mortality_pdf.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/shared_patient_search_panel.dart';
import 'package:mycapstone_project/web/shared/utils/report_generation.dart';
import 'package:mycapstone_project/shared/current_table_record_utils.dart';

const Color _primaryAqua = Color(0xFF2F80ED);
const Color _secondaryIceBlue = Color(0xFF163B66);
const Color _darkDeepTeal = Color(0xFF071A33);
const Color _lightOffWhite = Color(0xFF0B1F3A);
const Color _mutedCoolGray = Color(0xFF4B6075);
const Color _sidebarDark = Color(0xFF0D274D);

class MortalityPage extends StatefulWidget {
  const MortalityPage({super.key, this.initialPatient});

  final Map<String, dynamic>? initialPatient;

  @override
  State<MortalityPage> createState() => _MortalityPageState();
}

class _MortalityPageState extends State<MortalityPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  // Database helper
  final _mortalityHelper = MortalityDatabaseHelper.instance;
  final PatientCenteredHistoryService _patientHistoryService =
      PatientCenteredHistoryService();

  // Metrics
  int _totalDeaths = 0;
  String _leadingCause = '';
  int _elderlyDeaths = 0;
  double _verificationRate = 0.0;
  bool _isLoadingMetrics = false;
  bool _isDataLoaded = false;

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _sharedPatientMatches = [];
  bool _isSearchingSharedPatients = false;
  Timer? _sharedPatientSearchDebounce;
  int _currentPage = 1;
  int _rowsPerPage = 10;

  // Data
  List<Map<String, dynamic>> _mortalityRecords = [];
  List<Map<String, dynamic>> _filteredRecords = [];
  List<MonthlyTrend> _monthlyTrends = [];
  List<CauseData> _causeData = [];
  List<AgeDistribution> _ageDistributions = [];

  // Pie Chart Hover State
  CauseData? _selectedCause;
  late HealthModuleView _activeView;

  @override
  void initState() {
    super.initState();
    _activeView = healthModuleViewFromUrl();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => persistHealthModuleView('/mortality', _activeView),
    );
    // Load data asynchronously to avoid blocking UI
    Future.microtask(() => _loadData());
    if (widget.initialPatient != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAddRecordDialog(patientSeed: widget.initialPatient);
      });
    }
  }

  void _setActiveView(HealthModuleView view) {
    if (_activeView == view) return;
    setState(() => _activeView = view);
    persistHealthModuleView('/mortality', view);
  }

  @override
  void dispose() {
    _sharedPatientSearchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoadingMetrics = true);

    try {
      // Load mortality records from database
      final recordsList = await _mortalityHelper.getAllRecords();

      // Calculate metrics from records
      final totalDeaths = recordsList.length;
      final elderlyCount = recordsList
          .where((r) => (int.tryParse(r['age'].toString()) ?? 0) >= 60)
          .length;
      final verifiedCount = recordsList
          .where((r) => r['verification'] == 'Verified')
          .length;
      final verificationPercent = totalDeaths > 0
          ? (verifiedCount / totalDeaths) * 100
          : 0.0;

      // Find leading cause
      final leadingCause = await _mortalityHelper.getLeadingCause();

      // Generate trends from records
      final trends = _generateMonthlyTrends(recordsList);
      final causes = _generateCauseData(recordsList);
      final ages = _generateAgeDistribution(recordsList);
      final currentRecords = _collapseCurrentRecords(recordsList);

      setState(() {
        _mortalityRecords = recordsList;
        _filteredRecords = currentRecords;
        _totalDeaths = totalDeaths;
        _leadingCause = leadingCause;
        _elderlyDeaths = elderlyCount;
        _verificationRate = verificationPercent;
        _monthlyTrends = trends;
        _causeData = causes;
        _ageDistributions = ages;
        _currentPage = 1;
        _isLoadingMetrics = false;
        _isDataLoaded = true;
      });
    } catch (e) {
      print('Error loading data: $e');
      setState(() {
        _isLoadingMetrics = false;
        _isDataLoaded = true;
      });
    }
  }

  void _filterRecords(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      _currentPage = 1;
      if (_searchQuery.isEmpty) {
        _filteredRecords = _collapseCurrentRecords(_mortalityRecords);
      } else {
        final filtered = _mortalityRecords.where((record) {
          return record['name'].toString().toLowerCase().contains(
                _searchQuery,
              ) ||
              record['causeOfDeath'].toString().toLowerCase().contains(
                _searchQuery,
              ) ||
              record['place'].toString().toLowerCase().contains(_searchQuery) ||
              record['verification'].toString().toLowerCase().contains(
                _searchQuery,
              );
        }).toList();
        _filteredRecords = _collapseCurrentRecords(filtered);
      }
    });
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

  List<Map<String, dynamic>> _collapseCurrentRecords(
    List<Map<String, dynamic>> records,
  ) {
    return CurrentTableRecordUtils.collapseToLatestPerEntity(
      records,
      idKeys: const ['linkedPatientId', 'patientId'],
      nameKeys: const ['name', 'patientName', 'patient'],
      dateKeys: const ['dateReported', 'date', 'createdAt', 'timestamp'],
    );
  }

  Future<void> _generateMortalityReport() {
    return generateReportPdf(
      context: context,
      moduleLabel: 'Mortality',
      records: _filteredRecords,
      dateResolver: (record) =>
          parseReportDateValue(record['date']) ??
          parseReportDateValue(record['dateReported']),
      columns: [
        ReportCsvColumn('Record ID', (record) => reportText(record['id'])),
        ReportCsvColumn('Name', (record) => reportText(record['name'])),
        ReportCsvColumn(
          'Date of Death',
          (record) => formatReportDateValue(record['date']),
        ),
        ReportCsvColumn(
          'Cause of Death',
          (record) => reportText(record['causeOfDeath']),
        ),
        ReportCsvColumn('Place', (record) => reportText(record['place'])),
        ReportCsvColumn('Age', (record) => reportText(record['age'])),
        ReportCsvColumn('Gender', (record) => reportText(record['gender'])),
        ReportCsvColumn(
          'Verification Status',
          (record) => reportText(record['verification']),
        ),
        ReportCsvColumn(
          'Reported By',
          (record) => reportText(record['reportedBy']),
        ),
        ReportCsvColumn(
          'Date Reported',
          (record) => formatReportDateValue(record['dateReported']),
        ),
      ],
      accentColor: _primaryAqua,
      dialogColor: _sidebarDark,
      textColor: Colors.white,
      mutedColor: Colors.white70,
      sectionTitleBuilder: (record, index) =>
          'Record ${index + 1}: ${reportText(record['name'], fallback: 'Record')}',
    );
  }

  Color _getVerificationColor(String verification) {
    return verification.toLowerCase() == 'verified'
        ? const Color(0xFF4CAF50)
        : const Color(0xFFFFA726);
  }

  List<MonthlyTrend> _generateMonthlyTrends(
    List<Map<String, dynamic>> records,
  ) {
    Map<String, int> monthCounts = {
      'Aug': 0,
      'Sep': 0,
      'Oct': 0,
      'Nov': 0,
      'Dec': 0,
      'Jan': 0,
    };

    for (var record in records) {
      try {
        final recordDate = DateTime.parse(record['dateReported'] as String);
        final monthKey = [
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
        ][recordDate.month - 1];
        if (monthCounts.containsKey(monthKey)) {
          monthCounts[monthKey] = monthCounts[monthKey]! + 1;
        }
      } catch (e) {
        print('Error parsing date: $e');
      }
    }

    return [
      MonthlyTrend('Aug', monthCounts['Aug']!),
      MonthlyTrend('Sep', monthCounts['Sep']!),
      MonthlyTrend('Oct', monthCounts['Oct']!),
      MonthlyTrend('Nov', monthCounts['Nov']!),
      MonthlyTrend('Dec', monthCounts['Dec']!),
      MonthlyTrend('Jan', monthCounts['Jan']!),
    ];
  }

  List<CauseData> _generateCauseData(List<Map<String, dynamic>> records) {
    Map<String, int> causeCounts = {};

    for (var record in records) {
      final cause = record['causeOfDeath'] ?? 'Unknown';
      causeCounts[cause] = (causeCounts[cause] ?? 0) + 1;
    }

    final total = records.isEmpty ? 1 : records.length;
    final sorted = causeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Keep top 5 causes and group the rest as "Other"
    final topCauses = sorted.take(5).toList();
    int otherCount = 0;
    for (var i = 5; i < sorted.length; i++) {
      otherCount += sorted[i].value;
    }

    final result = topCauses.map((entry) {
      return CauseData(entry.key, entry.value, (entry.value / total) * 100);
    }).toList();

    // Add "Other" category if there are more than 5 causes
    if (otherCount > 0) {
      result.add(
        CauseData('Other Causes', otherCount, (otherCount / total) * 100),
      );
    }

    return result;
  }

  List<AgeDistribution> _generateAgeDistribution(
    List<Map<String, dynamic>> records,
  ) {
    Map<String, int> ageRangeCounts = {
      '0-18': 0,
      '19-40': 0,
      '41-60': 0,
      '61-80': 0,
      '81+': 0,
    };

    for (var record in records) {
      try {
        final age = int.parse(record['age'].toString());
        String range;
        if (age <= 18) {
          range = '0-18';
        } else if (age <= 40)
          range = '19-40';
        else if (age <= 60)
          range = '41-60';
        else if (age <= 80)
          range = '61-80';
        else
          range = '81+';

        ageRangeCounts[range] = ageRangeCounts[range]! + 1;
      } catch (e) {
        // Skip invalid age values
      }
    }

    final total = records.isEmpty ? 1 : records.length;

    return [
      AgeDistribution(
        '0-18',
        ageRangeCounts['0-18']!,
        (ageRangeCounts['0-18']! / total) * 100,
      ),
      AgeDistribution(
        '19-40',
        ageRangeCounts['19-40']!,
        (ageRangeCounts['19-40']! / total) * 100,
      ),
      AgeDistribution(
        '41-60',
        ageRangeCounts['41-60']!,
        (ageRangeCounts['41-60']! / total) * 100,
      ),
      AgeDistribution(
        '61-80',
        ageRangeCounts['61-80']!,
        (ageRangeCounts['61-80']! / total) * 100,
      ),
      AgeDistribution(
        '81+',
        ageRangeCounts['81+']!,
        (ageRangeCounts['81+']! / total) * 100,
      ),
    ];
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
        activeItem: WebSidebarItem.mortality,
      ),
      body: Column(
        children: [
          _buildTopBar(context),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HealthModuleViewHeader(
                      title: 'Mortality Monitoring',
                      description:
                          'Review mortality trends and verified indicators, or manage individual mortality records.',
                      activeView: _activeView,
                      onViewChanged: _setActiveView,
                      primaryColor: _primaryAqua,
                    ),
                    const SizedBox(height: 20),
                    if (_activeView == HealthModuleView.insights) ...[
                      if (_isDataLoaded && _mortalityRecords.isEmpty)
                        const ModuleEmptyState(
                          title: 'No mortality insights yet',
                          message:
                              'Mortality trends and cause distributions will appear when verified records are available.',
                          icon: Icons.query_stats_rounded,
                        )
                      else ...[
                        _buildOverviewDashboard(),
                        const SizedBox(height: 20),
                        _buildGraphsSection(),
                        const SizedBox(height: 20),
                        _buildTablesSection(),
                      ],
                    ] else
                      _buildRecordsTableSection(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
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
                    onTap: () => Get.to(() => const checkup_page.CheckUpPage()),
                  ),
                  _buildDrawerSidebarItem(
                    icon: Icons.favorite_rounded,
                    label: 'Summary Generation',
                    onTap: () => Get.to(() => const HealthMetricsPage()),
                  ),
                  _buildDrawerSidebarItem(
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
                  _buildDrawerSidebarItem(
                    icon: Icons.pregnant_woman_rounded,
                    label: 'Prenatal Care',
                    onTap: () => Get.to(() => const PrenatalPage()),
                  ),
                  _buildDrawerSidebarItem(
                    icon: Icons.vaccines_rounded,
                    label: 'Immunization',
                    onTap: () => Get.to(() => const ImmunizationPage()),
                  ),
                  _buildDrawerSidebarItem(
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
                  _buildDrawerSidebarItem(
                    icon: Icons.coronavirus_rounded,
                    label: 'Communicable',
                    onTap: () => Get.to(() => const CommunicablePage()),
                  ),
                  _buildDrawerSidebarItem(
                    icon: Icons.health_and_safety_rounded,
                    label: 'Non-Communicable',
                    onTap: () => Get.to(() => const NonCommunicablePage()),
                  ),
                  _buildDrawerSidebarItem(
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

  Widget _buildSidebar(BuildContext context, String userName) {
    final user = FirebaseAuth.instance.currentUser;
    return Container(
      width: 220,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_sidebarDark, _sidebarDark.withValues(alpha: 0.95)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(4, 0),
          ),
        ],
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
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
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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
                  onTap: () => Get.to(() => const PrenatalPage()),
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
                  isActive: true,
                  onTap: () {},
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
                      Icon(Icons.logout_rounded, color: Colors.white, size: 20),
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

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: _sidebarDark,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
              hoverColor: _primaryAqua.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.menu_rounded, color: Colors.white, size: 24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Mortality Monitoring',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _isLoadingMetrics ? null : _generateMortalityReport,
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
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Data',
            onPressed: _loadData,
            color: Colors.white70,
            iconSize: 28,
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
            color: Colors.white70,
            iconSize: 28,
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {},
            color: Colors.white70,
            iconSize: 28,
          ),
        ],
      ),
    );
  }

  // Overview Dashboard
  Widget _buildOverviewDashboard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryAqua.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Mortality Overview',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: _lightOffWhite,
                    letterSpacing: 0.5,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _primaryAqua.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _primaryAqua, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.pie_chart_rounded,
                        color: _primaryAqua,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Real-time Data',
                        style: TextStyle(
                          color: _lightOffWhite,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_isLoadingMetrics)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: _primaryAqua),
                ),
              )
            else
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildWebMetricCard(
                          title: 'Total Deaths',
                          value: _totalDeaths.toString(),
                          icon: Icons.assignment_outlined,
                          accentColor: Color(0xFF64B5F6),
                          backgroundColor: _sidebarDark,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildWebMetricCard(
                          title: 'Elderly Deaths',
                          value: _elderlyDeaths.toString(),
                          icon: Icons.elderly_rounded,
                          accentColor: Color(0xFF81C784),
                          backgroundColor: _sidebarDark,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildWebMetricCard(
                          title: 'Verification Rate',
                          value: '${_verificationRate.toStringAsFixed(1)}%',
                          icon: Icons.verified_user_rounded,
                          accentColor: Color(0xFFFFB74D),
                          backgroundColor: _sidebarDark,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildWebMetricCard(
                          title: 'Leading Cause',
                          value: _leadingCause.length > 20
                              ? '${_leadingCause.substring(0, 20)}...'
                              : _leadingCause,
                          icon: Icons.warning_rounded,
                          accentColor: Color(0xFFFF7043),
                          backgroundColor: _sidebarDark,
                          isSmallText: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color textColor,
    bool isSmallText = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
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
              Icon(icon, color: textColor, size: 28),
              if (!isSmallText)
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (isSmallText)
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: textColor.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
    required Color backgroundColor,
    bool isSmallText = false,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            isSmallText
                ? (value.length > 25 ? '${value.substring(0, 22)}...' : value)
                : value,
            style: TextStyle(
              fontSize: isSmallText ? 14 : 24,
              fontWeight: FontWeight.bold,
              color: _darkDeepTeal,
              letterSpacing: 0.5,
            ),
            maxLines: isSmallText ? 2 : 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: _mutedCoolGray,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // Graphs Section
  Widget _buildGraphsSection() {
    if (!_isDataLoaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: CircularProgressIndicator(color: _primaryAqua),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatsWebBar(),
        const SizedBox(height: 20),

        // Monthly Trends (Full Width Line Graph)
        if (_monthlyTrends.isNotEmpty)
          _buildWebGraphCard(
            title: 'Monthly Death Trends',
            subtitle: 'Deaths reported over 6 months',
            icon: Icons.trending_up_rounded,
            child: SizedBox(
              height: 300,
              child: charts.BarChart(
                [
                  charts.Series<MonthlyTrend, String>(
                    id: 'Deaths',
                    colorFn: (_, _) =>
                        charts.Color(r: 100, g: 181, b: 246, a: 255),
                    domainFn: (MonthlyTrend trend, _) => trend.month,
                    measureFn: (MonthlyTrend trend, _) => trend.deaths,
                    data: _monthlyTrends,
                  ),
                ],
                animate: true,
                vertical: true,
                barGroupingType: charts.BarGroupingType.groupedStacked,
                primaryMeasureAxis: const charts.NumericAxisSpec(
                  renderSpec: charts.GridlineRendererSpec(
                    labelStyle: charts.TextStyleSpec(
                      color: charts.Color(r: 255, g: 255, b: 255),
                      fontSize: 12,
                    ),
                  ),
                ),
                domainAxis: const charts.OrdinalAxisSpec(
                  renderSpec: charts.SmallTickRendererSpec(
                    labelStyle: charts.TextStyleSpec(
                      color: charts.Color(r: 255, g: 255, b: 255),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_causeData.isNotEmpty && _ageDistributions.isNotEmpty)
          const SizedBox(height: 24),

        // Two-Column Layout for Charts
        if (_causeData.isNotEmpty && _ageDistributions.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Leading Causes (Pie Chart with Legend)
              Expanded(
                flex: 1,
                child: _buildWebGraphCard(
                  title: 'Leading Causes of Death',
                  subtitle: 'Distribution by cause (Top 5)',
                  icon: Icons.pie_chart_rounded,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Hover Details Box
                      if (_selectedCause != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _primaryAqua.withValues(alpha: 0.15),
                                _primaryAqua.withValues(alpha: 0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _primaryAqua.withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _primaryAqua.withValues(alpha: 0.2),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_rounded,
                                color: _primaryAqua,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _selectedCause != null
                                      ? '${_selectedCause!.cause}: ${_selectedCause!.count} deaths (${_selectedCause!.percentage.toStringAsFixed(1)}%)'
                                      : '',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(
                        height: 250,
                        child: charts.PieChart<String>(
                          [
                            charts.Series<CauseData, String>(
                              id: 'Causes',
                              domainFn: (CauseData data, _) => data.cause,
                              measureFn: (CauseData data, _) => data.count,
                              data: _causeData,
                              labelAccessorFn: (CauseData data, _) => '',
                              colorFn: (CauseData data, int? index) {
                                final colors = [
                                  charts.Color(
                                    r: 255,
                                    g: 87,
                                    b: 34,
                                    a: 255,
                                  ), // Deep orange
                                  charts.Color(
                                    r: 63,
                                    g: 81,
                                    b: 181,
                                    a: 255,
                                  ), // Indigo
                                  charts.Color(
                                    r: 76,
                                    g: 175,
                                    b: 80,
                                    a: 255,
                                  ), // Green
                                  charts.Color(
                                    r: 233,
                                    g: 30,
                                    b: 99,
                                    a: 255,
                                  ), // Pink
                                  charts.Color(
                                    r: 0,
                                    g: 188,
                                    b: 212,
                                    a: 255,
                                  ), // Cyan
                                  charts.Color(
                                    r: 156,
                                    g: 39,
                                    b: 176,
                                    a: 255,
                                  ), // Purple
                                ];
                                return colors[(index ?? 0) % colors.length];
                              },
                            ),
                          ],
                          animate: true,
                          defaultRenderer: charts.ArcRendererConfig<String>(
                            arcWidth: 120,
                            arcRendererDecorators: [],
                          ),
                          selectionModels: [
                            charts.SelectionModelConfig(
                              type: charts.SelectionModelType.info,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Enhanced Legend with white text
                      SizedBox(
                        height: 150,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _primaryAqua.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: _causeData.asMap().entries.map((
                                  entry,
                                ) {
                                  int idx = entry.key;
                                  CauseData cause = entry.value;
                                  final colors = [
                                    Color(0xFFFF5722),
                                    Color(0xFF3F51B5),
                                    Color(0xFF4CAF50),
                                    Color(0xFFE91E63),
                                    Color(0xFF00BCD4),
                                    Color(0xFF9C27B0),
                                  ];
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: MouseRegion(
                                      onEnter: (_) {
                                        setState(() {
                                          _selectedCause = cause;
                                        });
                                      },
                                      onExit: (_) {
                                        setState(() {
                                          _selectedCause = null;
                                        });
                                      },
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 20,
                                            height: 20,
                                            decoration: BoxDecoration(
                                              color:
                                                  colors[idx % colors.length],
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              boxShadow: [
                                                BoxShadow(
                                                  color:
                                                      colors[idx %
                                                              colors.length]
                                                          .withValues(
                                                            alpha: 0.5,
                                                          ),
                                                  blurRadius: 6,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  cause.cause,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${cause.count} deaths',
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 11,
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
                                              color: _primaryAqua.withValues(
                                                alpha: 0.2,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: _primaryAqua.withValues(
                                                  alpha: 0.5,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              '${cause.percentage.toStringAsFixed(1)}%',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // Age Distribution (Bar Chart)
              Expanded(
                flex: 1,
                child: _buildWebGraphCard(
                  title: 'Age Distribution',
                  subtitle: 'Deaths by age group',
                  icon: Icons.bar_chart_rounded,
                  child: SizedBox(
                    height: 280,
                    child: charts.BarChart(
                      [
                        charts.Series<AgeDistribution, String>(
                          id: 'Ages',
                          colorFn: (_, _) =>
                              charts.Color(r: 129, g: 199, b: 132, a: 255),
                          domainFn: (AgeDistribution dist, _) => dist.ageRange,
                          measureFn: (AgeDistribution dist, _) => dist.count,
                          data: _ageDistributions,
                        ),
                      ],
                      animate: true,
                      vertical: true,
                      barGroupingType: charts.BarGroupingType.groupedStacked,
                      primaryMeasureAxis: const charts.NumericAxisSpec(
                        renderSpec: charts.GridlineRendererSpec(
                          labelStyle: charts.TextStyleSpec(
                            color: charts.Color(r: 255, g: 255, b: 255),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      domainAxis: const charts.OrdinalAxisSpec(
                        renderSpec: charts.SmallTickRendererSpec(
                          labelStyle: charts.TextStyleSpec(
                            color: charts.Color(r: 255, g: 255, b: 255),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildGraphCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildStatsWebBar() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_sidebarDark, _sidebarDark.withValues(alpha: 0.8)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryAqua.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Statistical Analysis Dashboard',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Comprehensive mortality statistics and trends',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                _buildWebBarButton(
                  icon: Icons.refresh_rounded,
                  label: 'Refresh',
                  onPressed: _loadData,
                ),
                const SizedBox(width: 12),
                _buildWebBarButton(
                  icon: Icons.download_rounded,
                  label: 'Export',
                  onPressed: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebBarButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        hoverColor: _primaryAqua.withValues(alpha: 0.1),
        splashColor: _primaryAqua.withValues(alpha: 0.2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: _primaryAqua.withValues(alpha: 0.4),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, color: _primaryAqua, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebGraphCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _sidebarDark.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: _primaryAqua.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _primaryAqua.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: _primaryAqua, size: 24),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: child,
          ),
        ],
      ),
    );
  }

  // Tables Section
  Widget _buildTablesSection() {
    if (!_isDataLoaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: CircularProgressIndicator(color: _primaryAqua),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Detailed Statistics',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),

        // Two Column Layout for Tables
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cause of Death Table (Left Column)
              Expanded(flex: 1, child: _buildCauseTable()),
              const SizedBox(width: 16),
              // Age Distribution Table (Right Column)
              Expanded(flex: 1, child: _buildAgeTable()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCauseTable() {
    return Container(
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.table_chart, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Cause of Death Breakdown',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                _primaryAqua.withValues(alpha: 0.2),
              ),
              columns: [
                DataColumn(
                  label: Text(
                    'Cause of Death',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Percentage',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Progress',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Death Count',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
              rows: _causeData.map((cause) {
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        cause.cause,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${cause.percentage.toStringAsFixed(1)}%',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 100,
                        child: LinearProgressIndicator(
                          value: cause.percentage / 100,
                          backgroundColor: Colors.grey[700],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _primaryAqua,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        cause.count.toString(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgeTable() {
    return Container(
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.table_rows, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Age Distribution',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                _primaryAqua.withValues(alpha: 0.2),
              ),
              columns: [
                DataColumn(
                  label: Text(
                    'Age Range',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Death Count',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Percentage',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
              rows: _ageDistributions.map((age) {
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        age.ageRange,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    DataCell(
                      Text(
                        age.count.toString(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${age.percentage.toStringAsFixed(1)}%',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // Search Bar
  Widget _buildSearchBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useStackedHeader = constraints.maxWidth < 720;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (useStackedHeader) ...[
              _buildRecordsTitle(),
              const SizedBox(height: 12),
              _buildAddRecordButtonContainer(),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: _buildRecordsTitle()),
                  const SizedBox(width: 16),
                  _buildAddRecordButtonContainer(),
                ],
              ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _primaryAqua.withValues(alpha: 0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: _lightOffWhite),
                onChanged: (value) {
                  _filterRecords(value);
                  _scheduleSharedPatientSearch(value);
                },
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText:
                      'Search by name, cause, place, or verification status...',
                  hintStyle: const TextStyle(color: _mutedCoolGray),
                  prefixIcon: const Icon(Icons.search, color: _primaryAqua),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: _mutedCoolGray),
                          onPressed: () {
                            _searchController.clear();
                            _filterRecords('');
                            _scheduleSharedPatientSearch('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
            if (_searchQuery.trim().isNotEmpty ||
                _isSearchingSharedPatients) ...[
              const SizedBox(height: 12),
              SharedPatientSearchPanel(
                query: _searchQuery,
                results: _sharedPatientMatches,
                isLoading: _isSearchingSharedPatients,
                primaryActionLabel: 'View Medical History',
                onPrimaryAction: _showSharedPatientTimeline,
                secondaryActionLabel: 'Add Mortality Record',
                onSecondaryAction: (patient) =>
                    _showAddRecordDialog(patientSeed: patient),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildRecordsTitle() {
    return const Text(
      'Mortality Records',
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _buildAddRecordButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showAddRecordDialog,
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

  Widget _buildAddRecordButtonContainer() {
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
      child: _buildAddRecordButton(),
    );
  }

  Widget _buildRecordsTableSection() {
    final effectiveRowsPerPage = _rowsPerPage > 0 ? _rowsPerPage : 10;
    final totalRecords = _filteredRecords.length;
    final totalPages = totalRecords == 0
        ? 1
        : ((totalRecords + effectiveRowsPerPage - 1) ~/ effectiveRowsPerPage);
    final currentPage = _currentPage < 1
        ? 1
        : (_currentPage > totalPages ? totalPages : _currentPage);
    final pageStartIndex = totalRecords == 0
        ? 0
        : (currentPage - 1) * effectiveRowsPerPage;
    final pageEndIndex = totalRecords == 0
        ? 0
        : ((pageStartIndex + effectiveRowsPerPage) < totalRecords
              ? (pageStartIndex + effectiveRowsPerPage)
              : totalRecords);
    final pagedRecords = totalRecords == 0
        ? <Map<String, dynamic>>[]
        : _filteredRecords.sublist(pageStartIndex, pageEndIndex);

    return Container(
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSearchBar(),
            const SizedBox(height: 16),
            if (pagedRecords.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: _primaryAqua.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.inbox_rounded,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty
                            ? 'No records found'
                            : 'No results for "$_searchQuery"',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Try adjusting your search or add a new mortality record',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              _buildMortalityTableHeader(),
              _buildMortalityTable(pagedRecords),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Showing ${pageStartIndex + 1}-$pageEndIndex of ${_filteredRecords.length} records',
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
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeaderCell(String label, {required int flex}) {
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

  Widget _buildTableHeaderDivider() {
    return Container(
      width: 1,
      height: 18,
      color: Colors.white.withValues(alpha: 0.2),
    );
  }

  Widget _buildMortalityTableHeader() {
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
          _buildTableHeaderCell('Patient', flex: 30),
          _buildTableHeaderDivider(),
          _buildTableHeaderCell('Mortality Details', flex: 40),
          _buildTableHeaderDivider(),
          _buildTableHeaderCell('Verification', flex: 18),
          _buildTableHeaderDivider(),
          const SizedBox(
            width: 148,
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
      ),
    );
  }

  Widget _buildMortalityTable(List<Map<String, dynamic>> records) {
    return Column(
      children: List.generate(records.length, (index) {
        return _buildMortalityTableRow(records[index]);
      }),
    );
  }

  String _safeText(dynamic value, [String fallback = 'N/A']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    final normalized = text.toLowerCase();
    if (text.isEmpty || normalized == 'null' || normalized == 'undefined') {
      return fallback;
    }
    return text;
  }

  Color _verificationChipBackground(String verification) {
    final lower = verification.toLowerCase();
    if (lower.contains('verified')) return const Color(0xFFDDE9D4);
    if (lower.contains('pending')) return const Color(0xFFFCE8CC);
    return const Color(0xFFDDE4F3);
  }

  Widget _buildRowDivider() {
    return Container(width: 1, height: 70, color: const Color(0xFF26476B));
  }

  Widget _buildRowActionButton({
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

  Widget _buildMortalityTableRow(Map<String, dynamic> record) {
    final name = _safeText(record['name'], 'Unknown');
    final age = _safeText(record['age'], '-');
    final gender = _safeText(record['gender'], 'Unknown');
    final cause = _safeText(record['causeOfDeath'], 'No cause recorded');
    final place = _safeText(record['place'], 'No place recorded');
    final reportedBy = _safeText(record['reportedBy'], 'Unknown');
    final verification = _safeText(record['verification'], 'Pending');
    final reportedDate = _formatDate(record['dateReported'] ?? record['date']);

    const rowText = Color(0xFFF3F8FC);
    const mutedText = Color(0xFFB1C4D5);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: _darkDeepTeal.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF26476B), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 30,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: rowText,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Age: $age years | $gender',
                    style: const TextStyle(
                      color: mutedText,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Reported: $reportedDate',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            _buildRowDivider(),
            Expanded(
              flex: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cause,
                      style: const TextStyle(
                        color: Color(0xFFE53935),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      place,
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
                      'Reported by: $reportedBy',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            _buildRowDivider(),
            Expanded(
              flex: 18,
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
                      color: _verificationChipBackground(verification),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      verification,
                      style: const TextStyle(
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
            _buildRowDivider(),
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 2),
              child: SizedBox(
                width: 148,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildRowActionButton(
                      icon: Icons.history_rounded,
                      onTap: () => _showMortalityHistory(context, record),
                    ),
                    const SizedBox(width: 6),
                    _buildRowActionButton(
                      icon: Icons.edit_rounded,
                      onTap: () => _editRecord(record),
                    ),
                    const SizedBox(width: 6),
                    _buildRowActionButton(
                      icon: Icons.verified_rounded,
                      onTap: () => _verifyRecord(record),
                    ),
                    const SizedBox(width: 6),
                    _buildRowActionButton(
                      icon: Icons.picture_as_pdf_rounded,
                      onTap: () => _printRecord(record),
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

  Widget _buildRecordCard(Map<String, dynamic> record) {
    return Container(
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _primaryAqua.withValues(alpha: 0.2),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: _primaryAqua,
                  child: Text(
                    record['name'].toString().substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record['name'],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${record['age']} years • ${record['gender']}',
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getVerificationColor(record['verification']),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    record['verification'],
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

          // Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildDetailRow(
                  icon: Icons.calendar_today,
                  label: 'Date',
                  value: _formatDate(record['date']),
                  color: _primaryAqua,
                ),
                const Divider(height: 20, color: Colors.white24),
                _buildDetailRow(
                  icon: Icons.warning_amber,
                  label: 'Cause of Death',
                  value: record['causeOfDeath'],
                  color: const Color(0xFFD84315),
                ),
                const Divider(height: 20, color: Colors.white24),
                _buildDetailRow(
                  icon: Icons.location_on,
                  label: 'Place',
                  value: record['place'],
                  color: const Color(0xFF7B1FA2),
                ),
                const Divider(height: 20, color: Colors.white24),
                _buildDetailRow(
                  icon: Icons.person,
                  label: 'Reported By',
                  value: record['reportedBy'],
                  color: const Color(0xFF2196F3),
                ),
              ],
            ),
          ),

          // Actions
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _secondaryIceBlue.withValues(alpha: 0.3),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  icon: Icons.history,
                  label: 'History',
                  color: _primaryAqua,
                  onTap: () => _showMortalityHistory(context, record),
                ),
                _buildActionButton(
                  icon: Icons.edit,
                  label: 'Edit',
                  color: const Color(0xFF7B1FA2),
                  onTap: () => _editRecord(record),
                ),
                _buildActionButton(
                  icon: Icons.verified,
                  label: 'Verify',
                  color: const Color(0xFF4CAF50),
                  onTap: () => _verifyRecord(record),
                ),
                _buildActionButton(
                  icon: Icons.picture_as_pdf,
                  label: 'PDF',
                  color: const Color(0xFF607D8B),
                  onTap: () => _printRecord(record),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic dateValue) {
    final dateString = (dateValue ?? '').toString().trim();
    if (dateString.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return '${date.month}/${date.day}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  List<Map<String, dynamic>> _getMortalityHistory(Map<String, dynamic> record) {
    return PatientHistoryDialogs.collectHistory(
      seedRecord: record,
      records: _mortalityRecords,
      idKeys: const ['linkedPatientId', 'patientId', 'id'],
      nameKeys: const ['name', 'patientName', 'patient'],
      sortDateKeys: const ['dateReported', 'date'],
    );
  }

  Map<String, dynamic> _buildPatientHistorySeed(Map<String, dynamic> record) {
    final patientName = _safeText(
      record['patientName'] ?? record['name'] ?? record['patient'],
      '',
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

  void _showMortalityHistory(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final history = _getMortalityHistory(record);
    PatientHistoryDialogs.showModuleHistoryDialog(
      context: context,
      moduleTitle: 'Mortality',
      seedRecord: record,
      history: history,
      description:
          'Review existing mortality reports for this patient before saving another death-related record.',
      addButtonLabel: 'Add Another Mortality Record',
      titleBuilder: (entry) =>
          (entry['causeOfDeath'] ?? 'Mortality report').toString(),
      subtitleBuilder: (entry) =>
          (entry['verification'] ?? 'Pending verification').toString(),
      metaBuilder: (entry) =>
          'Age: ${(entry['age'] ?? 'N/A').toString()} | Place: ${(entry['place'] ?? 'N/A').toString()}',
      dateKeys: const ['dateReported', 'date'],
      secondaryActionLabel: 'Medical History',
      onSecondaryAction: () => _showPatientMedicalHistory(context, record),
      onAddAnother: () => _showAddRecordDialog(
        patientSeed: history.isNotEmpty ? history.first : record,
      ),
      onOpenRecord: (entry) => _viewRecordDetails(entry),
    );
  }

  // Action Methods
  Future<void> _showAddRecordDialog({Map<String, dynamic>? patientSeed}) async {
    patientSeed = await _patientHistoryService.resolveRegisteredPatient(
      patientSeed,
    );
    if (patientSeed == null) {
      patientSeed = await PatientFirstServiceSelector.selectRegisteredPatient(
        context,
        serviceLabel: 'Mortality',
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
    _showMortalityRecordDialog(patientSeed: patientSeed);
  }

  void _showMortalityRecordDialog({
    Map<String, dynamic>? record,
    Map<String, dynamic>? patientSeed,
  }) {
    final isEditing = record != null;
    final seedRecord = record ?? patientSeed;
    final nameController = TextEditingController(
      text: seedRecord == null
          ? ''
          : patientDisplayName(seedRecord, fallback: ''),
    );
    final ageController = TextEditingController(
      text: _safeText(seedRecord?['age'], ''),
    );
    final causeController = TextEditingController(
      text: isEditing ? _safeText(record['causeOfDeath'], '') : '',
    );
    final placeController = TextEditingController(
      text: isEditing
          ? _safeText(record['place'], '')
          : _safeText(seedRecord?['place'], ''),
    );
    final reportedByController = TextEditingController(
      text: isEditing
          ? _safeText(record['reportedBy'], '')
          : _safeText(seedRecord?['reportedBy'], ''),
    );
    const genderOptions = ['Male', 'Female', 'Other'];
    final initialGender = _safeText(seedRecord?['gender'], 'Male');
    String selectedGender = genderOptions.contains(initialGender)
        ? initialGender
        : 'Male';
    final verification = _safeText(record?['verification'], 'Pending');
    final recordId = record == null
        ? 'Assigned on save'
        : _safeText(record['id'], 'Unavailable');
    final modeAccent = isEditing ? const Color(0xFFFF7043) : _primaryAqua;
    final statusColor = _getVerificationColor(verification);

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: _sidebarDark,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(
              color: _primaryAqua.withValues(alpha: 0.2),
              width: 1.2,
            ),
          ),
          constraints: BoxConstraints.tight(MediaQuery.of(context).size),
          insetPadding: EdgeInsets.zero,
          titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
          contentPadding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
          actionsPadding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isEditing
                            ? const [Color(0xFFFFB74D), Color(0xFFFF7043)]
                            : const [_primaryAqua, _secondaryIceBlue],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: modeAccent.withValues(alpha: 0.22),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(
                      isEditing
                          ? Icons.drive_file_rename_outline_rounded
                          : Icons.post_add_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEditing
                              ? 'Edit Mortality Record'
                              : 'Create Mortality Record',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 23,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isEditing
                              ? 'Refine patient and incident details without leaving the mortality table.'
                              : 'Capture a new mortality case with complete reporting details.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.68),
                            fontWeight: FontWeight.w500,
                            fontSize: 12.5,
                            height: 1.35,
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
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildMortalityDialogMetaChip(
                    icon: isEditing
                        ? Icons.edit_note_rounded
                        : Icons.add_task_rounded,
                    label: 'Mode',
                    value: isEditing ? 'Editing live record' : 'New entry',
                    accentColor: modeAccent,
                  ),
                  _buildMortalityDialogMetaChip(
                    icon: Icons.verified_outlined,
                    label: 'Status',
                    value: isEditing ? verification : 'Pending on save',
                    accentColor: statusColor,
                    valueColor: statusColor,
                  ),
                  _buildMortalityDialogMetaChip(
                    icon: Icons.tag_outlined,
                    label: 'Record ID',
                    value: recordId,
                    accentColor: const Color(0xFF64B5F6),
                  ),
                ],
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width < 860 ? 520 : 760,
            child: SingleChildScrollView(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 620;
                  final sectionWidth = isCompact
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 16) / 2;

                  Widget ageField() => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMortalityDialogFieldLabel('Age *'),
                      TextField(
                        controller: ageController,
                        cursorColor: _primaryAqua,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: _buildMortalityDialogInputDecoration(
                          hintText: 'e.g., 65',
                          icon: Icons.cake_outlined,
                        ),
                      ),
                    ],
                  );

                  Widget genderField() => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMortalityDialogFieldLabel('Gender *'),
                      DropdownButtonFormField<String>(
                        initialValue: selectedGender,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(18),
                        onChanged: (newValue) {
                          setState(() {
                            selectedGender = newValue ?? 'Male';
                          });
                        },
                        dropdownColor: _sidebarDark,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        iconEnabledColor: Colors.white,
                        items: genderOptions
                            .map(
                              (gender) => DropdownMenuItem(
                                value: gender,
                                child: Text(
                                  gender,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            )
                            .toList(),
                        selectedItemBuilder: (context) => genderOptions
                            .map(
                              (gender) => Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  gender,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            )
                            .toList(),
                        decoration: _buildMortalityDialogInputDecoration(
                          hintText: 'Select gender',
                          icon: Icons.wc_outlined,
                        ),
                      ),
                    ],
                  );

                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: sectionWidth,
                        child: _buildMortalityDialogSection(
                          title: 'Patient Profile',
                          subtitle:
                              'Basic identity details used throughout the mortality record.',
                          icon: Icons.person_outline_rounded,
                          accentColor: const Color(0xFF64B5F6),
                          children: [
                            _buildMortalityDialogFieldLabel('Patient Name *'),
                            TextField(
                              controller: nameController,
                              cursorColor: _primaryAqua,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: _buildMortalityDialogInputDecoration(
                                hintText: 'Enter full name',
                                icon: Icons.person_outline_rounded,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (isCompact) ...[
                              ageField(),
                              const SizedBox(height: 16),
                              genderField(),
                            ] else
                              Row(
                                children: [
                                  Expanded(child: ageField()),
                                  const SizedBox(width: 14),
                                  Expanded(child: genderField()),
                                ],
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: sectionWidth,
                        child: _buildMortalityDialogSection(
                          title: 'Incident Details',
                          subtitle:
                              'Capture the mortality event information used in reports and exports.',
                          icon: Icons.monitor_heart_outlined,
                          accentColor: const Color(0xFFE57373),
                          children: [
                            _buildMortalityDialogFieldLabel('Cause of Death *'),
                            TextField(
                              controller: causeController,
                              cursorColor: _primaryAqua,
                              maxLines: 3,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: _buildMortalityDialogInputDecoration(
                                hintText:
                                    'e.g., Myocardial Infarction, Stroke, Cancer',
                                icon: Icons.coronavirus_outlined,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildMortalityDialogFieldLabel('Place of Death'),
                            TextField(
                              controller: placeController,
                              cursorColor: _primaryAqua,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: _buildMortalityDialogInputDecoration(
                                hintText:
                                    'e.g., City General Hospital, Home, Clinic',
                                icon: Icons.location_on_outlined,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: sectionWidth,
                        child: _buildMortalityDialogSection(
                          title: 'Reporting Details',
                          subtitle:
                              'Identify the source or staff member responsible for the report.',
                          icon: Icons.assignment_ind_outlined,
                          accentColor: const Color(0xFF81C784),
                          children: [
                            _buildMortalityDialogFieldLabel('Reported By'),
                            TextField(
                              controller: reportedByController,
                              cursorColor: _primaryAqua,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: _buildMortalityDialogInputDecoration(
                                hintText: 'e.g., Dr. John Smith',
                                icon: Icons.person_search_outlined,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildMortalityDialogNote(
                              label: isEditing
                                  ? 'Edit mode note'
                                  : 'Before saving',
                              value: isEditing
                                  ? 'Changes here will update the existing mortality record while preserving its reporting history.'
                                  : 'Required fields must be complete before a new mortality record can be created.',
                              accentColor: statusColor,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: sectionWidth,
                        child: _buildMortalityDialogSection(
                          title: 'Record Context',
                          subtitle:
                              'Quick reference details for the item you are editing.',
                          icon: Icons.folder_open_outlined,
                          accentColor: const Color(0xFF00E5FF),
                          children: [
                            _buildMortalityDialogInfoTile(
                              icon: Icons.tag_outlined,
                              label: 'Record ID',
                              value: recordId,
                              accentColor: const Color(0xFF64B5F6),
                            ),
                            const SizedBox(height: 12),
                            _buildMortalityDialogInfoTile(
                              icon: Icons.verified_user_outlined,
                              label: 'Verification',
                              value: isEditing
                                  ? verification
                                  : 'Pending after creation',
                              accentColor: statusColor,
                              valueColor: statusColor,
                            ),
                            const SizedBox(height: 12),
                            _buildMortalityDialogInfoTile(
                              icon: Icons.rule_folder_outlined,
                              label: 'Required fields',
                              value: 'Patient Name, Age, and Cause of Death',
                              accentColor: const Color(0xFFFFB74D),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Cancel'),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isEditing
                      ? const [Color(0xFFFFB74D), Color(0xFFFF7043)]
                      : const [_primaryAqua, _secondaryIceBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: modeAccent.withValues(alpha: 0.24),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () async {
                  final didSave = isEditing
                      ? await _updateExistingRecord(
                          record,
                          nameController.text,
                          ageController.text,
                          selectedGender,
                          causeController.text,
                          placeController.text,
                          reportedByController.text,
                        )
                      : await _addNewRecord(
                          nameController.text,
                          ageController.text,
                          selectedGender,
                          causeController.text,
                          placeController.text,
                          reportedByController.text,
                          patientSeed!,
                        );

                  if (didSave && context.mounted) {
                    Navigator.pop(context);
                  }
                },
                icon: Icon(
                  isEditing
                      ? Icons.save_as_rounded
                      : Icons.library_add_check_rounded,
                  size: 18,
                ),
                label: Text(isEditing ? 'Update Record' : 'Save Record'),
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
    );
  }

  Widget _buildMortalityDialogMetaChip({
    required IconData icon,
    required String label,
    required String value,
    required Color accentColor,
    Color? valueColor,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.56),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: valueColor ?? Colors.white,
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

  Widget _buildMortalityDialogSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildMortalityDialogFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  InputDecoration _buildMortalityDialogInputDecoration({
    required String hintText,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: 14,
      ),
      filled: true,
      fillColor: _darkDeepTeal,
      prefixIcon: Icon(icon, color: Colors.white, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
    );
  }

  Widget _buildMortalityDialogNote({
    required String label,
    required String value,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.info_outline_rounded,
              color: accentColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
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
    );
  }

  Widget _buildMortalityDialogInfoTile({
    required IconData icon,
    required String label,
    required String value,
    required Color accentColor,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _addNewRecord(
    String name,
    String age,
    String gender,
    String cause,
    String place,
    String reportedBy,
    Map<String, dynamic> registeredPatient,
  ) async {
    final trimmedName = name.trim();
    final trimmedAge = age.trim();
    final trimmedCause = cause.trim();
    final trimmedPlace = place.trim();
    final trimmedReportedBy = reportedBy.trim();

    if (trimmedName.isEmpty || trimmedAge.isEmpty || trimmedCause.isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Please fill in all required fields (Name, Age, Cause of Death)',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFD84315),
        colorText: Colors.white,
      );
      return false;
    }

    final parsedAge = int.tryParse(trimmedAge);
    if (parsedAge == null) {
      Get.snackbar(
        'Validation Error',
        'Please enter a valid age.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFD84315),
        colorText: Colors.white,
      );
      return false;
    }

    try {
      final currentDate = DateTime.now().toString().split(' ')[0];
      final patientId =
          (registeredPatient['patientId'] ?? registeredPatient['id'] ?? '')
              .toString()
              .trim();
      final linkedPatientId =
          (registeredPatient['linkedPatientId'] ?? patientId).toString().trim();
      final newRecord = {
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'name': trimmedName,
        if (patientId.isNotEmpty) 'patientId': patientId,
        if (linkedPatientId.isNotEmpty) 'linkedPatientId': linkedPatientId,
        'date': currentDate,
        'month': _monthLabelForDate(currentDate),
        'age': parsedAge.toString(),
        'ageRange': _getAgeRange(parsedAge),
        'gender': gender,
        'causeOfDeath': trimmedCause,
        'place': trimmedPlace,
        'reportedBy': trimmedReportedBy,
        'verification': 'Pending',
        'dateReported': DateTime.now().toIso8601String(),
      };

      await _mortalityHelper.insertRecord(newRecord);

      Get.snackbar(
        'Success',
        'Record added successfully',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF4CAF50),
        colorText: Colors.white,
      );

      await _loadData();
      return true;
    } catch (e) {
      Get.snackbar(
        'Error',
        'Error adding record: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFD84315),
        colorText: Colors.white,
      );
      return false;
    }
  }

  Future<bool> _updateExistingRecord(
    Map<String, dynamic> existingRecord,
    String name,
    String age,
    String gender,
    String cause,
    String place,
    String reportedBy,
  ) async {
    final trimmedName = name.trim();
    final trimmedAge = age.trim();
    final trimmedCause = cause.trim();
    final trimmedPlace = place.trim();
    final trimmedReportedBy = reportedBy.trim();

    if (trimmedName.isEmpty || trimmedAge.isEmpty || trimmedCause.isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Please fill in all required fields (Name, Age, Cause of Death)',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFD84315),
        colorText: Colors.white,
      );
      return false;
    }

    final parsedAge = int.tryParse(trimmedAge);
    if (parsedAge == null) {
      Get.snackbar(
        'Validation Error',
        'Please enter a valid age.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFD84315),
        colorText: Colors.white,
      );
      return false;
    }

    try {
      final preservedDate = _safeText(
        existingRecord['date'],
        DateTime.now().toString().split(' ')[0],
      );
      final updatedRecord = Map<String, dynamic>.from(existingRecord)
        ..addAll({
          'name': trimmedName,
          'date': preservedDate,
          'month': _monthLabelForDate(
            preservedDate,
            fallback: _safeText(existingRecord['month'], ''),
          ),
          'age': parsedAge.toString(),
          'ageRange': _getAgeRange(parsedAge),
          'gender': gender,
          'causeOfDeath': trimmedCause,
          'place': trimmedPlace,
          'reportedBy': trimmedReportedBy,
          'verification': _safeText(existingRecord['verification'], 'Pending'),
          'dateReported':
              existingRecord['dateReported']?.toString() ??
              DateTime.now().toIso8601String(),
        });

      await _mortalityHelper.updateRecord(updatedRecord);

      Get.snackbar(
        'Success',
        'Record updated successfully',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF4CAF50),
        colorText: Colors.white,
      );

      await _loadData();
      return true;
    } catch (e) {
      Get.snackbar(
        'Error',
        'Error updating record: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFD84315),
        colorText: Colors.white,
      );
      return false;
    }
  }

  String _getAgeRange(int age) {
    if (age <= 18) return '0-18';
    if (age <= 40) return '19-40';
    if (age <= 60) return '41-60';
    if (age <= 80) return '61-80';
    return '81+';
  }

  String _monthLabelForDate(String dateValue, {String fallback = ''}) {
    const monthLabels = [
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

    final normalizedDate = dateValue.trim();
    if (normalizedDate.isNotEmpty) {
      try {
        final parsedDate = DateTime.parse(normalizedDate);
        return monthLabels[parsedDate.month - 1];
      } catch (_) {}
    }

    if (fallback.trim().isNotEmpty) {
      return fallback.trim();
    }

    return monthLabels[DateTime.now().month - 1];
  }

  void _viewRecordDetails(Map<String, dynamic> record) {
    final name = _safeText(record['name'], 'Unknown');
    final age = _safeText(record['age'], '-');
    final gender = _safeText(record['gender'], 'Unknown');
    final cause = _safeText(record['causeOfDeath'], 'No cause recorded');
    final place = _safeText(record['place'], 'No place recorded');
    final reportedBy = _safeText(record['reportedBy'], 'Unknown');
    final verification = _safeText(record['verification'], 'Pending');
    final recordId = _safeText(record['id'], 'No record ID');
    final patientId = _safeText(
      record['linkedPatientId'] ?? record['patientId'],
      '',
    );
    final dateOfDeath = _formatDate(record['date']);
    final reportedDate = _formatDate(record['dateReported'] ?? record['date']);
    final initials = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.substring(0, 1).toUpperCase())
        .join();

    showFullscreenDetailTableDialog(
      context: context,
      title: 'Mortality Record Details',
      subject: name,
      items: [
        DetailTableItem(
          icon: Icons.badge_outlined,
          label: 'Record ID',
          value: recordId,
        ),
        DetailTableItem(
          icon: Icons.credit_card_outlined,
          label: 'Patient ID',
          value: patientId,
        ),
        DetailTableItem(
          icon: Icons.person_outline_rounded,
          label: 'Patient Name',
          value: name,
        ),
        DetailTableItem(icon: Icons.cake_outlined, label: 'Age', value: age),
        DetailTableItem(
          icon: Icons.wc_outlined,
          label: 'Gender',
          value: gender,
        ),
        DetailTableItem(
          icon: Icons.coronavirus_outlined,
          label: 'Cause of Death',
          value: cause,
        ),
        DetailTableItem(
          icon: Icons.place_outlined,
          label: 'Place',
          value: place,
        ),
        DetailTableItem(
          icon: Icons.event_busy_outlined,
          label: 'Date of Death',
          value: dateOfDeath,
        ),
        DetailTableItem(
          icon: Icons.calendar_today_outlined,
          label: 'Date Reported',
          value: reportedDate,
        ),
        DetailTableItem(
          icon: Icons.verified_outlined,
          label: 'Verification',
          value: verification,
        ),
        DetailTableItem(
          icon: Icons.person_pin_outlined,
          label: 'Reported By',
          value: reportedBy,
        ),
        DetailTableItem(
          icon: Icons.notes_outlined,
          label: 'Remarks',
          value: _safeText(record['remarks'], ''),
        ),
      ],
    );
    return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (dialogContext) {
        final screenSize = MediaQuery.of(dialogContext).size;
        final isCompact = screenSize.width < 760;
        final statusColor = _getVerificationColor(verification);

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
                  color: _primaryAqua.withValues(alpha: 0.22),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.38),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
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
                          gradient: const LinearGradient(
                            colors: [Color(0xFF163B66), Color(0xFF0D274D)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border(
                            bottom: BorderSide(
                              color: _primaryAqua.withValues(alpha: 0.2),
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
                                  width: isCompact ? 58 : 68,
                                  height: isCompact ? 58 : 68,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF00E5FF),
                                        Color(0xFF2F80ED),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF00E5FF,
                                        ).withValues(alpha: 0.22),
                                        blurRadius: 18,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      initials.isEmpty ? 'MR' : initials,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: isCompact ? 22 : 26,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Mortality Record Details',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: isCompact ? 22 : 26,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        name,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.92,
                                          ),
                                          fontSize: isCompact ? 16 : 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Recorded on $reportedDate',
                                        style: TextStyle(
                                          color: _lightOffWhite.withValues(
                                            alpha: 0.7,
                                          ),
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
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
                                          alpha: 0.06,
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
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _buildMortalitySummaryChip(
                                  icon: Icons.verified_outlined,
                                  label: 'Status',
                                  value: verification,
                                  accentColor: statusColor,
                                  valueColor: statusColor,
                                ),
                                _buildMortalitySummaryChip(
                                  icon: Icons.cake_outlined,
                                  label: 'Age',
                                  value: age == 'N/A' || age == '-'
                                      ? 'Not recorded'
                                      : '$age years',
                                  accentColor: const Color(0xFFFFB74D),
                                ),
                                _buildMortalitySummaryChip(
                                  icon: Icons.wc_outlined,
                                  label: 'Gender',
                                  value: gender,
                                  accentColor: const Color(0xFF64B5F6),
                                ),
                                _buildMortalitySummaryChip(
                                  icon: Icons.location_on_outlined,
                                  label: 'Place',
                                  value: place,
                                  accentColor: const Color(0xFFE57373),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(isCompact ? 18 : 22),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final sectionWidth = isCompact
                                ? constraints.maxWidth
                                : (constraints.maxWidth - 16) / 2;

                            return Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                SizedBox(
                                  width: sectionWidth,
                                  child: _buildMortalityDetailSection(
                                    title: 'Personal Profile',
                                    icon: Icons.person_outline_rounded,
                                    accentColor: const Color(0xFF64B5F6),
                                    children: [
                                      _buildMortalityDetailField(
                                        label: 'Full Name',
                                        value: name,
                                        icon: Icons.badge_outlined,
                                      ),
                                      _buildMortalityDetailField(
                                        label: 'Age',
                                        value: age == 'N/A' || age == '-'
                                            ? 'Not recorded'
                                            : '$age years old',
                                        icon: Icons.cake_outlined,
                                      ),
                                      _buildMortalityDetailField(
                                        label: 'Gender',
                                        value: gender,
                                        icon: Icons.wc_outlined,
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: sectionWidth,
                                  child: _buildMortalityDetailSection(
                                    title: 'Record Tracking',
                                    icon: Icons.folder_open_outlined,
                                    accentColor: const Color(0xFF00E5FF),
                                    children: [
                                      _buildMortalityDetailField(
                                        label: 'Record ID',
                                        value: recordId,
                                        icon: Icons.tag_outlined,
                                      ),
                                      _buildMortalityDetailField(
                                        label: 'Date Reported',
                                        value: reportedDate,
                                        icon: Icons.event_note_outlined,
                                      ),
                                      _buildMortalityDetailField(
                                        label: 'Verification Status',
                                        value: verification,
                                        icon: Icons.verified_user_outlined,
                                        accentColor: statusColor,
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: sectionWidth,
                                  child: _buildMortalityDetailSection(
                                    title: 'Incident Details',
                                    icon: Icons.monitor_heart_outlined,
                                    accentColor: const Color(0xFFE57373),
                                    children: [
                                      _buildMortalityDetailField(
                                        label: 'Date of Death',
                                        value: dateOfDeath,
                                        icon: Icons.calendar_today_outlined,
                                      ),
                                      _buildMortalityDetailField(
                                        label: 'Cause of Death',
                                        value: cause,
                                        icon: Icons.coronavirus_outlined,
                                      ),
                                      _buildMortalityDetailField(
                                        label: 'Place',
                                        value: place,
                                        icon: Icons.location_on_outlined,
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: sectionWidth,
                                  child: _buildMortalityDetailSection(
                                    title: 'Reporting Information',
                                    icon: Icons.assignment_turned_in_outlined,
                                    accentColor: const Color(0xFF81C784),
                                    children: [
                                      _buildMortalityDetailField(
                                        label: 'Reported By',
                                        value: reportedBy,
                                        icon: Icons.person_search_outlined,
                                      ),
                                      _buildMortalityDetailField(
                                        label: 'Status Overview',
                                        value:
                                            'This case is currently marked as $verification.',
                                        icon: Icons.info_outline_rounded,
                                        accentColor: statusColor,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.fromLTRB(
                          isCompact ? 18 : 22,
                          14,
                          isCompact ? 18 : 22,
                          isCompact ? 18 : 22,
                        ),
                        decoration: BoxDecoration(
                          color: _sidebarDark.withValues(alpha: 0.78),
                          border: Border(
                            top: BorderSide(
                              color: Colors.white.withValues(alpha: 0.06),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.18),
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

  Widget _buildMortalitySummaryChip({
    required IconData icon,
    required String label,
    required String value,
    required Color accentColor,
    Color? valueColor,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accentColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: valueColor ?? Colors.white,
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

  Widget _buildMortalityDetailSection({
    required String title,
    required IconData icon,
    required Color accentColor,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _sidebarDark.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 14,
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
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildMortalityDetailField({
    required String label,
    required String value,
    required IconData icon,
    Color? accentColor,
  }) {
    final iconColor = accentColor ?? _primaryAqua;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _editRecord(Map<String, dynamic> record) {
    _showMortalityRecordDialog(record: record);
  }

  void _verifyRecord(Map<String, dynamic> record) {
    final name = _safeText(record['name'], 'Unknown');
    final age = _safeText(record['age'], '-');
    final gender = _safeText(record['gender'], 'Unknown');
    final verification = _safeText(record['verification'], 'Pending');
    final place = _safeText(record['place'], 'No place recorded');
    final cause = _safeText(record['causeOfDeath'], 'No cause recorded');
    final reportedBy = _safeText(record['reportedBy'], 'Unknown');
    final reportedDate = _formatDate(record['dateReported'] ?? record['date']);
    final recordId = _safeText(record['id'], 'Unavailable');
    final alreadyVerified = verification.toLowerCase().contains('verified');
    final initials = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.substring(0, 1).toUpperCase())
        .join();

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (dialogContext) {
        final screenSize = MediaQuery.of(dialogContext).size;
        final isCompact = screenSize.width < 720;
        final primaryAccent = alreadyVerified
            ? const Color(0xFF66BB6A)
            : const Color(0xFF81C784);
        final secondaryAccent = alreadyVerified
            ? const Color(0xFF2E7D32)
            : const Color(0xFF43A047);
        final dialogBorderColor = primaryAccent.withValues(alpha: 0.22);

        Widget impactTile({
          required IconData icon,
          required String title,
          required String subtitle,
        }) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: primaryAccent.withValues(alpha: 0.12)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: primaryAccent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: primaryAccent, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.64),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(
            horizontal: isCompact ? 16 : 28,
            vertical: 24,
          ),
          child: Container(
            constraints: BoxConstraints(maxWidth: isCompact ? 520 : 640),
            decoration: BoxDecoration(
              color: _darkDeepTeal,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: dialogBorderColor, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.36),
                  blurRadius: 30,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(isCompact ? 20 : 22),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: alreadyVerified
                            ? const [Color(0xFF23443A), Color(0xFF10261F)]
                            : const [Color(0xFF1A4A38), Color(0xFF0D274D)],
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
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [primaryAccent, secondaryAccent],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryAccent.withValues(
                                      alpha: 0.24,
                                    ),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: alreadyVerified
                                    ? const Icon(
                                        Icons.verified_rounded,
                                        color: Colors.white,
                                        size: 28,
                                      )
                                    : Text(
                                        initials.isEmpty ? 'MR' : initials,
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    alreadyVerified
                                        ? 'Record Already Verified'
                                        : 'Confirm Verification',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 23,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    alreadyVerified
                                        ? 'This mortality record is already secured as verified and reflected in record status tracking.'
                                        : 'Review the record snapshot below before finalizing verification for this mortality case.',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.72,
                                      ),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => Navigator.of(dialogContext).pop(),
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
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
                                primaryAccent.withValues(alpha: 0.18),
                                Colors.white.withValues(alpha: 0.02),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: primaryAccent.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: primaryAccent.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  alreadyVerified
                                      ? Icons.fact_check_rounded
                                      : Icons.gpp_good_rounded,
                                  color: primaryAccent,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      alreadyVerified
                                          ? 'Verification already completed'
                                          : 'Ready to promote this case to verified',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      alreadyVerified
                                          ? 'No additional action is needed unless the record must be edited later.'
                                          : 'Confirming will change the case status from Pending to Verified and refresh the dashboard metrics.',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.68,
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
                                  color: primaryAccent.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  verification,
                                  style: TextStyle(
                                    color: primaryAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(isCompact ? 18 : 22),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final sectionWidth = isCompact
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 16) / 2;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _buildMortalityDialogMetaChip(
                                    icon: Icons.person_outline_rounded,
                                    label: 'Patient',
                                    value: name,
                                    accentColor: const Color(0xFF64B5F6),
                                  ),
                                  _buildMortalityDialogMetaChip(
                                    icon: Icons.calendar_today_outlined,
                                    label: 'Reported',
                                    value: reportedDate,
                                    accentColor: const Color(0xFFFFB74D),
                                  ),
                                  _buildMortalityDialogMetaChip(
                                    icon: Icons.verified_outlined,
                                    label: 'Status',
                                    value: verification,
                                    accentColor: primaryAccent,
                                    valueColor: primaryAccent,
                                  ),
                                  _buildMortalityDialogMetaChip(
                                    icon: Icons.tag_outlined,
                                    label: 'Record ID',
                                    value: recordId,
                                    accentColor: primaryAccent,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                children: [
                                  SizedBox(
                                    width: sectionWidth,
                                    child: _buildMortalityDialogSection(
                                      title: 'Record Snapshot',
                                      subtitle:
                                          'Core patient and reporting details used for verification review.',
                                      icon: Icons.folder_open_outlined,
                                      accentColor: const Color(0xFF64B5F6),
                                      children: [
                                        _buildMortalityDialogInfoTile(
                                          icon: Icons.person_outline_rounded,
                                          label: 'Patient',
                                          value: '$name, $age years, $gender',
                                          accentColor: const Color(0xFF64B5F6),
                                        ),
                                        const SizedBox(height: 12),
                                        _buildMortalityDialogInfoTile(
                                          icon: Icons.person_search_outlined,
                                          label: 'Reported By',
                                          value: reportedBy,
                                          accentColor: const Color(0xFF81C784),
                                        ),
                                        const SizedBox(height: 12),
                                        _buildMortalityDialogInfoTile(
                                          icon: Icons.location_on_outlined,
                                          label: 'Place',
                                          value: place,
                                          accentColor: const Color(0xFFFFB74D),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: sectionWidth,
                                    child: _buildMortalityDialogSection(
                                      title: alreadyVerified
                                          ? 'Verification Outcome'
                                          : 'Verification Impact',
                                      subtitle: alreadyVerified
                                          ? 'This case already meets the verified status requirement.'
                                          : 'These updates will happen immediately after you confirm.',
                                      icon: alreadyVerified
                                          ? Icons.verified_user_outlined
                                          : Icons.privacy_tip_outlined,
                                      accentColor: primaryAccent,
                                      children: [
                                        impactTile(
                                          icon: Icons.sync_alt_rounded,
                                          title: alreadyVerified
                                              ? 'Status already confirmed'
                                              : 'Status will switch to Verified',
                                          subtitle: alreadyVerified
                                              ? 'The record is no longer waiting for review.'
                                              : 'Pending will be replaced with Verified in the records table.',
                                        ),
                                        const SizedBox(height: 12),
                                        impactTile(
                                          icon: Icons
                                              .dashboard_customize_outlined,
                                          title:
                                              'Dashboard metrics stay aligned',
                                          subtitle:
                                              'Mortality totals and verification rate will reflect the latest saved status.',
                                        ),
                                        const SizedBox(height: 12),
                                        impactTile(
                                          icon: Icons.fact_check_outlined,
                                          title: 'Review confidence improves',
                                          subtitle:
                                              'Verified cases are easier to distinguish during audits, exports, and reporting.',
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildMortalityDialogSection(
                                title: 'Clinical Review',
                                subtitle: alreadyVerified
                                    ? 'Diagnosis and verification context already attached to this verified case.'
                                    : 'Use these case details as the last checkpoint before confirming verification.',
                                icon: Icons.monitor_heart_outlined,
                                accentColor: const Color(0xFFE57373),
                                children: [
                                  _buildMortalityDialogInfoTile(
                                    icon: Icons.coronavirus_outlined,
                                    label: 'Cause of Death',
                                    value: cause,
                                    accentColor: const Color(0xFFE57373),
                                  ),
                                  const SizedBox(height: 12),
                                  _buildMortalityDialogInfoTile(
                                    icon: Icons.verified_outlined,
                                    label: 'Current Status',
                                    value: verification,
                                    accentColor: primaryAccent,
                                    valueColor: primaryAccent,
                                  ),
                                  if (!alreadyVerified) ...[
                                    const SizedBox(height: 12),
                                    _buildMortalityDialogNote(
                                      label: 'Verification note',
                                      value:
                                          'Verification is best used after you have reviewed the patient details, cause of death, and reporting source for accuracy.',
                                      accentColor: primaryAccent,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          );
                        },
                      ),
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
                      color: _sidebarDark.withValues(alpha: 0.8),
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
                          onPressed: () => Navigator.of(dialogContext).pop(),
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
                          child: Text(alreadyVerified ? 'Close' : 'Cancel'),
                        ),
                        if (!alreadyVerified) ...[
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [primaryAccent, secondaryAccent],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryAccent.withValues(alpha: 0.24),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                Navigator.of(dialogContext).pop();
                                await _confirmRecordVerification(record);
                              },
                              icon: const Icon(
                                Icons.verified_user_rounded,
                                size: 18,
                              ),
                              label: const Text('Verify Record'),
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmRecordVerification(Map<String, dynamic> record) async {
    final name = _safeText(record['name'], 'Unknown');

    try {
      final updatedRecord = Map<String, dynamic>.from(record)
        ..['verification'] = 'Verified';

      await _mortalityHelper.updateRecord(updatedRecord);
      await _loadData();

      Get.snackbar(
        'Verification Complete',
        '$name has been marked as verified.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF4CAF50),
        colorText: Colors.white,
      );
    } catch (e) {
      Get.snackbar(
        'Verification Failed',
        'Unable to verify $name: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFD84315),
        colorText: Colors.white,
      );
    }
  }

  Future<void> _printRecord(Map<String, dynamic> record) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF607D8B)),
      ),
    );

    // Let the loading dialog paint before running synchronous PDF work.
    await Future<void>.delayed(const Duration(milliseconds: 16));

    try {
      final pdfBytes = await buildMortalityPdfBytes(record);
      final filename = buildMortalityPdfFilename(record);
      final downloaded = downloadFile(
        bytes: pdfBytes,
        filename: filename,
        mimeType: 'application/pdf',
      );

      Get.snackbar(
        downloaded ? 'PDF Generated' : 'PDF Unsupported',
        downloaded
            ? 'PDF generated for ${record['name']}'
            : 'PDF generation is not supported on this platform.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: downloaded ? const Color(0xFF607D8B) : Colors.orange,
        colorText: Colors.white,
      );
    } catch (e) {
      Get.snackbar(
        'PDF Error',
        'Failed to generate mortality PDF: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }
}

// Data Models for Charts
class MonthlyTrend {
  final String month;
  final int deaths;

  MonthlyTrend(this.month, this.deaths);
}

class CauseData {
  final String cause;
  final int count;
  final double percentage;

  CauseData(this.cause, this.count, this.percentage);
}

class AgeDistribution {
  final String ageRange;
  final int count;
  final double percentage;

  AgeDistribution(this.ageRange, this.count, this.percentage);
}
