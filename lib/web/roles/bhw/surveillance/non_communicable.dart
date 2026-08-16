import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'package:mycapstone_project/web/roles/bhw/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_history_dialogs.dart';
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
import 'package:mycapstone_project/web/roles/bhw/surveillance/mortality.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/shared/components/app_metric_card.dart';
import 'package:mycapstone_project/web/shared/components/fullscreen_detail_table_dialog.dart';
import 'package:mycapstone_project/web/shared/components/module_view_components.dart';
import 'package:mycapstone_project/web/shared/components/web_data_components.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/shared/current_table_record_utils.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/communicable_insights.dart';

const Color _primaryAqua = Color(0xFF2F80ED);
const Color _secondaryIceBlue = Color(0xFF163B66);
const Color _darkDeepTeal = Color(0xFF071A33);
const Color _mutedCoolGray = Color(0xFF4B6075);
const Color _sidebarDark = Colors.white;

final RegExp _vitalLabelPattern = RegExp(
  r'\b(?:BP|Temp|HR|Bpm|bprm|O2|Weight|Height):',
  caseSensitive: false,
);

Widget _buildHighlightedVitalLabelText(
  String text, {
  required TextStyle baseStyle,
  int? maxLines,
  TextOverflow overflow = TextOverflow.clip,
}) {
  final matches = _vitalLabelPattern.allMatches(text).toList();
  if (matches.isEmpty) {
    return Text(text, style: baseStyle, maxLines: maxLines, overflow: overflow);
  }

  final spans = <TextSpan>[];
  var start = 0;

  for (final match in matches) {
    if (match.start > start) {
      spans.add(
        TextSpan(text: text.substring(start, match.start), style: baseStyle),
      );
    }

    spans.add(
      TextSpan(
        text: text.substring(match.start, match.end),
        style: baseStyle.copyWith(color: const Color(0xFF60A5FA)),
      ),
    );
    start = match.end;
  }

  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start), style: baseStyle));
  }

  return RichText(
    text: TextSpan(children: spans),
    maxLines: maxLines,
    overflow: overflow,
  );
}

class HistoryItem {
  final String label;
  final String value;

  HistoryItem(this.label, this.value);
}

class NonCommunicablePage extends StatefulWidget {
  const NonCommunicablePage({super.key});

  @override
  State<NonCommunicablePage> createState() => _NonCommunicablePageState();
}

class _NonCommunicablePageState extends State<NonCommunicablePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _isLoadingMetrics = false;
  HealthModuleView? _selectedView;

  HealthModuleView get _resolvedView =>
      _selectedView ?? healthModuleViewFromUrl();

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Selection mode
  bool _isSelectionMode = false;
  Set<String>? _selectedPatientIds;
  int _currentPage = 1;
  int _rowsPerPage = 10;

  Set<String> get _getSelectedPatientIds {
    _selectedPatientIds ??= <String>{};
    return _selectedPatientIds!;
  }

  // Data from check-up database
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _filteredPatients = [];
  List<Map<String, dynamic>> _nonCommunicableRecords = [];

  int get _activeCases => _nonCommunicableRecords.length;

  Map<String, int> get _diseaseTypes {
    final result = <String, int>{};
    for (final record in _nonCommunicableRecords) {
      final condition = (record['condition'] ?? 'Unknown').toString();
      result[condition] = (result[condition] ?? 0) + 1;
    }
    return result;
  }

  double get _controlRate {
    if (_nonCommunicableRecords.isEmpty) return 0;
    final completed = _nonCommunicableRecords.where((record) {
      final status = (record['currentStatus'] ?? record['status'] ?? '')
          .toString()
          .toLowerCase();
      return status.contains('complete') || status.contains('recover');
    }).length;
    return completed / _nonCommunicableRecords.length * 100;
  }

  @override
  void initState() {
    super.initState();
    _selectedView = healthModuleViewFromUrl();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) =>
          persistHealthModuleView(WebRoutes.bhwNonCommunicable, _resolvedView),
    );
    _dbHelper.startConnectivityListener();
    _loadPatients();
  }

  void _setActiveView(HealthModuleView view) {
    if (_resolvedView == view) return;
    setState(() {
      _selectedView = view;
      _isSelectionMode = false;
      _getSelectedPatientIds.clear();
    });
    persistHealthModuleView(WebRoutes.bhwNonCommunicable, view);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _extractAge(String details) {
    final ageMatch = RegExp(r'Age: (\d+)').firstMatch(details);
    return ageMatch?.group(1) ?? 'N/A';
  }

  List<Map<String, dynamic>> _collapseCurrentPatients(
    List<Map<String, dynamic>> patients,
  ) {
    final collapsed = CurrentTableRecordUtils.collapseToLatestPerEntity(
      patients,
      idKeys: const ['patientId', 'patientCode'],
      nameKeys: const ['patientName'],
      dateKeys: const ['lastVisit', 'nextVisit', 'datetime'],
    );

    return collapsed.map((patient) {
      final current = Map<String, dynamic>.from(patient);
      current['totalVisits'] =
          patient['tableHistoryCount'] ?? patient['totalVisits'] ?? 1;
      return current;
    }).toList();
  }

  Future<void> _loadPatients() async {
    if (mounted) {
      setState(() => _isLoadingMetrics = true);
    }
    try {
      // Sync from Firebase first
      await _dbHelper.syncFromFirebase();

      // Load non-communicable disease records from check-up database
      final allRecords = await _dbHelper.getAllRecords();

      // Filter for non-communicable diseases only
      final nonCommunicableRecords = allRecords.where((record) {
        final type = (record['diseaseType'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        return type == 'non-communicable' ||
            type == 'non communicable' ||
            type == 'non-communicable disease';
      }).toList();

      final currentPatients = _collapseCurrentPatients(
        nonCommunicableRecords.map((record) {
          return {
            'id': record['id'] ?? '',
            'patientId': record['linkedPatientId'] ?? record['patientId'] ?? '',
            'patientCode': record['patientCode'] ?? '',
            'patientName':
                record['patientName'] ?? record['patient'] ?? 'Unknown',
            'age': record['age'] ?? _extractAge(record['details'] ?? ''),
            'gender': record['gender'] ?? 'N/A',
            'condition':
                record['condition'] ?? record['details'] ?? 'No details',
            'lastVisit':
                record['lastVisit'] ??
                record['datetime']?.split(' ')[0] ??
                'N/A',
            'nextVisit': record['nextVisit'] ?? 'N/A',
            'currentStatus':
                record['currentStatus'] ?? record['status'] ?? 'Pending',
            'treatment':
                record['treatment'] ?? record['plan'] ?? 'No treatment plan',
            'bloodPressure': record['bloodPressure'] ?? 'N/A',
            'bloodSugar': record['bloodSugar'] ?? 'N/A',
            'totalVisits': record['totalVisits'] ?? 0,
            'notes': record['notes'] ?? '',
          };
        }).toList(),
      );

      setState(() {
        _nonCommunicableRecords = nonCommunicableRecords;
        _patients = currentPatients;
        _filteredPatients = List.from(_patients);
        _currentPage = 1;
        _isLoadingMetrics = false;
      });
    } catch (e) {
      print('Error loading patients: $e');
      if (mounted) {
        setState(() => _isLoadingMetrics = false);
      }
    }
  }

  void _filterPatients(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredPatients = List.from(_patients);
      } else {
        _filteredPatients = _patients.where((patient) {
          return patient['patientName'].toString().toLowerCase().contains(
                _searchQuery,
              ) ||
              patient['condition'].toString().toLowerCase().contains(
                _searchQuery,
              ) ||
              patient['currentStatus'].toString().toLowerCase().contains(
                _searchQuery,
              );
        }).toList();
      }
      _currentPage = 1;
    });
  }

  Color _getStatusColor(String status) {
    final lower = status.toLowerCase();
    if (lower.contains('stable') ||
        lower.contains('controlled') ||
        lower.contains('completed') ||
        lower.contains('recovered') ||
        lower.contains('recovering')) {
      return const Color(0xFF4CAF50);
    }
    if (lower.contains('critical') || lower.contains('risk')) {
      return const Color(0xFFD84315);
    }
    if (lower.contains('monitor') ||
        lower.contains('pending') ||
        lower.contains('review')) {
      return const Color(0xFFFFA726);
    }
    if (lower.contains('treatment') || lower.contains('progress')) {
      return const Color(0xFF2196F3);
    }
    return _mutedCoolGray;
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
        activeItem: WebSidebarItem.nonCommunicable,
      ),
      body: Column(
        children: [
          // Top Bar
          _buildTopBar(context),

          // Content Area
          Expanded(
            child: RefreshIndicator(
              backgroundColor: const Color(0xFFF5F7FA),
              color: _primaryAqua,
              onRefresh: () async {
                await _loadPatients();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HealthModuleViewHeader(
                      title: 'Non-Communicable Disease Management',
                      description:
                          'Review chronic-disease trends and case outcomes, or manage individual non-communicable records.',
                      activeView: _resolvedView,
                      onViewChanged: _setActiveView,
                      primaryColor: _primaryAqua,
                      recordsLabel: 'List of Records',
                    ),
                    const SizedBox(height: 20),
                    if (_resolvedView == HealthModuleView.insights)
                      if (_isLoadingMetrics)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(
                              color: _primaryAqua,
                            ),
                          ),
                        )
                      else if (_nonCommunicableRecords.isEmpty)
                        const ModuleEmptyState(
                          title: 'No non-communicable insights yet',
                          message:
                              'Non-communicable analytics will appear after records are saved in Firebase.',
                          icon: Icons.health_and_safety_outlined,
                        )
                      else
                        CommunicableInsights(
                          records: _nonCommunicableRecords,
                          caseLabel: 'Non-Communicable',
                        )
                    else ...[
                      _buildSearchBar(),
                      const SizedBox(height: 20),
                      _buildPatientCards(),
                    ],
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

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: _darkDeepTeal,
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
            'Non-Communicable Disease Management',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (_isSelectionMode) const SizedBox(width: 12),
          if (_isSelectionMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _primaryAqua.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_getSelectedPatientIds.length} selected',
                style: const TextStyle(
                  color: _primaryAqua,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (_isSelectionMode) const SizedBox(width: 12),
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.select_all_rounded),
              tooltip: 'Select All',
              onPressed: () {
                setState(() {
                  _getSelectedPatientIds.clear();
                  for (final patient in _filteredPatients) {
                    final patientId = patient['id'] as String? ?? '';
                    if (patientId.isNotEmpty) {
                      _getSelectedPatientIds.add(patientId);
                    }
                  }
                });
              },
              color: _mutedCoolGray,
              iconSize: 28,
            ),
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.clear_rounded),
              tooltip: 'Cancel Selection',
              onPressed: () {
                setState(() {
                  _isSelectionMode = false;
                  _getSelectedPatientIds.clear();
                });
              },
              color: _mutedCoolGray,
              iconSize: 28,
            ),
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete_rounded),
              tooltip: 'Delete Selected',
              onPressed: _getSelectedPatientIds.isEmpty
                  ? null
                  : _showDeleteConfirmationModal,
              color: _getSelectedPatientIds.isEmpty ? Colors.grey : Colors.red,
              iconSize: 28,
            ),
        ],
      ),
    );
  }

  Widget _buildDrawerContent(BuildContext context, String userName) {
    final user = FirebaseAuth.instance.currentUser;
    return Container(
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
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
              children: [
                _buildDrawerSidebarItem(
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  onTap: () {
                    Navigator.pop(context);
                    Get.toNamed(WebRoutes.bhwDashboard);
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
                  onTap: () {
                    Navigator.pop(context);
                  },
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
                      Icon(Icons.logout_rounded, color: Colors.white, size: 16),
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

  Widget _buildDrawer(BuildContext context, String userName) {
    return Drawer(child: _buildDrawerContent(context, userName));
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

  // Overview Dashboard Section
  Widget _buildOverviewDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isLoadingMetrics)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: _primaryAqua),
            ),
          )
        else
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 2.2,
            children: [
              _buildWebMetricCard(
                title: 'Active Cases',
                value: _activeCases.toString(),
                subtitle: 'Non-communicable cases',
                icon: Icons.people_outline,
              ),
              _buildWebMetricCard(
                title: 'Control Rate',
                value: '${_controlRate.toStringAsFixed(1)}%',
                subtitle: 'Cases completed',
                icon: Icons.trending_up_outlined,
              ),
              _buildWebMetricCard(
                title: 'Disease Types',
                value: _diseaseTypes.length.toString(),
                subtitle: 'Types tracked',
                icon: Icons.medical_services_outlined,
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildWebSectionHeader({
    required String title,
    required IconData icon,
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
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              if (onRefresh != null)
                IconButton(
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: Colors.white,
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

  Widget _buildDiseaseTypeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
            children: [
              Icon(Icons.medical_services, color: _primaryAqua, size: 24),
              const SizedBox(width: 8),
              Text(
                'Disease Types',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _darkDeepTeal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._diseaseTypes.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    entry.key,
                    style: TextStyle(fontSize: 14, color: _darkDeepTeal),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      entry.value.toString(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _primaryAqua,
                      ),
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

  // Search Bar
  Widget _buildSearchBar() {
    return WebSearchField(
      controller: _searchController,
      hintText: 'Search by patient name, condition, or status...',
      onChanged: _filterPatients,
      onClear: () {
        _searchController.clear();
        _filterPatients('');
      },
    );
  }

  // Patient Cards
  Widget _buildPatientCards() {
    if (_filteredPatients.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: _mutedCoolGray.withValues(alpha: 0.55),
              ),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isEmpty
                    ? 'No patients found'
                    : 'No results for "$_searchQuery"',
                style: TextStyle(fontSize: 16, color: const Color(0xFF0B1F3A)),
              ),
            ],
          ),
        ),
      );
    }

    final totalRecords = _filteredPatients.length;
    final effectiveRowsPerPage = _rowsPerPage > 0 ? _rowsPerPage : 10;
    final totalPages = totalRecords == 0
        ? 1
        : ((totalRecords + effectiveRowsPerPage - 1) ~/ effectiveRowsPerPage);
    final currentPage = _currentPage < 1
        ? 1
        : (_currentPage > totalPages ? totalPages : _currentPage);
    final startIndex = totalRecords == 0
        ? 0
        : (currentPage - 1) * effectiveRowsPerPage;
    final endIndex = totalRecords == 0
        ? 0
        : min(startIndex + effectiveRowsPerPage, totalRecords);
    final pagedPatients = totalRecords == 0
        ? <Map<String, dynamic>>[]
        : _filteredPatients.sublist(startIndex, endIndex);

    return Column(
      children: [
        WebTableSurface(
          minWidth: 1180,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _buildPatientTableHeader(),
                ...pagedPatients.map(_buildPatientCard),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildTablePagination(
          currentPage: currentPage,
          totalPages: totalPages,
          startIndex: startIndex,
          endIndex: endIndex,
          totalRecords: totalRecords,
        ),
      ],
    );
  }

  Widget _buildPatientTableHeaderCell(String label, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          label,
          style: TextStyle(
            color: const Color(0xFF0B1F3A),
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

  Widget _buildPatientTableHeaderDivider() {
    return Container(width: 1, height: 18, color: const Color(0xFFD9E5F2));
  }

  Widget _buildPatientTableHeader() {
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
          _buildPatientTableHeaderCell('Patient', flex: 26),
          _buildPatientTableHeaderDivider(),
          _buildPatientTableHeaderCell('Condition', flex: 20),
          _buildPatientTableHeaderDivider(),
          _buildPatientTableHeaderCell('Treatment', flex: 18),
          _buildPatientTableHeaderDivider(),
          _buildPatientTableHeaderCell('Last Visit', flex: 12),
          _buildPatientTableHeaderDivider(),
          _buildPatientTableHeaderCell('Next Visit', flex: 12),
          _buildPatientTableHeaderDivider(),
          _buildPatientTableHeaderCell('Status', flex: 14),
          if (!_isSelectionMode) ...[
            _buildPatientTableHeaderDivider(),
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

  Widget _buildPatientRowDivider() {
    return Container(width: 1, height: 70, color: const Color(0xFF26476B));
  }

  Widget _buildTableActionButton({
    required IconData icon,
    required VoidCallback onTap,
    Color backgroundColor = const Color(0xFF163B66),
    Color iconColor = Colors.white,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withValues(alpha: 0.28),
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
            child: Icon(icon, color: iconColor, size: 15),
          ),
        ),
      ),
    );
  }

  Widget _buildTablePagination({
    required int currentPage,
    required int totalPages,
    required int startIndex,
    required int endIndex,
    required int totalRecords,
  }) {
    final startLabel = totalRecords == 0 ? 0 : startIndex + 1;
    final canGoPrev = currentPage > 1;
    final canGoNext = currentPage < totalPages;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Text(
            'Showing $startLabel-$endIndex of $totalRecords',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _primaryAqua.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _rowsPerPage,
                dropdownColor: AppColors.surfaceLight,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                ),
                icon: const Icon(
                  Icons.arrow_drop_down,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
                items: const [5, 10, 20, 50]
                    .map(
                      (rows) => DropdownMenuItem<int>(
                        value: rows,
                        child: Text('$rows / page'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _rowsPerPage = value;
                    _currentPage = 1;
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: canGoPrev
                ? () => setState(() => _currentPage = currentPage - 1)
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
            color: canGoPrev ? _primaryAqua : AppColors.borderStrong,
            tooltip: 'Previous page',
          ),
          Text(
            '$currentPage / $totalPages',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            onPressed: canGoNext
                ? () => setState(() => _currentPage = currentPage + 1)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
            color: canGoNext ? _primaryAqua : AppColors.borderStrong,
            tooltip: 'Next page',
          ),
        ],
      ),
    );
  }

  Widget _buildPatientCard(Map<String, dynamic> patient) {
    final patientId = patient['id']?.toString() ?? '';
    final isSelected =
        patientId.isNotEmpty && _getSelectedPatientIds.contains(patientId);
    final patientName = patient['patientName']?.toString() ?? 'Unknown';
    final age = patient['age']?.toString() ?? 'N/A';
    final gender = patient['gender']?.toString() ?? 'N/A';
    final condition = patient['condition']?.toString() ?? 'No details';
    final treatment = patient['treatment']?.toString() ?? 'No treatment plan';
    final lastVisit = _formatDate(patient['lastVisit']?.toString() ?? 'N/A');
    final nextVisit = _formatDate(patient['nextVisit']?.toString() ?? 'N/A');
    final status = patient['currentStatus']?.toString() ?? 'Pending';
    final statusColor = _getStatusColor(status);

    const rowBg = Colors.white;
    const rowText = Color(0xFF0B1F3A);
    const mutedText = Color(0xFF546E7A);

    return GestureDetector(
      onTap: _isSelectionMode && patientId.isNotEmpty
          ? () {
              setState(() {
                if (isSelected) {
                  _getSelectedPatientIds.remove(patientId);
                } else {
                  _getSelectedPatientIds.add(patientId);
                }
              });
            }
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
              if (_isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: patientId.isEmpty
                        ? null
                        : (value) {
                            setState(() {
                              if (value ?? false) {
                                _getSelectedPatientIds.add(patientId);
                              } else {
                                _getSelectedPatientIds.remove(patientId);
                              }
                            });
                          },
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
                    Text(
                      '$age years, $gender',
                      style: const TextStyle(
                        color: mutedText,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${patientId.isEmpty ? '-' : patientId}',
                      style: const TextStyle(
                        color: Color(0xFF8BDCF0),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _buildPatientRowDivider(),
              Expanded(
                flex: 20,
                child: _buildHighlightedVitalLabelText(
                  condition,
                  baseStyle: const TextStyle(
                    color: rowText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _buildPatientRowDivider(),
              Expanded(
                flex: 18,
                child: Text(
                  treatment,
                  style: const TextStyle(
                    color: mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _buildPatientRowDivider(),
              Expanded(
                flex: 12,
                child: Text(
                  lastVisit,
                  style: const TextStyle(
                    color: rowText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _buildPatientRowDivider(),
              Expanded(
                flex: 12,
                child: Text(
                  nextVisit,
                  style: const TextStyle(
                    color: mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _buildPatientRowDivider(),
              Expanded(
                flex: 14,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
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
                ),
              ),
              if (!_isSelectionMode) ...[
                _buildPatientRowDivider(),
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 2),
                  child: SizedBox(
                    width: 112,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildTableActionButton(
                          icon: Icons.visibility_rounded,
                          onTap: () => _viewPatientDetails(patient),
                        ),
                        const SizedBox(width: 6),
                        _buildTableActionButton(
                          icon: Icons.edit_rounded,
                          onTap: () => _editPatient(patient),
                        ),
                        const SizedBox(width: 6),
                        _buildTableActionButton(
                          icon: Icons.history_rounded,
                          onTap: () => _viewHistory(patient),
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

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.month}/${date.day}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  void _showDeleteConfirmationModal() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _sidebarDark,
        title: const Text(
          'Delete Selected Records',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Are you sure you want to delete ${_getSelectedPatientIds.length} patient record${_getSelectedPatientIds.length > 1 ? 's' : ''}?',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning,
                      color: Colors.red.withValues(alpha: 0.7),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This action cannot be undone.',
                        style: TextStyle(
                          color: Colors.red.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
          TextButton(
            onPressed: () {
              _deleteSelectedPatients();
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelectedPatients() async {
    try {
      final deletedCount = _getSelectedPatientIds.length;
      for (final patientId in _getSelectedPatientIds) {
        // Find the patient to delete
        final patient = _patients.firstWhere(
          (p) => p['id'] == patientId,
          orElse: () => {},
        );

        if (patient.isNotEmpty) {
          // Delete from database
          await _dbHelper.deleteRecord(patientId);

          // Remove from local lists
          _patients.removeWhere((p) => p['id'] == patientId);
          _filteredPatients.removeWhere((p) => p['id'] == patientId);
        }
      }

      setState(() {
        _getSelectedPatientIds.clear();
        _isSelectionMode = false;
        _currentPage = 1;
      });

      // Refresh the shared record source used by both Records and Insights.
      await _loadPatients();

      Get.snackbar(
        'Success',
        '$deletedCount patient record${deletedCount > 1 ? 's' : ''} deleted successfully',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF4CAF50),
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      print('Error deleting patients: $e');
      Get.snackbar(
        'Error',
        'Failed to delete patient records',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  // Action Methods
  void _showSettingsMenu() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _sidebarDark,
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text(
                  'Select Data',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Enable selection mode to select and manage records',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
                trailing: const Icon(Icons.arrow_forward, color: _primaryAqua),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _isSelectionMode = true;
                    _getSelectedPatientIds.clear();
                  });
                },
              ),
              if (kDebugMode) const Divider(color: _primaryAqua),
              if (kDebugMode)
                ListTile(
                  title: const Text(
                    'Seed 100 Sample Data',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    'Generate 100 complete patient records',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward,
                    color: _primaryAqua,
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _seedSampleData();
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: _primaryAqua)),
          ),
        ],
      ),
    );
  }

  Future<void> _seedSampleData() async {
    Get.snackbar(
      'Policy enforced',
      'Sample data initialization is disabled. Non-communicable datasets now populate only from actual barangay transactions.',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.orange,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
    );
  }

  Future<void> _showAddPatientDialog() async {
    // Use the same canonical registration modal exposed by Patient Records
    // instead of leaving this module on a non-functional placeholder.
    await Get.toNamed(
      WebRoutes.bhwPatients,
      arguments: const {'openRegistrationOnLoad': true},
    );
  }

  void _viewPatientDetails(Map<String, dynamic> patient) {
    final ageText = detailText(patient['age']);

    showFullscreenDetailTableDialog(
      context: context,
      title: 'Non-Communicable Details',
      subject: detailText(patient['patientName'], fallback: 'Unknown Patient'),
      items: [
        DetailTableItem(
          icon: Icons.badge_outlined,
          label: 'Patient ID',
          value: detailText(patient['id']),
        ),
        DetailTableItem(
          icon: Icons.person_outline_rounded,
          label: 'Patient Name',
          value: detailText(
            patient['patientName'],
            fallback: 'Unknown Patient',
          ),
        ),
        DetailTableItem(
          icon: Icons.cake_outlined,
          label: 'Age',
          value: ageText.isEmpty ? '' : '$ageText years',
        ),
        DetailTableItem(
          icon: Icons.wc_outlined,
          label: 'Gender',
          value: detailText(patient['gender']),
        ),
        DetailTableItem(
          icon: Icons.medical_information_outlined,
          label: 'Condition',
          value: detailText(patient['condition']),
        ),
        DetailTableItem(
          icon: Icons.verified_outlined,
          label: 'Status',
          value: detailText(patient['currentStatus']),
        ),
        DetailTableItem(
          icon: Icons.healing_outlined,
          label: 'Treatment',
          value: detailText(patient['treatment']),
        ),
        DetailTableItem(
          icon: Icons.monitor_heart_outlined,
          label: 'Blood Pressure',
          value: detailText(patient['bloodPressure']),
        ),
        DetailTableItem(
          icon: Icons.thermostat_outlined,
          label: 'Blood Sugar',
          value: detailText(patient['bloodSugar']),
        ),
        DetailTableItem(
          icon: Icons.history_outlined,
          label: 'Last Visit',
          value: detailText(patient['lastVisit']),
        ),
        DetailTableItem(
          icon: Icons.event_available_outlined,
          label: 'Next Visit',
          value: detailText(patient['nextVisit']),
        ),
        DetailTableItem(
          icon: Icons.notes_outlined,
          label: 'Notes',
          value: detailText(patient['notes']),
        ),
      ],
    );
    return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: _sidebarDark,
        alignment: Alignment.center,
        elevation: 8,
        child: Container(
          width: 700,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: _sidebarDark,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with title and close button
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      patient['patientName'],
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(8),
                        hoverColor: _primaryAqua.withValues(alpha: 0.1),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withValues(alpha: 0.7),
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Divider
              Divider(
                color: _primaryAqua.withValues(alpha: 0.2),
                height: 1,
                thickness: 1,
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildInfoItem('Patient ID', patient['id']),
                      _buildInfoItem('Age', '${patient['age']} years'),
                      _buildInfoItem('Gender', patient['gender']),
                      _buildInfoItem('Condition', patient['condition']),
                      _buildInfoItem('Status', patient['currentStatus']),
                      _buildInfoItem('Treatment', patient['treatment']),
                      _buildInfoItem('Last Visit', patient['lastVisit']),
                      _buildInfoItem('Next Visit', patient['nextVisit']),
                    ],
                  ),
                ),
              ),
              // Divider
              Divider(
                color: _primaryAqua.withValues(alpha: 0.2),
                height: 1,
                thickness: 1,
              ),
              // Action buttons
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryAqua,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
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
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  void _editPatient(Map<String, dynamic> patient) {
    // Create text controllers for editing
    final nameController = TextEditingController(text: patient['patientName']);
    final ageController = TextEditingController(
      text: patient['age'].toString(),
    );
    final genderController = TextEditingController(text: patient['gender']);
    final conditionController = TextEditingController(
      text: patient['condition'],
    );
    final treatmentController = TextEditingController(
      text: patient['treatment'],
    );
    final statusController = TextEditingController(
      text: patient['currentStatus'],
    );
    final bloodPressureController = TextEditingController(
      text: patient['bloodPressure'],
    );
    final bloodSugarController = TextEditingController(
      text: patient['bloodSugar'],
    );
    final lastVisitController = TextEditingController(
      text: patient['lastVisit'],
    );
    final nextVisitController = TextEditingController(
      text: patient['nextVisit'],
    );

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
      builder: (context) => Dialog(
        backgroundColor: _sidebarDark,
        alignment: Alignment.center,
        elevation: 8,
        child: Container(
          width: 800,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: _sidebarDark,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with title and close button
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Edit Patient Information',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(8),
                        hoverColor: _primaryAqua.withValues(alpha: 0.1),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withValues(alpha: 0.7),
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Divider
              Divider(
                color: _primaryAqua.withValues(alpha: 0.2),
                height: 1,
                thickness: 1,
              ),
              // Content with 2-column layout
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Row 1: Patient Name and Age
                        Row(
                          children: [
                            Expanded(
                              child: _buildEditTextField(
                                'Patient Name',
                                nameController,
                                validator: requiredValidator,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildEditTextField(
                                'Age',
                                ageController,
                                validator: ageValidator,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Row 2: Gender and Condition
                        Row(
                          children: [
                            Expanded(
                              child: _buildEditTextField(
                                'Gender',
                                genderController,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildEditTextField(
                                'Condition',
                                conditionController,
                                validator: requiredValidator,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Row 3: Status and Treatment
                        Row(
                          children: [
                            Expanded(
                              child: _buildEditTextField(
                                'Status',
                                statusController,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildEditTextField(
                                'Treatment',
                                treatmentController,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Row 4: Blood Pressure and Blood Sugar
                        Row(
                          children: [
                            Expanded(
                              child: _buildEditTextField(
                                'Blood Pressure',
                                bloodPressureController,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildEditTextField(
                                'Blood Sugar',
                                bloodSugarController,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Row 5: Last Visit and Next Visit
                        Row(
                          children: [
                            Expanded(
                              child: _buildEditTextField(
                                'Last Visit',
                                lastVisitController,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildEditTextField(
                                'Next Visit',
                                nextVisitController,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Divider
              Divider(
                color: _primaryAqua.withValues(alpha: 0.2),
                height: 1,
                thickness: 1,
              ),
              // Action buttons
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) {
                          return;
                        }
                        // Update patient data
                        patient['patientName'] = nameController.text;
                        patient['age'] = int.parse(ageController.text.trim());
                        patient['bloodPressure'] = bloodPressureController.text;
                        patient['bloodSugar'] = bloodSugarController.text;
                        patient['gender'] = genderController.text;
                        patient['condition'] = conditionController.text;
                        patient['currentStatus'] = statusController.text;
                        patient['treatment'] = treatmentController.text;
                        patient['lastVisit'] = lastVisitController.text;
                        patient['nextVisit'] = nextVisitController.text;

                        final patientId = patient['id']?.toString() ?? '';
                        try {
                          await _dbHelper.updateRecord(patientId, patient);
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          setState(() {}); // Refresh UI
                          Get.snackbar(
                            'Success',
                            'Patient information updated successfully',
                            snackPosition: SnackPosition.BOTTOM,
                            backgroundColor: const Color(0xFF4CAF50),
                            colorText: Colors.white,
                          );
                        } catch (e) {
                          Get.snackbar(
                            'Error',
                            'Could not update patient information: $e',
                            snackPosition: SnackPosition.BOTTOM,
                            backgroundColor: Colors.redAccent,
                            colorText: Colors.white,
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryAqua,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Save Changes',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
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
    );
  }

  Widget _buildEditTextField(
    String label,
    TextEditingController controller, {
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.8),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            fillColor: _darkDeepTeal.withValues(alpha: 0.8),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: _primaryAqua.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: _primaryAqua.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _primaryAqua, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          ),
        ),
      ],
    );
  }

  Future<void> _viewHistory(Map<String, dynamic> patient) async {
    final allRecords = await _dbHelper.getAllRecords();
    final moduleRecords = allRecords
        .where(
          (record) =>
              (record['diseaseType'] ?? '').toString().toLowerCase() ==
              'non-communicable',
        )
        .map((record) => Map<String, dynamic>.from(record))
        .toList();

    if (!mounted) {
      return;
    }

    final history = PatientHistoryDialogs.collectHistory(
      seedRecord: patient,
      records: moduleRecords,
      idKeys: const ['linkedPatientId', 'patientId', 'id'],
      nameKeys: const ['patientName', 'patient'],
      sortDateKeys: const ['datetime', 'date', 'followup'],
    );

    await PatientHistoryDialogs.showModuleHistoryDialog(
      context: context,
      moduleTitle: 'Non-Communicable',
      seedRecord: patient,
      history: history,
      description:
          'Review earlier non-communicable visits for this patient before creating or updating the next case record.',
      titleBuilder: (entry) =>
          (entry['condition'] ?? entry['type'] ?? entry['symptoms'] ?? 'Visit')
              .toString(),
      subtitleBuilder: (entry) =>
          (entry['status'] ?? entry['currentStatus'] ?? 'Pending').toString(),
      metaBuilder: (entry) =>
          'Treatment: ${(entry['treatment'] ?? entry['plan'] ?? 'No treatment plan').toString()} | Follow-up: ${(entry['followup'] ?? entry['nextVisit'] ?? 'Not set').toString()}',
      dateKeys: const ['datetime', 'date', 'followup'],
    );
  }

  Widget _buildHistorySection(String title, List<HistoryItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: _primaryAqua,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _darkDeepTeal,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _primaryAqua.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isLast = index == items.length - 1;
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          '${item.label}:',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item.value,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!isLast)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(
                        color: Colors.white.withValues(alpha: 0.1),
                        height: 1,
                      ),
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
