import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/features/immunization/immunization_database_helper.dart';
import 'package:mycapstone_project/app/shared/widgets/mobile_pagination_controls.dart';
import 'dart:math' as math;
import 'package:mycapstone_project/shared/current_table_record_utils.dart';
import 'package:mycapstone_project/app/shared/widgets/ocr_record_action.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';
import 'package:mycapstone_project/app/shared/widgets/app_metric_card.dart';
import 'package:mycapstone_project/app/shared/widgets/health_record_card.dart';
import 'package:mycapstone_project/app/shared/widgets/mobile_compact_controls.dart';
import 'package:mycapstone_project/app/shared/widgets/mobile_record_action_sheet.dart';
import 'package:mycapstone_project/shared/widgets/spring_data_motion.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _darkDeepTeal = AppDesign.page;
const Color _mutedCoolGray = AppDesign.muted;
const Color _lightOffWhite = AppDesign.ink;
const Color _historyBackground = Color(0xFFF8FAFC);
const Color _historySurface = Colors.white;
const Color _historyAccent = Color(0xFF2563EB);
const Color _historyText = Color(0xFF0F172A);
const Color _historyMuted = Color(0xFF4B6075);
const Color _historyBorder = Color(0xFFE2E8F0);

class ImmunizationPage extends StatefulWidget {
  const ImmunizationPage({super.key});

  @override
  State<ImmunizationPage> createState() => _ImmunizationPageState();
}

class _ImmunizationPageState extends State<ImmunizationPage> {
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

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  DateTime? _fromDate;
  DateTime? _toDate;

  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};
  bool _isDeleteDialogShowing = false;
  bool _isLoading = true;

  // Database-backed immunization records
  List<Map<String, dynamic>> _immunizationRecords = [];
  final ImmunizationDatabaseHelper _dbHelper =
      ImmunizationDatabaseHelper.instance;
  static const int _defaultRowsPerPage = 5;
  int _currentPage = 1;
  int _rowsPerPage = _defaultRowsPerPage;

  @override
  void initState() {
    super.initState();
    _loadRecords();
    _dbHelper.startConnectivityListener();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _seedSampleData() async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Seeding 100 sample immunization records...'),
          ],
        ),
      ),
    );

    try {
      await _dbHelper.seedSampleImmunizationData();

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Reload records
      await _loadRecords();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Successfully added 100 sample immunization records.',
            ),
            backgroundColor: _primaryAqua,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error seeding data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
      _immunizationRecords = updatedRecords;
      _isLoading = false;
    });
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
    final lastAdministration = _formatDate(
      (latestRecord['administrationDate'] ?? '').toString(),
    );
    final nextDose = _formatDate(
      (latestRecord['nextDoseDueDate'] ?? '').toString(),
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: _historyBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.86,
            ),
            decoration: BoxDecoration(
              color: _historyBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _historyBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _historySurface,
                    border: Border(bottom: BorderSide(color: _historyBorder)),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.history,
                        color: _historyAccent,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              patientName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: _historyText,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              patientId.isEmpty
                                  ? 'Immunization history'
                                  : 'Patient ID: $patientId',
                              style: TextStyle(
                                color: _historyMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: _historyAccent),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final cardItems = [
                            (
                              icon: Icons.vaccines,
                              label: 'Latest Vaccine',
                              value: latestVaccine,
                            ),
                            (
                              icon: Icons.event,
                              label: 'Last Immunized',
                              value: lastAdministration,
                            ),
                            (
                              icon: Icons.update,
                              label: 'Next Dose Due',
                              value: nextDose,
                            ),
                            (
                              icon: Icons.list_alt,
                              label: 'History Entries',
                              value: '${history.length}',
                            ),
                          ];

                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: cardItems.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                  childAspectRatio: constraints.maxWidth < 420
                                      ? 1.45
                                      : 1.7,
                                ),
                            itemBuilder: (context, index) {
                              final item = cardItems[index];
                              return _buildDetailSummaryCard(
                                icon: item.icon,
                                label: item.label,
                                value: item.value,
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            'Recorded immunization history',
                            style: Theme.of(dialogContext).textTheme.titleMedium
                                ?.copyWith(
                                  color: _historyText,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(width: 10),
                          _buildStatusChip(latestStatus),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Review previous immunizations before adding another dose for this patient.',
                        style: TextStyle(color: _historyMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: history.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No previous immunization history found for this patient.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _historyMuted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          itemCount: history.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final historyRecord = history[index];
                            final vaccine =
                                (historyRecord['vaccine'] ?? 'Unknown vaccine')
                                    .toString();
                            final administrationDate = _formatDate(
                              (historyRecord['administrationDate'] ?? '')
                                  .toString(),
                            );
                            final nextDoseDue = _formatDate(
                              (historyRecord['nextDoseDueDate'] ?? '')
                                  .toString(),
                            );
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
                            final hasAdverseEvents =
                                adverseEvents.trim().isNotEmpty &&
                                adverseEvents.toLowerCase() != 'none' &&
                                adverseEvents.toLowerCase() != 'none reported';

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _showRecordDetails(
                                  dialogContext,
                                  historyRecord,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: _historySurface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: _historyBorder),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              vaccine,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: _historyText,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          _buildStatusChip(status),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 8,
                                        children: [
                                          _buildHistoryMetaText(
                                            'Given',
                                            administrationDate,
                                          ),
                                          _buildHistoryMetaText(
                                            'Next dose',
                                            nextDoseDue,
                                          ),
                                          _buildHistoryMetaText(
                                            'By',
                                            administeredBy,
                                          ),
                                        ],
                                      ),
                                      if (hasAdverseEvents) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Adverse events: $adverseEvents',
                                          style: TextStyle(
                                            color: const Color(0xFFB45309),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailSummaryCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _historySurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _historyBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _primaryAqua, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _historyAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryMetaText(String label, String value) {
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
    return Scaffold(
      backgroundColor: _darkDeepTeal,
      appBar: AppBar(
        backgroundColor: AppDesign.navy,
        elevation: 0,
        title: Text(
          'Immunization Records',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              PopupMenuItem(
                child: const Text('Seed Sample Data'),
                onTap: () => _seedSampleData(),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton:
          (_isDeleteDialogShowing ||
              (_isSelectionMode && _selectedIndices.isNotEmpty))
          ? null
          : RecordCreationFabGroup(
              moduleLabel: 'Immunization',
              manualLabel: 'New Immunization',
              onManualCreate: () => _showNewImmunizationModal(context),
              onOcrReady: (extraction) async {
                _showNewImmunizationModal(
                  context,
                  patientSeed: extraction.toFormSeed(),
                );
              },
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryAqua))
          : Stack(
              children: [
                SingleChildScrollView(
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 1600),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Search Bar with Burger Menu and Vaccine Filter
                            _buildImmunizationSearchAndFilterBar(),
                            const SizedBox(height: 16),

                            // Immunization Records Table
                            SpringDataMotion(
                              dataKey: _pagedFilteredRecords,
                              child: _ImmunizationTable(
                                records: _pagedFilteredRecords,
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
                                onEdit: (record) {
                                  _showEditImmunizationModal(context, record);
                                },
                                onTap: (record) {
                                  _showPatientImmunizationHistory(
                                    context,
                                    record,
                                  );
                                },
                                onLongPress: (record) {
                                  _showRecordActionModal(context, record);
                                },
                              ),
                            ),
                            MobilePaginationControls(
                              currentPage: _safeCurrentPage,
                              totalPages: _totalPages,
                              totalItems: _getFilteredRecords().length,
                              startIndex: _pageStartIndex,
                              endIndex: _pageEndIndex,
                              rowsPerPage: _effectiveRowsPerPage,
                              itemLabel: 'records',
                              accentColor: _primaryAqua,
                              textColor: _lightOffWhite,
                              surfaceColor: _darkDeepTeal.withValues(
                                alpha: 0.55,
                              ),
                              onRowsPerPageChanged: (value) {
                                setState(() {
                                  _rowsPerPage = value > 0
                                      ? value
                                      : _defaultRowsPerPage;
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
                            const SizedBox(height: 80),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                _buildSelectionActionCard(),
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
        try {
          final dueDate = DateTime.parse(record['date']?.toString() ?? '');
          if (_fromDate != null && dueDate.isBefore(_fromDate!)) {
            dateMatch = false;
          }
          if (_toDate != null && dueDate.isAfter(_toDate!)) {
            dateMatch = false;
          }
        } catch (e) {
          dateMatch = true;
        }
      }

      // Search filter by patient name, vaccine, or patient ID
      bool searchMatch = true;
      if (_searchQuery.isNotEmpty) {
        final patientName = (record['patientName'] ?? '')
            .toString()
            .toLowerCase();
        final vaccine = (record['vaccine'] ?? '').toString().toLowerCase();
        final patientId = (record['patientId'] ?? '').toString().toLowerCase();
        searchMatch =
            patientName.contains(_searchQuery) ||
            vaccine.contains(_searchQuery) ||
            patientId.contains(_searchQuery);
      }

      return vaccineMatch && dateMatch && searchMatch;
    }).toList();

    return CurrentTableRecordUtils.collapseToLatestPerEntity(
      filtered,
      idKeys: const ['patientId'],
      nameKeys: const ['patientName'],
      dateKeys: const ['administrationDate', 'date', 'time'],
      extraIdentityKeys: const ['contactNumber'],
    );
  }

  int get _effectiveRowsPerPage =>
      _rowsPerPage > 0 ? _rowsPerPage : _defaultRowsPerPage;

  int get _totalPages {
    final filteredCount = _getFilteredRecords().length;
    if (filteredCount == 0) {
      return 1;
    }
    return ((filteredCount + _effectiveRowsPerPage - 1) ~/
        _effectiveRowsPerPage);
  }

  int get _safeCurrentPage {
    if (_currentPage < 1) {
      return 1;
    }
    return _currentPage > _totalPages ? _totalPages : _currentPage;
  }

  int get _pageStartIndex {
    final filteredRecords = _getFilteredRecords();
    if (filteredRecords.isEmpty) {
      return 0;
    }
    return (_safeCurrentPage - 1) * _effectiveRowsPerPage;
  }

  int get _pageEndIndex {
    final filteredRecords = _getFilteredRecords();
    if (filteredRecords.isEmpty) {
      return 0;
    }
    return math.min(
      _pageStartIndex + _effectiveRowsPerPage,
      filteredRecords.length,
    );
  }

  List<Map<String, dynamic>> get _pagedFilteredRecords {
    final filteredRecords = _getFilteredRecords();
    if (filteredRecords.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    return filteredRecords
        .sublist(_pageStartIndex, _pageEndIndex)
        .map(_buildDisplayRecord)
        .toList();
  }

  void _resetPagination({bool clearSelection = false}) {
    _currentPage = 1;
    if (clearSelection) {
      _selectedIndices.clear();
      _isSelectionMode = false;
    }
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
        _resetPagination(clearSelection: true);
      });
    }
  }

  void _clearDateFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _resetPagination(clearSelection: true);
    });
  }

  Widget _buildImmunizationSearchAndFilterBar() {
    return Column(
      children: [
        // Search Bar with Burger Menu
        Row(
          children: [
            // Burger Menu Button
            Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _lightOffWhite.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _primaryAqua.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: PopupMenuButton(
                color: _darkDeepTeal,
                icon: Icon(Icons.menu, color: _lightOffWhite, size: 24),
                onSelected: (value) {
                  switch (value) {
                    case 'all':
                      setState(() {
                        _selectedVaccineFilter = 'All Vaccines';
                        _searchController.clear();
                        _searchQuery = '';
                        _resetPagination(clearSelection: true);
                      });
                      break;
                    case 'clear':
                      setState(() {
                        _fromDate = null;
                        _toDate = null;
                        _selectedVaccineFilter = 'All Vaccines';
                        _searchController.clear();
                        _searchQuery = '';
                        _resetPagination(clearSelection: true);
                      });
                      break;
                    case 'seed':
                      _seedSampleData();
                      break;
                  }
                },
                itemBuilder: (BuildContext context) => [
                  PopupMenuItem<String>(
                    value: 'all',
                    child: Text(
                      'Show All Records',
                      style: TextStyle(color: _lightOffWhite),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'clear',
                    child: Text(
                      'Clear All Filters',
                      style: TextStyle(color: _lightOffWhite),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'seed',
                    child: Text(
                      'Seed 100 Sample Records',
                      style: TextStyle(color: Color(0xFFF39C12)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Search Bar
            Expanded(
              child: MobileSearchField(
                controller: _searchController,
                hintText: 'Search by patient name, vaccine, or patient ID...',
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                    _resetPagination(clearSelection: true);
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Vaccine Filter Dropdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppDesign.navy, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _primaryAqua.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: DropdownButton<String>(
            value: _selectedVaccineFilter,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            dropdownColor: Colors.white,
            iconEnabledColor: AppDesign.navy,
            items: _vaccineFilterOptions.map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(
                  value,
                  style: TextStyle(
                    color: _lightOffWhite,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedVaccineFilter = newValue;
                  _resetPagination(clearSelection: true);
                });
              }
            },
          ),
        ),
      ],
    );
  }

  void _showNewImmunizationModal(
    BuildContext context, {
    Map<String, dynamic>? patientSeed,
  }) {
    // Controllers
    final firstNameController = TextEditingController();
    final surnameController = TextEditingController();
    final patientIdController = TextEditingController();
    final ageController = TextEditingController();
    final contactNumberController = TextEditingController();
    final vaccineBrandController = TextEditingController();
    final batchNumberController = TextEditingController();
    final doseNumberController = TextEditingController();
    final administeredByController = TextEditingController();
    final adverseEventsController = TextEditingController();

    String selectedVaccineType = _normalizeVaccineType(
      patientSeed != null ? patientSeed['vaccine'] : null,
    );
    String selectedRouteOfAdministration = 'Intramuscular (IM)';
    String selectedInjectionSite = 'Left Upper Arm';
    DateTime? expirationDate;
    DateTime? administrationDate = DateTime.now();
    TimeOfDay? administrationTime = TimeOfDay.now();
    DateTime? nextDoseDueDate;

    if (patientSeed != null) {
      final directFirstName = (patientSeed['firstName'] ?? '')
          .toString()
          .trim();
      final directSurname = (patientSeed['surname'] ?? '').toString().trim();
      if (directFirstName.isNotEmpty || directSurname.isNotEmpty) {
        firstNameController.text = directFirstName;
        surnameController.text = directSurname;
      } else {
        final seededName =
            (patientSeed['patientName'] ??
                    patientSeed['fullName'] ??
                    patientSeed['patient'] ??
                    patientSeed['name'] ??
                    '')
                .toString()
                .trim();
        final nameParts = seededName.isEmpty
            ? <String>[]
            : seededName.split(' ');
        firstNameController.text = nameParts.isNotEmpty ? nameParts.first : '';
        surnameController.text = nameParts.length > 1
            ? nameParts.sublist(1).join(' ')
            : '';
      }
      patientIdController.text = (patientSeed['patientId'] ?? '').toString();
      ageController.text = (patientSeed['age'] ?? '').toString();
      contactNumberController.text = (patientSeed['contactNumber'] ?? '')
          .toString();
      if (patientSeed['doseNumber'] != null || patientSeed['dose'] != null) {
        doseNumberController.text =
            (patientSeed['doseNumber'] ?? patientSeed['dose'] ?? '').toString();
      }
      if (patientSeed['vaccineBrand'] != null) {
        vaccineBrandController.text = patientSeed['vaccineBrand'].toString();
      }
      if (patientSeed['batchNumber'] != null) {
        batchNumberController.text = patientSeed['batchNumber'].toString();
      }
      if (patientSeed['administeredBy'] != null) {
        administeredByController.text = patientSeed['administeredBy']
            .toString();
      }
    }

    final modalTitle = patientSeed == null
        ? 'New Immunization Record'
        : 'Add Another Immunization';
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height,
            decoration: const BoxDecoration(
              color: _darkDeepTeal,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // Modal Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _darkDeepTeal,
                    border: Border(
                      bottom: BorderSide(
                        color: _lightOffWhite.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: _lightOffWhite),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.vaccines,
                          color: _lightOffWhite,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            modalTitle,
                            style: const TextStyle(
                              color: _lightOffWhite,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Form Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: formKey,
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
                                            administrationTime ??
                                            TimeOfDay.now(),
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
                              validator: (value) =>
                                  value == null || value.isEmpty
                                  ? 'Required'
                                  : null,
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

                                // Create new immunization record
                                final newRecord = {
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
                                  'status': 'Completed',
                                  'date':
                                      administrationDate?.toIso8601String() ??
                                      '',
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
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
                ),
              ],
            ),
          );
        },
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _lightOffWhite.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _lightOffWhite, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              color: _lightOffWhite,
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
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _lightOffWhite.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [],
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
    String? Function(String?)? validator,
  }) {
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
          validator: validator,
          style: TextStyle(
            color: _lightOffWhite,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.4),
              fontSize: 14,
              fontWeight: FontWeight.normal,
            ),
            prefixIcon: Icon(icon, color: _lightOffWhite, size: 20),
            filled: true,
            fillColor: Colors.transparent,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _lightOffWhite.withValues(alpha: 0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _lightOffWhite.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _primaryAqua, width: 2),
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
            color: _lightOffWhite,
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
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: date != null
                    ? _lightOffWhite
                    : _lightOffWhite.withValues(alpha: 0.3),
                width: date != null ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: _lightOffWhite, size: 20),
                const SizedBox(width: 12),
                Text(
                  date != null
                      ? '${date.day}/${date.month}/${date.year}'
                      : 'Select Date',
                  style: TextStyle(
                    color: _lightOffWhite,
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
            color: _lightOffWhite,
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
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: time != null
                    ? _lightOffWhite
                    : _lightOffWhite.withValues(alpha: 0.3),
                width: time != null ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: _lightOffWhite, size: 20),
                const SizedBox(width: 12),
                Text(
                  time != null ? time.format(context) : 'Select Time',
                  style: TextStyle(
                    color: _lightOffWhite,
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
            color: _lightOffWhite,
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
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: time != null
                    ? _lightOffWhite
                    : _lightOffWhite.withValues(alpha: 0.3),
                width: time != null ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: _lightOffWhite, size: 20),
                const SizedBox(width: 12),
                Text(
                  time != null ? time.format(context) : 'Select Time',
                  style: TextStyle(
                    color: _lightOffWhite,
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
            color: _lightOffWhite,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _lightOffWhite.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, color: _lightOffWhite, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: safeValue,
                    isExpanded: true,
                    icon: Icon(Icons.arrow_drop_down, color: _lightOffWhite),
                    style: TextStyle(
                      color: _lightOffWhite,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    items: sanitizedItems.map((String item) {
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
                    borderRadius: BorderRadius.circular(12),
                    items: _vaccineFilterOptions.map((String option) {
                      return DropdownMenuItem<String>(
                        value: option,
                        child: Text(option),
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

  Widget _buildDashboardCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return AppMetricCard(label: title, value: value, icon: icon);
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
    final colors = AppDesign.statusColors(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.foreground.withValues(alpha: 0.25)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: colors.foreground,
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
    final patientName = record['patientName'] ?? 'N/A';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: _historyBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            color: _historyBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _historyBorder),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _historySurface,
                  border: Border(bottom: BorderSide(color: _historyBorder)),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.vaccines, color: _historyAccent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        patientName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _historyText,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: _historyAccent),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
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
              ),
            ],
          ),
        ),
      ),
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
    String selectedInjectionSite = record['injectionSite'] ?? 'Left Upper Arm';
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height,
            decoration: const BoxDecoration(
              color: _lightOffWhite,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // Modal Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _primaryAqua,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
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
                                'status': record['status'] ?? 'Completed',
                                'date':
                                    administrationDate?.toIso8601String() ?? '',
                              };

                              // Update in database
                              final id = record['id']?.toString() ?? '';
                              if (id.isNotEmpty) {
                                await _dbHelper.updateRecord(id, updatedRecord);
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
                              padding: const EdgeInsets.symmetric(vertical: 16),
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
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: _lightOffWhite.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: _lightOffWhite,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: _historyText,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _historySurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _historyBorder),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildDetailRowWithIcon(IconData icon, String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: _historyAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: _historyMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value?.toString() ?? 'N/A',
                  style: TextStyle(
                    fontSize: 14,
                    color: _historyAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
    } catch (e) {
      return dateString;
    }
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
                Expanded(
                  child: Text(
                    '${_selectedIndices.length} Record${_selectedIndices.length > 1 ? 's' : ''} Selected',
                    style: TextStyle(
                      color: _darkDeepTeal,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                // Select All Button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedIndices.clear();
                        for (int i = 0; i < _getFilteredRecords().length; i++) {
                          _selectedIndices.add(i);
                        }
                      });
                    },
                    icon: Icon(Icons.select_all, size: 18),
                    label: Text(
                      'Select All',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryAqua,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Delete Button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _confirmDelete();
                    },
                    icon: Icon(Icons.delete, size: 18),
                    label: Text(
                      'Delete',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Cancel Button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isSelectionMode = false;
                        _selectedIndices.clear();
                      });
                    },
                    icon: Icon(Icons.close, size: 18),
                    label: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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

  void _showRecordActionModal(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final rawName = (record['patientName'] ?? record['childName'] ?? '')
        .toString()
        .trim();
    final patientName = rawName.isEmpty ? 'Record Details' : rawName;

    MobileRecordActionSheet.show(
      context: context,
      title: patientName,
      headerIcon: Icons.vaccines_outlined,
      actions: [
        MobileRecordAction(
          label: 'View Patient History',
          icon: Icons.history_rounded,
          tone: MobileRecordActionTone.primary,
          onPressed: () => _showPatientImmunizationHistory(context, record),
        ),
        MobileRecordAction(
          label: 'Add Another Immunization',
          icon: Icons.add_circle_outline,
          onPressed: () =>
              _showNewImmunizationModal(context, patientSeed: record),
        ),
        MobileRecordAction(
          label: 'View Current Record Details',
          icon: Icons.visibility_outlined,
          onPressed: () => _showRecordDetails(context, record),
        ),
        MobileRecordAction(
          label: 'Edit Record',
          icon: Icons.edit_outlined,
          onPressed: () => _showEditImmunizationModal(context, record),
        ),
        MobileRecordAction(
          label: 'Delete Record',
          icon: Icons.delete_outline,
          tone: MobileRecordActionTone.danger,
          onPressed: () => _showDeleteConfirmation(context, record),
        ),
        MobileRecordAction(
          label: 'Select Multiple',
          icon: Icons.check_box_outlined,
          onPressed: () {
            setState(() {
              _isSelectionMode = true;
              _selectedIndices.clear();
            });
          },
        ),
        MobileRecordAction(
          label: 'Delete Selected',
          icon: Icons.delete_sweep,
          tone: MobileRecordActionTone.danger,
          onPressed: () {
            if (_selectedIndices.isNotEmpty) {
              setState(() => _isDeleteDialogShowing = true);
              _showDeleteConfirmationForSelected(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please select records first'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        ),
      ],
    );
  }

  void _showRecordDetails(BuildContext context, Map<String, dynamic> record) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _darkDeepTeal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: _lightOffWhite.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          title: Text(
            'Immunization Details',
            style: TextStyle(
              color: _lightOffWhite,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailSection('Patient Information', [
                  _buildDetailRow('Name', record['patientName'] ?? 'N/A'),
                  _buildDetailRow('Patient ID', record['patientId'] ?? 'N/A'),
                  _buildDetailRow('Age', record['age']?.toString() ?? 'N/A'),
                  _buildDetailRow('Contact', record['contactNumber'] ?? 'N/A'),
                ]),
                const SizedBox(height: 16),
                _buildDetailSection('Vaccine Information', [
                  _buildDetailRow('Vaccine Type', record['vaccine'] ?? 'N/A'),
                  _buildDetailRow('Brand', record['vaccineBrand'] ?? 'N/A'),
                  _buildDetailRow(
                    'Batch Number',
                    record['batchNumber'] ?? 'N/A',
                  ),
                  _buildDetailRow(
                    'Expiration Date',
                    _formatDate(record['expirationDate']),
                  ),
                ]),
                const SizedBox(height: 16),
                _buildDetailSection('Administration', [
                  _buildDetailRow(
                    'Administration Date',
                    _formatDate(record['administrationDate']),
                  ),
                  _buildDetailRow(
                    'Time',
                    record['administrationTime'] ?? 'N/A',
                  ),
                  _buildDetailRow('Dose Number', record['doseNumber'] ?? 'N/A'),
                  _buildDetailRow(
                    'Route',
                    record['routeOfAdministration'] ?? 'N/A',
                  ),
                  _buildDetailRow(
                    'Injection Site',
                    record['injectionSite'] ?? 'N/A',
                  ),
                  _buildDetailRow(
                    'Administered By',
                    record['administeredBy'] ?? 'N/A',
                  ),
                ]),
                const SizedBox(height: 16),
                _buildDetailSection('Additional Information', [
                  _buildDetailRow(
                    'Adverse Events',
                    record['adverseEvents'] ?? 'None',
                  ),
                  _buildDetailRow(
                    'Next Dose Due',
                    _formatDate(record['nextDoseDueDate']),
                  ),
                ]),
                const SizedBox(height: 16),
                _buildDetailSection('Status', [
                  _buildDetailRow('Status', record['status'] ?? 'N/A'),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Close',
                style: TextStyle(color: _lightOffWhite),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _darkDeepTeal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: _lightOffWhite.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          title: const Text(
            'Delete Record?',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to delete this immunization record for ${record['patientName'] ?? 'this patient'}?',
            style: const TextStyle(color: _lightOffWhite),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: _lightOffWhite),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final id = record['id'] as String?;
                if (id != null) {
                  await _dbHelper.deleteRecords([id]);
                  await _loadRecords();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Record deleted successfully'),
                        backgroundColor: Colors.green,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _showEditImmunizationModal(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    // Keep the records-table and compact/mobile entry points on the same
    // validated edit flow.  The full form below pre-fills every field and
    // persists through ImmunizationDatabaseHelper, so this entry point must
    // not show a placeholder or maintain a second, divergent form.
    _showEditDialog(context, record);
  }

  void _showDeleteConfirmationForSelected(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _darkDeepTeal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: _lightOffWhite.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          title: const Text(
            'Delete Selected Records?',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to delete ${_selectedIndices.length} selected record(s)? This action cannot be undone.',
            style: const TextStyle(color: _lightOffWhite),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: _lightOffWhite),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                _deleteSelectedRecords();
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: _lightOffWhite,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _ImmunizationTable extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final int startIndex;
  final bool isSelectionMode;
  final Set<int> selectedIndices;
  final Function(int, bool) onSelectionChanged;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>)? onTap;
  final Function(Map<String, dynamic>)? onLongPress;

  const _ImmunizationTable({
    required this.records,
    required this.startIndex,
    required this.isSelectionMode,
    required this.selectedIndices,
    required this.onSelectionChanged,
    required this.onEdit,
    this.onTap,
    this.onLongPress,
  });

  String _getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'I';
    }

    final parts = trimmed
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    if (parts.isEmpty) {
      return 'I';
    }

    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }

    return parts[0][0].toUpperCase();
  }

  Color _getAvatarColor(int index) {
    final colors = AppDesign.chartPalette;
    return colors[index % colors.length];
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.vaccines,
                size: 64,
                color: _mutedCoolGray.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'No immunization records found.',
                style: TextStyle(
                  color: _mutedCoolGray,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add a new immunization record to get started',
                style: TextStyle(color: _mutedCoolGray, fontSize: 14),
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
        final patientName = record['patientName'] ?? 'Unknown';
        final patientId = record['patientId']?.toString() ?? 'N/A';
        final age = record['age']?.toString() ?? 'N/A';
        final vaccine = record['vaccine']?.toString() ?? 'N/A';
        final date = _formatDate(record['administrationDate']?.toString());
        final status = record['status']?.toString() ?? 'Pending';
        final historyCount =
            int.tryParse(record['patientHistoryCount']?.toString() ?? '') ?? 1;

        return HealthRecordCard(
          recordLabel: 'Immunization',
          patientName: patientName.toString(),
          location:
              record['barangay']?.toString() ??
              record['address']?.toString() ??
              'Location not recorded',
          accentColor: AppDesign.checkUp,
          status: status,
          isSelected: selectedIndices.contains(absoluteIndex),
          showSelection: isSelectionMode,
          onSelectionChanged: (selected) =>
              onSelectionChanged(absoluteIndex, selected),
          onTap: () {
            if (isSelectionMode) {
              onSelectionChanged(
                absoluteIndex,
                !selectedIndices.contains(absoluteIndex),
              );
            } else {
              onTap?.call(record);
            }
          },
          onLongPress: () => onLongPress?.call(record),
          onAction: () => onLongPress?.call(record),
          metadata: [
            RecordMetadata(label: 'Age', value: age, icon: Icons.cake_outlined),
            RecordMetadata(
              label: 'Vaccine',
              value: vaccine,
              icon: Icons.vaccines_outlined,
              emphasize: true,
            ),
            RecordMetadata(
              label: 'Dose',
              value: record['doseNumber']?.toString() ?? 'Not recorded',
              icon: Icons.format_list_numbered_rounded,
            ),
            RecordMetadata(
              label: 'Date given',
              value: date,
              icon: Icons.event_available_outlined,
            ),
            RecordMetadata(
              label: 'Next schedule',
              value: HealthRecordDate.format(record['nextDoseDueDate']),
              icon: Icons.event_repeat_outlined,
            ),
            RecordMetadata(
              label: 'Administered by',
              value: record['administeredBy']?.toString() ?? 'Not recorded',
              icon: Icons.medical_services_outlined,
            ),
          ],
        );

        // ignore: dead_code
        return GestureDetector(
          onTap: () {
            if (isSelectionMode) {
              onSelectionChanged(
                absoluteIndex,
                !selectedIndices.contains(absoluteIndex),
              );
              return;
            }
            onTap?.call(record);
          },
          onLongPress: () => onLongPress?.call(record),
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
                  color: selectedIndices.contains(absoluteIndex)
                      ? _primaryAqua
                      : _lightOffWhite.withValues(alpha: 0.3),
                  width: selectedIndices.contains(absoluteIndex) ? 2.5 : 1.5,
                ),
                color: selectedIndices.contains(absoluteIndex)
                    ? _primaryAqua.withValues(alpha: 0.08)
                    : null,
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
                              color: selectedIndices.contains(absoluteIndex)
                                  ? _primaryAqua
                                  : _lightOffWhite.withValues(alpha: 0.5),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            color: selectedIndices.contains(absoluteIndex)
                                ? _primaryAqua
                                : Colors.transparent,
                          ),
                          child: selectedIndices.contains(absoluteIndex)
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 16,
                                )
                              : null,
                        ),
                      ),
                    // Avatar
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _getAvatarColor(absoluteIndex),
                        boxShadow: [
                          BoxShadow(
                            color: _getAvatarColor(
                              absoluteIndex,
                            ).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
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

                    // Patient Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Patient Name
                          Text(
                            patientName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _lightOffWhite,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),

                          // Patient ID
                          Text(
                            'ID: $patientId',
                            style: TextStyle(
                              fontSize: 13,
                              color: _lightOffWhite.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'History Entries: $historyCount',
                            style: TextStyle(
                              fontSize: 12,
                              color: _primaryAqua,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),

                          // Details Row
                          Row(
                            children: [
                              // Age
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Age: ',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _lightOffWhite.withValues(
                                            alpha: 0.7,
                                          ),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      TextSpan(
                                        text: age,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: _lightOffWhite,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Date
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Date: ',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _lightOffWhite.withValues(
                                            alpha: 0.7,
                                          ),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      TextSpan(
                                        text: date,
                                        style: const TextStyle(
                                          fontSize: 12,
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

                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: (status == 'Completed')
                            ? Colors.green.withValues(alpha: 0.15)
                            : status == 'Pending'
                            ? Colors.orange.withValues(alpha: 0.15)
                            : Colors.blue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: (status == 'Completed')
                              ? Colors.green.withValues(alpha: 0.3)
                              : status == 'Pending'
                              ? Colors.orange.withValues(alpha: 0.3)
                              : Colors.blue.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (status == 'Completed')
                                  ? Colors.green
                                  : status == 'Pending'
                                  ? Colors.orange
                                  : Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            status,
                            style: TextStyle(
                              color: (status == 'Completed')
                                  ? Colors.green.shade700
                                  : status == 'Pending'
                                  ? Colors.orange.shade700
                                  : Colors.blue.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
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
        );
      },
    );
  }
}
