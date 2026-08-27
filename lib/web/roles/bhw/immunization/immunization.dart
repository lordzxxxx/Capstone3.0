import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/roles/bhw/immunization/immunization_database_helper.dart';
import 'package:mycapstone_project/web/roles/bhw/immunization/immunization_insights.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/shared/components/fullscreen_detail_table_dialog.dart';
import 'package:mycapstone_project/web/shared/components/module_view_components.dart';
import 'package:mycapstone_project/web/shared/components/web_data_components.dart';
import 'package:mycapstone_project/web/shared/components/web_responsive_body.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_first_service_selector.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_identity_utils.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/shared_patient_search_panel.dart';
import 'package:mycapstone_project/web/shared/utils/file_download.dart';
import 'package:mycapstone_project/web/shared/utils/immunization_pdf.dart';
import 'package:mycapstone_project/shared/current_table_record_utils.dart';
import 'package:mycapstone_project/shared/input_validation.dart';
import 'package:mycapstone_project/web/shared/widgets/web_sync_status_badge.dart';
import 'package:mycapstone_project/shared/immunization_reference_data.dart';

const Color _primaryAqua = Color(0xFF2F80ED);
const Color _darkDeepTeal = Color(0xFF071A33);
const Color _mutedCoolGray = Color(0xFF4B6075);
const Color _lightOffWhite = Color(0xFFEBF3FC);
const Color _sidebarDark = Colors.white;
const Color _historyBackground = Color(0xFFF5F7FA);
const Color _historySurface = Colors.white;
const Color _historyAccent = Color(0xFF2563EB);
const Color _historyMuted = Color(0xFF4B6075);
const Color _historyBorder = Color(0xFFE2E8F0);

class ImmunizationPage extends StatefulWidget {
  const ImmunizationPage({super.key, this.initialPatient});

  final Map<String, dynamic>? initialPatient;

  @override
  State<ImmunizationPage> createState() => _ImmunizationPageState();
}

class _ImmunizationPageState extends State<ImmunizationPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  static const List<String> _vaccineTypeOptions = kImmunizationVaccineOptions;
  String _selectedVaccineFilter = 'All Vaccines';
  final List<String> _vaccineFilterOptions = [
    'All Vaccines',
    ..._vaccineTypeOptions,
  ];

  DateTime? _fromDate;
  DateTime? _toDate;

  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};
  final bool _isDeleteDialogShowing = false;
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
      (_) => persistHealthModuleView(WebRoutes.bhwImmunization, _activeView),
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
    persistHealthModuleView(WebRoutes.bhwImmunization, view);
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
              color: _historyBackground,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _historyBorder),
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
                    color: _historySurface,
                    border: Border(bottom: BorderSide(color: _historyBorder)),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              patientName,
                              style: const TextStyle(
                                color: _lightOffWhite,
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
                                color: _historyMuted,
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
                        tooltip: 'Close',
                        icon: const Icon(
                          Icons.close_rounded,
                          color: _historyAccent,
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
                                color: _lightOffWhite,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Review previous immunizations before adding another dose for this patient.',
                              style: TextStyle(
                                color: _historyMuted,
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
                              color: _historyMuted,
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
                                color: _historySurface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _historyBorder),
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
                                            color: _lightOffWhite,
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
                                    'AEFI / adverse events: $adverseEvents',
                                    style: TextStyle(
                                      color: _historyMuted,
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
                                        style: _historyOutlinedButtonStyle(),
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
                                        style: _historyOutlinedButtonStyle(),
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
                          style: _historyOutlinedButtonStyle(),
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
                          style: _historyPrimaryButtonStyle(),
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

  ButtonStyle _historyOutlinedButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: _historyAccent,
      side: const BorderSide(color: _historyAccent, width: 1.4),
      minimumSize: const Size.fromHeight(48),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );
  }

  ButtonStyle _historyPrimaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: _historyAccent,
      foregroundColor: Colors.white,
      elevation: 0,
      minimumSize: const Size.fromHeight(48),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
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
        color: _historySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _historyBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _historyAccent, size: 16),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: _historyMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: _historyAccent,
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
              color: _historyMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: _historyAccent,
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
      body: WebResponsiveBody(
        sidebar: WebAppSidebar(
          userName: userName,
          activeItem: WebSidebarItem.immunization,
        ),
        title: 'Immunization Management',
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: _primaryAqua),
              )
            : Stack(
                children: [
                  SingleChildScrollView(
                    child: WebPageContent(
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
            WebSearchField(
              controller: _searchController,
              hintText:
                  'Search by patient name, patient ID, vaccine type, or status...',
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _currentPage = 1;
                  _selectedIndices.clear();
                });
                _scheduleSharedPatientSearch(value);
              },
              onClear: () {
                setState(() {
                  _searchController.clear();
                  _searchQuery = '';
                  _currentPage = 1;
                  _selectedIndices.clear();
                });
                _scheduleSharedPatientSearch('');
              },
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
        color: _lightOffWhite,
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

  Widget _buildAddImmunizationButtonContainer(BuildContext context) {
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
      child: _buildAddImmunizationButton(context),
    );
  }

  // Web Header Bar

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
              WebFilterSurface(
                padding: const EdgeInsets.all(12),
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Search Bar
                      _buildSearchBar(),
                      const SizedBox(height: 16),

                      // Filters Row
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          // Vaccine Filter Dropdown
                          WebFilterDropdown<String>(
                            label: 'Vaccine',
                            value: _selectedVaccineFilter,
                            width: 360,
                            items: _vaccineFilterOptions
                                .map(
                                  (option) => DropdownMenuItem<String>(
                                    value: option,
                                    child: Text(option),
                                  ),
                                )
                                .toList(),
                            onChanged: (newValue) {
                              if (newValue == null) return;
                              setState(() {
                                _selectedVaccineFilter = newValue;
                                _currentPage = 1;
                                _selectedIndices.clear();
                              });
                            },
                          ),
                          const SizedBox(width: 16),

                          // Date Range Filter
                          SizedBox(
                            width: 420,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: _primaryAqua.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _primaryAqua.withValues(alpha: 0.25),
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
                          SizedBox(
                            width: 180,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: _isSelectionMode
                                    ? _primaryAqua.withValues(alpha: 0.14)
                                    : _primaryAqua.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _isSelectionMode
                                      ? _primaryAqua.withValues(alpha: 0.55)
                                      : _primaryAqua.withValues(alpha: 0.25),
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
                                        color: _primaryAqua,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _isSelectionMode
                                              ? 'Active'
                                              : 'Select',
                                          style: TextStyle(
                                            color: _isSelectionMode
                                                ? _primaryAqua
                                                : _darkDeepTeal,
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
                      WebTableSurface(
                        minWidth: 1180,
                        child: Column(
                          children: [
                            _buildImmunizationCardHeader(),
                            _immunizationTable(
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
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text(
                                          'Delete',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  try {
                                    await _dbHelper.deleteRecord(record['id']);
                                    await _loadRecords();
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Failed to delete immunization record: $e',
                                        ),
                                        backgroundColor: Colors.red,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                }
                              },
                              onView: (record) {
                                _showPatientImmunizationHistory(
                                  context,
                                  record,
                                );
                              },
                            ),
                          ],
                        ),
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
  Widget _immunizationTable({
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
        color: Colors.white,
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
              color: _mutedCoolGray,
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
                style: const TextStyle(color: _lightOffWhite, fontSize: 12),
                icon: const Icon(
                  Icons.arrow_drop_down,
                  color: _mutedCoolGray,
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
              color: _lightOffWhite,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            onPressed: canGoNext
                ? () => setState(() => _currentPage = currentPage + 1)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
            color: canGoNext ? _primaryAqua : const Color(0xFFB8C9DB),
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
        vaccineMatch =
            _normalizeVaccineType(record['vaccine']) == _selectedVaccineFilter;
      }

      // Date range filter
      bool dateMatch = true;
      if (_fromDate != null || _toDate != null) {
        final recordDate = DateTime.tryParse(record['date']?.toString() ?? '');
        if (recordDate == null) {
          dateMatch = false;
        } else {
          if (_fromDate != null && recordDate.isBefore(_fromDate!)) {
            dateMatch = false;
          }
          if (_toDate != null && recordDate.isAfter(_toDate!)) {
            dateMatch = false;
          }
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
      'pentavalent': 'Pentavalent Vaccine',
      'pentavalent vaccine': 'Pentavalent Vaccine',
      'penta': 'Pentavalent Vaccine',
      'opv': 'OPV',
      'oral polio vaccine': 'OPV',
      'oral polio vaccine (opv)': 'OPV',
      'ipv': 'IPV',
      'inactivated polio vaccine': 'IPV',
      'inactivated polio vaccine (ipv)': 'IPV',
      'pcv': 'PCV',
      'pneumococcal conjugate vaccine': 'PCV',
      'pneumococcal conjugate vaccine (pcv)': 'PCV',
      'hepatitis a': 'Hepatitis A',
      'hepa': 'Hepatitis A',
      'mr': 'MR Vaccine',
      'mr vaccine': 'MR Vaccine',
      'japanese encephalitis': 'Japanese Encephalitis (JE)',
      'je': 'Japanese Encephalitis (JE)',
      'td': 'Tetanus-Diphtheria (Td)',
      'hpv': 'HPV Vaccine',
      'ppv': 'Pneumococcal Polysaccharide Vaccine (PPV)',
      'rotavirus': 'Rotavirus Vaccine',
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

    // Preserve a legacy/custom value while editing so opening a record never
    // silently changes its stored vaccine.
    return value;
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

  Future<void> _showNewImmunizationModal(
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
      if (!context.mounted || patientSeed == null) return;
    }
    // Controllers
    final firstNameController = TextEditingController();
    final surnameController = TextEditingController();
    final patientIdController = TextEditingController();
    final ageController = TextEditingController();
    final contactNumberController = TextEditingController();

    final name = patientNameParts(patientSeed);
    firstNameController.text = name.firstName;
    surnameController.text = name.surname;
    patientIdController.text = (patientSeed['patientId'] ?? '').toString();
    ageController.text = (patientSeed['age'] ?? '').toString();
    contactNumberController.text = (patientSeed['contactNumber'] ?? '')
        .toString();

    String selectedVaccineType = _normalizeVaccineType(patientSeed['vaccine']);
    final vaccineBrandController = TextEditingController();
    final batchNumberController = TextEditingController();
    DateTime? expirationDate;

    DateTime? administrationDate = DateTime.now();
    TimeOfDay? administrationTime = TimeOfDay.now();
    bool isSaving = false;
    final doseNumberController = TextEditingController();
    String selectedRouteOfAdministration = 'Intramuscular (IM)';
    String selectedInjectionSite = 'Left Upper Arm';
    final administeredByController = TextEditingController();
    final adverseEventsController = TextEditingController();
    DateTime? nextDoseDueDate;
    final modalTitle = 'Add Another Immunization';
    final formKey = GlobalKey<FormState>();

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
                    color: _sidebarDark,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    child: Form(
                      key: formKey,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 900;

                          final patientDetailsCard = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(
                                'Patient Details',
                                Icons.person,
                              ),
                              _buildFormCard([
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: firstNameController,
                                        label: 'First Name',
                                        icon: Icons.person_outline,
                                        hintText: 'Enter first name',
                                        validator: (value) =>
                                            value == null || value.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: surnameController,
                                        label: 'Surname',
                                        icon: Icons.person,
                                        hintText: 'Enter surname',
                                        validator: (value) =>
                                            value == null || value.isEmpty
                                            ? 'Required'
                                            : null,
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
                            ],
                          );

                          final vaccineDetailsCard = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                                  label: 'Vaccine Brand / Manufacturer',
                                  icon: Icons.business,
                                  hintText: 'e.g., Pfizer, AstraZeneca',
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: batchNumberController,
                                  label: 'Batch / Lot Number',
                                  icon: Icons.qr_code,
                                  hintText: 'e.g., LOT-2026-X123',
                                ),
                                const SizedBox(height: 16),
                                _buildModalDatePickerField(
                                  context: context,
                                  label: 'Expiration Date',
                                  date: expirationDate,
                                  icon: Icons.event,
                                  onTap: () async {
                                    final picked = await _showModalDatePicker(
                                      context,
                                    );
                                    if (picked != null) {
                                      setModalState(
                                        () => expirationDate = picked,
                                      );
                                    }
                                  },
                                ),
                              ]),
                            ],
                          );

                          final adminDetailsCard = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                                          final picked =
                                              await _showModalDatePicker(
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
                                                administrationTime ??
                                                TimeOfDay.now(),
                                            builder: (context, child) {
                                              return Theme(
                                                data: Theme.of(context)
                                                    .copyWith(
                                                      colorScheme:
                                                          ColorScheme.light(
                                                            primary:
                                                                _primaryAqua,
                                                            onPrimary:
                                                                Colors.white,
                                                            onSurface:
                                                                _darkDeepTeal,
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
                                        () => selectedRouteOfAdministration =
                                            value,
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
                                  validator: (value) =>
                                      value == null || value.isEmpty
                                      ? 'Required'
                                      : null,
                                ),
                              ]),
                            ],
                          );

                          final postAdminCard = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(
                                'Post-Administration & Follow-up',
                                Icons.event_available,
                              ),
                              _buildFormCard([
                                _buildTextField(
                                  controller: adverseEventsController,
                                  label:
                                      'Adverse Events Following Immunization (AEFI)',
                                  icon: Icons.warning,
                                  hintText:
                                      'Note any adverse reactions or events',
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
                                      setModalState(
                                        () => nextDoseDueDate = picked,
                                      );
                                    }
                                  },
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
                                      patientDetailsCard,
                                      const SizedBox(height: 16),
                                      vaccineDetailsCard,
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      adminDetailsCard,
                                      const SizedBox(height: 16),
                                      postAdminCard,
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              patientDetailsCard,
                              const SizedBox(height: 16),
                              vaccineDetailsCard,
                              const SizedBox(height: 16),
                              adminDetailsCard,
                              const SizedBox(height: 16),
                              postAdminCard,
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
                            : const Icon(Icons.save_rounded, size: 18),
                        label: Text(
                          isSaving ? 'Saving...' : 'Save Immunization Record',
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
                                if (!isFormValid) {
                                  return;
                                }
                                if (selectedVaccineType.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Vaccine type is required'),
                                      backgroundColor: Colors.red,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  return;
                                }
                                if (administrationDate == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Administration date is required',
                                      ),
                                      backgroundColor: Colors.red,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  return;
                                }

                                setModalState(() => isSaving = true);

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
                                  'status': 'Completed',
                                  'date':
                                      administrationDate?.toIso8601String() ??
                                      '',
                                };

                                // Save to database (offline + Firebase sync)
                                try {
                                  await _dbHelper.insertRecord(newRecord);
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Failed to save immunization record: $e',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      backgroundColor: Colors.red,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  setModalState(() => isSaving = false);
                                  return;
                                }

                                // Reload records
                                await _loadRecords();

                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
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
        children: children,
      ),
    );
  }

  String? _defaultTextFieldValidator(String label, String? value) {
    final normalizedLabel = label.toLowerCase();
    if (normalizedLabel == 'age') {
      return InputValidation.age(value);
    }
    if (normalizedLabel.contains('contact')) {
      return InputValidation.phone(value);
    }
    if (normalizedLabel.contains('vaccine brand')) {
      return InputValidation.optionalText(value, label: label, maxLength: 120);
    }
    if (normalizedLabel.contains('batch')) {
      return InputValidation.optionalText(value, label: label, maxLength: 80);
    }
    if (normalizedLabel.contains('dose')) {
      return InputValidation.dose(value);
    }
    if (normalizedLabel.contains('adverse')) {
      return InputValidation.optionalText(value, label: label, maxLength: 2000);
    }
    return null;
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
    final effectiveValidator =
        validator ?? ((value) => _defaultTextFieldValidator(label, value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _lightOffWhite,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: (value) => effectiveValidator(value?.trim()),
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
              horizontal: 14,
              vertical: 10,
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
    final dropdownItems = [...sanitizedItems];
    final preservedValue = value?.trim();
    if (preservedValue != null &&
        preservedValue.isNotEmpty &&
        !dropdownItems.contains(preservedValue)) {
      dropdownItems.insert(0, preservedValue);
    }
    final safeValue = dropdownItems.contains(preservedValue)
        ? preservedValue
        : (dropdownItems.isNotEmpty ? dropdownItems.first : null);

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
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _primaryAqua.withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: _primaryAqua, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: safeValue,
                    isExpanded: true,
                    icon: Icon(Icons.arrow_drop_down, color: _mutedCoolGray),
                    style: TextStyle(
                      color: _lightOffWhite,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    dropdownColor: Colors.white,
                    items: dropdownItems.map((String item) {
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
                ),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _primaryAqua.withValues(alpha: 0.3),
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
                  color: date != null ? _darkDeepTeal : _mutedCoolGray,
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
          label: 'Adverse Events Following Immunization (AEFI)',
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
    bool isSaving = false;

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

    final formKey = GlobalKey<FormState>();

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
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _primaryAqua,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: 'Close',
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
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Patient Details
                            _buildSectionHeader(
                              'Patient Details',
                              Icons.person,
                            ),
                            _buildFormCard([
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildTextField(
                                      controller: firstNameController,
                                      label: 'First Name',
                                      icon: Icons.person_outline,
                                      hintText: 'Enter first name',
                                      validator: (value) =>
                                          value == null || value.isEmpty
                                          ? 'Required'
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildTextField(
                                      controller: surnameController,
                                      label: 'Surname',
                                      icon: Icons.person,
                                      hintText: 'Enter surname',
                                      validator: (value) =>
                                          value == null || value.isEmpty
                                          ? 'Required'
                                          : null,
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
                            const SizedBox(height: 14),

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
                                    setModalState(
                                      () => expirationDate = picked,
                                    );
                                  }
                                },
                              ),
                            ]),
                            const SizedBox(height: 14),

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
                                      () =>
                                          selectedRouteOfAdministration = value,
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
                                validator: (value) =>
                                    value == null || value.isEmpty
                                    ? 'Required'
                                    : null,
                              ),
                            ]),
                            const SizedBox(height: 14),

                            // Additional Information
                            _buildSectionHeader(
                              'Additional Information',
                              Icons.info_outline,
                            ),
                            _buildFormCard([
                              _buildTextField(
                                controller: adverseEventsController,
                                label:
                                    'Adverse Events Following Immunization (AEFI)',
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
                                    setModalState(
                                      () => nextDoseDueDate = picked,
                                    );
                                  }
                                },
                              ),
                            ]),
                            const SizedBox(height: 14),

                            // Save Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: isSaving
                                    ? null
                                    : () async {
                                        final isFormValid =
                                            formKey.currentState?.validate() ??
                                            false;
                                        if (!isFormValid) {
                                          return;
                                        }
                                        if (selectedVaccineType.isEmpty) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Vaccine type is required',
                                              ),
                                              backgroundColor: Colors.red,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                          return;
                                        }
                                        if (administrationDate == null) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Administration date is required',
                                              ),
                                              backgroundColor: Colors.red,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                          return;
                                        }

                                        setModalState(() => isSaving = true);

                                        // Update immunization record
                                        final updatedRecord = {
                                          'time':
                                              '${administrationTime?.hour.toString().padLeft(2, '0')}:${administrationTime?.minute.toString().padLeft(2, '0')}',
                                          'patientName':
                                              '${firstNameController.text} ${surnameController.text}'
                                                  .trim(),
                                          'patientId': patientIdController.text,
                                          'age': ageController.text,
                                          'contactNumber':
                                              contactNumberController.text,
                                          'vaccine': selectedVaccineType,
                                          'vaccineBrand':
                                              vaccineBrandController.text,
                                          'batchNumber':
                                              batchNumberController.text,
                                          'expirationDate':
                                              expirationDate
                                                  ?.toIso8601String() ??
                                              '',
                                          'administrationDate':
                                              administrationDate
                                                  ?.toIso8601String() ??
                                              '',
                                          'administrationTime':
                                              '${administrationTime?.hour.toString().padLeft(2, '0')}:${administrationTime?.minute.toString().padLeft(2, '0')}',
                                          'doseNumber':
                                              doseNumberController.text,
                                          'routeOfAdministration':
                                              selectedRouteOfAdministration,
                                          'injectionSite':
                                              selectedInjectionSite,
                                          'administeredBy':
                                              administeredByController.text,
                                          'adverseEvents':
                                              adverseEventsController.text,
                                          'nextDoseDueDate':
                                              nextDoseDueDate
                                                  ?.toIso8601String() ??
                                              '',
                                          'status':
                                              record['status'] ?? 'Completed',
                                          'date':
                                              administrationDate
                                                  ?.toIso8601String() ??
                                              '',
                                        };

                                        // Update in database
                                        final id =
                                            record['id']?.toString() ?? '';
                                        if (id.isNotEmpty) {
                                          try {
                                            await _dbHelper.updateRecord(
                                              id,
                                              updatedRecord,
                                            );
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Failed to update immunization record: $e',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                backgroundColor: Colors.red,
                                                behavior:
                                                    SnackBarBehavior.floating,
                                              ),
                                            );
                                            setModalState(
                                              () => isSaving = false,
                                            );
                                            return;
                                          }
                                        }

                                        // Reload records
                                        await _loadRecords();
                                        if (!context.mounted) return;

                                        Navigator.pop(context);
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
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
                                child: isSaving
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
                                    : const Text(
                                        'Update Immunization Record',
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

  Future<void> _deleteSelectedRecords() async {
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

    // Delete from database, tracking which ids actually succeeded
    final succeededIds = await _dbHelper.deleteRecords(idsToDelete);
    final failedCount = idsToDelete.length - succeededIds.length;
    if (!mounted) return;

    // Remove only the records that were actually deleted
    setState(() {
      _immunizationRecords.removeWhere(
        (record) => succeededIds.contains(record['id']),
      );
      _selectedIndices.clear();
      _isSelectionMode = false;
    });

    if (failedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Successfully deleted ${succeededIds.length} record(s)',
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
            'Deleted ${succeededIds.length} of ${idsToDelete.length} record(s); $failedCount failed',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: succeededIds.isEmpty ? Colors.red : Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
    final patientName = _safe(
      record['patientName'] ?? record['patient'] ?? record['name'],
      'Unknown Patient',
    );
    final age = _safe(record['age'], 'N/A');
    final patientId = _safe(
      record['patientId'] ?? record['id'] ?? record['linkedPatientId'],
      '-',
    );
    final vaccine = _safe(
      record['vaccine'] ?? record['vaccineType'] ?? record['vaccineName'],
      'N/A',
    );
    final status = _safe(record['status'], 'Completed');
    final doseNumber = _safe(record['doseNumber'] ?? record['dose'], '1');
    final route = _safe(
      record['routeOfAdministration'] ?? record['route'],
      'Intramuscular',
    );
    final brand = _safe(record['vaccineBrand'] ?? record['brand'], 'Standard');
    final batch = _safe(record['batchNumber'] ?? record['batch'], 'N/A');
    final adminDate = _formatDateLabel(
      record['administrationDate'] ??
          record['date'] ??
          record['createdAt'] ??
          record['timestamp'],
    );
    final nextDoseDate = _formatDateLabel(record['nextDoseDueDate']);
    final adverseEvents = _safe(record['adverseEvents'], 'None reported');
    final statusColor = _statusColor(status);
    const rowBg = Colors.white;
    const adminLabelText = Color(0xFF2F80ED);
    const rowText = Color(0xFF0B1F3A);
    const mutedText = Color(0xFF546E7A);

    return GestureDetector(
      onTap: isSelectionMode
          ? () => onSelectionChanged(index, !isSelected)
          : onView == null
          ? null
          : () => onView!(record),
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
                    if (patientId != '-') ...[
                      const SizedBox(height: 3),
                      Text(
                        'ID: $patientId',
                        style: const TextStyle(
                          color: _primaryAqua,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      'Admin Date: $adminDate',
                      style: const TextStyle(
                        color: mutedText,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    WebSyncStatusBadge(record: record),
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
                          const TextSpan(
                            text: 'Dose: ',
                            style: TextStyle(
                              color: adminLabelText,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
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
                          const TextSpan(
                            text: '   Route: ',
                            style: TextStyle(
                              color: adminLabelText,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
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
                          const TextSpan(
                            text: 'Brand: ',
                            style: TextStyle(
                              color: adminLabelText,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
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
                          const TextSpan(
                            text: '   Batch: ',
                            style: TextStyle(
                              color: adminLabelText,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
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
                      label: 'Adverse Events Following Immunization (AEFI)',
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
