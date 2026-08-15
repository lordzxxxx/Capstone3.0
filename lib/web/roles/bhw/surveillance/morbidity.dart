import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/shared/components/app_buttons.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/shared/components/app_metric_card.dart';
import 'package:mycapstone_project/web/shared/components/fullscreen_detail_table_dialog.dart';
import 'package:mycapstone_project/web/shared/components/module_view_components.dart';
import 'package:mycapstone_project/web/shared/utils/checkup_pdf.dart';
import 'package:mycapstone_project/web/shared/utils/file_download.dart';
import 'package:mycapstone_project/web/shared/utils/report_generation.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/shared_patient_search_panel.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/shared/current_table_record_utils.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';

const Color _primaryAqua = Color(0xFF2F80ED);
const Color _darkDeepTeal = Color(0xFF071A33);
const Color _panelTeal = Colors.white;
const Color _lightOffWhite = Color(0xFF0B1F3A);
const Color _mutedCoolGray = Color(0xFF4B6075);
const Color _signalGreen = Color(0xFF74D7A7);
const Color _signalAmber = Color(0xFFFFC86B);
const Color _signalRed = Color(0xFFF0897C);

class MorbidityPage extends StatefulWidget {
  const MorbidityPage({super.key});

  @override
  State<MorbidityPage> createState() => _MorbidityPageState();
}

class _MorbidityPageState extends State<MorbidityPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  final PatientCenteredHistoryService _patientHistoryService =
      PatientCenteredHistoryService();

  String _searchQuery = '';
  String _statusFilter = 'All';
  String _severityFilter = 'All';
  int _currentPage = 1;
  int _rowsPerPage = 10;
  List<Map<String, dynamic>> _reportRecords = const [];
  List<Map<String, dynamic>> _sharedPatientMatches = [];
  bool _isSearchingSharedPatients = false;
  Timer? _sharedPatientSearchDebounce;
  late HealthModuleView _activeView;

  @override
  void initState() {
    super.initState();
    _activeView = healthModuleViewFromUrl();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => persistHealthModuleView(WebRoutes.bhwMorbidity, _activeView),
    );
  }

  void _setActiveView(HealthModuleView view) {
    if (_activeView == view) return;
    setState(() => _activeView = view);
    persistHealthModuleView(WebRoutes.bhwMorbidity, view);
  }

  static const List<String> _statusOptions = [
    'All',
    'Pending',
    'Completed',
    'Active',
    'Deceased',
  ];

  static const List<String> _severityOptions = [
    'All',
    'Mild',
    'Moderate',
    'Severe',
    'Critical',
  ];

  static const List<String> _editableStatusOptions = [
    'Pending',
    'Active',
    'Completed',
    'Deceased',
  ];

  static const List<String> _editableSeverityOptions = [
    'Mild',
    'Moderate',
    'Severe',
    'Critical',
  ];

  static const List<String> _classificationOptions = [
    'General',
    'Communicable',
    'Non-Communicable',
  ];

  @override
  void dispose() {
    _sharedPatientSearchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _morbidityStream() {
    return Stream.fromFuture(
      UserAccessScopeService.instance.loadCurrentScope(),
    ).asyncExpand((scope) {
      return buildScopedRecordQuery(
        getFirestoreInstance(),
        'checkup_records',
        scope,
      ).snapshots();
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

  Future<void> _generateMorbidityReport() {
    return generateReportPdf(
      context: context,
      moduleLabel: 'Morbidity',
      records: _reportRecords,
      dateResolver: (record) {
        final source = record['sourceRecord'] is Map
            ? Map<String, dynamic>.from(record['sourceRecord'] as Map)
            : const <String, dynamic>{};
        return parseReportDateValue(record['reportedDate']) ??
            parseReportDateValue(source['datetime']) ??
            parseReportDateValue(source['dateReported']) ??
            parseReportDateValue(source['date']);
      },
      columns: [
        ReportCsvColumn(
          'Patient Name',
          (record) => reportText(record['patientName']),
          flex: 1.45,
        ),
        ReportCsvColumn(
          'Age',
          (record) => reportText(
            record['age'],
            fallback: reportText((record['sourceRecord'] as Map?)?['age']),
          ),
          flex: 0.55,
          center: true,
        ),
        ReportCsvColumn(
          'Sex',
          (record) => reportText(
            record['sex'] ?? record['gender'],
            fallback: reportText(
              (record['sourceRecord'] as Map?)?['gender'] ??
                  (record['sourceRecord'] as Map?)?['sex'],
            ),
          ),
          flex: 0.55,
          center: true,
        ),
        ReportCsvColumn(
          'Disease / Diagnosis',
          (record) => reportText(record['disease']),
          flex: 1.45,
        ),
        ReportCsvColumn(
          'Date Recorded',
          (record) => formatReportDateValue(record['reportedDate']),
          flex: 0.95,
          center: true,
        ),
        ReportCsvColumn(
          'Case Status',
          (record) => reportText(record['status']),
          flex: 0.9,
          center: true,
        ),
        ReportCsvColumn(
          'Remarks',
          (record) => reportText(record['remarks']),
          flex: 1.45,
        ),
      ],
      accentColor: _primaryAqua,
      dialogColor: _panelTeal,
      textColor: _lightOffWhite,
      mutedColor: _mutedCoolGray,
      sectionTitleBuilder: (record, index) =>
          'Record ${index + 1}: ${reportText(record['patientName'], fallback: 'Patient')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.email?.split('@').first ?? 'User';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F7FA),
      drawer: WebAppSidebar(
        userName: userName,
        activeItem: WebSidebarItem.morbidity,
      ),
      appBar: AppBar(
        toolbarHeight: 70,
        backgroundColor: _darkDeepTeal,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 36),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(
          'Morbidity Dashboard',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: FilledButton.icon(
                onPressed: _generateMorbidityReport,
                style: AppButtonStyles.report(),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: const Text(
                  'Generate',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ColoredBox(
        color: Color(0xFFF5F7FA),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _morbidityStream(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _buildStateMessage(
                context,
                icon: Icons.error_outline_rounded,
                title: 'Linked check-up morbidity records could not be loaded.',
                subtitle:
                    'Check the Firestore connection or record permissions for check-up records and try again.',
              );
            }

            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: _primaryAqua),
              );
            }

            final records = _normalizeRecords(snapshot.data!.docs);
            final filteredRecords = _applyFilters(records);
            _reportRecords = filteredRecords;
            final summary = _summarizeRecords(records);
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

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HealthModuleViewHeader(
                    title: 'Morbidity Records',
                    description:
                        'Review morbidity activity and care priorities, or manage individual patient-linked case records.',
                    activeView: _activeView,
                    onViewChanged: _setActiveView,
                    primaryColor: _primaryAqua,
                    mutedColor: _mutedCoolGray,
                    insightsLabel: 'Summary',
                  ),
                  const SizedBox(height: 16),
                  if (_activeView == HealthModuleView.insights) ...[
                    if (records.isEmpty)
                      const ModuleEmptyState(
                        title: 'No morbidity insights yet',
                        message:
                            'Linked check-up morbidity entries will appear here when records become available.',
                        icon: Icons.analytics_outlined,
                      )
                    else ...[
                      _buildOverviewSection(summary),
                      const SizedBox(height: 24),
                      _buildOperationalPanels(summary),
                    ],
                  ] else
                    _buildRecordsSection(
                      context,
                      filteredCount: filteredRecords.length,
                      totalCount: records.length,
                      pagedRecords: pagedRecords,
                      currentPage: currentPage,
                      totalPages: totalPages,
                      effectiveRowsPerPage: effectiveRowsPerPage,
                      pageStartIndex: pageStartIndex,
                      pageEndIndex: pageEndIndex,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _normalizeRecords(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final records = docs
        .map((doc) {
          final source = materializeFirestoreRecord(doc);
          final linkedCheckupId = _safeText(source['id'], fallback: doc.id);
          final linkedPatientId = _safeText(
            source['linkedPatientId'] ??
                source['patientId'] ??
                source['patientID'] ??
                source['patient_id'],
            fallback: 'Not linked',
          );
          final patientName = _safeText(
            source['patient'] ?? source['patientName'],
            fallback: 'Unknown patient',
          );
          final caseClassification = _safeText(
            source['caseClassification'] ??
                source['diseaseType'] ??
                source['classification'],
            fallback: 'General',
          );
          final disease = _safeText(
            source['symptoms'] ??
                source['disease'] ??
                source['diagnosis'] ??
                source['condition'] ??
                source['ai_category'],
            fallback: caseClassification == 'General'
                ? _safeText(
                    source['details'],
                    fallback: 'General clinical case',
                  )
                : caseClassification,
          );
          final severity = _safeText(
            source['severity'] ?? source['ai_severity'] ?? source['urgency'],
            fallback: 'Unspecified',
          );
          final remarks = _safeText(
            source['remarks'] ??
                source['plan'] ??
                source['details'] ??
                source['symptoms'],
            fallback: 'No remarks recorded',
          );
          final status = _safeText(
            source['status'] ?? source['caseStatus'],
            fallback: 'Pending',
          );
          final reportedDate =
              source['datetime'] ?? source['dateReported'] ?? source['date'];

          return {
            'id': linkedCheckupId,
            'documentId': doc.id,
            'linkedCheckupId': linkedCheckupId,
            'linkedPatientId': linkedPatientId,
            'patientName': patientName,
            'disease': disease,
            'caseClassification': caseClassification,
            'severity': severity,
            'remarks': remarks,
            'status': status,
            'reportedDate': reportedDate,
            'sourceRecord': source,
          };
        })
        .where(_isLinkedMorbidityRecord)
        .toList();

    records.sort(
      (a, b) => _parseDate(
        b['reportedDate'],
      ).compareTo(_parseDate(a['reportedDate'])),
    );

    return records;
  }

  bool _isLinkedMorbidityRecord(Map<String, dynamic> record) {
    final classification = _safeText(
      record['caseClassification'],
    ).toLowerCase();
    final disease = _safeText(record['disease']).toLowerCase();
    final severity = _safeText(record['severity']).toLowerCase();
    final remarks = _safeText(record['remarks']).toLowerCase();

    return classification == 'communicable' ||
        classification == 'non-communicable' ||
        (classification.isNotEmpty && classification != 'general') ||
        (disease.isNotEmpty &&
            disease != 'general' &&
            disease != 'general clinical case' &&
            disease != 'unspecified') ||
        (severity.isNotEmpty &&
            severity != 'n/a' &&
            severity != 'unspecified') ||
        (remarks.isNotEmpty && remarks != 'no remarks recorded') ||
        disease.contains('disease') ||
        disease.contains('fever') ||
        disease.contains('infection') ||
        disease.contains('hypertension') ||
        disease.contains('diabetes');
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> records) {
    final filtered = records.where((record) {
      final searchMatch = _searchQuery.trim().isEmpty
          ? true
          : [
              _safeText(record['linkedCheckupId']),
              _safeText(record['linkedPatientId']),
              _safeText(record['patientName']),
              _safeText(record['disease']),
              _safeText(record['caseClassification']),
              _safeText(record['remarks']),
            ].any(
              (value) =>
                  value.toLowerCase().contains(_searchQuery.toLowerCase()),
            );

      final statusMatch = _statusFilter == 'All'
          ? true
          : _safeText(record['status']).toLowerCase() ==
                _statusFilter.toLowerCase();

      final severityMatch = _severityFilter == 'All'
          ? true
          : _safeText(record['severity']).toLowerCase() ==
                _severityFilter.toLowerCase();

      return searchMatch && statusMatch && severityMatch;
    }).toList();

    return CurrentTableRecordUtils.collapseToLatestPerEntity(
      filtered,
      idKeys: const ['linkedPatientId', 'patientId'],
      nameKeys: const ['patientName', 'patient', 'name'],
      dateKeys: const ['reportedDate', 'datetime', 'dateReported', 'date'],
    );
  }

  _MorbiditySummary _summarizeRecords(List<Map<String, dynamic>> records) {
    final diseaseCounts = <String, int>{};
    int activeCases = 0;
    int recoveredCases = 0;
    int highPriorityCases = 0;

    for (final record in records) {
      final disease = _safeText(record['disease'], fallback: 'Unspecified');
      final status = _safeText(record['status']).toLowerCase();
      final severity = _safeText(record['severity']).toLowerCase();
      diseaseCounts[disease] = (diseaseCounts[disease] ?? 0) + 1;
      if (status == 'active' ||
          status == 'under treatment' ||
          status == 'pending') {
        activeCases++;
      }
      if (status == 'recovered' ||
          status == 'completed' ||
          status == 'resolved') {
        recoveredCases++;
      }
      if (severity == 'severe' || severity == 'critical') {
        highPriorityCases++;
      }
    }

    final sortedDiseases = diseaseCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final priorityRecords = records
        .where((record) {
          final severity = _safeText(record['severity']).toLowerCase();
          final status = _safeText(record['status']).toLowerCase();
          return severity == 'severe' ||
              severity == 'critical' ||
              status == 'active' ||
              status == 'under treatment' ||
              status == 'pending';
        })
        .take(4)
        .toList();

    return _MorbiditySummary(
      totalCases: records.length,
      activeCases: activeCases,
      recoveredCases: recoveredCases,
      highPriorityCases: highPriorityCases,
      topDisease: sortedDiseases.isEmpty
          ? 'No cases recorded'
          : sortedDiseases.first.key,
      recoveryRate: records.isEmpty
          ? 0
          : (recoveredCases / records.length) * 100,
      topDiseases: sortedDiseases.take(5).toList(),
      priorityRecords: priorityRecords,
    );
  }

  Widget _buildOverviewSection(_MorbiditySummary summary) {
    final cards = <Widget>[
      _MetricCard(
        label: 'Total Cases',
        value: summary.totalCases.toString(),
        helper: 'All morbidity cases derived from linked check-up records',
        icon: Icons.folder_open_rounded,
      ),
      _MetricCard(
        label: 'Active Follow-up',
        value: summary.activeCases.toString(),
        helper: 'Cases still active or under treatment',
        icon: Icons.health_and_safety_rounded,
      ),
      _MetricCard(
        label: 'Closed Cases',
        value: summary.recoveredCases.toString(),
        helper: 'Linked check-up cases already completed or resolved',
        icon: Icons.healing_rounded,
      ),
      _MetricCard(
        label: 'High Priority',
        value: summary.highPriorityCases.toString(),
        helper: 'Severe or critical records needing close review',
        icon: Icons.priority_high_rounded,
      ),
      _MetricCard(
        label: 'Recovery Rate',
        value: '${summary.recoveryRate.toStringAsFixed(1)}%',
        helper: 'Closed cases compared with total linked morbidity cases',
        icon: Icons.trending_up_rounded,
      ),
      _MetricCard(
        label: 'Top Disease',
        value: summary.topDisease,
        helper: 'Most reported symptom pulled from linked check-up records',
        icon: Icons.biotech_rounded,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading(
          'Morbidity Overview',
          'Patient-linked morbidity indicators synchronized from check-up records.',
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1180
                ? 3
                : constraints.maxWidth >= 720
                ? 2
                : 1;
            const spacing = 16.0;
            final cardWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: cards
                  .map(
                    (card) =>
                        SizedBox(width: cardWidth, height: 190, child: card),
                  )
                  .toList(growable: false),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSectionHeading(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _lightOffWhite,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: _mutedCoolGray, fontSize: 12.5),
        ),
      ],
    );
  }

  Widget _buildOperationalPanels(_MorbiditySummary summary) {
    final topConditionsPanel = _PanelCard(
      title: 'Top Reported Conditions',
      child: summary.topDiseases.isEmpty
          ? const _PanelEmptyState(
              text:
                  'Condition counts will appear here once morbidity records are saved.',
            )
          : Column(
              children: summary.topDiseases.map((entry) {
                final ratio = summary.totalCases == 0
                    ? 0.0
                    : entry.value / summary.totalCases;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                color: _lightOffWhite,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${entry.value} case${entry.value == 1 ? '' : 's'}',
                            style: const TextStyle(color: _mutedCoolGray),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: ratio.clamp(0, 1),
                          minHeight: 10,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            _primaryAqua,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
    final watchlistPanel = _PanelCard(
      title: 'Priority Watchlist',
      child: summary.priorityRecords.isEmpty
          ? const _PanelEmptyState(
              text:
                  'No linked check-up cases are waiting for severity-based review right now.',
            )
          : Column(
              children: summary.priorityRecords.map((record) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _priorityColor(record).withValues(alpha: 0.30),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _safeText(
                                  record['patientName'],
                                  fallback: 'Unknown patient',
                                ),
                                style: const TextStyle(
                                  color: _lightOffWhite,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            _StatusBadge(
                              label: _safeText(
                                record['severity'],
                                fallback: 'Unspecified',
                              ),
                              color: _severityColor(
                                _safeText(record['severity']),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _safeText(
                            record['disease'],
                            fallback: 'No disease label',
                          ),
                          style: const TextStyle(
                            color: _lightOffWhite,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_safeText(record['caseClassification'], fallback: 'Case classification not set')}  |  ${_safeText(record['status'], fallback: 'Status not set')}',
                          style: const TextStyle(
                            color: _mutedCoolGray,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Check-up ID: ${_safeText(record['linkedCheckupId'], fallback: '-')}  |  Patient ID: ${_safeText(record['linkedPatientId'], fallback: 'Not linked')}',
                          style: const TextStyle(
                            color: _mutedCoolGray,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final vertical = constraints.maxWidth < 1100;
        if (vertical) {
          return Column(
            children: [
              topConditionsPanel,
              const SizedBox(height: 20),
              watchlistPanel,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: topConditionsPanel),
            const SizedBox(width: 20),
            Expanded(child: watchlistPanel),
          ],
        );
      },
    );
  }

  Widget _buildHeaderCell(String label, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildHeaderDivider() {
    return Container(
      width: 1,
      height: 18,
      color: Colors.white.withValues(alpha: 0.28),
    );
  }

  Widget _buildMorbidityCardHeader() {
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
          _buildHeaderCell('Patient Details', flex: 22),
          _buildHeaderDivider(),
          _buildHeaderCell('Disease / Classification', flex: 22),
          _buildHeaderDivider(),
          _buildHeaderCell('Case Notes', flex: 28),
          _buildHeaderDivider(),
          _buildHeaderCell('Severity / Status', flex: 16),
          _buildHeaderDivider(),
          _buildHeaderCell('Date Recorded', flex: 12),
          _buildHeaderDivider(),
          const SizedBox(
            width: 112,
            child: Text(
              'Actions',
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

  Widget _buildRecordsSection(
    BuildContext context, {
    required int filteredCount,
    required int totalCount,
    required List<Map<String, dynamic>> pagedRecords,
    required int currentPage,
    required int totalPages,
    required int effectiveRowsPerPage,
    required int pageStartIndex,
    required int pageEndIndex,
  }) {
    return _PanelCard(
      title: 'Morbidity Records',
      registryStyle: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInlineFilterBar(context, filteredCount, totalCount),
          const SizedBox(height: 16),
          if (filteredCount == 0)
            const _PanelEmptyState(
              text:
                  'No linked check-up morbidity records match the current filters. Try clearing the search or adjusting the status and severity selections.',
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: math.max(1380, constraints.maxWidth),
                    child: Column(
                      children: [
                        _buildMorbidityCardHeader(),
                        _MorbidityTable(
                          records: pagedRecords,
                          startIndex: pageStartIndex,
                          onView: (record) =>
                              _showMorbidityHistory(context, record),
                          onEdit: (record) =>
                              _showEditMorbidityDialog(context, record),
                          onGeneratePdf: (record) =>
                              _generateMorbidityPdf(context, record),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Showing ${pageStartIndex + 1}-$pageEndIndex of $filteredCount records',
                    style: TextStyle(
                      fontSize: 12,
                      color: _lightOffWhite.withValues(alpha: 0.72),
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
                        color: _lightOffWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      iconEnabledColor: _primaryAqua,
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
                  color: _lightOffWhite,
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
                      color: _lightOffWhite,
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
                  color: _lightOffWhite,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInlineFilterBar(
    BuildContext context,
    int filteredCount,
    int totalCount,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$filteredCount of $totalCount morbidity records shown',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: _mutedCoolGray),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final searchField = TextField(
              controller: _searchController,
              style: const TextStyle(color: _lightOffWhite),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _currentPage = 1;
                });
                _scheduleSharedPatientSearch(value);
              },
              decoration: InputDecoration(
                hintText:
                    'Search patient, disease, classification, or linked IDs',
                hintStyle: const TextStyle(color: _mutedCoolGray),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: _primaryAqua,
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: _primaryAqua.withValues(alpha: 0.18),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: _primaryAqua.withValues(alpha: 0.18),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _primaryAqua),
                ),
              ),
            );
            final statusFilter = _FilterDropdown(
              label: 'Status',
              value: _statusFilter,
              options: _statusOptions,
              onChanged: (value) => setState(() {
                _statusFilter = value;
                _currentPage = 1;
              }),
            );
            final severityFilter = _FilterDropdown(
              label: 'Severity',
              value: _severityFilter,
              options: _severityOptions,
              onChanged: (value) => setState(() {
                _severityFilter = value;
                _currentPage = 1;
              }),
            );

            if (constraints.maxWidth < 820) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  searchField,
                  const SizedBox(height: 12),
                  statusFilter,
                  const SizedBox(height: 12),
                  severityFilter,
                ],
              );
            }

            return Row(
              children: [
                Expanded(flex: 5, child: searchField),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: statusFilter),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: severityFilter),
              ],
            );
          },
        ),
        if (_searchQuery.trim().isNotEmpty || _isSearchingSharedPatients) ...[
          const SizedBox(height: 14),
          SharedPatientSearchPanel(
            query: _searchQuery,
            results: _sharedPatientMatches,
            isLoading: _isSearchingSharedPatients,
            primaryActionLabel: 'View Medical History',
            onPrimaryAction: _showSharedPatientTimeline,
          ),
        ],
      ],
    );
  }

  Map<String, dynamic> _buildLinkedCheckupPayload(Map<String, dynamic> record) {
    final rawSource = record['sourceRecord'];
    final source = rawSource is Map
        ? Map<String, dynamic>.from(rawSource)
        : <String, dynamic>{};

    final disease = _safeText(
      record['disease'],
      fallback: _safeText(
        source['symptoms'] ?? source['disease'],
        fallback: 'Unspecified',
      ),
    );
    final caseClassification = _safeText(
      record['caseClassification'],
      fallback: _safeText(source['diseaseType'], fallback: 'General'),
    );
    final severity = _safeText(
      record['severity'],
      fallback: _safeText(source['ai_severity'], fallback: 'Unspecified'),
    );
    final remarks = _safeText(
      record['remarks'],
      fallback: _safeText(
        source['remarks'],
        fallback: _safeText(source['plan'], fallback: 'No remarks recorded'),
      ),
    );
    final patientName = _safeText(
      record['patientName'],
      fallback: _safeText(source['patient'], fallback: 'Unknown patient'),
    );
    final linkedPatientId = _safeText(
      record['linkedPatientId'],
      fallback: _safeText(
        source['linkedPatientId'] ?? source['patientId'],
        fallback: 'Not linked',
      ),
    );
    final linkedCheckupId = _safeText(
      record['linkedCheckupId'],
      fallback: _safeText(
        source['id'],
        fallback: _safeText(record['documentId']),
      ),
    );
    final reportedDate = record['reportedDate'] ?? source['datetime'];
    final status = _safeText(
      record['status'],
      fallback: _safeText(source['status'], fallback: 'Pending'),
    );

    return {
      ...source,
      'id': linkedCheckupId,
      'patient': patientName,
      'patientId': linkedPatientId,
      'linkedPatientId': linkedPatientId,
      'disease': disease,
      'caseClassification': caseClassification,
      'diseaseType': caseClassification,
      'severity': severity,
      'remarks': remarks,
      'status': status,
      'datetime': reportedDate,
      'plan': _safeText(source['plan'], fallback: remarks),
      'details': _safeText(source['details'], fallback: remarks),
      'ai_category': disease,
      'ai_severity': severity,
    };
  }

  Future<void> _generateMorbidityPdf(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final pdfRecord = _buildLinkedCheckupPayload(record);

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
      final pdfBytes = await buildCheckupPdfBytes(pdfRecord);
      final filename = buildCheckupPdfFilename(pdfRecord);
      final downloaded = downloadFile(
        bytes: pdfBytes,
        filename: filename,
        mimeType: 'application/pdf',
      );

      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            downloaded
                ? 'PDF generated for ${pdfRecord['patient'] ?? 'this record'}.'
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

  List<Map<String, dynamic>> _getMorbidityHistory(Map<String, dynamic> record) {
    return PatientHistoryDialogs.collectHistory(
      seedRecord: record,
      records: _reportRecords,
      idKeys: const ['linkedPatientId', 'patientId', 'id'],
      nameKeys: const ['patientName', 'patient', 'name'],
      sortDateKeys: const ['reportedDate', 'datetime', 'dateReported', 'date'],
    );
  }

  Future<void> _showMorbidityHistory(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    final history = _getMorbidityHistory(record);
    await PatientHistoryDialogs.showModuleHistoryDialog(
      context: context,
      moduleTitle: 'Morbidity',
      seedRecord: record,
      history: history,
      description:
          'Review previous morbidity reports for this patient before recording another disease episode.',
      titleBuilder: (entry) =>
          (entry['disease'] ?? entry['symptoms'] ?? 'Morbidity record')
              .toString(),
      subtitleBuilder: (entry) =>
          '${(entry['severity'] ?? 'Unspecified').toString()} | ${(entry['status'] ?? 'Pending').toString()}',
      metaBuilder: (entry) =>
          'Classification: ${(entry['caseClassification'] ?? entry['diseaseType'] ?? 'General').toString()} | Remarks: ${(entry['remarks'] ?? 'No remarks').toString()}',
      dateKeys: const ['reportedDate', 'datetime', 'dateReported', 'date'],
      onOpenRecord: (entry) => _showMorbidityDetailsDialog(context, entry),
    );
  }

  Future<void> _showMorbidityDetailsDialog(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    final payload = _buildLinkedCheckupPayload(record);
    final rawSource = record['sourceRecord'];
    final sourceRecord = rawSource is Map
        ? Map<String, dynamic>.from(rawSource)
        : <String, dynamic>{};
    final databaseFields = <MapEntry<String, dynamic>>[
      if (_safeText(record['documentId']).isNotEmpty &&
          !sourceRecord.containsKey('documentId'))
        MapEntry('documentId', record['documentId']),
      ...sourceRecord.entries,
    ];
    databaseFields.sort((a, b) => a.key.compareTo(b.key));
    final patientName = _safeText(
      payload['patient'],
      fallback: 'Unknown patient',
    );
    final linkedCheckupId = _safeText(payload['id'], fallback: '-');
    final linkedPatientId = _safeText(
      payload['linkedPatientId'] ?? payload['patientId'],
      fallback: 'Not linked',
    );
    final disease = _safeText(payload['disease'], fallback: 'Unspecified');
    final classification = _safeText(
      payload['caseClassification'] ?? payload['diseaseType'],
      fallback: 'General',
    );
    final severity = _safeText(payload['severity'], fallback: 'Unspecified');
    final status = _safeText(payload['status'], fallback: 'Pending');
    final remarks = _safeText(
      payload['remarks'],
      fallback: 'No remarks recorded',
    );
    final reportDate = _safeText(
      payload['datetime'],
      fallback: 'Report date unavailable',
    );
    final symptoms = _safeText(
      payload['symptoms'],
      fallback: 'No symptoms recorded',
    );
    final vitals = _safeText(
      payload['vitalsigns'],
      fallback: 'No vital signs recorded',
    );
    final followUp = _safeText(
      payload['followup'],
      fallback: 'No follow-up schedule recorded',
    );

    await showFullscreenDetailTableDialog(
      context: context,
      title: 'Morbidity Details',
      subject: patientName,
      items: [
        DetailTableItem(
          icon: Icons.person_outline_rounded,
          label: 'Patient Name',
          value: patientName,
        ),
        DetailTableItem(
          icon: Icons.assignment_outlined,
          label: 'Check-up ID',
          value: linkedCheckupId,
        ),
        DetailTableItem(
          icon: Icons.credit_card_outlined,
          label: 'Patient ID',
          value: linkedPatientId,
        ),
        DetailTableItem(
          icon: Icons.calendar_today_outlined,
          label: 'Report Date',
          value: reportDate,
        ),
        DetailTableItem(
          icon: Icons.coronavirus_outlined,
          label: 'Disease',
          value: disease,
        ),
        DetailTableItem(
          icon: Icons.category_outlined,
          label: 'Case Classification',
          value: classification,
        ),
        DetailTableItem(
          icon: Icons.warning_amber_rounded,
          label: 'Severity',
          value: severity,
        ),
        DetailTableItem(
          icon: Icons.verified_outlined,
          label: 'Status',
          value: status,
        ),
        DetailTableItem(
          icon: Icons.sick_outlined,
          label: 'Symptoms',
          value: symptoms,
        ),
        DetailTableItem(
          icon: Icons.favorite_outline_rounded,
          label: 'Vital Signs',
          value: vitals,
        ),
        DetailTableItem(
          icon: Icons.update_outlined,
          label: 'Follow-up Date',
          value: followUp,
        ),
        DetailTableItem(
          icon: Icons.notes_outlined,
          label: 'Remarks',
          value: remarks,
        ),
      ],
    );
    return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 24,
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 920),
            decoration: BoxDecoration(
              color: _darkDeepTeal,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Linked morbidity details from the related check-up record.',
                              style: TextStyle(
                                color: _mutedCoolGray.withValues(alpha: 0.92),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: _lightOffWhite,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildDialogSection(
                    title: 'Linked Record',
                    children: [
                      _buildDialogField('Check-up ID', linkedCheckupId),
                      _buildDialogField('Patient ID', linkedPatientId),
                      _buildDialogField('Report Date', reportDate),
                      _buildDialogField('Status', status),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildDialogSection(
                    title: 'Case Information',
                    children: [
                      _buildDialogField('Disease', disease),
                      _buildDialogField('Case Classification', classification),
                      _buildDialogField('Severity', severity),
                      _buildDialogField('Remarks', remarks, maxLines: 4),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildDialogSection(
                    title: 'Check-up Notes',
                    children: [
                      _buildDialogField('Symptoms', symptoms, maxLines: null),
                      _buildDialogField('Vital Signs', vitals, maxLines: null),
                      _buildDialogField('Follow-up Date', followUp),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildDialogSection(
                    title: 'Database Details',
                    children: databaseFields.isEmpty
                        ? const [
                            Text(
                              'No database fields were found for this linked record.',
                              style: TextStyle(
                                color: _mutedCoolGray,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ]
                        : databaseFields
                              .map(
                                (field) => _buildDialogField(
                                  _humanizeFieldLabel(field.key),
                                  _formatDatabaseValue(field.value),
                                  maxLines: null,
                                ),
                              )
                              .toList(),
                  ),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _lightOffWhite,
                            side: BorderSide(
                              color: _primaryAqua.withValues(alpha: 0.24),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          child: const Text('Close'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            Navigator.of(dialogContext).pop();
                            await _generateMorbidityPdf(context, record);
                          },
                          icon: const Icon(Icons.picture_as_pdf_rounded),
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
        );
      },
    );
  }

  Future<void> _showEditMorbidityDialog(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    final linkedCheckupId = _safeText(record['linkedCheckupId']);
    final documentId = _safeText(
      record['documentId'],
      fallback: linkedCheckupId,
    );
    final diseaseController = TextEditingController(
      text: _safeText(record['disease']),
    );
    final linkedPatientIdController = TextEditingController(
      text: _safeText(
        record['linkedPatientId'],
        fallback: _safeText(record['patientId']),
      ),
    );
    final remarksController = TextEditingController(
      text: _safeText(record['remarks']),
    );
    var classification =
        _classificationOptions.contains(_safeText(record['caseClassification']))
        ? _safeText(record['caseClassification'])
        : 'General';
    var severity =
        _editableSeverityOptions.contains(_safeText(record['severity']))
        ? _safeText(record['severity'])
        : 'Mild';
    var status = _editableStatusOptions.contains(_safeText(record['status']))
        ? _safeText(record['status'])
        : 'Pending';
    var isSaving = false;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogStateContext, setDialogState) {
              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 24,
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 720),
                  decoration: BoxDecoration(
                    color: _darkDeepTeal,
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
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Edit Linked Morbidity Record',
                                    style: TextStyle(
                                      color: _lightOffWhite,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Check-up ID: ${linkedCheckupId.isEmpty ? '-' : linkedCheckupId}',
                                    style: const TextStyle(
                                      color: _mutedCoolGray,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: isSaving
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                              icon: const Icon(Icons.close_rounded),
                              color: _lightOffWhite,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildEditTextField(
                          controller: diseaseController,
                          label: 'Symptoms',
                        ),
                        const SizedBox(height: 14),
                        _buildEditTextField(
                          controller: linkedPatientIdController,
                          label: 'Linked Patient ID',
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _buildEditDropdown(
                                label: 'Case Classification',
                                value: classification,
                                items: _classificationOptions,
                                onChanged: (value) => setDialogState(() {
                                  classification = value;
                                }),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _buildEditDropdown(
                                label: 'Severity',
                                value: severity,
                                items: _editableSeverityOptions,
                                onChanged: (value) => setDialogState(() {
                                  severity = value;
                                }),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _buildEditDropdown(
                          label: 'Status',
                          value: status,
                          items: _editableStatusOptions,
                          onChanged: (value) => setDialogState(() {
                            status = value;
                          }),
                        ),
                        const SizedBox(height: 14),
                        _buildEditTextField(
                          controller: remarksController,
                          label: 'Remarks',
                          maxLines: 4,
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              OutlinedButton(
                                onPressed: isSaving
                                    ? null
                                    : () => Navigator.of(dialogContext).pop(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _lightOffWhite,
                                  side: BorderSide(
                                    color: _primaryAqua.withValues(alpha: 0.24),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton.icon(
                                onPressed: isSaving
                                    ? null
                                    : () async {
                                        final disease = diseaseController.text
                                            .trim();
                                        final linkedPatientId =
                                            linkedPatientIdController.text
                                                .trim();
                                        final remarks = remarksController.text
                                            .trim();

                                        if (documentId.isEmpty) {
                                          ScaffoldMessenger.maybeOf(
                                            context,
                                          )?.showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'This record is missing a linked check-up ID.',
                                              ),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                          return;
                                        }

                                        if (disease.isEmpty) {
                                          ScaffoldMessenger.maybeOf(
                                            context,
                                          )?.showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Please enter the symptoms before saving.',
                                              ),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                          return;
                                        }

                                        setDialogState(() => isSaving = true);

                                        try {
                                          final accessScope =
                                              await UserAccessScopeService
                                                  .instance
                                                  .loadCurrentScope();
                                          final updateData = <String, dynamic>{
                                            'patientId': linkedPatientId,
                                            'linkedPatientId': linkedPatientId,
                                            'symptoms': disease,
                                            'disease': disease,
                                            'caseClassification':
                                                classification,
                                            'diseaseType': classification,
                                            'severity': severity,
                                            'ai_category': disease,
                                            'ai_severity': severity,
                                            'remarks': remarks,
                                            'status': status,
                                            'caseStatus': status,
                                            'updatedAt':
                                                FieldValue.serverTimestamp(),
                                          };
                                          final documentRef =
                                              await resolveScopedRecordDocumentReference(
                                                getFirestoreInstance(),
                                                'checkup_records',
                                                documentId,
                                                accessScope: accessScope,
                                                record: {
                                                  ...(record['sourceRecord']
                                                          is Map
                                                      ? Map<
                                                          String,
                                                          dynamic
                                                        >.from(
                                                          record['sourceRecord']
                                                              as Map,
                                                        )
                                                      : const <
                                                          String,
                                                          dynamic
                                                        >{}),
                                                  ...updateData,
                                                },
                                                existingPath:
                                                    (record['sourceRecord']
                                                                is Map
                                                            ? (record['sourceRecord']
                                                                  as Map)['_firestorePath']
                                                            : null)
                                                        ?.toString(),
                                              );
                                          await documentRef.update(updateData);

                                          if (!dialogContext.mounted) return;
                                          Navigator.of(dialogContext).pop();

                                          if (!mounted) return;
                                          ScaffoldMessenger.maybeOf(
                                            context,
                                          )?.showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Linked morbidity record updated successfully.',
                                              ),
                                              backgroundColor: _primaryAqua,
                                            ),
                                          );
                                        } catch (e) {
                                          if (dialogContext.mounted) {
                                            setDialogState(
                                              () => isSaving = false,
                                            );
                                          }
                                          ScaffoldMessenger.maybeOf(
                                            context,
                                          )?.showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Failed to update record: $e',
                                              ),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      },
                                icon: isSaving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: _darkDeepTeal,
                                        ),
                                      )
                                    : const Icon(Icons.save_rounded),
                                label: Text(
                                  isSaving ? 'Saving...' : 'Save Changes',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryAqua,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 14,
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
            },
          );
        },
      );
    } finally {
      diseaseController.dispose();
      linkedPatientIdController.dispose();
      remarksController.dispose();
    }
  }

  Widget _buildDialogSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panelTeal.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _lightOffWhite,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDialogField(String label, String value, {int? maxLines = 2}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _mutedCoolGray,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: maxLines,
            overflow: maxLines == null
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            softWrap: true,
            style: const TextStyle(
              color: _lightOffWhite,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  String _humanizeFieldLabel(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      return 'Field';
    }

    final withSpaces = trimmed
        .replaceAll('_', ' ')
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        );

    return withSpaces
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  dynamic _normalizeDatabaseValue(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is GeoPoint) {
      return {'latitude': value.latitude, 'longitude': value.longitude};
    }
    if (value is List) {
      return value.map(_normalizeDatabaseValue).toList();
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _normalizeDatabaseValue(entry.value),
      };
    }
    return value;
  }

  String _formatDatabaseValue(dynamic value) {
    if (value == null) {
      return 'Not recorded';
    }

    final normalized = _normalizeDatabaseValue(value);

    if (normalized is List || normalized is Map) {
      if ((normalized is List && normalized.isEmpty) ||
          (normalized is Map && normalized.isEmpty)) {
        return 'Not recorded';
      }

      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(normalized);
    }

    final text = normalized.toString().trim();
    return text.isEmpty ? 'Not recorded' : text;
  }

  InputDecoration _buildEditFieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white),
      filled: true,
      fillColor: _darkDeepTeal,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: _primaryAqua, width: 2),
      ),
    );
  }

  Widget _buildEditTextField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: _lightOffWhite),
      decoration: _buildEditFieldDecoration(label),
    );
  }

  Widget _buildEditDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      dropdownColor: _darkDeepTeal,
      style: const TextStyle(
        color: _lightOffWhite,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      iconEnabledColor: _primaryAqua,
      decoration: _buildEditFieldDecoration(label),
      items: items
          .map(
            (item) => DropdownMenuItem<String>(value: item, child: Text(item)),
          )
          .toList(),
      onChanged: (nextValue) {
        if (nextValue != null) {
          onChanged(nextValue);
        }
      },
    );
  }

  Widget _buildStateMessage(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _PanelCard(
            title: title,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: _primaryAqua, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _mutedCoolGray,
                      height: 1.5,
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

  DateTime _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _safeText(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') {
      return fallback;
    }
    return text;
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return _signalRed;
      case 'severe':
        return _signalAmber;
      case 'moderate':
        return _primaryAqua;
      case 'mild':
        return _signalGreen;
      default:
        return _mutedCoolGray;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'recovered':
        return _signalGreen;
      case 'deceased':
        return _signalRed;
      case 'under treatment':
        return _signalAmber;
      case 'active':
        return _primaryAqua;
      default:
        return _mutedCoolGray;
    }
  }

  Color _priorityColor(Map<String, dynamic> record) {
    final severity = _safeText(record['severity']);
    final status = _safeText(record['status']);
    final severityColor = _severityColor(severity);
    final statusColor = _statusColor(status);
    return severityColor == _mutedCoolGray ? statusColor : severityColor;
  }
}

class _MorbiditySummary {
  final int totalCases;
  final int activeCases;
  final int recoveredCases;
  final int highPriorityCases;
  final String topDisease;
  final double recoveryRate;
  final List<MapEntry<String, int>> topDiseases;
  final List<Map<String, dynamic>> priorityRecords;

  const _MorbiditySummary({
    required this.totalCases,
    required this.activeCases,
    required this.recoveredCases,
    required this.highPriorityCases,
    required this.topDisease,
    required this.recoveryRate,
    required this.topDiseases,
    required this.priorityRecords,
  });
}

class _PanelCard extends StatelessWidget {
  final String title;
  final Widget child;
  final bool registryStyle;

  const _PanelCard({
    required this.title,
    required this.child,
    this.registryStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(registryStyle ? 16 : 18),
      decoration: BoxDecoration(
        color: _panelTeal,
        borderRadius: BorderRadius.circular(registryStyle ? 12 : 14),
        border: Border.all(
          color: registryStyle
              ? _primaryAqua.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.07),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _lightOffWhite,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String helper;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AppMetricCard(
      label: label,
      value: value,
      icon: icon,
      supportingText: helper,
    );
  }
}

class _MorbidityTable extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final int startIndex;
  final Future<void> Function(Map<String, dynamic>) onView;
  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(Map<String, dynamic>) onGeneratePdf;

  const _MorbidityTable({
    required this.records,
    required this.startIndex,
    required this.onView,
    required this.onEdit,
    required this.onGeneratePdf,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const Center(
        child: Text(
          'No records found.',
          style: TextStyle(color: _lightOffWhite, fontSize: 16),
        ),
      );
    }

    return Column(
      children: List.generate(records.length, (index) {
        final absoluteIndex = startIndex + index;
        return _MorbidityRecordCard(
          record: records[index],
          absoluteIndex: absoluteIndex,
          onView: () => onView(records[index]),
          onEdit: () => onEdit(records[index]),
          onGeneratePdf: () => onGeneratePdf(records[index]),
        );
      }),
    );
  }
}

class _MorbidityRecordCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final int absoluteIndex;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onGeneratePdf;

  const _MorbidityRecordCard({
    required this.record,
    required this.absoluteIndex,
    required this.onView,
    required this.onEdit,
    required this.onGeneratePdf,
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

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return const Color(0xFFE57373);
      case 'severe':
        return const Color(0xFFFFB74D);
      case 'moderate':
        return const Color(0xFF64B5F6);
      case 'mild':
        return const Color(0xFF81C784);
      default:
        return const Color(0xFFB0BEC5);
    }
  }

  Color _statusColor(String status) {
    final normalized = status.toLowerCase();
    if (normalized.contains('recover') ||
        normalized.contains('complete') ||
        normalized.contains('resolved')) {
      return const Color(0xFF66BB6A);
    }
    if (normalized.contains('active') || normalized.contains('treatment')) {
      return const Color(0xFF42A5F5);
    }
    if (normalized.contains('deceased')) {
      return const Color(0xFFEF5350);
    }
    if (normalized.contains('pending')) {
      return const Color(0xFFFFB74D);
    }
    return const Color(0xFFB0BEC5);
  }

  String _formatReportedDate(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();
      return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
    if (value is DateTime) {
      return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    }
    final text = _safe(value, '');
    if (text.isEmpty) {
      return 'Report date unavailable';
    }
    return text.contains('T') ? text.split('T').first : text;
  }

  Widget _buildDivider() {
    return Container(width: 1, height: 74, color: const Color(0xFFD9E5F2));
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        decoration: BoxDecoration(
          color: _primaryAqua,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patientName = _safe(record['patientName'], 'Unknown');
    final linkedCheckupId = _safe(record['linkedCheckupId'], '-');
    final linkedPatientId = _safe(record['linkedPatientId'], 'Not linked');
    final disease = _safe(record['disease'], 'Unspecified');
    final caseClassification = _safe(
      record['caseClassification'],
      'Case classification not set',
    );
    final severity = _safe(record['severity'], 'N/A');
    final status = _safe(record['status'], 'Pending');
    final remarks = _safe(record['remarks'], 'No remarks recorded');
    final reportDateText = _formatReportedDate(record['reportedDate']);
    const rowText = Color(0xFF0B1F3A);
    const mutedText = Color(0xFF4B6075);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD9E5F2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 22,
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
                    '#${absoluteIndex + 1}  |  Check-up ID: $linkedCheckupId',
                    style: const TextStyle(
                      color: mutedText,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Linked Patient ID: $linkedPatientId',
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
            _buildDivider(),
            Expanded(
              flex: 22,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    disease,
                    style: const TextStyle(
                      color: Color(0xFFE53935),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    caseClassification,
                    style: const TextStyle(
                      color: rowText,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  remarks,
                  style: const TextStyle(
                    color: mutedText,
                    fontSize: 11,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            _buildDivider(),
            Expanded(
              flex: 16,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _severityColor(severity).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _severityColor(
                            severity,
                          ).withValues(alpha: 0.32),
                        ),
                      ),
                      child: Text(
                        severity,
                        style: TextStyle(
                          color: _severityColor(severity),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _statusColor(status).withValues(alpha: 0.32),
                        ),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: _statusColor(status),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildDivider(),
            Expanded(
              flex: 12,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  reportDateText,
                  style: const TextStyle(
                    color: mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
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
                      icon: Icons.visibility_rounded,
                      tooltip: 'View',
                      onTap: onView,
                    ),
                    const SizedBox(width: 6),
                    _buildActionButton(
                      icon: Icons.edit_rounded,
                      tooltip: 'Edit',
                      onTap: onEdit,
                    ),
                    const SizedBox(width: 6),
                    _buildActionButton(
                      icon: Icons.picture_as_pdf_rounded,
                      tooltip: 'Generate PDF',
                      onTap: onGeneratePdf,
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
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9E5F2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: Colors.white,
          style: const TextStyle(color: _lightOffWhite),
          iconEnabledColor: _primaryAqua,
          items: options
              .map(
                (option) => DropdownMenuItem<String>(
                  value: option,
                  child: Text('$label: $option'),
                ),
              )
              .toList(),
          onChanged: (newValue) {
            if (newValue != null) {
              onChanged(newValue);
            }
          },
        ),
      ),
    );
  }
}

class _PanelEmptyState extends StatelessWidget {
  final String text;

  const _PanelEmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: _mutedCoolGray, height: 1.5),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
