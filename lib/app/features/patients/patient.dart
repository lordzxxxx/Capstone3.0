import 'package:firebase_auth/firebase_auth.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
  final _patientHistoryService = PatientCenteredHistoryService();

  // Color scheme matching Check-up modal
  static const Color _primaryAqua = AppDesign.blue;
  static const Color _darkDeepTeal = AppDesign.page;
  static const Color _mutedCoolGray = AppDesign.muted;
  static const Color _lightOffWhite = AppDesign.ink;

  // Controllers for Canonical Details & Credentials (consistent with Web)
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _dateOfBirthController = TextEditingController();
  final _ageController = TextEditingController();
  final _addressController = TextEditingController();
  final _barangayController = TextEditingController();
  final _householdIdController = TextEditingController();
  final _contactNumberController = TextEditingController();
  final _guardianController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _emergencyRelationshipController = TextEditingController();
  final _emergencyContactNumberController = TextEditingController();
  final _medicalHistoryController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _registrationDateController = TextEditingController();
  final _registeredByController = TextEditingController();

  late final String _patientId;
  DateTime? _dateOfBirth;
  String _sex = 'Female';
  bool _consentGiven = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final values = widget.initialValues ?? const <String, dynamic>{};
    _patientId = (values['patientId'] ?? values['id'] ?? PatientDatabaseHelper.generatePatientId()).toString().trim();

    final directFirst = (values['firstName'] ?? '').toString().trim();
    final directMiddle = (values['middleName'] ?? '').toString().trim();
    final directSurname = (values['surname'] ?? '').toString().trim();
    if (directFirst.isNotEmpty || directSurname.isNotEmpty) {
      _firstNameController.text = directFirst;
      _middleNameController.text = directMiddle;
      _surnameController.text = directSurname;
    } else {
      final name = (values['fullName'] ?? values['patientName'] ?? values['patient'] ?? values['name'] ?? '').toString().trim();
      if (name.contains(',')) {
        final commaParts = name.split(',');
        _surnameController.text = commaParts.first.trim();
        _firstNameController.text = commaParts.sublist(1).join(' ').trim();
      } else {
        final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList(growable: false);
        _firstNameController.text = parts.isNotEmpty ? parts.first : '';
        _surnameController.text = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }
    }

    _dateOfBirthController.text = (values['dateOfBirth'] ?? values['dob'] ?? '').toString().trim();
    _dateOfBirth = DateTime.tryParse(_dateOfBirthController.text);
    
    final rawAge = (values['age'] ?? '').toString().trim();
    final ageDigits = RegExp(r'\d+').firstMatch(rawAge);
    _ageController.text = ageDigits != null ? ageDigits.group(0)! : rawAge;

    final sexVal = (values['sex'] ?? values['gender'] ?? 'Female').toString().trim();
    _sex = const ['Female', 'Male', 'Other'].contains(sexVal) ? sexVal : 'Female';

    _addressController.text = (values['address'] ?? values['street'] ?? '').toString().trim();
    _householdIdController.text = (values['householdId'] ?? '').toString().trim();
    _contactNumberController.text = (values['contactNumber'] ?? values['phoneNumber'] ?? values['phone'] ?? '').toString().trim();
    _guardianController.text = (values['guardian'] ?? values['parentName'] ?? values['parentGuardianName'] ?? '').toString().trim();
    _emergencyContactController.text = (values['emergencyContact'] ?? values['emergencyContactName'] ?? '').toString().trim();
    _emergencyRelationshipController.text = (values['emergencyRelationship'] ?? '').toString().trim();
    _emergencyContactNumberController.text = (values['emergencyContactNumber'] ?? values['emergencyContactPhone'] ?? '').toString().trim();
    _medicalHistoryController.text = (values['medicalHistory'] ?? values['pastMedicalHistory'] ?? '').toString().trim();
    _allergiesController.text = (values['allergies'] ?? '').toString().trim();

    final now = DateTime.now();
    _registrationDateController.text = (values['registrationDate'] ?? '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}').toString().trim();

    String? currentUserName;
    try {
      final user = FirebaseAuth.instance.currentUser;
      currentUserName = user?.displayName ?? user?.email;
    } catch (_) {}
    _registeredByController.text = (values['registeredBy'] ?? currentUserName ?? 'BHW').toString().trim();

    final initialBarangay = (values['barangay'] ?? '').toString().trim();
    if (initialBarangay.isNotEmpty) {
      _barangayController.text = initialBarangay;
    } else {
      _loadAssignedBarangay();
    }
  }

  Future<void> _loadAssignedBarangay() async {
    try {
      final scope = await UserAccessScopeService.instance.loadCurrentScope();
      if (!mounted || scope.barangay.isEmpty) return;
      setState(() => _barangayController.text = scope.barangay);
    } catch (_) {}
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _surnameController.dispose();
    _dateOfBirthController.dispose();
    _ageController.dispose();
    _addressController.dispose();
    _barangayController.dispose();
    _householdIdController.dispose();
    _contactNumberController.dispose();
    _guardianController.dispose();
    _emergencyContactController.dispose();
    _emergencyRelationshipController.dispose();
    _emergencyContactNumberController.dispose();
    _medicalHistoryController.dispose();
    _allergiesController.dispose();
    _registrationDateController.dispose();
    _registeredByController.dispose();
    super.dispose();
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 20),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (selected == null) return;
    final age = _calculateAge(selected, now);
    setState(() {
      _dateOfBirth = selected;
      _dateOfBirthController.text = '${selected.year}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
      _ageController.text = age.toString();
    });
  }

  int _calculateAge(DateTime birthDate, DateTime today) {
    var age = today.year - birthDate.year;
    if (today.month < birthDate.month || (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age < 0 ? 0 : age;
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _lightOffWhite.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _lightOffWhite,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, {String? hintText, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      labelStyle: const TextStyle(color: _lightOffWhite),
      hintStyle: TextStyle(color: _lightOffWhite.withValues(alpha: 0.5)),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _lightOffWhite.withValues(alpha: 0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _lightOffWhite.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryAqua, width: 2),
      ),
      filled: true,
      fillColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  Future<void> _savePatient() async {
    if (!_consentGiven) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please confirm patient consent and data privacy compliance.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false) || _isSaving) {
      return;
    }

    final firstName = _firstNameController.text.trim();
    final middleName = _middleNameController.text.trim();
    final surname = _surnameController.text.trim();

    setState(() => _isSaving = true);

    try {
      final duplicates = await _patientHistoryService.findDuplicateCandidates(
        firstName: firstName,
        surname: surname,
        dateOfBirth: _dateOfBirthController.text.trim(),
        phoneNumber: _contactNumberController.text.trim(),
      );

      if (!mounted) return;
      if (duplicates.isNotEmpty) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: _darkDeepTeal,
            title: const Text(
              'Patient May Already Be Registered',
              style: TextStyle(color: _lightOffWhite, fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'A matching patient record already exists. Are you sure you want to register this patient as a new separate entry?',
              style: TextStyle(color: _mutedCoolGray),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel', style: TextStyle(color: _mutedCoolGray)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: _primaryAqua, foregroundColor: Colors.white),
                child: const Text('Proceed Anyway'),
              ),
            ],
          ),
        );
        if (proceed != true) {
          setState(() => _isSaving = false);
          return;
        }
      }

      final fullName = [firstName, middleName, surname].where((s) => s.isNotEmpty).join(' ');
      final address = _addressController.text.trim();
      final contact = _contactNumberController.text.trim();
      final emergencyContact = _emergencyContactController.text.trim();
      final emergencyContactNumber = _emergencyContactNumberController.text.trim();
      final medicalHistory = _medicalHistoryController.text.trim();
      String? currentUserName;
      try {
        final user = FirebaseAuth.instance.currentUser;
        currentUserName = user?.displayName ?? user?.email;
      } catch (_) {}
      final registeredBy = _registeredByController.text.trim().isNotEmpty
          ? _registeredByController.text.trim()
          : (currentUserName ?? 'BHW');

      final patientData = <String, dynamic>{
        'id': _patientId,
        'patientId': _patientId,
        'fullName': fullName,
        'firstName': firstName,
        'middleName': middleName,
        'surname': surname,
        'dateOfBirth': _dateOfBirthController.text.trim(),
        'dob': _dateOfBirthController.text.trim(),
        'age': _ageController.text.trim(),
        'gender': _sex,
        'sex': _sex,
        'address': address,
        'street': address,
        'barangay': _barangayController.text.trim(),
        'householdId': _householdIdController.text.trim(),
        'phoneNumber': contact,
        'contactNumber': contact,
        'phone': contact,
        'guardian': _guardianController.text.trim(),
        'parentName': _guardianController.text.trim(),
        'emergencyContactName': emergencyContact,
        'emergencyContact': emergencyContact,
        'emergencyRelationship': _emergencyRelationshipController.text.trim(),
        'emergencyContactPhone': emergencyContactNumber,
        'emergencyContactNumber': emergencyContactNumber,
        'medicalHistory': medicalHistory,
        'pastMedicalHistory': medicalHistory,
        'allergies': _allergiesController.text.trim(),
        'registrationDate': _registrationDateController.text.trim(),
        'registeredBy': registeredBy,
        'consentGiven': _consentGiven.toString(),
        'status': 'Active',
      };

      final dbHelper = PatientDatabaseHelper.instance;
      await dbHelper.insertRecord(patientData);

      if (!mounted) return;
      Navigator.pop(context, true);
      await widget.onSaved?.call(fullName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving patient: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.95,
      minChildSize: 0.7,
      maxChildSize: 0.98,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: _darkDeepTeal,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with Close and Export buttons
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Add New Patient',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: _lightOffWhite,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'One-time canonical patient registration used across all health modules',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: _lightOffWhite.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Print / Export Patient Form PDF',
                        icon: const Icon(
                          Icons.picture_as_pdf_outlined,
                          color: _primaryAqua,
                          size: 22,
                        ),
                        onPressed: () {
                          ClinicalFormPdfService.showExportDialog(
                            context,
                            formType: ClinicalFormType.patientRegistration,
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: _lightOffWhite.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close, color: _lightOffWhite, size: 24),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Auto-generated Patient ID Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _primaryAqua.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _primaryAqua.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.badge_outlined, color: _primaryAqua, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Patient ID (Auto-generated)',
                                style: TextStyle(
                                  color: _mutedCoolGray,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              SelectableText(
                                _patientId,
                                style: const TextStyle(
                                  color: _lightOffWhite,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Section 1: Patient Identity
                  _buildSectionCard(
                    context: context,
                    title: 'Patient Identity',
                    icon: Icons.person_outline_rounded,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _firstNameController,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('First Name *', hintText: 'Given name'),
                                validator: (val) => val?.trim().isEmpty == true ? 'First Name is required' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _surnameController,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Surname *', hintText: 'Family name'),
                                validator: (val) => val?.trim().isEmpty == true ? 'Surname is required' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _middleNameController,
                          style: const TextStyle(color: _lightOffWhite),
                          decoration: _buildInputDecoration('Middle Name (Optional)', hintText: 'Middle name'),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _dateOfBirthController,
                                readOnly: true,
                                onTap: _pickDateOfBirth,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration(
                                  'Date of Birth *',
                                  hintText: 'YYYY-MM-DD',
                                  suffixIcon: const Icon(Icons.calendar_today_outlined, color: _primaryAqua),
                                ),
                                validator: (val) => val?.trim().isEmpty == true ? 'Date of Birth is required' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 1,
                              child: TextFormField(
                                controller: _ageController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Age', hintText: 'Auto / manual'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _sex,
                          dropdownColor: _darkDeepTeal,
                          style: const TextStyle(color: _lightOffWhite),
                          decoration: _buildInputDecoration('Sex / Gender *'),
                          items: const ['Female', 'Male', 'Other']
                              .map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(color: _lightOffWhite))))
                              .toList(growable: false),
                          onChanged: (v) => setState(() => _sex = v ?? _sex),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Section 2: Address and Contact Information
                  _buildSectionCard(
                    context: context,
                    title: 'Address & Contact Information',
                    icon: Icons.home_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _addressController,
                          maxLines: 2,
                          style: const TextStyle(color: _lightOffWhite),
                          decoration: _buildInputDecoration('Address *', hintText: 'House number, street, or purok'),
                          validator: (val) => val?.trim().isEmpty == true ? 'Address is required' : null,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _barangayController,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Barangay *', hintText: 'Assigned barangay'),
                                validator: (val) => val?.trim().isEmpty == true ? 'Barangay is required' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _householdIdController,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Household ID (Optional)', hintText: 'Family record #'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _contactNumberController,
                                keyboardType: TextInputType.phone,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Phone Number', hintText: '09XXXXXXXXX'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _guardianController,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Parent/Guardian (Optional)', hintText: 'For dependents'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Section 3: Emergency Contact
                  _buildSectionCard(
                    context: context,
                    title: 'Emergency Contact',
                    icon: Icons.contact_phone_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _emergencyContactController,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Emergency Contact Name *', hintText: 'Full name'),
                                validator: (val) => val?.trim().isEmpty == true ? 'Emergency Contact Name is required' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _emergencyRelationshipController,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Relationship', hintText: 'Parent, spouse, sibling'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _emergencyContactNumberController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: _lightOffWhite),
                          decoration: _buildInputDecoration('Emergency Contact Number *', hintText: '09XXXXXXXXX'),
                          validator: (val) => val?.trim().isEmpty == true ? 'Emergency Contact Number is required' : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Section 4: Baseline Health Information
                  _buildSectionCard(
                    context: context,
                    title: 'Baseline Health Information',
                    icon: Icons.health_and_safety_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _medicalHistoryController,
                          maxLines: 3,
                          style: const TextStyle(color: _lightOffWhite),
                          decoration: _buildInputDecoration(
                            'Medical History',
                            hintText: 'Existing conditions, previous diagnoses, or "None"',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _allergiesController,
                          maxLines: 2,
                          style: const TextStyle(color: _lightOffWhite),
                          decoration: _buildInputDecoration(
                            'Allergies (Optional)',
                            hintText: 'Food, medicine, environmental allergies, or leave blank',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Section 5: Registration Details & Consent
                  _buildSectionCard(
                    context: context,
                    title: 'Registration & Data Consent',
                    icon: Icons.verified_user_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _registrationDateController,
                                readOnly: true,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Registration Date'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _registeredByController,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Registered By'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        InkWell(
                          onTap: () => setState(() => _consentGiven = !_consentGiven),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _consentGiven,
                                  activeColor: _primaryAqua,
                                  onChanged: (val) => setState(() => _consentGiven = val ?? true),
                                ),
                                const Expanded(
                                  child: Text(
                                    'I confirm patient consent and compliance with data privacy policies.',
                                    style: TextStyle(color: _lightOffWhite, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Service Interoperability Info Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _primaryAqua.withValues(alpha: 0.24)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, color: _primaryAqua, size: 22),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'After registration, this patient becomes searchable in Check-up, Prenatal, Immunization, Morbidity, Mortality, and Referrals.',
                            style: TextStyle(color: _lightOffWhite, height: 1.45, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Bottom Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _lightOffWhite,
                            side: BorderSide(color: _lightOffWhite.withValues(alpha: 0.3)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _savePatient,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryAqua,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.person_add_alt_1_rounded, size: 20),
                          label: Text(
                            _isSaving ? 'Registering...' : 'Register Patient',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Edit Patient Modal Widget
class EditPatientModal extends StatefulWidget {
  final Map<String, dynamic> patient;
  final VoidCallback? onSaved;

  const EditPatientModal({
    super.key,
    required this.patient,
    this.onSaved,
  });

  @override
  State<EditPatientModal> createState() => _EditPatientModalState();
}

class _EditPatientModalState extends State<EditPatientModal> {
  final _formKey = GlobalKey<FormState>();

  static const Color _primaryAqua = AppDesign.blue;
  static const Color _darkDeepTeal = AppDesign.page;
  static const Color _mutedCoolGray = AppDesign.muted;
  static const Color _lightOffWhite = AppDesign.ink;

  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _dateOfBirthController = TextEditingController();
  final _ageController = TextEditingController();
  final _addressController = TextEditingController();
  final _barangayController = TextEditingController();
  final _householdIdController = TextEditingController();
  final _contactNumberController = TextEditingController();
  final _guardianController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _emergencyRelationshipController = TextEditingController();
  final _emergencyContactNumberController = TextEditingController();
  final _medicalHistoryController = TextEditingController();
  final _allergiesController = TextEditingController();

  late final String _patientId;
  DateTime? _dateOfBirth;
  String _sex = 'Female';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final patient = widget.patient;
    _patientId = (patient['patientId'] ?? patient['id'] ?? '').toString().trim();

    final directFirst = (patient['firstName'] ?? '').toString().trim();
    final directMiddle = (patient['middleName'] ?? '').toString().trim();
    final directSurname = (patient['surname'] ?? '').toString().trim();
    if (directFirst.isNotEmpty || directSurname.isNotEmpty) {
      _firstNameController.text = directFirst;
      _middleNameController.text = directMiddle;
      _surnameController.text = directSurname;
    } else {
      final name = (patient['fullName'] ?? patient['patientName'] ?? patient['patient'] ?? patient['name'] ?? '').toString().trim();
      if (name.contains(',')) {
        final commaParts = name.split(',');
        _surnameController.text = commaParts.first.trim();
        _firstNameController.text = commaParts.sublist(1).join(' ').trim();
      } else {
        final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList(growable: false);
        _firstNameController.text = parts.isNotEmpty ? parts.first : '';
        _surnameController.text = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }
    }

    _dateOfBirthController.text = (patient['dateOfBirth'] ?? patient['dob'] ?? '').toString().trim();
    _dateOfBirth = DateTime.tryParse(_dateOfBirthController.text);

    final rawAge = (patient['age'] ?? '').toString().trim();
    final ageDigits = RegExp(r'\d+').firstMatch(rawAge);
    _ageController.text = ageDigits != null ? ageDigits.group(0)! : rawAge;

    final sexVal = (patient['sex'] ?? patient['gender'] ?? 'Female').toString().trim();
    _sex = const ['Female', 'Male', 'Other'].contains(sexVal) ? sexVal : 'Female';

    _addressController.text = (patient['address'] ?? patient['street'] ?? '').toString().trim();
    _barangayController.text = (patient['barangay'] ?? '').toString().trim();
    _householdIdController.text = (patient['householdId'] ?? '').toString().trim();
    _contactNumberController.text = (patient['contactNumber'] ?? patient['phoneNumber'] ?? patient['phone'] ?? '').toString().trim();
    _guardianController.text = (patient['guardian'] ?? patient['parentName'] ?? patient['parentGuardianName'] ?? '').toString().trim();
    _emergencyContactController.text = (patient['emergencyContact'] ?? patient['emergencyContactName'] ?? '').toString().trim();
    _emergencyRelationshipController.text = (patient['emergencyRelationship'] ?? '').toString().trim();
    _emergencyContactNumberController.text = (patient['emergencyContactNumber'] ?? patient['emergencyContactPhone'] ?? '').toString().trim();
    _medicalHistoryController.text = (patient['medicalHistory'] ?? patient['pastMedicalHistory'] ?? '').toString().trim();
    _allergiesController.text = (patient['allergies'] ?? '').toString().trim();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _surnameController.dispose();
    _dateOfBirthController.dispose();
    _ageController.dispose();
    _addressController.dispose();
    _barangayController.dispose();
    _householdIdController.dispose();
    _contactNumberController.dispose();
    _guardianController.dispose();
    _emergencyContactController.dispose();
    _emergencyRelationshipController.dispose();
    _emergencyContactNumberController.dispose();
    _medicalHistoryController.dispose();
    _allergiesController.dispose();
    super.dispose();
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 20),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (selected == null) return;
    final age = _calculateAge(selected, now);
    setState(() {
      _dateOfBirth = selected;
      _dateOfBirthController.text = '${selected.year}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
      _ageController.text = age.toString();
    });
  }

  int _calculateAge(DateTime birthDate, DateTime today) {
    var age = today.year - birthDate.year;
    if (today.month < birthDate.month || (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age < 0 ? 0 : age;
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _lightOffWhite.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _lightOffWhite,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, {String? hintText, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      labelStyle: const TextStyle(color: _lightOffWhite),
      hintStyle: TextStyle(color: _lightOffWhite.withValues(alpha: 0.5)),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _lightOffWhite.withValues(alpha: 0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _lightOffWhite.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryAqua, width: 2),
      ),
      filled: true,
      fillColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  Future<void> _saveChanges() async {
    if (!(_formKey.currentState?.validate() ?? false) || _isSaving) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final firstName = _firstNameController.text.trim();
      final middleName = _middleNameController.text.trim();
      final surname = _surnameController.text.trim();
      final fullName = [firstName, middleName, surname].where((s) => s.isNotEmpty).join(' ');
      final address = _addressController.text.trim();
      final contact = _contactNumberController.text.trim();
      final emergencyContact = _emergencyContactController.text.trim();
      final emergencyContactNumber = _emergencyContactNumberController.text.trim();
      final medicalHistory = _medicalHistoryController.text.trim();

      final existing = widget.patient;
      final updatedData = <String, dynamic>{
        ...existing,
        'id': _patientId,
        'patientId': _patientId,
        'fullName': fullName,
        'firstName': firstName,
        'middleName': middleName,
        'surname': surname,
        'dateOfBirth': _dateOfBirthController.text.trim(),
        'dob': _dateOfBirthController.text.trim(),
        'age': _ageController.text.trim(),
        'gender': _sex,
        'sex': _sex,
        'address': address,
        'street': address,
        'barangay': _barangayController.text.trim(),
        'householdId': _householdIdController.text.trim(),
        'phoneNumber': contact,
        'contactNumber': contact,
        'phone': contact,
        'guardian': _guardianController.text.trim(),
        'parentName': _guardianController.text.trim(),
        'emergencyContactName': emergencyContact,
        'emergencyContact': emergencyContact,
        'emergencyRelationship': _emergencyRelationshipController.text.trim(),
        'emergencyContactPhone': emergencyContactNumber,
        'emergencyContactNumber': emergencyContactNumber,
        'medicalHistory': medicalHistory,
        'pastMedicalHistory': medicalHistory,
        'allergies': _allergiesController.text.trim(),
      };

      final recordId = (existing['id'] ?? _patientId).toString();
      await PatientDatabaseHelper.instance.updateRecord(recordId, updatedData);

      if (!mounted) return;
      Navigator.pop(context, true);
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating patient: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.95,
      minChildSize: 0.7,
      maxChildSize: 0.98,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: _darkDeepTeal,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with Close and Export buttons
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit Patient Record',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: _lightOffWhite,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Update patient identity, contact, and medical information',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: _lightOffWhite.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Print / Export Patient Form PDF',
                        icon: const Icon(
                          Icons.picture_as_pdf_outlined,
                          color: _primaryAqua,
                          size: 22,
                        ),
                        onPressed: () {
                          ClinicalFormPdfService.showExportDialog(
                            context,
                            formType: ClinicalFormType.patientRegistration,
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: _lightOffWhite.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close, color: _lightOffWhite, size: 24),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Patient ID Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _primaryAqua.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _primaryAqua.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.badge_outlined, color: _primaryAqua, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Patient ID',
                                style: TextStyle(
                                  color: _mutedCoolGray,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              SelectableText(
                                _patientId,
                                style: const TextStyle(
                                  color: _lightOffWhite,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Section 1: Patient Identity
                  _buildSectionCard(
                    context: context,
                    title: 'Patient Identity',
                    icon: Icons.person_outline_rounded,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _firstNameController,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('First Name *', hintText: 'Given name'),
                                validator: (val) => val?.trim().isEmpty == true ? 'First Name is required' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _surnameController,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Surname *', hintText: 'Family name'),
                                validator: (val) => val?.trim().isEmpty == true ? 'Surname is required' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _middleNameController,
                          style: const TextStyle(color: _lightOffWhite),
                          decoration: _buildInputDecoration('Middle Name (Optional)', hintText: 'Middle name'),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _dateOfBirthController,
                                readOnly: true,
                                onTap: _pickDateOfBirth,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration(
                                  'Date of Birth *',
                                  hintText: 'YYYY-MM-DD',
                                  suffixIcon: const Icon(Icons.calendar_today_outlined, color: _primaryAqua),
                                ),
                                validator: (val) => val?.trim().isEmpty == true ? 'Date of Birth is required' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 1,
                              child: TextFormField(
                                controller: _ageController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Age', hintText: 'Auto / manual'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _sex,
                          dropdownColor: _darkDeepTeal,
                          style: const TextStyle(color: _lightOffWhite),
                          decoration: _buildInputDecoration('Sex / Gender *'),
                          items: const ['Female', 'Male', 'Other']
                              .map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(color: _lightOffWhite))))
                              .toList(growable: false),
                          onChanged: (v) => setState(() => _sex = v ?? _sex),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Section 2: Address and Contact Information
                  _buildSectionCard(
                    context: context,
                    title: 'Address & Contact Information',
                    icon: Icons.home_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _addressController,
                          maxLines: 2,
                          style: const TextStyle(color: _lightOffWhite),
                          decoration: _buildInputDecoration('Address *', hintText: 'House number, street, or purok'),
                          validator: (val) => val?.trim().isEmpty == true ? 'Address is required' : null,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _barangayController,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Barangay *', hintText: 'Assigned barangay'),
                                validator: (val) => val?.trim().isEmpty == true ? 'Barangay is required' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _householdIdController,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Household ID (Optional)', hintText: 'Family record #'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _contactNumberController,
                                keyboardType: TextInputType.phone,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Phone Number', hintText: '09XXXXXXXXX'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _guardianController,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Parent/Guardian (Optional)', hintText: 'For dependents'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Section 3: Emergency Contact
                  _buildSectionCard(
                    context: context,
                    title: 'Emergency Contact',
                    icon: Icons.contact_phone_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _emergencyContactController,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Emergency Contact Name *', hintText: 'Full name'),
                                validator: (val) => val?.trim().isEmpty == true ? 'Emergency Contact Name is required' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _emergencyRelationshipController,
                                style: const TextStyle(color: _lightOffWhite),
                                decoration: _buildInputDecoration('Relationship', hintText: 'Parent, spouse, sibling'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _emergencyContactNumberController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: _lightOffWhite),
                          decoration: _buildInputDecoration('Emergency Contact Number *', hintText: '09XXXXXXXXX'),
                          validator: (val) => val?.trim().isEmpty == true ? 'Emergency Contact Number is required' : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Section 4: Baseline Health Information
                  _buildSectionCard(
                    context: context,
                    title: 'Baseline Health Information',
                    icon: Icons.health_and_safety_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _medicalHistoryController,
                          maxLines: 3,
                          style: const TextStyle(color: _lightOffWhite),
                          decoration: _buildInputDecoration(
                            'Medical History',
                            hintText: 'Existing conditions, previous diagnoses, or "None"',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _allergiesController,
                          maxLines: 2,
                          style: const TextStyle(color: _lightOffWhite),
                          decoration: _buildInputDecoration(
                            'Allergies (Optional)',
                            hintText: 'Food, medicine, environmental allergies, or leave blank',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Bottom Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _lightOffWhite,
                            side: BorderSide(color: _lightOffWhite.withValues(alpha: 0.3)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveChanges,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryAqua,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save_rounded, size: 20),
                          label: Text(
                            _isSaving ? 'Saving...' : 'Save Changes',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
