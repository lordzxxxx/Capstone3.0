import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/features/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/app/features/patients/patient.dart';
import 'package:mycapstone_project/app/shared/widgets/mobile_pagination_controls.dart';
import 'package:mycapstone_project/app/features/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/shared/current_table_record_utils.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';
import 'package:mycapstone_project/app/shared/widgets/health_record_card.dart';
import 'package:mycapstone_project/app/shared/widgets/mobile_compact_controls.dart';
import 'package:mycapstone_project/app/shared/widgets/mobile_record_action_sheet.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _secondaryIceBlue = AppDesign.blueSoft;
const Color _darkDeepTeal = AppDesign.page;
const Color _mutedCoolGray = AppDesign.muted;
const Color _lightOffWhite = AppDesign.ink;

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
        style: baseStyle.copyWith(color: const Color(0xFF00E5F7)),
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

class NonCommunicablePage extends StatefulWidget {
  const NonCommunicablePage({super.key});

  @override
  State<NonCommunicablePage> createState() => _NonCommunicablePageState();
}

class _NonCommunicablePageState extends State<NonCommunicablePage> {
  // State variables for metrics
  int _activeCases = 0;
  Map<String, int> _diseaseTypes = {};
  double _controlRate = 0.0;
  bool _isLoadingMetrics = false;

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Data from check-up database
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _filteredPatients = [];
  static const int _defaultRowsPerPage = 5;
  int _currentPage = 1;
  int _rowsPerPage = _defaultRowsPerPage;
  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};

  @override
  void initState() {
    super.initState();
    _dbHelper.startConnectivityListener();
    _loadMetrics();
    _loadPatients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMetrics() async {
    setState(() {
      _isLoadingMetrics = true;
    });

    try {
      // Load actual metrics from database
      final allRecords = await _dbHelper.getAllRecords();
      final nonCommunicableRecords = allRecords.where((record) {
        return record['diseaseType'] == 'Non-Communicable';
      }).toList();

      final activeCases = nonCommunicableRecords.length;
      final completedCases = nonCommunicableRecords
          .where((r) => r['status'] == 'Completed')
          .length;
      final controlRate = _calculateControlRate(activeCases, completedCases);

      setState(() {
        _activeCases = activeCases;
        _diseaseTypes = {};
        _controlRate = controlRate;
        _isLoadingMetrics = false;
      });
    } catch (e) {
      print('Error loading metrics: $e');
      setState(() {
        _isLoadingMetrics = false;
      });
    }
  }

  double _calculateControlRate(int activeCases, int completedCases) {
    if (activeCases == 0) return 0.0;
    return (completedCases / activeCases * 100);
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
      idKeys: const ['patientId'],
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
    try {
      // Sync from Firebase first
      await _dbHelper.syncFromFirebase();

      // Load non-communicable disease records from check-up database
      final allRecords = await _dbHelper.getAllRecords();

      // Filter for non-communicable diseases only
      final nonCommunicableRecords = allRecords.where((record) {
        return record['diseaseType'] == 'Non-Communicable';
      }).toList();

      final currentPatients = _collapseCurrentPatients(
        nonCommunicableRecords.map((record) {
          return {
            'id': record['id'] ?? '',
            'patientId': record['linkedPatientId'] ?? record['patientId'] ?? '',
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
        _patients = currentPatients;
        _applySearchFilter();
        _resetPagination(clearSelection: true);
      });
    } catch (e) {
      print('Error loading patients: $e');
    }
  }

  void _applySearchFilter() {
    if (_searchQuery.isEmpty) {
      _filteredPatients = List.from(_patients);
      return;
    }

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

  void _filterPatients(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      _applySearchFilter();
      _resetPagination(clearSelection: true);
    });
  }

  int get _effectiveRowsPerPage =>
      _rowsPerPage > 0 ? _rowsPerPage : _defaultRowsPerPage;

  int get _totalPages {
    final totalItems = _filteredPatients.length;
    if (totalItems == 0) {
      return 1;
    }
    return ((totalItems + _effectiveRowsPerPage - 1) ~/ _effectiveRowsPerPage);
  }

  int get _safeCurrentPage {
    if (_currentPage < 1) {
      return 1;
    }
    return _currentPage > _totalPages ? _totalPages : _currentPage;
  }

  int get _pageStartIndex {
    if (_filteredPatients.isEmpty) {
      return 0;
    }
    return (_safeCurrentPage - 1) * _effectiveRowsPerPage;
  }

  int get _pageEndIndex {
    if (_filteredPatients.isEmpty) {
      return 0;
    }
    final end = _pageStartIndex + _effectiveRowsPerPage;
    return end > _filteredPatients.length ? _filteredPatients.length : end;
  }

  List<Map<String, dynamic>> get _pagedFilteredPatients {
    if (_filteredPatients.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    return _filteredPatients.sublist(_pageStartIndex, _pageEndIndex);
  }

  void _resetPagination({bool clearSelection = false}) {
    _currentPage = 1;
    if (clearSelection) {
      _selectedIndices.clear();
      _isSelectionMode = false;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return const Color(0xFF4CAF50); // Green
      case 'pending':
        return const Color(0xFFFFC107); // Yellow
      case 'stable':
      case 'recovering':
        return const Color(0xFF4CAF50);
      case 'under treatment':
        return const Color(0xFF2196F3);
      case 'critical':
        return const Color(0xFFD84315);
      default:
        return _mutedCoolGray;
    }
  }

  Future<void> _seedNonCommunicableData() async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(color: _primaryAqua),
            SizedBox(height: 16),
            Text('Seeding 100 sample non-communicable disease records...'),
          ],
        ),
      ),
    );

    try {
      await _dbHelper.seedSampleNonCommunicableData();

      // Close loading dialog
      Navigator.of(context).pop();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Successfully seeded 100 NCD records.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      // Reload data
      await _loadMetrics();
      await _loadPatients();
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error seeding data: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkDeepTeal,
      appBar: AppBar(
        title: const Text(
          'Non-Communicable Disease Management',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppDesign.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              _showAddPatientDialog();
            },
            tooltip: 'Add Patient',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadMetrics();
              _loadPatients();
            },
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: Icon(
              _isSelectionMode
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
            ),
            onPressed: () {
              setState(() {
                _isSelectionMode = !_isSelectionMode;
                if (!_isSelectionMode) {
                  _selectedIndices.clear();
                }
              });
            },
            tooltip: _isSelectionMode
                ? 'Exit Selection Mode'
                : 'Select Multiple',
          ),
          PopupMenuButton<String>(
            onSelected: (String value) {
              if (value == 'seed') {
                _seedNonCommunicableData();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'seed',
                child: Text('Seed 100 Sample Records'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadMetrics();
          await _loadPatients();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: _buildSearchBar(),
              ),

              const SizedBox(height: 10),

              // Dashboard Overview
              _buildOverviewDashboard(),

              const SizedBox(height: 20),

              // Patient Table
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _NonCommunicableTable(
                  records: _pagedFilteredPatients,
                  startIndex: _pageStartIndex,
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
                  onEdit: _editPatient,
                  onTap: (patient) {
                    _viewHistory(patient);
                  },
                  onLongPress: _showRecordActionModal,
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: MobilePaginationControls(
                  currentPage: _safeCurrentPage,
                  totalPages: _totalPages,
                  totalItems: _filteredPatients.length,
                  startIndex: _pageStartIndex,
                  endIndex: _pageEndIndex,
                  rowsPerPage: _effectiveRowsPerPage,
                  itemLabel: 'records',
                  accentColor: _primaryAqua,
                  textColor: _lightOffWhite,
                  surfaceColor: _darkDeepTeal.withValues(alpha: 0.55),
                  onRowsPerPageChanged: (value) {
                    setState(() {
                      _rowsPerPage = value > 0 ? value : _defaultRowsPerPage;
                      _resetPagination();
                    });
                  },
                  onPreviousPage: _safeCurrentPage > 1
                      ? () {
                          setState(() {
                            _currentPage = _safeCurrentPage - 1;
                          });
                        }
                      : null,
                  onNextPage: _safeCurrentPage < _totalPages
                      ? () {
                          setState(() {
                            _currentPage = _safeCurrentPage + 1;
                          });
                        }
                      : null,
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      bottomNavigationBar: (_isSelectionMode && _selectedIndices.isNotEmpty)
          ? BottomAppBar(
              color: _darkDeepTeal,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_selectedIndices.length} selected',
                      style: const TextStyle(
                        color: _lightOffWhite,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _confirmDeleteSelected,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.delete, size: 18),
                      label: const Text('Delete'),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  // Overview Dashboard Section
  Widget _buildOverviewDashboard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'NCD Overview',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            if (_isLoadingMetrics)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            else
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Active Cases',
                          value: _activeCases.toString(),
                          icon: Icons.people,
                          color: Colors.transparent,
                          textColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Control Rate',
                          value: '${_controlRate.toStringAsFixed(1)}%',
                          icon: Icons.trending_up,
                          color: Colors.transparent,
                          textColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildDiseaseTypeCard(),
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
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: color == Colors.transparent
            ? Border.all(color: _primaryAqua.withValues(alpha: 0.3), width: 1)
            : null,
        boxShadow: color == Colors.transparent
            ? []
            : [
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

  Widget _buildDiseaseTypeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
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
              Icon(Icons.local_hospital, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Text(
                'Disease Types',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
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
                    style: TextStyle(fontSize: 14, color: Colors.white),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      entry.value.toString(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
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
    return MobileSearchField(
      controller: _searchController,
      hintText: 'Search by patient name, condition, or status...',
      onChanged: _filterPatients,
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
                color: _mutedCoolGray.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isEmpty
                    ? 'No patients found'
                    : 'No results for "$_searchQuery"',
                style: TextStyle(fontSize: 16, color: _mutedCoolGray),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _filteredPatients.map((patient) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildPatientCard(patient),
        );
      }).toList(),
    );
  }

  Widget _buildPatientCard(Map<String, dynamic> patient) {
    return GestureDetector(
      onLongPress: () => _showRecordActionModal(patient),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _primaryAqua.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Patient Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: _getStatusColor(
                      patient['currentStatus'],
                    ).withValues(alpha: 0.3),
                    child: Text(
                      patient['patientName']
                          .toString()
                          .substring(0, 1)
                          .toUpperCase(),
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
                          patient['patientName'],
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${patient['age']} years • ${patient['gender']}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
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
                      color: _getStatusColor(patient['currentStatus']),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      patient['currentStatus'],
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

            // Patient Details
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildDetailRow(
                    icon: Icons.medical_information,
                    label: 'Condition',
                    value: patient['condition'],
                    color: Colors.white,
                  ),
                  Divider(
                    height: 20,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  _buildDetailRow(
                    icon: Icons.medication,
                    label: 'Treatment',
                    value: patient['treatment'],
                    color: Colors.white,
                  ),
                  Divider(
                    height: 20,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDetailRow(
                          icon: Icons.calendar_today,
                          label: 'Last Visit',
                          value: _formatDate(patient['lastVisit']),
                          color: Colors.white,
                          isCompact: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDetailRow(
                          icon: Icons.event,
                          label: 'Next Visit',
                          value: _formatDate(patient['nextVisit']),
                          color: Colors.white,
                          isCompact: true,
                        ),
                      ),
                    ],
                  ),
                  if (patient['notes'] != null &&
                      patient['notes'].toString().isNotEmpty) ...[
                    Divider(
                      height: 20,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    _buildDetailRow(
                      icon: Icons.note,
                      label: 'Notes',
                      value: patient['notes'],
                      color: Colors.white,
                    ),
                  ],
                ],
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    icon: Icons.visibility,
                    label: 'View',
                    onTap: () => _viewPatientDetails(patient),
                  ),
                  _buildActionButton(
                    icon: Icons.edit,
                    label: 'Edit',
                    onTap: () => _editPatient(patient),
                  ),
                  _buildActionButton(
                    icon: Icons.medical_services,
                    label: 'Treatment',
                    onTap: () => _manageTreatment(patient),
                  ),
                  _buildActionButton(
                    icon: Icons.history,
                    label: 'History',
                    onTap: () => _viewHistory(patient),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool isCompact = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: isCompact ? 18 : 20, color: Colors.white),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: isCompact ? 11 : 12,
                  color: Colors.white.withValues(alpha: 0.7),
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
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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

  // Action Methods
  Future<void> _showAddPatientDialog() async {
    await Get.to(() => const PatientRecordPage(openRegistrationOnLoad: true));
  }

  void _showRecordActionModal(Map<String, dynamic> patient) {
    final patientName = (patient['patientName'] ?? '').toString().trim().isEmpty
        ? 'Record Details'
        : patient['patientName'].toString();

    MobileRecordActionSheet.show(
      context: context,
      title: patientName,
      headerIcon: Icons.person_search_rounded,
      actions: [
        MobileRecordAction(
          label: 'View Details',
          icon: Icons.visibility_outlined,
          tone: MobileRecordActionTone.primary,
          onPressed: () => _viewPatientDetails(patient),
        ),
        MobileRecordAction(
          label: 'Edit Record',
          icon: Icons.edit_outlined,
          onPressed: () => _editPatient(patient),
        ),
        MobileRecordAction(
          label: 'Manage Treatment',
          icon: Icons.medical_services_outlined,
          tone: MobileRecordActionTone.success,
          onPressed: () => _manageTreatment(patient),
        ),
        MobileRecordAction(
          label: 'View Patient History',
          icon: Icons.history_rounded,
          tone: MobileRecordActionTone.primary,
          onPressed: () => _viewHistory(patient),
        ),
      ],
    );
  }

  void _confirmDeleteSelected() {
    if (_selectedIndices.isEmpty) {
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _darkDeepTeal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: _lightOffWhite.withValues(alpha: 0.2)),
          ),
          title: const Text(
            'Delete Selected Records?',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to delete ${_selectedIndices.length} selected non-communicable record(s)?',
            style: const TextStyle(color: _lightOffWhite),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Cancel',
                style: TextStyle(color: _lightOffWhite),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _deleteSelectedRecords();
              },
              child: const Text(
                'Delete',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteSelectedRecords() async {
    if (_selectedIndices.isEmpty) {
      return;
    }

    final selectedRecords = _selectedIndices
        .where((index) => index >= 0 && index < _filteredPatients.length)
        .map((index) => _filteredPatients[index])
        .toList(growable: false);

    final idsToDelete = selectedRecords
        .map((record) => (record['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (idsToDelete.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid records selected for deletion.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await _dbHelper.deleteRecords(idsToDelete);
    await _loadMetrics();
    await _loadPatients();

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedIndices.clear();
      _isSelectionMode = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${idsToDelete.length} record(s) deleted successfully.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _viewPatientDetails(Map<String, dynamic> patient) {
    final patientName = (patient['patientName'] ?? 'Unknown').toString();
    final patientId = (patient['patientId'] ?? patient['id'] ?? 'N/A')
        .toString();
    final age = '${patient['age'] ?? 'N/A'} years';
    final gender = (patient['gender'] ?? 'N/A').toString();
    final condition = (patient['condition'] ?? 'No details').toString();
    final status = (patient['currentStatus'] ?? 'Pending').toString();
    final treatment = (patient['treatment'] ?? 'No treatment plan').toString();
    final bloodPressure = (patient['bloodPressure'] ?? 'N/A').toString();
    final bloodSugar = (patient['bloodSugar'] ?? 'N/A').toString();
    final lastVisit = (patient['lastVisit'] ?? 'N/A').toString();
    final nextVisit = (patient['nextVisit'] ?? 'N/A').toString();
    final notes = (patient['notes'] ?? '').toString();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: _darkDeepTeal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: _darkDeepTeal,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _lightOffWhite.withValues(alpha: 0.18)),
            ),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Non-Communicable Details',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _lightOffWhite,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(dialogContext),
                        child: Icon(
                          Icons.close,
                          color: _lightOffWhite.withValues(alpha: 0.7),
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildCheckupStyleDetailSection('Patient Information', [
                    _buildCheckupStyleDetailRow('Name', patientName),
                    _buildCheckupStyleDetailRow('Patient ID', patientId),
                    _buildCheckupStyleDetailRow('Age', age),
                    _buildCheckupStyleDetailRow('Gender', gender),
                  ]),
                  const SizedBox(height: 16),
                  _buildCheckupStyleDetailSection('Case Details', [
                    _buildCheckupStyleDetailRow('Condition', condition),
                    _buildCheckupStyleDetailRow('Status', status),
                    _buildCheckupStyleDetailRow('Treatment Plan', treatment),
                  ]),
                  const SizedBox(height: 16),
                  _buildCheckupStyleDetailSection('Monitoring', [
                    _buildCheckupStyleDetailRow(
                      'Blood Pressure',
                      bloodPressure,
                    ),
                    _buildCheckupStyleDetailRow('Blood Sugar', bloodSugar),
                    _buildCheckupStyleDetailRow('Last Visit', lastVisit),
                    _buildCheckupStyleDetailRow('Next Visit', nextVisit),
                    if (notes.isNotEmpty)
                      _buildCheckupStyleDetailRow('Notes', notes),
                  ]),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _editPatient(patient);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryAqua,
                            foregroundColor: _lightOffWhite,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text(
                            'Edit',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _lightOffWhite,
                            side: BorderSide(
                              color: _lightOffWhite.withValues(alpha: 0.35),
                              width: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Close',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _lightOffWhite,
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
      },
    );
  }

  Widget _buildCheckupStyleDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: _lightOffWhite.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: _buildHighlightedVitalLabelText(
              value,
              baseStyle: const TextStyle(
                fontSize: 13,
                color: _lightOffWhite,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckupStyleDetailSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _darkDeepTeal.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _lightOffWhite.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: _primaryAqua.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: _lightOffWhite,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _lightOffWhite.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _lightOffWhite.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  void _editPatient(Map<String, dynamic> patient) {
    Get.snackbar(
      'Edit Patient',
      'Editing ${patient['patientName']}',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: const Color(0xFF7B1FA2),
      colorText: Colors.white,
    );
  }

  void _manageTreatment(Map<String, dynamic> patient) {
    Get.snackbar(
      'Manage Treatment',
      'Treatment plan for ${patient['patientName']}',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: const Color(0xFF4CAF50),
      colorText: Colors.white,
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
}

class _NonCommunicableTable extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final int startIndex;
  final bool isSelectionMode;
  final Set<int> selectedIndices;
  final Function(int, bool) onSelectionChanged;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>) onTap;
  final Function(Map<String, dynamic>) onLongPress;

  const _NonCommunicableTable({
    required this.records,
    required this.startIndex,
    required this.isSelectionMode,
    required this.selectedIndices,
    required this.onSelectionChanged,
    required this.onEdit,
    required this.onTap,
    required this.onLongPress,
  });

  String _getInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (parts.isEmpty) {
      return 'P';
    }
    return parts[0][0].toUpperCase();
  }

  Color _getAvatarColor(int index) {
    final colors = [
      AppDesign.nonCommunicable,
      const Color(0xFF1E5A7A),
      const Color(0xFFFF6B6B),
      const Color(0xFF4ECDC4),
      const Color(0xFFFFBE5B),
      const Color(0xFF845EC2),
    ];
    return colors[index % colors.length];
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'stable':
      case 'recovering':
      case 'controlled':
        return Colors.green;
      case 'under treatment':
      case 'process':
        return Colors.blue;
      case 'critical':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(
                Icons.person_off,
                size: 64,
                color: _mutedCoolGray.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'No records found.',
                style: TextStyle(
                  color: _mutedCoolGray,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: records.length,
      itemBuilder: (context, index) {
        final absoluteIndex = startIndex + index;
        final record = records[index];
        final patientName =
            (record['patientName'] ?? 'Unknown').toString().trim().isEmpty
            ? 'Unknown'
            : record['patientName'].toString();
        final condition = (record['condition'] ?? 'No details').toString();
        final age = (record['age'] ?? 'N/A').toString();
        final status = (record['currentStatus'] ?? 'Pending').toString();
        final lastVisit = (record['lastVisit'] ?? 'N/A').toString();
        final statusColor = _getStatusColor(status);
        final isSelected = selectedIndices.contains(absoluteIndex);

        return HealthRecordCard(
          recordLabel: 'Non-communicable disease',
          patientName: patientName,
          location:
              record['barangay']?.toString() ??
              record['address']?.toString() ??
              'Location not recorded',
          accentColor: AppDesign.nonCommunicable,
          status: status,
          secondaryStatus:
              record['referralStatus']?.toString() ??
              record['referral_status']?.toString(),
          isSelected: isSelected,
          showSelection: isSelectionMode,
          onSelectionChanged: (selected) =>
              onSelectionChanged(absoluteIndex, selected),
          onTap: () {
            if (isSelectionMode) {
              onSelectionChanged(absoluteIndex, !isSelected);
            } else {
              onTap(record);
            }
          },
          onLongPress: () => onLongPress(record),
          onAction: () => onEdit(record),
          metadata: [
            RecordMetadata(label: 'Age', value: age, icon: Icons.cake_outlined),
            RecordMetadata(
              label: 'Recorded condition',
              value: condition,
              icon: Icons.biotech_outlined,
              emphasize: true,
            ),
            RecordMetadata(
              label: 'Date recorded',
              value: HealthRecordDate.format(
                record['dateReported'] ?? record['date'],
              ),
              icon: Icons.event_outlined,
            ),
            RecordMetadata(
              label: 'Monitoring status',
              value: record['monitoringStatus']?.toString() ?? status,
              icon: Icons.monitor_heart_outlined,
            ),
            RecordMetadata(
              label: 'Last check-up',
              value: HealthRecordDate.format(lastVisit),
              icon: Icons.history_rounded,
            ),
            RecordMetadata(
              label: 'Next follow-up',
              value: HealthRecordDate.format(
                record['nextFollowUp'] ?? record['followUpDate'],
              ),
              icon: Icons.event_repeat_outlined,
            ),
            RecordMetadata(
              label: 'Risk level',
              value: record['riskLevel']?.toString() ?? 'Not recorded',
              icon: Icons.warning_amber_rounded,
            ),
          ],
        );

        // ignore: dead_code
        return GestureDetector(
          onTap: () {
            if (isSelectionMode) {
              onSelectionChanged(absoluteIndex, !isSelected);
            } else {
              onTap(record);
            }
          },
          onLongPress: () => onLongPress(record),
          child: Card(
            elevation: 2,
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? _primaryAqua
                      : _lightOffWhite.withValues(alpha: 0.3),
                  width: isSelected ? 2.5 : 1.5,
                ),
                color: isSelected ? _primaryAqua.withValues(alpha: 0.08) : null,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    if (isSelectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isSelected
                                  ? _primaryAqua
                                  : _lightOffWhite.withValues(alpha: 0.5),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            color: isSelected
                                ? _primaryAqua
                                : Colors.transparent,
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 16,
                                )
                              : null,
                        ),
                      ),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _getAvatarColor(absoluteIndex),
                      ),
                      child: Center(
                        child: Text(
                          _getInitials(patientName),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _lightOffWhite,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          _buildHighlightedVitalLabelText(
                            condition,
                            baseStyle: TextStyle(
                              fontSize: 14,
                              color: _lightOffWhite.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Age: ',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: _lightOffWhite.withValues(
                                            alpha: 0.7,
                                          ),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextSpan(
                                        text: age,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: _lightOffWhite,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Visit: ',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: _lightOffWhite.withValues(
                                            alpha: 0.7,
                                          ),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextSpan(
                                        text: lastVisit,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: _lightOffWhite,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.35),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        IconButton(
                          tooltip: 'Edit Record',
                          onPressed: () => onEdit(record),
                          icon: const Icon(
                            Icons.edit,
                            color: _primaryAqua,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
