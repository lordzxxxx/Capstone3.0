import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:math' as math;
import 'package:mycapstone_project/app/features/patients/patient_database_helper.dart';
import 'package:mycapstone_project/app/shared/widgets/mobile_pagination_controls.dart';
import 'package:mycapstone_project/app/shared/widgets/health_record_card.dart';
import 'package:mycapstone_project/app/shared/widgets/app_metric_card.dart';
import 'package:mycapstone_project/app/features/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/app/features/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/app/shared/widgets/ocr_record_action.dart';
import 'package:mycapstone_project/app/shared/widgets/mobile_compact_controls.dart';
import 'package:mycapstone_project/app/shared/widgets/mobile_record_action_sheet.dart';
import 'package:mycapstone_project/app/shared/services/clinical_form_pdf_service.dart';
import 'package:mycapstone_project/shared/current_table_record_utils.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

class PatientRecordPage extends StatefulWidget {
  const PatientRecordPage({super.key, this.openRegistrationOnLoad = false});

  final bool openRegistrationOnLoad;

  @override
  State<PatientRecordPage> createState() => _PatientRecordPageState();
}

class _PatientRecordPageState extends State<PatientRecordPage> {
  // Color scheme
  static const Color _primaryAqua = AppDesign.blue;
  static const Color _darkDeepTeal = AppDesign.page;
  static const Color _mutedCoolGray = AppDesign.muted;
  static const Color _lightOffWhite = AppDesign.ink;

  // Filter state
  String _selectedStatus = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Selection state
  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};
  bool _isDeleteDialogShowing = false;
  bool _registrationOpened = false;

  // Database helper
  final _dbHelper = PatientDatabaseHelper.instance;
  final _patientHistoryService = PatientCenteredHistoryService();

  // Patient data from database
  List<Map<String, dynamic>> _patients = [];
  bool _isLoading = true;
  static const int _defaultRowsPerPage = 5;
  int _currentPage = 1;
  int _rowsPerPage = _defaultRowsPerPage;

  @override
  void initState() {
    super.initState();
    _loadPatients().then((_) {
      if (!widget.openRegistrationOnLoad || _registrationOpened || !mounted) {
        return;
      }
      _registrationOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAddPatientModal();
      });
    });
    _dbHelper.startConnectivityListener();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final records = await _dbHelper.getAllRecords();
      setState(() {
        _patients = records;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading patients: $e');
      setState(() {
        _isLoading = false;
      });
    }
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
            Text('Seeding 100 sample patient records...'),
          ],
        ),
      ),
    );

    try {
      await _dbHelper.seedSamplePatientData();

      // Close loading dialog
      Navigator.of(context).pop();

      // Reload patients
      await _loadPatients();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Successfully added 100 sample patient records.'),
          backgroundColor: AppDesign.patientRecords,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error seeding data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Filtered patients based on search and filters
  List<Map<String, dynamic>> get _filteredPatients {
    final filtered = _patients.where((patient) {
      // Status filter
      if (_selectedStatus != 'All' && patient['status'] != _selectedStatus) {
        return false;
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
        final name = '${patient['firstName']} ${patient['surname']}'
            .toLowerCase();
        final phone = (patient['phoneNumber'] ?? '').toString().toLowerCase();
        final address = '${patient['barangay']}, ${patient['municipality']}'
            .toLowerCase();
        return name.contains(query) ||
            phone.contains(query) ||
            address.contains(query) ||
            (patient['age'] ?? '').toString().contains(query);
      }

      return true;
    }).toList();

    return CurrentTableRecordUtils.collapseToLatestPerEntity(
      filtered,
      idKeys: const ['patientId'],
      nameKeys: const ['firstName', 'middleName', 'surname'],
      dateKeys: const ['registrationDate', 'createdAt', 'timestamp'],
      extraIdentityKeys: const ['dateOfBirth', 'phoneNumber'],
    );
  }

  int get _effectiveRowsPerPage =>
      _rowsPerPage > 0 ? _rowsPerPage : _defaultRowsPerPage;

  int get _totalPages {
    final filteredCount = _filteredPatients.length;
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
    if (_filteredPatients.isEmpty) {
      return 0;
    }
    return (_safeCurrentPage - 1) * _effectiveRowsPerPage;
  }

  int get _pageEndIndex {
    if (_filteredPatients.isEmpty) {
      return 0;
    }
    return math.min(
      _pageStartIndex + _effectiveRowsPerPage,
      _filteredPatients.length,
    );
  }

  List<Map<String, dynamic>> get _pagedPatients {
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
    return Scaffold(
      backgroundColor: _darkDeepTeal,
      appBar: AppBar(
        backgroundColor: AppDesign.navy,
        elevation: 0,
        title: Text(
          'Patient Records',
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
              if (kDebugMode)
                PopupMenuItem(
                  child: const Text('Seed Sample Data'),
                  onTap: () => _seedSampleData(),
                ),
              PopupMenuItem(child: const Text('Settings'), onTap: () {}),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Container(
              color: _darkDeepTeal,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Burger Menu + Search Bar
                    Row(
                      children: [
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
                          child: PopupMenuButton<String>(
                            color: _darkDeepTeal,
                            icon: Icon(
                              Icons.menu,
                              color: _lightOffWhite,
                              size: 24,
                            ),
                            onSelected: (value) {
                              switch (value) {
                                case 'all':
                                  setState(() {
                                    _selectedStatus = 'All';
                                    _searchController.clear();
                                    _searchQuery = '';
                                    _resetPagination(clearSelection: true);
                                  });
                                  break;
                                case 'clear':
                                  setState(() {
                                    _selectedStatus = 'All';
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
                              if (kDebugMode)
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
                        Expanded(child: _buildSearchBar()),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Filter Dropdown
                    _buildFilterDropdown(),
                    const SizedBox(height: 12),

                    // Patient Cards
                    _buildPatientCards(),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ),
          // Selection Action Card
          _buildSelectionActionCard(),
        ],
      ),
      floatingActionButton: RecordCreationFabGroup(
        moduleLabel: 'Patient',
        manualLabel: 'New Patient',
        onManualCreate: _showAddPatientModal,
        onOcrReady: (extraction) async {
          _showAddPatientModal(initialValues: extraction.toFormSeed());
        },
      ),
    );
  }

  Widget _buildFilterDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: _darkDeepTeal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _lightOffWhite.withValues(alpha: 0.5),
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
        value: _selectedStatus,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: _darkDeepTeal,
        iconEnabledColor: _lightOffWhite,
        items: ['All', 'Active', 'Follow-up', 'Inactive']
            .map(
              (status) => DropdownMenuItem<String>(
                value: status,
                child: Text(
                  status,
                  style: TextStyle(
                    color: _lightOffWhite,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) {
            setState(() {
              _selectedStatus = value;
              _resetPagination(clearSelection: true);
            });
          }
        },
      ),
    );
  }

  Widget _buildStatisticsDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Patient Statistics',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: _lightOffWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 720 ? 3 : 2;
            const spacing = 12.0;
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            final cards = <Widget>[
              _buildStatCard(
                icon: Icons.people_outline,
                title: 'Total Patients',
                value: _totalPatients.toString(),
              ),
              _buildStatCard(
                icon: Icons.person_add_outlined,
                title: 'New This Month',
                value: _newThisMonth.toString(),
              ),
              _buildStatCard(
                icon: Icons.event_repeat_outlined,
                title: 'Follow-up Rate',
                value: '${_followUpRate.toStringAsFixed(1)}%',
              ),
            ];
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: cards
                  .map((card) => SizedBox(width: width, child: card))
                  .toList(growable: false),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return AppMetricCard(label: title, value: value, icon: icon);
  }

  Widget _buildFiltersSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
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
          Text(
            'Filters',
            style: TextStyle(
              color: AppDesign.ink,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Status Filter
          Row(
            children: [
              Icon(Icons.filter_list, color: _primaryAqua, size: 20),
              const SizedBox(width: 8),
              Text(
                'Status:',
                style: TextStyle(
                  color: AppDesign.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _lightOffWhite,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _mutedCoolGray.withValues(alpha: 0.3),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedStatus,
                      isExpanded: true,
                      items: ['All', 'Active', 'Follow-up', 'Inactive']
                          .map(
                            (status) => DropdownMenuItem(
                              value: status,
                              child: Text(status),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedStatus = value!;
                          _resetPagination(clearSelection: true);
                        });
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Date Range Filter
          Row(
            children: [
              Icon(Icons.date_range, color: _primaryAqua, size: 20),
              const SizedBox(width: 8),
              Text(
                'Date Range:',
                style: TextStyle(
                  color: AppDesign.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _buildDateButton(
                        label: _fromDate != null
                            ? '${_fromDate!.day}/${_fromDate!.month}/${_fromDate!.year}'
                            : 'From',
                        onTap: () => _selectFromDate(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward, color: _mutedCoolGray, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDateButton(
                        label: _toDate != null
                            ? '${_toDate!.day}/${_toDate!.month}/${_toDate!.year}'
                            : 'To',
                        onTap: () => _selectToDate(),
                      ),
                    ),
                  ],
                ),
              ),
              if (_fromDate != null || _toDate != null)
                IconButton(
                  icon: Icon(Icons.clear, color: Colors.red, size: 20),
                  onPressed: () {
                    setState(() {
                      _fromDate = null;
                      _toDate = null;
                      _resetPagination(clearSelection: true);
                    });
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _lightOffWhite,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _mutedCoolGray.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: _darkDeepTeal, fontSize: 13)),
            Icon(Icons.calendar_today, color: _primaryAqua, size: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _selectFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _fromDate = picked;
        _resetPagination(clearSelection: true);
      });
    }
  }

  Future<void> _selectToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: _fromDate ?? DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _toDate = picked;
        _resetPagination(clearSelection: true);
      });
    }
  }

  Widget _buildSearchBar() {
    return MobileSearchField(
      controller: _searchController,
      hintText: 'Search by name, address, age...',
      onChanged: (value) {
        setState(() {
          _searchQuery = value;
          _resetPagination(clearSelection: true);
        });
      },
    );
  }

  Widget _buildPatientCards() {
    final filteredPatients = _filteredPatients;

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

    if (filteredPatients.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              Icon(Icons.search_off, size: 64, color: _mutedCoolGray),
              const SizedBox(height: 16),
              Text(
                'No patients found',
                style: TextStyle(
                  color: _lightOffWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _patients.isEmpty
                    ? 'Add your first patient to get started'
                    : 'Try adjusting your filters or search terms',
                style: TextStyle(color: _mutedCoolGray, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(
          _pagedPatients.length,
          (index) =>
              _buildPatientCard(_pagedPatients[index], _pageStartIndex + index),
        ),
        MobilePaginationControls(
          currentPage: _safeCurrentPage,
          totalPages: _totalPages,
          totalItems: filteredPatients.length,
          startIndex: _pageStartIndex,
          endIndex: _pageEndIndex,
          rowsPerPage: _effectiveRowsPerPage,
          itemLabel: 'patients',
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
      ],
    );
  }

  Widget _buildPatientCard(Map<String, dynamic> patient, int index) {
    final firstName = patient['firstName']?.toString().trim() ?? '';
    final surname = patient['surname']?.toString().trim() ?? '';
    final patientName = '$firstName $surname'.trim();
    final location = [
      patient['barangay']?.toString().trim(),
      patient['address']?.toString().trim(),
      patient['municipality']?.toString().trim(),
    ].whereType<String>().where((value) => value.isNotEmpty).toSet().join(', ');
    final registrationDate =
        patient['registrationDate'] ?? patient['createdAt'];
    final statusLabel = patient['status']?.toString().trim().isNotEmpty == true
        ? patient['status'].toString().trim()
        : 'Active';
    final isSelected = _selectedIndices.contains(index);
    return HealthRecordCard(
      recordLabel: 'Patient record',
      patientName: patientName.isEmpty ? 'Unknown patient' : patientName,
      location: location.isEmpty ? 'Location not recorded' : location,
      accentColor: AppDesign.checkUp,
      status: statusLabel,
      isSelected: isSelected,
      showSelection: _isSelectionMode,
      onSelectionChanged: (selected) {
        setState(() {
          if (selected) {
            _selectedIndices.add(index);
          } else {
            _selectedIndices.remove(index);
            if (_selectedIndices.isEmpty) _isSelectionMode = false;
          }
        });
      },
      onTap: () {
        if (_isSelectionMode) {
          setState(() {
            if (isSelected) {
              _selectedIndices.remove(index);
              if (_selectedIndices.isEmpty) _isSelectionMode = false;
            } else {
              _selectedIndices.add(index);
            }
          });
        } else {
          _showPatientDetails(patient);
        }
      },
      onLongPress: () => _showRecordActionModal(context, patient, index),
      onAction: () => _showRecordActionModal(context, patient, index),
      metadata: [
        RecordMetadata(
          label: 'Age',
          value: patient['age']?.toString() ?? 'Not recorded',
          icon: Icons.cake_outlined,
        ),
        RecordMetadata(
          label: 'Date added',
          value: HealthRecordDate.format(registrationDate),
          icon: Icons.calendar_today_outlined,
        ),
        RecordMetadata(
          label: 'Time added',
          value: HealthRecordDate.time(registrationDate),
          icon: Icons.schedule_outlined,
        ),
      ],
    );
  }

  Future<void> _showPatientHistory(Map<String, dynamic> patient) async {
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

  void _showPatientDetails(Map<String, dynamic> patient) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppDesign.navy,
        child: Container(
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
                  color: AppDesign.navy,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white.withValues(alpha: 0.3),
                      child: Text(
                        (patient['firstName'] ?? 'P')
                            .toString()
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${patient['firstName']} ${patient['surname']}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
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
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showPatientHistory(patient);
                          },
                          icon: const Icon(Icons.timeline),
                          label: const Text('Open Cross-Module History'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryAqua,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
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
                        _buildDetailRow(Icons.numbers, 'Age', patient['age']),
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
                        _buildDetailRow(Icons.wc, 'Gender', patient['gender']),
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppDesign.navy.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _primaryAqua.withValues(alpha: 0.4)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
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
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _editPatient(Map<String, dynamic> patient) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          EditPatientModal(patient: patient, onSaved: _loadPatients),
    );
  }

  void _deletePatient(Map<String, dynamic> patient) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.red),
            const SizedBox(width: 8),
            const Text('Confirm Delete'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${patient['name']}? This action cannot be undone.',
          style: TextStyle(color: AppDesign.ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: _mutedCoolGray)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _patients.remove(patient);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${patient['name']} deleted successfully'),
                  backgroundColor: Colors.green,
                ),
              );
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
                        : 'Select Patients',
                    style: TextStyle(
                      color: AppDesign.ink,
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
          color: Colors.transparent,
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
                  '${_selectedIndices.length} patient(s) selected',
                  style: TextStyle(
                    color: AppDesign.ink,
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
                          _filteredPatients.length,
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
                    onPressed: _confirmDelete,
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
          style: TextStyle(color: AppDesign.ink),
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

      // Delete from database
      await _dbHelper.deleteRecords(patientIds);

      // Reload the patient list
      await _loadPatients();

      setState(() {
        _selectedIndices.clear();
        _isSelectionMode = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Successfully deleted $count patient(s)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
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

  void _showRecordActionModal(
    BuildContext context,
    Map<String, dynamic> patient,
    int index,
  ) {
    final patientName =
        '${patient['firstName'] ?? ''} ${patient['surname'] ?? ''}'.trim();

    MobileRecordActionSheet.show(
      context: context,
      title: patientName.isEmpty ? 'Patient Record' : patientName,
      headerIcon: Icons.person_outline_rounded,
      actions: [
        MobileRecordAction(
          label: 'View Details',
          icon: Icons.visibility_outlined,
          tone: MobileRecordActionTone.primary,
          onPressed: () => _showPatientDetails(patient),
        ),
        MobileRecordAction(
          label: 'View Health History',
          icon: Icons.timeline_rounded,
          onPressed: () => _showPatientHistory(patient),
        ),
        MobileRecordAction(
          label: 'Select Multiple',
          icon: Icons.check_box_outlined,
          onPressed: () {
            setState(() {
              _isSelectionMode = true;
              _selectedIndices.add(index);
            });
          },
        ),
        MobileRecordAction(
          label: 'Edit Record',
          icon: Icons.edit_outlined,
          onPressed: () => _editPatient(patient),
        ),
        MobileRecordAction(
          label: 'Export Form PDF / Print',
          icon: Icons.picture_as_pdf_outlined,
          onPressed: () {
            ClinicalFormPdfService.showExportDialog(
              context,
              formType: ClinicalFormType.patientRegistration,
              record: patient,
              patientName: patientName,
            );
          },
        ),
        MobileRecordAction(
          label: 'Delete Record',
          icon: Icons.delete_outline,
          tone: MobileRecordActionTone.danger,
          onPressed: () => _showDeletePatientConfirmation(context, patient),
        ),
      ],
    );
  }

  void _showDeletePatientConfirmation(
    BuildContext context,
    Map<String, dynamic> patient,
  ) {
    final patientName = '${patient['firstName']} ${patient['surname']}';

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Confirm Delete'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete the record for $patientName? This action cannot be undone.',
          style: const TextStyle(color: AppDesign.ink),
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
              final patientId = patient['id'] as String?;
              if (patientId != null) {
                try {
                  await _dbHelper.deleteRecords([patientId]);
                  await _loadPatients();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Patient record deleted successfully',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        backgroundColor: Colors.green,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
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

  // Add Patient Modal
  void _showAddPatientModal({Map<String, dynamic>? initialValues}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddPatientModal(
        initialValues: initialValues,
        onSaved: _handlePatientSaved,
      ),
    );
  }

  Future<void> _handlePatientSaved(String patientName) async {
    if (!mounted) return;
    await _loadPatients();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Patient $patientName added successfully'),
        backgroundColor: Colors.green,
      ),
    );
  }
}

// Add Patient Modal Widget
class AddPatientModal extends StatefulWidget {
  const AddPatientModal({super.key, this.initialValues, this.onSaved});

  final Map<String, dynamic>? initialValues;
  final Future<void> Function(String patientName)? onSaved;

  @override
  State<AddPatientModal> createState() => _AddPatientModalState();
}

class _AddPatientModalState extends State<AddPatientModal> {
  final _formKey = GlobalKey<FormState>();
  final _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 10;

  // Color scheme
  static const Color _primaryAqua = AppDesign.blue;
  static const Color _darkDeepTeal = AppDesign.page;
  static const Color _mutedCoolGray = AppDesign.muted;
  static const Color _lightOffWhite = AppDesign.ink;

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
  String _tempUnit = '°C';
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
    final values = widget.initialValues;
    if (values != null) {
      final name =
          (values['patientName'] ??
                  values['fullName'] ??
                  values['patient'] ??
                  values['name'] ??
                  '')
              .toString()
              .trim();
      final parts = name
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList(growable: false);
      _firstNameController.text =
          (values['firstName'] ?? (parts.isNotEmpty ? parts.first : ''))
              .toString();
      _surnameController.text =
          (values['surname'] ??
                  (parts.length > 1 ? parts.sublist(1).join(' ') : ''))
              .toString();
      _dobController.text = (values['dateOfBirth'] ?? values['dob'] ?? '')
          .toString();
      _ageController.text = (values['age'] ?? '').toString();
      _phoneController.text =
          (values['contactNumber'] ??
                  values['phoneNumber'] ??
                  values['phone'] ??
                  '')
              .toString();
      _emailController.text = (values['email'] ?? values['emailAddress'] ?? '')
          .toString();
      _streetController.text = (values['address'] ?? values['street'] ?? '')
          .toString();
      _barangayController.text = (values['barangay'] ?? '').toString();
      _municipalityController.text = (values['municipality'] ?? '').toString();
      _provinceController.text = (values['province'] ?? '').toString();
      _chiefComplaintController.text =
          (values['symptoms'] ?? values['chiefComplaint'] ?? '').toString();
      _currentSymptomsController.text =
          (values['symptoms'] ?? values['chiefComplaint'] ?? '').toString();
      _bodyTempController.text = (values['temperature'] ?? values['temp'] ?? '')
          .toString();
      _heartRateController.text =
          (values['heartRate'] ?? values['hr'] ?? values['pulse'] ?? '')
              .toString();
      _respiratoryRateController.text =
          (values['respiratoryRate'] ?? values['rr'] ?? '').toString();
      _oxygenSaturationController.text =
          (values['oxygenSaturation'] ?? values['spo2'] ?? '').toString();
      _weightController.text = (values['weight'] ?? values['wt'] ?? '')
          .toString();
      _heightController.text = (values['height'] ?? values['ht'] ?? '')
          .toString();

      final bp = (values['bloodPressure'] ?? values['bp'] ?? '')
          .toString()
          .trim();
      if (bp.isNotEmpty) {
        final bpParts = bp.split('/');
        if (bpParts.length == 2) {
          _bpSystolicController.text = bpParts[0].trim();
          _bpDiastolicController.text = bpParts[1].trim();
        }
      }

      if (values['gender'] != null || values['sex'] != null) {
        final g = (values['gender'] ?? values['sex']).toString().toLowerCase();
        if (g == 'female' || g == 'f') {
          _gender = 'Female';
        } else if (g == 'male' || g == 'm') {
          _gender = 'Male';
        }
      }
      if (values['civilStatus'] != null) {
        final cs = values['civilStatus'].toString();
        if (['Single', 'Married', 'Widowed', 'Separated'].contains(cs)) {
          _civilStatus = cs;
        }
      }
    }
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
        appBar: AppBar(
          backgroundColor: AppDesign.surface,
          title: const Text(
            'Add New Patient',
            style: TextStyle(
              color: AppDesign.ink,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: AppDesign.ink),
            onPressed: () => _showExitConfirmation(),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.save_outlined, color: AppDesign.blue),
              label: const Text(
                'Save',
                style: TextStyle(
                  color: AppDesign.blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onPressed: _savePatient,
            ),
          ],
        ),
        body: Column(
          children: [
            _buildProgressIndicator(),
            Expanded(
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
                    // Wrapped with _KeepAlivePage so every page's
                    // TextFormFields stay registered with _formKey's Form
                    // even after scrolling off-screen; otherwise PageView
                    // disposes off-screen pages and validate() would skip
                    // required fields that aren't on the current page.
                    _KeepAlivePage(child: _buildPersonalDetailsPage()),
                    _KeepAlivePage(child: _buildContactInformationPage()),
                    _KeepAlivePage(child: _buildMedicalDetailsPage()),
                    _KeepAlivePage(child: _buildVitalSignsPage()),
                    _KeepAlivePage(child: _buildEmergencyContactPage()),
                    _KeepAlivePage(child: _buildLifestyleHabitsPage()),
                    _KeepAlivePage(child: _buildMorbidityAssessmentPage()),
                    _KeepAlivePage(child: _buildInsuranceCoveragePage()),
                    _KeepAlivePage(child: _buildAdditionalDetailsPage()),
                    _KeepAlivePage(child: _buildConsentAndRegistrationPage()),
                  ],
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: AppDesign.surface,
      child: Column(
        children: [
          Row(
            children: List.generate(_totalPages, (index) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: index <= _currentPage
                        ? _primaryAqua
                        : AppDesign.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'Step ${_currentPage + 1} of $_totalPages: ${_getPageTitle()}',
            style: TextStyle(
              color: AppDesign.muted,
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: AppDesign.surface,
        boxShadow: [
          BoxShadow(
            color: AppDesign.navy.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentPage > 0)
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('Previous'),
                onPressed: () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppDesign.navy,
                  side: const BorderSide(color: AppDesign.borderStrong),
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(vertical: 11),
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
              ),
              label: Text(_currentPage < _totalPages - 1 ? 'Next' : 'Complete'),
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
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(vertical: 11),
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
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
          ),
          _buildTextField(
            'Surname',
            _surnameController,
            required: true,
            hint: 'Enter surname/last name',
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
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
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
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
          Text(
            'Address',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppDesign.navy,
            ),
          ),
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
                  '°C',
                  '°F',
                ], (value) => setState(() => _tempUnit = value!)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Blood Pressure',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppDesign.ink,
            ),
          ),
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
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
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
              color: _darkDeepTeal,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _lightOffWhite.withValues(alpha: 0.3)),
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
                    ),
                    Expanded(
                      child: Text(
                        'I consent to the collection, storage, and processing of my personal and medical information for healthcare purposes in accordance with data privacy laws.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppDesign.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
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
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
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
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppDesign.navy,
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
    FormFieldValidator<String>? validator,
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppDesign.ink,
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
            maxLines: maxLines,
            keyboardType: keyboardType,
            style: const TextStyle(color: AppDesign.ink, fontSize: 14),
            validator: validator,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppDesign.subtle),
              filled: true,
              fillColor: AppDesign.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppDesign.borderStrong),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppDesign.borderStrong),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppDesign.ink,
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
              color: AppDesign.surface,
              borderRadius: BorderRadius.circular(12),
              border: const Border.fromBorderSide(
                BorderSide(color: AppDesign.borderStrong),
              ),
            ),
            child: DropdownButtonFormField<String>(
              initialValue: value,
              style: const TextStyle(color: AppDesign.ink, fontSize: 14),
              decoration: InputDecoration(
                border: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              dropdownColor: AppDesign.surface,
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(
                    item,
                    style: const TextStyle(color: AppDesign.ink),
                  ),
                );
              }).toList(),
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppDesign.ink,
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
            style: const TextStyle(color: AppDesign.ink, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'mm/dd/yyyy',
              hintStyle: const TextStyle(color: AppDesign.subtle),
              filled: true,
              fillColor: AppDesign.surface,
              suffixIcon: Icon(
                Icons.calendar_today_outlined,
                color: AppDesign.muted,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppDesign.borderStrong),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppDesign.borderStrong),
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

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppDesign.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Discard Changes?',
          style: TextStyle(color: AppDesign.ink),
        ),
        content: const Text(
          'Are you sure you want to exit? All unsaved data will be lost.',
          style: TextStyle(color: AppDesign.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _primaryAqua)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close modal
            },
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
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
    if (!(_formKey.currentState?.validate() ?? false)) {
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

      final patientName =
          '${_firstNameController.text.trim()} ${_surnameController.text.trim()}'
              .trim();
      if (!context.mounted) return;

      // The dialog route is not a descendant of PatientRecordPage, so an
      // ancestor-state lookup cannot reliably reach the page that owns the
      // patient list. Notify it through the explicit callback instead.
      Navigator.pop(context);
      await widget.onSaved?.call(patientName);
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

// Keeps a PageView page's element tree alive when scrolled off-screen so its
// TextFormFields stay registered with the modal's shared Form/validate().
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
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
  final _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 10;

  // Color scheme
  static const Color _primaryAqua = AppDesign.blue;
  static const Color _mutedCoolGray = AppDesign.muted;

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
    _tempUnit = p['temperatureUnit']?.toString() ?? '°C';
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
    _mentalHealthStatus = p['mentalHealthStatus']?.toString() ?? 'Good';
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

    _smokingStatus = p['smokingStatus']?.toString() ?? 'Never';
    _exerciseFrequency = p['exerciseFrequency']?.toString() ?? 'Daily';
    _alcoholConsumption = p['alcoholConsumption']?.toString() ?? 'Never';
    _dietaryRestrictionsController = TextEditingController(
      text: p['dietaryRestrictions']?.toString() ?? '',
    );
    _mentalHealthStatusLifestyle =
        p['mentalHealthStatusLifestyle']?.toString() ?? 'Good';
    _sleepQuality = p['sleepQuality']?.toString() ?? 'Excellent';

    _morbidityRiskLevel = p['morbidityRiskLevel']?.toString() ?? 'Low';
    _numberOfComorbiditiesController = TextEditingController(
      text: p['numberOfComorbidities']?.toString() ?? '',
    );
    _functionalStatus = p['functionalStatus']?.toString() ?? 'Independent';
    _mobilityStatus = p['mobilityStatus']?.toString() ?? 'Fully Mobile';
    _frailtyIndexController = TextEditingController(
      text: p['frailtyIndex']?.toString() ?? '',
    );
    _polypharmacyRisk = p['polypharmacyRisk']?.toString() ?? 'Low';
    _preventiveCareCompliance =
        p['preventiveCareCompliance']?.toString() ?? 'Full Compliance';
    _healthLiteracyLevel = p['healthLiteracyLevel']?.toString() ?? 'High';
    _socialSupportLevel = p['socialSupportLevel']?.toString() ?? 'Strong';
    _economicStatusImpact = p['economicStatusImpact']?.toString() ?? 'Minimal';
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
    _pageController.dispose();
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
        backgroundColor: AppDesign.page,
        appBar: AppBar(
          backgroundColor: AppDesign.surface,
          title: const Text(
            'Edit Patient',
            style: TextStyle(
              color: AppDesign.ink,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: AppDesign.ink),
            onPressed: () => _showExitConfirmation(),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.save_outlined, color: AppDesign.blue),
              label: const Text(
                'Update',
                style: TextStyle(
                  color: AppDesign.blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onPressed: _updatePatient,
            ),
          ],
        ),
        body: Column(
          children: [
            // Progress Indicator
            Container(
              color: AppDesign.surface,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (_currentPage + 1) / _totalPages,
                      backgroundColor: _mutedCoolGray.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(_primaryAqua),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '${_currentPage + 1}/$_totalPages',
                    style: TextStyle(
                      color: AppDesign.navy,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            // Form Content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                children: [
                  _buildPersonalDetailsPage(),
                  _buildContactInfoPage(),
                  _buildMedicalDetailsPage(),
                  _buildVitalSignsPage(),
                  _buildHealthStatusPage(),
                  _buildEmergencyContactPage(),
                  _buildLifestylePage(),
                  _buildMorbidityAssessmentPage(),
                  _buildInsurancePage(),
                  _buildFinalPage(),
                ],
              ),
            ),

            // Navigation Buttons
            Container(
              color: AppDesign.surface,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Previous'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppDesign.navy,
                          side: const BorderSide(color: AppDesign.borderStrong),
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(vertical: 11),
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
                      onPressed: () {
                        if (_currentPage < _totalPages - 1) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else {
                          _updatePatient();
                        }
                      },
                      icon: Icon(
                        _currentPage < _totalPages - 1
                            ? Icons.arrow_forward
                            : Icons.check,
                      ),
                      label: Text(
                        _currentPage < _totalPages - 1
                            ? 'Next'
                            : 'Update Patient',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryAqua,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
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
  }

  // Page 1: Personal Details (same as Add but with pre-filled data)
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
  Widget _buildContactInfoPage() {
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
          Text(
            'Address',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppDesign.navy,
            ),
          ),
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
            hint: 'Body Mass Index',
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
            hint: 'List any known allergies',
          ),
          _buildTextField(
            'Immunization Status',
            _immunizationStatusController,
            maxLines: 2,
            hint: 'Vaccination history',
          ),
          _buildTextField(
            'Family Medical History',
            _familyMedicalHistoryController,
            maxLines: 3,
            hint: 'Hereditary conditions',
          ),
          _buildTextField(
            'Past Medical History',
            _pastMedicalHistoryController,
            maxLines: 3,
            hint: 'Previous illnesses, surgeries',
          ),
          _buildTextField(
            'Current Medications',
            _currentMedicationsController,
            maxLines: 2,
            hint: 'Medications currently taking',
          ),
          _buildTextField(
            'Chronic Conditions',
            _chronicConditionsController,
            maxLines: 2,
            hint: 'Long-term health conditions',
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
            hint: 'Current symptoms',
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
                  hint: 'e.g., 36.5',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdownField('Unit', _tempUnit, [
                  '°C',
                  '°F',
                ], (value) => setState(() => _tempUnit = value!)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Blood Pressure',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppDesign.ink,
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
                    style: TextStyle(fontSize: 13, color: AppDesign.ink),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
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
        color: AppDesign.navy,
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
                  color: AppDesign.ink,
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
            maxLines: maxLines,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
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
                  color: AppDesign.ink,
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: DropdownButtonFormField<String>(
              initialValue: value,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: items
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
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
                  color: AppDesign.ink,
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
            decoration: InputDecoration(
              hintText: 'mm/dd/yyyy',
              filled: true,
              fillColor: Colors.white,
              suffixIcon: const Icon(Icons.calendar_today),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
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

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppDesign.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Discard Changes?',
          style: TextStyle(color: AppDesign.ink),
        ),
        content: const Text(
          'Are you sure you want to exit without saving changes?',
          style: TextStyle(color: AppDesign.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _primaryAqua)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close modal
            },
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
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
