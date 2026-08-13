import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mycapstone_project/app/features/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/app/core/services/disease_prediction_api_service.dart';
import 'package:mycapstone_project/app/core/services/health_ai_classifier.dart';
import 'package:mycapstone_project/app/shared/widgets/mobile_pagination_controls.dart';
import 'package:mycapstone_project/app/shared/widgets/health_record_card.dart';
import 'package:mycapstone_project/app/features/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/app/features/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/shared/current_table_record_utils.dart';
import 'package:mycapstone_project/app/shared/widgets/ocr_record_action.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _secondaryIceBlue = AppDesign.blueSoft;
const Color _darkDeepTeal = AppDesign.page;
const Color _mutedCoolGray = AppDesign.muted;
const Color _lightOffWhite = AppDesign.ink;

class CheckUpPage extends StatefulWidget {
  const CheckUpPage({super.key});

  @override
  State<CheckUpPage> createState() => _CheckUpPageState();
}

class _CheckUpPageState extends State<CheckUpPage> {
  DateTime? _selectedDate;
  String _filterType = 'All'; // All, Day, Month, Year
  String _statusFilter =
      'All'; // All, Pending, Completed, Process, On Follow Up
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};
  bool _isDeleteDialogShowing = false;
  bool _isLoading = true;

  // Metrics
  int _totalCheckups = 0;
  int _thisMonthCheckups = 0;
  int _vitalRecordsCount = 0;

  // Database-backed records
  List<Map<String, dynamic>> _records = [];
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  StreamSubscription<List<Map<String, dynamic>>>? _recordsSubscription;
  static const int _defaultRowsPerPage = 5;
  int _currentPage = 1;
  int _rowsPerPage = _defaultRowsPerPage;

  // AI Classifier
  final HealthAIClassifier _aiClassifier = HealthAIClassifier.instance;
  final SymptomGuidanceApiService _guidanceApi = SymptomGuidanceApiService();
  final PatientCenteredHistoryService _patientHistoryService =
      PatientCenteredHistoryService();

  @override
  void initState() {
    super.initState();
    _setupRealtimeListener();
    _dbHelper.startConnectivityListener();
    _initializeAI();
  }

  Future<void> _initializeAI() async {
    await _aiClassifier.initialize();
  }

  void _setupRealtimeListener() {
    // Listen to real-time updates from Firestore
    _recordsSubscription = _dbHelper.getRecordsStream().listen((records) {
      _updateRecordsWithMetrics(records);
    });
  }

  void _updateRecordsWithMetrics(List<Map<String, dynamic>> records) {
    // Calculate metrics
    final now = DateTime.now();
    final thisMonthCount = records.where((record) {
      try {
        final datetime = DateTime.parse(record['datetime'] ?? '');
        return datetime.year == now.year && datetime.month == now.month;
      } catch (e) {
        return false;
      }
    }).length;

    // Count records with vital signs
    final vitalRecords = records.where((record) {
      final details = record['details']?.toString() ?? '';
      return details.contains('BP:') ||
          details.contains('Temp:') ||
          details.contains('HR:');
    }).length;

    if (mounted) {
      setState(() {
        _records = records;
        _totalCheckups = records.length;
        _thisMonthCheckups = thisMonthCount;
        _vitalRecordsCount = vitalRecords;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _recordsSubscription?.cancel();
    _searchController.dispose();
    _guidanceApi.close();
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
            Text('Seeding 100 sample checkup records...'),
          ],
        ),
      ),
    );

    try {
      await _dbHelper.seedSampleCheckupData();

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Successfully added 100 sample checkup records!'),
                ),
              ],
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
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Error seeding data: $e')),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadRecords() async {
    // This method is kept for compatibility but real-time listener
    // will automatically update the UI
    if (!kIsWeb) {
      // On mobile, manually sync from Firebase if needed
      await _dbHelper.syncFromFirebase();
    }
  }

  void _showNewCheckUpModal(
    BuildContext context, {
    Map<String, dynamic>? patientSeed,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _NewCheckUpFullScreenModal(
        guidanceApi: _guidanceApi,
        patientSeed: patientSeed,
        onGuidanceSave: (updatedRecord) async {
          final id = updatedRecord['id']?.toString() ?? '';
          if (id.isEmpty) return;
          await _dbHelper.updateRecord(id, updatedRecord);
          await _loadRecords();
        },
        onSave: (newRecord) async {
          final diseaseType = newRecord['diseaseType'] ?? 'General';

          await _dbHelper.insertRecord(newRecord);
          await _loadRecords();

          String message = 'Check-up record saved successfully!';
          if (diseaseType == 'Communicable') {
            message =
                'Check-up saved! This communicable disease case has been recorded for tracking.';
          } else if (diseaseType == 'Non-Communicable') {
            message =
                'Check-up saved! This non-communicable disease case has been recorded for management.';
          }

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message), backgroundColor: Colors.green),
            );
          }
        },
      ),
    );
  }

  void _handleEditRecord(BuildContext context, Map<String, dynamic> record) {
    Future.microtask(() {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _EditCheckUpFullScreenModal(
          record: record,
          aiClassifier: _aiClassifier,
          onSave: (updatedRecord) async {
            try {
              // Update in database
              final id = updatedRecord['id']?.toString() ?? '';
              if (id.isEmpty) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error: Record ID not found'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return;
              }
              await _dbHelper.updateRecord(id, updatedRecord);
              // Reload from database
              await _loadRecords();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Record updated successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error updating record: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
        ),
      );
    });
  }

  List<Map<String, dynamic>> get _filteredRecords {
    List<Map<String, dynamic>> filtered = _records;

    // Apply status filter
    if (_statusFilter != 'All') {
      filtered = filtered.where((record) {
        final status = record['status']?.toString() ?? 'Pending';
        return status == _statusFilter;
      }).toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((record) {
        final patientName = (record['patient']?.toString() ?? '').toLowerCase();
        final address = (record['address']?.toString() ?? '').toLowerCase();
        final age = (record['age']?.toString() ?? '').toLowerCase();
        return patientName.contains(query) ||
            address.contains(query) ||
            age.contains(query);
      }).toList();
    }

    // Apply date filter
    if (_selectedDate == null || _filterType == 'All') {
      return CurrentTableRecordUtils.collapseToLatestPerEntity(
        filtered,
        idKeys: const ['linkedPatientId', 'patientId'],
        nameKeys: const ['patient', 'patientName'],
        dateKeys: const ['datetime', 'followup', 'updatedAt', 'createdAt'],
        extraIdentityKeys: const ['age', 'gender', 'address'],
      );
    }

    final dateFiltered = filtered.where((record) {
      try {
        final recordDate = DateTime.parse(
          record['datetime']?.split(' ')[0] ?? '',
        );

        switch (_filterType) {
          case 'Day':
            return recordDate.year == _selectedDate!.year &&
                recordDate.month == _selectedDate!.month &&
                recordDate.day == _selectedDate!.day;
          case 'Month':
            return recordDate.year == _selectedDate!.year &&
                recordDate.month == _selectedDate!.month;
          case 'Year':
            return recordDate.year == _selectedDate!.year;
          default:
            return true;
        }
      } catch (e) {
        return false;
      }
    }).toList();

    return CurrentTableRecordUtils.collapseToLatestPerEntity(
      dateFiltered,
      idKeys: const ['linkedPatientId', 'patientId'],
      nameKeys: const ['patient', 'patientName'],
      dateKeys: const ['datetime', 'followup', 'updatedAt', 'createdAt'],
      extraIdentityKeys: const ['age', 'gender', 'address'],
    );
  }

  int get _effectiveRowsPerPage =>
      _rowsPerPage > 0 ? _rowsPerPage : _defaultRowsPerPage;

  int get _totalPages {
    final filteredCount = _filteredRecords.length;
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
    if (_filteredRecords.isEmpty) {
      return 0;
    }
    return (_safeCurrentPage - 1) * _effectiveRowsPerPage;
  }

  int get _pageEndIndex {
    if (_filteredRecords.isEmpty) {
      return 0;
    }
    return math.min(
      _pageStartIndex + _effectiveRowsPerPage,
      _filteredRecords.length,
    );
  }

  List<Map<String, dynamic>> get _pagedFilteredRecords {
    if (_filteredRecords.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    return _filteredRecords.sublist(_pageStartIndex, _pageEndIndex);
  }

  void _resetPagination({bool clearSelection = false}) {
    _currentPage = 1;
    if (clearSelection) {
      _selectedIndices.clear();
      _isSelectionMode = false;
    }
  }

  /// Extract vital sign value from vitalsigns string
  String _extractVital(List<String> parts, String prefix) {
    for (var part in parts) {
      if (part.trim().startsWith(prefix)) {
        String value = part.trim().substring(prefix.length).trim();
        return value;
      }
    }
    return 'N/A';
  }

  /// Show AI recommendations dialog after record is saved
  void _showAIRecommendationsDialog(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final recoveryPlan = record['ai_recovery_plan'] as Map<String, dynamic>?;
    if (recoveryPlan == null) return;

    final category = record['ai_category'] ?? 'Unknown';
    final severity = record['ai_severity'] ?? 'Unknown';
    // Handle both double and string types for confidence
    final confidenceValue = record['ai_confidence'];
    final confidence = confidenceValue is double
        ? confidenceValue
        : (confidenceValue is String
              ? (double.tryParse(confidenceValue) ?? 0.0)
              : 0.0);
    final keywords = record['ai_keywords'] ?? '';

    // Show loading spinner dialog for 3 seconds before showing AI modal
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
                  'Analyzing Health Data...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'AI is classifying your record',
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

    // Wait 3 seconds, dismiss loading, then show actual AI modal
    Future.delayed(const Duration(seconds: 3), () {
      if (context.mounted) {
        Navigator.of(context).pop(); // dismiss loading dialog
      }
      if (!context.mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          backgroundColor: _darkDeepTeal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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
                              'AI Health Analysis',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Personalized recommendations for recovery',
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

                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Classification Summary
                        _buildDialogClassificationSummary(
                          category,
                          severity,
                          confidence,
                          keywords,
                        ),

                        const SizedBox(height: 24),

                        // Recovery Plan
                        _buildDialogRecoveryPlan(recoveryPlan),
                      ],
                    ),
                  ),
                ),

                // Footer Actions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _darkDeepTeal,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    border: Border(
                      top: BorderSide(
                        color: _lightOffWhite.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Close',
                          style: TextStyle(color: _lightOffWhite),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          // Optional: Navigate to detailed view
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('Got It'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryAqua,
                          foregroundColor: _lightOffWhite,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
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
    }); // end Future.delayed
  }

  Widget _buildDialogClassificationSummary(
    String category,
    String severity,
    double confidence,
    String keywords,
  ) {
    Color severityColor;
    IconData severityIcon;

    switch (severity.toLowerCase()) {
      case 'critical':
        severityColor = Colors.red;
        severityIcon = Icons.local_hospital;
        break;
      case 'high':
        severityColor = Colors.orange;
        severityIcon = Icons.warning;
        break;
      case 'moderate':
        severityColor = Colors.amber;
        severityIcon = Icons.info;
        break;
      case 'low':
        severityColor = Colors.green;
        severityIcon = Icons.check_circle;
        break;
      default:
        severityColor = Colors.blue;
        severityIcon = Icons.info;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: severityColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: severityColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(severityIcon, color: severityColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: severityColor,
                      ),
                    ),
                    Text(
                      'Severity: $severity',
                      style: TextStyle(
                        fontSize: 14,
                        color: severityColor.withValues(alpha: 0.8),
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
                  color: _lightOffWhite.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _lightOffWhite.withValues(alpha: 0.12),
                  ),
                ),
                child: Text(
                  '${(confidence * 100).toStringAsFixed(0)}% confident',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _lightOffWhite,
                  ),
                ),
              ),
            ],
          ),
          if (keywords.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Detected Keywords:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _lightOffWhite,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: keywords.split(',').map((keyword) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _lightOffWhite.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: severityColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    keyword.trim(),
                    style: TextStyle(
                      fontSize: 11,
                      color: severityColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDialogRecoveryPlan(Map<String, dynamic> recoveryPlan) {
    final homeCare = (recoveryPlan['home_care'] as List?)?.cast<String>() ?? [];
    final precautions =
        (recoveryPlan['precautions'] as List?)?.cast<String>() ?? [];
    final estimatedRecovery = recoveryPlan['estimated_recovery']?.toString();
    final generalAdvice =
        (recoveryPlan['general_advice'] as List?)?.cast<String>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.healing_outlined, color: _lightOffWhite, size: 20),
            SizedBox(width: 8),
            Text(
              'AI-Assisted Home-Care Recommendation',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _lightOffWhite,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Home Care
        if (homeCare.isNotEmpty) ...[
          _buildDialogRecommendationSection(
            icon: Icons.home_outlined,
            title: 'Home Care',
            color: Colors.green,
            items: homeCare,
          ),
          const SizedBox(height: 16),
        ],

        // Precautions
        if (precautions.isNotEmpty) ...[
          _buildDialogRecommendationSection(
            icon: Icons.warning_amber_rounded,
            title: 'Precautions',
            color: Colors.orange,
            items: precautions,
          ),
          const SizedBox(height: 16),
        ],

        // General Advice
        if (generalAdvice.isNotEmpty) ...[
          _buildDialogRecommendationSection(
            icon: Icons.info_outline,
            title: 'General Advice',
            color: Colors.purple,
            items: generalAdvice,
          ),
          const SizedBox(height: 16),
        ],

        // Estimated Recovery
        if (estimatedRecovery != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _lightOffWhite.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _lightOffWhite.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule, color: _primaryAqua, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Estimated Recovery: $estimatedRecovery',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _lightOffWhite,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _lightOffWhite.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _lightOffWhite.withValues(alpha: 0.12)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: _primaryAqua, size: 14),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'AI-generated information provides supportive home-care '
                  'guidance only. Medication and clinical decisions remain '
                  'under the attending physician.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white70,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDialogRecommendationSection({
    required IconData icon,
    required String title,
    required Color color,
    required List<String> items,
  }) {
    return Container(
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
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 14,
                        color: _lightOffWhite.withValues(alpha: 0.85),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesign.page,
      appBar: AppBar(
        backgroundColor: AppDesign.surface,
        title: Text(
          'Check Up Dashboard',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppDesign.ink,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: AppDesign.ink),
        elevation: 0,
        actions: [
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              PopupMenuItem(
                child: const Text('Seed Sample Data'),
                onTap: () => _seedSampleData(),
              ),
              PopupMenuItem(
                child: const Text('View Data in Console'),
                onTap: () {
                  print('=== CHECK-UP RECORDS DATA ===');
                  print('Total Records: ${_records.length}');
                  for (var i = 0; i < _records.length; i++) {
                    print('\nRecord ${i + 1}:');
                    _records[i].forEach((key, value) {
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
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryAqua))
          : Stack(
              children: [
                SingleChildScrollView(
                  child: Center(
                    // Center content on web
                    child: Container(
                      constraints: kIsWeb
                          ? const BoxConstraints(
                              maxWidth: 1600,
                            ) // Max width on web
                          : const BoxConstraints(), // No constraints on mobile
                      child: Padding(
                        padding: EdgeInsets.all(
                          kIsWeb ? 32.0 : 20.0,
                        ), // More padding on web
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Search Bar with Burger Menu and Status Filter
                            _buildSearchAndFilterBar(),
                            const SizedBox(height: 16),

                            // Records Table
                            _CheckUpTable(
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
                                Future.microtask(() {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (context) => _EditCheckUpFullScreenModal(
                                      record: record,
                                      aiClassifier: _aiClassifier,
                                      onSave: (updatedRecord) async {
                                        try {
                                          // Update in database
                                          final id =
                                              updatedRecord['id']?.toString() ??
                                              '';
                                          if (id.isEmpty) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Error: Record ID not found',
                                                  ),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            }
                                            return;
                                          }
                                          await _dbHelper.updateRecord(
                                            id,
                                            updatedRecord,
                                          );
                                          // Reload from database
                                          await _loadRecords();
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Record updated successfully',
                                                ),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Error updating record: $e',
                                                ),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  );
                                });
                              },
                              onLongPress: _showLongPressContextMenu,
                              onTap: _showCheckUpHistory,
                            ),
                            MobilePaginationControls(
                              currentPage: _safeCurrentPage,
                              totalPages: _totalPages,
                              totalItems: _filteredRecords.length,
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
                            const SizedBox(
                              height: 80,
                            ), // Space for floating action card
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
              moduleLabel: 'Check-up',
              manualLabel: 'New Check Up',
              onManualCreate: () => _showNewCheckUpModal(context),
              onOcrReady: (extraction) async {
                _showNewCheckUpModal(
                  context,
                  patientSeed: extraction.toFormSeed(),
                );
              },
            ),
      bottomNavigationBar: (_isSelectionMode && _selectedIndices.isNotEmpty)
          ? BottomAppBar(
              color: _darkDeepTeal,
              elevation: 8,
              notchMargin: 8,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_selectedIndices.length} Selected',
                          style: const TextStyle(
                            color: _lightOffWhite,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Tap cards to deselect',
                          style: TextStyle(color: _mutedCoolGray, fontSize: 12),
                        ),
                      ],
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Row(
                          children: [
                            // Select All Button
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectedIndices.clear();
                                  for (
                                    int i = 0;
                                    i < _filteredRecords.length;
                                    i++
                                  ) {
                                    _selectedIndices.add(i);
                                  }
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryAqua.withValues(
                                  alpha: 0.2,
                                ),
                                foregroundColor: _primaryAqua,
                                side: BorderSide(
                                  color: _primaryAqua.withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
                              ),
                              icon: const Icon(Icons.select_all, size: 18),
                              label: const Text('Select All'),
                            ),
                            const SizedBox(width: 8),
                            // Cancel Button
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectedIndices.clear();
                                  _isSelectionMode = false;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _mutedCoolGray.withValues(
                                  alpha: 0.2,
                                ),
                                foregroundColor: _lightOffWhite,
                                side: BorderSide(
                                  color: _mutedCoolGray.withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                              ),
                              icon: const Icon(Icons.close, size: 18),
                              label: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            // Delete Button
                            ElevatedButton.icon(
                              onPressed: () {
                                _showMultipleDeleteConfirmationDialog(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.withValues(
                                  alpha: 0.2,
                                ),
                                foregroundColor: Colors.red,
                                side: BorderSide(
                                  color: Colors.red.withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
                              ),
                              icon: const Icon(Icons.delete, size: 18),
                              label: const Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildSearchAndFilterBar() {
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
                  // Handle menu selection
                  switch (value) {
                    case 'all':
                      setState(() {
                        _statusFilter = 'All';
                        _resetPagination(clearSelection: true);
                      });
                      break;
                    case 'pending':
                      setState(() {
                        _statusFilter = 'Pending';
                        _resetPagination(clearSelection: true);
                      });
                      break;
                    case 'completed':
                      setState(() {
                        _statusFilter = 'Completed';
                        _resetPagination(clearSelection: true);
                      });
                      break;
                    case 'process':
                      setState(() {
                        _statusFilter = 'Process';
                        _resetPagination(clearSelection: true);
                      });
                      break;
                    case 'followup':
                      setState(() {
                        _statusFilter = 'On Follow Up';
                        _resetPagination(clearSelection: true);
                      });
                      break;
                    case 'clear':
                      setState(() {
                        _selectedDate = null;
                        _filterType = 'All';
                        _statusFilter = 'All';
                        _searchController.clear();
                        _searchQuery = '';
                        _resetPagination(clearSelection: true);
                      });
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
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Search Bar
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                    _resetPagination(clearSelection: true);
                  });
                },
                style: TextStyle(color: _lightOffWhite),
                decoration: InputDecoration(
                  hintText: 'Search by name, address, age...',
                  hintStyle: TextStyle(
                    color: _lightOffWhite.withValues(alpha: 0.5),
                  ),
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
                      color: _lightOffWhite.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _lightOffWhite.withValues(alpha: 0.3),
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
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Status Filter Dropdown
        Container(
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
            value: _statusFilter,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            dropdownColor: _darkDeepTeal,
            iconEnabledColor: _lightOffWhite,
            items: ['All', 'Pending', 'Completed', 'Process', 'On Follow Up']
                .map((String value) {
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
                })
                .toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _statusFilter = newValue;
                  _resetPagination(clearSelection: true);
                });
              }
            },
          ),
        ),
      ],
    );
  }

  void _confirmDelete() {
    if (_selectedIndices.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
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
        backgroundColor: _darkDeepTeal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            const SizedBox(width: 8),
            Text(
              'Confirm Delete',
              style: TextStyle(
                color: _lightOffWhite,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${_selectedIndices.length} selected record(s)? This action cannot be undone.',
          style: TextStyle(color: _lightOffWhite),
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
                color: _primaryAqua,
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
    final idsToDelete = _selectedIndices
        .map(
          (index) => index < _filteredRecords.length
              ? _filteredRecords[index]['id'] as String?
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
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<Map<String, dynamic>> _getCheckUpHistory(Map<String, dynamic> record) {
    return PatientHistoryDialogs.collectHistory(
      seedRecord: record,
      records: _records,
      idKeys: const ['linkedPatientId', 'patientId'],
      nameKeys: const ['patient', 'patientName'],
      sortDateKeys: const ['datetime', 'followup'],
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

  void _showCheckUpHistory(BuildContext context, Map<String, dynamic> record) {
    final history = _getCheckUpHistory(record);
    PatientHistoryDialogs.showModuleHistoryDialog(
      context: context,
      moduleTitle: 'Check Up',
      seedRecord: record,
      history: history,
      description:
          'Review previous check-up visits before adding the next visit for the same patient.',
      addButtonLabel: 'Add Another Check-Up',
      titleBuilder: (entry) =>
          (entry['ai_category'] ?? entry['status'] ?? 'Check-up visit')
              .toString(),
      subtitleBuilder: (entry) =>
          'Symptoms: ${(entry['symptoms'] ?? 'No symptoms recorded').toString()}',
      metaBuilder: (entry) =>
          'Visit: ${(entry['datetime'] ?? 'No visit date').toString()} | Follow-up: ${(entry['followup'] ?? 'N/A').toString()}',
      dateKeys: const ['datetime', 'followup'],
      secondaryActionLabel: 'Medical History',
      onSecondaryAction: () => _showPatientMedicalHistory(context, record),
      onAddAnother: () => _showNewCheckUpModal(
        context,
        patientSeed: history.isNotEmpty ? history.first : record,
      ),
      onOpenRecord: (entry) => _showCheckUpDetailsDialog(context, entry),
      fullScreen: true,
    );
  }

  void _showLongPressContextMenu(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: _darkDeepTeal,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _mutedCoolGray.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // Patient Name as Title
              Text(
                record['patient'] ?? 'Record Details',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _lightOffWhite,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // View Patient History Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showCheckUpHistory(context, record);
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

              // Select Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      _isSelectionMode = true;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF4ECDC4).withValues(alpha: 0.1),
                    side: BorderSide(color: Color(0xFF4ECDC4), width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_box_outlined,
                        size: 20,
                        color: Color(0xFF4ECDC4),
                      ),
                      const SizedBox(width: 8),
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

              // Edit Details Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Future.microtask(() {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => _EditCheckUpFullScreenModal(
                          record: record,
                          aiClassifier: _aiClassifier,
                          onSave: (updatedRecord) async {
                            try {
                              final id = updatedRecord['id']?.toString() ?? '';
                              if (id.isEmpty) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Error: Record ID not found',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                                return;
                              }
                              await DatabaseHelper.instance.updateRecord(
                                id,
                                updatedRecord,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Record updated successfully',
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error updating record: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      );
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryAqua.withValues(alpha: 0.1),
                    side: BorderSide(color: _primaryAqua, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit, size: 20, color: _primaryAqua),
                      const SizedBox(width: 8),
                      Text(
                        'Edit Details',
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

              // Delete Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showDeleteConfirmationDialog(context, record);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.1),
                    side: BorderSide(color: Colors.red, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      const SizedBox(width: 8),
                      const Text(
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
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // Show Delete Confirmation Dialog for Single Record
  void _showDeleteConfirmationDialog(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final patientName = record['patient'] ?? 'Unknown';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: _darkDeepTeal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Delete Record',
                  style: TextStyle(
                    color: _lightOffWhite,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Are you sure you want to delete the record for $patientName? This action cannot be undone.',
                  style: const TextStyle(color: _lightOffWhite, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: _primaryAqua,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        try {
                          final id = record['id']?.toString() ?? '';
                          if (id.isEmpty) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Error: Record ID not found'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                            return;
                          }

                          await DatabaseHelper.instance.deleteRecord(id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Record deleted successfully'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error deleting record: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Show Delete Confirmation Dialog for Multiple Records
  void _showMultipleDeleteConfirmationDialog(BuildContext context) {
    final count = _selectedIndices.length;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: _darkDeepTeal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Delete Multiple Records',
                  style: TextStyle(
                    color: _lightOffWhite,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Are you sure you want to delete $count record(s)? This action cannot be undone.',
                  style: const TextStyle(color: _lightOffWhite, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: _primaryAqua,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CheckUpTable extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final int startIndex;
  final bool isSelectionMode;
  final Set<int> selectedIndices;
  final Function(int, bool) onSelectionChanged;
  final Function(Map<String, dynamic>) onEdit;
  final Function(BuildContext, Map<String, dynamic>) onLongPress;
  final Function(BuildContext, Map<String, dynamic>) onTap;

  const _CheckUpTable({
    required this.records,
    required this.startIndex,
    required this.isSelectionMode,
    required this.selectedIndices,
    required this.onSelectionChanged,
    required this.onEdit,
    required this.onLongPress,
    required this.onTap,
  });

  String _getInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

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
      AppDesign.checkUp,
      const Color(0xFF1E5A7A), // Ice Blue
      const Color(0xFFFF6B6B), // Red
      const Color(0xFF4ECDC4), // Teal
      const Color(0xFFFFBE5B), // Gold
      const Color(0xFF845EC2), // Purple
    ];
    return colors[index % colors.length];
  }

  Widget _buildLabeledValueRow({
    required String label,
    required String value,
    Color valueColor = _lightOffWhite,
    double valueFontSize = 12,
    FontWeight valueFontWeight = FontWeight.w600,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 106,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 12,
              color: _lightOffWhite.withValues(alpha: 0.72),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: valueFontSize,
              color: valueColor,
              fontWeight: valueFontWeight,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
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
              const SizedBox(height: 8),
              Text(
                'Add a new check-up record to get started',
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
        final patientNameValue = record['patient']?.toString().trim() ?? '';
        final patientName = patientNameValue.isEmpty
            ? 'Unknown'
            : patientNameValue;
        final address = record['address']?.toString() ?? 'N/A';
        final age = record['age']?.toString() ?? 'N/A';
        final datetime = record['datetime']?.toString() ?? 'N/A';
        final symptoms =
            record['symptoms']?.toString().trim().isNotEmpty == true
            ? record['symptoms'].toString().trim()
            : 'No symptoms recorded';
        final vitalSigns =
            record['vitalsigns']?.toString().trim().isNotEmpty == true
            ? record['vitalsigns'].toString().trim()
            : 'No vital signs recorded';
        final treatmentPlan =
            record['plan']?.toString().trim().isNotEmpty == true
            ? record['plan'].toString().trim()
            : 'No treatment plan';
        final dateLabel = datetime.contains('T')
            ? datetime.split('T').first
            : datetime.split(' ').first;

        return HealthRecordCard(
          recordLabel: 'Check-up record',
          patientName: patientName,
          location: address,
          accentColor: AppDesign.checkUp,
          status: record['status']?.toString() ?? 'Recorded',
          secondaryStatus:
              record['referralStatus']?.toString() ??
              record['referral_status']?.toString(),
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
              onTap(context, record);
            }
          },
          onLongPress: () => onLongPress(context, record),
          onAction: () => onLongPress(context, record),
          metadata: [
            RecordMetadata(label: 'Age', value: age, icon: Icons.cake_outlined),
            RecordMetadata(
              label: 'Vital signs',
              value: vitalSigns,
              icon: Icons.monitor_heart_outlined,
              emphasize: true,
            ),
            RecordMetadata(
              label: 'Symptoms',
              value: symptoms,
              icon: Icons.sick_outlined,
              emphasize: true,
            ),
            RecordMetadata(
              label: 'Treatment / management',
              value: treatmentPlan,
              icon: Icons.medication_outlined,
              emphasize: true,
            ),
            RecordMetadata(
              label: 'Check-up date',
              value: HealthRecordDate.format(datetime, includeTime: true),
              icon: Icons.event_outlined,
            ),
          ],
        );

        // Retained legacy layout below is unreachable and will be removed once
        // downstream forks no longer reference its private helper methods.
        // ignore: dead_code
        return GestureDetector(
          onTap: () {
            if (isSelectionMode) {
              onSelectionChanged(
                absoluteIndex,
                !selectedIndices.contains(absoluteIndex),
              );
            } else {
              onTap(context, record);
            }
          },
          onLongPress: () => onLongPress(context, record),
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
                    // Checkbox (visible only in selection mode)
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
                              fontSize: 18,
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
                              fontSize: 14,
                              color: _lightOffWhite.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Age: ',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _lightOffWhite.withValues(
                                      alpha: 0.7,
                                    ),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextSpan(
                                  text: age,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: _lightOffWhite,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          _buildLabeledValueRow(
                            label: 'Vital Signs',
                            value: vitalSigns,
                            valueColor: _lightOffWhite,
                            valueFontSize: 12.5,
                          ),
                          const SizedBox(height: 4),
                          _buildLabeledValueRow(
                            label: 'Symptoms',
                            value: symptoms,
                            valueColor: _lightOffWhite,
                            valueFontSize: 13,
                            valueFontWeight: FontWeight.w700,
                          ),
                          const SizedBox(height: 4),
                          _buildLabeledValueRow(
                            label: 'Treatment Plan',
                            value: treatmentPlan,
                            valueColor: _primaryAqua,
                            valueFontSize: 12.5,
                            valueFontWeight: FontWeight.w700,
                          ),
                          const SizedBox(height: 4),
                          _buildLabeledValueRow(
                            label: 'Date',
                            value: dateLabel,
                            valueColor: _lightOffWhite,
                            valueFontSize: 12.5,
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

// Show Full Details Dialog
void _showCheckUpDetailsDialog(
  BuildContext context,
  Map<String, dynamic> record,
) {
  final patientName = record['patient'] ?? 'Unknown';
  final address = record['address']?.toString() ?? 'N/A';
  final age = record['age']?.toString() ?? 'N/A';
  final status = record['status']?.toString() ?? 'Pending';
  final datetime = record['datetime']?.toString() ?? 'N/A';
  final symptoms = record['symptoms']?.toString() ?? 'No symptoms recorded';
  final plan = record['plan']?.toString() ?? 'No treatment plan';
  final followup = record['followup']?.toString() ?? 'Not scheduled';

  // Extract vital signs from the vitalsigns field
  final vitalSigns = record['vitalsigns'] ?? '';
  final vitalParts = vitalSigns.split(', ');
  final pageState = context.findAncestorStateOfType<_CheckUpPageState>();
  final temperature = pageState?._extractVital(vitalParts, 'Temp:') ?? 'N/A';
  final bloodPressure = pageState?._extractVital(vitalParts, 'BP:') ?? 'N/A';
  final heartRate = pageState?._extractVital(vitalParts, 'HR:') ?? 'N/A';
  final respiratoryRate = pageState?._extractVital(vitalParts, 'RR:') ?? 'N/A';
  final oxygenSaturation = pageState?._extractVital(vitalParts, 'O2:') ?? 'N/A';
  final weight = pageState?._extractVital(vitalParts, 'Weight:') ?? 'N/A';
  final height = pageState?._extractVital(vitalParts, 'Height:') ?? 'N/A';

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return Dialog(
        backgroundColor: _darkDeepTeal,
        insetPadding: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: _darkDeepTeal,
            border: Border.all(color: _lightOffWhite.withValues(alpha: 0.12)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with Close Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Check-Up Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _lightOffWhite,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(
                        Icons.close,
                        color: _lightOffWhite.withValues(alpha: 0.7),
                        size: 28,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Patient Info Section
                _buildDetailSection('Patient Information', [
                  _buildDetailRow('Name', patientName),
                  _buildDetailRow('Age', age),
                  _buildDetailRow('Address', address),
                ]),
                const SizedBox(height: 16),

                // Check-Up Details Section
                _buildDetailSection('Check-Up Details', [
                  _buildDetailRow('Date & Time', datetime),
                  _buildDetailRow('Temperature', temperature),
                  _buildDetailRow('Blood Pressure', bloodPressure),
                  _buildDetailRow('Heart Rate', heartRate),
                  _buildDetailRow('Respiratory Rate', respiratoryRate),
                  _buildDetailRow('Oxygen Saturation', oxygenSaturation),
                  _buildDetailRow('Weight', weight),
                  _buildDetailRow('Height', height),
                ]),
                const SizedBox(height: 16),

                // Status Section
                _buildDetailSection('Status', [
                  _buildDetailRow('Status', status),
                ]),
                const SizedBox(height: 16),

                // Symptoms Section
                _buildDetailSection('Symptoms', [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _lightOffWhite.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _lightOffWhite.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Text(
                      symptoms,
                      style: TextStyle(
                        fontSize: 13,
                        color: _lightOffWhite,
                        height: 1.5,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),

                // Treatment Plan Section
                _buildDetailSection('Treatment Plan', [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _lightOffWhite.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _lightOffWhite.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Text(
                      plan,
                      style: TextStyle(
                        fontSize: 13,
                        color: _lightOffWhite,
                        height: 1.5,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),

                // Follow-up Section
                _buildDetailSection('Follow-up Schedule', [
                  _buildDetailRow('Follow-up Date', followup),
                ]),
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    // Edit Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          pageState?._handleEditRecord(context, record);
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
                    // Close Button
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
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

// Helper function to build detail section
// Helper function to build detail row
Widget _buildDetailRow(String label, String value) {
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
              color: label == 'Vital Signs'
                  ? const Color(0xFF00E5F7)
                  : _lightOffWhite.withValues(alpha: 0.7),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: label == 'Vital Signs'
              ? _buildHighlightedVitalSigns(value)
              : Text(
                  value,
                  style: const TextStyle(
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

Widget _buildHighlightedVitalSigns(String vitalsString) {
  if (vitalsString.isEmpty || vitalsString == 'N/A') {
    return Text(
      vitalsString,
      style: const TextStyle(
        fontSize: 16,
        color: _lightOffWhite,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  final parts = vitalsString.split(' | ');
  final textSpans = <TextSpan>[];

  for (int i = 0; i < parts.length; i++) {
    final part = parts[i].trim();
    if (part.isEmpty) continue;

    // Extract label and value
    final colonIndex = part.indexOf(':');
    if (colonIndex != -1) {
      final vitalLabel = part.substring(
        0,
        colonIndex + 1,
      ); // includes the colon
      final vitalValue = part.substring(colonIndex + 1).trim();

      // Add highlighted label
      textSpans.add(
        TextSpan(
          text: vitalLabel,
          style: TextStyle(
            fontSize: 16,
            color: const Color(0xFF00E5F7),
            fontWeight: FontWeight.w900,
          ),
        ),
      );

      // Add space and value
      textSpans.add(
        TextSpan(
          text: ' $vitalValue',
          style: const TextStyle(
            fontSize: 16,
            color: _lightOffWhite,
            fontWeight: FontWeight.w900,
          ),
        ),
      );

      // Add separator if not last item
      if (i < parts.length - 1) {
        textSpans.add(
          TextSpan(
            text: ' | ',
            style: TextStyle(
              fontSize: 16,
              color: _lightOffWhite.withValues(alpha: 0.4),
            ),
          ),
        );
      }
    } else {
      textSpans.add(
        TextSpan(
          text: part,
          style: const TextStyle(
            fontSize: 16,
            color: _lightOffWhite,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }
  }

  return RichText(
    text: TextSpan(children: textSpans),
    maxLines: 4,
    overflow: TextOverflow.ellipsis,
  );
}

// Helper function to show checkup details
void _showCheckUpDetails(BuildContext context, Map<String, dynamic> record) {
  // Parse first name and surname
  final patientName = record['patient'] ?? 'Unknown';
  final nameParts = patientName.split(' ');
  final firstName = nameParts.isNotEmpty ? nameParts[0] : '';
  final surname = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

  showDialog(
    context: context,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
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
                  colors: [_primaryAqua, _primaryAqua.withValues(alpha: 0.8)],
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
                  Icon(Icons.medical_services, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      patientName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
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
                    _buildDetailSection('Patient Information', [
                      _buildDetailRow('First Name', firstName),
                      _buildDetailRow('Surname', surname),
                      _buildDetailRow('Age', record['age']),
                      _buildDetailRow('Address', record['address']),
                    ]),
                    const SizedBox(height: 16),
                    _buildDetailSection('Check-Up Details', [
                      _buildDetailRow('Date & Time', record['datetime']),
                      _buildDetailRow('Status', record['status']),
                      _buildDetailRow('Follow-up Date', record['followup']),
                    ]),
                    const SizedBox(height: 16),
                    _buildDetailSection('Vital Signs', [
                      _buildDetailRow('Vital Signs', record['vitalsigns']),
                    ]),
                    const SizedBox(height: 16),
                    _buildDetailSection('Symptoms & Assessment', [
                      _buildDetailRow('Symptoms', record['symptoms']),
                    ]),
                    const SizedBox(height: 16),
                    // AI Classification Section
                    if (record['ai_category'] != null) ...[
                      _buildAIClassificationSection(record),
                      const SizedBox(height: 16),
                    ],
                    _buildDetailSection('Treatment Plan', [
                      _buildDetailRow('Plan', record['plan']),
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
        // Section Title.
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
        // Section Content.
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

bool _isInvalidAiText(String? value) {
  if (value == null) return true;
  final normalized = value.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == 'undefined' ||
      normalized == 'null';
}

String _safeAiText(dynamic value, {String fallback = 'N/A'}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return _isInvalidAiText(text) ? fallback : text;
}

List<String> _safeAiStringList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => _safeAiText(item, fallback: '').trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const <String>[];
}

double _safeAiConfidence(dynamic value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  final confidence = parsed ?? 0.0;
  if (confidence.isNaN) return 0.0;
  if (confidence < 0) return 0.0;
  if (confidence > 1) return 1.0;
  return confidence;
}

List<String> _safeAiKeywords(dynamic rawKeywords) {
  final text = _safeAiText(rawKeywords, fallback: '');
  if (text.isEmpty) return const <String>[];

  final seen = <String>{};
  final keywords = <String>[];
  for (final raw in text.split(',')) {
    final keyword = _safeAiText(raw, fallback: '').trim();
    if (keyword.isEmpty) continue;
    final key = keyword.toLowerCase();
    if (seen.add(key)) {
      keywords.add(keyword);
    }
  }
  return keywords;
}

Map<String, dynamic>? _parseAiRecoveryPlan(dynamic recoveryData) {
  try {
    Map<String, dynamic>? plan;
    if (recoveryData is Map) {
      plan = Map<String, dynamic>.from(recoveryData);
    } else if (recoveryData is String && !_isInvalidAiText(recoveryData)) {
      final decoded = jsonDecode(recoveryData);
      if (decoded is Map) {
        plan = Map<String, dynamic>.from(decoded);
      }
    }

    if (plan == null) return null;

    final homeCare = _safeAiStringList(plan['home_care']);
    final precautions = _safeAiStringList(plan['precautions']);
    final generalAdvice = _safeAiStringList(plan['general_advice']);
    final estimatedRecovery = _safeAiText(
      plan['estimated_recovery'],
      fallback: '',
    );

    if (homeCare.isEmpty &&
        precautions.isEmpty &&
        generalAdvice.isEmpty &&
        estimatedRecovery.isEmpty) {
      return null;
    }

    return {
      'home_care': homeCare,
      'precautions': precautions,
      'general_advice': generalAdvice,
      'estimated_recovery': estimatedRecovery,
    };
  } catch (e) {
    debugPrint('Error parsing recovery plan: $e');
    return null;
  }
}

Widget _buildAIClassificationSection(Map<String, dynamic> record) {
  final category = _safeAiText(record['ai_category'], fallback: 'Unknown');
  final severity = _safeAiText(record['ai_severity'], fallback: 'Unknown');
  final confidence = _safeAiConfidence(record['ai_confidence']);
  final method = _safeAiText(
    record['ai_method'],
    fallback: 'unknown',
  ).toLowerCase();
  final keywords = _safeAiKeywords(record['ai_keywords']);

  final recoveryPlan = _parseAiRecoveryPlan(record['ai_recovery_plan']);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(Icons.psychology, color: _primaryAqua, size: 20),
          const SizedBox(width: 8),
          Text(
            'AI Classification',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _darkDeepTeal,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: method == 'ml_model'
                  ? Colors.purple.shade50
                  : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: method == 'ml_model' ? Colors.purple : Colors.blue,
                width: 1,
              ),
            ),
            child: Text(
              method == 'ml_model' ? 'ML Model' : 'Rule-Based',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: method == 'ml_model' ? Colors.purple : Colors.blue,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_primaryAqua.withValues(alpha: 0.05), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _primaryAqua.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            // Category Badge
            Row(
              children: [
                Expanded(
                  child: _buildAIBadge(
                    label: 'Category',
                    value: category,
                    icon: Icons.category,
                    color: _getCategoryColor(category),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildAIBadge(
                    label: 'Severity',
                    value: severity,
                    icon: Icons.warning_amber,
                    color: _getSeverityColor(severity),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Confidence Indicator
            Row(
              children: [
                Icon(Icons.speed, size: 16, color: _mutedCoolGray),
                const SizedBox(width: 8),
                Text(
                  'Confidence:',
                  style: TextStyle(
                    color: _mutedCoolGray,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    value: confidence,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      confidence > 0.7
                          ? Colors.green
                          : confidence > 0.4
                          ? Colors.orange
                          : Colors.red,
                    ),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(confidence * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: _darkDeepTeal,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            // Keywords if available
            if (keywords.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: keywords.take(5).map((keyword) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _primaryAqua.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      keyword,
                      style: TextStyle(
                        fontSize: 10,
                        color: _darkDeepTeal,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
      // Recovery Recommendations Section
      if (recoveryPlan != null) ...[
        const SizedBox(height: 16),
        _buildRecoveryRecommendations(recoveryPlan),
      ],
    ],
  );
}

Widget _buildRecoveryRecommendations(Map<String, dynamic> recoveryPlan) {
  final homeCare = _safeAiStringList(recoveryPlan['home_care']);
  final precautions = _safeAiStringList(recoveryPlan['precautions']);
  final estimatedRecovery = _safeAiText(
    recoveryPlan['estimated_recovery'],
    fallback: '',
  );
  final generalAdvice = _safeAiStringList(recoveryPlan['general_advice']);

  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.green.shade50, Colors.white],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.green.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.healing, color: Colors.green.shade700, size: 20),
            const SizedBox(width: 8),
            Text(
              'AI-Assisted Home-Care Recommendation',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Estimated Recovery Time
        if (estimatedRecovery.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule, color: Colors.blue.shade700, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Estimated Recovery: $estimatedRecovery',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Home Care
        if (homeCare.isNotEmpty) ...[
          _buildRecommendationSection(
            'Home Care Instructions',
            Icons.home_outlined,
            homeCare,
            Colors.orange.shade700,
            Colors.orange.shade50,
          ),
          const SizedBox(height: 10),
        ],

        // Precautions
        if (precautions.isNotEmpty) ...[
          _buildRecommendationSection(
            'Important Precautions',
            Icons.warning_amber_rounded,
            precautions,
            Colors.red.shade700,
            Colors.red.shade50,
          ),
          const SizedBox(height: 10),
        ],

        // General Advice
        if (generalAdvice.isNotEmpty) ...[
          _buildRecommendationSection(
            'General Advice',
            Icons.info_outline,
            generalAdvice,
            Colors.teal.shade700,
            Colors.teal.shade50,
          ),
        ],

        // Disclaimer
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.amber.shade300, width: 1),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.amber.shade800, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'AI-generated information provides supportive home-care '
                  'guidance only. Medication and clinical decisions remain '
                  'under the attending physician.',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.amber.shade900,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildRecommendationSection(
  String title,
  IconData icon,
  List<String> items,
  Color textColor,
  Color bgColor,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      ...items.map(
        (item) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: textColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item,
                  style: TextStyle(
                    fontSize: 11,
                    color: _darkDeepTeal,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

Widget _buildAIBadge({
  required String label,
  required String value,
  required IconData icon,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: _mutedCoolGray,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

Color _getCategoryColor(String category) {
  switch (category.toLowerCase()) {
    case 'emergency':
      return Colors.red;
    case 'communicable disease':
      return Colors.orange;
    case 'non-communicable disease':
      return Colors.blue;
    case 'prenatal care':
      return Colors.pink;
    case 'pediatric care':
      return Colors.purple;
    default:
      return Colors.green;
  }
}

Color _getSeverityColor(String severity) {
  switch (severity.toLowerCase()) {
    case 'critical':
      return Colors.red.shade700;
    case 'high':
      return Colors.orange.shade700;
    case 'medium':
      return Colors.yellow.shade700;
    default:
      return Colors.green.shade600;
  }
}

class _NewCheckUpFullScreenModal extends StatefulWidget {
  final Future<void> Function(Map<String, dynamic>) onSave;
  final Future<void> Function(Map<String, dynamic>) onGuidanceSave;
  final SymptomGuidanceApiService guidanceApi;
  final Map<String, dynamic>? patientSeed;

  const _NewCheckUpFullScreenModal({
    required this.onSave,
    required this.onGuidanceSave,
    required this.guidanceApi,
    this.patientSeed,
  });

  @override
  State<_NewCheckUpFullScreenModal> createState() =>
      _NewCheckUpFullScreenModalState();
}

class _NewCheckUpFullScreenModalState
    extends State<_NewCheckUpFullScreenModal> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  // Separate vital sign controllers
  final TextEditingController _bloodPressureController =
      TextEditingController();
  final TextEditingController _temperatureController = TextEditingController();
  final TextEditingController _heartRateController = TextEditingController();
  final TextEditingController _respiratoryRateController =
      TextEditingController();
  final TextEditingController _oxygenSaturationController =
      TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();

  final TextEditingController _symptomsController = TextEditingController();
  final TextEditingController _planController = TextEditingController();
  DateTime? _followUpDate;
  final String _recordType = 'General';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final patientSeed = widget.patientSeed;
    if (patientSeed == null) {
      return;
    }

    final patientName =
        (patientSeed['patient'] ?? patientSeed['patientName'] ?? '')
            .toString()
            .trim();
    final nameParts = patientName.isEmpty
        ? <String>[]
        : patientName.split(RegExp(r'\s+'));
    _firstNameController.text = nameParts.isNotEmpty ? nameParts.first : '';
    _surnameController.text = nameParts.length > 1
        ? nameParts.sublist(1).join(' ')
        : '';
    _ageController.text = (patientSeed['age'] ?? '').toString();
    _addressController.text = (patientSeed['address'] ?? '').toString();
    _symptomsController.text =
        (patientSeed['symptoms'] ?? patientSeed['disease'] ?? '').toString();
    _bloodPressureController.text = (patientSeed['bloodPressure'] ?? '')
        .toString();
    _temperatureController.text = (patientSeed['temperature'] ?? '').toString();
    _heartRateController.text = (patientSeed['heartRate'] ?? '').toString();
    _respiratoryRateController.text = (patientSeed['respiratoryRate'] ?? '')
        .toString();
    _oxygenSaturationController.text = (patientSeed['oxygenSaturation'] ?? '')
        .toString();
    _weightController.text = (patientSeed['weight'] ?? '').toString();
    _heightController.text = (patientSeed['height'] ?? '').toString();
  }

  // Helper method to build section cards
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
        boxShadow: const [],
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
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _lightOffWhite,
                  fontWeight: FontWeight.bold,
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

  // Helper method for input decoration
  InputDecoration _buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _lightOffWhite),
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
        borderSide: const BorderSide(color: _lightOffWhite, width: 2),
      ),
      filled: true,
      fillColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFollowUpVisit = widget.patientSeed != null;
    final modalTitle = isFollowUpVisit
        ? 'Add Another Check Up'
        : 'New Check Up Record';
    final modalSubtitle = isFollowUpVisit
        ? 'Record the next visit for the same patient while keeping past check-up history available.'
        : 'Add a new patient check-up record to the system';

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with close button
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            modalTitle,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            modalSubtitle,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _lightOffWhite.withValues(alpha: 0.8),
                                ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: _lightOffWhite.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 24,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Form sections
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Patient Information Section
                      _buildSectionCard(
                        context: context,
                        title: 'Patient Information',
                        icon: Icons.person,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _firstNameController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _buildInputDecoration(
                                      'First Name',
                                    ),
                                    validator: (v) => v == null || v.isEmpty
                                        ? 'Required'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _surnameController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _buildInputDecoration(
                                      'Surname',
                                    ),
                                    validator: (v) => v == null || v.isEmpty
                                        ? 'Required'
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  flex: 1,
                                  child: TextFormField(
                                    controller: _ageController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _buildInputDecoration('Age'),
                                    keyboardType: TextInputType.number,
                                    validator: (v) => v == null || v.isEmpty
                                        ? 'Required'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: _addressController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _buildInputDecoration(
                                      'Address',
                                    ),
                                    validator: (v) => v == null || v.isEmpty
                                        ? 'Required'
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Vital Signs Section (Separated)
                      _buildSectionCard(
                        context: context,
                        title: 'Vital Signs',
                        icon: Icons.monitor_heart,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _bloodPressureController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _buildInputDecoration(
                                      'Blood Pressure (e.g., 120/80)',
                                    ),
                                    validator: (v) => v == null || v.isEmpty
                                        ? 'Required'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _temperatureController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _buildInputDecoration(
                                      'Temperature (°C)',
                                    ),
                                    keyboardType:
                                        TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    validator: (v) => v == null || v.isEmpty
                                        ? 'Required'
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _heartRateController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _buildInputDecoration(
                                      'Heart Rate (bpm)',
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: (v) => v == null || v.isEmpty
                                        ? 'Required'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _respiratoryRateController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _buildInputDecoration(
                                      'Respiratory Rate (brpm)',
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: (v) => v == null || v.isEmpty
                                        ? 'Required'
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _oxygenSaturationController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _buildInputDecoration(
                                      'Oxygen Saturation (%)',
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: (v) => v == null || v.isEmpty
                                        ? 'Required'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _weightController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _buildInputDecoration(
                                      'Weight (kg)',
                                    ),
                                    keyboardType:
                                        TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _heightController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _buildInputDecoration('Height (cm)'),
                              keyboardType: TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Clinical Details Section
                      _buildSectionCard(
                        context: context,
                        title: 'Clinical Details',
                        icon: Icons.medical_services,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _symptomsController,
                              style: const TextStyle(color: Colors.white),
                              decoration:
                                  _buildInputDecoration(
                                    'Symptoms / Known Conditions',
                                  ).copyWith(
                                    helperText:
                                        'Enter patient-reported symptoms or an already-known condition. Separate entries with commas, semicolons, or new lines.',
                                    helperStyle: TextStyle(
                                      color: _lightOffWhite.withValues(
                                        alpha: 0.65,
                                      ),
                                    ),
                                  ),
                              maxLines: 3,
                              validator: (v) =>
                                  v == null || v.isEmpty ? 'Required' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _planController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _buildInputDecoration(
                                'Treatment Plan',
                              ),
                              maxLines: 3,
                              validator: (v) =>
                                  v == null || v.isEmpty ? 'Required' : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Follow-up Section
                      _buildSectionCard(
                        context: context,
                        title: 'Follow-up',
                        icon: Icons.schedule,
                        child: Column(
                          children: [
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _followUpDate ?? DateTime.now(),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 365),
                                  ),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _followUpDate = picked;
                                  });
                                }
                              },
                              child: InputDecorator(
                                decoration: _buildInputDecoration(
                                  'Follow-up Date',
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _followUpDate != null
                                            ? "${_followUpDate!.year}-${_followUpDate!.month.toString().padLeft(2, '0')}-${_followUpDate!.day.toString().padLeft(2, '0')}"
                                            : 'Tap to select date',
                                        style: TextStyle(
                                          color: _followUpDate != null
                                              ? Colors.white
                                              : _lightOffWhite.withValues(
                                                  alpha: 0.5,
                                                ),
                                          fontWeight: FontWeight.w500,
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
                      const SizedBox(height: 32),

                      // Action Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                color: _mutedCoolGray,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryAqua,
                              foregroundColor: _darkDeepTeal,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 12,
                              ),
                              elevation: 4,
                            ),
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _darkDeepTeal,
                                    ),
                                  )
                                : const Icon(Icons.check_circle),
                            label: Text(
                              _isSaving
                                  ? 'Analyzing & Saving...'
                                  : 'Save Record',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            onPressed: _isSaving
                                ? null
                                : () async {
                                    if (_formKey.currentState?.validate() ??
                                        false) {
                                      setState(() => _isSaving = true);
                                      // Combine all vital signs into one string
                                      List<String> vitalSignsParts = [];

                                      if (_bloodPressureController
                                          .text
                                          .isNotEmpty) {
                                        vitalSignsParts.add(
                                          'BP: ${_bloodPressureController.text}',
                                        );
                                      }
                                      if (_temperatureController
                                          .text
                                          .isNotEmpty) {
                                        vitalSignsParts.add(
                                          'Temp: ${_temperatureController.text}°C',
                                        );
                                      }
                                      if (_heartRateController
                                          .text
                                          .isNotEmpty) {
                                        vitalSignsParts.add(
                                          'HR: ${_heartRateController.text} bpm',
                                        );
                                      }
                                      if (_respiratoryRateController
                                          .text
                                          .isNotEmpty) {
                                        vitalSignsParts.add(
                                          'RR: ${_respiratoryRateController.text} brpm',
                                        );
                                      }
                                      if (_oxygenSaturationController
                                          .text
                                          .isNotEmpty) {
                                        vitalSignsParts.add(
                                          'O2: ${_oxygenSaturationController.text}%',
                                        );
                                      }
                                      if (_weightController.text.isNotEmpty) {
                                        vitalSignsParts.add(
                                          'Weight: ${_weightController.text} kg',
                                        );
                                      }
                                      if (_heightController.text.isNotEmpty) {
                                        vitalSignsParts.add(
                                          'Height: ${_heightController.text} cm',
                                        );
                                      }

                                      String vitalSignsString = vitalSignsParts
                                          .join(', ');

                                      // Create new record
                                      final now = DateTime.now();
                                      final linkedPatientId =
                                          widget.patientSeed?['linkedPatientId']
                                              ?.toString()
                                              .trim() ??
                                          '';
                                      final patientId =
                                          widget.patientSeed?['patientId']
                                              ?.toString()
                                              .trim() ??
                                          '';
                                      final Map<String, dynamic> newRecord = {
                                        'id': now.millisecondsSinceEpoch
                                            .toString(),
                                        if (linkedPatientId.isNotEmpty)
                                          'linkedPatientId': linkedPatientId,
                                        if (patientId.isNotEmpty)
                                          'patientId': patientId,
                                        'datetime':
                                            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                                        'type': 'General',
                                        'diseaseType': 'General',
                                        'patient':
                                            '${_firstNameController.text} ${_surnameController.text}',
                                        'age': _ageController.text,
                                        'address': _addressController.text,
                                        'vitalsigns': vitalSignsString,
                                        'symptoms': _symptomsController.text,
                                        'details': vitalSignsString.isNotEmpty
                                            ? '$vitalSignsString | ${_symptomsController.text}'
                                            : 'Age: ${_ageController.text}, ${_symptomsController.text}',
                                        'plan': _planController.text,
                                        'followup': _followUpDate != null
                                            ? '${_followUpDate!.year}-${_followUpDate!.month.toString().padLeft(2, '0')}-${_followUpDate!.day.toString().padLeft(2, '0')}'
                                            : 'N/A',
                                      };

                                      SymptomGuidanceResult? guidance;
                                      String? guidanceError;
                                      try {
                                        await widget.onSave(newRecord);
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Unable to save check-up record: $e',
                                              ),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                          setState(() => _isSaving = false);
                                        }
                                        return;
                                      }

                                      try {
                                        guidance = await widget.guidanceApi
                                            .getGuidanceFromText(
                                              _symptomsController.text,
                                            );
                                        newRecord.addAll(
                                          guidance.toRecordFields(),
                                        );
                                        await widget.onGuidanceSave(newRecord);
                                        debugPrint(
                                          'Symptom guidance loaded for: '
                                          '${[...guidance.recognizedSymptoms, ...guidance.recognizedConditions].join(', ')}',
                                        );
                                      } catch (e) {
                                        guidanceError = e.toString();
                                        debugPrint(
                                          'Symptom guidance failed: $e',
                                        );
                                      }

                                      if (context.mounted && guidance != null) {
                                        await _showSymptomGuidanceModal(
                                          context,
                                          guidance,
                                        );
                                      } else if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Record saved, but ${guidanceError ?? 'symptom guidance is unavailable.'}',
                                            ),
                                            backgroundColor: Colors.orange,
                                          ),
                                        );
                                      }

                                      if (context.mounted) {
                                        Navigator.of(context).pop();
                                      }
                                    }
                                  },
                          ),
                        ],
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

  Future<void> _showSymptomGuidanceModal(
    BuildContext context,
    SymptomGuidanceResult result,
  ) async {
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: _darkDeepTeal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 760),
          decoration: BoxDecoration(
            color: _darkDeepTeal,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _lightOffWhite.withValues(alpha: 0.14)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                        Icons.health_and_safety_outlined,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Symptom Guidance',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Firestore-backed self-care and safety information',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recognized Symptoms',
                        style: TextStyle(
                          color: _lightOffWhite,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: result.recognizedSymptoms
                            .map(
                              (symptom) => Chip(
                                label: Text(symptom),
                                backgroundColor: _primaryAqua.withValues(
                                  alpha: 0.18,
                                ),
                                labelStyle: const TextStyle(
                                  color: _lightOffWhite,
                                ),
                                side: BorderSide(
                                  color: _primaryAqua.withValues(alpha: 0.45),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      if (result.recognizedConditions.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const Text(
                          'Entered Conditions (not AI predictions)',
                          style: TextStyle(
                            color: _lightOffWhite,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: result.recognizedConditions
                              .map(
                                (condition) => Chip(
                                  avatar: const Icon(
                                    Icons.fact_check_outlined,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  label: Text(condition),
                                  backgroundColor: Colors.blue.withValues(
                                    alpha: 0.18,
                                  ),
                                  labelStyle: const TextStyle(
                                    color: _lightOffWhite,
                                  ),
                                  side: BorderSide(
                                    color: Colors.blue.withValues(alpha: 0.45),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      if (result.homeCare.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _buildModalRecommendationSection(
                          icon: Icons.home_outlined,
                          title: 'Home Care / Self-Care',
                          color: Colors.green,
                          items: result.homeCare,
                        ),
                      ],
                      if (result.precautions.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildModalRecommendationSection(
                          icon: Icons.warning_amber_rounded,
                          title: 'Important Precautions',
                          color: Colors.orange,
                          items: result.precautions,
                        ),
                      ],
                      if (result.whenToSeekCare.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildModalRecommendationSection(
                          icon: Icons.medical_services_outlined,
                          title: 'When to Seek Medical Care',
                          color: Colors.blue,
                          items: result.whenToSeekCare,
                        ),
                      ],
                      if (result.emergencyWarningSigns.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildModalRecommendationSection(
                          icon: Icons.emergency_outlined,
                          title: 'Emergency Warning Signs',
                          color: Colors.red,
                          items: result.emergencyWarningSigns,
                        ),
                      ],
                      if (result.ignoredSymptoms.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildPredictionNotice(
                          'Not recognized: ${result.ignoredSymptoms.join(', ')}',
                          color: Colors.orange,
                          icon: Icons.help_outline,
                        ),
                      ],
                      if (result.missingGuidanceSymptoms.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildPredictionNotice(
                          'General safety guidance was used for: '
                          '${result.missingGuidanceSymptoms.join(', ')}',
                          color: Colors.blueGrey,
                          icon: Icons.info_outline,
                        ),
                      ],
                      if (result.missingGuidanceConditions.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildPredictionNotice(
                          'No reviewed Firestore guidance is available for: '
                          '${result.missingGuidanceConditions.join(', ')}',
                          color: Colors.orange,
                          icon: Icons.info_outline,
                        ),
                      ],
                      if (!result.contentAvailable) ...[
                        const SizedBox(height: 16),
                        _buildPredictionNotice(
                          'Symptom guidance could not be loaded from Firestore.',
                          color: Colors.orange,
                          icon: Icons.cloud_off_outlined,
                        ),
                      ],
                      if (result.disclaimer.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildPredictionNotice(
                          result.disclaimer,
                          color: Colors.blueGrey,
                          icon: Icons.info_outline,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.check),
                    label: const Text('Got It'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryAqua,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDiseasePredictionModal(
    BuildContext context,
    DiseasePredictionResult result,
  ) async {
    final info = result.diseaseInformation;
    final recordFields = result.toRecordFields();
    final recoveryPlan = _parseAiRecoveryPlan(recordFields['ai_recovery_plan']);
    final category = info?.name.isNotEmpty == true
        ? info!.name
        : result.prediction.disease;
    final severity = result.confidenceThresholdMet
        ? 'Decision support'
        : 'Low confidence';
    final confidence = result.prediction.confidence / 100;
    final keywords = result.recognizedSymptoms.join(', ');

    // Show the actual AI classification result modal
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
                            'AI Disease Prediction',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Firestore-backed educational guidance',
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

              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Classification Summary
                      _buildModalClassificationSummary(
                        category,
                        severity,
                        confidence,
                        keywords,
                      ),
                      if (result.warning != null) ...[
                        const SizedBox(height: 12),
                        _buildPredictionNotice(
                          result.warning!,
                          color: Colors.orange,
                          icon: Icons.warning_amber_rounded,
                        ),
                      ],
                      if (info?.description.isNotEmpty == true) ...[
                        const SizedBox(height: 20),
                        Text(
                          info!.description,
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.88),
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      _buildTopPredictions(result.topPredictions),
                      const SizedBox(height: 24),
                      if (recoveryPlan != null)
                        _buildModalRecoveryPlan(recoveryPlan),
                      if (info?.recommendedSpecialist.isNotEmpty == true) ...[
                        const SizedBox(height: 16),
                        _buildModalRecommendationSection(
                          icon: Icons.medical_services_outlined,
                          title: 'Recommended Specialist',
                          color: Colors.blue,
                          items: info!.recommendedSpecialist,
                        ),
                      ],
                      if (result.ignoredSymptoms.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildPredictionNotice(
                          'Not recognized by the model: '
                          '${result.ignoredSymptoms.join(', ')}',
                          color: Colors.orange,
                          icon: Icons.help_outline,
                        ),
                      ],
                      if (!result.contentAvailable) ...[
                        const SizedBox(height: 16),
                        _buildPredictionNotice(
                          result.fallbackMessage ??
                              'No educational content is available for this prediction.',
                          color: Colors.orange,
                          icon: Icons.cloud_off_outlined,
                        ),
                      ],
                      if (result.disclaimer.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildPredictionNotice(
                          result.disclaimer,
                          color: Colors.blueGrey,
                          icon: Icons.info_outline,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Footer Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _darkDeepTeal,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: _lightOffWhite.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text(
                        'Close',
                        style: TextStyle(color: _lightOffWhite),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Got It'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryAqua,
                        foregroundColor: _lightOffWhite,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
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

  Widget _buildTopPredictions(List<DiseasePrediction> predictions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Top Predictions',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: _lightOffWhite,
          ),
        ),
        const SizedBox(height: 10),
        ...predictions.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '#${item.rank}',
                    style: const TextStyle(
                      color: _primaryAqua,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    item.disease,
                    style: const TextStyle(color: _lightOffWhite),
                  ),
                ),
                Text(
                  '${item.confidence.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: _lightOffWhite.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPredictionNotice(
    String message, {
    required Color color,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: _lightOffWhite.withValues(alpha: 0.9),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModalClassificationSummary(
    String category,
    String severity,
    double confidence,
    String keywords,
  ) {
    Color severityColor;
    IconData severityIcon;

    switch (severity.toLowerCase()) {
      case 'critical':
        severityColor = Colors.red;
        severityIcon = Icons.local_hospital;
        break;
      case 'high':
        severityColor = Colors.orange;
        severityIcon = Icons.warning;
        break;
      case 'moderate':
        severityColor = Colors.amber;
        severityIcon = Icons.info;
        break;
      case 'low':
        severityColor = Colors.green;
        severityIcon = Icons.check_circle;
        break;
      default:
        severityColor = Colors.blue;
        severityIcon = Icons.info;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: severityColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: severityColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(severityIcon, color: severityColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: severityColor,
                      ),
                    ),
                    Text(
                      'Severity: $severity',
                      style: TextStyle(
                        fontSize: 14,
                        color: severityColor.withValues(alpha: 0.8),
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
                  color: _lightOffWhite.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _lightOffWhite.withValues(alpha: 0.12),
                  ),
                ),
                child: Text(
                  '${(confidence * 100).toStringAsFixed(0)}% confident',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _lightOffWhite,
                  ),
                ),
              ),
            ],
          ),
          if (keywords.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Detected Keywords:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _lightOffWhite,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: keywords.split(',').map((keyword) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _lightOffWhite.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: severityColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    keyword.trim(),
                    style: TextStyle(
                      fontSize: 11,
                      color: severityColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModalRecoveryPlan(Map<String, dynamic> recoveryPlan) {
    final homeCare = _safeAiStringList(recoveryPlan['home_care']);
    final precautions = _safeAiStringList(recoveryPlan['precautions']);
    final estimatedRecovery = _safeAiText(
      recoveryPlan['estimated_recovery'],
      fallback: '',
    );
    final generalAdvice = _safeAiStringList(recoveryPlan['general_advice']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.healing_outlined, color: _lightOffWhite, size: 20),
            SizedBox(width: 8),
            Text(
              'AI-Assisted Home-Care Recommendation',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _lightOffWhite,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (homeCare.isNotEmpty) ...[
          _buildModalRecommendationSection(
            icon: Icons.home_outlined,
            title: 'Home Remedies / Self-Care',
            color: Colors.green,
            items: homeCare,
          ),
          const SizedBox(height: 16),
        ],
        if (precautions.isNotEmpty) ...[
          _buildModalRecommendationSection(
            icon: Icons.warning_amber,
            title: 'Emergency Warning Signs',
            color: Colors.orange,
            items: precautions,
          ),
          const SizedBox(height: 16),
        ],
        if (generalAdvice.isNotEmpty) ...[
          _buildModalRecommendationSection(
            icon: Icons.tips_and_updates,
            title: 'Prevention / When to Seek Care',
            color: Colors.purple,
            items: generalAdvice,
          ),
          const SizedBox(height: 16),
        ],
        if (estimatedRecovery.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _lightOffWhite.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _lightOffWhite.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule, color: _primaryAqua, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Estimated Recovery: $estimatedRecovery',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _lightOffWhite,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _lightOffWhite.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _lightOffWhite.withValues(alpha: 0.12)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: _primaryAqua, size: 14),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'AI-generated information provides supportive home-care '
                  'guidance only. Medication and clinical decisions remain '
                  'under the attending physician.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white70,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModalRecommendationSection({
    required IconData icon,
    required String title,
    required Color color,
    required List<String> items,
  }) {
    return Container(
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
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
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
                  Text('• ', style: TextStyle(color: color, fontSize: 14)),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 13,
                        color: _lightOffWhite.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _surnameController.dispose();
    _ageController.dispose();
    _addressController.dispose();

    // Dispose all vital sign controllers
    _bloodPressureController.dispose();
    _temperatureController.dispose();
    _heartRateController.dispose();
    _respiratoryRateController.dispose();
    _oxygenSaturationController.dispose();
    _weightController.dispose();
    _heightController.dispose();

    _symptomsController.dispose();
    _planController.dispose();
    super.dispose();
  }
}

// Edit Check Up Modal
class _EditCheckUpFullScreenModal extends StatefulWidget {
  final Map<String, dynamic> record;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final HealthAIClassifier aiClassifier;

  const _EditCheckUpFullScreenModal({
    required this.record,
    required this.onSave,
    required this.aiClassifier,
  });

  @override
  State<_EditCheckUpFullScreenModal> createState() =>
      _EditCheckUpFullScreenModalState();
}

class _EditCheckUpFullScreenModalState
    extends State<_EditCheckUpFullScreenModal> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _surnameController;
  late final TextEditingController _ageController;
  late final TextEditingController _addressController;

  // Separate vital sign controllers
  late final TextEditingController _bloodPressureController;
  late final TextEditingController _temperatureController;
  late final TextEditingController _heartRateController;
  late final TextEditingController _respiratoryRateController;
  late final TextEditingController _oxygenSaturationController;
  late final TextEditingController _weightController;
  late final TextEditingController _heightController;

  late final TextEditingController _symptomsController;
  late final TextEditingController _planController;
  DateTime? _followUpDate;
  final String _recordType = 'General';
  String _diseaseType = 'General';

  @override
  void initState() {
    super.initState();

    // Initialize controllers with existing data
    final patientName = widget.record['patient'] ?? '';
    final nameParts = patientName.split(' ');
    _firstNameController = TextEditingController(
      text: nameParts.isNotEmpty ? nameParts[0] : '',
    );
    _surnameController = TextEditingController(
      text: nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '',
    );
    _ageController = TextEditingController(
      text: widget.record['age']?.toString() ?? '',
    );
    _addressController = TextEditingController(
      text: widget.record['address'] ?? '',
    );

    // Parse vital signs from the record
    final vitalSigns = widget.record['vitalsigns'] ?? '';
    final vitalParts = vitalSigns.split(', ');
    _bloodPressureController = TextEditingController(
      text: _extractVital(vitalParts, 'BP:'),
    );
    _temperatureController = TextEditingController(
      text: _extractVital(vitalParts, 'Temp:'),
    );
    _heartRateController = TextEditingController(
      text: _extractVital(vitalParts, 'HR:'),
    );
    _respiratoryRateController = TextEditingController(
      text: _extractVital(vitalParts, 'RR:'),
    );
    _oxygenSaturationController = TextEditingController(
      text: _extractVital(vitalParts, 'O2:'),
    );
    _weightController = TextEditingController(
      text: _extractVital(vitalParts, 'Weight:'),
    );
    _heightController = TextEditingController(
      text: _extractVital(vitalParts, 'Height:'),
    );

    _symptomsController = TextEditingController(
      text: widget.record['symptoms'] ?? '',
    );
    _planController = TextEditingController(text: widget.record['plan'] ?? '');

    // Initialize _diseaseType from record
    final availableDiseaseTypes = [
      'General',
      'Communicable',
      'Non-Communicable',
    ];
    final diseaseType = widget.record['diseaseType'] ?? 'General';
    _diseaseType = availableDiseaseTypes.contains(diseaseType)
        ? diseaseType
        : 'General';

    if (widget.record['followup'] != null &&
        widget.record['followup'] != 'N/A') {
      try {
        _followUpDate = DateTime.parse(widget.record['followup']);
      } catch (e) {
        _followUpDate = null;
      }
    }
  }

  String _extractVital(List<String> parts, String prefix) {
    for (var part in parts) {
      if (part.trim().startsWith(prefix)) {
        String value = part.trim().substring(prefix.length).trim();
        // Remove unit suffixes to prevent duplication on re-save
        value = value
            .replaceAll(RegExp(r'°C$'), '')
            .replaceAll(RegExp(r'\s*brpm$', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s*bpm$', caseSensitive: false), '')
            .replaceAll(RegExp(r'%$'), '')
            .replaceAll(RegExp(r'\s*kg$', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s*cm$', caseSensitive: false), '')
            .trim();
        return value;
      }
    }
    return '';
  }

  // Helper method to build section cards
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
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

  // Helper method for input decoration
  InputDecoration _buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: _lightOffWhite.withValues(alpha: 0.7)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: _lightOffWhite.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: _lightOffWhite.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: _lightOffWhite.withValues(alpha: 0.7),
          width: 2,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      filled: true,
      fillColor: Colors.transparent,
      hintStyle: TextStyle(color: _lightOffWhite.withValues(alpha: 0.5)),
      floatingLabelStyle: const TextStyle(color: Colors.white),
    );
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
          color: _lightOffWhite,
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
                  // Header with close button
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit Check Up Record',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: _darkDeepTeal,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Update patient check-up information',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: _mutedCoolGray),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: _darkDeepTeal),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Same form fields as _NewCheckUpFullScreenModal
                  Text(
                    'Patient Information',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _darkDeepTeal,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _firstNameController,
                          decoration: _buildInputDecoration('First Name'),
                          validator: (value) =>
                              value?.isEmpty == true ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _surnameController,
                          decoration: _buildInputDecoration('Surname'),
                          validator: (value) =>
                              value?.isEmpty == true ? 'Required' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _ageController,
                          decoration: _buildInputDecoration('Age'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _addressController,
                          decoration: _buildInputDecoration('Address'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  Text(
                    'Vital Signs',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _darkDeepTeal,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _bloodPressureController,
                          decoration: _buildInputDecoration('Blood Pressure'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _temperatureController,
                          decoration: _buildInputDecoration('Temperature (°C)'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _heartRateController,
                          decoration: _buildInputDecoration('Heart Rate (bpm)'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _respiratoryRateController,
                          decoration: _buildInputDecoration('Respiratory Rate'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _oxygenSaturationController,
                          decoration: _buildInputDecoration(
                            'Oxygen Saturation (%)',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _weightController,
                          decoration: _buildInputDecoration('Weight (kg)'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _heightController,
                    decoration: _buildInputDecoration('Height (cm)'),
                    keyboardType: TextInputType.number,
                  ),

                  const SizedBox(height: 24),
                  Text(
                    'Check-Up Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _darkDeepTeal,
                    ),
                  ),
                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    initialValue: _diseaseType,
                    decoration: _buildInputDecoration('Disease Classification'),
                    items: const [
                      DropdownMenuItem(
                        value: 'General',
                        child: Text('General Check-up'),
                      ),
                      DropdownMenuItem(
                        value: 'Communicable',
                        child: Text('Communicable Disease'),
                      ),
                      DropdownMenuItem(
                        value: 'Non-Communicable',
                        child: Text('Non-Communicable Disease'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _diseaseType = value);
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _symptomsController,
                    decoration: _buildInputDecoration('Symptoms'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _planController,
                    decoration: _buildInputDecoration('Treatment Plan'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),

                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _followUpDate ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => _followUpDate = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: _buildInputDecoration('Follow-up Date'),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _followUpDate != null
                                ? "${_followUpDate!.year}-${_followUpDate!.month.toString().padLeft(2, '0')}-${_followUpDate!.day.toString().padLeft(2, '0')}"
                                : 'Select Date',
                            style: TextStyle(
                              color: _followUpDate != null
                                  ? _darkDeepTeal
                                  : _mutedCoolGray,
                            ),
                          ),
                          const Icon(Icons.calendar_today, color: _primaryAqua),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          final patientName =
                              '${_firstNameController.text} ${_surnameController.text}';

                          // Build vital signs string
                          List<String> vitalsList = [];
                          if (_bloodPressureController.text.isNotEmpty) {
                            vitalsList.add(
                              'BP: ${_bloodPressureController.text}',
                            );
                          }
                          if (_temperatureController.text.isNotEmpty) {
                            vitalsList.add(
                              'Temp: ${_temperatureController.text}°C',
                            );
                          }
                          if (_heartRateController.text.isNotEmpty) {
                            vitalsList.add(
                              'HR: ${_heartRateController.text} bpm',
                            );
                          }
                          if (_respiratoryRateController.text.isNotEmpty) {
                            vitalsList.add(
                              'RR: ${_respiratoryRateController.text} brpm',
                            );
                          }
                          if (_oxygenSaturationController.text.isNotEmpty) {
                            vitalsList.add(
                              'O2: ${_oxygenSaturationController.text}%',
                            );
                          }
                          if (_weightController.text.isNotEmpty) {
                            vitalsList.add(
                              'Weight: ${_weightController.text} kg',
                            );
                          }
                          if (_heightController.text.isNotEmpty) {
                            vitalsList.add(
                              'Height: ${_heightController.text} cm',
                            );
                          }

                          final vitalSigns = vitalsList.join(', ');

                          final updatedRecord = {
                            'id': widget.record['id'], // Keep the original ID
                            'patient': patientName,
                            'age': _ageController.text,
                            'address': _addressController.text,
                            'type': 'General',
                            'diseaseType': _diseaseType,
                            'datetime': widget
                                .record['datetime'], // Keep original datetime
                            'vitalsigns': vitalSigns,
                            'symptoms': _symptomsController.text,
                            'plan': _planController.text,
                            'followup': _followUpDate != null
                                ? '${_followUpDate!.year}-${_followUpDate!.month.toString().padLeft(2, '0')}-${_followUpDate!.day.toString().padLeft(2, '0')}'
                                : 'N/A',
                          };

                          // AI Classification on edited record
                          ClassificationResult? classification;
                          try {
                            debugPrint(
                              '🤖 Starting AI classification on edited record...',
                            );
                            classification = await widget.aiClassifier.classify(
                              updatedRecord,
                            );
                            debugPrint(
                              '✅ AI Classification complete: ${classification.category}',
                            );

                            updatedRecord['ai_category'] =
                                classification.category;
                            updatedRecord['ai_severity'] =
                                classification.severity;
                            updatedRecord['ai_confidence'] =
                                classification.confidence;
                            updatedRecord['ai_method'] = classification.method;
                            if (classification.keywords != null) {
                              updatedRecord['ai_keywords'] = classification
                                  .keywords!
                                  .join(', ');
                            }
                            if (classification.recoveryPlan != null) {
                              updatedRecord['ai_recovery_plan'] =
                                  Map<String, dynamic>.from(
                                    classification.recoveryPlan!,
                                  );
                            }
                          } catch (e) {
                            debugPrint(
                              '❌ AI classification failed on edit: $e',
                            );
                          }

                          await widget.onSave(updatedRecord);

                          // Show AI Classification modal BEFORE popping
                          if (context.mounted && classification != null) {
                            await _showEditAIClassificationModal(
                              context,
                              classification,
                            );
                          }

                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryAqua,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 4,
                      ),
                      child: const Text(
                        'Update Record',
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
          ),
        ),
      ),
    );
  }

  // Show AI loading spinner then classification result modal for edited record
  Future<void> _showEditAIClassificationModal(
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
                    'Re-analyzing Health Data...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'AI is re-classifying your updated record',
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

      // Wait 3 seconds then dismiss loading dialog
      await Future.delayed(const Duration(seconds: 3));
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }

    final recoveryPlan = _parseAiRecoveryPlan(classification.recoveryPlan);
    final category = _safeAiText(classification.category, fallback: 'Unknown');
    final severity = _safeAiText(classification.severity, fallback: 'Unknown');
    final confidence = _safeAiConfidence(classification.confidence);
    final keywords = _safeAiKeywords(
      classification.keywords?.join(', '),
    ).join(', ');

    // Show the actual AI classification result modal
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
                            'AI Re-Classification Complete',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Updated record analyzed successfully',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.check_circle,
                      color: Colors.greenAccent,
                      size: 28,
                    ),
                  ],
                ),
              ),

              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildEditModalClassificationSummary(
                        category,
                        severity,
                        confidence,
                        keywords,
                      ),
                      const SizedBox(height: 24),
                      if (recoveryPlan != null)
                        _buildEditModalRecoveryPlan(recoveryPlan),
                    ],
                  ),
                ),
              ),

              // Footer Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _darkDeepTeal,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: _lightOffWhite.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text(
                        'Close',
                        style: TextStyle(color: _lightOffWhite),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Got It'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryAqua,
                        foregroundColor: _lightOffWhite,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
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

  Widget _buildEditModalClassificationSummary(
    String category,
    String severity,
    double confidence,
    String keywords,
  ) {
    Color severityColor;
    IconData severityIcon;

    switch (severity.toLowerCase()) {
      case 'critical':
        severityColor = Colors.red;
        severityIcon = Icons.local_hospital;
        break;
      case 'high':
        severityColor = Colors.orange;
        severityIcon = Icons.warning;
        break;
      case 'moderate':
        severityColor = Colors.amber;
        severityIcon = Icons.info;
        break;
      case 'low':
        severityColor = Colors.green;
        severityIcon = Icons.check_circle;
        break;
      default:
        severityColor = Colors.blue;
        severityIcon = Icons.info;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: severityColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: severityColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(severityIcon, color: severityColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: severityColor,
                      ),
                    ),
                    Text(
                      'Severity: $severity',
                      style: TextStyle(
                        fontSize: 14,
                        color: severityColor.withValues(alpha: 0.8),
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
                  color: _lightOffWhite.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _lightOffWhite.withValues(alpha: 0.12),
                  ),
                ),
                child: Text(
                  '${(confidence * 100).toStringAsFixed(0)}% confident',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _lightOffWhite,
                  ),
                ),
              ),
            ],
          ),
          if (keywords.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Detected Keywords:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _lightOffWhite,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: keywords.split(',').map((keyword) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _lightOffWhite.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: severityColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    keyword.trim(),
                    style: TextStyle(
                      fontSize: 11,
                      color: severityColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEditModalRecoveryPlan(Map<String, dynamic> recoveryPlan) {
    final homeCare = _safeAiStringList(recoveryPlan['home_care']);
    final precautions = _safeAiStringList(recoveryPlan['precautions']);
    final estimatedRecovery = _safeAiText(
      recoveryPlan['estimated_recovery'],
      fallback: '',
    );
    final generalAdvice = _safeAiStringList(recoveryPlan['general_advice']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.healing_outlined, color: _lightOffWhite, size: 20),
            SizedBox(width: 8),
            Text(
              'AI-Assisted Home-Care Recommendation',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _lightOffWhite,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (homeCare.isNotEmpty) ...[
          _buildEditModalRecommendationSection(
            icon: Icons.home_outlined,
            title: 'Home Care',
            color: Colors.green,
            items: homeCare,
          ),
          const SizedBox(height: 16),
        ],
        if (precautions.isNotEmpty) ...[
          _buildEditModalRecommendationSection(
            icon: Icons.warning_amber,
            title: 'Precautions',
            color: Colors.orange,
            items: precautions,
          ),
          const SizedBox(height: 16),
        ],
        if (generalAdvice.isNotEmpty) ...[
          _buildEditModalRecommendationSection(
            icon: Icons.tips_and_updates,
            title: 'General Advice',
            color: Colors.purple,
            items: generalAdvice,
          ),
          const SizedBox(height: 16),
        ],
        if (estimatedRecovery.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _lightOffWhite.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _lightOffWhite.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule, color: _primaryAqua, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Estimated Recovery: $estimatedRecovery',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _lightOffWhite,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _lightOffWhite.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _lightOffWhite.withValues(alpha: 0.12)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: _primaryAqua, size: 14),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'AI-generated information provides supportive home-care '
                  'guidance only. Medication and clinical decisions remain '
                  'under the attending physician.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white70,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditModalRecommendationSection({
    required IconData icon,
    required String title,
    required Color color,
    required List<String> items,
  }) {
    return Container(
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
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
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
                  Text('• ', style: TextStyle(color: color, fontSize: 14)),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 13,
                        color: _lightOffWhite.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _surnameController.dispose();
    _ageController.dispose();
    _addressController.dispose();
    _bloodPressureController.dispose();
    _temperatureController.dispose();
    _heartRateController.dispose();
    _respiratoryRateController.dispose();
    _oxygenSaturationController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _symptomsController.dispose();
    _planController.dispose();
    super.dispose();
  }
}
