import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
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
import 'package:mycapstone_project/shared/immunization_record_utils.dart';

const Color _primaryAqua = AppColors.primary;
const Color _darkDeepTeal = AppColors.backgroundDark;
const Color _mutedCoolGray = AppColors.textSecondary;
const Color _lightOffWhite = AppColors.textPrimary;
const Color _sidebarDark = AppColors.surfaceLight;
const Color _historyBackground = AppColors.backgroundLight;
const Color _historySurface = AppColors.surfaceLight;
const Color _historyAccent = AppColors.primary;
const Color _historyMuted = AppColors.textSecondary;
const Color _historyBorder = AppColors.border;

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
    return immunizationPatientKey(record);
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

  Future<bool> _confirmPotentialDuplicate(
    BuildContext context,
    Map<String, dynamic> candidate, {
    String? excludeId,
  }) async {
    final hasDuplicate = _immunizationRecords.any(
      (record) => immunizationLooksLikeDuplicate(
        record,
        candidate,
        excludeId: excludeId,
      ),
    );
    if (!hasDuplicate || !context.mounted) return true;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Possible duplicate immunization'),
        content: const Text(
          'This patient already has the same vaccine and dose recorded on this date. Review the history before continuing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Review history'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue anyway'),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  Map<String, dynamic> _buildDisplayRecord(Map<String, dynamic> record) {
    return {
      ...record,
      'patientHistoryCount': _getPatientHistoryRecords(record).length,
    };
  }

  Future<void> _showPatientImmunizationHistory(
    BuildContext context,
    Map<String, dynamic> seedRecord,
  ) async {
    final resolvedPatient = await _patientHistoryService
        .resolveRegisteredPatient(seedRecord);
    if (!context.mounted) return;

    final history = _getPatientHistoryRecords(seedRecord);
    final latestRecord = history.isNotEmpty ? history.first : seedRecord;
    final patientProfile = <String, dynamic>{
      ...latestRecord,
      if (resolvedPatient != null) ...resolvedPatient,
    };
    final patientName = immunizationRecordText(patientProfile, const [
      'fullName',
      'patientName',
      'name',
    ], fallback: 'Unknown Patient');
    final patientId = immunizationRecordText(patientProfile, const [
      'patientId',
      'linkedPatientId',
      'id',
    ]);
    final isPediatric = immunizationPatientIsPediatric(patientProfile);
    final parentGuardian = isPediatric
        ? immunizationRecordText(patientProfile, const [
            'guardian',
            'parentGuardianName',
          ])
        : '';
    final profileItems = <String, String>{
      'Date of Birth': immunizationRecordText(patientProfile, const [
        'dateOfBirth',
        'dob',
      ]),
      'Sex': immunizationRecordText(patientProfile, const ['sex', 'gender']),
      'Contact': immunizationRecordText(patientProfile, const [
        'contactNumber',
        'phoneNumber',
        'phone',
      ]),
      'Address': immunizationRecordText(patientProfile, const [
        'address',
        'street',
        'fullAddress',
      ]),
      'Barangay': immunizationRecordText(patientProfile, const [
        'barangay',
        'barangayName',
      ]),
    }..removeWhere((_, value) => value.isEmpty);
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
                  color: AppColors.secondary.withValues(alpha: 0.35),
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
                            if (parentGuardian.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Parent/Guardian: $parentGuardian',
                                style: TextStyle(
                                  color: _historyMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            if (profileItems.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 14,
                                runSpacing: 6,
                                children: profileItems.entries
                                    .map(
                                      (entry) => Text(
                                        '${entry.key}: ${entry.value}',
                                        style: TextStyle(
                                          color: _historyMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
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
      backgroundColor: AppColors.backgroundLight,
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
                          else ...[
                            _buildVaccineMasterTable(),
                            const SizedBox(height: 18),
                            _buildImmunizationTable(),
                          ],
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
  Widget _buildVaccineMasterTable() {
    final vaccines = kImmunizationVaccineMaster
        .where((vaccine) => vaccine.active)
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 680.0;
        final tableWidth = math.max(availableWidth, 620.0);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: _historySurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _historyBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.vaccines_outlined,
                    color: _primaryAqua,
                    size: 21,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Vaccine List / Master Table',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _darkDeepTeal,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Chip(
                    label: Text('${vaccines.length} active'),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    backgroundColor: _primaryAqua.withValues(alpha: 0.10),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Authoritative vaccine reference used by immunization entry and patient records. Select the vaccine name exactly as listed.',
                style: TextStyle(color: _mutedCoolGray, height: 1.25),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: DataTable(
                    headingRowHeight: 36,
                    dataRowMinHeight: 38,
                    dataRowMaxHeight: 44,
                    horizontalMargin: 10,
                    columnSpacing: availableWidth < 680 ? 18 : 28,
                    dividerThickness: 0.5,
                    headingRowColor: WidgetStatePropertyAll(
                      _primaryAqua.withValues(alpha: 0.08),
                    ),
                    headingTextStyle: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(
                          color: _darkDeepTeal,
                          fontWeight: FontWeight.w800,
                        ),
                    dataTextStyle: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: _darkDeepTeal),
                    columns: const [
                      DataColumn(label: Text('Vaccine')),
                      DataColumn(label: Text('Code')),
                      DataColumn(label: Text('Dose reference')),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: vaccines
                        .map(
                          (vaccine) => DataRow(
                            cells: [
                              DataCell(Text(vaccine.name)),
                              DataCell(Text(vaccine.code)),
                              DataCell(Text(vaccine.doseSequence)),
                              const DataCell(Text('Active')),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

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
          color: AppColors.primary.withValues(alpha: 0.55),
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
                                          color: AppColors.error,
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
                      Column(
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
                                        style: TextStyle(
                                          color: AppColors.error,
                                        ),
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
                                      backgroundColor: AppColors.error,
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
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white.withValues(alpha: 0.2),
    );
  }

  Widget _buildImmunizationCardHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.secondary,
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
              width: 156,
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
            color: canGoNext ? _primaryAqua : AppColors.borderStrong,
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
                      backgroundColor: AppColors.primary,
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
                      backgroundColor: AppColors.error,
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
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
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
      return '';
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
    final selectedPatient = patientSeed;
    final patientIdentity = immunizationIdentitySnapshot(
      patient: selectedPatient,
    );
    final isPediatricPatient = immunizationPatientIsPediatric(selectedPatient);
    // Controllers
    final firstNameController = TextEditingController();
    final middleNameController = TextEditingController();
    final surnameController = TextEditingController();
    final patientIdController = TextEditingController();
    final ageController = TextEditingController();
    final contactNumberController = TextEditingController();
    final guardianController = TextEditingController();

    final name = patientNameParts(selectedPatient);
    firstNameController.text = name.firstName;
    middleNameController.text = name.middleName;
    surnameController.text = name.surname;
    patientIdController.text = (patientIdentity['patientId'] ?? '').toString();
    ageController.text = (patientIdentity['age'] ?? '').toString();
    contactNumberController.text = (patientIdentity['contactNumber'] ?? '')
        .toString();
    guardianController.text = (patientIdentity['parentGuardianName'] ?? '')
        .toString();

    String selectedVaccineType = _normalizeVaccineType(
      selectedPatient['vaccine'],
    );
    final vaccineBrandController = TextEditingController();
    final batchNumberController = TextEditingController();
    DateTime? expirationDate;

    DateTime? administrationDate = DateTime.now();
    TimeOfDay? administrationTime = TimeOfDay.now();
    bool isSaving = false;
    String selectedDose = 'Initial';
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
              color: _historyBackground,
              border: Border.all(color: _historyBorder, width: 1.2),
            ),
            child: Column(
              children: [
                // Modal Header
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
                            Text(
                              'Vaccine administration and follow-up planning',
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
                                        readOnly: true,
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
                                        readOnly: true,
                                        validator: (value) =>
                                            value == null || value.isEmpty
                                            ? 'Required'
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: middleNameController,
                                  label: 'Middle Name',
                                  icon: Icons.person_outline,
                                  hintText: 'Optional middle name',
                                  readOnly: true,
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
                                        readOnly: true,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: ageController,
                                        label: 'Age',
                                        icon: Icons.cake,
                                        hintText: 'Enter age',
                                        readOnly: true,
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
                                  readOnly: true,
                                  keyboardType: TextInputType.phone,
                                ),
                                if (isPediatricPatient) ...[
                                  const SizedBox(height: 16),
                                  _buildTextField(
                                    controller: guardianController,
                                    label: 'Parent/Guardian Name',
                                    icon: Icons.family_restroom,
                                    hintText:
                                        'For children or dependent patients',
                                    readOnly: true,
                                  ),
                                ],
                              ]),
                              const SizedBox(height: 12),
                              _buildPatientProfileReference(
                                selectedPatient,
                                isPediatric: isPediatricPatient,
                              ),
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
                                  allowEmpty: true,
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
                                _buildDropdownField(
                                  label: 'Dose Number',
                                  icon: Icons.format_list_numbered,
                                  value: selectedDose,
                                  items: immunizationDoseOptions(
                                    existing: selectedDose,
                                  ),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setModalState(() => selectedDose = value);
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildDropdownField(
                                  label: 'Route of Administration',
                                  value: selectedRouteOfAdministration,
                                  icon: Icons.medical_information,
                                  items: kImmunizationRouteOptions,
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
                                  items: kImmunizationSiteOptions,
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
                        color: AppColors.secondary.withValues(alpha: 0.08),
                        width: 1,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.secondary.withValues(alpha: 0.03),
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
                            color: AppColors.secondary.withValues(alpha: 0.18),
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
                                      backgroundColor: AppColors.error,
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
                                      backgroundColor: AppColors.error,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  return;
                                }
                                final canonicalPatientId =
                                    (patientIdentity['patientId'] ?? '')
                                        .toString()
                                        .trim();
                                if (canonicalPatientId.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Select a registered patient before saving.',
                                      ),
                                      backgroundColor: AppColors.error,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  return;
                                }
                                final shouldContinue =
                                    await _confirmPotentialDuplicate(context, {
                                      'patientId': canonicalPatientId,
                                      'vaccine': selectedVaccineType,
                                      'doseNumber': selectedDose,
                                      'administrationDate': administrationDate!
                                          .toIso8601String(),
                                    });
                                if (!shouldContinue || !context.mounted) {
                                  return;
                                }

                                setModalState(() => isSaving = true);

                                // Create new immunization record
                                final newRecord = {
                                  'time':
                                      '${administrationTime?.hour.toString().padLeft(2, '0')}:${administrationTime?.minute.toString().padLeft(2, '0')}',
                                  'patientName':
                                      [
                                            firstNameController.text.trim(),
                                            middleNameController.text.trim(),
                                            surnameController.text.trim(),
                                          ]
                                          .where((value) => value.isNotEmpty)
                                          .join(' '),
                                  'patientId': canonicalPatientId,
                                  'linkedPatientId':
                                      (patientIdentity['linkedPatientId'] ??
                                              canonicalPatientId)
                                          .toString(),
                                  'firstName': firstNameController.text.trim(),
                                  'middleName': middleNameController.text
                                      .trim(),
                                  'surname': surnameController.text.trim(),
                                  if (isPediatricPatient)
                                    'parentGuardianName':
                                        patientIdentity['parentGuardianName'] ??
                                        '',
                                  'age': patientIdentity['age'] ?? '',
                                  'contactNumber':
                                      patientIdentity['contactNumber'] ?? '',
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
                                  'doseNumber': selectedDose,
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
                                      backgroundColor: AppColors.error,
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
                                      backgroundColor: AppColors.success,
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
            colorScheme: ColorScheme.light(
              primary: _primaryAqua,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: _lightOffWhite,
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
        color: _sidebarDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.16),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: 0.04),
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

  Widget _buildPatientProfileReference(
    Map<String, dynamic> patient, {
    required bool isPediatric,
  }) {
    final fields = <String, String>{
      'Date of Birth': immunizationRecordText(patient, const [
        'dateOfBirth',
        'dob',
      ]),
      'Sex': immunizationRecordText(patient, const ['sex', 'gender']),
      'Blood Type': immunizationRecordText(patient, const ['bloodType']),
      'Address': immunizationRecordText(patient, const [
        'address',
        'street',
        'fullAddress',
      ]),
      'Barangay': immunizationRecordText(patient, const [
        'barangay',
        'barangayName',
      ]),
    }..removeWhere((_, value) => value.isEmpty);
    if (isPediatric) {
      final guardian = immunizationRecordText(patient, const [
        'guardian',
        'parentGuardianName',
      ]);
      if (guardian.isNotEmpty) fields['Parent/Guardian'] = guardian;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: fields.isEmpty
          ? const Text(
              'Additional patient information is not recorded.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          : Wrap(
              spacing: 16,
              runSpacing: 8,
              children: fields.entries
                  .map(
                    (entry) => Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${entry.key}: ',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: entry.value,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
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
    bool readOnly = false,
    String? Function(String?)? validator,
  }) {
    final effectiveValidator =
        validator ?? ((value) => _defaultTextFieldValidator(label, value));
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
          readOnly: readOnly,
          validator: (value) => effectiveValidator(value?.trim()),
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
            fillColor: readOnly ? AppColors.surfaceSubtle : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _primaryAqua, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.error, width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.error, width: 2),
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
                    : AppColors.border,
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
                        ? '${date.day}/${date.month}/${date.year}'
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
                color: time != null
                    ? _primaryAqua.withValues(alpha: 0.5)
                    : AppColors.border,
                width: time != null ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: _primaryAqua, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    time != null ? time.format(context) : 'Select Time',
                    style: TextStyle(
                      color: time != null
                          ? _lightOffWhite
                          : _mutedCoolGray.withValues(alpha: 0.6),
                      fontSize: 14,
                      fontWeight: time != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (time != null)
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

  Widget _buildModalTimePickerField({
    required BuildContext context,
    required String label,
    required TimeOfDay? time,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return _buildTimePickerField(
      context: context,
      label: label,
      time: time,
      icon: icon,
      onTap: onTap,
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
    bool allowEmpty = false,
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
        : (allowEmpty
              ? null
              : (dropdownItems.isNotEmpty ? dropdownItems.first : null));

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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1),
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
                    icon: const Icon(
                      Icons.arrow_drop_down_rounded,
                      color: _primaryAqua,
                    ),
                    style: const TextStyle(
                      color: _lightOffWhite,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    dropdownColor: Colors.white,
                    hint: allowEmpty
                        ? Text(
                            'Select $label',
                            style: TextStyle(
                              color: _mutedCoolGray.withValues(alpha: 0.7),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        : null,
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
        statusColor = AppColors.success;
        break;
      case 'Scheduled':
        statusColor = AppColors.warning;
        break;
      case 'In Progress':
        statusColor = AppColors.primary;
        break;
      default:
        statusColor = AppColors.borderStrong;
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

  Future<void> _showImmunizationDetails(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    final resolvedPatient = await _patientHistoryService
        .resolveRegisteredPatient(record);
    if (!context.mounted) return;
    final patientProfile = <String, dynamic>{
      ...record,
      if (resolvedPatient != null) ...resolvedPatient,
    };
    final isPediatric = immunizationPatientIsPediatric(patientProfile);
    final patientName = _safeImmunizationDetailText(
      immunizationRecordText(patientProfile, const [
        'fullName',
        'patientName',
        'name',
      ]),
      fallback: 'Unknown Patient',
    );
    final patientId = _safeImmunizationDetailText(
      immunizationRecordText(patientProfile, const [
        'patientId',
        'linkedPatientId',
        'id',
      ]),
    );
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
          value: _safeImmunizationDetailText(patientProfile['age']),
        ),
        DetailTableItem(
          icon: Icons.phone_outlined,
          label: 'Contact Number',
          value: _safeImmunizationDetailText(
            immunizationRecordText(patientProfile, const [
              'contactNumber',
              'phoneNumber',
              'phone',
            ]),
          ),
        ),
        DetailTableItem(
          icon: Icons.calendar_month_outlined,
          label: 'Date of Birth',
          value: _safeImmunizationDetailText(
            immunizationRecordText(patientProfile, const [
              'dateOfBirth',
              'dob',
            ]),
          ),
        ),
        DetailTableItem(
          icon: Icons.wc_outlined,
          label: 'Sex',
          value: _safeImmunizationDetailText(
            immunizationRecordText(patientProfile, const ['sex', 'gender']),
          ),
        ),
        DetailTableItem(
          icon: Icons.home_outlined,
          label: 'Address',
          value: _safeImmunizationDetailText(
            immunizationRecordText(patientProfile, const [
              'address',
              'street',
              'fullAddress',
            ]),
          ),
        ),
        DetailTableItem(
          icon: Icons.location_city_outlined,
          label: 'Barangay',
          value: _safeImmunizationDetailText(
            immunizationRecordText(patientProfile, const [
              'barangay',
              'barangayName',
            ]),
          ),
        ),
        if (isPediatric)
          DetailTableItem(
            icon: Icons.family_restroom_outlined,
            label: 'Parent/Guardian Name',
            value: _safeImmunizationDetailText(
              immunizationRecordText(patientProfile, const [
                'guardian',
                'parentGuardianName',
              ]),
            ),
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

  Future<void> _showEditDialog(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    final resolvedPatient = await _patientHistoryService
        .resolveRegisteredPatient(record);
    if (!context.mounted) return;
    // Preserve values already stored on the immunization while allowing
    // non-empty fields from the registered patient to fill or correct them.
    final identity = <String, dynamic>{...record};
    for (final key in const [
      'id',
      'patientId',
      'linkedPatientId',
      'fullName',
      'patientName',
      'firstName',
      'middleName',
      'surname',
      'age',
      'contactNumber',
      'phoneNumber',
      'guardian',
      'parentGuardianName',
    ]) {
      final value = resolvedPatient?[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        identity[key] = value;
      }
    }
    final name = patientNameParts(identity);
    final isPediatricPatient = immunizationPatientIsPediatric(
      resolvedPatient ?? identity,
    );

    String firstNonEmpty(Iterable<dynamic> values) {
      for (final value in values) {
        final text = value?.toString().trim() ?? '';
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    // Pre-fill controllers with existing data
    final firstNameController = TextEditingController(text: name.firstName);
    final middleNameController = TextEditingController(text: name.middleName);
    final surnameController = TextEditingController(text: name.surname);
    final canonicalPatientId = firstNonEmpty([
      resolvedPatient?['patientId'],
      resolvedPatient?['id'],
      record['patientId'],
      record['linkedPatientId'],
    ]);
    final canonicalLinkedPatientId = firstNonEmpty([
      resolvedPatient?['patientId'],
      resolvedPatient?['id'],
      record['linkedPatientId'],
      record['patientId'],
    ]);
    final patientIdController = TextEditingController(text: canonicalPatientId);
    final ageController = TextEditingController(
      text: firstNonEmpty([record['age'], resolvedPatient?['age']]),
    );
    final contactNumberController = TextEditingController(
      text: firstNonEmpty([
        record['contactNumber'],
        resolvedPatient?['contactNumber'],
        resolvedPatient?['phoneNumber'],
      ]),
    );
    final guardianController = TextEditingController(
      text:
          record['parentGuardianName'] ??
          identity['guardian'] ??
          identity['parentGuardianName'] ??
          '',
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

    String selectedDose = firstNonEmpty([record['doseNumber'], record['dose']]);
    if (selectedDose.isEmpty) selectedDose = 'Initial';
    String selectedRouteOfAdministration =
        (record['routeOfAdministration'] ?? 'Intramuscular (IM)').toString();
    String selectedInjectionSite = (record['injectionSite'] ?? 'Left Upper Arm')
        .toString();
    final administeredByController = TextEditingController(
      text: (record['administeredBy'] ?? '').toString(),
    );
    final adverseEventsController = TextEditingController(
      text: (record['adverseEvents'] ?? '').toString(),
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
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Container(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          color: _historyBackground,
          child: Column(
            children: [
              // Modal Header
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
                            'Edit Immunization Record',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Update vaccine administration and follow-up details',
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

              // Form Content
              Expanded(
                child: StatefulBuilder(
                  builder: (context, setModalState) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
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
                                      readOnly: true,
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
                                      readOnly: true,
                                      validator: (value) =>
                                          value == null || value.isEmpty
                                          ? 'Required'
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(
                                controller: middleNameController,
                                label: 'Middle Name',
                                icon: Icons.person_outline,
                                hintText: 'Optional middle name',
                                readOnly: true,
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
                                      readOnly: true,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildTextField(
                                      controller: ageController,
                                      label: 'Age',
                                      icon: Icons.cake,
                                      hintText: 'Enter age',
                                      readOnly: true,
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
                                readOnly: true,
                                keyboardType: TextInputType.phone,
                              ),
                              if (isPediatricPatient) ...[
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: guardianController,
                                  label: 'Parent/Guardian Name',
                                  icon: Icons.family_restroom,
                                  hintText:
                                      'For children or dependent patients',
                                  readOnly: true,
                                ),
                              ],
                            ]),
                            const SizedBox(height: 12),
                            _buildPatientProfileReference(
                              resolvedPatient ?? identity,
                              isPediatric: isPediatricPatient,
                            ),
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
                              _buildDropdownField(
                                label: 'Dose Number',
                                icon: Icons.filter_1,
                                value: selectedDose,
                                items: immunizationDoseOptions(
                                  existing: selectedDose,
                                ),
                                onChanged: (value) {
                                  if (value != null) {
                                    setModalState(() => selectedDose = value);
                                  }
                                },
                              ),
                              const SizedBox(height: 16),
                              _buildDropdownField(
                                label: 'Route of Administration',
                                value: selectedRouteOfAdministration,
                                icon: Icons.route,
                                items: kImmunizationRouteOptions,
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
                                items: kImmunizationSiteOptions,
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
                                              backgroundColor: AppColors.error,
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
                                              backgroundColor: AppColors.error,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                          return;
                                        }
                                        final shouldContinue =
                                            await _confirmPotentialDuplicate(
                                              context,
                                              {
                                                'patientId': canonicalPatientId,
                                                'vaccine': selectedVaccineType,
                                                'doseNumber': selectedDose,
                                                'administrationDate':
                                                    administrationDate!
                                                        .toIso8601String(),
                                              },
                                              excludeId: record['id']
                                                  ?.toString(),
                                            );
                                        if (!shouldContinue ||
                                            !context.mounted) {
                                          return;
                                        }

                                        setModalState(() => isSaving = true);

                                        // Update immunization record
                                        final updatedRecord = {
                                          'time':
                                              '${administrationTime?.hour.toString().padLeft(2, '0')}:${administrationTime?.minute.toString().padLeft(2, '0')}',
                                          'patientName':
                                              [
                                                    firstNameController.text
                                                        .trim(),
                                                    middleNameController.text
                                                        .trim(),
                                                    surnameController.text
                                                        .trim(),
                                                  ]
                                                  .where(
                                                    (value) => value.isNotEmpty,
                                                  )
                                                  .join(' '),
                                          'patientId': canonicalPatientId,
                                          'linkedPatientId':
                                              canonicalLinkedPatientId,
                                          'firstName': firstNameController.text
                                              .trim(),
                                          'middleName': middleNameController
                                              .text
                                              .trim(),
                                          'surname': surnameController.text
                                              .trim(),
                                          'parentGuardianName':
                                              immunizationPatientIsPediatric(
                                                resolvedPatient ?? identity,
                                              )
                                              ? guardianController.text.trim()
                                              : '',
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
                                          'doseNumber': selectedDose,
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
                                                backgroundColor:
                                                    AppColors.error,
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
                                            backgroundColor: AppColors.success,
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
                                    borderRadius: BorderRadius.circular(10),
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
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
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
          backgroundColor: AppColors.success,
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
          backgroundColor: succeededIds.isEmpty
              ? AppColors.error
              : AppColors.warning,
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

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed;
    final match = RegExp(r'seconds=(\d+)').firstMatch(raw);
    if (match != null) {
      final seconds = int.tryParse(match.group(1)!);
      if (seconds != null) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
    }
    return null;
  }

  String _formatDate(dynamic value) {
    final dt = _parseDateTime(value);
    if (dt == null) {
      final raw = _safe(value, 'N/A');
      return raw;
    }
    return DateFormat('MMMM d, yyyy').format(dt);
  }

  String _formatDateLabel(dynamic value) {
    return _formatDate(value);
  }

  Color _statusColor(String status) {
    final lower = status.toLowerCase();
    if (lower.contains('overdue') || lower.contains('adverse')) {
      return AppColors.secondary;
    }
    if (lower.contains('completed') || lower.contains('progress')) {
      return AppColors.primary;
    }
    if (lower.contains('scheduled') ||
        lower.contains('pending') ||
        lower.contains('due')) {
      return AppColors.secondary;
    }
    return AppColors.textSecondary;
  }

  Color _vaccineChipColor(String _) {
    return AppColors.surfaceSubtle;
  }

  Widget _buildDivider() {
    return Container(width: 1, height: 70, color: AppColors.border);
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    Color backgroundColor = AppColors.secondary,
    Color iconColor = Colors.white,
  }) {
    final button = Container(
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
    if (tooltip != null) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
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
    const rowBg = AppColors.surfaceLight;
    const adminLabelText = AppColors.primary;
    const rowText = AppColors.textPrimary;
    const mutedText = AppColors.textSecondary;

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
                : AppColors.border,
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
                      color: AppColors.borderStrong.withValues(alpha: 0.8),
                      width: 1.2,
                    ),
                  ),
                ),
              // 1. Patient Details (flex: 26)
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
                    ],
                    const SizedBox(height: 5),
                    WebSyncStatusBadge(record: record),
                  ],
                ),
              ),
              _buildDivider(),

              // 2. Administration Details (flex: 28)
              Expanded(
                flex: 28,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 12,
                            color: _primaryAqua,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Date: $adminDate',
                              style: const TextStyle(
                                color: rowText,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
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
                      const SizedBox(height: 3),
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
                      if (nextDoseDate.isNotEmpty && nextDoseDate != 'N/A') ...[
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.event_repeat_rounded,
                              size: 11,
                              color: _primaryAqua,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Next Dose: $nextDoseDate',
                                style: const TextStyle(
                                  color: _primaryAqua,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (adverseEvents.isNotEmpty &&
                          adverseEvents != 'None reported' &&
                          adverseEvents != 'N/A') ...[
                        const SizedBox(height: 3),
                        Text(
                          'AEFI: $adverseEvents',
                          style: const TextStyle(
                            color: Color(0xFFE53935),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
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
                          color: AppColors.secondary,
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
                    width: 156,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildActionButton(
                          icon: Icons.history_rounded,
                          tooltip: 'View Details',
                          onTap: onView != null
                              ? () => onView!(record)
                              : () => onEdit(record),
                        ),
                        const SizedBox(width: 6),
                        _buildActionButton(
                          icon: Icons.edit_rounded,
                          tooltip: 'Edit Record',
                          onTap: () => onEdit(record),
                        ),
                        const SizedBox(width: 6),
                        _buildActionButton(
                          icon: Icons.picture_as_pdf_rounded,
                          tooltip: 'Export PDF',
                          onTap: () =>
                              _downloadImmunizationRecordPdf(context, record),
                        ),
                        const SizedBox(width: 6),
                        _buildActionButton(
                          icon: Icons.delete_rounded,
                          tooltip: 'Delete Record',
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
    final resolvedPatient = await PatientCenteredHistoryService()
        .resolveRegisteredPatient(record);
    final pdfRecord = <String, dynamic>{
      ...record,
      if (resolvedPatient != null) ...resolvedPatient,
    };
    final pdfBytes = await buildImmunizationPdfBytes(pdfRecord);
    final filename = buildImmunizationPdfFilename(pdfRecord);
    final downloaded = downloadFile(
      bytes: pdfBytes,
      filename: filename,
      mimeType: 'application/pdf',
    );

    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          downloaded
              ? 'PDF generated for ${pdfRecord['patientName'] ?? 'this record'}.'
              : 'PDF generation is not supported on this platform.',
        ),
        backgroundColor: downloaded ? _primaryAqua : AppColors.warning,
        duration: const Duration(seconds: 2),
      ),
    );
  } catch (e) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Failed to generate PDF: $e'),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 3),
      ),
    );
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
