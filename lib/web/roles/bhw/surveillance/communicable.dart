import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'package:mycapstone_project/web/roles/bhw/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/shared/components/fullscreen_detail_table_dialog.dart';
import 'package:mycapstone_project/web/shared/components/module_view_components.dart';
import 'package:mycapstone_project/web/shared/components/web_data_components.dart';
import 'package:mycapstone_project/web/shared/components/web_responsive_body.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/shared/current_table_record_utils.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/communicable_insights.dart';
import 'package:mycapstone_project/web/shared/widgets/web_sync_status_badge.dart';

const Color _primaryAqua = Color(0xFF2F80ED);
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
        style: baseStyle.copyWith(
          color: const Color(0xFF2F80ED),
          fontWeight: FontWeight.w700,
        ),
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

class CommunicablePage extends StatefulWidget {
  const CommunicablePage({super.key});

  @override
  State<CommunicablePage> createState() => _CommunicablePageState();
}

class _CommunicablePageState extends State<CommunicablePage> {
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
  List<Map<String, dynamic>> _chronicCarePatients = [];
  List<Map<String, dynamic>> _filteredPatients = [];
  List<Map<String, dynamic>> _communicableRecords = [];

  @override
  void initState() {
    super.initState();
    _selectedView = healthModuleViewFromUrl();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => persistHealthModuleView(WebRoutes.bhwCommunicable, _resolvedView),
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
    persistHealthModuleView(WebRoutes.bhwCommunicable, view);
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

  String _extractVital(String details, String vitalName) {
    final regex = RegExp('$vitalName: ([^,|]+)');
    final match = regex.firstMatch(details);
    return match?.group(1)?.trim() ?? 'N/A';
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

      // Load communicable disease records from check-up database
      final allRecords = await _dbHelper.getAllRecords();

      // Filter for communicable diseases only
      final communicableRecords = allRecords.where((record) {
        final type = (record['diseaseType'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        return type == 'communicable' || type == 'communicable disease';
      }).toList();

      final currentPatients = _collapseCurrentPatients(
        communicableRecords.map((record) {
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
            'bloodSugar':
                record['bloodSugar'] ??
                _extractVital(record['details'] ?? '', 'Temp'),
            'bloodPressure':
                record['bloodPressure'] ??
                _extractVital(record['details'] ?? '', 'BP'),
            'totalVisits': record['totalVisits'] ?? 0,
          };
        }).toList(),
      );

      setState(() {
        _communicableRecords = communicableRecords;
        _chronicCarePatients = currentPatients;
        _filteredPatients = List.from(_chronicCarePatients);
        _currentPage = 1;
        _isLoadingMetrics = false;
      });
    } catch (e) {
      debugPrint('Error loading patients: $e');
      if (mounted) {
        setState(() => _isLoadingMetrics = false);
      }
    }
  }

  void _filterPatients(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredPatients = List.from(_chronicCarePatients);
      } else {
        _filteredPatients = _chronicCarePatients.where((patient) {
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
        lower.contains('recovered')) {
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
      body: WebResponsiveBody(
        sidebar: WebAppSidebar(
          userName: userName,
          activeItem: WebSidebarItem.communicable,
        ),
        title: 'Communicable Diseases',
        child: RefreshIndicator(
          backgroundColor: const Color(0xFFF5F7FA),
          color: _primaryAqua,
          onRefresh: () async {
            await _loadPatients();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HealthModuleViewHeader(
                  title: 'Communicable Disease Management',
                  description:
                      'Review disease trends and case outcomes, or manage individual communicable records.',
                  activeView: _resolvedView,
                  onViewChanged: _setActiveView,
                  primaryColor: _primaryAqua,
                  recordsLabel: 'List of Records',
                  actions: _resolvedView == HealthModuleView.insights
                      ? const []
                      : [
                          if (!_isSelectionMode)
                            IconButton(
                              icon: const Icon(Icons.checklist_rounded),
                              tooltip: 'Select records to delete',
                              color: _primaryAqua,
                              onPressed: () =>
                                  setState(() => _isSelectionMode = true),
                            ),
                        ],
                ),
                const SizedBox(height: 20),
                if (_resolvedView != HealthModuleView.insights &&
                    _isSelectionMode) ...[
                  _buildSelectionToolbar(),
                  const SizedBox(height: 16),
                ],
                if (_resolvedView == HealthModuleView.insights)
                  if (_isLoadingMetrics)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(color: _primaryAqua),
                      ),
                    )
                  else if (_communicableRecords.isEmpty)
                    const ModuleEmptyState(
                      title: 'No communicable insights yet',
                      message:
                          'Communicable analytics will appear after records are saved in Firebase.',
                      icon: Icons.coronavirus_outlined,
                    )
                  else
                    CommunicableInsights(records: _communicableRecords)
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
    );
  }

  Widget _buildSelectionToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Text(
            '${_getSelectedPatientIds.length} selected',
            style: const TextStyle(
              color: Color(0xFF0B1F3A),
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.select_all_rounded),
            tooltip: 'Select all',
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
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded),
            tooltip: 'Delete selected',
            color: _getSelectedPatientIds.isEmpty
                ? Colors.grey
                : Colors.redAccent,
            onPressed: _getSelectedPatientIds.isEmpty
                ? null
                : _showDeleteConfirmationModal,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel selection',
            onPressed: () {
              setState(() {
                _isSelectionMode = false;
                _getSelectedPatientIds.clear();
              });
            },
          ),
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
        Column(
          children: [
            _buildPatientTableHeader(),
            ...pagedPatients.map(_buildPatientCard),
          ],
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
          softWrap: true,
        ),
      ),
    );
  }

  Widget _buildPatientTableHeaderDivider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      color: const Color(0xFFD9E5F2),
    );
  }

  Widget _buildPatientTableHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          _buildPatientTableHeaderCell('Patient Details', flex: 24),
          _buildPatientTableHeaderDivider(),
          _buildPatientTableHeaderCell('Case Summary', flex: 34),
          _buildPatientTableHeaderDivider(),
          _buildPatientTableHeaderCell('Visit Schedule', flex: 18),
          _buildPatientTableHeaderDivider(),
          _buildPatientTableHeaderCell('Status', flex: 14),
          if (!_isSelectionMode) ...[
            _buildPatientTableHeaderDivider(),
            SizedBox(
              width: 140,
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
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      color: const Color(0xFF26476B),
    );
  }

  Widget _buildTableDetailBlock({
    required String label,
    required String value,
    required TextStyle valueStyle,
    IconData? icon,
    Color? iconColor,
  }) {
    final displayValue = value.trim().isEmpty ? 'N/A' : value.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: iconColor ?? AppColors.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _buildHighlightedVitalLabelText(displayValue, baseStyle: valueStyle),
      ],
    );
  }

  Widget _buildVisitScheduleBlock({
    required String label,
    required String value,
    required Color valueColor,
    IconData? icon,
    Color? iconColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: iconColor ?? AppColors.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value.trim().isEmpty ? 'N/A' : value.trim(),
          style: TextStyle(
            color: valueColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          softWrap: true,
        ),
      ],
    );
  }

  Widget _buildTableActionButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    Color backgroundColor = const Color(0xFF163B66),
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
    final patientId =
        patient['id']?.toString() ??
        patient['patientId']?.toString() ??
        patient['linkedPatientId']?.toString() ??
        '';
    final isSelected =
        patientId.isNotEmpty && _getSelectedPatientIds.contains(patientId);
    final patientName =
        (patient['patientName'] ??
                patient['name'] ??
                patient['patient'] ??
                patient['fullName'])
            ?.toString() ??
        'Unknown Patient';
    final age = (patient['age'])?.toString() ?? 'N/A';
    final gender =
        (patient['gender'] ?? patient['sex'])?.toString() ?? 'Unknown';
    final condition =
        (patient['condition'] ??
                patient['disease'] ??
                patient['diagnosis'] ??
                patient['caseClassification'])
            ?.toString()
            .trim() ??
        'No details';
    final treatment =
        (patient['treatment'] ??
                patient['medication'] ??
                patient['plan'] ??
                patient['remarks'])
            ?.toString()
            .trim() ??
        'No treatment plan';
    final lastVisit = _formatDate(
      patient['lastVisit'] ??
          patient['date'] ??
          patient['lastCheckup'] ??
          patient['consultationDate'] ??
          patient['createdAt'],
    );
    final nextVisit = _formatDate(
      patient['nextVisit'] ??
          patient['nextAppointment'] ??
          patient['followUpDate'],
    );
    final status =
        (patient['currentStatus'] ?? patient['status'])?.toString() ??
        'Pending';
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
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  flex: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patientName,
                        style: const TextStyle(
                          color: rowText,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                        softWrap: true,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$gender • $age yrs',
                        style: const TextStyle(
                          color: mutedText,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        softWrap: true,
                      ),
                      if (patientId.isNotEmpty) ...[
                        const SizedBox(height: 6),
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
                            softWrap: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _buildPatientRowDivider(),
                Expanded(
                  flex: 34,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTableDetailBlock(
                        label: 'CONDITION',
                        value: condition.isEmpty ? 'No details' : condition,
                        icon: Icons.coronavirus_outlined,
                        iconColor: _primaryAqua,
                        valueStyle: const TextStyle(
                          color: rowText,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildTableDetailBlock(
                        label: 'TREATMENT PLAN',
                        value: treatment.isEmpty
                            ? 'No treatment plan'
                            : treatment,
                        icon: Icons.medication_outlined,
                        iconColor: AppColors.textSecondary,
                        valueStyle: const TextStyle(
                          color: mutedText,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildPatientRowDivider(),
                Expanded(
                  flex: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildVisitScheduleBlock(
                        label: 'LAST VISIT',
                        value: lastVisit,
                        icon: Icons.calendar_today_outlined,
                        iconColor: _primaryAqua,
                        valueColor: rowText,
                      ),
                      const SizedBox(height: 8),
                      _buildVisitScheduleBlock(
                        label: 'NEXT VISIT',
                        value: nextVisit,
                        icon: Icons.event_repeat_rounded,
                        iconColor: const Color(0xFFE67E22),
                        valueColor: mutedText,
                      ),
                    ],
                  ),
                ),
                _buildPatientRowDivider(),
                Expanded(
                  flex: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
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
                          softWrap: true,
                        ),
                      ),
                      const SizedBox(height: 6),
                      WebSyncStatusBadge(record: patient),
                    ],
                  ),
                ),
                if (!_isSelectionMode) ...[
                  _buildPatientRowDivider(),
                  Padding(
                    padding: const EdgeInsets.only(left: 8, right: 2),
                    child: SizedBox(
                      width: 140,
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildTableActionButton(
                              icon: Icons.visibility_rounded,
                              tooltip: 'View Details',
                              onTap: () => _viewPatientDetails(patient),
                            ),
                            const SizedBox(width: 6),
                            _buildTableActionButton(
                              icon: Icons.edit_rounded,
                              tooltip: 'Edit Record',
                              onTap: () => _editPatient(patient),
                            ),
                            const SizedBox(width: 6),
                            _buildTableActionButton(
                              icon: Icons.history_rounded,
                              tooltip: 'View History',
                              onTap: () => _viewHistory(patient),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
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

  String _formatDate(dynamic dateValue) {
    final dt = _parseDateTime(dateValue);
    if (dt == null) {
      final raw = (dateValue ?? '').toString().trim();
      return raw.isEmpty ? 'N/A' : raw;
    }
    return DateFormat('MMMM d, yyyy').format(dt);
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
        final patient = _chronicCarePatients.firstWhere(
          (p) => p['id'] == patientId,
          orElse: () => {},
        );

        if (patient.isNotEmpty) {
          // Delete from database
          await _dbHelper.deleteRecord(patientId);

          // Remove from local lists
          _chronicCarePatients.removeWhere((p) => p['id'] == patientId);
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
      debugPrint('Error deleting patients: $e');
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

  void _viewPatientDetails(Map<String, dynamic> patient) {
    final ageText = detailText(patient['age']);

    showFullscreenDetailTableDialog(
      context: context,
      title: 'Communicable Details',
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
          icon: Icons.coronavirus_outlined,
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
      ],
    );
    return;
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
                        patient['gender'] = genderController.text;
                        patient['condition'] = conditionController.text;
                        patient['currentStatus'] = statusController.text;
                        patient['treatment'] = treatmentController.text;
                        patient['bloodPressure'] = bloodPressureController.text;
                        patient['bloodSugar'] = bloodSugarController.text;
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
              'communicable',
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
      moduleTitle: 'Communicable',
      seedRecord: patient,
      history: history,
      description:
          'Review earlier communicable visits for this patient before creating or updating the next case record.',
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
}
