import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/roles/bhw/dashboard/homepage.dart';
import 'package:mycapstone_project/web/roles/bhw/checkups/checkup.dart'
    as checkup_page;
import 'package:mycapstone_project/web/roles/bhw/analytics/health_metrics.dart';
import 'package:mycapstone_project/web/roles/cho/analytics/cho_analytics.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal.dart';
import 'package:mycapstone_project/web/roles/bhw/immunization/immunization.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/communicable.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/non_communicable.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/mortality.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/morbidity.dart';
import 'package:mycapstone_project/web/roles/bhw/referrals/bhw_referral_management.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/shared/components/app_top_bar.dart';
import 'package:mycapstone_project/web/shared/components/app_metric_card.dart';
import 'package:mycapstone_project/web/shared/components/fullscreen_detail_table_dialog.dart';
import 'package:mycapstone_project/web/shared/components/module_view_components.dart';
import 'package:mycapstone_project/web/shared/components/web_data_components.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_database_helper.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/canonical_patient_registration_modal.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/canonical_patient_details_modal.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_operational_summary.dart';
import 'package:mycapstone_project/web/shared/utils/file_download.dart';
import 'package:mycapstone_project/web/shared/utils/patient_pdf.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/shared/components/app_buttons.dart';
import 'package:mycapstone_project/shared/current_table_record_utils.dart';
import 'dart:async';
import 'dart:math' as math;

class PatientRecordPage extends StatefulWidget {
  const PatientRecordPage({super.key, this.openRegistrationOnLoad = false});

  final bool openRegistrationOnLoad;

  @override
  State<PatientRecordPage> createState() => _PatientRecordPageState();
}

class _PatientRecordPageState extends State<PatientRecordPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Color scheme
  static const Color _primaryAqua = Color(0xFF2F80ED);
  static const Color _secondaryIceBlue = Color(0xFF163B66);
  static const Color _darkDeepTeal = Color(0xFF071A33);
  static const Color _mutedCoolGray = Color(0xFF4B6075);
  static const Color _lightOffWhite = Color(0xFFF5F5F5);
  static const Color _sidebarDark = Color(0xFF0D274D);

  // Filter state
  String _selectedStatus = 'All';
  String _selectedBarangay = 'All';
  String _selectedHousehold = 'All';
  String _selectedAgeGroup = 'All';
  String _selectedSex = 'All';
  String _sortField = 'Name';
  bool _sortAscending = true;
  DateTime? _fromDate;
  DateTime? _toDate;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  // Selection state
  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};
  bool _isDeleteDialogShowing = false;
  int _currentPage = 1;
  int _rowsPerPage = 10;
  int _selectedPatientTab = 0;

  // Database helper
  final _dbHelper = PatientDatabaseHelper.instance;

  // Patient data from database
  List<Map<String, dynamic>> _patients = [];
  bool _isLoading = true;
  String? _loadErrorMessage;
  StreamSubscription<List<Map<String, dynamic>>>? _patientsSubscription;

  @override
  void initState() {
    super.initState();
    _startPatientRecordsSync();
    _dbHelper.startConnectivityListener();
    if (widget.openRegistrationOnLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAddPatientModal();
      });
    }
  }

  @override
  void dispose() {
    _patientsSubscription?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _startPatientRecordsSync() {
    _patientsSubscription?.cancel();
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadErrorMessage = null;
      });
    }
    _patientsSubscription = _dbHelper.getRecordsStream().listen(
      (records) {
        if (!mounted) return;
        setState(() {
          _patients = records;
          _isLoading = false;
          _loadErrorMessage = null;
        });
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

  Future<void> _loadPatients() async {
    setState(() {
      _isLoading = true;
      _loadErrorMessage = null;
    });

    try {
      final records = await _dbHelper.getAllRecords();
      setState(() {
        _patients = records;
        _isLoading = false;
        _loadErrorMessage = null;
      });
    } catch (e) {
      print('Error loading patients: $e');
      setState(() {
        _isLoading = false;
        _loadErrorMessage = e.toString();
      });
    }
  }

  // Filtered patients based on search and filters
  List<Map<String, dynamic>> get _filteredPatients {
    final filtered = _patients.where((patient) {
      // Status filter
      if (_selectedStatus != 'All' && patient['status'] != _selectedStatus) {
        return false;
      }
      if (_selectedBarangay != 'All' &&
          (patient['barangay'] ?? '').toString() != _selectedBarangay) {
        return false;
      }
      if (_selectedHousehold != 'All' &&
          (patient['householdId'] ?? '').toString() != _selectedHousehold) {
        return false;
      }
      if (_selectedSex != 'All') {
        final sex = (patient['sex'] ?? patient['gender'] ?? '')
            .toString()
            .toLowerCase();
        if (sex != _selectedSex.toLowerCase()) return false;
      }
      if (_selectedAgeGroup != 'All') {
        final age = int.tryParse((patient['age'] ?? '').toString()) ?? -1;
        final matchesAge = switch (_selectedAgeGroup) {
          '0–5' => age >= 0 && age <= 5,
          '6–17' => age >= 6 && age <= 17,
          '18–59' => age >= 18 && age <= 59,
          '60+' => age >= 60,
          _ => true,
        };
        if (!matchesAge) return false;
      }

      // Date filter
      if (_fromDate != null || _toDate != null) {
        try {
          final registrationDate = DateTime.parse(
            patient['registrationDate'] ?? '',
          );
          if (_fromDate != null && registrationDate.isBefore(_fromDate!)) {
            return false;
          }
          if (_toDate != null &&
              registrationDate.isAfter(_toDate!.add(const Duration(days: 1)))) {
            return false;
          }
        } catch (e) {
          return false;
        }
      }

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final searchableValues = <dynamic>[
          patient['patientId'],
          patient['fullName'],
          patient['firstName'],
          patient['surname'],
          patient['phoneNumber'],
          patient['contactNumber'],
          patient['emergencyContact'],
          patient['emergencyContactNumber'],
          patient['emergencyContactPhone'],
          patient['address'],
          patient['barangay'],
          patient['municipality'],
          patient['householdId'],
          patient['age'],
        ];
        return searchableValues.any(
          (value) => (value ?? '').toString().toLowerCase().contains(query),
        );
      }

      return true;
    }).toList();

    final collapsed = CurrentTableRecordUtils.collapseToLatestPerEntity(
      filtered,
      idKeys: const ['patientId'],
      nameKeys: const ['firstName', 'middleName', 'surname'],
      dateKeys: const ['registrationDate', 'createdAt', 'timestamp'],
      extraIdentityKeys: const ['dateOfBirth', 'phoneNumber'],
    );
    collapsed.sort((left, right) {
      Comparable<dynamic> value(Map<String, dynamic> patient) {
        return switch (_sortField) {
          'Patient ID' => (patient['patientId'] ?? '').toString().toLowerCase(),
          'Age' => int.tryParse((patient['age'] ?? '').toString()) ?? -1,
          'Registration Date' =>
            DateTime.tryParse((patient['registrationDate'] ?? '').toString()) ??
                DateTime(1900),
          _ =>
            '${patient['firstName'] ?? ''} ${patient['surname'] ?? ''}'
                .trim()
                .toLowerCase(),
        };
      }

      final comparison = value(left).compareTo(value(right));
      return _sortAscending ? comparison : -comparison;
    });
    return collapsed;
  }

  // Calculate statistics
  int get _totalPatients => _patients.length;

  int get _newThisMonth {
    final now = DateTime.now();
    return _patients.where((patient) {
      try {
        final registrationDate = DateTime.parse(
          patient['registrationDate'] ?? '',
        );
        return registrationDate.year == now.year &&
            registrationDate.month == now.month;
      } catch (e) {
        return false;
      }
    }).length;
  }

  double get _followUpRate {
    final followUpCount = _patients
        .where((p) => p['status'] == 'Follow-up')
        .length;
    return _totalPatients > 0 ? (followUpCount / _totalPatients * 100) : 0;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.email?.split('@')[0] ?? 'User';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F7FA),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WebAppSidebar(
            userName: userName,
            activeItem: WebSidebarItem.patientRecords,
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _primaryAqua),
                  )
                : _loadErrorMessage != null
                ? _buildPatientLoadError()
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
                              title: 'Patient Records',
                              description:
                                  'Review assigned-patient activity and demographics, or manage individual patient records.',
                              activeView: _selectedPatientTab == 0
                                  ? HealthModuleView.insights
                                  : HealthModuleView.records,
                              onViewChanged: (view) {
                                setState(() {
                                  _selectedPatientTab =
                                      view == HealthModuleView.insights ? 0 : 1;
                                  if (_selectedPatientTab == 0) {
                                    _isSelectionMode = false;
                                    _selectedIndices.clear();
                                  }
                                });
                              },
                              primaryColor: _primaryAqua,
                              insightsLabel: 'Summary',
                            ),
                            const SizedBox(height: 16),
                            if (_selectedPatientTab == 0)
                              PatientOperationalSummary(
                                patients: _patients,
                                onViewPatient: _showPatientDetails,
                                onViewAll: () =>
                                    setState(() => _selectedPatientTab = 1),
                              )
                            else ...[
                              _buildPatientTable(),
                              const SizedBox(height: 80),
                            ],
                          ],
                        ),
                      ),
                      if (_selectedPatientTab == 1) _buildSelectionActionCard(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientLoadError() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF241E22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.45)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Colors.redAccent,
              size: 42,
            ),
            const SizedBox(height: 12),
            const Text(
              'Patient insights could not be synchronized',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'No fallback or sample values are being displayed. Check the Firebase connection and account permissions, then retry.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _startPatientRecordsSync,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry Firebase Sync'),
            ),
          ],
        ),
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
                    onTap: () => Get.toNamed(WebRoutes.bhwDashboard),
                  ),
                  _buildSidebarItem(
                    icon: Icons.assignment_turned_in_rounded,
                    label: 'Check-ups',
                    onTap: () => Get.toNamed(WebRoutes.bhwCheckups),
                  ),
                  _buildSidebarItem(
                    icon: Icons.favorite_rounded,
                    label: 'Summary Generation',
                    onTap: () => Get.toNamed(WebRoutes.bhwSummary),
                  ),
                  _buildSidebarItem(
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
                  _buildSidebarItem(
                    icon: Icons.pregnant_woman_rounded,
                    label: 'Prenatal Care',
                    onTap: () => Get.toNamed(WebRoutes.bhwPrenatal),
                  ),
                  _buildSidebarItem(
                    icon: Icons.vaccines_rounded,
                    label: 'Immunization',
                    onTap: () => Get.toNamed(WebRoutes.bhwImmunization),
                  ),
                  _buildSidebarItem(
                    icon: Icons.person_rounded,
                    label: 'Patient Records',
                    isActive: true,
                    onTap: () {},
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
                    onTap: () => Get.toNamed(WebRoutes.bhwCommunicable),
                  ),
                  _buildSidebarItem(
                    icon: Icons.health_and_safety_rounded,
                    label: 'Non-Communicable',
                    onTap: () => Get.toNamed(WebRoutes.bhwNonCommunicable),
                  ),
                  _buildSidebarItem(
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
    return WebAppTopBar(
      title: 'Patient Dashboard',
      scaffoldKey: _scaffoldKey,
      isLoading: _isLoading,
      onRefresh: () => _loadPatients(),
      selectionCount: _isSelectionMode ? _selectedIndices.length : null,
    );
  }

  Widget _buildStatisticsDashboard() {
    final cards = <Widget>[
      _buildWebMetricCard(
        title: 'Total Patients',
        value: '${_filteredPatients.length}',
        icon: Icons.people_outline,
      ),
      _buildWebMetricCard(
        title: 'Active',
        value:
            '${_filteredPatients.where((r) => r['status'] == 'Active').length}',
        icon: Icons.check_circle_outline,
      ),
      _buildWebMetricCard(
        title: 'Follow-up',
        value:
            '${_filteredPatients.where((r) => r['status'] == 'Follow-up').length}',
        icon: Icons.schedule_outlined,
      ),
      _buildWebMetricCard(
        title: 'Inactive',
        value:
            '${_filteredPatients.where((r) => r['status'] == 'Inactive').length}',
        icon: Icons.hourglass_empty_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 4
            : constraints.maxWidth >= 680
            ? 2
            : 1;
        const spacing = 12.0;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map((card) => SizedBox(width: width, child: card))
              .toList(growable: false),
        );
      },
    );
  }

  Widget _buildWebMetricCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return AppMetricCard(label: title, value: value, icon: icon);
  }

  Widget _buildFiltersSection() {
    return Column(
      children: [
        // Status Filter
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
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
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 6),
                child: Icon(Icons.filter_list, color: _primaryAqua, size: 18),
              ),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedStatus,
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    icon: Icon(Icons.arrow_drop_down, color: _primaryAqua),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    items: ['All', 'Active', 'Follow-up', 'Inactive'].map((
                      String option,
                    ) {
                      return DropdownMenuItem<String>(
                        value: option,
                        child: Text(
                          option,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedStatus = newValue;
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Date Range Filter
        Container(
          padding: const EdgeInsets.all(10),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.date_range, color: _primaryAqua, size: 18),
                  const SizedBox(width: 6),
                  const Text(
                    'Date Range',
                    style: TextStyle(
                      color: _darkDeepTeal,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_fromDate != null || _toDate != null)
                    InkWell(
                      onTap: () {
                        setState(() {
                          _fromDate = null;
                          _toDate = null;
                        });
                      },
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
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildDatePickerButton(
                      context: context,
                      label: 'From',
                      date: _fromDate,
                      isFromDate: true,
                    ),
                  ),
                  const SizedBox(width: 8),
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
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDatePickerButton({
    required BuildContext context,
    required String label,
    required DateTime? date,
    required bool isFromDate,
  }) {
    return InkWell(
      onTap: () => _selectDateForPatient(context, isFromDate),
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
              style: TextStyle(
                color: _darkDeepTeal,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            Icon(Icons.calendar_today, color: _primaryAqua, size: 14),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDateForPatient(
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
            colorScheme: const ColorScheme.dark(
              primary: _primaryAqua,
              onPrimary: Colors.white,
              surface: _darkDeepTeal,
              onSurface: Colors.white,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: _primaryAqua),
            ),
            dialogTheme: DialogThemeData(backgroundColor: _darkDeepTeal),
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
        controller: _searchController,
        onChanged: (value) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 300), () {
            if (!mounted) return;
            setState(() {
              _searchQuery = value.trim();
              _currentPage = 1;
            });
          });
        },
        style: const TextStyle(color: Color(0xFF0B1F3A)),
        cursorColor: _primaryAqua,
        decoration: InputDecoration(
          hintText:
              'Search by name, Patient ID, barangay, household, or contact...',
          hintStyle: const TextStyle(color: Color(0xFF4B6075)),
          prefixIcon: const Icon(Icons.search, color: _primaryAqua),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Color(0xFF4B6075)),
                  onPressed: () {
                    _searchDebounce?.cancel();
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                      _currentPage = 1;
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFFD9E5F2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFFD9E5F2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _primaryAqua, width: 2),
          ),
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  Widget _buildRegistryAdvancedFilters() {
    final barangays =
        _patients
            .map((patient) => (patient['barangay'] ?? '').toString().trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final households =
        _patients
            .map((patient) => (patient['householdId'] ?? '').toString().trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return Semantics(
      label: 'Patient registry filters and sorting',
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
            label: 'Household',
            value: _selectedHousehold,
            options: ['All', ...households],
            onChanged: (value) => setState(() {
              _selectedHousehold = value;
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
            options: const ['All', 'Male', 'Female', 'Other'],
            onChanged: (value) => setState(() {
              _selectedSex = value;
              _currentPage = 1;
            }),
          ),
          _registryDropdown(
            label: 'Sort By',
            value: _sortField,
            options: const ['Name', 'Patient ID', 'Age', 'Registration Date'],
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
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(() {
              _selectedStatus = 'All';
              _selectedBarangay = 'All';
              _selectedHousehold = 'All';
              _selectedAgeGroup = 'All';
              _selectedSex = 'All';
              _fromDate = null;
              _toDate = null;
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

  Widget _buildTableAddPatientButton() {
    return FilledButton.icon(
      onPressed: _showAddPatientModal,
      style: AppButtonStyles.primary(),
      icon: const Icon(Icons.person_add_outlined, size: 18),
      label: const Text('Add'),
    );
  }

  Widget _buildTableSelectPatientsButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() {
            _isSelectionMode = !_isSelectionMode;
            if (!_isSelectionMode) {
              _selectedIndices.clear();
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _primaryAqua.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _primaryAqua.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isSelectionMode ? Icons.close : Icons.checklist,
                color: _primaryAqua,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                _isSelectionMode ? 'Active' : 'Select',
                style: TextStyle(
                  color: _lightOffWhite,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _safePatientValue(dynamic value, [String fallback = 'N/A']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  Map<String, String> _formatPatientDateTimeParts(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return {'date': 'N/A', 'time': ''};
    }

    DateTime? parsed;
    if (value is Timestamp) {
      parsed = value.toDate().toLocal();
    } else if (value is DateTime) {
      parsed = value.toLocal();
    } else if (value is int) {
      parsed = DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    } else if (value is Map) {
      final seconds = value['_seconds'] ?? value['seconds'];
      if (seconds is num) {
        parsed = DateTime.fromMillisecondsSinceEpoch(
          seconds.toInt() * 1000,
          isUtc: true,
        ).toLocal();
      }
    }

    final raw = value.toString().trim();
    parsed ??= DateTime.tryParse(raw)?.toLocal();
    if (parsed != null) {
      final date =
          '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
      final time =
          '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
      return {'date': date, 'time': time};
    }

    final usDateRegex = RegExp(r'^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:\s+(.*))?$');
    final usMatch = usDateRegex.firstMatch(raw);
    if (usMatch != null) {
      final month = usMatch.group(1)!.padLeft(2, '0');
      final day = usMatch.group(2)!.padLeft(2, '0');
      final year = usMatch.group(3)!;
      final trailing = (usMatch.group(4) ?? '').trim();
      return {'date': '$year-$month-$day', 'time': trailing};
    }

    final parts = raw.split(' ');
    if (parts.length > 1) {
      return {'date': parts.first, 'time': parts.sublist(1).join(' ')};
    }

    return {'date': raw, 'time': ''};
  }

  Color _getPatientStatusColor(String status) {
    switch (status) {
      case 'Active':
        return Colors.green;
      case 'Follow-up':
        return Colors.orange;
      case 'Inactive':
        return _mutedCoolGray;
      default:
        return _mutedCoolGray;
    }
  }

  Widget _buildPatientHeaderCell(String label, {required int flex}) {
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

  Widget _buildPatientHeaderDivider() {
    return Container(
      width: 1,
      height: 18,
      color: Colors.white.withValues(alpha: 0.2),
    );
  }

  Widget _buildPatientLabeledLine({
    required List<MapEntry<String, String>> items,
    double fontSize = 11,
    FontWeight valueWeight = FontWeight.w600,
    String separator = '   ',
  }) {
    const labelBlue = Color(0xFF60A5FA);
    const valueWhite = Color(0xFFF3F8FC);
    final spans = <TextSpan>[];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      spans.add(
        TextSpan(
          text: '${item.key}: ',
          style: TextStyle(
            color: labelBlue,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      spans.add(
        TextSpan(
          text: item.value,
          style: TextStyle(
            color: valueWhite,
            fontSize: fontSize,
            fontWeight: valueWeight,
          ),
        ),
      );

      if (i < items.length - 1) {
        spans.add(
          TextSpan(
            text: separator,
            style: TextStyle(
              color: valueWhite.withValues(alpha: 0.35),
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }

  Widget _buildPatientCardHeader() {
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
          _buildPatientHeaderCell('Patient ID', flex: 16),
          _buildPatientHeaderDivider(),
          _buildPatientHeaderCell('Full Name', flex: 24),
          _buildPatientHeaderDivider(),
          _buildPatientHeaderCell('Age', flex: 8),
          _buildPatientHeaderDivider(),
          _buildPatientHeaderCell('Sex', flex: 10),
          _buildPatientHeaderDivider(),
          _buildPatientHeaderCell('Barangay', flex: 18),
          _buildPatientHeaderDivider(),
          _buildPatientHeaderCell('Household No.', flex: 16),
          _buildPatientHeaderDivider(),
          _buildPatientHeaderCell('Status', flex: 12),
          _buildPatientHeaderDivider(),
          _buildPatientHeaderCell('Last Visit', flex: 16),
          _buildPatientHeaderDivider(),
          _buildPatientHeaderCell('Assigned BHW', flex: 18),
          if (!_isSelectionMode) ...[
            _buildPatientHeaderDivider(),
            const SizedBox(
              width: 178,
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

  Widget _buildPatientIconActionButton({
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

  Widget _buildRegistryCell(
    String value, {
    required int flex,
    bool bold = false,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _darkDeepTeal,
            fontSize: 12,
            height: 1.25,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildPatientTable() {
    if (_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              CircularProgressIndicator(color: _primaryAqua),
              const SizedBox(height: 16),
              Text(
                'Loading patients...',
                style: TextStyle(color: _mutedCoolGray, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    final filteredPatients = _filteredPatients;
    final effectiveRowsPerPage = _rowsPerPage > 0 ? _rowsPerPage : 10;
    final totalPages = filteredPatients.isEmpty
        ? 1
        : ((filteredPatients.length + effectiveRowsPerPage - 1) ~/
              effectiveRowsPerPage);
    final currentPage = _currentPage < 1
        ? 1
        : (_currentPage > totalPages ? totalPages : _currentPage);
    final pageStartIndex = filteredPatients.isEmpty
        ? 0
        : (currentPage - 1) * effectiveRowsPerPage;
    final pageEndIndex = filteredPatients.isEmpty
        ? 0
        : math.min(
            pageStartIndex + effectiveRowsPerPage,
            filteredPatients.length,
          );
    final startLabel = filteredPatients.isEmpty ? 0 : pageStartIndex + 1;
    final pagedPatients = filteredPatients.isEmpty
        ? <Map<String, dynamic>>[]
        : filteredPatients.sublist(pageStartIndex, pageEndIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Web-oriented data table - Full width with integrated filters
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _primaryAqua.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              // Filters and Search Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Search Bar
                    _buildSearchBar(),
                    const SizedBox(height: 16),

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
                                Icon(
                                  Icons.filter_list,
                                  color: _primaryAqua,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedStatus,
                                      isExpanded: true,
                                      dropdownColor: Colors.white,
                                      isDense: true,
                                      iconSize: 18,
                                      icon: Icon(
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
                                      items:
                                          [
                                            'All',
                                            'Active',
                                            'Follow-up',
                                            'Inactive',
                                          ].map((String option) {
                                            return DropdownMenuItem<String>(
                                              value: option,
                                              child: Text(option),
                                            );
                                          }).toList(),
                                      onChanged: (String? newValue) {
                                        if (newValue != null) {
                                          setState(() {
                                            _selectedStatus = newValue;
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
                                Icon(
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
                                      child: Icon(
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
                    _buildRegistryAdvancedFilters(),
                  ],
                ),
              ),

              // Divider
              Divider(
                color: _primaryAqua.withValues(alpha: 0.3),
                height: 0,
                thickness: 2,
              ),

              // Patient Count and Table
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildTableSelectPatientsButton(),
                        const Spacer(),
                        if (!(_isDeleteDialogShowing ||
                            (_isSelectionMode && _selectedIndices.isNotEmpty)))
                          _buildTableAddPatientButton(),
                      ],
                    ),
                    const SizedBox(height: 10),
                    WebTableSurface(
                      minWidth: 1380,
                      child: Column(
                        children: [
                          _buildPatientCardHeader(),
                          if (pagedPatients.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 20,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceSubtle,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _primaryAqua.withValues(alpha: 0.18),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.search_off,
                                        color: _mutedCoolGray,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'No patients found',
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _patients.isEmpty
                                        ? 'Add your first patient record to get started.'
                                        : 'Try adjusting the search text or filter options.',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Column(
                              children: List.generate(pagedPatients.length, (
                                index,
                              ) {
                                final absoluteIndex = pageStartIndex + index;
                                final isSelected = _selectedIndices.contains(
                                  absoluteIndex,
                                );
                                return _buildPatientCard(
                                  pagedPatients[index],
                                  absoluteIndex,
                                  isSelected,
                                );
                              }),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Showing $startLabel-$pageEndIndex of ${filteredPatients.length} patients',
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
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _primaryAqua.withValues(alpha: 0.25),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              dropdownColor: Colors.white,
                              value: effectiveRowsPerPage,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              iconEnabledColor: AppColors.textPrimary,
                              items: const [
                                DropdownMenuItem(
                                  value: 10,
                                  child: Text('10 / page'),
                                ),
                                DropdownMenuItem(
                                  value: 20,
                                  child: Text('20 / page'),
                                ),
                                DropdownMenuItem(
                                  value: 50,
                                  child: Text('50 / page'),
                                ),
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
                          color: AppColors.textPrimary,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
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
                          color: AppColors.textPrimary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPatientCard(
    Map<String, dynamic> patient,
    int index,
    bool isSelected,
  ) {
    final firstName = _safePatientValue(patient['firstName'], '');
    final surname = _safePatientValue(patient['surname'], '');
    final middleName = _safePatientValue(patient['middleName'], '');
    final constructedName = [firstName, middleName, surname]
        .where((s) => s.isNotEmpty)
        .join(' ')
        .trim();
    final legacyPatientName = constructedName.isEmpty
        ? 'Unknown'
        : constructedName;
    final patientName = _safePatientValue(
      patient['fullName'],
      _safePatientValue(patient['name'], legacyPatientName),
    );
    final patientId = _safePatientValue(
      patient['patientId'],
      _safePatientValue(patient['id']),
    );
    final age = _safePatientValue(patient['age']);
    final sex = _safePatientValue(
      patient['sex'],
      _safePatientValue(patient['gender']),
    );
    final barangay = _safePatientValue(
      patient['barangay'],
      _safePatientValue(
        patient['assignedBarangay'],
        _safePatientValue(patient['address']),
      ),
    );
    final householdId = _safePatientValue(
      patient['householdId'],
      _safePatientValue(
        patient['householdNo'],
        _safePatientValue(patient['householdNumber']),
      ),
    );
    final status = _safePatientValue(patient['status'], 'Active');
    final lastVisitParts = _formatPatientDateTimeParts(
      patient['lastVisit'] ??
          patient['lastCheckup'] ??
          patient['updatedAt'] ??
          patient['createdAt'] ??
          patient['registrationDate'],
    );
    final lastVisit = lastVisitParts['date'] ?? 'N/A';
    final assignedBhw = _safePatientValue(
      patient['assignedBhw'],
      _safePatientValue(
        patient['registeredBy'],
        _safePatientValue(patient['bhwName'], 'Current BHW'),
      ),
    );

    final statusColor = _getPatientStatusColor(status);
    const rowBg = Colors.white;

    return GestureDetector(
      onTap: _isSelectionMode
          ? () => setState(() {
              if (isSelected) {
                _selectedIndices.remove(index);
              } else {
                _selectedIndices.add(index);
              }
            })
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: rowBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? _primaryAqua.withValues(alpha: 0.85)
                : Color(0xFFD9E5F2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (_isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        _selectedIndices.add(index);
                      } else {
                        _selectedIndices.remove(index);
                      }
                    }),
                    activeColor: _primaryAqua,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: BorderSide(
                      color: const Color(0xFFB1C4D5).withValues(alpha: 0.8),
                      width: 1.2,
                    ),
                  ),
                ),
              _buildRegistryCell(patientId, flex: 16, bold: true),
              _buildPatientHeaderDivider(),
              _buildRegistryCell(patientName, flex: 24, bold: true),
              _buildPatientHeaderDivider(),
              _buildRegistryCell(age, flex: 8),
              _buildPatientHeaderDivider(),
              _buildRegistryCell(sex, flex: 10),
              _buildPatientHeaderDivider(),
              _buildRegistryCell(barangay, flex: 18),
              _buildPatientHeaderDivider(),
              _buildRegistryCell(householdId, flex: 16),
              _buildPatientHeaderDivider(),
              Expanded(
                flex: 12,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.35),
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
              _buildPatientHeaderDivider(),
              _buildRegistryCell(lastVisit, flex: 16),
              _buildPatientHeaderDivider(),
              _buildRegistryCell(assignedBhw, flex: 18),
              if (!_isSelectionMode) ...[
                _buildPatientHeaderDivider(),
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 2),
                  child: SizedBox(
                    width: 178,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildPatientIconActionButton(
                          icon: Icons.visibility_rounded,
                          onTap: () => _showPatientDetails(patient),
                        ),
                        const SizedBox(width: 6),
                        _buildPatientIconActionButton(
                          icon: Icons.edit_rounded,
                          onTap: () => _editPatient(patient),
                        ),
                        const SizedBox(width: 6),
                        _buildPatientIconActionButton(
                          icon: Icons.picture_as_pdf_rounded,
                          onTap: () =>
                              _downloadPatientRecordPdf(context, patient),
                        ),
                        const SizedBox(width: 6),
                        _buildPatientIconActionButton(
                          icon: Icons.more_horiz_rounded,
                          onTap: () => _showPatientActionMenu(patient),
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

  Future<void> _showPatientActionMenu(Map<String, dynamic> patient) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _sidebarDark,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 620),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Patient Actions',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Every new service record will reuse this patient ID.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
              ),
              const SizedBox(height: 14),
              ...<({String value, String label, IconData icon})>[
                (
                  value: 'followup',
                  label: 'Create Follow-up',
                  icon: Icons.event_repeat,
                ),
                (
                  value: 'checkup',
                  label: 'Record Check-up',
                  icon: Icons.medical_services_outlined,
                ),
                (
                  value: 'prenatal',
                  label: 'Record Prenatal Visit',
                  icon: Icons.pregnant_woman,
                ),
                (
                  value: 'immunization',
                  label: 'Record Immunization',
                  icon: Icons.vaccines_outlined,
                ),
                (
                  value: 'morbidity',
                  label: 'Record Morbidity',
                  icon: Icons.monitor_heart_outlined,
                ),
                (
                  value: 'mortality',
                  label: 'Record Mortality',
                  icon: Icons.assignment_outlined,
                ),
                (
                  value: 'referral',
                  label: 'Create Referral',
                  icon: Icons.outbound_outlined,
                ),
                (
                  value: 'archive',
                  label: 'Archive Patient',
                  icon: Icons.archive_outlined,
                ),
              ].map(
                (item) => ListTile(
                  leading: Icon(item.icon, color: _primaryAqua),
                  title: Text(
                    item.label,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.pop(context, item.value),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    await _performPatientAction(action, patient);
  }

  Future<void> _performPatientAction(
    String action,
    Map<String, dynamic> patient,
  ) async {
    switch (action) {
      case 'followup':
        await _schedulePatientFollowUp(patient);
        return;
      case 'checkup':
        Get.off(() => checkup_page.CheckUpPage(initialPatient: patient));
        return;
      case 'prenatal':
        Get.off(() => PrenatalPage(initialPatient: patient));
        return;
      case 'immunization':
        Get.off(() => ImmunizationPage(initialPatient: patient));
        return;
      case 'morbidity':
        Get.off(() => const MorbidityPage());
        return;
      case 'mortality':
        Get.off(() => MortalityPage(initialPatient: patient));
        return;
      case 'referral':
        Get.off(() => BhwReferralPage(initialPatient: patient));
        return;
      case 'archive':
        await _archivePatient(patient);
        return;
      case 'print':
        await _downloadPatientRecordPdf(context, patient);
        return;
    }
  }

  Future<void> _schedulePatientFollowUp(Map<String, dynamic> patient) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected == null) return;
    final id = (patient['id'] ?? patient['patientId'] ?? '').toString();
    try {
      await _dbHelper.updateRecord(id, {
        ...patient,
        'status': 'Follow-up',
        'followUpDate': selected.toIso8601String(),
        'followUpCompleted': false,
      });
      if (!mounted) return;
      await _loadPatients();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not schedule follow-up: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _archivePatient(Map<String, dynamic> patient) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _sidebarDark,
        title: const Text(
          'Archive Patient',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'The patient will remain in the registry but will be marked inactive.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final id = (patient['id'] ?? patient['patientId'] ?? '').toString();
    try {
      await _dbHelper.updateRecord(id, {
        ...patient,
        'status': 'Inactive',
        'archivedAt': DateTime.now().toIso8601String(),
      });
      if (!mounted) return;
      await _loadPatients();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not archive patient: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showDeleteConfirmation(Map<String, dynamic> patient) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _sidebarDark,
        title: Text(
          'Delete Patient',
          style: TextStyle(color: _primaryAqua, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete ${patient['firstName']} ${patient['surname']}?',
          style: TextStyle(color: _lightOffWhite),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: _primaryAqua)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _deletePatient(patient);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _deletePatient(Map<String, dynamic> patient) async {
    try {
      await _dbHelper.deleteRecord(patient['id']);
      _loadPatients();
    } catch (e) {
      print('Error deleting patient: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting patient: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPatientDetails(Map<String, dynamic> patient) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CanonicalPatientDetailsModal(
        patient: patient,
        onAction: _performPatientAction,
      ),
    );
    return;

    final firstName = _safePatientDetailText(
      patient['firstName'],
      fallback: 'Unknown',
    );
    final surname = _safePatientDetailText(
      patient['surname'],
      fallback: 'Patient',
    );
    final fullName = _safePatientDetailText(
      patient['fullName'],
      fallback: '$firstName $surname',
    );
    final status = _safePatientDetailText(
      patient['status'],
      fallback: 'Active',
    );
    final patientId = _safePatientDetailText(patient['patientId']);
    final age = _safePatientDetailText(patient['age']);
    final gender = _safePatientDetailText(patient['gender']);
    final barangay = _safePatientDetailText(patient['barangay']);
    final statusColor = _getPatientDetailStatusColor(status);
    final initials = [
      if (firstName.isNotEmpty) firstName.substring(0, 1).toUpperCase(),
      if (surname.isNotEmpty) surname.substring(0, 1).toUpperCase(),
    ].join();

    showFullscreenDetailTableDialog(
      context: context,
      title: 'Patient Details',
      subject: fullName.trim(),
      items: [
        DetailTableItem(
          icon: Icons.badge_outlined,
          label: 'Patient ID',
          value: patientId,
        ),
        DetailTableItem(
          icon: Icons.person_outline,
          label: 'First Name',
          value: firstName,
        ),
        DetailTableItem(icon: Icons.person, label: 'Surname', value: surname),
        DetailTableItem(
          icon: Icons.family_restroom,
          label: 'Mother\'s Maiden Name',
          value: _safePatientDetailText(
            patient['mothersMaidenName'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.cake,
          label: 'Date of Birth',
          value: _safePatientDetailText(patient['dateOfBirth'], fallback: ''),
        ),
        DetailTableItem(icon: Icons.numbers, label: 'Age', value: age),
        DetailTableItem(icon: Icons.wc, label: 'Gender', value: gender),
        DetailTableItem(
          icon: Icons.place,
          label: 'Place of Birth',
          value: _safePatientDetailText(patient['placeOfBirth'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.flag,
          label: 'Nationality',
          value: _safePatientDetailText(patient['nationality'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.favorite,
          label: 'Civil Status',
          value: _safePatientDetailText(patient['civilStatus'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.church,
          label: 'Religion',
          value: _safePatientDetailText(patient['religion'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.work,
          label: 'Occupation',
          value: _safePatientDetailText(patient['occupation'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.school,
          label: 'Educational Attainment',
          value: _safePatientDetailText(
            patient['educationalAttainment'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.badge,
          label: 'Employee Status',
          value: _safePatientDetailText(
            patient['employeeStatus'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.phone,
          label: 'Phone Number',
          value: _safePatientDetailText(patient['phoneNumber'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.email,
          label: 'Email Address',
          value: _safePatientDetailText(patient['emailAddress'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.phone_android,
          label: 'Alternative Phone',
          value: _safePatientDetailText(
            patient['alternativePhone'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.person_pin,
          label: 'Guardian',
          value: _safePatientDetailText(patient['guardian'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.home,
          label: 'Address',
          value: _safePatientDetailText(
            patient['address'],
            fallback: _safePatientDetailText(patient['street'], fallback: ''),
          ),
        ),
        DetailTableItem(
          icon: Icons.location_city,
          label: 'Barangay',
          value: barangay,
        ),
        DetailTableItem(
          icon: Icons.location_on,
          label: 'Municipality',
          value: _safePatientDetailText(patient['municipality'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.map,
          label: 'Province',
          value: _safePatientDetailText(patient['province'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.home_work_outlined,
          label: 'Household ID',
          value: _safePatientDetailText(patient['householdId'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.height,
          label: 'Height',
          value: _safePatientDetailText(patient['height'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.monitor_weight,
          label: 'Weight',
          value: _safePatientDetailText(patient['weight'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.assessment,
          label: 'BMI',
          value: _safePatientDetailText(patient['bmi'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.bloodtype,
          label: 'Blood Type',
          value: _safePatientDetailText(patient['bloodType'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.health_and_safety,
          label: 'Allergies',
          value: _safePatientDetailText(patient['allergies'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.vaccines,
          label: 'Immunization Status',
          value: _safePatientDetailText(
            patient['immunizationStatus'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.history,
          label: 'Medical History',
          value: _safePatientDetailText(
            patient['medicalHistory'],
            fallback: _safePatientDetailText(
              patient['pastMedicalHistory'],
              fallback: '',
            ),
          ),
        ),
        DetailTableItem(
          icon: Icons.medication,
          label: 'Current Medications',
          value: _safePatientDetailText(
            patient['currentMedications'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.local_hospital,
          label: 'Chronic Conditions',
          value: _safePatientDetailText(
            patient['chronicConditions'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.notes,
          label: 'Chief Complaint',
          value: _safePatientDetailText(
            patient['chiefComplaint'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.sick,
          label: 'Current Symptoms',
          value: _safePatientDetailText(
            patient['currentSymptoms'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.thermostat,
          label: 'Body Temperature',
          value:
              '${_safePatientDetailText(patient['bodyTemperature'], fallback: '')} ${_safePatientDetailText(patient['temperatureUnit'], fallback: '')}'
                  .trim(),
        ),
        DetailTableItem(
          icon: Icons.favorite_border,
          label: 'Blood Pressure',
          value:
              '${_safePatientDetailText(patient['bpSystolic'], fallback: '')}/${_safePatientDetailText(patient['bpDiastolic'], fallback: '')} mmHg'
                  .replaceFirst('/ mmHg', '')
                  .trim(),
        ),
        DetailTableItem(
          icon: Icons.favorite,
          label: 'Heart Rate',
          value: _safePatientDetailText(patient['heartRate'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.air,
          label: 'Respiratory Rate',
          value: _safePatientDetailText(
            patient['respiratoryRate'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.water_drop,
          label: 'Oxygen Saturation',
          value: _safePatientDetailText(
            patient['oxygenSaturation'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.accessible,
          label: 'Disability',
          value: _safePatientDetailText(patient['disability'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.psychology,
          label: 'Mental Health Status',
          value: _safePatientDetailText(
            patient['mentalHealthStatus'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.event,
          label: 'Last Checkup',
          value: _safePatientDetailText(patient['lastCheckup'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.event_available,
          label: 'Next Checkup',
          value: _safePatientDetailText(patient['nextCheckup'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.person,
          label: 'Emergency Contact',
          value: _safePatientDetailText(
            patient['emergencyContact'],
            fallback: _safePatientDetailText(
              patient['emergencyContactName'],
              fallback: '',
            ),
          ),
        ),
        DetailTableItem(
          icon: Icons.people,
          label: 'Emergency Relationship',
          value: _safePatientDetailText(
            patient['emergencyRelationship'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.phone_in_talk,
          label: 'Emergency Contact Phone',
          value: _safePatientDetailText(
            patient['emergencyContactPhone'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.home_work_outlined,
          label: 'Emergency Contact Address',
          value: _safePatientDetailText(
            patient['emergencyContactAddress'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.business,
          label: 'Insurance Provider',
          value: _safePatientDetailText(
            patient['insuranceProvider'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.payments,
          label: 'Monthly Income',
          value: _safePatientDetailText(patient['monthlyIncome'], fallback: ''),
        ),
        DetailTableItem(
          icon: Icons.info_outline,
          label: 'Status',
          value: status,
        ),
        DetailTableItem(
          icon: Icons.notes_outlined,
          label: 'Additional Notes',
          value: _safePatientDetailText(
            patient['additionalNotes'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.calendar_today,
          label: 'Registration Date',
          value: _safePatientDetailText(
            patient['registrationDate'],
            fallback: '',
          ),
        ),
        DetailTableItem(
          icon: Icons.person_pin,
          label: 'Registered By',
          value: _safePatientDetailText(patient['registeredBy'], fallback: ''),
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
                                      initials.isEmpty ? 'PT' : initials,
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
                                        fullName,
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Patient record overview with identity, contact, medical, lifestyle, insurance, and registration details.',
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
                                      Icons.badge_rounded,
                                      color: statusColor,
                                      size: 21,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Current patient status',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'This patient is marked as $status, with profile details currently registered in $barangay.',
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
                                      status,
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
                                _buildPatientDetailMetaChip(
                                  icon: Icons.badge_outlined,
                                  label: 'Patient ID',
                                  value: patientId,
                                  accentColor: const Color(0xFF64B5F6),
                                ),
                                _buildPatientDetailMetaChip(
                                  icon: Icons.cake_outlined,
                                  label: 'Age',
                                  value: age,
                                  accentColor: const Color(0xFFFFB74D),
                                ),
                                _buildPatientDetailMetaChip(
                                  icon: Icons.wc_outlined,
                                  label: 'Gender',
                                  value: gender,
                                  accentColor: const Color(0xFF81C784),
                                ),
                                _buildPatientDetailMetaChip(
                                  icon: Icons.location_city_outlined,
                                  label: 'Barangay',
                                  value: barangay,
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
                            _buildDetailSection('Personal Details', [
                              _buildDetailRow(
                                Icons.person,
                                'First Name',
                                patient['firstName'],
                              ),
                              _buildDetailRow(
                                Icons.person_outline,
                                'Surname',
                                patient['surname'],
                              ),
                              _buildDetailRow(
                                Icons.family_restroom,
                                'Mother\'s Maiden Name',
                                patient['mothersMaidenName'],
                              ),
                              _buildDetailRow(
                                Icons.cake,
                                'Date of Birth',
                                patient['dateOfBirth'],
                              ),
                              _buildDetailRow(
                                Icons.numbers,
                                'Age',
                                patient['age'],
                              ),
                              _buildDetailRow(
                                Icons.place,
                                'Place of Birth',
                                patient['placeOfBirth'],
                              ),
                              _buildDetailRow(
                                Icons.flag,
                                'Nationality',
                                patient['nationality'],
                              ),
                              _buildDetailRow(
                                Icons.favorite,
                                'Civil Status',
                                patient['civilStatus'],
                              ),
                              _buildDetailRow(
                                Icons.wc,
                                'Gender',
                                patient['gender'],
                              ),
                              _buildDetailRow(
                                Icons.church,
                                'Religion',
                                patient['religion'],
                              ),
                              _buildDetailRow(
                                Icons.work,
                                'Occupation',
                                patient['occupation'],
                              ),
                              _buildDetailRow(
                                Icons.school,
                                'Educational Attainment',
                                patient['educationalAttainment'],
                              ),
                              _buildDetailRow(
                                Icons.badge,
                                'Employee Status',
                                patient['employeeStatus'],
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildDetailSection('Contact Information', [
                              _buildDetailRow(
                                Icons.phone,
                                'Phone Number',
                                patient['phoneNumber'],
                              ),
                              _buildDetailRow(
                                Icons.email,
                                'Email Address',
                                patient['emailAddress'],
                              ),
                              _buildDetailRow(
                                Icons.phone_android,
                                'Alternative Phone',
                                patient['alternativePhone'],
                              ),
                              _buildDetailRow(
                                Icons.person_pin,
                                'Guardian',
                                patient['guardian'],
                              ),
                              _buildDetailRow(
                                Icons.home,
                                'Street',
                                patient['street'],
                              ),
                              _buildDetailRow(
                                Icons.location_city,
                                'Barangay',
                                patient['barangay'],
                              ),
                              _buildDetailRow(
                                Icons.location_on,
                                'Municipality',
                                patient['municipality'],
                              ),
                              _buildDetailRow(
                                Icons.map,
                                'Province',
                                patient['province'],
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildDetailSection('Medical Details', [
                              _buildDetailRow(
                                Icons.height,
                                'Height',
                                patient['height'],
                              ),
                              _buildDetailRow(
                                Icons.monitor_weight,
                                'Weight',
                                patient['weight'],
                              ),
                              _buildDetailRow(
                                Icons.assessment,
                                'BMI',
                                patient['bmi'],
                              ),
                              _buildDetailRow(
                                Icons.bloodtype,
                                'Blood Type',
                                patient['bloodType'],
                              ),
                              _buildDetailRow(
                                Icons.health_and_safety,
                                'Allergies',
                                patient['allergies'],
                              ),
                              _buildDetailRow(
                                Icons.vaccines,
                                'Immunization Status',
                                patient['immunizationStatus'],
                              ),
                              _buildDetailRow(
                                Icons.family_restroom,
                                'Family Medical History',
                                patient['familyMedicalHistory'],
                              ),
                              _buildDetailRow(
                                Icons.history,
                                'Past Medical History',
                                patient['pastMedicalHistory'],
                              ),
                              _buildDetailRow(
                                Icons.medication,
                                'Current Medications',
                                patient['currentMedications'],
                              ),
                              _buildDetailRow(
                                Icons.local_hospital,
                                'Chronic Conditions',
                                patient['chronicConditions'],
                              ),
                              _buildDetailRow(
                                Icons.notes,
                                'Chief Complaint',
                                patient['chiefComplaint'],
                              ),
                              _buildDetailRow(
                                Icons.sick,
                                'Current Symptoms',
                                patient['currentSymptoms'],
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildDetailSection('Vital Signs', [
                              _buildDetailRow(
                                Icons.thermostat,
                                'Body Temperature',
                                '${patient['bodyTemperature']} ${patient['temperatureUnit']}',
                              ),
                              _buildDetailRow(
                                Icons.favorite,
                                'Blood Pressure',
                                '${patient['bpSystolic']}/${patient['bpDiastolic']} mmHg',
                              ),
                              _buildDetailRow(
                                Icons.favorite_border,
                                'Heart Rate',
                                patient['heartRate'],
                              ),
                              _buildDetailRow(
                                Icons.air,
                                'Respiratory Rate',
                                patient['respiratoryRate'],
                              ),
                              _buildDetailRow(
                                Icons.water_drop,
                                'Oxygen Saturation',
                                patient['oxygenSaturation'],
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildDetailSection('Health Status', [
                              _buildDetailRow(
                                Icons.accessible,
                                'Disability',
                                patient['disability'],
                              ),
                              _buildDetailRow(
                                Icons.psychology,
                                'Mental Health Status',
                                patient['mentalHealthStatus'],
                              ),
                              _buildDetailRow(
                                Icons.science,
                                'Substance Use History',
                                patient['substanceUseHistory'],
                              ),
                              _buildDetailRow(
                                Icons.event,
                                'Last Checkup',
                                patient['lastCheckup'],
                              ),
                              _buildDetailRow(
                                Icons.event_available,
                                'Next Checkup',
                                patient['nextCheckup'],
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildDetailSection('Emergency Contact', [
                              _buildDetailRow(
                                Icons.person,
                                'Name',
                                patient['emergencyContactName'],
                              ),
                              _buildDetailRow(
                                Icons.people,
                                'Relationship',
                                patient['emergencyRelationship'],
                              ),
                              _buildDetailRow(
                                Icons.phone,
                                'Phone',
                                patient['emergencyContactPhone'],
                              ),
                              _buildDetailRow(
                                Icons.home,
                                'Address',
                                patient['emergencyContactAddress'],
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildDetailSection('Lifestyle & Habits', [
                              _buildDetailRow(
                                Icons.smoking_rooms,
                                'Smoking Status',
                                patient['smokingStatus'],
                              ),
                              _buildDetailRow(
                                Icons.fitness_center,
                                'Exercise Frequency',
                                patient['exerciseFrequency'],
                              ),
                              _buildDetailRow(
                                Icons.local_bar,
                                'Alcohol Consumption',
                                patient['alcoholConsumption'],
                              ),
                              _buildDetailRow(
                                Icons.restaurant,
                                'Dietary Restrictions',
                                patient['dietaryRestrictions'],
                              ),
                              _buildDetailRow(
                                Icons.psychology,
                                'Mental Health',
                                patient['mentalHealthStatusLifestyle'],
                              ),
                              _buildDetailRow(
                                Icons.bedtime,
                                'Sleep Quality',
                                patient['sleepQuality'],
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildDetailSection('Morbidity Assessment', [
                              _buildDetailRow(
                                Icons.warning,
                                'Morbidity Risk Level',
                                patient['morbidityRiskLevel'],
                              ),
                              _buildDetailRow(
                                Icons.numbers,
                                'Number of Comorbidities',
                                patient['numberOfComorbidities'],
                              ),
                              _buildDetailRow(
                                Icons.accessibility_new,
                                'Functional Status',
                                patient['functionalStatus'],
                              ),
                              _buildDetailRow(
                                Icons.directions_walk,
                                'Mobility Status',
                                patient['mobilityStatus'],
                              ),
                              _buildDetailRow(
                                Icons.score,
                                'Frailty Index',
                                patient['frailtyIndex'],
                              ),
                              _buildDetailRow(
                                Icons.medication_liquid,
                                'Polypharmacy Risk',
                                patient['polypharmacyRisk'],
                              ),
                              _buildDetailRow(
                                Icons.verified,
                                'Preventive Care Compliance',
                                patient['preventiveCareCompliance'],
                              ),
                              _buildDetailRow(
                                Icons.menu_book,
                                'Health Literacy Level',
                                patient['healthLiteracyLevel'],
                              ),
                              _buildDetailRow(
                                Icons.groups,
                                'Social Support Level',
                                patient['socialSupportLevel'],
                              ),
                              _buildDetailRow(
                                Icons.attach_money,
                                'Economic Status Impact',
                                patient['economicStatusImpact'],
                              ),
                              _buildDetailRow(
                                Icons.note,
                                'Morbidity Notes',
                                patient['morbidityNotes'],
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildDetailSection('Insurance & Coverage', [
                              _buildDetailRow(
                                Icons.business,
                                'Insurance Provider',
                                patient['insuranceProvider'],
                              ),
                              _buildDetailRow(
                                Icons.numbers,
                                'Insurance Number',
                                patient['insuranceNumber'],
                              ),
                              _buildDetailRow(
                                Icons.calendar_today,
                                'Insurance Expiry',
                                patient['insuranceExpiry'],
                              ),
                              _buildDetailRow(
                                Icons.payments,
                                'Monthly Income',
                                patient['monthlyIncome'],
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildDetailSection('Additional Details', [
                              _buildDetailRow(
                                Icons.info,
                                'Additional Info',
                                patient['additionalInfo'],
                              ),
                              _buildDetailRow(
                                Icons.school,
                                'Education Level',
                                patient['educationLevel'],
                              ),
                              _buildDetailRow(
                                Icons.language,
                                'Preferred Language',
                                patient['preferredLanguage'],
                              ),
                              _buildDetailRow(
                                Icons.person_search,
                                'Referral Source',
                                patient['referralSource'],
                              ),
                              _buildDetailRow(
                                Icons.directions_bus,
                                'Transportation',
                                patient['transportation'],
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildDetailSection('Registration Details', [
                              _buildDetailRow(
                                Icons.event,
                                'Registration Date',
                                patient['registrationDate'],
                              ),
                              _buildDetailRow(
                                Icons.person_pin,
                                'Registered By',
                                patient['registeredBy'],
                              ),
                              _buildDetailRow(
                                Icons.info_outline,
                                'Status',
                                patient['status'],
                              ),
                              _buildDetailRow(
                                Icons.notes,
                                'Additional Notes',
                                patient['additionalNotes'],
                              ),
                            ]),
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
                            FilledButton.icon(
                              onPressed: () async {
                                Navigator.of(dialogContext).pop();
                                await _downloadPatientRecordPdf(
                                  context,
                                  patient,
                                );
                              },
                              icon: const Icon(
                                Icons.picture_as_pdf_rounded,
                                size: 18,
                              ),
                              label: const Text('Generate PDF'),
                              style: AppButtonStyles.report(),
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

  String _safePatientDetailText(
    dynamic value, {
    String fallback = 'Not recorded',
  }) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  Color _getPatientDetailStatusColor(String status) {
    final lower = status.toLowerCase();

    if (lower.contains('active')) return const Color(0xFF66BB6A);
    if (lower.contains('inactive')) return const Color(0xFFE57373);
    if (lower.contains('follow')) return const Color(0xFFFFB74D);
    if (lower.contains('pending')) return const Color(0xFF64B5F6);
    return _primaryAqua;
  }

  Widget _buildPatientDetailMetaChip({
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

  Widget _buildDetailSection(String title, List<Widget> children) {
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

  Widget _buildDetailRow(IconData icon, String label, dynamic value) {
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
                  Text(
                    _safePatientDetailText(value),
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

  Future<void> _editPatient(Map<String, dynamic> patient) async {
    final wasUpdated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          CanonicalPatientRegistrationModal(existingPatient: patient),
    );
    if (wasUpdated == true && mounted) {
      await _loadPatients();
    }
  }

  Widget _buildActionMenuButton() {
    return Container(
      decoration: BoxDecoration(
        color: _sidebarDark,
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _isSelectionMode = !_isSelectionMode;
              if (!_isSelectionMode) {
                _selectedIndices.clear();
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  _isSelectionMode ? Icons.close : Icons.checklist,
                  color: _primaryAqua,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isSelectionMode
                        ? 'Selection Mode Active'
                        : 'Select Patients',
                    style: TextStyle(
                      color: _lightOffWhite,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_isSelectionMode && _selectedIndices.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _primaryAqua,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_selectedIndices.length}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Icon(Icons.chevron_right, color: _mutedCoolGray),
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
                  '${_selectedIndices.length} patient(s) selected',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(_selectedIndices.length / _filteredPatients.length * 100).toStringAsFixed(0)}%',
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
                          _filteredPatients.length,
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
          content: Text('No patients selected'),
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
          'Are you sure you want to delete ${_selectedIndices.length} selected patient(s)? This action cannot be undone.',
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
    try {
      // Get the actual patient IDs from filtered patients
      final patientIds = _selectedIndices
          .map(
            (index) => index < _filteredPatients.length
                ? _filteredPatients[index]['id'] as String
                : null,
          )
          .whereType<String>()
          .toList();

      // Delete from database, tracking any per-record failures
      final failedIds = await _dbHelper.deleteRecords(patientIds);

      // Reload the patient list to reflect the actual database state
      await _loadPatients();

      final failedCount = failedIds.length;
      final succeededCount = patientIds.length - failedCount;

      setState(() {
        if (failedIds.isEmpty) {
          _selectedIndices.clear();
          _isSelectionMode = false;
        } else {
          // Keep the still-undeleted records selected so the user can retry
          // without having to re-select everything.
          final retryIndices = _filteredPatients
              .asMap()
              .entries
              .where((entry) => failedIds.contains(entry.value['id']))
              .map((entry) => entry.key);
          _selectedIndices
            ..clear()
            ..addAll(retryIndices);
        }
      });

      if (failedIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully deleted $succeededCount patient(s)',
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
                  ? 'Deleted $succeededCount of ${patientIds.length} patients; $failedCount failed'
                  : 'Failed to delete $failedCount patient(s)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      print('Error deleting patients: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting patients: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Add Patient Modal
  Future<void> _showAddPatientModal() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CanonicalPatientRegistrationModal(),
    );
    if (created == true && mounted) {
      await _loadPatients();
    }
  }
}

Future<void> _downloadPatientRecordPdf(
  BuildContext context,
  Map<String, dynamic> patient,
) async {
  const pdfActionColor = Color(0xFF2F80ED);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final patientName =
      '${patient['firstName'] ?? ''} ${patient['surname'] ?? ''}'.trim();

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) =>
        Center(child: CircularProgressIndicator(color: pdfActionColor)),
  );

  // Let the loading dialog paint before running synchronous PDF work.
  await Future<void>.delayed(const Duration(milliseconds: 16));

  try {
    final pdfBytes = await buildPatientPdfBytes(patient);
    final filename = buildPatientPdfFilename(patient);
    final downloaded = downloadFile(
      bytes: pdfBytes,
      filename: filename,
      mimeType: 'application/pdf',
    );

    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          downloaded
              ? 'PDF generated for ${patientName.isEmpty ? 'this patient' : patientName}.'
              : 'PDF generation is not supported on this platform.',
        ),
        backgroundColor: downloaded ? pdfActionColor : Colors.orange,
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

// Add Patient Modal Widget
class AddPatientModal extends StatefulWidget {
  const AddPatientModal({super.key});

  @override
  State<AddPatientModal> createState() => _AddPatientModalState();
}

class _AddPatientModalState extends State<AddPatientModal> {
  final _formKey = GlobalKey<FormState>();
  final _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 10;

  // Color scheme
  static const Color _primaryAqua = Color(0xFF2F80ED);
  static const Color _darkDeepTeal = Color(0xFF0D274D);
  static const Color _sidebarDark = Color(0xFF0D274D);
  static const Color _panelSurface = Color(0xFF163B66);
  static const Color _fieldSurface = Color(0xFF0B1F3A);
  static const Color _lightOffWhite = Color(0xFFF5F7FA);

  // Personal Details Controllers
  final _firstNameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _mothersMaidenNameController = TextEditingController();
  final _dobController = TextEditingController();
  final _ageController = TextEditingController();
  final _placeOfBirthController = TextEditingController();
  final _nationalityController = TextEditingController();
  String _civilStatus = 'Single';
  String _gender = 'Male';
  final _religionController = TextEditingController();
  final _occupationController = TextEditingController();
  String _educationalAttainment = 'Elementary';
  String _employeeStatus = 'Employed';

  // Contact Information Controllers
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _altPhoneController = TextEditingController();
  final _guardianController = TextEditingController();
  final _streetController = TextEditingController();
  final _barangayController = TextEditingController();
  final _municipalityController = TextEditingController();
  final _provinceController = TextEditingController();

  // Medical Details Controllers
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _bmiController = TextEditingController();
  String _bloodType = 'A+';
  final _allergiesController = TextEditingController();
  final _immunizationStatusController = TextEditingController();
  final _familyMedicalHistoryController = TextEditingController();
  final _pastMedicalHistoryController = TextEditingController();
  final _currentMedicationsController = TextEditingController();
  final _chronicConditionsController = TextEditingController();
  final _chiefComplaintController = TextEditingController();
  final _currentSymptomsController = TextEditingController();

  // Vital Signs
  final _bodyTempController = TextEditingController();
  String _tempUnit = 'Â°C';
  final _bpSystolicController = TextEditingController();
  final _bpDiastolicController = TextEditingController();
  final _heartRateController = TextEditingController();
  final _respiratoryRateController = TextEditingController();
  final _oxygenSaturationController = TextEditingController();

  final _disabilityController = TextEditingController();
  String _mentalHealthStatus = 'Good';
  final _substanceUseController = TextEditingController();
  final _lastCheckupController = TextEditingController();
  final _nextCheckupController = TextEditingController();

  // Emergency Contact Controllers
  final _emergencyNameController = TextEditingController();
  final _emergencyRelationshipController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  final _emergencyAddressController = TextEditingController();

  // Lifestyle and Habits Controllers
  String _smokingStatus = 'Never';
  String _exerciseFrequency = 'Daily';
  String _alcoholConsumption = 'Never';
  final _dietaryRestrictionsController = TextEditingController();
  String _mentalHealthStatusLifestyle = 'Good';
  String _sleepQuality = 'Excellent';

  // Morbidity Assessment Controllers
  String _morbidityRiskLevel = 'Low';
  final _numberOfComorbiditiesController = TextEditingController();
  String _functionalStatus = 'Independent';
  String _mobilityStatus = 'Fully Mobile';
  final _frailtyIndexController = TextEditingController();
  String _polypharmacyRisk = 'Low';
  String _preventiveCareCompliance = 'Full Compliance';
  String _healthLiteracyLevel = 'High';
  String _socialSupportLevel = 'Strong';
  String _economicStatusImpact = 'Minimal';
  final _morbidityNotesController = TextEditingController();

  // Insurance and Coverage Controllers
  final _insuranceProviderController = TextEditingController();
  final _insuranceNumberController = TextEditingController();
  final _insuranceExpiryController = TextEditingController();
  final _monthlyIncomeController = TextEditingController();

  // Additional Details Controllers
  final _additionalInfoController = TextEditingController();
  String _educationLevel = 'High School';
  String _preferredLanguage = 'Filipino';
  String _referralSource = 'Walk-in';
  final _transportationController = TextEditingController();

  // Consent
  bool _consentGiven = false;

  // Registration Details Controllers
  final _registrationDateController = TextEditingController();
  final _registeredByController = TextEditingController();
  final _additionalNotesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _registrationDateController.text = '01/29/2026';
  }

  @override
  void dispose() {
    _pageController.dispose();
    // Dispose all controllers
    _firstNameController.dispose();
    _surnameController.dispose();
    _mothersMaidenNameController.dispose();
    _dobController.dispose();
    _ageController.dispose();
    _placeOfBirthController.dispose();
    _nationalityController.dispose();
    _religionController.dispose();
    _occupationController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _altPhoneController.dispose();
    _guardianController.dispose();
    _streetController.dispose();
    _barangayController.dispose();
    _municipalityController.dispose();
    _provinceController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _bmiController.dispose();
    _allergiesController.dispose();
    _immunizationStatusController.dispose();
    _familyMedicalHistoryController.dispose();
    _pastMedicalHistoryController.dispose();
    _currentMedicationsController.dispose();
    _chronicConditionsController.dispose();
    _chiefComplaintController.dispose();
    _currentSymptomsController.dispose();
    _bodyTempController.dispose();
    _bpSystolicController.dispose();
    _bpDiastolicController.dispose();
    _heartRateController.dispose();
    _respiratoryRateController.dispose();
    _oxygenSaturationController.dispose();
    _disabilityController.dispose();
    _substanceUseController.dispose();
    _lastCheckupController.dispose();
    _nextCheckupController.dispose();
    _emergencyNameController.dispose();
    _emergencyRelationshipController.dispose();
    _emergencyPhoneController.dispose();
    _emergencyAddressController.dispose();
    _dietaryRestrictionsController.dispose();
    _numberOfComorbiditiesController.dispose();
    _frailtyIndexController.dispose();
    _morbidityNotesController.dispose();
    _insuranceProviderController.dispose();
    _insuranceNumberController.dispose();
    _insuranceExpiryController.dispose();
    _monthlyIncomeController.dispose();
    _additionalInfoController.dispose();
    _transportationController.dispose();
    _registrationDateController.dispose();
    _registeredByController.dispose();
    _additionalNotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: _darkDeepTeal,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(82),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_sidebarDark, _darkDeepTeal],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              border: Border(
                bottom: BorderSide(
                  color: _primaryAqua.withValues(alpha: 0.32),
                  width: 1.4,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
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
                              Icons.close,
                              color: Colors.white,
                              size: 24,
                            ),
                            onPressed: () => _showExitConfirmation(),
                            tooltip: 'Close',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'Add New Patient',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 24,
                                ),
                              ),
                              Text(
                                'Patient registration and health profile intake',
                                style: TextStyle(
                                  color: _lightOffWhite.withValues(alpha: 0.72),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: _primaryAqua,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save'),
                      onPressed: _savePatient,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryAqua,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            _buildProgressIndicator(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: _sidebarDark,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _primaryAqua.withValues(alpha: 0.18),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Form(
                      key: _formKey,
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        onPageChanged: (page) {
                          setState(() {
                            _currentPage = page;
                          });
                        },
                        children: [
                          _buildPersonalDetailsPage(),
                          _buildContactInformationPage(),
                          _buildMedicalDetailsPage(),
                          _buildVitalSignsPage(),
                          _buildEmergencyContactPage(),
                          _buildLifestyleHabitsPage(),
                          _buildMorbidityAssessmentPage(),
                          _buildInsuranceCoveragePage(),
                          _buildAdditionalDetailsPage(),
                          _buildConsentAndRegistrationPage(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _buildNavigationButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Row(
            children: List.generate(_totalPages, (index) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: index <= _currentPage ? _primaryAqua : _fieldSurface,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'Step ${_currentPage + 1} of $_totalPages: ${_getPageTitle()}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  String _getPageTitle() {
    switch (_currentPage) {
      case 0:
        return 'Personal Details';
      case 1:
        return 'Contact Information';
      case 2:
        return 'Medical Details';
      case 3:
        return 'Vital Signs';
      case 4:
        return 'Emergency Contact';
      case 5:
        return 'Lifestyle & Habits';
      case 6:
        return 'Morbidity Assessment';
      case 7:
        return 'Insurance & Coverage';
      case 8:
        return 'Additional Details';
      case 9:
        return 'Consent & Registration';
      default:
        return '';
    }
  }

  Widget _buildNavigationButtons() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentPage > 0)
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF2F80ED)),
                label: const Text(
                  'Previous',
                  style: TextStyle(color: Color(0xFF2F80ED)),
                ),
                onPressed: () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2F80ED),
                  side: BorderSide(
                    color: _primaryAqua.withValues(alpha: 0.5),
                    width: 1.2,
                  ),
                  backgroundColor: _fieldSurface,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          if (_currentPage > 0) const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              icon: Icon(
                _currentPage < _totalPages - 1
                    ? Icons.arrow_forward
                    : Icons.check,
                color: Colors.white,
              ),
              label: Text(
                _currentPage < _totalPages - 1 ? 'Next' : 'Complete',
                style: const TextStyle(color: Colors.white),
              ),
              onPressed: () {
                if (_currentPage < _totalPages - 1) {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                } else {
                  _savePatient();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryAqua,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Page 1: Personal Details
  Widget _buildPersonalDetailsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Personal Details'),
          const SizedBox(height: 16),
          _buildTextField(
            'First Name',
            _firstNameController,
            required: true,
            hint: 'Enter first name',
          ),
          _buildTextField(
            'Surname',
            _surnameController,
            required: true,
            hint: 'Enter surname/last name',
          ),
          _buildTextField(
            'Mothers Maiden Name',
            _mothersMaidenNameController,
            hint: 'Enter mother\'s maiden name',
          ),
          _buildDateField('Date of Birth', _dobController, required: true),
          _buildTextField(
            'Age',
            _ageController,
            keyboardType: TextInputType.number,
            hint: 'e.g., 25',
          ),
          _buildTextField(
            'Place of Birth',
            _placeOfBirthController,
            hint: 'City/Municipality of birth',
          ),
          _buildTextField(
            'Nationality',
            _nationalityController,
            hint: 'e.g., Filipino',
          ),
          _buildDropdownField(
            'Civil Status',
            _civilStatus,
            ['Single', 'Married', 'Widowed', 'Separated', 'Divorced'],
            (value) => setState(() => _civilStatus = value!),
          ),
          _buildDropdownField('Gender', _gender, [
            'Male',
            'Female',
            'Other',
          ], (value) => setState(() => _gender = value!)),
          _buildTextField(
            'Religion',
            _religionController,
            hint: 'e.g., Catholic, Islam, Protestant',
          ),
          _buildTextField(
            'Occupation',
            _occupationController,
            hint: 'Current occupation or job title',
          ),
          _buildDropdownField(
            'Educational Attainment',
            _educationalAttainment,
            [
              'Elementary',
              'High School',
              'College',
              'Vocational',
              'Graduate',
              'Post-Graduate',
            ],
            (value) => setState(() => _educationalAttainment = value!),
          ),
          _buildDropdownField(
            'Employee Status',
            _employeeStatus,
            ['Employed', 'Unemployed', 'Self-Employed', 'Retired', 'Student'],
            (value) => setState(() => _employeeStatus = value!),
          ),
        ],
      ),
    );
  }

  // Page 2: Contact Information
  Widget _buildContactInformationPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Contact Information'),
          const SizedBox(height: 16),
          _buildTextField(
            'Phone Number',
            _phoneController,
            keyboardType: TextInputType.phone,
            required: true,
            hint: '0912-345-6789',
          ),
          _buildTextField(
            'Email Address',
            _emailController,
            keyboardType: TextInputType.emailAddress,
            hint: 'example@email.com',
          ),
          _buildTextField(
            'Alternative Phone Number',
            _altPhoneController,
            keyboardType: TextInputType.phone,
            hint: 'Optional contact number',
          ),
          _buildTextField(
            'Guardian',
            _guardianController,
            hint: 'Guardian or next of kin name',
          ),
          const SizedBox(height: 16),
          _buildSubsectionLabel('Address'),
          const SizedBox(height: 8),
          _buildTextField(
            'Street of Address',
            _streetController,
            hint: 'House number, street name',
          ),
          _buildTextField(
            'Barangay',
            _barangayController,
            required: true,
            hint: 'Barangay name',
          ),
          _buildTextField(
            'Municipality',
            _municipalityController,
            required: true,
            hint: 'City/Municipality',
          ),
          _buildTextField(
            'Province',
            _provinceController,
            required: true,
            hint: 'Province name',
          ),
        ],
      ),
    );
  }

  // Page 3: Medical Details
  Widget _buildMedicalDetailsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Medical Details'),
          const SizedBox(height: 16),
          _buildTextField(
            'Height (cm)',
            _heightController,
            keyboardType: TextInputType.number,
            hint: 'e.g., 165',
          ),
          _buildTextField(
            'Weight (kg)',
            _weightController,
            keyboardType: TextInputType.number,
            hint: 'e.g., 60',
          ),
          _buildTextField(
            'BMI',
            _bmiController,
            keyboardType: TextInputType.number,
            hint: 'Body Mass Index (calculated)',
          ),
          _buildDropdownField('Blood Type', _bloodType, [
            'A+',
            'A-',
            'B+',
            'B-',
            'AB+',
            'AB-',
            'O+',
            'O-',
            'Unknown',
          ], (value) => setState(() => _bloodType = value!)),
          _buildTextField(
            'Allergies',
            _allergiesController,
            maxLines: 2,
            hint: 'List any known allergies (food, drugs, etc.)',
          ),
          _buildTextField(
            'Immunization Status',
            _immunizationStatusController,
            maxLines: 2,
            hint: 'Vaccination history and status',
          ),
          _buildTextField(
            'Family Medical History',
            _familyMedicalHistoryController,
            maxLines: 3,
            hint: 'Hereditary conditions, family health conditions',
          ),
          _buildTextField(
            'Past Medical History',
            _pastMedicalHistoryController,
            maxLines: 3,
            hint: 'Previous illnesses, surgeries, hospitalizations',
          ),
          _buildTextField(
            'Current Medications',
            _currentMedicationsController,
            maxLines: 2,
            hint: 'Medications currently taking with dosage',
          ),
          _buildTextField(
            'Chronic Conditions',
            _chronicConditionsController,
            maxLines: 2,
            hint: 'Long-term health conditions (e.g., diabetes, hypertension)',
          ),
          _buildTextField(
            'Chief Complaint',
            _chiefComplaintController,
            maxLines: 2,
            hint: 'Primary reason for visit',
          ),
          _buildTextField(
            'Current Symptoms',
            _currentSymptomsController,
            maxLines: 3,
            hint: 'Current symptoms being experienced',
          ),
        ],
      ),
    );
  }

  // Page 4: Vital Signs
  Widget _buildVitalSignsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Vital Signs'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildTextField(
                  'Body Temperature',
                  _bodyTempController,
                  keyboardType: TextInputType.number,
                  hint: 'e.g., 36.5 or 98.6',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdownField('Unit', _tempUnit, [
                  'Â°C',
                  'Â°F',
                ], (value) => setState(() => _tempUnit = value!)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildSubsectionLabel('Blood Pressure'),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  'Systolic',
                  _bpSystolicController,
                  keyboardType: TextInputType.number,
                  hint: 'e.g., 120',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTextField(
                  'Diastolic',
                  _bpDiastolicController,
                  keyboardType: TextInputType.number,
                  hint: 'e.g., 80',
                ),
              ),
            ],
          ),
          _buildTextField(
            'Heart Rate (Pulse)',
            _heartRateController,
            keyboardType: TextInputType.number,
            hint: 'beats per minute (e.g., 72)',
          ),
          _buildTextField(
            'Respiratory Rate',
            _respiratoryRateController,
            keyboardType: TextInputType.number,
            hint: 'breaths per minute (e.g., 16)',
          ),
          _buildTextField(
            'Oxygen Saturation (SpO2)',
            _oxygenSaturationController,
            keyboardType: TextInputType.number,
            hint: 'percentage (e.g., 98)',
          ),
          const SizedBox(height: 16),
          _buildTextField(
            'Disability/Impairment',
            _disabilityController,
            maxLines: 2,
            hint: 'Any physical or cognitive disabilities',
          ),
          _buildDropdownField(
            'Mental Health Status',
            _mentalHealthStatus,
            ['Excellent', 'Good', 'Fair', 'Poor', 'Critical'],
            (value) => setState(() => _mentalHealthStatus = value!),
          ),
          _buildTextField(
            'Substance Use History',
            _substanceUseController,
            maxLines: 2,
            hint: 'Tobacco, alcohol, or drug use history',
          ),
          _buildDateField('Last Medical Check Up', _lastCheckupController),
          _buildDateField('Recommended Next Check Up', _nextCheckupController),
        ],
      ),
    );
  }

  // Page 5: Emergency Contact Details
  Widget _buildEmergencyContactPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Emergency Contact Details'),
          const SizedBox(height: 16),
          _buildTextField(
            'Emergency Contact Name',
            _emergencyNameController,
            required: true,
            hint: 'Full name of emergency contact',
          ),
          _buildTextField(
            'Relationship',
            _emergencyRelationshipController,
            required: true,
            hint: 'e.g., Spouse, Parent, Sibling',
          ),
          _buildTextField(
            'Emergency Contact Phone',
            _emergencyPhoneController,
            keyboardType: TextInputType.phone,
            required: true,
            hint: '0912-345-6789',
          ),
          _buildTextField(
            'Emergency Contact Address',
            _emergencyAddressController,
            maxLines: 2,
            hint: 'Complete address of emergency contact',
          ),
        ],
      ),
    );
  }

  // Page 6: Lifestyle and Habits
  Widget _buildLifestyleHabitsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Lifestyle and Habits'),
          const SizedBox(height: 16),
          _buildDropdownField(
            'Smoking Status',
            _smokingStatus,
            [
              'Never',
              'Former',
              'Current - Light',
              'Current - Moderate',
              'Current - Heavy',
            ],
            (value) => setState(() => _smokingStatus = value!),
          ),
          _buildDropdownField(
            'Exercise Frequency',
            _exerciseFrequency,
            ['Daily', '3-5 times/week', '1-2 times/week', 'Rarely', 'Never'],
            (value) => setState(() => _exerciseFrequency = value!),
          ),
          _buildDropdownField(
            'Alcohol Consumption',
            _alcoholConsumption,
            ['Never', 'Rarely', 'Socially', 'Moderate', 'Heavy'],
            (value) => setState(() => _alcoholConsumption = value!),
          ),
          _buildTextField(
            'Dietary Restrictions',
            _dietaryRestrictionsController,
            maxLines: 2,
            hint: 'Vegetarian, allergies, religious restrictions, etc.',
          ),
          _buildDropdownField(
            'Mental Health Status',
            _mentalHealthStatusLifestyle,
            ['Excellent', 'Good', 'Fair', 'Poor'],
            (value) => setState(() => _mentalHealthStatusLifestyle = value!),
          ),
          _buildDropdownField(
            'Sleep Quality',
            _sleepQuality,
            ['Excellent', 'Good', 'Fair', 'Poor', 'Very Poor'],
            (value) => setState(() => _sleepQuality = value!),
          ),
        ],
      ),
    );
  }

  // Page 7: Morbidity Assessment
  Widget _buildMorbidityAssessmentPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Morbidity Assessment'),
          const SizedBox(height: 16),
          _buildDropdownField(
            'Morbidity Risk Level',
            _morbidityRiskLevel,
            ['Low', 'Moderate', 'High', 'Very High'],
            (value) => setState(() => _morbidityRiskLevel = value!),
            required: true,
          ),
          _buildTextField(
            'Number of Comorbidities',
            _numberOfComorbiditiesController,
            keyboardType: TextInputType.number,
            hint: 'e.g., 2',
          ),
          _buildDropdownField(
            'Functional Status',
            _functionalStatus,
            ['Independent', 'Partially Dependent', 'Fully Dependent'],
            (value) => setState(() => _functionalStatus = value!),
          ),
          _buildDropdownField(
            'Mobility Status',
            _mobilityStatus,
            [
              'Fully Mobile',
              'Assisted Walking',
              'Wheelchair Bound',
              'Bedridden',
            ],
            (value) => setState(() => _mobilityStatus = value!),
          ),
          _buildTextField(
            'Frailty Index Score',
            _frailtyIndexController,
            keyboardType: TextInputType.number,
            hint: 'e.g., 0.25 (0.0 = Robust, 1.0 = Severely Frail)',
          ),
          _buildDropdownField(
            'Polypharmacy Risk',
            _polypharmacyRisk,
            ['Low', 'Moderate', 'High'],
            (value) => setState(() => _polypharmacyRisk = value!),
          ),
          _buildDropdownField(
            'Preventive Care Compliance',
            _preventiveCareCompliance,
            ['Full Compliance', 'Partial Compliance', 'Non-Compliant'],
            (value) => setState(() => _preventiveCareCompliance = value!),
          ),
          _buildDropdownField(
            'Health Literacy Level',
            _healthLiteracyLevel,
            ['High', 'Moderate', 'Low'],
            (value) => setState(() => _healthLiteracyLevel = value!),
          ),
          _buildDropdownField(
            'Social Support Level',
            _socialSupportLevel,
            ['Strong', 'Moderate', 'Weak', 'None'],
            (value) => setState(() => _socialSupportLevel = value!),
          ),
          _buildDropdownField(
            'Economic Status Impact',
            _economicStatusImpact,
            ['Minimal', 'Moderate', 'Significant', 'Severe'],
            (value) => setState(() => _economicStatusImpact = value!),
          ),
          _buildTextField(
            'Morbidity Assessment Notes',
            _morbidityNotesController,
            maxLines: 4,
            hint:
                'Include specific concerns, interventions needed, and follow-up requirements',
          ),
        ],
      ),
    );
  }

  // Page 8: Insurance and Coverage
  Widget _buildInsuranceCoveragePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Insurance and Coverage'),
          const SizedBox(height: 16),
          _buildTextField(
            'Insurance Provider',
            _insuranceProviderController,
            hint: 'e.g., PhilHealth, Private Insurance',
          ),
          _buildTextField(
            'Insurance/Membership Number',
            _insuranceNumberController,
            hint: 'Policy or membership number',
          ),
          _buildDateField('Insurance Expiry Date', _insuranceExpiryController),
          _buildTextField(
            'Monthly Income Level',
            _monthlyIncomeController,
            keyboardType: TextInputType.number,
            hint: 'Monthly income in PHP',
          ),
        ],
      ),
    );
  }

  // Page 9: Additional Details
  Widget _buildAdditionalDetailsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Additional Details'),
          const SizedBox(height: 16),
          _buildTextField(
            'Additional Information',
            _additionalInfoController,
            maxLines: 3,
            hint: 'Any other relevant information',
          ),
          _buildDropdownField(
            'Education Level',
            _educationLevel,
            [
              'Elementary',
              'High School',
              'Vocational',
              'College',
              'Graduate',
              'Post-Graduate',
            ],
            (value) => setState(() => _educationLevel = value!),
          ),
          _buildDropdownField(
            'Preferred Language',
            _preferredLanguage,
            [
              'Filipino',
              'English',
              'Cebuano',
              'Ilocano',
              'Hiligaynon',
              'Other',
            ],
            (value) => setState(() => _preferredLanguage = value!),
          ),
          _buildDropdownField(
            'How did you hear about us?',
            _referralSource,
            [
              'Walk-in',
              'Referral',
              'Social Media',
              'Community Event',
              'Website',
              'Other',
            ],
            (value) => setState(() => _referralSource = value!),
          ),
          _buildTextField(
            'Transportation Method',
            _transportationController,
            hint: 'e.g., Tricycle, Jeepney, Private vehicle',
          ),
        ],
      ),
    );
  }

  // Page 10: Consent and Registration
  Widget _buildConsentAndRegistrationPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Consent and Privacy'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _panelSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _primaryAqua.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: _consentGiven,
                      onChanged: (value) =>
                          setState(() => _consentGiven = value!),
                      activeColor: _primaryAqua,
                      checkColor: Colors.white,
                      side: BorderSide(
                        color: _primaryAqua.withValues(alpha: 0.45),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'I consent to the collection, storage, and processing of my personal and medical information for healthcare purposes in accordance with data privacy laws.',
                        style: TextStyle(
                          fontSize: 13,
                          color: _lightOffWhite.withValues(alpha: 0.9),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionTitle('Registration Details'),
          const SizedBox(height: 16),
          _buildDateField(
            'Registration Date',
            _registrationDateController,
            required: true,
          ),
          _buildTextField(
            'Registered By',
            _registeredByController,
            hint: 'Health Worker Name',
            required: true,
          ),
          _buildTextField(
            'Additional Notes',
            _additionalNotesController,
            maxLines: 3,
            hint: 'Any additional notes or remarks',
          ),
        ],
      ),
    );
  }

  // Helper Methods
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: _lightOffWhite,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildSubsectionLabel(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: _primaryAqua,
      ),
    );
  }

  OutlineInputBorder _buildFieldBorder({
    required Color color,
    double width = 1.2,
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  InputDecoration _buildFieldDecoration({String? hint, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _lightOffWhite.withValues(alpha: 0.42)),
      filled: true,
      fillColor: _fieldSurface,
      suffixIcon: suffixIcon,
      border: _buildFieldBorder(color: _primaryAqua.withValues(alpha: 0.2)),
      enabledBorder: _buildFieldBorder(
        color: _primaryAqua.withValues(alpha: 0.2),
      ),
      focusedBorder: _buildFieldBorder(color: _primaryAqua, width: 1.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    );
  }

  BoxDecoration _buildDropdownContainerDecoration() {
    return BoxDecoration(
      color: _fieldSurface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: _primaryAqua.withValues(alpha: 0.2),
        width: 1.2,
      ),
    );
  }

  TextStyle _buildFieldLabelStyle() {
    return TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: _lightOffWhite,
    );
  }

  TextStyle _buildRequiredMarkerStyle() {
    return const TextStyle(color: Colors.redAccent, fontSize: 14);
  }

  Widget _buildPageLabel(String label) {
    return Text(label, style: _buildFieldLabelStyle());
  }

  Widget _buildRequiredMarker() {
    return Text(' *', style: _buildRequiredMarkerStyle());
  }

  Widget _buildPageFieldLabel(String label, {bool required = false}) {
    return Row(
      children: [_buildPageLabel(label), if (required) _buildRequiredMarker()],
    );
  }

  Widget _buildPageField({
    required Widget child,
    required String label,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageFieldLabel(label, required: required),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool required = false,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? hint,
  }) {
    return _buildPageField(
      label: label,
      required: required,
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        cursorColor: _primaryAqua,
        style: TextStyle(color: _lightOffWhite),
        decoration: _buildFieldDecoration(hint: hint),
      ),
    );
  }

  Widget _buildDropdownField(
    String label,
    String value,
    List<String> items,
    ValueChanged<String?> onChanged, {
    bool required = false,
  }) {
    return _buildPageField(
      label: label,
      required: required,
      child: Theme(
        data: Theme.of(context).copyWith(canvasColor: _sidebarDark),
        child: Container(
          decoration: _buildDropdownContainerDecoration(),
          child: DropdownButtonFormField<String>(
            initialValue: value,
            dropdownColor: _sidebarDark,
            decoration: _buildFieldDecoration().copyWith(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            icon: Icon(Icons.arrow_drop_down, color: _lightOffWhite),
            items: items.map((item) {
              return DropdownMenuItem(
                value: item,
                child: Text(item, style: TextStyle(color: _lightOffWhite)),
              );
            }).toList(),
            onChanged: onChanged,
            style: TextStyle(color: _lightOffWhite),
          ),
        ),
      ),
    );
  }

  Widget _buildDateField(
    String label,
    TextEditingController controller, {
    bool required = false,
  }) {
    return _buildPageField(
      label: label,
      required: required,
      child: TextFormField(
        controller: controller,
        readOnly: true,
        cursorColor: _primaryAqua,
        style: TextStyle(color: _lightOffWhite),
        decoration: _buildFieldDecoration(
          hint: 'mm/dd/yyyy',
          suffixIcon: Icon(Icons.calendar_today, color: _primaryAqua),
        ),
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: DateTime.now(),
            firstDate: DateTime(1900),
            lastDate: DateTime(2100),
            builder: (context, child) {
              return Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: ColorScheme.dark(
                    primary: _primaryAqua,
                    onPrimary: Colors.white,
                    surface: _sidebarDark,
                    onSurface: _lightOffWhite,
                  ),
                  textButtonTheme: TextButtonThemeData(
                    style: TextButton.styleFrom(foregroundColor: _primaryAqua),
                  ),
                  dialogTheme: DialogThemeData(backgroundColor: _sidebarDark),
                ),
                child: child!,
              );
            },
          );
          if (date != null) {
            controller.text =
                '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
          }
        },
      ),
    );
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _sidebarDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Discard Changes?',
          style: TextStyle(color: _lightOffWhite, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to exit? All unsaved data will be lost.',
          style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.82)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: _primaryAqua)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close modal
            },
            child: const Text(
              'Discard',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _savePatient() async {
    if (!_consentGiven) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide consent to continue'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate required fields
    if (_firstNameController.text.isEmpty ||
        _surnameController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _emergencyNameController.text.isEmpty ||
        _registeredByController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all required fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Prepare patient data
      final patientData = {
        'firstName': _firstNameController.text,
        'surname': _surnameController.text,
        'mothersMaidenName': _mothersMaidenNameController.text,
        'dateOfBirth': _dobController.text,
        'age': _ageController.text,
        'placeOfBirth': _placeOfBirthController.text,
        'nationality': _nationalityController.text,
        'civilStatus': _civilStatus,
        'gender': _gender,
        'religion': _religionController.text,
        'occupation': _occupationController.text,
        'educationalAttainment': _educationalAttainment,
        'employeeStatus': _employeeStatus,
        'phoneNumber': _phoneController.text,
        'emailAddress': _emailController.text,
        'alternativePhone': _altPhoneController.text,
        'guardian': _guardianController.text,
        'street': _streetController.text,
        'barangay': _barangayController.text,
        'municipality': _municipalityController.text,
        'province': _provinceController.text,
        'height': _heightController.text,
        'weight': _weightController.text,
        'bmi': _bmiController.text,
        'bloodType': _bloodType,
        'allergies': _allergiesController.text,
        'immunizationStatus': _immunizationStatusController.text,
        'familyMedicalHistory': _familyMedicalHistoryController.text,
        'pastMedicalHistory': _pastMedicalHistoryController.text,
        'currentMedications': _currentMedicationsController.text,
        'chronicConditions': _chronicConditionsController.text,
        'chiefComplaint': _chiefComplaintController.text,
        'currentSymptoms': _currentSymptomsController.text,
        'bodyTemperature': _bodyTempController.text,
        'temperatureUnit': _tempUnit,
        'bpSystolic': _bpSystolicController.text,
        'bpDiastolic': _bpDiastolicController.text,
        'heartRate': _heartRateController.text,
        'respiratoryRate': _respiratoryRateController.text,
        'oxygenSaturation': _oxygenSaturationController.text,
        'disability': _disabilityController.text,
        'mentalHealthStatus': _mentalHealthStatus,
        'substanceUseHistory': _substanceUseController.text,
        'lastCheckup': _lastCheckupController.text,
        'nextCheckup': _nextCheckupController.text,
        'emergencyContactName': _emergencyNameController.text,
        'emergencyRelationship': _emergencyRelationshipController.text,
        'emergencyContactPhone': _emergencyPhoneController.text,
        'emergencyContactAddress': _emergencyAddressController.text,
        'smokingStatus': _smokingStatus,
        'exerciseFrequency': _exerciseFrequency,
        'alcoholConsumption': _alcoholConsumption,
        'dietaryRestrictions': _dietaryRestrictionsController.text,
        'mentalHealthStatusLifestyle': _mentalHealthStatusLifestyle,
        'sleepQuality': _sleepQuality,
        'morbidityRiskLevel': _morbidityRiskLevel,
        'numberOfComorbidities': _numberOfComorbiditiesController.text,
        'functionalStatus': _functionalStatus,
        'mobilityStatus': _mobilityStatus,
        'frailtyIndex': _frailtyIndexController.text,
        'polypharmacyRisk': _polypharmacyRisk,
        'preventiveCareCompliance': _preventiveCareCompliance,
        'healthLiteracyLevel': _healthLiteracyLevel,
        'socialSupportLevel': _socialSupportLevel,
        'economicStatusImpact': _economicStatusImpact,
        'morbidityNotes': _morbidityNotesController.text,
        'insuranceProvider': _insuranceProviderController.text,
        'insuranceNumber': _insuranceNumberController.text,
        'insuranceExpiry': _insuranceExpiryController.text,
        'monthlyIncome': _monthlyIncomeController.text,
        'additionalInfo': _additionalInfoController.text,
        'educationLevel': _educationLevel,
        'preferredLanguage': _preferredLanguage,
        'referralSource': _referralSource,
        'transportation': _transportationController.text,
        'consentGiven': _consentGiven.toString(),
        'registrationDate': _registrationDateController.text,
        'registeredBy': _registeredByController.text,
        'additionalNotes': _additionalNotesController.text,
        'status': 'Active',
      };

      // Save to database
      final dbHelper = PatientDatabaseHelper.instance;
      await dbHelper.insertRecord(patientData);

      // Close modal and reload list
      Navigator.pop(context);

      // Trigger reload in parent widget
      if (context.mounted) {
        final parentState = context
            .findAncestorStateOfType<_PatientRecordPageState>();
        parentState?._loadPatients();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Patient ${_firstNameController.text} ${_surnameController.text} added successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error saving patient: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving patient: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// Edit Patient Modal Widget
class EditPatientModal extends StatefulWidget {
  final Map<String, dynamic> patient;
  final VoidCallback onSaved;

  const EditPatientModal({
    super.key,
    required this.patient,
    required this.onSaved,
  });

  @override
  State<EditPatientModal> createState() => _EditPatientModalState();
}

class _EditPatientModalState extends State<EditPatientModal> {
  final _formKey = GlobalKey<FormState>();
  int _selectedTabIndex = 0;

  // Tab sections for web-oriented design
  final List<String> _tabs = [
    'Personal',
    'Contact',
    'Medical',
    'Vitals',
    'Health',
    'Emergency',
    'Lifestyle',
    'Morbidity',
    'Insurance',
    'Additional',
  ];

  // Color scheme
  static const Color _primaryAqua = Color(0xFF2F80ED);
  static const Color _darkDeepTeal = Color(0xFF071A33);
  static const Color _mutedCoolGray = Color(0xFFB8C9DB);
  static const Color _lightOffWhite = Color(0xFFF7F9FC);

  // Controllers - will be initialized with existing data
  late TextEditingController _firstNameController;
  late TextEditingController _surnameController;
  late TextEditingController _mothersMaidenNameController;
  late TextEditingController _dobController;
  late TextEditingController _ageController;
  late TextEditingController _placeOfBirthController;
  late TextEditingController _nationalityController;
  late String _civilStatus;
  late String _gender;
  late TextEditingController _religionController;
  late TextEditingController _occupationController;
  late String _educationalAttainment;
  late String _employeeStatus;

  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _altPhoneController;
  late TextEditingController _guardianController;
  late TextEditingController _streetController;
  late TextEditingController _barangayController;
  late TextEditingController _municipalityController;
  late TextEditingController _provinceController;

  late TextEditingController _heightController;
  late TextEditingController _weightController;
  late TextEditingController _bmiController;
  late String _bloodType;
  late TextEditingController _allergiesController;
  late TextEditingController _immunizationStatusController;
  late TextEditingController _familyMedicalHistoryController;
  late TextEditingController _pastMedicalHistoryController;
  late TextEditingController _currentMedicationsController;
  late TextEditingController _chronicConditionsController;
  late TextEditingController _chiefComplaintController;
  late TextEditingController _currentSymptomsController;

  late TextEditingController _bodyTempController;
  late String _tempUnit;
  late TextEditingController _bpSystolicController;
  late TextEditingController _bpDiastolicController;
  late TextEditingController _heartRateController;
  late TextEditingController _respiratoryRateController;
  late TextEditingController _oxygenSaturationController;

  late TextEditingController _disabilityController;
  late String _mentalHealthStatus;
  late TextEditingController _substanceUseController;
  late TextEditingController _lastCheckupController;
  late TextEditingController _nextCheckupController;

  late TextEditingController _emergencyNameController;
  late TextEditingController _emergencyRelationshipController;
  late TextEditingController _emergencyPhoneController;
  late TextEditingController _emergencyAddressController;

  late String _smokingStatus;
  late String _exerciseFrequency;
  late String _alcoholConsumption;
  late TextEditingController _dietaryRestrictionsController;
  late String _mentalHealthStatusLifestyle;
  late String _sleepQuality;

  late String _morbidityRiskLevel;
  late TextEditingController _numberOfComorbiditiesController;
  late String _functionalStatus;
  late String _mobilityStatus;
  late TextEditingController _frailtyIndexController;
  late String _polypharmacyRisk;
  late String _preventiveCareCompliance;
  late String _healthLiteracyLevel;
  late String _socialSupportLevel;
  late String _economicStatusImpact;
  late TextEditingController _morbidityNotesController;

  late TextEditingController _insuranceProviderController;
  late TextEditingController _insuranceNumberController;
  late TextEditingController _insuranceExpiryController;
  late TextEditingController _monthlyIncomeController;

  late TextEditingController _additionalInfoController;
  late String _educationLevel;
  late String _preferredLanguage;
  late String _referralSource;
  late TextEditingController _transportationController;

  late bool _consentGiven;

  late TextEditingController _registrationDateController;
  late TextEditingController _registeredByController;
  late TextEditingController _additionalNotesController;

  @override
  void initState() {
    super.initState();

    // Initialize all controllers with existing patient data
    final p = widget.patient;

    _firstNameController = TextEditingController(
      text: p['firstName']?.toString() ?? '',
    );
    _surnameController = TextEditingController(
      text: p['surname']?.toString() ?? '',
    );
    _mothersMaidenNameController = TextEditingController(
      text: p['mothersMaidenName']?.toString() ?? '',
    );
    _dobController = TextEditingController(
      text: p['dateOfBirth']?.toString() ?? '',
    );
    _ageController = TextEditingController(text: p['age']?.toString() ?? '');
    _placeOfBirthController = TextEditingController(
      text: p['placeOfBirth']?.toString() ?? '',
    );
    _nationalityController = TextEditingController(
      text: p['nationality']?.toString() ?? '',
    );
    _civilStatus = p['civilStatus']?.toString() ?? 'Single';
    _gender = p['gender']?.toString() ?? 'Male';
    _religionController = TextEditingController(
      text: p['religion']?.toString() ?? '',
    );
    _occupationController = TextEditingController(
      text: p['occupation']?.toString() ?? '',
    );
    _educationalAttainment =
        p['educationalAttainment']?.toString() ?? 'Elementary';
    _employeeStatus = p['employeeStatus']?.toString() ?? 'Employed';

    _phoneController = TextEditingController(
      text: p['phoneNumber']?.toString() ?? '',
    );
    _emailController = TextEditingController(
      text: p['emailAddress']?.toString() ?? '',
    );
    _altPhoneController = TextEditingController(
      text: p['alternativePhone']?.toString() ?? '',
    );
    _guardianController = TextEditingController(
      text: p['guardian']?.toString() ?? '',
    );
    _streetController = TextEditingController(
      text: p['street']?.toString() ?? '',
    );
    _barangayController = TextEditingController(
      text: p['barangay']?.toString() ?? '',
    );
    _municipalityController = TextEditingController(
      text: p['municipality']?.toString() ?? '',
    );
    _provinceController = TextEditingController(
      text: p['province']?.toString() ?? '',
    );

    _heightController = TextEditingController(
      text: p['height']?.toString() ?? '',
    );
    _weightController = TextEditingController(
      text: p['weight']?.toString() ?? '',
    );
    _bmiController = TextEditingController(text: p['bmi']?.toString() ?? '');
    _bloodType = p['bloodType']?.toString() ?? 'A+';
    _allergiesController = TextEditingController(
      text: p['allergies']?.toString() ?? '',
    );
    _immunizationStatusController = TextEditingController(
      text: p['immunizationStatus']?.toString() ?? '',
    );
    _familyMedicalHistoryController = TextEditingController(
      text: p['familyMedicalHistory']?.toString() ?? '',
    );
    _pastMedicalHistoryController = TextEditingController(
      text: p['pastMedicalHistory']?.toString() ?? '',
    );
    _currentMedicationsController = TextEditingController(
      text: p['currentMedications']?.toString() ?? '',
    );
    _chronicConditionsController = TextEditingController(
      text: p['chronicConditions']?.toString() ?? '',
    );
    _chiefComplaintController = TextEditingController(
      text: p['chiefComplaint']?.toString() ?? '',
    );
    _currentSymptomsController = TextEditingController(
      text: p['currentSymptoms']?.toString() ?? '',
    );

    _bodyTempController = TextEditingController(
      text: p['bodyTemperature']?.toString() ?? '',
    );
    _tempUnit = _normalizeTemperatureUnit(
      p['temperatureUnit']?.toString() ?? 'Â°C',
    );
    _bpSystolicController = TextEditingController(
      text: p['bpSystolic']?.toString() ?? '',
    );
    _bpDiastolicController = TextEditingController(
      text: p['bpDiastolic']?.toString() ?? '',
    );
    _heartRateController = TextEditingController(
      text: p['heartRate']?.toString() ?? '',
    );
    _respiratoryRateController = TextEditingController(
      text: p['respiratoryRate']?.toString() ?? '',
    );
    _oxygenSaturationController = TextEditingController(
      text: p['oxygenSaturation']?.toString() ?? '',
    );

    _disabilityController = TextEditingController(
      text: p['disability']?.toString() ?? '',
    );
    _mentalHealthStatus = _normalizeMentalHealth(
      p['mentalHealthStatus']?.toString() ?? 'Good',
    );
    _substanceUseController = TextEditingController(
      text: p['substanceUseHistory']?.toString() ?? '',
    );
    _lastCheckupController = TextEditingController(
      text: p['lastCheckup']?.toString() ?? '',
    );
    _nextCheckupController = TextEditingController(
      text: p['nextCheckup']?.toString() ?? '',
    );

    _emergencyNameController = TextEditingController(
      text: p['emergencyContactName']?.toString() ?? '',
    );
    _emergencyRelationshipController = TextEditingController(
      text: p['emergencyRelationship']?.toString() ?? '',
    );
    _emergencyPhoneController = TextEditingController(
      text: p['emergencyContactPhone']?.toString() ?? '',
    );
    _emergencyAddressController = TextEditingController(
      text: p['emergencyContactAddress']?.toString() ?? '',
    );

    _smokingStatus = _normalizeSmoking(
      p['smokingStatus']?.toString() ?? 'Never',
    );
    _exerciseFrequency = _normalizeExercise(
      p['exerciseFrequency']?.toString() ?? 'Daily',
    );
    _alcoholConsumption = _normalizeAlcohol(
      p['alcoholConsumption']?.toString() ?? 'Never',
    );
    _dietaryRestrictionsController = TextEditingController(
      text: p['dietaryRestrictions']?.toString() ?? '',
    );
    _mentalHealthStatusLifestyle = _normalizeMentalHealth(
      p['mentalHealthStatusLifestyle']?.toString() ?? 'Good',
    );
    _sleepQuality = _normalizeSleep(
      p['sleepQuality']?.toString() ?? 'Excellent',
    );

    _morbidityRiskLevel = _normalizeMorbidityRisk(
      p['morbidityRiskLevel']?.toString() ?? 'Low',
    );
    _numberOfComorbiditiesController = TextEditingController(
      text: p['numberOfComorbidities']?.toString() ?? '',
    );
    _functionalStatus = _normalizeFunctional(
      p['functionalStatus']?.toString() ?? 'Independent',
    );
    _mobilityStatus = _normalizeMobility(
      p['mobilityStatus']?.toString() ?? 'Fully Mobile',
    );
    _frailtyIndexController = TextEditingController(
      text: p['frailtyIndex']?.toString() ?? '',
    );
    _polypharmacyRisk = _normalizePolypharmacy(
      p['polypharmacyRisk']?.toString() ?? 'Low',
    );
    _preventiveCareCompliance = _normalizePreventiveCare(
      p['preventiveCareCompliance']?.toString() ?? 'Full Compliance',
    );
    _healthLiteracyLevel = _normalizeHealthLiteracy(
      p['healthLiteracyLevel']?.toString() ?? 'High',
    );
    _socialSupportLevel = _normalizeSocialSupport(
      p['socialSupportLevel']?.toString() ?? 'Strong',
    );
    _economicStatusImpact = _normalizeEconomicStatus(
      p['economicStatusImpact']?.toString() ?? 'Minimal',
    );
    _morbidityNotesController = TextEditingController(
      text: p['morbidityNotes']?.toString() ?? '',
    );

    _insuranceProviderController = TextEditingController(
      text: p['insuranceProvider']?.toString() ?? '',
    );
    _insuranceNumberController = TextEditingController(
      text: p['insuranceNumber']?.toString() ?? '',
    );
    _insuranceExpiryController = TextEditingController(
      text: p['insuranceExpiry']?.toString() ?? '',
    );
    _monthlyIncomeController = TextEditingController(
      text: p['monthlyIncome']?.toString() ?? '',
    );

    _additionalInfoController = TextEditingController(
      text: p['additionalInfo']?.toString() ?? '',
    );
    _educationLevel = p['educationLevel']?.toString() ?? 'High School';
    _preferredLanguage = p['preferredLanguage']?.toString() ?? 'Filipino';
    _referralSource = p['referralSource']?.toString() ?? 'Walk-in';
    _transportationController = TextEditingController(
      text: p['transportation']?.toString() ?? '',
    );

    _consentGiven = p['consentGiven']?.toString() == 'true';

    _registrationDateController = TextEditingController(
      text: p['registrationDate']?.toString() ?? '',
    );
    _registeredByController = TextEditingController(
      text: p['registeredBy']?.toString() ?? '',
    );
    _additionalNotesController = TextEditingController(
      text: p['additionalNotes']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _surnameController.dispose();
    _mothersMaidenNameController.dispose();
    _dobController.dispose();
    _ageController.dispose();
    _placeOfBirthController.dispose();
    _nationalityController.dispose();
    _religionController.dispose();
    _occupationController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _altPhoneController.dispose();
    _guardianController.dispose();
    _streetController.dispose();
    _barangayController.dispose();
    _municipalityController.dispose();
    _provinceController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _bmiController.dispose();
    _allergiesController.dispose();
    _immunizationStatusController.dispose();
    _familyMedicalHistoryController.dispose();
    _pastMedicalHistoryController.dispose();
    _currentMedicationsController.dispose();
    _chronicConditionsController.dispose();
    _chiefComplaintController.dispose();
    _currentSymptomsController.dispose();
    _bodyTempController.dispose();
    _bpSystolicController.dispose();
    _bpDiastolicController.dispose();
    _heartRateController.dispose();
    _respiratoryRateController.dispose();
    _oxygenSaturationController.dispose();
    _disabilityController.dispose();
    _substanceUseController.dispose();
    _lastCheckupController.dispose();
    _nextCheckupController.dispose();
    _emergencyNameController.dispose();
    _emergencyRelationshipController.dispose();
    _emergencyPhoneController.dispose();
    _emergencyAddressController.dispose();
    _dietaryRestrictionsController.dispose();
    _numberOfComorbiditiesController.dispose();
    _frailtyIndexController.dispose();
    _morbidityNotesController.dispose();
    _insuranceProviderController.dispose();
    _insuranceNumberController.dispose();
    _insuranceExpiryController.dispose();
    _monthlyIncomeController.dispose();
    _additionalInfoController.dispose();
    _transportationController.dispose();
    _registrationDateController.dispose();
    _registeredByController.dispose();
    _additionalNotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = (screenWidth > 1400 ? 1400.0 : screenWidth * 0.95);

    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: _darkDeepTeal,
        appBar: AppBar(
          backgroundColor: _primaryAqua,
          elevation: 2,
          title: const Text(
            'Edit Patient Information',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => _showExitConfirmation(),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Update Patient'),
                onPressed: _updatePatient,
                style: AppButtonStyles.primary(),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // Tab Navigation Bar
            Container(
              color: _darkDeepTeal,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(
                    _tabs.length,
                    (index) => _buildTabButton(index),
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: _primaryAqua.withValues(alpha: 0.3)),

            // Tab Content
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 20,
                      ),
                      child: _buildTabContent(),
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

  Widget _buildTabButton(int index) {
    final isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? _primaryAqua : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          _tabs[index],
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? _primaryAqua : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    return Form(
      key: _formKey,
      child: switch (_selectedTabIndex) {
        0 => _buildPersonalDetailsTab(),
        1 => _buildContactInfoTab(),
        2 => _buildMedicalDetailsTab(),
        3 => _buildVitalSignsTab(),
        4 => _buildHealthStatusTab(),
        5 => _buildEmergencyContactTab(),
        6 => _buildLifestyleTab(),
        7 => _buildMorbidityAssessmentTab(),
        8 => _buildInsuranceTab(),
        9 => _buildAdditionalInfoTab(),
        _ => const SizedBox(),
      },
    );
  }

  // Tab 0: Personal Details
  Widget _buildPersonalDetailsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Personal Information'),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildTextField(
            'First Name',
            _firstNameController,
            required: true,
            hint: 'Enter first name',
          ),
          _buildTextField(
            'Surname',
            _surnameController,
            required: true,
            hint: 'Enter surname',
          ),
          _buildTextField(
            'Mother\'s Maiden Name',
            _mothersMaidenNameController,
            hint: 'Optional',
          ),
        ]),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildTextField('Date of Birth', _dobController, hint: 'YYYY-MM-DD'),
          _buildTextField('Age', _ageController, hint: 'Auto-calculated'),
          _buildTextField(
            'Place of Birth',
            _placeOfBirthController,
            hint: 'Enter place',
          ),
        ]),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildTextField(
            'Nationality',
            _nationalityController,
            hint: 'Enter nationality',
          ),
          _buildDropdownField(
            'Civil Status',
            _civilStatus,
            ['Single', 'Married', 'Divorced', 'Widowed'],
            (value) => setState(() => _civilStatus = value!),
          ),
          _buildDropdownField('Gender', _gender, [
            'Male',
            'Female',
            'Other',
          ], (value) => setState(() => _gender = value!)),
        ]),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildTextField(
            'Religion',
            _religionController,
            hint: 'Enter religion',
          ),
          _buildTextField(
            'Occupation',
            _occupationController,
            hint: 'Enter occupation',
          ),
          _buildDropdownField(
            'Educational Attainment',
            _educationalAttainment,
            ['Elementary', 'High School', 'College', 'Post-Graduate'],
            (value) => setState(() => _educationalAttainment = value!),
          ),
        ]),
        const SizedBox(height: 12),
        _buildDropdownField(
          'Employee Status',
          _employeeStatus,
          ['Employed', 'Self-Employed', 'Unemployed', 'Retired', 'Student'],
          (value) => setState(() => _employeeStatus = value!),
        ),
      ],
    );
  }

  // Tab 1: Contact Information
  Widget _buildContactInfoTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Contact Information'),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildTextField(
            'Phone Number',
            _phoneController,
            keyboardType: TextInputType.phone,
            hint: 'XXX-XXX-XXXX',
          ),
          _buildTextField(
            'Email Address',
            _emailController,
            keyboardType: TextInputType.emailAddress,
            hint: 'user@example.com',
          ),
          _buildTextField(
            'Alternative Phone',
            _altPhoneController,
            keyboardType: TextInputType.phone,
            hint: 'XXX-XXX-XXXX',
          ),
        ]),
        const SizedBox(height: 12),
        _buildSectionTitle('Address Information'),
        const SizedBox(height: 16),
        _buildTextField(
          'Guardian/Representative',
          _guardianController,
          hint: 'Name of guardian',
        ),
        const SizedBox(height: 16),
        _buildFormGrid([
          _buildTextField('Street', _streetController, hint: 'Street address'),
          _buildTextField('Barangay', _barangayController, hint: 'Barangay'),
          _buildTextField(
            'Municipality',
            _municipalityController,
            hint: 'Municipality/City',
          ),
        ]),
        const SizedBox(height: 16),
        _buildTextField('Province', _provinceController, hint: 'Province'),
      ],
    );
  }

  // Tab 2: Medical Details
  Widget _buildMedicalDetailsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Anthropometric Measurements'),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildTextField(
            'Height (cm)',
            _heightController,
            keyboardType: TextInputType.number,
            hint: 'e.g., 170',
          ),
          _buildTextField(
            'Weight (kg)',
            _weightController,
            keyboardType: TextInputType.number,
            hint: 'e.g., 70',
          ),
          _buildTextField(
            'BMI',
            _bmiController,
            keyboardType: TextInputType.number,
            hint: 'Auto-calculated',
          ),
        ]),
        const SizedBox(height: 12),
        _buildSectionTitle('Blood & Allergies'),
        const SizedBox(height: 16),
        _buildFormGrid([
          _buildDropdownField('Blood Type', _bloodType, [
            'A+',
            'A-',
            'B+',
            'B-',
            'AB+',
            'AB-',
            'O+',
            'O-',
          ], (value) => setState(() => _bloodType = value!)),
          _buildTextField(
            'Allergies',
            _allergiesController,
            hint: 'List any allergies',
          ),
        ]),
        const SizedBox(height: 12),
        _buildSectionTitle('Medical History'),
        const SizedBox(height: 16),
        _buildTextField(
          'Immunization Status',
          _immunizationStatusController,
          maxLines: 3,
          hint: 'Enter immunization details',
        ),
        const SizedBox(height: 16),
        _buildTextField(
          'Family Medical History',
          _familyMedicalHistoryController,
          maxLines: 3,
          hint: 'Describe family medical conditions',
        ),
        const SizedBox(height: 16),
        _buildTextField(
          'Past Medical History',
          _pastMedicalHistoryController,
          maxLines: 3,
          hint: 'Describe past medical conditions',
        ),
        const SizedBox(height: 16),
        _buildTextField(
          'Current Medications',
          _currentMedicationsController,
          maxLines: 3,
          hint: 'List current medications',
        ),
        const SizedBox(height: 16),
        _buildTextField(
          'Chronic Conditions',
          _chronicConditionsController,
          maxLines: 3,
          hint: 'List chronic conditions',
        ),
      ],
    );
  }

  // Tab 3: Vital Signs
  Widget _buildVitalSignsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Vital Signs'),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildTextField(
            'Body Temperature',
            _bodyTempController,
            keyboardType: TextInputType.number,
            hint: 'e.g., 36.5',
          ),
          _buildDropdownField('Unit', _tempUnit, [
            'Â°C',
            'Â°F',
          ], (value) => setState(() => _tempUnit = value!)),
        ]),
        const SizedBox(height: 12),
        _buildSectionTitle('Blood Pressure'),
        const SizedBox(height: 16),
        _buildFormGrid([
          _buildTextField(
            'Systolic (mmHg)',
            _bpSystolicController,
            keyboardType: TextInputType.number,
            hint: 'e.g., 120',
          ),
          _buildTextField(
            'Diastolic (mmHg)',
            _bpDiastolicController,
            keyboardType: TextInputType.number,
            hint: 'e.g., 80',
          ),
        ]),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildTextField(
            'Heart Rate (bpm)',
            _heartRateController,
            keyboardType: TextInputType.number,
            hint: 'e.g., 72',
          ),
          _buildTextField(
            'Respiratory Rate',
            _respiratoryRateController,
            keyboardType: TextInputType.number,
            hint: 'breaths/min',
          ),
          _buildTextField(
            'Oxygen Saturation (%)',
            _oxygenSaturationController,
            keyboardType: TextInputType.number,
            hint: 'e.g., 98',
          ),
        ]),
        const SizedBox(height: 12),
        _buildSectionTitle('Chief Complaint & Symptoms'),
        const SizedBox(height: 16),
        _buildTextField(
          'Chief Complaint',
          _chiefComplaintController,
          hint: 'Primary reason for visit',
        ),
        const SizedBox(height: 16),
        _buildTextField(
          'Current Symptoms',
          _currentSymptomsController,
          maxLines: 4,
          hint: 'Describe symptoms',
        ),
      ],
    );
  }

  // Tab 4: Health Status
  Widget _buildHealthStatusTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Health Assessment'),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildTextField(
            'Disability',
            _disabilityController,
            hint: 'Describe any disabilities',
          ),
          _buildDropdownField(
            'Mental Health Status',
            _mentalHealthStatus,
            ['Excellent', 'Good', 'Fair', 'Poor'],
            (value) => setState(() => _mentalHealthStatus = value!),
          ),
        ]),
        const SizedBox(height: 12),
        _buildTextField(
          'Substance Use History',
          _substanceUseController,
          maxLines: 3,
          hint: 'Describe substance use',
        ),
        const SizedBox(height: 12),
        _buildSectionTitle('Check-up Schedule'),
        const SizedBox(height: 16),
        _buildFormGrid([
          _buildTextField(
            'Last Check-up Date',
            _lastCheckupController,
            hint: 'YYYY-MM-DD',
          ),
          _buildTextField(
            'Next Check-up Date',
            _nextCheckupController,
            hint: 'YYYY-MM-DD',
          ),
        ]),
      ],
    );
  }

  // Tab 5: Emergency Contact
  Widget _buildEmergencyContactTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Emergency Contact Information'),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildTextField(
            'Contact Name',
            _emergencyNameController,
            required: true,
            hint: 'Full name',
          ),
          _buildTextField(
            'Relationship',
            _emergencyRelationshipController,
            required: true,
            hint: 'e.g., Spouse, Parent',
          ),
        ]),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildTextField(
            'Phone Number',
            _emergencyPhoneController,
            keyboardType: TextInputType.phone,
            hint: 'XXX-XXX-XXXX',
          ),
          _buildTextField(
            'Address',
            _emergencyAddressController,
            hint: 'Street address',
          ),
        ]),
      ],
    );
  }

  // Tab 6: Lifestyle
  Widget _buildLifestyleTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Lifestyle Factors'),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildDropdownField(
            'Smoking Status',
            _smokingStatus,
            ['Never', 'Former', 'Current'],
            (value) => setState(() => _smokingStatus = value!),
          ),
          _buildDropdownField(
            'Exercise Frequency',
            _exerciseFrequency,
            ['Daily', '3-4x/week', '1-2x/week', 'Rarely', 'Never'],
            (value) => setState(() => _exerciseFrequency = value!),
          ),
          _buildDropdownField(
            'Alcohol Consumption',
            _alcoholConsumption,
            ['Never', 'Rarely', 'Moderate', 'Frequent'],
            (value) => setState(() => _alcoholConsumption = value!),
          ),
        ]),
        const SizedBox(height: 12),
        _buildTextField(
          'Dietary Restrictions',
          _dietaryRestrictionsController,
          maxLines: 3,
          hint: 'List any dietary restrictions',
        ),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildDropdownField(
            'Mental Health (Lifestyle)',
            _mentalHealthStatusLifestyle,
            ['Excellent', 'Good', 'Fair', 'Poor'],
            (value) => setState(() => _mentalHealthStatusLifestyle = value!),
          ),
          _buildDropdownField(
            'Sleep Quality',
            _sleepQuality,
            ['Excellent', 'Good', 'Fair', 'Poor'],
            (value) => setState(() => _sleepQuality = value!),
          ),
        ]),
      ],
    );
  }

  // Tab 7: Morbidity Assessment
  Widget _buildMorbidityAssessmentTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Morbidity Assessment'),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildDropdownField(
            'Risk Level',
            _morbidityRiskLevel,
            ['Low', 'Moderate', 'High', 'Very High'],
            (value) => setState(() => _morbidityRiskLevel = value!),
          ),
          _buildTextField(
            'Number of Comorbidities',
            _numberOfComorbiditiesController,
            keyboardType: TextInputType.number,
            hint: 'e.g., 2',
          ),
          _buildDropdownField(
            'Functional Status',
            _functionalStatus,
            ['Independent', 'Partially Dependent', 'Fully Dependent'],
            (value) => setState(() => _functionalStatus = value!),
          ),
        ]),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildDropdownField(
            'Mobility Status',
            _mobilityStatus,
            [
              'Fully Mobile',
              'Assisted Walking',
              'Wheelchair Bound',
              'Bedridden',
            ],
            (value) => setState(() => _mobilityStatus = value!),
          ),
          _buildTextField(
            'Frailty Index',
            _frailtyIndexController,
            keyboardType: TextInputType.number,
            hint: '0.0 = Robust, 1.0 = Frail',
          ),
          _buildDropdownField(
            'Polypharmacy Risk',
            _polypharmacyRisk,
            ['Low', 'Moderate', 'High'],
            (value) => setState(() => _polypharmacyRisk = value!),
          ),
        ]),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildDropdownField(
            'Preventive Care Compliance',
            _preventiveCareCompliance,
            ['Full Compliance', 'Partial Compliance', 'Non-Compliant'],
            (value) => setState(() => _preventiveCareCompliance = value!),
          ),
          _buildDropdownField(
            'Health Literacy',
            _healthLiteracyLevel,
            ['High', 'Moderate', 'Low'],
            (value) => setState(() => _healthLiteracyLevel = value!),
          ),
          _buildDropdownField(
            'Social Support',
            _socialSupportLevel,
            ['Strong', 'Moderate', 'Weak', 'None'],
            (value) => setState(() => _socialSupportLevel = value!),
          ),
        ]),
        const SizedBox(height: 12),
        _buildDropdownField(
          'Economic Impact',
          _economicStatusImpact,
          ['Minimal', 'Moderate', 'Significant', 'Severe'],
          (value) => setState(() => _economicStatusImpact = value!),
        ),
        const SizedBox(height: 16),
        _buildTextField(
          'Assessment Notes',
          _morbidityNotesController,
          maxLines: 4,
          hint: 'Add assessment notes',
        ),
      ],
    );
  }

  // Tab 8: Insurance
  Widget _buildInsuranceTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Insurance & Financial Information'),
        const SizedBox(height: 12),
        _buildTextField(
          'Insurance Provider',
          _insuranceProviderController,
          hint: 'Provider name',
        ),
        const SizedBox(height: 16),
        _buildFormGrid([
          _buildTextField(
            'Insurance Number',
            _insuranceNumberController,
            hint: 'Policy number',
          ),
          _buildTextField(
            'Insurance Expiry',
            _insuranceExpiryController,
            hint: 'YYYY-MM-DD',
          ),
          _buildTextField(
            'Monthly Income',
            _monthlyIncomeController,
            keyboardType: TextInputType.number,
            hint: 'Amount',
          ),
        ]),
      ],
    );
  }

  // Tab 9: Additional Information
  Widget _buildAdditionalInfoTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Additional Information'),
        const SizedBox(height: 12),
        _buildTextField(
          'Additional Notes',
          _additionalInfoController,
          maxLines: 4,
          hint: 'Any additional information',
        ),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildDropdownField(
            'Education Level',
            _educationLevel,
            ['Primary', 'Secondary', 'Tertiary', 'Post-Graduate'],
            (value) => setState(() => _educationLevel = value!),
          ),
          _buildDropdownField(
            'Preferred Language',
            _preferredLanguage,
            ['English', 'Filipino', 'Cebuano'],
            (value) => setState(() => _preferredLanguage = value!),
          ),
        ]),
        const SizedBox(height: 12),
        _buildFormGrid([
          _buildDropdownField(
            'Referral Source',
            _referralSource,
            ['Walk-in', 'Referral', 'Phone', 'Online'],
            (value) => setState(() => _referralSource = value!),
          ),
          _buildTextField(
            'Transportation',
            _transportationController,
            hint: 'Mode of transportation',
          ),
        ]),
        const SizedBox(height: 12),
        _buildSectionTitle('Registration Details'),
        const SizedBox(height: 16),
        _buildFormGrid([
          _buildTextField(
            'Registration Date',
            _registrationDateController,
            hint: 'YYYY-MM-DD',
          ),
          _buildTextField(
            'Registered By',
            _registeredByController,
            hint: 'Staff name',
          ),
        ]),
        const SizedBox(height: 12),
        _buildTextField(
          'Additional Notes',
          _additionalNotesController,
          maxLines: 4,
          hint: 'Final notes',
        ),
      ],
    );
  }

  // Helper to build multi-column form grid
  Widget _buildFormGrid(List<Widget> children, {int columns = 3}) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: children
          .map(
            (child) => SizedBox(
              width: (MediaQuery.of(context).size.width - 100) / columns,
              child: child,
            ),
          )
          .toList(),
    );
  }

  // Page 4: Vital Signs
  Widget _buildVitalSignsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Vital Signs'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildTextField(
                  'Body Temperature',
                  _bodyTempController,
                  keyboardType: TextInputType.number,
                  hint: 'e.g., 36.5',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdownField('Unit', _tempUnit, [
                  'Â°C',
                  'Â°F',
                ], (value) => setState(() => _tempUnit = value!)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Blood Pressure',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _darkDeepTeal,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  'Systolic',
                  _bpSystolicController,
                  keyboardType: TextInputType.number,
                  hint: '120',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTextField(
                  'Diastolic',
                  _bpDiastolicController,
                  keyboardType: TextInputType.number,
                  hint: '80',
                ),
              ),
            ],
          ),
          _buildTextField(
            'Heart Rate',
            _heartRateController,
            keyboardType: TextInputType.number,
            hint: 'e.g., 72 bpm',
          ),
          _buildTextField(
            'Respiratory Rate',
            _respiratoryRateController,
            keyboardType: TextInputType.number,
            hint: 'breaths per minute',
          ),
          _buildTextField(
            'Oxygen Saturation',
            _oxygenSaturationController,
            keyboardType: TextInputType.number,
            hint: 'e.g., 98%',
          ),
          const SizedBox(height: 16),
          _buildTextField(
            'Disability/Impairment',
            _disabilityController,
            maxLines: 2,
            hint: 'Any physical or cognitive disabilities',
          ),
          _buildDropdownField(
            'Mental Health Status',
            _mentalHealthStatus,
            ['Excellent', 'Good', 'Fair', 'Poor', 'Critical'],
            (value) => setState(() => _mentalHealthStatus = value!),
          ),
          _buildTextField(
            'Substance Use History',
            _substanceUseController,
            maxLines: 2,
            hint: 'Tobacco, alcohol, drug use',
          ),
          _buildDateField('Last Medical Check Up', _lastCheckupController),
          _buildDateField('Next Check Up', _nextCheckupController),
        ],
      ),
    );
  }

  // Page 5: Health Status Page (keep naming as in EditPatientModal)
  Widget _buildHealthStatusPage() {
    return _buildEmergencyContactPage(); // Reference to page 5 content
  }

  // Page 6: Emergency Contact
  Widget _buildEmergencyContactPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Emergency Contact'),
          const SizedBox(height: 16),
          _buildTextField(
            'Emergency Contact Name',
            _emergencyNameController,
            required: true,
            hint: 'Full name',
          ),
          _buildTextField(
            'Relationship',
            _emergencyRelationshipController,
            required: true,
            hint: 'e.g., Spouse, Parent',
          ),
          _buildTextField(
            'Emergency Phone',
            _emergencyPhoneController,
            keyboardType: TextInputType.phone,
            required: true,
            hint: '0912-345-6789',
          ),
          _buildTextField(
            'Emergency Address',
            _emergencyAddressController,
            maxLines: 2,
            hint: 'Complete address',
          ),
        ],
      ),
    );
  }

  // Page 7: Lifestyle
  Widget _buildLifestylePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Lifestyle & Habits'),
          const SizedBox(height: 16),
          _buildDropdownField(
            'Smoking Status',
            _smokingStatus,
            [
              'Never',
              'Former',
              'Current - Light',
              'Current - Moderate',
              'Current - Heavy',
            ],
            (value) => setState(() => _smokingStatus = value!),
          ),
          _buildDropdownField(
            'Exercise Frequency',
            _exerciseFrequency,
            ['Daily', '3-5 times/week', '1-2 times/week', 'Rarely', 'Never'],
            (value) => setState(() => _exerciseFrequency = value!),
          ),
          _buildDropdownField(
            'Alcohol Consumption',
            _alcoholConsumption,
            ['Never', 'Rarely', 'Socially', 'Moderate', 'Heavy'],
            (value) => setState(() => _alcoholConsumption = value!),
          ),
          _buildTextField(
            'Dietary Restrictions',
            _dietaryRestrictionsController,
            maxLines: 2,
            hint: 'Vegetarian, allergies, etc.',
          ),
          _buildDropdownField(
            'Mental Health',
            _mentalHealthStatusLifestyle,
            ['Excellent', 'Good', 'Fair', 'Poor'],
            (value) => setState(() => _mentalHealthStatusLifestyle = value!),
          ),
          _buildDropdownField(
            'Sleep Quality',
            _sleepQuality,
            ['Excellent', 'Good', 'Fair', 'Poor', 'Very Poor'],
            (value) => setState(() => _sleepQuality = value!),
          ),
        ],
      ),
    );
  }

  // Page 8: Morbidity Assessment
  Widget _buildMorbidityAssessmentPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Morbidity Assessment'),
          const SizedBox(height: 16),
          _buildDropdownField(
            'Risk Level',
            _morbidityRiskLevel,
            ['Low', 'Moderate', 'High', 'Very High'],
            (value) => setState(() => _morbidityRiskLevel = value!),
          ),
          _buildTextField(
            'Number of Comorbidities',
            _numberOfComorbiditiesController,
            keyboardType: TextInputType.number,
            hint: 'e.g., 2',
          ),
          _buildDropdownField(
            'Functional Status',
            _functionalStatus,
            ['Independent', 'Partially Dependent', 'Fully Dependent'],
            (value) => setState(() => _functionalStatus = value!),
          ),
          _buildDropdownField(
            'Mobility Status',
            _mobilityStatus,
            [
              'Fully Mobile',
              'Assisted Walking',
              'Wheelchair Bound',
              'Bedridden',
            ],
            (value) => setState(() => _mobilityStatus = value!),
          ),
          _buildTextField(
            'Frailty Index',
            _frailtyIndexController,
            keyboardType: TextInputType.number,
            hint: '0.0 = Robust, 1.0 = Frail',
          ),
          _buildDropdownField(
            'Polypharmacy Risk',
            _polypharmacyRisk,
            ['Low', 'Moderate', 'High'],
            (value) => setState(() => _polypharmacyRisk = value!),
          ),
          _buildDropdownField(
            'Preventive Care Compliance',
            _preventiveCareCompliance,
            ['Full Compliance', 'Partial Compliance', 'Non-Compliant'],
            (value) => setState(() => _preventiveCareCompliance = value!),
          ),
          _buildDropdownField(
            'Health Literacy',
            _healthLiteracyLevel,
            ['High', 'Moderate', 'Low'],
            (value) => setState(() => _healthLiteracyLevel = value!),
          ),
          _buildDropdownField(
            'Social Support',
            _socialSupportLevel,
            ['Strong', 'Moderate', 'Weak', 'None'],
            (value) => setState(() => _socialSupportLevel = value!),
          ),
          _buildDropdownField(
            'Economic Impact',
            _economicStatusImpact,
            ['Minimal', 'Moderate', 'Significant', 'Severe'],
            (value) => setState(() => _economicStatusImpact = value!),
          ),
          _buildTextField(
            'Notes',
            _morbidityNotesController,
            maxLines: 4,
            hint: 'Assessment notes',
          ),
        ],
      ),
    );
  }

  // Page 9: Insurance
  Widget _buildInsurancePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Insurance & Coverage'),
          const SizedBox(height: 16),
          _buildTextField(
            'Insurance Provider',
            _insuranceProviderController,
            hint: 'e.g., PhilHealth',
          ),
          _buildTextField(
            'Insurance Number',
            _insuranceNumberController,
            hint: 'Policy number',
          ),
          _buildDateField('Insurance Expiry', _insuranceExpiryController),
          _buildTextField(
            'Monthly Income',
            _monthlyIncomeController,
            keyboardType: TextInputType.number,
            hint: 'PHP',
          ),
          const SizedBox(height: 16),
          _buildTextField(
            'Additional Info',
            _additionalInfoController,
            maxLines: 3,
            hint: 'Other relevant information',
          ),
          _buildDropdownField(
            'Education Level',
            _educationLevel,
            [
              'Elementary',
              'High School',
              'Vocational',
              'College',
              'Graduate',
              'Post-Graduate',
            ],
            (value) => setState(() => _educationLevel = value!),
          ),
          _buildDropdownField(
            'Preferred Language',
            _preferredLanguage,
            [
              'Filipino',
              'English',
              'Cebuano',
              'Ilocano',
              'Hiligaynon',
              'Other',
            ],
            (value) => setState(() => _preferredLanguage = value!),
          ),
          _buildDropdownField(
            'Referral Source',
            _referralSource,
            [
              'Walk-in',
              'Referral',
              'Social Media',
              'Community Event',
              'Website',
              'Other',
            ],
            (value) => setState(() => _referralSource = value!),
          ),
          _buildTextField(
            'Transportation',
            _transportationController,
            hint: 'e.g., Tricycle, Jeepney',
          ),
        ],
      ),
    );
  }

  // Page 10: Final/Consent Page
  Widget _buildFinalPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Consent & Registration'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _consentGiven,
                  onChanged: (value) => setState(() => _consentGiven = value!),
                  activeColor: _primaryAqua,
                ),
                Expanded(
                  child: Text(
                    'I consent to the collection, storage, and processing of my personal and medical information for healthcare purposes.',
                    style: TextStyle(fontSize: 13, color: _darkDeepTeal),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildSectionTitle('Registration Details'),
          const SizedBox(height: 16),
          _buildDateField(
            'Registration Date',
            _registrationDateController,
            required: true,
          ),
          _buildTextField(
            'Registered By',
            _registeredByController,
            hint: 'Health Worker Name',
            required: true,
          ),
          _buildTextField(
            'Additional Notes',
            _additionalNotesController,
            maxLines: 3,
            hint: 'Any additional notes',
          ),
        ],
      ),
    );
  }

  // Helper Methods
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool required = false,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (required)
                const Text(
                  ' *',
                  style: TextStyle(color: Colors.red, fontSize: 14),
                ),
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[400]),
              filled: true,
              fillColor: _darkDeepTeal,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _primaryAqua.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _primaryAqua.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _primaryAqua, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField(
    String label,
    String value,
    List<String> items,
    ValueChanged<String?> onChanged, {
    bool required = false,
  }) {
    // Ensure the value exists in items, otherwise use the first item as fallback
    final validValue = items.contains(value) ? value : items.first;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (required)
                const Text(
                  ' *',
                  style: TextStyle(color: Colors.red, fontSize: 14),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: _darkDeepTeal,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _primaryAqua.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: DropdownButtonFormField<String>(
              initialValue: validValue,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                filled: true,
                fillColor: _darkDeepTeal,
              ),
              dropdownColor: const Color(0xFF1a3a3f),
              items: items
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(
                        item,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateField(
    String label,
    TextEditingController controller, {
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (required)
                const Text(
                  ' *',
                  style: TextStyle(color: Colors.red, fontSize: 14),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            readOnly: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'mm/dd/yyyy',
              hintStyle: TextStyle(color: Colors.grey[400]),
              filled: true,
              fillColor: _darkDeepTeal,
              suffixIcon: Icon(Icons.calendar_today, color: _primaryAqua),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _primaryAqua.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _primaryAqua.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _primaryAqua, width: 2),
              ),
            ),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime(2100),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: _primaryAqua,
                        onPrimary: Colors.white,
                        surface: _darkDeepTeal,
                        onSurface: Colors.white,
                      ),
                      textButtonTheme: TextButtonThemeData(
                        style: TextButton.styleFrom(
                          foregroundColor: _primaryAqua,
                        ),
                      ),
                      dialogTheme: DialogThemeData(
                        backgroundColor: _darkDeepTeal,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (date != null) {
                controller.text =
                    '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
              }
            },
          ),
        ],
      ),
    );
  }

  String _normalizeTemperatureUnit(String unit) {
    // Normalize old database values to current format
    final trimmedUnit = unit.toLowerCase().trim();
    if (trimmedUnit.contains('celsius') || trimmedUnit == 'c') {
      return 'Â°C';
    } else if (trimmedUnit.contains('fahrenheit') || trimmedUnit == 'f') {
      return 'Â°F';
    }
    return unit; // Return as-is if already normalized
  }

  String _normalizeMentalHealth(String value) {
    // Normalize old database values to current format
    final lowerValue = value.toLowerCase().trim();

    // Check more specific patterns first before general ones
    if (lowerValue.contains('excellent') || lowerValue.contains('very good')) {
      return 'Excellent';
    } else if (lowerValue.contains('critical') ||
        lowerValue.contains('severe')) {
      return 'Critical';
    } else if (lowerValue.contains('moderate anxiety') ||
        lowerValue.contains('moderate anxiety')) {
      return 'Poor';
    } else if (lowerValue.contains('mild anxiety') ||
        lowerValue.contains('mild')) {
      return 'Fair';
    } else if (lowerValue.contains('poor') || lowerValue.contains('anxiety')) {
      return 'Poor';
    } else if (lowerValue.contains('good') ||
        lowerValue.contains('normal') ||
        lowerValue.contains('minimal')) {
      return 'Good';
    }
    // Default to valid value if unrecognized
    return 'Good';
  }

  String _normalizeSmoking(String value) {
    final lowerValue = value.toLowerCase().trim();
    if (lowerValue.contains('never')) return 'Never';
    if (lowerValue.contains('former') ||
        lowerValue.contains('ex') ||
        lowerValue.contains('smoker')) {
      return 'Former';
    }
    if (lowerValue.contains('light')) return 'Current - Light';
    if (lowerValue.contains('moderate')) return 'Current - Moderate';
    if (lowerValue.contains('heavy') || lowerValue.contains('current')) {
      return 'Current - Heavy';
    }
    return 'Never';
  }

  String _normalizeExercise(String value) {
    final lowerValue = value.toLowerCase().trim();
    if (lowerValue.contains('daily')) return 'Daily';
    if (lowerValue.contains('3-5') || lowerValue.contains('3 to 5')) {
      return '3-5 times/week';
    }
    if (lowerValue.contains('1-2') || lowerValue.contains('1 to 2')) {
      return '1-2 times/week';
    }
    if (lowerValue.contains('rarely')) return 'Rarely';
    if (lowerValue.contains('never')) return 'Never';
    return 'Daily';
  }

  String _normalizeAlcohol(String value) {
    final lowerValue = value.toLowerCase().trim();
    if (lowerValue.contains('never')) return 'Never';
    if (lowerValue.contains('rarely')) return 'Rarely';
    if (lowerValue.contains('social') || lowerValue.contains('occasional')) {
      return 'Socially';
    }
    if (lowerValue.contains('moderate')) return 'Moderate';
    if (lowerValue.contains('heavy')) return 'Heavy';
    return 'Never';
  }

  String _normalizeSleep(String value) {
    final lowerValue = value.toLowerCase().trim();
    if (lowerValue.contains('excellent') || lowerValue.contains('very good')) {
      return 'Excellent';
    }
    if (lowerValue.contains('good') && !lowerValue.contains('very')) {
      return 'Good';
    }
    if (lowerValue.contains('fair') || lowerValue.contains('average')) {
      return 'Fair';
    }
    if (lowerValue.contains('poor') && !lowerValue.contains('very')) {
      return 'Poor';
    }
    if (lowerValue.contains('very poor') || lowerValue.contains('terrible')) {
      return 'Very Poor';
    }
    return 'Good';
  }

  String _normalizeMorbidityRisk(String value) {
    final lowerValue = value.toLowerCase().trim();
    if (lowerValue.contains('low')) return 'Low';
    if (lowerValue.contains('moderate')) return 'Moderate';
    if (lowerValue.contains('very high') || lowerValue.contains('critical')) {
      return 'Very High';
    }
    if (lowerValue.contains('high')) return 'High';
    return 'Low';
  }

  String _normalizeFunctional(String value) {
    final lowerValue = value.toLowerCase().trim();
    if (lowerValue.contains('independent')) return 'Independent';
    if (lowerValue.contains('partial')) return 'Partially Dependent';
    if (lowerValue.contains('fully') || lowerValue.contains('dependent')) {
      return 'Fully Dependent';
    }
    return 'Independent';
  }

  String _normalizeMobility(String value) {
    final lowerValue = value.toLowerCase().trim();
    if (lowerValue.contains('fully mobile') ||
        (lowerValue.contains('fully') && !lowerValue.contains('dependent'))) {
      return 'Fully Mobile';
    }
    if (lowerValue.contains('assisted') ||
        lowerValue.contains('cane') ||
        lowerValue.contains('walker')) {
      return 'Assisted Walking';
    }
    if (lowerValue.contains('wheelchair') ||
        lowerValue.contains('immobile') ||
        lowerValue == 'uses wheelchair') {
      return 'Wheelchair Bound';
    }
    if (lowerValue.contains('bedridden')) return 'Bedridden';
    return 'Fully Mobile';
  }

  String _normalizePolypharmacy(String value) {
    final lowerValue = value.toLowerCase().trim();
    if (lowerValue.contains('low')) return 'Low';
    if (lowerValue.contains('moderate')) return 'Moderate';
    if (lowerValue.contains('high')) return 'High';
    return 'Low';
  }

  String _normalizePreventiveCare(String value) {
    final lowerValue = value.toLowerCase().trim();
    if (lowerValue.contains('full') || lowerValue.contains('compliant')) {
      return 'Full Compliance';
    }
    if (lowerValue.contains('partial')) return 'Partial Compliance';
    if (lowerValue.contains('non') || lowerValue.contains('non-compliant')) {
      return 'Non-Compliant';
    }
    return 'Full Compliance';
  }

  String _normalizeHealthLiteracy(String value) {
    final lowerValue = value.toLowerCase().trim();
    if (lowerValue.contains('high')) return 'High';
    if (lowerValue.contains('moderate')) return 'Moderate';
    if (lowerValue.contains('low')) return 'Low';
    return 'High';
  }

  String _normalizeSocialSupport(String value) {
    final lowerValue = value.toLowerCase().trim();
    if (lowerValue.contains('strong') || lowerValue.contains('excellent')) {
      return 'Strong';
    }
    if (lowerValue.contains('moderate') || lowerValue.contains('adequate')) {
      return 'Moderate';
    }
    if (lowerValue.contains('weak') || lowerValue.contains('limited')) {
      return 'Weak';
    }
    if (lowerValue.contains('none') || lowerValue.contains('no')) return 'None';
    return 'Strong';
  }

  String _normalizeEconomicStatus(String value) {
    final lowerValue = value.toLowerCase().trim();
    if (lowerValue.contains('minimal') || lowerValue.contains('minimum')) {
      return 'Minimal';
    }
    if (lowerValue.contains('moderate')) return 'Moderate';
    if (lowerValue.contains('significant')) return 'Significant';
    if (lowerValue.contains('severe')) return 'Severe';
    return 'Minimal';
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Changes?'),
        content: const Text(
          'Are you sure you want to exit without saving changes?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close modal
            },
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  void _updatePatient() async {
    if (!_consentGiven) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide consent to continue'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate required fields
    if (_firstNameController.text.isEmpty ||
        _surnameController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _emergencyNameController.text.isEmpty ||
        _registeredByController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all required fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Prepare updated patient data
      final patientData = {
        'id': widget.patient['id'], // Keep original ID
        'firstName': _firstNameController.text,
        'surname': _surnameController.text,
        'mothersMaidenName': _mothersMaidenNameController.text,
        'dateOfBirth': _dobController.text,
        'age': _ageController.text,
        'placeOfBirth': _placeOfBirthController.text,
        'nationality': _nationalityController.text,
        'civilStatus': _civilStatus,
        'gender': _gender,
        'religion': _religionController.text,
        'occupation': _occupationController.text,
        'educationalAttainment': _educationalAttainment,
        'employeeStatus': _employeeStatus,
        'phoneNumber': _phoneController.text,
        'emailAddress': _emailController.text,
        'alternativePhone': _altPhoneController.text,
        'guardian': _guardianController.text,
        'street': _streetController.text,
        'barangay': _barangayController.text,
        'municipality': _municipalityController.text,
        'province': _provinceController.text,
        'height': _heightController.text,
        'weight': _weightController.text,
        'bmi': _bmiController.text,
        'bloodType': _bloodType,
        'allergies': _allergiesController.text,
        'immunizationStatus': _immunizationStatusController.text,
        'familyMedicalHistory': _familyMedicalHistoryController.text,
        'pastMedicalHistory': _pastMedicalHistoryController.text,
        'currentMedications': _currentMedicationsController.text,
        'chronicConditions': _chronicConditionsController.text,
        'chiefComplaint': _chiefComplaintController.text,
        'currentSymptoms': _currentSymptomsController.text,
        'bodyTemperature': _bodyTempController.text,
        'temperatureUnit': _tempUnit,
        'bpSystolic': _bpSystolicController.text,
        'bpDiastolic': _bpDiastolicController.text,
        'heartRate': _heartRateController.text,
        'respiratoryRate': _respiratoryRateController.text,
        'oxygenSaturation': _oxygenSaturationController.text,
        'disability': _disabilityController.text,
        'mentalHealthStatus': _mentalHealthStatus,
        'substanceUseHistory': _substanceUseController.text,
        'lastCheckup': _lastCheckupController.text,
        'nextCheckup': _nextCheckupController.text,
        'emergencyContactName': _emergencyNameController.text,
        'emergencyRelationship': _emergencyRelationshipController.text,
        'emergencyContactPhone': _emergencyPhoneController.text,
        'emergencyContactAddress': _emergencyAddressController.text,
        'smokingStatus': _smokingStatus,
        'exerciseFrequency': _exerciseFrequency,
        'alcoholConsumption': _alcoholConsumption,
        'dietaryRestrictions': _dietaryRestrictionsController.text,
        'mentalHealthStatusLifestyle': _mentalHealthStatusLifestyle,
        'sleepQuality': _sleepQuality,
        'morbidityRiskLevel': _morbidityRiskLevel,
        'numberOfComorbidities': _numberOfComorbiditiesController.text,
        'functionalStatus': _functionalStatus,
        'mobilityStatus': _mobilityStatus,
        'frailtyIndex': _frailtyIndexController.text,
        'polypharmacyRisk': _polypharmacyRisk,
        'preventiveCareCompliance': _preventiveCareCompliance,
        'healthLiteracyLevel': _healthLiteracyLevel,
        'socialSupportLevel': _socialSupportLevel,
        'economicStatusImpact': _economicStatusImpact,
        'morbidityNotes': _morbidityNotesController.text,
        'insuranceProvider': _insuranceProviderController.text,
        'insuranceNumber': _insuranceNumberController.text,
        'insuranceExpiry': _insuranceExpiryController.text,
        'monthlyIncome': _monthlyIncomeController.text,
        'additionalInfo': _additionalInfoController.text,
        'educationLevel': _educationLevel,
        'preferredLanguage': _preferredLanguage,
        'referralSource': _referralSource,
        'transportation': _transportationController.text,
        'consentGiven': _consentGiven.toString(),
        'registrationDate': _registrationDateController.text,
        'registeredBy': _registeredByController.text,
        'additionalNotes': _additionalNotesController.text,
        'status': widget.patient['status'] ?? 'Active',
      };

      // Update in database
      final dbHelper = PatientDatabaseHelper.instance;
      final id = widget.patient['id']?.toString() ?? '';
      if (id.isNotEmpty) {
        await dbHelper.updateRecord(id, patientData);

        // Close modal and trigger reload
        Navigator.pop(context);
        widget.onSaved();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Patient ${_firstNameController.text} ${_surnameController.text} updated successfully',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Patient ID not found');
      }
    } catch (e) {
      print('Error updating patient: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating patient: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
