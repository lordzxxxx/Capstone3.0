import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/web/roles/bhw/immunization/immunization_database_helper.dart';
import 'package:mycapstone_project/web/roles/bhw/immunization/immunization_insights.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/roles/bhw/checkups/checkup.dart'
    as checkup_page;
import 'package:mycapstone_project/web/roles/bhw/analytics/health_metrics.dart';
import 'package:mycapstone_project/web/roles/cho/analytics/cho_analytics.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/communicable.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/non_communicable.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/mortality.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/shared/components/fullscreen_detail_table_dialog.dart';
import 'package:mycapstone_project/web/shared/components/module_view_components.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_first_service_selector.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_identity_utils.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/shared_patient_search_panel.dart';
import 'package:mycapstone_project/web/shared/utils/file_download.dart';
import 'package:mycapstone_project/web/shared/utils/immunization_pdf.dart';
import 'package:mycapstone_project/web/shared/utils/report_generation.dart';
import 'package:mycapstone_project/shared/current_table_record_utils.dart';

const Color _primaryAqua = Color(0xFF2F80ED);
const Color _secondaryIceBlue = Color(0xFF163B66);
const Color _darkDeepTeal = Color(0xFF071A33);
const Color _cardBackground = Color(0xFF0D274D);
const Color _mutedCoolGray = Color(0xFFB8C9DB);
const Color _lightOffWhite = Color(0xFFF5F5F5);
const Color _sidebarDark = Color(0xFF0D274D);

class ImmunizationPage extends StatefulWidget {
  const ImmunizationPage({super.key, this.initialPatient});

  final Map<String, dynamic>? initialPatient;

  @override
  State<ImmunizationPage> createState() => _ImmunizationPageState();
}

class _ImmunizationPageState extends State<ImmunizationPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  static const List<String> _vaccineTypeOptions = [
    'BCG Vaccine',
    'Hepatitis B',
    'DPT Vaccine',
    'Polio Vaccine',
    'MMR Vaccine',
    'Varicella Vaccine',
    'Influenza',
    'Pneumococcal',
  ];
  String _selectedVaccineFilter = 'All Vaccines';
  final List<String> _vaccineFilterOptions = [
    'All Vaccines',
    'BCG Vaccine',
    'Hepatitis B',
    'DPT Vaccine',
    'Polio Vaccine',
    'MMR Vaccine',
    'Varicella Vaccine',
  ];

  DateTime? _fromDate;
  DateTime? _toDate;

  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};
  bool _isDeleteDialogShowing = false;
  bool _isLoading = true;
  int _currentPage = 1;
  int _rowsPerPage = 10;
  late HealthModuleView _activeView;

  // Search state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _sharedPatientMatches = [];
  bool _isSearchingSharedPatients = false;
  Timer? _sharedPatientSearchDebounce;

  // Database-backed immunization records
  List<Map<String, dynamic>> _immunizationRecords = [];
  final ImmunizationDatabaseHelper _dbHelper =
      ImmunizationDatabaseHelper.instance;
  final PatientCenteredHistoryService _patientHistoryService =
      PatientCenteredHistoryService();

  @override
  void initState() {
    super.initState();
    _activeView = healthModuleViewFromUrl();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => persistHealthModuleView('/immunization', _activeView),
    );
    Future.microtask(() => _loadRecords());
    _dbHelper.startConnectivityListener();
    if (widget.initialPatient != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showNewImmunizationModal(
            context,
            patientSeed: widget.initialPatient,
          );
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
    persistHealthModuleView('/immunization', view);
  }

  @override
  void dispose() {
    _sharedPatientSearchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);

    // Try to sync from Firebase
    await _dbHelper.syncFromFirebase();

    // Reload after sync
    final updatedRecords = await _dbHelper.getAllRecords();

    setState(() {
      _immunizationRecords = updatedRecords;
      _isLoading = false;
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

  Future<void> _seedSampleData() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sample data initialization is disabled. Immunization records now populate only from actual encoding.',
        ),
        backgroundColor: Colors.orange,
      ),
    );
  }

  String _getPatientHistoryKey(Map<String, dynamic> record) {
    final patientId = (record['patientId'] ?? '').toString().trim();
    if (patientId.isNotEmpty) {
      return 'id:${patientId.toLowerCase()}';
    }

    final patientName = (record['patientName'] ?? '').toString().trim();
    return 'name:${patientName.toLowerCase()}';
  }

  List<Map<String, dynamic>> _getPatientHistoryRecords(
    Map<String, dynamic> seedRecord,
  ) {
    final historyKey = _getPatientHistoryKey(seedRecord);
    final history = _immunizationRecords
        .where((record) {
          return _getPatientHistoryKey(record) == historyKey;
        })
        .map((record) => Map<String, dynamic>.from(record))
        .toList();

    history.sort((left, right) {
      final leftDate =
          DateTime.tryParse(
            (left['administrationDate'] ?? left['date'] ?? '').toString(),
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final rightDate =
          DateTime.tryParse(
            (right['administrationDate'] ?? right['date'] ?? '').toString(),
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return rightDate.compareTo(leftDate);
    });

    return history;
  }

  Map<String, dynamic> _buildDisplayRecord(Map<String, dynamic> record) {
    return {
      ...record,
      'patientHistoryCount': _getPatientHistoryRecords(record).length,
    };
  }

  void _showPatientImmunizationHistory(
    BuildContext context,
    Map<String, dynamic> seedRecord,
  ) {
    final history = _getPatientHistoryRecords(seedRecord);
    final latestRecord = history.isNotEmpty ? history.first : seedRecord;
    final patientName = (latestRecord['patientName'] ?? 'Unknown Patient')
        .toString();
    final patientId = (latestRecord['patientId'] ?? 'No patient ID')
        .toString()
        .trim();
    final latestVaccine = (latestRecord['vaccine'] ?? 'No vaccine recorded')
        .toString();
    final latestStatus = (latestRecord['status'] ?? 'Completed')
        .toString()
        .trim();
    final lastAdministration = _formatDate(latestRecord['administrationDate']);
    final nextDose = _formatDate(latestRecord['nextDoseDueDate']);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 48,
            vertical: 32,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: _darkDeepTeal,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            constraints: BoxConstraints(
              maxWidth: 920,
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.88,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_sidebarDark, _secondaryIceBlue, _primaryAqua],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.history_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              patientName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              patientId.isEmpty
                                  ? 'Patient immunization history'
                                  : 'Patient ID: $patientId',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.76),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _buildImmunizationHistorySummaryCard(
                                  icon: Icons.vaccines,
                                  label: 'Latest Vaccine',
                                  value: latestVaccine,
                                ),
                                _buildImmunizationHistorySummaryCard(
                                  icon: Icons.event,
                                  label: 'Last Immunized',
                                  value: lastAdministration,
                                ),
                                _buildImmunizationHistorySummaryCard(
                                  icon: Icons.update,
                                  label: 'Next Dose Due',
                                  value: nextDose,
                                ),
                                _buildImmunizationHistorySummaryCard(
                                  icon: Icons.list_alt,
                                  label: 'History Entries',
                                  value: '${history.length}',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Recorded immunization history',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Review previous immunizations before adding another dose for this patient.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildStatusChip(latestStatus),
                    ],
                  ),
                ),
                Expanded(
                  child: history.isEmpty
                      ? Center(
                          child: Text(
                            'No previous immunization history found for this patient.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                          itemCount: history.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final historyRecord = history[index];
                            final vaccine = (historyRecord['vaccine'] ?? 'N/A')
                                .toString();
                            final administrationDate = _formatDate(
                              historyRecord['administrationDate'],
                            );
                            final doseNumber =
                                (historyRecord['doseNumber'] ?? 'N/A')
                                    .toString();
                            final administeredBy =
                                (historyRecord['administeredBy'] ??
                                        'Not recorded')
                                    .toString();
                            final adverseEvents =
                                (historyRecord['adverseEvents'] ??
                                        'None reported')
                                    .toString();
                            final status =
                                (historyRecord['status'] ?? 'Completed')
                                    .toString();

                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: _sidebarDark.withValues(alpha: 0.74),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _primaryAqua.withValues(alpha: 0.14),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          vaccine,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      _buildStatusChip(status),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 14,
                                    runSpacing: 8,
                                    children: [
                                      _buildImmunizationHistoryMetaText(
                                        'Date',
                                        administrationDate,
                                      ),
                                      _buildImmunizationHistoryMetaText(
                                        'Dose',
                                        doseNumber,
                                      ),
                                      _buildImmunizationHistoryMetaText(
                                        'Administered By',
                                        administeredBy,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Adverse events: $adverseEvents',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.7,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      TextButton.icon(
                                        onPressed: () {
                                          _showImmunizationDetails(
                                            context,
                                            historyRecord,
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.visibility_rounded,
                                          size: 16,
                                        ),
                                        label: const Text('View Details'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: _primaryAqua,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton.icon(
                                        onPressed: () {
                                          _showEditDialog(
                                            context,
                                            historyRecord,
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.edit_rounded,
                                          size: 16,
                                        ),
                                        label: const Text('Edit'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          child: const Text('Close'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            _showNewImmunizationModal(
                              context,
                              patientSeed: latestRecord,
                            );
                          },
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add Another Immunization'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryAqua,
                            foregroundColor: _darkDeepTeal,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
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
    );
  }

  Widget _buildImmunizationHistorySummaryCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.68),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImmunizationHistoryMetaText(String label, String value) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.58),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
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
        activeItem: WebSidebarItem.immunization,
      ),
      body: Column(
        children: [
          // Fixed Web Header Bar
          _buildWebHeaderBar(context),

          // Content Area with proper web layout
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _primaryAqua),
                  )
                : Stack(
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24.0,
                          vertical: 20.0,
                        ),
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              HealthModuleViewHeader(
                                title: 'Immunization Management',
                                description:
                                    'Monitor vaccination performance and follow-up needs, or manage individual immunization records.',
                                activeView: _activeView,
                                onViewChanged: _setActiveView,
                                primaryColor: _primaryAqua,
                              ),
                              const SizedBox(height: 20),
                              if (_activeView == HealthModuleView.insights)
                                if (_immunizationRecords.isEmpty)
                                  const ModuleEmptyState(
                                    title: 'No immunization insights yet',
                                    message:
                                        'Add an immunization record to begin monitoring vaccine activity, schedules, and follow-up needs.',
                                    icon: Icons.vaccines_outlined,
                                  )
                                else
                                  ImmunizationInsights(
                                    records: _immunizationRecords,
                                  )
                              else ...[_buildImmunizationTable()],
                              const SizedBox(
                                height: 80,
                              ), // Space for bottom selection action card
                            ],
                          ),
                        ),
                      ),
                      if (_activeView == HealthModuleView.records)
                        _buildSelectionActionCard(),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: null,
    );
  }

  // Search Bar Widget
  Widget _buildSearchBar() {
    final showAddButton =
        !(_isDeleteDialogShowing ||
            (_isSelectionMode && _selectedIndices.isNotEmpty));

    return LayoutBuilder(
      builder: (context, constraints) {
        final useStackedHeader = constraints.maxWidth < 760;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (useStackedHeader) ...[
              _buildImmunizationRecordsTitle(),
              if (showAddButton) ...[
                const SizedBox(height: 12),
                _buildAddImmunizationButtonContainer(context),
              ],
            ] else
              Row(
                children: [
                  Expanded(child: _buildImmunizationRecordsTitle()),
                  if (showAddButton) ...[
                    const SizedBox(width: 16),
                    _buildAddImmunizationButtonContainer(context),
                  ],
                ],
              ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: _darkDeepTeal,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
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
                  setState(() {
                    _searchQuery = value;
                    _currentPage = 1;
                    _selectedIndices.clear();
                  });
                  _scheduleSharedPatientSearch(value);
                },
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText:
                      'Search by patient name, patient ID, vaccine type, or status...',
                  hintStyle: const TextStyle(color: Colors.white),
                  prefixIcon: const Icon(Icons.search, color: Colors.white),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                              _currentPage = 1;
                              _selectedIndices.clear();
                            });
                            _scheduleSharedPatientSearch('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: _darkDeepTeal,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
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
                secondaryActionLabel: 'Add Immunization',
                onSecondaryAction: (patient) =>
                    _showNewImmunizationModal(context, patientSeed: patient),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildImmunizationRecordsTitle() {
    return const Text(
      'Immunization Records',
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _buildAddImmunizationButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showNewImmunizationModal(context),
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

  Widget _buildAddImmunizationButtonContainer(BuildContext context) {
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
      child: _buildAddImmunizationButton(context),
    );
  }

  // Web Header Bar
  Widget _buildWebHeaderBar(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_darkDeepTeal, _darkDeepTeal.withValues(alpha: 0.92)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border(
          bottom: BorderSide(
            color: _primaryAqua.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Menu Button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
              hoverColor: _primaryAqua.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.menu_rounded, color: Colors.white, size: 28),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Title
          Text(
            'Immunization Dashboard',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          // Selection Mode Info
          if (_isSelectionMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _primaryAqua.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _primaryAqua, width: 1.5),
              ),
              child: Row(
                children: [
                  Text(
                    '${_selectedIndices.length}',
                    style: const TextStyle(
                      color: _primaryAqua,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'selected',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Immunization Records Table
  Widget _buildImmunizationTable() {
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
    final displayRecords = pagedRecords.map(_buildDisplayRecord).toList();
    final hasActiveFilters =
        _selectedVaccineFilter != 'All Vaccines' ||
        _fromDate != null ||
        _toDate != null ||
        _searchQuery.isNotEmpty;
    final showFilteredEmptyState =
        records.isEmpty && _immunizationRecords.isNotEmpty && hasActiveFilters;
    final showInitialEmptyState = _immunizationRecords.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Web-oriented data table - Full width with integrated filters
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _sidebarDark,
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
                        // Vaccine Filter Dropdown
                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _darkDeepTeal,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _primaryAqua.withValues(alpha: 0.45),
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.vaccines,
                                  color: _primaryAqua,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedVaccineFilter,
                                      isExpanded: true,
                                      icon: const Icon(
                                        Icons.arrow_drop_down,
                                        color: Colors.white70,
                                        size: 16,
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      dropdownColor: _darkDeepTeal,
                                      borderRadius: BorderRadius.circular(8),
                                      items: _vaccineFilterOptions.map((
                                        String option,
                                      ) {
                                        return DropdownMenuItem<String>(
                                          value: option,
                                          child: Text(
                                            option,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (String? newValue) {
                                        if (newValue != null) {
                                          setState(() {
                                            _selectedVaccineFilter = newValue;
                                            _currentPage = 1;
                                            _selectedIndices.clear();
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

                        // Date Range Filter
                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: _darkDeepTeal,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _primaryAqua.withValues(alpha: 0.45),
                                width: 1.2,
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
                                          _selectedIndices.clear();
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
                        const SizedBox(width: 16),

                        // Select Immunization Records Button
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: _darkDeepTeal,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _isSelectionMode
                                    ? _primaryAqua.withValues(alpha: 0.65)
                                    : _primaryAqua.withValues(alpha: 0.45),
                                width: 1.2,
                              ),
                            ),
                            child: Material(
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
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _isSelectionMode
                                          ? Icons.close
                                          : Icons.checklist,
                                      color: _isSelectionMode
                                          ? _primaryAqua
                                          : Colors.white70,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _isSelectionMode ? 'Active' : 'Select',
                                        style: TextStyle(
                                          color: _isSelectionMode
                                              ? _primaryAqua
                                              : _lightOffWhite,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
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

              // Divider
              Divider(
                color: _primaryAqua.withValues(alpha: 0.3),
                height: 0,
                thickness: 2,
              ),

              // Records Count and Table
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showInitialEmptyState)
                      _buildImmunizationEmptyState(
                        icon: Icons.vaccines,
                        title: 'No immunization records',
                        message:
                            'Add your first immunization record to get started',
                      )
                    else if (showFilteredEmptyState)
                      _buildImmunizationEmptyState(
                        icon: Icons.search_off,
                        title: 'No immunization records found',
                        message: 'Try adjusting your filters or search terms',
                      )
                    else ...[
                      _buildImmunizationCardHeader(),
                      _ImmunizationTable(
                        records: displayRecords,
                        startIndex: pageStartIndex,
                        isSelectionMode: _isSelectionMode,
                        selectedIndices: _selectedIndices,
                        onSelectionChanged: (index, selected) {
                          setState(() {
                            if (selected) {
                              _selectedIndices.add(index);
                            } else {
                              _selectedIndices.remove(index);
                            }
                          });
                        },
                        onEdit: (record) {
                          _showEditDialog(context, record);
                        },
                        onDelete: (record) async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: _sidebarDark,
                              title: Text(
                                'Delete Immunization',
                                style: TextStyle(
                                  color: _primaryAqua,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              content: Text(
                                'Are you sure you want to delete this record?',
                                style: TextStyle(color: _lightOffWhite),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await _dbHelper.deleteRecord(record['id']);
                            await _loadRecords();
                          }
                        },
                        onView: (record) {
                          _showPatientImmunizationHistory(context, record);
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildImmunizationTablePagination(
                        currentPage: currentPage,
                        totalPages: totalPages,
                        startIndex: pageStartIndex,
                        endIndex: pageEndIndex,
                        totalRecords: records.length,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImmunizationEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Icon(icon, size: 64, color: _mutedCoolGray),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: _mutedCoolGray,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: _mutedCoolGray, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // Format date helper
  String _formatDate(dynamic dateValue) {
    try {
      if (dateValue == null || dateValue.isEmpty) return 'N/A';
      final date = DateTime.parse(dateValue.toString());
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'N/A';
    }
  }

  Widget _buildImmunizationHeaderCell(String label, {required int flex}) {
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

  Widget _buildImmunizationHeaderDivider() {
    return Container(
      width: 1,
      height: 18,
      color: Colors.white.withValues(alpha: 0.2),
    );
  }

  Widget _buildImmunizationCardHeader() {
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
          _buildImmunizationHeaderCell('Patient', flex: 26),
          _buildImmunizationHeaderDivider(),
          _buildImmunizationHeaderCell('Administration Details', flex: 28),
          _buildImmunizationHeaderDivider(),
          _buildImmunizationHeaderCell('Type', flex: 22),
          _buildImmunizationHeaderDivider(),
          _buildImmunizationHeaderCell('Status', flex: 14),
          if (!_isSelectionMode) ...[
            _buildImmunizationHeaderDivider(),
            SizedBox(
              width: 148,
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

  // Immunization Records Table
  Widget _ImmunizationTable({
    required List<Map<String, dynamic>> records,
    required int startIndex,
    required bool isSelectionMode,
    required Set<int> selectedIndices,
    required Function(int, bool) onSelectionChanged,
    required Function(Map<String, dynamic>) onEdit,
    required Function(Map<String, dynamic>) onDelete,
    Function(Map<String, dynamic>)? onView,
  }) {
    if (records.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              Icon(Icons.vaccines, size: 64, color: _mutedCoolGray),
              const SizedBox(height: 16),
              Text(
                'No immunization records found',
                style: TextStyle(
                  color: _mutedCoolGray,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try adjusting your filters or search terms',
                style: TextStyle(color: _mutedCoolGray, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: List.generate(records.length, (index) {
        final absoluteIndex = startIndex + index;
        final isSelected = selectedIndices.contains(absoluteIndex);
        return _ImmunizationCard(
          record: records[index],
          isSelectionMode: isSelectionMode,
          isSelected: isSelected,
          index: absoluteIndex,
          onSelectionChanged: onSelectionChanged,
          onEdit: onEdit,
          onDelete: onDelete,
          onView: onView,
        );
      }),
    );
  }

  Widget _buildImmunizationTablePagination({
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
        color: _darkDeepTeal,
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
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _sidebarDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _primaryAqua.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _rowsPerPage,
                dropdownColor: _sidebarDark,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                icon: const Icon(
                  Icons.arrow_drop_down,
                  color: Colors.white70,
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
            color: canGoPrev ? _primaryAqua : Colors.white24,
            tooltip: 'Previous page',
          ),
          Text(
            '$currentPage / $totalPages',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            onPressed: canGoNext
                ? () => setState(() => _currentPage = currentPage + 1)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
            color: canGoNext ? _primaryAqua : Colors.white24,
            tooltip: 'Next page',
          ),
        ],
      ),
    );
  }

  // Selection Action Card - Floating card for bulk actions
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _primaryAqua.withValues(alpha: 0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: _darkDeepTeal.withValues(alpha: 0.2),
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
                    color: _darkDeepTeal,
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
                          _getFilteredRecords().length,
                          (index) => index,
                        );
                        _selectedIndices.addAll(allIndices);
                      });
                    },
                    icon: Icon(Icons.select_all, size: 18),
                    label: Text('Select All'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
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
                    onPressed: _showDeleteConfirmDialog,
                    icon: Icon(Icons.delete, size: 18),
                    label: Text('Delete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
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
                      foregroundColor: _mutedCoolGray,
                      side: BorderSide(color: _mutedCoolGray, width: 1.5),
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

  void _showDeleteConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Records'),
        content: Text('Delete ${_selectedIndices.length} selected record(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteSelectedRecords();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredRecords() {
    final filtered = _immunizationRecords.where((record) {
      // Vaccine filter
      bool vaccineMatch = true;
      if (_selectedVaccineFilter != 'All Vaccines') {
        vaccineMatch = record['vaccine'] == _selectedVaccineFilter;
      }

      // Date range filter
      bool dateMatch = true;
      if (_fromDate != null || _toDate != null) {
        final recordDate = DateTime.parse(record['date']);
        if (_fromDate != null && recordDate.isBefore(_fromDate!)) {
          dateMatch = false;
        }
        if (_toDate != null && recordDate.isAfter(_toDate!)) {
          dateMatch = false;
        }
      }

      // Search filter
      bool searchMatch = true;
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        searchMatch =
            (record['patientName']?.toString().toLowerCase().contains(query) ??
                false) ||
            (record['patientId']?.toString().toLowerCase().contains(query) ??
                false) ||
            (record['vaccine']?.toString().toLowerCase().contains(query) ??
                false) ||
            (record['status']?.toString().toLowerCase().contains(query) ??
                false);
      }

      return vaccineMatch && dateMatch && searchMatch;
    }).toList();

    return CurrentTableRecordUtils.collapseToLatestPerEntity(
      filtered,
      idKeys: const ['patientId', 'linkedPatientId', 'patientCode'],
      nameKeys: const ['patientName'],
      dateKeys: const ['administrationDate', 'date', 'time'],
    );
  }

  List<String> _sanitizeDropdownItems(List<String> items) {
    final seen = <String>{};
    final sanitized = <String>[];
    for (final item in items) {
      final trimmed = item.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        continue;
      }
      sanitized.add(trimmed);
    }
    return sanitized;
  }

  String _normalizeVaccineType(dynamic rawValue) {
    final value = (rawValue ?? '').toString().trim();
    if (value.isEmpty) {
      return _vaccineTypeOptions.first;
    }

    final normalized = value.toLowerCase();
    const aliases = <String, String>{
      'bcg': 'BCG Vaccine',
      'bcg vaccine': 'BCG Vaccine',
      'hepatitis b': 'Hepatitis B',
      'hepatitis b vaccine': 'Hepatitis B',
      'hep b': 'Hepatitis B',
      'hepa b': 'Hepatitis B',
      'dpt': 'DPT Vaccine',
      'dpt vaccine': 'DPT Vaccine',
      'polio': 'Polio Vaccine',
      'polio vaccine': 'Polio Vaccine',
      'mmr': 'MMR Vaccine',
      'mmr vaccine': 'MMR Vaccine',
      'varicella': 'Varicella Vaccine',
      'varicella vaccine': 'Varicella Vaccine',
      'influenza': 'Influenza',
      'pneumococcal': 'Pneumococcal',
    };

    final aliased = aliases[normalized];
    if (aliased != null) {
      return aliased;
    }

    for (final option in _vaccineTypeOptions) {
      if (option.toLowerCase() == normalized) {
        return option;
      }
    }

    return _vaccineTypeOptions.first;
  }

  Future<void> _generateImmunizationReport() {
    return generateReportPdf(
      context: context,
      moduleLabel: 'Immunization',
      records: _getFilteredRecords(),
      dateResolver: (record) =>
          parseReportDateValue(record['administrationDate']) ??
          parseReportDateValue(record['date']),
      columns: [
        ReportCsvColumn(
          'Patient ID',
          (record) => reportText(record['patientId']),
          flex: 0.9,
        ),
        ReportCsvColumn(
          'Patient Name',
          (record) => reportText(record['patientName']),
          flex: 1.35,
        ),
        ReportCsvColumn(
          'Age',
          (record) => reportText(record['age']),
          flex: 0.55,
          center: true,
        ),
        ReportCsvColumn(
          'Vaccine Type',
          (record) => reportText(record['vaccine']),
          flex: 1.2,
        ),
        ReportCsvColumn(
          'Administration Date',
          (record) => formatReportDateValue(record['administrationDate']),
          flex: 0.95,
          center: true,
        ),
        ReportCsvColumn(
          'Dose Number',
          (record) => reportText(record['doseNumber']),
          flex: 0.6,
          center: true,
        ),
        ReportCsvColumn(
          'Status',
          (record) => reportText(record['status']),
          flex: 0.9,
          center: true,
        ),
        ReportCsvColumn(
          'Administered By',
          (record) => reportText(record['administeredBy']),
          flex: 1.1,
        ),
        ReportCsvColumn(
          'Route',
          (record) => reportText(record['routeOfAdministration']),
          flex: 0.95,
        ),
        ReportCsvColumn(
          'Injection Site',
          (record) => reportText(record['injectionSite']),
          flex: 0.95,
        ),
        ReportCsvColumn(
          'Adverse Events',
          (record) => reportText(record['adverseEvents'], fallback: 'None'),
          flex: 1.2,
        ),
      ],
      accentColor: _primaryAqua,
      dialogColor: Colors.white,
      textColor: _darkDeepTeal,
      mutedColor: _mutedCoolGray,
      sectionTitleBuilder: (record, index) =>
          'Record ${index + 1}: ${reportText(record['patientName'], fallback: 'Patient')}',
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
            colorScheme: const ColorScheme.dark(
              primary: _primaryAqua,
              onPrimary: Colors.white,
              surface: _sidebarDark,
              onSurface: Colors.white,
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

    if (picked != null) {
      setState(() {
        if (isFromDate) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
        _currentPage = 1;
        _selectedIndices.clear();
      });
    }
  }

  void _clearDateFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _currentPage = 1;
      _selectedIndices.clear();
    });
  }

  Future<void> _showNewImmunizationModal(
    BuildContext context, {
    Map<String, dynamic>? patientSeed,
  }) async {
    patientSeed = await _patientHistoryService.resolveRegisteredPatient(
      patientSeed,
    );
    if (patientSeed == null) {
      patientSeed = await PatientFirstServiceSelector.selectRegisteredPatient(
        context,
        serviceLabel: 'Immunization',
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
    // Controllers
    final firstNameController = TextEditingController();
    final surnameController = TextEditingController();
    final patientIdController = TextEditingController();
    final ageController = TextEditingController();
    final contactNumberController = TextEditingController();

    if (patientSeed != null) {
      final name = patientNameParts(patientSeed);
      firstNameController.text = name.firstName;
      surnameController.text = name.surname;
      patientIdController.text = (patientSeed['patientId'] ?? '').toString();
      ageController.text = (patientSeed['age'] ?? '').toString();
      contactNumberController.text = (patientSeed['contactNumber'] ?? '')
          .toString();
    }

    String selectedVaccineType = _normalizeVaccineType(
      patientSeed != null ? patientSeed['vaccine'] : null,
    );
    final vaccineBrandController = TextEditingController();
    final batchNumberController = TextEditingController();
    DateTime? expirationDate;

    DateTime? administrationDate = DateTime.now();
    TimeOfDay? administrationTime = TimeOfDay.now();
    final doseNumberController = TextEditingController();
    String selectedRouteOfAdministration = 'Intramuscular (IM)';
    String selectedInjectionSite = 'Left Upper Arm';
    final administeredByController = TextEditingController();
    final adverseEventsController = TextEditingController();
    DateTime? nextDoseDueDate;
    final modalTitle = patientSeed == null
        ? 'New Immunization Record'
        : 'Add Another Immunization';

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
                              'Vaccine administration and follow-up planning',
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
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Patient Details
                        _buildSectionHeader('Patient Details', Icons.person),
                        _buildFormCard([
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
                                  controller: patientIdController,
                                  label: 'Patient ID',
                                  icon: Icons.badge,
                                  hintText: 'e.g., PAT-2026-001',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: ageController,
                                  label: 'Age',
                                  icon: Icons.cake,
                                  hintText: 'Enter age',
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: contactNumberController,
                            label: 'Contact Number',
                            icon: Icons.phone,
                            hintText: 'e.g., +63 912 345 6789',
                            keyboardType: TextInputType.phone,
                          ),
                        ]),
                        const SizedBox(height: 24),

                        // Vaccine Details
                        _buildSectionHeader(
                          'Vaccine Details',
                          Icons.medical_services,
                        ),
                        _buildFormCard([
                          _buildDropdownField(
                            label: 'Vaccine Type',
                            value: selectedVaccineType,
                            icon: Icons.vaccines,
                            items: _vaccineTypeOptions,
                            onChanged: (value) {
                              if (value != null) {
                                setModalState(
                                  () => selectedVaccineType = value,
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: vaccineBrandController,
                            label: 'Vaccine Brand',
                            icon: Icons.business,
                            hintText: 'Enter vaccine brand/manufacturer',
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: batchNumberController,
                            label: 'Batch/Lot Number',
                            icon: Icons.numbers,
                            hintText: 'Enter batch or lot number',
                          ),
                          const SizedBox(height: 16),
                          _buildModalDatePickerField(
                            context: context,
                            label: 'Expiration Date',
                            date: expirationDate,
                            icon: Icons.event_busy,
                            onTap: () async {
                              final picked = await _showModalDatePicker(
                                context,
                              );
                              if (picked != null) {
                                setModalState(() => expirationDate = picked);
                              }
                            },
                          ),
                        ]),
                        const SizedBox(height: 24),

                        // Administration Details
                        _buildSectionHeader(
                          'Administration Details',
                          Icons.local_hospital,
                        ),
                        _buildFormCard([
                          Row(
                            children: [
                              Expanded(
                                child: _buildModalDatePickerField(
                                  context: context,
                                  label: 'Administration Date',
                                  date: administrationDate,
                                  icon: Icons.calendar_today,
                                  onTap: () async {
                                    final picked = await _showModalDatePicker(
                                      context,
                                    );
                                    if (picked != null) {
                                      setModalState(
                                        () => administrationDate = picked,
                                      );
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTimePickerField(
                                  context: context,
                                  label: 'Administration Time',
                                  time: administrationTime,
                                  icon: Icons.access_time,
                                  onTap: () async {
                                    final picked = await showTimePicker(
                                      context: context,
                                      initialTime:
                                          administrationTime ?? TimeOfDay.now(),
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
                                      setModalState(
                                        () => administrationTime = picked,
                                      );
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: doseNumberController,
                            label: 'Dose Number',
                            icon: Icons.format_list_numbered,
                            hintText: 'e.g., 1st dose, 2nd dose',
                          ),
                          const SizedBox(height: 16),
                          _buildDropdownField(
                            label: 'Route of Administration',
                            value: selectedRouteOfAdministration,
                            icon: Icons.medical_information,
                            items: [
                              'Intramuscular (IM)',
                              'Subcutaneous (SC)',
                              'Intradermal (ID)',
                              'Oral',
                              'Intranasal',
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setModalState(
                                  () => selectedRouteOfAdministration = value,
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildDropdownField(
                            label: 'Injection Site',
                            value: selectedInjectionSite,
                            icon: Icons.place,
                            items: [
                              'Left Upper Arm',
                              'Right Upper Arm',
                              'Left Thigh',
                              'Right Thigh',
                              'Left Buttock',
                              'Right Buttock',
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setModalState(
                                  () => selectedInjectionSite = value,
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: administeredByController,
                            label: 'Administered By',
                            icon: Icons.person_pin,
                            hintText: 'Enter staff name or ID',
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: adverseEventsController,
                            label: 'Adverse Events/Reactions',
                            icon: Icons.warning,
                            hintText: 'Note any adverse reactions or events',
                            maxLines: 3,
                          ),
                          const SizedBox(height: 16),
                          _buildModalDatePickerField(
                            context: context,
                            label: 'Next Dose Due Date',
                            date: nextDoseDueDate,
                            icon: Icons.event,
                            onTap: () async {
                              final picked = await _showModalDatePicker(
                                context,
                              );
                              if (picked != null) {
                                setModalState(() => nextDoseDueDate = picked);
                              }
                            },
                          ),
                        ]),
                        const SizedBox(height: 32),

                        // Submit Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              // Create new immunization record
                              final newRecord = {
                                'time':
                                    '${administrationTime?.hour.toString().padLeft(2, '0')}:${administrationTime?.minute.toString().padLeft(2, '0')}',
                                'patientName':
                                    '${firstNameController.text} ${surnameController.text}'
                                        .trim(),
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
                                'age': ageController.text,
                                'contactNumber': contactNumberController.text,
                                'vaccine': selectedVaccineType,
                                'vaccineBrand': vaccineBrandController.text,
                                'batchNumber': batchNumberController.text,
                                'expirationDate':
                                    expirationDate?.toIso8601String() ?? '',
                                'administrationDate':
                                    administrationDate?.toIso8601String() ?? '',
                                'administrationTime':
                                    '${administrationTime?.hour.toString().padLeft(2, '0')}:${administrationTime?.minute.toString().padLeft(2, '0')}',
                                'doseNumber': doseNumberController.text,
                                'routeOfAdministration':
                                    selectedRouteOfAdministration,
                                'injectionSite': selectedInjectionSite,
                                'administeredBy': administeredByController.text,
                                'adverseEvents': adverseEventsController.text,
                                'nextDoseDueDate':
                                    nextDoseDueDate?.toIso8601String() ?? '',
                                'status': 'Completed',
                                'date':
                                    administrationDate?.toIso8601String() ?? '',
                              };

                              // Save to database (offline + Firebase sync)
                              await _dbHelper.insertRecord(newRecord);

                              // Reload records
                              await _loadRecords();

                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Immunization record saved successfully!',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryAqua,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            child: const Text(
                              'Save Immunization Record',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
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

  Future<DateTime?> _showModalDatePicker(BuildContext context) async {
    return await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: _primaryAqua,
              onPrimary: Colors.white,
              surface: _darkDeepTeal,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primaryAqua.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
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
        children: children,
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
          style: TextStyle(
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
          style: TextStyle(
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
            fillColor: _darkDeepTeal,
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
              borderSide: BorderSide(color: _primaryAqua, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModalDatePickerField({
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
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _darkDeepTeal,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: date != null
                    ? _primaryAqua
                    : Colors.white.withValues(alpha: 0.2),
                width: date != null ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text(
                  date != null
                      ? '${date.day}/${date.month}/${date.year}'
                      : 'Select Date',
                  style: TextStyle(
                    color: Colors.white,
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

  Widget _buildTimePickerField({
    required BuildContext context,
    required String label,
    required TimeOfDay? time,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _mutedCoolGray,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _lightOffWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: time != null
                    ? _primaryAqua
                    : _mutedCoolGray.withValues(alpha: 0.3),
                width: time != null ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: _primaryAqua, size: 20),
                const SizedBox(width: 12),
                Text(
                  time != null ? time.format(context) : 'Select Time',
                  style: TextStyle(
                    color: time != null ? _darkDeepTeal : _mutedCoolGray,
                    fontSize: 14,
                    fontWeight: time != null
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

  Widget _buildModalTimePickerField({
    required BuildContext context,
    required String label,
    required TimeOfDay? time,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _darkDeepTeal,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: time != null
                    ? _primaryAqua
                    : Colors.white.withValues(alpha: 0.2),
                width: time != null ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text(
                  time != null ? time.format(context) : 'Select Time',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: time != null
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

  Future<TimeOfDay?> _showModalTimePicker(
    BuildContext context,
    TimeOfDay? initialTime,
  ) async {
    return await showTimePicker(
      context: context,
      initialTime: initialTime ?? TimeOfDay.now(),
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

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required IconData icon,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    final sanitizedItems = _sanitizeDropdownItems(items);
    final safeValue = sanitizedItems.contains(value)
        ? value
        : (sanitizedItems.isNotEmpty ? sanitizedItems.first : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: _darkDeepTeal,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: safeValue,
                    isExpanded: true,
                    icon: Icon(Icons.arrow_drop_down, color: Colors.white),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    dropdownColor: _darkDeepTeal,
                    items: sanitizedItems.map((String item) {
                      return DropdownMenuItem<String>(
                        value: item,
                        child: Text(
                          item,
                          style: const TextStyle(color: Colors.white),
                        ),
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

  Widget _buildFilters() {
    return Column(
      children: [
        // Vaccine Filter
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Icon(Icons.vaccines, color: _primaryAqua, size: 20),
              ),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedVaccineFilter,
                    isExpanded: true,
                    icon: Icon(Icons.arrow_drop_down, color: _primaryAqua),
                    style: TextStyle(
                      color: _darkDeepTeal,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    dropdownColor: _darkDeepTeal,
                    borderRadius: BorderRadius.circular(12),
                    items: _vaccineFilterOptions.map((String option) {
                      return DropdownMenuItem<String>(
                        value: option,
                        child: Text(
                          option,
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedVaccineFilter = newValue;
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
          padding: const EdgeInsets.all(16),
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
                  Icon(Icons.date_range, color: _primaryAqua, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Filter by Date Range',
                    style: TextStyle(
                      color: _darkDeepTeal,
                      fontSize: 14,
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
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: _darkDeepTeal,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _primaryAqua.withValues(alpha: 0.45),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 14, color: _primaryAqua),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                date != null ? '${date.day}/${date.month}/${date.year}' : label,
                style: TextStyle(
                  color: date != null
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.75),
                  fontSize: 12,
                  fontWeight: date != null
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
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

  Widget _buildImmunizationCard({
    required BuildContext context,
    required int index,
    required Map<String, dynamic> record,
  }) {
    final isSelected = _selectedIndices.contains(index);
    final time = record['time'] ?? 'N/A';
    final patientName = record['patientName'] ?? 'N/A';
    final vaccine = record['vaccine'] ?? 'N/A';
    final status = record['status'] ?? 'N/A';

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
              // Time and Status Header with Selection Checkbox
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (_isSelectionMode) ...[
                        Checkbox(
                          value: isSelected,
                          onChanged: (value) {
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
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _primaryAqua.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.access_time,
                          color: _primaryAqua,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        time,
                        style: TextStyle(
                          color: _darkDeepTeal,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  _buildStatusChip(status),
                ],
              ),
              const SizedBox(height: 16),

              // Patient Name and Vaccine Info
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.person, size: 16, color: _mutedCoolGray),
                            const SizedBox(width: 6),
                            Text(
                              'Patient Name',
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
                          patientName,
                          style: TextStyle(
                            color: _darkDeepTeal,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.vaccines,
                              size: 16,
                              color: _mutedCoolGray,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Vaccine',
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
                          vaccine,
                          style: TextStyle(
                            color: _darkDeepTeal,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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
                        onPressed: () {
                          _showImmunizationDetails(context, record);
                        },
                        icon: Icon(Icons.visibility, size: 16),
                        label: Text(
                          'View',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryAqua,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _showEditDialog(context, record);
                        },
                        icon: Icon(Icons.edit, size: 16),
                        label: Text(
                          'Edit',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primaryAqua,
                          side: BorderSide(color: _primaryAqua, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 10),
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
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color statusColor;
    switch (status) {
      case 'Completed':
        statusColor = const Color(0xFF4CAF50);
        break;
      case 'Scheduled':
        statusColor = const Color(0xFFFF9800);
        break;
      case 'In Progress':
        statusColor = const Color(0xFF2196F3);
        break;
      default:
        statusColor = const Color(0xFFB8C9DB);
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

  void _showImmunizationDetails(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final patientName = _safeImmunizationDetailText(
      record['patientName'],
      fallback: 'Unknown Patient',
    );
    final patientId = _safeImmunizationDetailText(record['patientId']);
    final vaccine = _safeImmunizationDetailText(record['vaccine']);
    final status = _safeImmunizationDetailText(
      record['status'],
      fallback: 'Scheduled',
    );
    final administrationDate = _formatDate(record['administrationDate']);
    final nextDoseDueDate = _formatDate(record['nextDoseDueDate']);
    final statusColor = _getImmunizationDetailStatusColor(status);
    final nameParts = patientName.split(' ');
    final initials = nameParts
        .where((part) => part.trim().isNotEmpty)
        .take(2)
        .map((part) => part.trim().substring(0, 1).toUpperCase())
        .join();

    showFullscreenDetailTableDialog(
      context: context,
      title: 'Immunization Details',
      subject: patientName,
      items: [
        DetailTableItem(
          icon: Icons.person_outline_rounded,
          label: 'Patient Name',
          value: patientName,
        ),
        DetailTableItem(
          icon: Icons.credit_card_outlined,
          label: 'Patient ID',
          value: patientId,
        ),
        DetailTableItem(
          icon: Icons.cake_outlined,
          label: 'Age',
          value: _safeImmunizationDetailText(record['age']),
        ),
        DetailTableItem(
          icon: Icons.phone_outlined,
          label: 'Contact Number',
          value: _safeImmunizationDetailText(record['contactNumber']),
        ),
        DetailTableItem(
          icon: Icons.vaccines_outlined,
          label: 'Vaccine Type',
          value: vaccine,
        ),
        DetailTableItem(
          icon: Icons.business_outlined,
          label: 'Vaccine Brand',
          value: _safeImmunizationDetailText(record['vaccineBrand']),
        ),
        DetailTableItem(
          icon: Icons.numbers_outlined,
          label: 'Batch/Lot Number',
          value: _safeImmunizationDetailText(record['batchNumber']),
        ),
        DetailTableItem(
          icon: Icons.event_busy_outlined,
          label: 'Expiration Date',
          value: _formatDate(record['expirationDate']),
        ),
        DetailTableItem(
          icon: Icons.event_outlined,
          label: 'Administration Date',
          value: administrationDate,
        ),
        DetailTableItem(
          icon: Icons.access_time_outlined,
          label: 'Administration Time',
          value: _safeImmunizationDetailText(record['administrationTime']),
        ),
        DetailTableItem(
          icon: Icons.filter_1_outlined,
          label: 'Dose Number',
          value: _safeImmunizationDetailText(record['doseNumber']),
        ),
        DetailTableItem(
          icon: Icons.route_outlined,
          label: 'Route of Administration',
          value: _safeImmunizationDetailText(record['routeOfAdministration']),
        ),
        DetailTableItem(
          icon: Icons.place_outlined,
          label: 'Injection Site',
          value: _safeImmunizationDetailText(record['injectionSite']),
        ),
        DetailTableItem(
          icon: Icons.person_pin_outlined,
          label: 'Administered By',
          value: _safeImmunizationDetailText(record['administeredBy']),
        ),
        DetailTableItem(
          icon: Icons.warning_amber_rounded,
          label: 'Adverse Events',
          value: _safeImmunizationDetailText(record['adverseEvents']),
        ),
        DetailTableItem(
          icon: Icons.event_available_outlined,
          label: 'Next Dose Due Date',
          value: nextDoseDueDate,
        ),
        DetailTableItem(
          icon: Icons.verified_outlined,
          label: 'Status',
          value: status,
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
                                      initials.isEmpty ? 'IM' : initials,
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
                                        'Immunization record overview with patient, vaccine, administration, and follow-up details.',
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
                                      Icons.vaccines_outlined,
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
                                          'Current immunization status',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'This vaccine record is marked as $status and currently references $vaccine.',
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
                                _buildImmunizationDetailMetaChip(
                                  icon: Icons.badge_outlined,
                                  label: 'Patient ID',
                                  value: patientId,
                                  accentColor: const Color(0xFF64B5F6),
                                ),
                                _buildImmunizationDetailMetaChip(
                                  icon: Icons.vaccines_outlined,
                                  label: 'Vaccine',
                                  value: vaccine,
                                  accentColor: const Color(0xFF81C784),
                                ),
                                _buildImmunizationDetailMetaChip(
                                  icon: Icons.event_outlined,
                                  label: 'Administered',
                                  value: administrationDate,
                                  accentColor: const Color(0xFFFFB74D),
                                ),
                                _buildImmunizationDetailMetaChip(
                                  icon: Icons.update_outlined,
                                  label: 'Next Dose',
                                  value: nextDoseDueDate,
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
                            _buildDetailsSection('Patient Information', [
                              _buildDetailRowWithIcon(
                                Icons.person,
                                'Patient Name',
                                record['patientName'],
                              ),
                              _buildDetailRowWithIcon(
                                Icons.badge,
                                'Patient ID',
                                record['patientId'],
                              ),
                              _buildDetailRowWithIcon(
                                Icons.cake,
                                'Age',
                                record['age'],
                              ),
                              _buildDetailRowWithIcon(
                                Icons.phone,
                                'Contact Number',
                                record['contactNumber'],
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildDetailsSection('Vaccine Information', [
                              _buildDetailRowWithIcon(
                                Icons.vaccines,
                                'Vaccine Type',
                                record['vaccine'],
                              ),
                              _buildDetailRowWithIcon(
                                Icons.business,
                                'Vaccine Brand',
                                record['vaccineBrand'],
                              ),
                              _buildDetailRowWithIcon(
                                Icons.numbers,
                                'Batch/Lot Number',
                                record['batchNumber'],
                              ),
                              _buildDetailRowWithIcon(
                                Icons.event_busy,
                                'Expiration Date',
                                _formatDate(record['expirationDate']),
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildDetailsSection('Administration Details', [
                              _buildDetailRowWithIcon(
                                Icons.event,
                                'Administration Date',
                                _formatDate(record['administrationDate']),
                              ),
                              _buildDetailRowWithIcon(
                                Icons.access_time,
                                'Administration Time',
                                record['administrationTime'],
                              ),
                              _buildDetailRowWithIcon(
                                Icons.filter_1,
                                'Dose Number',
                                record['doseNumber'],
                              ),
                              _buildDetailRowWithIcon(
                                Icons.route,
                                'Route of Administration',
                                record['routeOfAdministration'],
                              ),
                              _buildDetailRowWithIcon(
                                Icons.place,
                                'Injection Site',
                                record['injectionSite'],
                              ),
                              _buildDetailRowWithIcon(
                                Icons.person_pin,
                                'Administered By',
                                record['administeredBy'],
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _buildDetailsSection('Additional Information', [
                              _buildDetailRowWithIcon(
                                Icons.warning_amber,
                                'Adverse Events',
                                record['adverseEvents'] ?? 'None reported',
                              ),
                              _buildDetailRowWithIcon(
                                Icons.event_available,
                                'Next Dose Due Date',
                                _formatDate(record['nextDoseDueDate']),
                              ),
                              _buildDetailRowWithIcon(
                                Icons.info,
                                'Status',
                                record['status'],
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
                                  await _downloadImmunizationRecordPdf(
                                    context,
                                    record,
                                  );
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

  void _showEditDialog(BuildContext context, Map<String, dynamic> record) {
    // Parse patient name into first name and surname
    final patientName = record['patientName'] ?? '';
    final nameParts = patientName.split(' ');

    // Pre-fill controllers with existing data
    final firstNameController = TextEditingController(
      text: nameParts.isNotEmpty ? nameParts[0] : '',
    );
    final surnameController = TextEditingController(
      text: nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '',
    );
    final patientIdController = TextEditingController(
      text: record['patientId'],
    );
    final ageController = TextEditingController(text: record['age']);
    final contactNumberController = TextEditingController(
      text: record['contactNumber'],
    );

    String selectedVaccineType = _normalizeVaccineType(record['vaccine']);
    final vaccineBrandController = TextEditingController(
      text: record['vaccineBrand'],
    );
    final batchNumberController = TextEditingController(
      text: record['batchNumber'],
    );
    DateTime? expirationDate;
    try {
      expirationDate =
          record['expirationDate'] != null &&
              record['expirationDate'].isNotEmpty
          ? DateTime.parse(record['expirationDate'])
          : null;
    } catch (e) {
      expirationDate = null;
    }

    DateTime? administrationDate;
    try {
      administrationDate =
          record['administrationDate'] != null &&
              record['administrationDate'].isNotEmpty
          ? DateTime.parse(record['administrationDate'])
          : DateTime.now();
    } catch (e) {
      administrationDate = DateTime.now();
    }

    TimeOfDay? administrationTime;
    try {
      final timeString = record['administrationTime'];
      if (timeString != null && timeString.isNotEmpty) {
        final parts = timeString.split(':');
        administrationTime = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      } else {
        administrationTime = TimeOfDay.now();
      }
    } catch (e) {
      administrationTime = TimeOfDay.now();
    }

    final doseNumberController = TextEditingController(
      text: record['doseNumber'],
    );
    String selectedRouteOfAdministration =
        record['routeOfAdministration'] ?? 'Intramuscular (IM)';
    // Ensure the route exists in available options
    final routeOptions = [
      'Intramuscular (IM)',
      'Subcutaneous (SC)',
      'Intradermal (ID)',
      'Oral (PO)',
    ];
    if (!routeOptions.contains(selectedRouteOfAdministration)) {
      selectedRouteOfAdministration = 'Intramuscular (IM)';
    }

    String selectedInjectionSite = record['injectionSite'] ?? 'Left Upper Arm';
    // Ensure the injection site exists in available options
    final siteOptions = [
      'Left Upper Arm',
      'Right Upper Arm',
      'Left Thigh',
      'Right Thigh',
    ];
    if (!siteOptions.contains(selectedInjectionSite)) {
      selectedInjectionSite = 'Left Upper Arm';
    }
    final administeredByController = TextEditingController(
      text: record['administeredBy'],
    );
    final adverseEventsController = TextEditingController(
      text: record['adverseEvents'],
    );
    DateTime? nextDoseDueDate;
    try {
      nextDoseDueDate =
          record['nextDoseDueDate'] != null &&
              record['nextDoseDueDate'].isNotEmpty
          ? DateTime.parse(record['nextDoseDueDate'])
          : null;
    } catch (e) {
      nextDoseDueDate = null;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: _darkDeepTeal,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Modal Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_primaryAqua, _secondaryIceBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.edit, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Edit Immunization Record',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Form Content
              Flexible(
                child: StatefulBuilder(
                  builder: (context, setModalState) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Patient Details
                          _buildSectionHeader('Patient Details', Icons.person),
                          _buildFormCard([
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
                                    controller: patientIdController,
                                    label: 'Patient ID',
                                    icon: Icons.badge,
                                    hintText: 'e.g., PAT-2026-001',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildTextField(
                                    controller: ageController,
                                    label: 'Age',
                                    icon: Icons.cake,
                                    hintText: 'Enter age',
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: contactNumberController,
                              label: 'Contact Number',
                              icon: Icons.phone,
                              hintText: 'e.g., +63 912 345 6789',
                              keyboardType: TextInputType.phone,
                            ),
                          ]),
                          const SizedBox(height: 24),

                          // Vaccine Details
                          _buildSectionHeader(
                            'Vaccine Details',
                            Icons.medical_services,
                          ),
                          _buildFormCard([
                            _buildDropdownField(
                              label: 'Vaccine Type',
                              value: selectedVaccineType,
                              icon: Icons.vaccines,
                              items: _vaccineTypeOptions,
                              onChanged: (value) {
                                if (value != null) {
                                  setModalState(
                                    () => selectedVaccineType = value,
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: vaccineBrandController,
                              label: 'Vaccine Brand',
                              icon: Icons.business,
                              hintText: 'Enter vaccine brand/manufacturer',
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: batchNumberController,
                              label: 'Batch/Lot Number',
                              icon: Icons.numbers,
                              hintText: 'Enter batch or lot number',
                            ),
                            const SizedBox(height: 16),
                            _buildModalDatePickerField(
                              context: context,
                              label: 'Expiration Date',
                              date: expirationDate,
                              icon: Icons.event_busy,
                              onTap: () async {
                                final picked = await _showModalDatePicker(
                                  context,
                                );
                                if (picked != null) {
                                  setModalState(() => expirationDate = picked);
                                }
                              },
                            ),
                          ]),
                          const SizedBox(height: 24),

                          // Administration Details
                          _buildSectionHeader(
                            'Administration Details',
                            Icons.medical_information,
                          ),
                          _buildFormCard([
                            _buildModalDatePickerField(
                              context: context,
                              label: 'Administration Date',
                              date: administrationDate,
                              icon: Icons.event,
                              onTap: () async {
                                final picked = await _showModalDatePicker(
                                  context,
                                );
                                if (picked != null) {
                                  setModalState(
                                    () => administrationDate = picked,
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildModalTimePickerField(
                              context: context,
                              label: 'Administration Time',
                              time: administrationTime,
                              icon: Icons.access_time,
                              onTap: () async {
                                final picked = await _showModalTimePicker(
                                  context,
                                  administrationTime,
                                );
                                if (picked != null) {
                                  setModalState(
                                    () => administrationTime = picked,
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: doseNumberController,
                              label: 'Dose Number',
                              icon: Icons.filter_1,
                              hintText: 'e.g., 1, 2, 3',
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 16),
                            _buildDropdownField(
                              label: 'Route of Administration',
                              value: selectedRouteOfAdministration,
                              icon: Icons.route,
                              items: [
                                'Intramuscular (IM)',
                                'Subcutaneous (SC)',
                                'Intradermal (ID)',
                                'Oral',
                                'Intranasal',
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setModalState(
                                    () => selectedRouteOfAdministration = value,
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildDropdownField(
                              label: 'Injection Site',
                              value: selectedInjectionSite,
                              icon: Icons.place,
                              items: [
                                'Left Upper Arm',
                                'Right Upper Arm',
                                'Left Thigh',
                                'Right Thigh',
                                'Abdomen',
                                'Buttocks',
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setModalState(
                                    () => selectedInjectionSite = value,
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: administeredByController,
                              label: 'Administered By',
                              icon: Icons.person_pin,
                              hintText: 'Name of healthcare provider',
                            ),
                          ]),
                          const SizedBox(height: 24),

                          // Additional Information
                          _buildSectionHeader(
                            'Additional Information',
                            Icons.info_outline,
                          ),
                          _buildFormCard([
                            _buildTextField(
                              controller: adverseEventsController,
                              label: 'Adverse Events',
                              icon: Icons.warning_amber,
                              hintText: 'Any adverse reactions observed',
                              maxLines: 3,
                            ),
                            const SizedBox(height: 16),
                            _buildModalDatePickerField(
                              context: context,
                              label: 'Next Dose Due Date',
                              date: nextDoseDueDate,
                              icon: Icons.event_available,
                              onTap: () async {
                                final picked = await _showModalDatePicker(
                                  context,
                                );
                                if (picked != null) {
                                  setModalState(() => nextDoseDueDate = picked);
                                }
                              },
                            ),
                          ]),
                          const SizedBox(height: 24),

                          // Save Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                // Update immunization record
                                final updatedRecord = {
                                  'time':
                                      '${administrationTime?.hour.toString().padLeft(2, '0')}:${administrationTime?.minute.toString().padLeft(2, '0')}',
                                  'patientName':
                                      '${firstNameController.text} ${surnameController.text}'
                                          .trim(),
                                  'patientId': patientIdController.text,
                                  'age': ageController.text,
                                  'contactNumber': contactNumberController.text,
                                  'vaccine': selectedVaccineType,
                                  'vaccineBrand': vaccineBrandController.text,
                                  'batchNumber': batchNumberController.text,
                                  'expirationDate':
                                      expirationDate?.toIso8601String() ?? '',
                                  'administrationDate':
                                      administrationDate?.toIso8601String() ??
                                      '',
                                  'administrationTime':
                                      '${administrationTime?.hour.toString().padLeft(2, '0')}:${administrationTime?.minute.toString().padLeft(2, '0')}',
                                  'doseNumber': doseNumberController.text,
                                  'routeOfAdministration':
                                      selectedRouteOfAdministration,
                                  'injectionSite': selectedInjectionSite,
                                  'administeredBy':
                                      administeredByController.text,
                                  'adverseEvents': adverseEventsController.text,
                                  'nextDoseDueDate':
                                      nextDoseDueDate?.toIso8601String() ?? '',
                                  'status': record['status'] ?? 'Completed',
                                  'date':
                                      administrationDate?.toIso8601String() ??
                                      '',
                                };

                                // Update in database
                                final id = record['id']?.toString() ?? '';
                                if (id.isNotEmpty) {
                                  await _dbHelper.updateRecord(
                                    id,
                                    updatedRecord,
                                  );
                                }

                                // Reload records
                                await _loadRecords();

                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Immunization record updated successfully!',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    backgroundColor: Colors.green,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
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
                                'Update Immunization Record',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _safeImmunizationDetailText(
    dynamic value, {
    String fallback = 'Not recorded',
  }) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  Color _getImmunizationDetailStatusColor(String status) {
    final lower = status.toLowerCase();

    if (lower.contains('complete')) return const Color(0xFF66BB6A);
    if (lower.contains('progress')) return const Color(0xFF64B5F6);
    if (lower.contains('schedule')) return const Color(0xFFFFB74D);
    if (lower.contains('missed') || lower.contains('overdue')) {
      return const Color(0xFFE57373);
    }
    return _primaryAqua;
  }

  Widget _buildImmunizationDetailMetaChip({
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

  Widget _buildDetailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _mutedCoolGray,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
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

  Widget _buildDetailsSection(String title, List<Widget> children) {
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

  Widget _buildDetailRowWithIcon(IconData icon, String label, dynamic value) {
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
              child: Icon(icon, size: 18, color: _primaryAqua),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.62),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _safeImmunizationDetailText(value),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
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

  Widget _buildActionMenuButton() {
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  _isSelectionMode ? Icons.close : Icons.check_circle_outline,
                  color: _primaryAqua,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isSelectionMode
                        ? 'Selection Mode Active'
                        : 'Select Records',
                    style: TextStyle(
                      color: _darkDeepTeal,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_isSelectionMode && _selectedIndices.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_selectedIndices.length} selected',
                      style: TextStyle(
                        color: _primaryAqua,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Icon(Icons.arrow_drop_down, color: _primaryAqua),
              ],
            ),
          ),
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

  Future<void> _deleteSelectedRecords() async {
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

    // Remove deleted records from list directly (no loading refresh)
    setState(() {
      _immunizationRecords.removeWhere(
        (record) => idsToDelete.contains(record['id']),
      );
      _selectedIndices.clear();
      _isSelectionMode = false;
    });

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
                    isActive: true,
                    onTap: () {},
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

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: Colors.white,
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
                child: Icon(Icons.menu_rounded, color: _darkDeepTeal, size: 24),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _generateImmunizationReport,
            style: OutlinedButton.styleFrom(
              foregroundColor: _darkDeepTeal,
              side: BorderSide(color: _primaryAqua.withValues(alpha: 0.45)),
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
          PopupMenuButton(
            icon: const Icon(Icons.more_vert_outlined),
            color: _mutedCoolGray,
            itemBuilder: (context) => [
              PopupMenuItem(
                child: const Text('Seed Sample Data'),
                onTap: () => _seedSampleData(),
              ),
              PopupMenuItem(
                child: const Text('Refresh Data'),
                onTap: () => _loadRecords(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImmunizationCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final bool isSelectionMode;
  final bool isSelected;
  final int index;
  final Function(int, bool) onSelectionChanged;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>) onDelete;
  final Function(Map<String, dynamic>)? onView;

  const _ImmunizationCard({
    required this.record,
    required this.isSelectionMode,
    required this.isSelected,
    required this.index,
    required this.onSelectionChanged,
    required this.onEdit,
    required this.onDelete,
    this.onView,
  });

  String _safe(dynamic value, [String fallback = 'N/A']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _formatDateLabel(dynamic value) {
    final raw = _safe(value, '');
    if (raw.isEmpty) return 'N/A';

    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
    }

    if (raw.contains(' ')) {
      return raw.split(' ').first;
    }

    return raw;
  }

  Color _statusColor(String status) {
    final lower = status.toLowerCase();
    if (lower.contains('overdue')) return const Color(0xFFE53935);
    if (lower.contains('adverse')) return const Color(0xFFE53935);
    if (lower.contains('completed')) return const Color(0xFF4CAF50);
    if (lower.contains('progress')) return const Color(0xFF2196F3);
    if (lower.contains('scheduled') ||
        lower.contains('pending') ||
        lower.contains('due')) {
      return const Color(0xFFFF9800);
    }
    return const Color(0xFFB8C9DB);
  }

  Color _vaccineChipColor(String vaccine) {
    final lower = vaccine.toLowerCase();
    if (lower.contains('hepatitis')) return const Color(0xFFF5D9D9);
    if (lower.contains('polio') || lower.contains('mmr')) {
      return const Color(0xFFDDE4F3);
    }
    if (lower.contains('bcg')) return const Color(0xFFDDE9D4);
    return const Color(0xFFE9D6E0);
  }

  Widget _buildDivider() {
    return Container(width: 1, height: 70, color: const Color(0xFF26476B));
  }

  Widget _buildActionButton({
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

  Widget _buildLabeledDetailLine({
    required String label,
    required String value,
    required Color labelColor,
    required Color valueColor,
    FontWeight valueWeight = FontWeight.w700,
  }) {
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              color: labelColor,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: valueColor,
              fontSize: 10.5,
              fontWeight: valueWeight,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patientName = _safe(record['patientName'], 'Unknown');
    final age = _safe(record['age']);
    final contactNumber = _safe(record['contactNumber']);
    final vaccine = _safe(record['vaccine'], 'N/A');
    final status = _safe(record['status'], 'Pending');
    final historyCount =
        int.tryParse(record['patientHistoryCount']?.toString() ?? '') ?? 1;
    final doseNumber = _safe(record['doseNumber']);
    final route = _safe(record['routeOfAdministration']);
    final brand = _safe(record['vaccineBrand']);
    final batch = _safe(record['batchNumber']);
    final nextDoseDate = _formatDateLabel(record['nextDoseDueDate']);
    final adverseEvents = _safe(record['adverseEvents'], 'None reported');
    final statusColor = _statusColor(status);
    final rowBg = _darkDeepTeal.withValues(alpha: 0.96);
    const adminLabelText = Color(0xFF60A5FA);
    const rowText = Color(0xFFF3F8FC);
    const mutedText = Color(0xFFB1C4D5);

    return GestureDetector(
      onTap: isSelectionMode
          ? () => onSelectionChanged(index, !isSelected)
          : onView == null
          ? null
          : () => onView!(record),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: rowBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? _primaryAqua.withValues(alpha: 0.85)
                : const Color(0xFF26476B),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                    Text(
                      '$age years old',
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
                      'History Entries: $historyCount',
                      style: const TextStyle(
                        color: _primaryAqua,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Contact: $contactNumber',
                      style: const TextStyle(
                        color: mutedText,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _buildDivider(),
              Expanded(
                flex: 28,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'Dose: ',
                            style: const TextStyle(
                              color: adminLabelText,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextSpan(
                            text: doseNumber,
                            style: const TextStyle(
                              color: rowText,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: '   Route: ',
                            style: const TextStyle(
                              color: adminLabelText,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextSpan(
                            text: route,
                            style: const TextStyle(
                              color: rowText,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'Brand: ',
                            style: const TextStyle(
                              color: adminLabelText,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextSpan(
                            text: brand,
                            style: const TextStyle(
                              color: rowText,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: '   Batch: ',
                            style: const TextStyle(
                              color: adminLabelText,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextSpan(
                            text: batch,
                            style: const TextStyle(
                              color: rowText,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    _buildLabeledDetailLine(
                      label: 'Next Dose',
                      value: nextDoseDate,
                      labelColor: adminLabelText,
                      valueColor: rowText,
                    ),
                    const SizedBox(height: 3),
                    _buildLabeledDetailLine(
                      label: 'Adverse Events',
                      value: adverseEvents,
                      labelColor: adminLabelText,
                      valueColor: rowText,
                      valueWeight: FontWeight.w600,
                    ),
                  ],
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
                        color: _vaccineChipColor(vaccine),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        vaccine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF163B66),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _buildDivider(),
              Expanded(
                flex: 14,
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
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (!isSelectionMode) ...[
                _buildDivider(),
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 2),
                  child: SizedBox(
                    width: 148,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildActionButton(
                          icon: Icons.history_rounded,
                          onTap: onView != null
                              ? () => onView!(record)
                              : () => onEdit(record),
                        ),
                        const SizedBox(width: 6),
                        _buildActionButton(
                          icon: Icons.edit_rounded,
                          onTap: () => onEdit(record),
                        ),
                        const SizedBox(width: 6),
                        _buildActionButton(
                          icon: Icons.picture_as_pdf_rounded,
                          onTap: () =>
                              _downloadImmunizationRecordPdf(context, record),
                        ),
                        const SizedBox(width: 6),
                        _buildActionButton(
                          icon: Icons.delete_rounded,
                          onTap: () => onDelete(record),
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

Future<void> _downloadImmunizationRecordPdf(
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
    final pdfBytes = await buildImmunizationPdfBytes(record);
    final filename = buildImmunizationPdfFilename(record);
    final downloaded = downloadFile(
      bytes: pdfBytes,
      filename: filename,
      mimeType: 'application/pdf',
    );

    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          downloaded
              ? 'PDF generated for ${record['patientName'] ?? 'this record'}.'
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
