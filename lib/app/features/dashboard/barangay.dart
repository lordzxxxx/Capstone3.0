import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mycapstone_project/app/features/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/app/features/prenatal/prenatal_database_helper.dart';
import 'package:mycapstone_project/app/features/immunization/immunization_database_helper.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _secondaryIceBlue = AppDesign.blueSoft;
const Color _darkDeepTeal = AppDesign.page;
const Color _mutedCoolGray = AppDesign.muted;
const Color _lightOffWhite = AppDesign.ink;
const Color _emergencyRed = Color(0xFFE74C3C);
const Color _warningOrange = Color(0xFFF39C12);
const Color _successGreen = Color(0xFF27AE60);

class BarangayRecordsPage extends StatefulWidget {
  const BarangayRecordsPage({super.key});

  @override
  State<BarangayRecordsPage> createState() => _BarangayRecordsPageState();
}

class _BarangayRecordsPageState extends State<BarangayRecordsPage> {
  final DatabaseHelper _checkupDB = DatabaseHelper.instance;
  final PrenatalDatabaseHelper _prenatalDB = PrenatalDatabaseHelper.instance;
  final ImmunizationDatabaseHelper _immunizationDB =
      ImmunizationDatabaseHelper.instance;

  // Aggregated Records
  List<Map<String, dynamic>> _checkupRecords = [];
  List<Map<String, dynamic>> _prenatalRecords = [];
  List<Map<String, dynamic>> _immunizationRecords = [];
  List<Map<String, dynamic>> _barangayRecords = [];

  // Community Statistics
  int _totalPatients = 0;
  int _totalCheckups = 0;
  int _communicableDiseases = 0;
  int _nonCommunicableDiseases = 0;
  int _emergencyCases = 0;
  int _prenatalCases = 0;
  int _immunizedChildren = 0;

  bool _isLoading = true;
  Timer? _refreshTimer;
  DateTime? _lastUpdated;
  final String _selectedTimeRange = 'All'; // All, This Month, This Year

  @override
  void initState() {
    super.initState();
    _loadAllData();
    // Auto-refresh every 10 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadAllData();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    try {
      final checkupData = await _checkupDB.getAllRecords();
      final prenatalData = await _prenatalDB.getAllRecords();
      final immunizationData = await _immunizationDB.getAllRecords();
      final barangayData = await _fetchBarangayRecords();

      if (mounted) {
        setState(() {
          _checkupRecords = checkupData;
          _prenatalRecords = prenatalData;
          _immunizationRecords = immunizationData;
          _barangayRecords = barangayData;
          _generateCommunityStatistics();
          _lastUpdated = DateTime.now();
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading barangay data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchBarangayRecords() async {
    if (kIsWeb) {
      try {
        final snapshot = await getFirestoreInstance()
            .collection('barangay_records')
            .orderBy('recordDate', descending: true)
            .get();
        return snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
      } catch (e) {
        print('Error fetching barangay records: $e');
        return [];
      }
    }
    return [];
  }

  void _generateCommunityStatistics() {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final currentYear = now.year;

    // Count unique patients
    final uniquePatients = <String>{};
    for (var record in _checkupRecords) {
      final patient = record['patient']?.toString() ?? '';
      if (patient.isNotEmpty) uniquePatients.add(patient);
    }
    for (var record in _prenatalRecords) {
      final patient = record['patientName']?.toString() ?? '';
      if (patient.isNotEmpty) uniquePatients.add(patient);
    }

    _totalPatients = uniquePatients.length;
    _totalCheckups = _checkupRecords.length;

    // Classify diseases (based on AI classification)
    _communicableDiseases = 0;
    _nonCommunicableDiseases = 0;
    _emergencyCases = 0;

    for (var record in _checkupRecords) {
      final category = record['ai_category']?.toString() ?? '';
      final severity = record['ai_severity']?.toString() ?? '';

      if (category == 'Emergency' || severity == 'Critical') {
        _emergencyCases++;
      } else if (category == 'Communicable Disease') {
        _communicableDiseases++;
      } else if (category == 'Non-Communicable Disease') {
        _nonCommunicableDiseases++;
      }
    }

    // Count prenatal and pediatric
    _prenatalCases = _prenatalRecords.length;
    _immunizedChildren = _immunizationRecords
        .where((r) => r['status'] == 'Completed')
        .length;
  }

  void _saveSummaryToFirebase() async {
    try {
      final summaryData = {
        'barangayName': 'Your Barangay',
        'recordDate': DateTime.now().toIso8601String(),
        'totalPatients': _totalPatients,
        'totalCheckups': _totalCheckups,
        'communicableDiseases': _communicableDiseases,
        'nonCommunicableDiseases': _nonCommunicableDiseases,
        'emergencyCases': _emergencyCases,
        'prenatalCases': _prenatalCases,
        'immunizedChildren': _immunizedChildren,
        'lastUpdated': DateTime.now().toIso8601String(),
      };

      await getFirestoreInstance()
          .collection('barangay_records')
          .add(summaryData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Barangay summary saved successfully'),
            backgroundColor: _successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving summary: $e'),
            backgroundColor: _emergencyRed,
          ),
        );
      }
    }
  }

  Future<void> _seedBarangayData() async {
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
            Text('Seeding 100 sample barangay records...'),
          ],
        ),
      ),
    );

    try {
      final List<String> barangays = [
        'Del Carmen',
        'Sagcahan',
        'Binakayan',
        'Kanluran',
        'Silang',
        'Salawag',
        'Paliparan',
        'Pag-asa',
        'Sampalukan',
        'Bagtas',
        'Magdalo',
        'Bayan',
        'Caloocan',
        'San Roque',
        'Dasmariñas',
        'Pakil',
        'Marikina',
      ];

      final List<String> recordTypes = [
        'Regular Checkup',
        'Vaccination',
        'Prenatal Care',
        'Child Immunization',
        'Disease Surveillance',
        'Health Education',
        'Community Outreach',
        'Emergency Medical Care',
        'Chronic Disease Management',
        'Follow-up Visit',
      ];

      final List<String> statuses = [
        'Completed',
        'Completed',
        'Completed',
        'In Progress',
        'Pending Review',
      ];

      final List<String> findings = [
        'Healthy',
        'Mild Condition',
        'Moderate Condition',
        'Referral Required',
        'Requires Hospitalization',
        'Normal',
        'Abnormal Findings',
      ];

      int savedCount = 0;
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      for (int i = 0; i < 100; i++) {
        final recordDate = DateTime.now().subtract(
          Duration(days: 300 - (i * 3)),
        );

        final barangayRecord = {
          'barangayName': barangays[i % barangays.length],
          'recordType': recordTypes[i % recordTypes.length],
          'recordDate': recordDate.toIso8601String(),
          'status': statuses[i % statuses.length],
          'findings': findings[i % findings.length],
          'patientCount': 5 + (i % 20),
          'casesIdentified': 1 + (i % 8),
          'casesResolved': i % 3 == 0 ? 0 : 1 + (i % 6),
          'referralsIssued': i % 5 == 0 ? 0 : 1 + (i % 4),
          'vaccinesAdministered': i % 2 == 0 ? 0 : 5 + (i % 20),
          'healthEducationAttendees': 10 + (i % 50),
          'notes': 'Sample barangay health record #${i + 1}',
          'recordedBy': 'Health Worker ${(i % 5) + 1}',
          'timestamp': timestamp + i,
          'createdAt': DateTime.now(),
        };

        await getFirestoreInstance()
            .collection('barangay_records')
            .add(barangayRecord);

        savedCount++;
      }

      // Close loading dialog
      Navigator.of(context).pop();

      // Reload data
      await _loadAllData();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully added $savedCount sample barangay records.',
            ),
            backgroundColor: _successGreen,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error seeding data: $e'),
            backgroundColor: _emergencyRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _darkDeepTeal,
        appBar: AppBar(
          backgroundColor: AppDesign.navy,
          title: const Text(
            'Barangay Health Records',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 0,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: _primaryAqua),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _darkDeepTeal,
      appBar: AppBar(
        backgroundColor: AppDesign.navy,
        title: const Text(
          'Barangay Health Records',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: _loadAllData,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save Summary',
            onPressed: _saveSummaryToFirebase,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Last Updated
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _lightOffWhite.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Last updated: ${_lastUpdated != null ? _formatDateTime(_lastUpdated!) : "N/A"}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Dashboard Title
            _buildSectionTitle('Community Health Dashboard'),
            const SizedBox(height: 16),

            // Key Metrics Grid
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.3,
              children: [
                _buildMetricCard(
                  'Total Patients',
                  '$_totalPatients',
                  Icons.people,
                  _primaryAqua,
                ),
                _buildMetricCard(
                  'Total Checkups',
                  '$_totalCheckups',
                  Icons.medical_services,
                  _secondaryIceBlue,
                ),
                _buildMetricCard(
                  'Emergency Cases',
                  '$_emergencyCases',
                  Icons.warning,
                  _emergencyRed,
                ),
                _buildMetricCard(
                  'Prenatal Cases',
                  '$_prenatalCases',
                  Icons.pregnant_woman,
                  _warningOrange,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Disease Statistics Section
            _buildSectionTitle('Disease Classification Statistics'),
            const SizedBox(height: 16),
            _buildDiseaseStatsCards(),
            const SizedBox(height: 24),

            // Vaccination Statistics
            _buildSectionTitle('Immunization Status'),
            const SizedBox(height: 16),
            _buildVaccinationStatsCard(),
            const SizedBox(height: 24),

            // Recent Barangay Summary Records
            if (_barangayRecords.isNotEmpty) ...[
              _buildSectionTitle('Recent Summary Records'),
              const SizedBox(height: 16),
              _buildRecentRecordsList(),
              const SizedBox(height: 24),
            ],

            // Top Health Issues
            _buildSectionTitle('Top Health Concerns'),
            const SizedBox(height: 16),
            _buildHealthConcernsList(),
            const SizedBox(height: 24),

            // Action Buttons
            _buildSectionTitle('Actions'),
            const SizedBox(height: 16),
            _buildActionButtons(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _lightOffWhite.withValues(alpha: 0.4),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiseaseStatsCards() {
    final total =
        _communicableDiseases + _nonCommunicableDiseases + _emergencyCases;
    final commPercent = total > 0
        ? ((_communicableDiseases / total) * 100).toStringAsFixed(1)
        : '0.0';
    final nonCommPercent = total > 0
        ? ((_nonCommunicableDiseases / total) * 100).toStringAsFixed(1)
        : '0.0';
    final emergPercent = total > 0
        ? ((_emergencyCases / total) * 100).toStringAsFixed(1)
        : '0.0';

    return Column(
      children: [
        _buildStatsBar(
          'Communicable Diseases',
          '$_communicableDiseases ($commPercent%)',
          _communicableDiseases.toDouble(),
          total.toDouble(),
          _successGreen,
        ),
        const SizedBox(height: 12),
        _buildStatsBar(
          'Non-Communicable Diseases',
          '$_nonCommunicableDiseases ($nonCommPercent%)',
          _nonCommunicableDiseases.toDouble(),
          total.toDouble(),
          _warningOrange,
        ),
        const SizedBox(height: 12),
        _buildStatsBar(
          'Emergency/Critical Cases',
          '$_emergencyCases ($emergPercent%)',
          _emergencyCases.toDouble(),
          total.toDouble(),
          _emergencyRed,
        ),
      ],
    );
  }

  Widget _buildStatsBar(
    String label,
    String value,
    double current,
    double total,
    Color color,
  ) {
    final percentage = total > 0 ? current / total : 0.0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _lightOffWhite.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentage,
              minHeight: 8,
              backgroundColor: _mutedCoolGray.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVaccinationStatsCard() {
    final totalImmunizationRecords = _immunizationRecords.length;
    final completedPercent = totalImmunizationRecords > 0
        ? ((_immunizedChildren / totalImmunizationRecords) * 100)
              .toStringAsFixed(1)
        : '0.0';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _lightOffWhite.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.vaccines, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              const Text(
                'Immunization Coverage',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_immunizedChildren / $totalImmunizationRecords',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Children Immunized',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _successGreen.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _lightOffWhite.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Text(
                  '$completedPercent%',
                  style: const TextStyle(
                    color: _successGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentRecordsList() {
    if (_barangayRecords.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'No summary records yet',
          style: TextStyle(color: Colors.white, fontSize: 13),
        ),
      );
    }

    return Column(
      children: _barangayRecords.take(3).map((record) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _lightOffWhite.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Barangay Summary - ${_formatDateTime(DateTime.parse(record['recordDate'] ?? DateTime.now().toIso8601String()))}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildInfoChip('Patients: ${record['totalPatients'] ?? 0}'),
                  _buildInfoChip('Checkups: ${record['totalCheckups'] ?? 0}'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildInfoChip('Emergency: ${record['emergencyCases'] ?? 0}'),
                  _buildInfoChip('Prenatal: ${record['prenatalCases'] ?? 0}'),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInfoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _darkDeepTeal,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _lightOffWhite.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _primaryAqua,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildHealthConcernsList() {
    final concerns = <Map<String, dynamic>>[];

    if (_emergencyCases > 0) {
      concerns.add({
        'title': 'Critical Cases Requiring Immediate Attention',
        'count': _emergencyCases,
        'color': _emergencyRed,
        'icon': Icons.warning_amber,
      });
    }

    if (_communicableDiseases > _totalCheckups * 0.1) {
      concerns.add({
        'title': 'High Communicable Disease Cases',
        'count': _communicableDiseases,
        'color': _warningOrange,
        'icon': Icons.health_and_safety,
      });
    }

    if (_prenatalCases > 0) {
      concerns.add({
        'title': 'Active Maternal Health Programs',
        'count': _prenatalCases,
        'color': _primaryAqua,
        'icon': Icons.pregnant_woman,
      });
    }

    if (_nonCommunicableDiseases > 0) {
      concerns.add({
        'title': 'Chronic Disease Management Cases',
        'count': _nonCommunicableDiseases,
        'color': _successGreen,
        'icon': Icons.favorite,
      });
    }

    if (concerns.isEmpty) {
      concerns.add({
        'title': 'Community Health Status: Stable',
        'count': 0,
        'color': _successGreen,
        'icon': Icons.check_circle,
      });
    }

    return Column(
      children: concerns
          .map(
            (concern) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _lightOffWhite.withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: concern['color'].withOpacity(0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(concern['icon'], color: Colors.white, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          concern['title'],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${concern['count']} cases identified',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
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
                      color: concern['color'].withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      concern['count'].toString(),
                      style: TextStyle(
                        color: concern['color'],
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Generate & Save Summary Report'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryAqua,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _saveSummaryToFirebase,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh All Data'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _loadAllData,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.add_circle),
            label: const Text('Seed 100 Sample Records'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _warningOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _seedBarangayData,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
