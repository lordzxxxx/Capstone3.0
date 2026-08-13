import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/features/prenatal/prenatal_database_helper.dart';
import 'package:mycapstone_project/app/core/services/health_ai_classifier.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:mycapstone_project/app/shared/widgets/mobile_pagination_controls.dart';
import 'package:mycapstone_project/app/features/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/app/features/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/shared/current_table_record_utils.dart';
import 'package:mycapstone_project/app/shared/widgets/ocr_record_action.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';
import 'package:mycapstone_project/app/shared/widgets/health_record_card.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _secondaryIceBlue = AppDesign.blueSoft;
const Color _darkDeepTeal = AppDesign.page;
const Color _mutedCoolGray = AppDesign.muted;
const Color _lightOffWhite = AppDesign.ink;

class PrenatalPage extends StatefulWidget {
  const PrenatalPage({super.key});

  @override
  State<PrenatalPage> createState() => _PrenatalPageState();
}

class _PrenatalPageState extends State<PrenatalPage> {
  String _selectedStatusFilter = 'All Cases';
  final List<String> _statusFilterOptions = [
    'All Cases',
    'Active',
    'High Risk',
    'Follow Up',
    'Completed',
  ];

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  DateTime? _fromDate;
  DateTime? _toDate;

  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};
  bool _isDeleteDialogShowing = false;
  bool _isLoading = true;

  // Database-backed prenatal records
  List<Map<String, dynamic>> _prenatalRecords = [];
  final PrenatalDatabaseHelper _dbHelper = PrenatalDatabaseHelper.instance;
  static const int _defaultRowsPerPage = 5;
  int _currentPage = 1;
  int _rowsPerPage = _defaultRowsPerPage;

  // AI Classifier
  final HealthAIClassifier _aiClassifier = HealthAIClassifier.instance;
  final PatientCenteredHistoryService _patientHistoryService =
      PatientCenteredHistoryService();

  @override
  void initState() {
    super.initState();
    _loadRecords();
    _dbHelper.startConnectivityListener();
    _initializeAI();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeAI() async {
    await _aiClassifier.initialize();
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
      _prenatalRecords = updatedRecords;
      _isLoading = false;
    });
  }

  Future<void> _seedPrenatalData() async {
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
            Text('Seeding 100 sample prenatal records...'),
          ],
        ),
      ),
    );

    try {
      await _dbHelper.seedSamplePrenatalData();

      // Close loading dialog
      Navigator.of(context).pop();

      // Reload records
      await _loadRecords();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Successfully added 100 sample prenatal records!',
                  ),
                ),
              ],
            ),
            backgroundColor: Color(0xFF27AE60),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Error seeding data: $e')),
              ],
            ),
            backgroundColor: const Color(0xFFE74C3C),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkDeepTeal,
      appBar: AppBar(
        backgroundColor: _darkDeepTeal,
        title: Text(
          'Prenatal Care Dashboard',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: _lightOffWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: _lightOffWhite),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'View Data in Console',
            onPressed: () {
              print('=== PRENATAL RECORDS DATA ===');
              print('Total Records: ${_prenatalRecords.length}');
              for (var i = 0; i < _prenatalRecords.length; i++) {
                print('\nRecord ${i + 1}:');
                _prenatalRecords[i].forEach((key, value) {
                  print('  $key: $value');
                });
              }
              print('=============================');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Data printed to console! Check Debug Console.',
                    ),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
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
                            // Search Bar with Burger Menu and Status Filter
                            _buildPrenatalSearchAndFilterBar(),
                            const SizedBox(height: 16),

                            // Prenatal Records Table
                            _PrenatalTable(
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
                                _showEditPrenatalModal(context, record);
                              },
                              onTap: (record) {
                                _showPrenatalHistory(context, record);
                              },
                              onLongPress: (record) {
                                _showRecordActionModal(context, record);
                              },
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
              ],
            ),
      floatingActionButton:
          (_isDeleteDialogShowing ||
              (_isSelectionMode && _selectedIndices.isNotEmpty))
          ? null
          : RecordCreationFabGroup(
              moduleLabel: 'Prenatal',
              manualLabel: 'New Prenatal',
              onManualCreate: () => _showNewPrenatalModal(context),
              onOcrReady: (extraction) async {
                _showNewPrenatalModal(
                  context,
                  patientSeed: extraction.toFormSeed(),
                );
              },
            ),
    );
  }

  Widget _buildPrenatalSearchAndFilterBar() {
    return Column(
      children: [
        // Search Bar (top row)
        TextField(
          controller: _searchController,
          onChanged: (value) {
            setState(() {
              _searchQuery = value.toLowerCase();
              _resetPagination(clearSelection: true);
            });
          },
          style: TextStyle(color: _lightOffWhite),
          decoration: InputDecoration(
            hintText: 'Search by name, address, or patient ID...',
            hintStyle: TextStyle(color: _lightOffWhite.withValues(alpha: 0.5)),
            prefixIcon: Icon(Icons.search, color: _lightOffWhite),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, color: _lightOffWhite),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                        _resetPagination(clearSelection: true);
                      });
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _lightOffWhite.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _lightOffWhite.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _lightOffWhite, width: 2),
            ),
            filled: true,
            fillColor: Colors.transparent,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 12),

        // Burger Menu and Status Filter (bottom row)
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
                        _selectedStatusFilter = 'All Cases';
                        _searchController.clear();
                        _searchQuery = '';
                        _resetPagination(clearSelection: true);
                      });
                      break;
                    case 'clear':
                      setState(() {
                        _fromDate = null;
                        _toDate = null;
                        _selectedStatusFilter = 'All Cases';
                        _searchController.clear();
                        _searchQuery = '';
                        _resetPagination(clearSelection: true);
                      });
                      break;
                    case 'seed':
                      _seedPrenatalData();
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

            // Status Filter Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: _darkDeepTeal.withValues(alpha: 0.2),
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
              child: DropdownButton<String>(
                value: _selectedStatusFilter,
                isExpanded: false,
                underline: const SizedBox.shrink(),
                dropdownColor: _darkDeepTeal,
                items: _statusFilterOptions.map((String value) {
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
                      _selectedStatusFilter = newValue;
                      _resetPagination(clearSelection: true);
                    });
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _getFilteredRecords() {
    final filtered = _prenatalRecords.where((record) {
      // Status filter
      bool statusMatch = true;
      if (_selectedStatusFilter != 'All Cases') {
        statusMatch =
            record['status'] == _selectedStatusFilter ||
            record['riskLevel'] == _selectedStatusFilter;
      }

      // Date range filter
      bool dateMatch = true;
      if (_fromDate != null || _toDate != null) {
        try {
          final dueDate = DateTime.parse(
            record['dueDate']?.toString() ??
                record['eddDate']?.toString() ??
                '',
          );
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

      // Search filter by patient name, address, or patient ID
      bool searchMatch = true;
      if (_searchQuery.isNotEmpty) {
        final patientName = (record['patientName'] ?? '')
            .toString()
            .toLowerCase();
        final address = (record['address'] ?? '').toString().toLowerCase();
        final patientId = (record['patientId'] ?? '').toString().toLowerCase();
        searchMatch =
            patientName.contains(_searchQuery) ||
            address.contains(_searchQuery) ||
            patientId.contains(_searchQuery);
      }

      return statusMatch && dateMatch && searchMatch;
    }).toList();

    return CurrentTableRecordUtils.collapseToLatestPerEntity(
      filtered,
      idKeys: const ['patientId'],
      nameKeys: const ['patientName'],
      dateKeys: const ['registrationDate', 'dueDate', 'lmpDate', 'eddDate'],
      extraIdentityKeys: const ['contactNumber', 'address'],
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
    return filteredRecords.sublist(_pageStartIndex, _pageEndIndex);
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

  void _confirmDelete() {
    if (_selectedIndices.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No records selected'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() {
      _isDeleteDialogShowing = true;
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Confirm Delete'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${_selectedIndices.length} selected record(s)? This action cannot be undone.',
          style: const TextStyle(color: _darkDeepTeal),
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
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ).then((_) {
      setState(() {
        _isDeleteDialogShowing = false;
      });
    });
  }

  void _deleteSelectedRecords() async {
    final count = _selectedIndices.length;

    // Get IDs of records to delete
    final idsToDelete = _selectedIndices
        .map(
          (index) => index < _getFilteredRecords().length
              ? _getFilteredRecords()[index]['id'] as String?
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

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Successfully deleted $count record(s)',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<Map<String, dynamic>> _getPrenatalHistory(Map<String, dynamic> record) {
    return PatientHistoryDialogs.collectHistory(
      seedRecord: record,
      records: _prenatalRecords,
      idKeys: const ['linkedPatientId', 'patientId'],
      nameKeys: const ['patientName', 'patient'],
      sortDateKeys: const ['registrationDate', 'dueDate', 'lmpDate'],
    );
  }

  Map<String, dynamic> _buildPatientHistorySeed(Map<String, dynamic> record) {
    final patientName =
        (record['patientName'] ?? record['patient'] ?? record['name'] ?? '')
            .toString()
            .trim();
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

  void _showPrenatalHistory(BuildContext context, Map<String, dynamic> record) {
    final history = _getPrenatalHistory(record);
    PatientHistoryDialogs.showModuleHistoryDialog(
      context: context,
      moduleTitle: 'Prenatal',
      seedRecord: record,
      history: history,
      description:
          'Review previous prenatal visits before recording the next maternal check-in for the same patient.',
      addButtonLabel: 'Add Another Prenatal Visit',
      titleBuilder: (entry) =>
          (entry['riskLevel'] ?? entry['status'] ?? 'Prenatal visit')
              .toString(),
      subtitleBuilder: (entry) =>
          'Gestational age: ${(entry['gestationalAge'] ?? entry['aog'] ?? 'N/A').toString()}',
      metaBuilder: (entry) =>
          'Due: ${_formatDate(entry['dueDate'])} | Contact: ${(entry['contactNumber'] ?? 'N/A').toString()}',
      dateKeys: const ['registrationDate', 'dueDate', 'lmpDate'],
      secondaryActionLabel: 'Medical History',
      onSecondaryAction: () => _showPatientMedicalHistory(context, record),
      onAddAnother: () => _showNewPrenatalModal(
        context,
        patientSeed: history.isNotEmpty ? history.first : record,
      ),
      onOpenRecord: (entry) => _showPatientDetails(context, entry),
    );
  }

  void _showRecordActionModal(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final rawName = record['patientName']?.toString().trim() ?? '';
    final patientName = rawName.isEmpty ? 'Record Details' : rawName;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: const BoxDecoration(
            color: _darkDeepTeal,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _mutedCoolGray.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                patientName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _lightOffWhite,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _showPrenatalHistory(context, record);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryAqua,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'View Patient History',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _showNewPrenatalModal(context, patientSeed: record);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryAqua.withValues(alpha: 0.1),
                    side: const BorderSide(color: _primaryAqua, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_circle_outline,
                        size: 20,
                        color: _primaryAqua,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Add Another Prenatal Visit',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _primaryAqua,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _showEditPrenatalModal(context, record);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.withValues(alpha: 0.1),
                    side: const BorderSide(color: Colors.orange, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit, size: 20, color: Colors.orange),
                      SizedBox(width: 8),
                      Text(
                        'Edit Record',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _showDeleteConfirmation(context, record);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.1),
                    side: const BorderSide(color: Colors.red, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text(
                        'Delete Record',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    setState(() {
                      _isSelectionMode = true;
                      _selectedIndices.clear();
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(
                      0xFF4ECDC4,
                    ).withValues(alpha: 0.1),
                    side: const BorderSide(color: Color(0xFF4ECDC4), width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_box_outlined,
                        size: 20,
                        color: Color(0xFF4ECDC4),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Select Multiple',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4ECDC4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    if (_selectedIndices.isNotEmpty) {
                      setState(() {
                        _isDeleteDialogShowing = true;
                      });
                      _showDeleteConfirmationForSelected(context);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select records first'),
                          backgroundColor: Colors.orange,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700.withValues(alpha: 0.1),
                    side: BorderSide(color: Colors.red.shade700, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.delete_sweep,
                        size: 20,
                        color: Colors.red.shade700,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Delete Selected',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final patientName = record['patientName'] ?? 'Unknown';

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Record'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete the record for $patientName? This action cannot be undone.',
          style: const TextStyle(color: _darkDeepTeal),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: _mutedCoolGray,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final recordId = record['id'] as String?;
              if (recordId != null) {
                await _dbHelper.deleteRecords([recordId]);
                await _loadRecords();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Record deleted successfully',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmationForSelected(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Selected Records'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${_selectedIndices.length} selected record(s)? This action cannot be undone.',
          style: const TextStyle(color: _darkDeepTeal),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: _mutedCoolGray,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              _deleteSelectedRecords();
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// Prenatal Table Widget
class _PrenatalTable extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final int startIndex;
  final bool isSelectionMode;
  final Set<int> selectedIndices;
  final Function(int, bool) onSelectionChanged;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>)? onTap;
  final Function(Map<String, dynamic>)? onLongPress;

  const _PrenatalTable({
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
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : 'P';
  }

  Color _getAvatarColor(int index) {
    final colors = [
      AppDesign.prenatal,
      const Color(0xFF1E5A7A), // Ice Blue
      const Color(0xFFFF6B6B), // Red
      const Color(0xFF4ECDC4), // Teal
      const Color(0xFFFFBE5B), // Gold
      const Color(0xFF845EC2), // Purple
    ];
    return colors[index % colors.length];
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
                Icons.pregnant_woman,
                size: 64,
                color: _mutedCoolGray.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'No prenatal records found.',
                style: TextStyle(
                  color: _mutedCoolGray,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add a new prenatal record to get started',
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
        final address = record['address']?.toString() ?? 'N/A';
        final age = record['age']?.toString() ?? 'N/A';
        final status =
            record['riskLevel']?.toString() ??
            record['status']?.toString() ??
            'Active';
        final gestationalAge = record['gestationalAge']?.toString() ?? 'N/A';
        final dueDate = record['dueDate']?.toString() ?? 'N/A';

        return HealthRecordCard(
          recordLabel: 'Prenatal care',
          patientName: patientName.toString(),
          location: address,
          accentColor: AppDesign.prenatal,
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
              label: 'Gestational age',
              value: gestationalAge,
              icon: Icons.pregnant_woman_rounded,
            ),
            RecordMetadata(
              label: 'Trimester',
              value: record['trimester']?.toString() ?? 'Not recorded',
              icon: Icons.timeline_rounded,
            ),
            RecordMetadata(
              label: 'Blood pressure',
              value: record['bp']?.toString() ?? 'Not recorded',
              icon: Icons.monitor_heart_outlined,
            ),
            RecordMetadata(
              label: 'Weight',
              value: record['wt']?.toString() ?? 'Not recorded',
              icon: Icons.monitor_weight_outlined,
            ),
            RecordMetadata(
              label: 'Last visit',
              value: HealthRecordDate.format(record['registrationDate']),
              icon: Icons.event_available_outlined,
            ),
            RecordMetadata(
              label: 'Next visit',
              value: HealthRecordDate.format(record['nextVisit']),
              icon: Icons.event_repeat_outlined,
            ),
            RecordMetadata(
              label: 'Expected delivery',
              value: HealthRecordDate.format(
                record['eddDate'] ?? record['dueDate'],
              ),
              icon: Icons.child_friendly_outlined,
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

                          // Address
                          Text(
                            address,
                            style: TextStyle(
                              fontSize: 13,
                              color: _lightOffWhite.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w500,
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
                              // Gestational Age
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'AOG: ',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _lightOffWhite.withValues(
                                            alpha: 0.7,
                                          ),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      TextSpan(
                                        text: gestationalAge,
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
                        color: (status == 'Active')
                            ? Colors.green.withValues(alpha: 0.15)
                            : status == 'Follow Up'
                            ? Colors.orange.withValues(alpha: 0.15)
                            : status == 'High Risk'
                            ? Colors.red.withValues(alpha: 0.15)
                            : Colors.blue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: (status == 'Active')
                              ? Colors.green.withValues(alpha: 0.3)
                              : status == 'Follow Up'
                              ? Colors.orange.withValues(alpha: 0.3)
                              : status == 'High Risk'
                              ? Colors.red.withValues(alpha: 0.3)
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
                              color: (status == 'Active')
                                  ? Colors.green
                                  : status == 'Follow Up'
                                  ? Colors.orange
                                  : status == 'High Risk'
                                  ? Colors.red
                                  : Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            status,
                            style: TextStyle(
                              color: (status == 'Active')
                                  ? Colors.green.shade700
                                  : status == 'Follow Up'
                                  ? Colors.orange.shade700
                                  : status == 'High Risk'
                                  ? Colors.red.shade700
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

// Prenatal Page State Helper Methods
extension _PrenatalPageStateExtension on _PrenatalPageState {
  Future<void> _showPrenatalAIModal(
    BuildContext context,
    ClassificationResult classification,
  ) async {
    // Show loading spinner dialog for 3 seconds
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (loadingContext) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Center(
            child: Container(
              width: 260,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_primaryAqua, _secondaryIceBlue],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _primaryAqua.withValues(alpha: 0.3),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 50,
                    height: 50,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Analyzing Prenatal Data...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'AI is classifying your prenatal record',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await Future.delayed(const Duration(seconds: 3));
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }

    final recoveryPlan = classification.recoveryPlan;

    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: _darkDeepTeal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          decoration: BoxDecoration(
            color: _darkDeepTeal,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _lightOffWhite.withValues(alpha: 0.14)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_darkDeepTeal, _secondaryIceBlue],
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
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.psychology,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AI Prenatal Analysis',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Prenatal record analyzed successfully',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category
                      _prenatalDialogInfoRow(
                        Icons.category_rounded,
                        'Category',
                        classification.category,
                        _prenatalGetCategoryColor(classification.category),
                      ),
                      const SizedBox(height: 10),
                      // Severity
                      _prenatalDialogInfoRow(
                        Icons.warning_amber_rounded,
                        'Severity',
                        classification.severity,
                        _prenatalGetSeverityColor(classification.severity),
                      ),
                      const SizedBox(height: 10),
                      // Confidence
                      _prenatalDialogInfoRow(
                        Icons.speed_rounded,
                        'Confidence',
                        '${(classification.confidence * 100).toStringAsFixed(1)}%',
                        Colors.blueAccent,
                      ),
                      const SizedBox(height: 10),
                      // Keywords
                      if (classification.keywords != null)
                        _prenatalDialogInfoRow(
                          Icons.label_rounded,
                          'Keywords',
                          classification.keywords!.join(', '),
                          Colors.orangeAccent,
                        ),

                      if (recoveryPlan != null) ...[
                        const SizedBox(height: 18),
                        const Text(
                          'Recovery Recommendations',
                          style: TextStyle(
                            color: _lightOffWhite,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (recoveryPlan['home_care'] != null)
                          _prenatalAppRecoverySection(
                            Icons.home_rounded,
                            'Home Care',
                            List<String>.from(recoveryPlan['home_care']),
                            Colors.teal,
                          ),
                        if (recoveryPlan['precautions'] != null)
                          _prenatalAppRecoverySection(
                            Icons.shield_rounded,
                            'Precautions',
                            List<String>.from(recoveryPlan['precautions']),
                            Colors.amber,
                          ),
                        if (recoveryPlan['estimated_recovery'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _lightOffWhite.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _lightOffWhite.withValues(alpha: 0.12),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.schedule,
                                    color: _primaryAqua,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Estimated Recovery: ',
                                    style: TextStyle(
                                      color: _lightOffWhite.withValues(
                                        alpha: 0.72,
                                      ),
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    recoveryPlan['estimated_recovery']
                                        .toString(),
                                    style: const TextStyle(
                                      color: _lightOffWhite,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (recoveryPlan['general_advice'] != null)
                          _prenatalAppRecoverySection(
                            Icons.tips_and_updates_rounded,
                            'General Advice',
                            List<String>.from(recoveryPlan['general_advice']),
                            Colors.green,
                          ),
                      ],
                    ],
                  ),
                ),
              ),

              // Footer
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.check),
                        label: const Text('Got It'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryAqua,
                          foregroundColor: _lightOffWhite,
                          padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _prenatalDialogInfoRow(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.72),
              fontSize: 13,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _prenatalAppRecoverySection(
    IconData icon,
    String title,
    List<String> items,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _lightOffWhite.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.circle,
                        color: color.withValues(alpha: 0.6),
                        size: 6,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: TextStyle(
                          color: _lightOffWhite.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
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

  Color _prenatalGetCategoryColor(String category) {
    switch (category) {
      case 'Communicable Disease':
        return Colors.orangeAccent;
      case 'Non-Communicable Disease':
        return Colors.purpleAccent;
      case 'Emergency':
        return Colors.redAccent;
      case 'Prenatal Care':
        return Colors.pinkAccent;
      case 'Pediatric Care':
        return Colors.cyanAccent;
      case 'Routine Checkup':
        return Colors.greenAccent;
      default:
        return _primaryAqua;
    }
  }

  Color _prenatalGetSeverityColor(String severity) {
    switch (severity) {
      case 'Critical':
        return Colors.red;
      case 'High':
        return Colors.deepOrange;
      case 'Medium':
        return Colors.amber;
      case 'Low':
        return Colors.greenAccent;
      default:
        return Colors.white70;
    }
  }

  void _showNewPrenatalModal(
    BuildContext context, {
    Map<String, dynamic>? patientSeed,
  }) {
    // Text editing controllers
    final firstNameController = TextEditingController();
    final surnameController = TextEditingController();
    final ageController = TextEditingController();
    final addressController = TextEditingController();
    final patientIdController = TextEditingController();
    final contactNumberController = TextEditingController();
    final civilStatusController = TextEditingController();
    final philhealthNumberController = TextEditingController();
    final philhealthMemberController = TextEditingController();
    final religionController = TextEditingController();

    DateTime? lmpDate;
    DateTime? eddDate;
    DateTime? lastDeliveryDate;
    DateTime? registrationDate = DateTime.now();

    final gravidaController = TextEditingController();
    final paraController = TextEditingController();
    String selectedRiskLevel = 'Active';

    final bloodTypeController = TextEditingController();
    final allergiesController = TextEditingController();
    final preExistingConditionsController = TextEditingController();
    final previousComplicationsController = TextEditingController();

    // Medical measurements controllers
    final aogController = TextEditingController(); // Age of Gestation
    final wtController = TextEditingController(); // Weight
    final atController = TextEditingController(); // Abdominal Tenderness
    final tempController = TextEditingController(); // Temperature
    final bpController = TextEditingController(); // Blood Pressure
    final bmiController = TextEditingController(); // Body Mass Index
    final fhController = TextEditingController(); // Fundal Height
    final dhbController = TextEditingController(); // Fetal Heart Beat
    final tcbController = TextEditingController(); // Total Bilirubin

    final registeredByController = TextEditingController();
    final additionalNoteController = TextEditingController();
    final modalTitle = patientSeed == null
        ? 'New Prenatal Registration'
        : 'Add Another Prenatal Visit';

    if (patientSeed != null) {
      final seededName = (patientSeed['patientName'] ?? '').toString().trim();
      final nameParts = seededName
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList();
      if (nameParts.isNotEmpty) {
        firstNameController.text = nameParts.first;
        if (nameParts.length > 1) {
          surnameController.text = nameParts.sublist(1).join(' ');
        }
      }
      ageController.text = (patientSeed['age'] ?? '').toString();
      addressController.text = (patientSeed['address'] ?? '').toString();
      patientIdController.text = (patientSeed['patientId'] ?? '').toString();
      contactNumberController.text = (patientSeed['contactNumber'] ?? '')
          .toString();
      civilStatusController.text = (patientSeed['civilStatus'] ?? '')
          .toString();
      philhealthNumberController.text = (patientSeed['philhealthNumber'] ?? '')
          .toString();
      philhealthMemberController.text = (patientSeed['philhealthMember'] ?? '')
          .toString();
      religionController.text = (patientSeed['religion'] ?? '').toString();
      gravidaController.text = (patientSeed['gravida'] ?? '').toString();
      paraController.text = (patientSeed['para'] ?? '').toString();
      selectedRiskLevel =
          (patientSeed['riskLevel'] ?? patientSeed['status'] ?? 'Active')
              .toString();
      bloodTypeController.text = (patientSeed['bloodType'] ?? '').toString();
      allergiesController.text = (patientSeed['allergies'] ?? '').toString();
      preExistingConditionsController.text =
          (patientSeed['preExistingConditions'] ?? '').toString();
      previousComplicationsController.text =
          (patientSeed['previousComplications'] ?? '').toString();
      aogController.text =
          (patientSeed['gestationalAge'] ?? patientSeed['aog'] ?? '')
              .toString();
      wtController.text = (patientSeed['weight'] ?? patientSeed['wt'] ?? '')
          .toString();
      atController.text =
          (patientSeed['abdominalTenderness'] ?? patientSeed['at'] ?? '')
              .toString();
      tempController.text =
          (patientSeed['temperature'] ?? patientSeed['temp'] ?? '').toString();
      bpController.text =
          (patientSeed['bloodPressure'] ?? patientSeed['bp'] ?? '').toString();
      bmiController.text = (patientSeed['bmi'] ?? '').toString();
      fhController.text =
          (patientSeed['fundalHeight'] ?? patientSeed['fh'] ?? '').toString();
      dhbController.text =
          (patientSeed['fetalHeartBeat'] ?? patientSeed['dhb'] ?? '')
              .toString();
      tcbController.text = (patientSeed['tcb'] ?? '').toString();
      registeredByController.text = (patientSeed['registeredBy'] ?? '')
          .toString();
      additionalNoteController.text =
          (patientSeed['additionalNotes'] ??
                  patientSeed['additionalNote'] ??
                  '')
              .toString();
      lmpDate = _parseDate(patientSeed['lmpDate']);
      eddDate = _parseDate(patientSeed['eddDate'] ?? patientSeed['dueDate']);
      lastDeliveryDate = _parseDate(patientSeed['lastDeliveryDate']);
      registrationDate = DateTime.now();
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
                    gradient: LinearGradient(
                      colors: [
                        _darkDeepTeal,
                        _darkDeepTeal.withValues(alpha: 0.9),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
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
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.pregnant_woman,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            modalTitle,
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
                        // Patient Information Area
                        _buildSectionHeader(
                          'Patient Information',
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
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: surnameController,
                                  label: 'Surname',
                                  icon: Icons.person_outline,
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
                                  controller: ageController,
                                  label: 'Age',
                                  icon: Icons.cake,
                                  hintText: 'Enter age',
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: patientIdController,
                                  label: 'Patient ID',
                                  icon: Icons.badge,
                                  hintText: 'e.g., PAT-2026-001',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: addressController,
                            label: 'Address',
                            icon: Icons.home,
                            hintText: 'Enter complete address',
                            maxLines: 2,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: contactNumberController,
                            label: 'Contact Number',
                            icon: Icons.phone,
                            hintText: 'e.g., +63 912 345 6789',
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  controller: civilStatusController,
                                  label: 'Civil Status',
                                  icon: Icons.favorite,
                                  hintText: 'e.g., Single, Married',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: religionController,
                                  label: 'Religion',
                                  icon: Icons.church,
                                  hintText: 'Enter religion',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  controller: philhealthNumberController,
                                  label: 'Philhealth Number',
                                  icon: Icons.medical_information,
                                  hintText: 'Enter Philhealth #',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: philhealthMemberController,
                                  label: 'Philhealth Member',
                                  icon: Icons.card_membership,
                                  hintText: 'Member name',
                                ),
                              ),
                            ],
                          ),
                        ]),
                        const SizedBox(height: 24),

                        // Pregnancy Detail Area
                        _buildSectionHeader(
                          'Pregnancy Detail',
                          Icons.child_care,
                        ),
                        _buildFormCard([
                          _buildDatePickerField(
                            context: context,
                            label: 'Last Menstrual Period (LMP)',
                            date: lmpDate,
                            icon: Icons.calendar_today,
                            onTap: () async {
                              final picked = await _showDatePickerModal(
                                context,
                              );
                              if (picked != null) {
                                setModalState(() => lmpDate = picked);
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildDatePickerField(
                            context: context,
                            label: 'Estimated Due Date (EDD)',
                            date: eddDate,
                            icon: Icons.event,
                            onTap: () async {
                              final picked = await _showDatePickerModal(
                                context,
                              );
                              if (picked != null) {
                                setModalState(() => eddDate = picked);
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildDatePickerField(
                            context: context,
                            label: 'Last Date of Delivery',
                            date: lastDeliveryDate,
                            icon: Icons.child_friendly,
                            onTap: () async {
                              final picked = await _showDatePickerModal(
                                context,
                              );
                              if (picked != null) {
                                setModalState(() => lastDeliveryDate = picked);
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  controller: gravidaController,
                                  label: 'Gravida (Number of Pregnancy)',
                                  icon: Icons.numbers,
                                  hintText: 'e.g., 1, 2, 3',
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: paraController,
                                  label: 'Para (Number of Live Births)',
                                  icon: Icons.numbers,
                                  hintText: 'e.g., 0, 1, 2',
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildDropdownField(
                            label: 'Risk Level',
                            value: selectedRiskLevel,
                            icon: Icons.warning_amber,
                            items: ['Active', 'Follow Up', 'High Risk'],
                            onChanged: (value) {
                              if (value != null) {
                                setModalState(() => selectedRiskLevel = value);
                              }
                            },
                          ),
                        ]),
                        const SizedBox(height: 24),

                        // Medical History Area
                        _buildSectionHeader(
                          'Medical History',
                          Icons.medical_services,
                        ),
                        _buildFormCard([
                          _buildTextField(
                            controller: bloodTypeController,
                            label: 'Blood Type',
                            icon: Icons.bloodtype,
                            hintText: 'e.g., A+, B-, O+, AB+',
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: allergiesController,
                            label: 'Allergies',
                            icon: Icons.health_and_safety,
                            hintText: 'List any known allergies',
                            maxLines: 2,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: preExistingConditionsController,
                            label: 'Pre-existing Medical Conditions',
                            icon: Icons.local_hospital,
                            hintText: 'e.g., Diabetes, Hypertension, Asthma',
                            maxLines: 3,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: previousComplicationsController,
                            label: 'Previous Pregnancy Complications',
                            icon: Icons.warning,
                            hintText:
                                'List any complications from previous pregnancies',
                            maxLines: 3,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  controller: aogController,
                                  label: 'AOG (Age of Gestation)',
                                  icon: Icons.calendar_view_week,
                                  hintText: 'e.g., 28 weeks',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: wtController,
                                  label: 'WT (Weight)',
                                  icon: Icons.monitor_weight,
                                  hintText: 'e.g., 65 kg',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  controller: tempController,
                                  label: 'TEMP (Temperature)',
                                  icon: Icons.thermostat,
                                  hintText: 'e.g., 36.5°C',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: bpController,
                                  label: 'BP (Blood Pressure)',
                                  icon: Icons.favorite,
                                  hintText: 'e.g., 120/80',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  controller: bmiController,
                                  label: 'BMI (Body Mass Index)',
                                  icon: Icons.assessment,
                                  hintText: 'e.g., 22.5',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: fhController,
                                  label: 'FH (Fundal Height)',
                                  icon: Icons.straighten,
                                  hintText: 'e.g., 28 cm',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  controller: dhbController,
                                  label: 'DHB (Fetal Heart Beat)',
                                  icon: Icons.favorite_border,
                                  hintText: 'e.g., 140 bpm',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: atController,
                                  label: 'AT (Abdominal Tenderness)',
                                  icon: Icons.touch_app,
                                  hintText: 'e.g., None, Mild',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: tcbController,
                            label: 'TCB (Total Bilirubin)',
                            icon: Icons.science,
                            hintText: 'e.g., 0.8 mg/dL',
                          ),
                        ]),
                        const SizedBox(height: 24),

                        // Registration Details Area
                        _buildSectionHeader(
                          'Registration Details',
                          Icons.app_registration,
                        ),
                        _buildFormCard([
                          _buildDatePickerField(
                            context: context,
                            label: 'Registration Date',
                            date: registrationDate,
                            icon: Icons.calendar_month,
                            onTap: () async {
                              final picked = await _showDatePickerModal(
                                context,
                              );
                              if (picked != null) {
                                setModalState(() => registrationDate = picked);
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: registeredByController,
                            label: 'Registered By',
                            icon: Icons.person_pin,
                            hintText: 'Enter staff name or ID',
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: additionalNoteController,
                            label: 'Additional Note',
                            icon: Icons.note,
                            hintText: 'Enter any additional notes or remarks',
                            maxLines: 4,
                          ),
                        ]),
                        const SizedBox(height: 32),

                        // Submit Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              // Create new prenatal record
                              final newRecord = {
                                'patientName':
                                    '${firstNameController.text} ${surnameController.text}',
                                'age': ageController.text,
                                'address': addressController.text,
                                'patientId': patientIdController.text,
                                'contactNumber': contactNumberController.text,
                                'civilStatus': civilStatusController.text,
                                'religion': religionController.text,
                                'philhealthNumber':
                                    philhealthNumberController.text,
                                'philhealthMember':
                                    philhealthMemberController.text,
                                'lmpDate': lmpDate?.toIso8601String() ?? '',
                                'eddDate': eddDate?.toIso8601String() ?? '',
                                'lastDeliveryDate':
                                    lastDeliveryDate?.toIso8601String() ?? '',
                                'gravida': gravidaController.text,
                                'para': paraController.text,
                                'riskLevel': selectedRiskLevel,
                                'bloodType': bloodTypeController.text,
                                'allergies': allergiesController.text,
                                'preExistingConditions':
                                    preExistingConditionsController.text,
                                'previousComplications':
                                    previousComplicationsController.text,
                                'aog': aogController.text,
                                'wt': wtController.text,
                                'at': atController.text,
                                'temp': tempController.text,
                                'bp': bpController.text,
                                'bmi': bmiController.text,
                                'fh': fhController.text,
                                'dhb': dhbController.text,
                                'tcb': tcbController.text,
                                'registrationDate':
                                    registrationDate?.toIso8601String() ?? '',
                                'registeredBy': registeredByController.text,
                                'additionalNote': additionalNoteController.text,
                                'gestationalAge': aogController.text,
                                'dueDate': eddDate?.toIso8601String() ?? '',
                                'status': selectedRiskLevel,
                              };

                              // AI Classification
                              ClassificationResult? classification;
                              try {
                                debugPrint(
                                  '🤖 Starting prenatal AI classification...',
                                );
                                classification = await _aiClassifier.classify(
                                  newRecord,
                                );
                                debugPrint(
                                  '✅ Prenatal AI classification complete: ${classification.category}',
                                );

                                newRecord['ai_category'] =
                                    classification.category;
                                newRecord['ai_severity'] =
                                    classification.severity;
                                newRecord['ai_confidence'] = classification
                                    .confidence
                                    .toString();
                                newRecord['ai_method'] = classification.method;
                                if (classification.keywords != null) {
                                  newRecord['ai_keywords'] = classification
                                      .keywords!
                                      .join(', ');
                                }
                                if (classification.recoveryPlan != null) {
                                  final recoveryPlan =
                                      Map<String, dynamic>.from(
                                        classification.recoveryPlan!,
                                      );
                                  if (classification.decisionSupport != null) {
                                    recoveryPlan['decision_support'] =
                                        classification.decisionSupport!
                                            .toJson();
                                  }
                                  newRecord['ai_recovery_plan'] = jsonEncode(
                                    recoveryPlan,
                                  );
                                }
                              } catch (e) {
                                debugPrint(
                                  '❌ Prenatal AI classification failed: $e',
                                );
                              }

                              // Save to database (offline + Firebase sync)
                              await _dbHelper.insertRecord(newRecord);

                              // Reload records
                              await _loadRecords();

                              // Show AI Classification modal with loading spinner
                              if (context.mounted && classification != null) {
                                await _showPrenatalAIModal(
                                  context,
                                  classification,
                                );
                              }

                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Prenatal registration saved successfully!',
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
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryAqua,
                              foregroundColor: _darkDeepTeal,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            child: const Text(
                              'Register Prenatal Patient',
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

  void _showEditPrenatalModal(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    // For now, show a simple dialog indicating edit functionality
    // Full implementation would parse record data and open an edit form
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Prenatal Record'),
        content: Text(
          'Editing record for: ${record['patientName'] ?? 'Unknown'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPatientDetails(BuildContext context, Map<String, dynamic> record) {
    // Parse patient name
    final patientName = record['patientName'] ?? 'Unknown';
    final nameParts = patientName.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts[0] : '';
    final surname = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: _darkDeepTeal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            color: _darkDeepTeal,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _lightOffWhite.withValues(alpha: 0.18)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_darkDeepTeal, _secondaryIceBlue],
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
                    Icon(Icons.pregnant_woman, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        patientName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _lightOffWhite,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
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
                      // Personal Information
                      _buildDetailSection('Personal Information', [
                        _buildDetailRow('First Name', firstName),
                        _buildDetailRow('Surname', surname),
                        _buildDetailRow('Patient ID', record['patientId']),
                        _buildDetailRow('Age', record['age']),
                        _buildDetailRow('Address', record['address']),
                        _buildDetailRow(
                          'Contact Number',
                          record['contactNumber'],
                        ),
                        _buildDetailRow('Civil Status', record['civilStatus']),
                        _buildDetailRow('Religion', record['religion']),
                      ]),
                      const SizedBox(height: 16),

                      // Philhealth Information
                      _buildDetailSection('Philhealth Information', [
                        _buildDetailRow(
                          'Philhealth Number',
                          record['philhealthNumber'],
                        ),
                        _buildDetailRow(
                          'Philhealth Member',
                          record['philhealthMember'],
                        ),
                      ]),
                      const SizedBox(height: 16),

                      // Pregnancy Details
                      _buildDetailSection('Pregnancy Details', [
                        _buildDetailRow(
                          'Gestational Age',
                          record['gestationalAge'],
                        ),
                        _buildDetailRow(
                          'LMP Date',
                          _formatDate(record['lmpDate']),
                        ),
                        _buildDetailRow(
                          'EDD Date',
                          _formatDate(record['eddDate']),
                        ),
                        _buildDetailRow(
                          'Due Date',
                          _formatDate(record['dueDate']),
                        ),
                        _buildDetailRow(
                          'Last Delivery Date',
                          _formatDate(record['lastDeliveryDate']),
                        ),
                        _buildDetailRow('Gravida', record['gravida']),
                        _buildDetailRow('Para', record['para']),
                        _buildDetailRow('Risk Level', record['riskLevel']),
                      ]),
                      const SizedBox(height: 16),

                      // Medical History
                      _buildDetailSection('Medical History', [
                        _buildDetailRow('Blood Type', record['bloodType']),
                        _buildDetailRow('Allergies', record['allergies']),
                        _buildDetailRow(
                          'Pre-existing Conditions',
                          record['preExistingConditions'],
                        ),
                        _buildDetailRow(
                          'Previous Complications',
                          record['previousComplications'],
                        ),
                      ]),
                      const SizedBox(height: 16),

                      // Vital Signs & Measurements
                      _buildDetailSection('Vital Signs & Measurements', [
                        _buildDetailRow(
                          'Age of Gestation (AOG)',
                          record['aog'],
                        ),
                        _buildDetailRow('Weight (WT)', record['wt']),
                        _buildDetailRow(
                          'Abdominal Tenderness (AT)',
                          record['at'],
                        ),
                        _buildDetailRow('Temperature', record['temp']),
                        _buildDetailRow('Blood Pressure (BP)', record['bp']),
                        _buildDetailRow('BMI', record['bmi']),
                        _buildDetailRow('Fundal Height (FH)', record['fh']),
                        _buildDetailRow(
                          'Fetal Heart Beat (DHB)',
                          record['dhb'],
                        ),
                        _buildDetailRow('Total Bilirubin (TCB)', record['tcb']),
                      ]),
                      const SizedBox(height: 16),

                      // Registration Details
                      _buildDetailSection('Registration Details', [
                        _buildDetailRow(
                          'Registration Date',
                          _formatDate(record['registrationDate']),
                        ),
                        _buildDetailRow(
                          'Registered By',
                          record['registeredBy'],
                        ),
                        _buildDetailRow('Status', record['status']),
                      ]),
                      const SizedBox(height: 16),

                      // Additional Notes
                      if (record['additionalNote'] != null &&
                          record['additionalNote'].toString().isNotEmpty)
                        _buildDetailSection('Additional Notes', [
                          _buildDetailRow('Notes', record['additionalNote']),
                        ]),
                    ],
                  ),
                ),
              ),
              // Footer with Action Buttons
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showEditPrenatalModal(context, record);
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _secondaryIceBlue,
                          foregroundColor: _lightOffWhite,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        label: const Text('Close'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _lightOffWhite,
                          side: BorderSide(
                            color: _lightOffWhite.withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _buildDetailSection(String title, List<Widget> children) {
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
          // Section Title
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: _primaryAqua.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              title,
              style: TextStyle(
                color: _lightOffWhite,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Section Content
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _lightOffWhite.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _lightOffWhite.withValues(alpha: 0.08)),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, dynamic value) {
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
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value?.toString() ?? 'N/A',
              style: TextStyle(
                color: _lightOffWhite,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null || date.toString().isEmpty) return 'N/A';
    try {
      final dateTime = DateTime.parse(date.toString());
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return date.toString();
    }
  }

  DateTime? _parseDate(dynamic dateValue) {
    if (dateValue == null || dateValue.toString().isEmpty) return null;
    try {
      return DateTime.parse(dateValue.toString());
    } catch (e) {
      return null;
    }
  }

  Future<DateTime?> _showDatePickerModal(BuildContext context) async {
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
            style: const TextStyle(
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
        boxShadow: const [],
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
            color: _lightOffWhite,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: const TextStyle(
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
              borderSide: const BorderSide(color: _lightOffWhite, width: 2),
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

  Widget _buildDatePickerField({
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

  Widget _buildDropdownField({
    required String label,
    required String value,
    required IconData icon,
    required List<String> items,
    required Function(String?) onChanged,
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
                    value: value,
                    isExpanded: true,
                    icon: Icon(Icons.arrow_drop_down, color: _lightOffWhite),
                    style: const TextStyle(
                      color: _lightOffWhite,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    items: items.map((String item) {
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

  Widget _buildDateFilter() {
    return Column(
      children: [
        // Status Filter
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
                child: Icon(Icons.filter_list, color: _primaryAqua, size: 20),
              ),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedStatusFilter,
                    isExpanded: true,
                    icon: Icon(Icons.arrow_drop_down, color: _primaryAqua),
                    style: TextStyle(
                      color: _darkDeepTeal,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    items: _statusFilterOptions.map((String option) {
                      return DropdownMenuItem<String>(
                        value: option,
                        child: Text(option),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedStatusFilter = newValue;
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
                    'Filter by Due Date Range',
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _mutedCoolGray,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: _darkDeepTeal,
                    fontSize: 24,
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

  Widget _buildPatientCard({
    required BuildContext context,
    required int index,
    required Map<String, dynamic> record,
  }) {
    final isSelected = _selectedIndices.contains(index);
    final patientName = record['patientName'] ?? 'Unknown';
    final nameParts = patientName.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts[0] : 'N/A';
    final surname = nameParts.length > 1
        ? nameParts.sublist(1).join(' ')
        : 'N/A';
    final gestationalAge = record['gestationalAge'] ?? 'N/A';
    final dueDate = record['dueDate'] ?? 'N/A';
    final status = record['status'] ?? 'Active';
    final age = record['age'] ?? 'N/A';
    final address = record['address'] ?? 'N/A';
    final contactNumber = record['contactNumber'] ?? 'N/A';
    final riskLevel = record['riskLevel'] ?? status;

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
              // Patient Name Header with Checkbox
              Row(
                children: [
                  if (_isSelectionMode) ...[
                    Checkbox(
                      value: isSelected,
                      onChanged: (bool? value) {
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.pregnant_woman,
                      color: _primaryAqua,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      patientName,
                      style: TextStyle(
                        color: _darkDeepTeal,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildStatusChip(status),
                ],
              ),
              const SizedBox(height: 16),

              // Patient Details
              Row(
                children: [
                  Expanded(
                    child: _buildInfoRow(
                      icon: Icons.person_outline,
                      label: 'First Name',
                      value: firstName,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInfoRow(
                      icon: Icons.person,
                      label: 'Surname',
                      value: surname,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoRow(
                      icon: Icons.cake,
                      label: 'Age',
                      value: age,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInfoRow(
                      icon: Icons.location_on,
                      label: 'Address',
                      value: address,
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
                          _showPatientDetails(context, record);
                        },
                        icon: Icon(Icons.visibility, size: 18),
                        label: Text(
                          'View History',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryAqua,
                          foregroundColor: _darkDeepTeal,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _showEditPrenatalModal(context, record);
                        },
                        icon: Icon(Icons.edit, size: 18),
                        label: Text(
                          'Edit',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _secondaryIceBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
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

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: _mutedCoolGray),
            const SizedBox(width: 4),
            Text(
              label,
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

  Widget _buildStatusChip(String status) {
    Color statusColor;
    switch (status) {
      case 'Active':
        statusColor = Colors.green;
        break;
      case 'Follow Up':
        statusColor = Colors.orange;
        break;
      case 'High Risk':
        statusColor = Colors.red;
        break;
      case 'Completed':
        statusColor = Colors.blue;
        break;
      default:
        statusColor = _mutedCoolGray;
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
                  _isSelectionMode ? Icons.close : Icons.checklist,
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
                      color: _primaryAqua,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_selectedIndices.length}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
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
                      foregroundColor: _darkDeepTeal,
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
                    icon: Icon(Icons.delete, size: 18),
                    label: Text('Delete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: _darkDeepTeal,
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
}
