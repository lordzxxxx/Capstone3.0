import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:community_charts_flutter/community_charts_flutter.dart'
    as charts;
import 'package:mycapstone_project/app/shared/widgets/mobile_pagination_controls.dart';
import 'package:mycapstone_project/app/features/surveillance/mortality/mortality_database_helper.dart';
import 'package:mycapstone_project/app/features/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/app/features/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/shared/current_table_record_utils.dart';
import 'package:mycapstone_project/app/shared/widgets/ocr_record_action.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';
import 'package:mycapstone_project/app/shared/widgets/health_record_card.dart';
import 'package:mycapstone_project/app/shared/widgets/app_metric_card.dart';
import 'package:mycapstone_project/app/shared/widgets/mobile_compact_controls.dart';
import 'package:mycapstone_project/app/shared/widgets/mobile_record_action_sheet.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _secondaryIceBlue = AppDesign.blueSoft;
const Color _darkDeepTeal = AppDesign.page;
const Color _mutedCoolGray = AppDesign.muted;
const Color _lightOffWhite = AppDesign.ink;

class MortalityPage extends StatefulWidget {
  const MortalityPage({super.key});

  @override
  State<MortalityPage> createState() => _MortalityPageState();
}

class _MortalityPageState extends State<MortalityPage>
    with WidgetsBindingObserver {
  // Database helper
  final _mortalityHelper = MortalityDatabaseHelper.instance;
  final PatientCenteredHistoryService _patientHistoryService =
      PatientCenteredHistoryService();

  // Periodic refresh timer
  Timer? _refreshTimer;
  DateTime _lastUpdated = DateTime.now();
  bool _isRefreshing = false;

  // Metrics
  int _totalDeaths = 0;
  String _leadingCause = '';
  int _elderlyDeaths = 0;
  double _verificationRate = 0.0;
  bool _isLoadingMetrics = false;
  bool _isDataLoaded = false;

  // Search & Filter
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'All';
  static const int _defaultRowsPerPage = 10;
  int _currentPage = 1;
  int _rowsPerPage = _defaultRowsPerPage;

  // Data
  List<Map<String, dynamic>> _mortalityRecords = [];
  List<Map<String, dynamic>> _filteredRecords = [];
  List<MonthlyTrend> _monthlyTrends = [];
  List<CauseData> _causeData = [];
  List<AgeDistribution> _ageDistributions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Load data asynchronously to avoid blocking UI
    Future.microtask(() => _loadData());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Real-time updates disabled
  }

  Future<void> _loadData() async {
    if (_isRefreshing) return; // Prevent multiple simultaneous refreshes

    _isRefreshing = true;
    if (!_isLoadingMetrics) {
      setState(() => _isLoadingMetrics = true);
    }

    try {
      // Load mortality records from database
      final recordsList = await _mortalityHelper.getAllRecords();

      // Calculate metrics from records
      final totalDeaths = recordsList.length;
      final elderlyCount = recordsList
          .where((r) => (int.tryParse(r['age'].toString()) ?? 0) >= 60)
          .length;
      final verifiedCount = recordsList
          .where((r) => r['verification'] == 'Verified')
          .length;
      final verificationPercent = totalDeaths > 0
          ? (verifiedCount / totalDeaths) * 100
          : 0.0;

      // Find leading cause
      final leadingCause = await _mortalityHelper.getLeadingCause();

      // Generate trends from records
      final trends = _generateMonthlyTrends(recordsList);
      final causes = _generateCauseData(recordsList);
      final ages = _generateAgeDistribution(recordsList);
      final currentRecords = _collapseCurrentRecords(recordsList);

      if (mounted) {
        setState(() {
          _mortalityRecords = recordsList;
          _filteredRecords = currentRecords;
          _totalDeaths = totalDeaths;
          _leadingCause = leadingCause;
          _elderlyDeaths = elderlyCount;
          _verificationRate = verificationPercent;
          _monthlyTrends = trends;
          _causeData = causes;
          _ageDistributions = ages;
          _isLoadingMetrics = false;
          _isDataLoaded = true;
          _lastUpdated = DateTime.now();
        });
      }
    } catch (e) {
      print('Error loading mortality data: $e');
      if (mounted) {
        setState(() => _isLoadingMetrics = false);
      }
    } finally {
      _isRefreshing = false;
    }
  }

  List<MonthlyTrend> _generateMonthlyTrends(
    List<Map<String, dynamic>> records,
  ) {
    Map<String, int> monthCounts = {
      'Aug': 0,
      'Sep': 0,
      'Oct': 0,
      'Nov': 0,
      'Dec': 0,
      'Jan': 0,
    };

    for (var record in records) {
      final month = record['month'] ?? '';
      if (monthCounts.containsKey(month)) {
        monthCounts[month] = monthCounts[month]! + 1;
      }
    }

    return [
      MonthlyTrend('Aug', monthCounts['Aug']!),
      MonthlyTrend('Sep', monthCounts['Sep']!),
      MonthlyTrend('Oct', monthCounts['Oct']!),
      MonthlyTrend('Nov', monthCounts['Nov']!),
      MonthlyTrend('Dec', monthCounts['Dec']!),
      MonthlyTrend('Jan', monthCounts['Jan']!),
    ];
  }

  List<CauseData> _generateCauseData(List<Map<String, dynamic>> records) {
    Map<String, int> causeCounts = {};

    for (var record in records) {
      final cause = record['causeOfDeath'] ?? 'Unknown';
      causeCounts[cause] = (causeCounts[cause] ?? 0) + 1;
    }

    final total = records.isEmpty ? 1 : records.length;
    final sorted = causeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Limit to top 5 causes, group rest as "Other"
    List<CauseData> result = [];
    int otherCount = 0;

    for (int i = 0; i < sorted.length; i++) {
      if (i < 5) {
        result.add(
          CauseData(
            sorted[i].key,
            sorted[i].value,
            (sorted[i].value / total) * 100,
          ),
        );
      } else {
        otherCount += sorted[i].value;
      }
    }

    if (otherCount > 0) {
      result.add(CauseData('Other', otherCount, (otherCount / total) * 100));
    }

    return result;
  }

  List<AgeDistribution> _generateAgeDistribution(
    List<Map<String, dynamic>> records,
  ) {
    Map<String, int> ageRangeCounts = {
      '0-18': 0,
      '19-40': 0,
      '41-60': 0,
      '61-80': 0,
      '81+': 0,
    };

    for (var record in records) {
      try {
        final age = int.parse(record['age'].toString());
        String range;
        if (age <= 18) {
          range = '0-18';
        } else if (age <= 40)
          range = '19-40';
        else if (age <= 60)
          range = '41-60';
        else if (age <= 80)
          range = '61-80';
        else
          range = '81+';

        ageRangeCounts[range] = ageRangeCounts[range]! + 1;
      } catch (e) {
        // Skip invalid age values
      }
    }

    final total = records.isEmpty ? 1 : records.length;

    return [
      AgeDistribution(
        '0-18',
        ageRangeCounts['0-18']!,
        (ageRangeCounts['0-18']! / total) * 100,
      ),
      AgeDistribution(
        '19-40',
        ageRangeCounts['19-40']!,
        (ageRangeCounts['19-40']! / total) * 100,
      ),
      AgeDistribution(
        '41-60',
        ageRangeCounts['41-60']!,
        (ageRangeCounts['41-60']! / total) * 100,
      ),
      AgeDistribution(
        '61-80',
        ageRangeCounts['61-80']!,
        (ageRangeCounts['61-80']! / total) * 100,
      ),
      AgeDistribution(
        '81+',
        ageRangeCounts['81+']!,
        (ageRangeCounts['81+']! / total) * 100,
      ),
    ];
  }

  List<Map<String, dynamic>> _collapseCurrentRecords(
    List<Map<String, dynamic>> records,
  ) {
    return CurrentTableRecordUtils.collapseToLatestPerEntity(
      records,
      idKeys: const ['linkedPatientId', 'patientId'],
      nameKeys: const ['name', 'patientName', 'patient'],
      dateKeys: const ['dateReported', 'date', 'createdAt', 'timestamp'],
    );
  }

  void _filterRecords(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      var filtered = _mortalityRecords;
      if (_searchQuery.isNotEmpty) {
        filtered = filtered.where((record) {
          return record['name'].toString().toLowerCase().contains(
                _searchQuery,
              ) ||
              record['causeOfDeath'].toString().toLowerCase().contains(
                _searchQuery,
              ) ||
              record['place'].toString().toLowerCase().contains(_searchQuery) ||
              record['verification'].toString().toLowerCase().contains(
                _searchQuery,
              );
        }).toList();
      }
      if (_statusFilter != 'All') {
        filtered = filtered.where((record) {
          final verification =
              (record['verification'] ?? record['status'] ?? '')
                  .toString()
                  .toLowerCase();
          final filter = _statusFilter.toLowerCase();
          return verification == filter || verification.contains(filter);
        }).toList();
      }
      _filteredRecords = _collapseCurrentRecords(filtered);
      _resetPagination();
    });
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

  void _resetPagination() {
    _currentPage = 1;
  }

  Future<void> _refreshData() async {
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data refreshed successfully'),
          duration: Duration(milliseconds: 800),
        ),
      );
    }
  }

  Future<void> _seedSampleData() async {
    // Show confirmation dialog
    if (!mounted) return;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Seed Sample Data'),
            content: const Text(
              'This will add 100 sample mortality records to the database. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Seed Data',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            const Expanded(child: Text('Seeding 100 sample records...')),
          ],
        ),
      ),
    );

    try {
      // Call seed function
      await _mortalityHelper.seedSample100Records();

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      // Reload data
      await _loadData();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully seeded 100 sample records!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.pop(context);

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('âŒ Error seeding data: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      print('Error seeding data: $e');
    }
  }

  Color _getVerificationColor(String verification) {
    return AppDesign.statusColors(verification).foreground;
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkDeepTeal,
      appBar: AppBar(
        title: const Text(
          'Mortality List',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppDesign.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: _buildSearchBar(),
              ),

              const SizedBox(height: 20),

              // Mortality Records Table
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildRecordCards(),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      floatingActionButton: RecordCreationFabGroup(
        moduleLabel: 'Mortality',
        manualLabel: 'New Record',
        onManualCreate: _showAddRecordDialog,
        onOcrReady: (extraction) async {
          _showAddRecordDialog(patientSeed: extraction.toFormSeed());
        },
      ),
    );
  }

  // Overview Dashboard
  Widget _buildOverviewDashboard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _darkDeepTeal,
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
            Text(
              'Mortality Overview',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _lightOffWhite,
              ),
            ),
            const SizedBox(height: 20),
            if (_isLoadingMetrics)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: _primaryAqua),
                ),
              )
            else
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Total Deaths',
                          value: _totalDeaths.toString(),
                          icon: Icons.assignment,
                          color: _primaryAqua,
                          textColor: _lightOffWhite,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Elderly Deaths',
                          value: _elderlyDeaths.toString(),
                          icon: Icons.elderly,
                          color: _primaryAqua,
                          textColor: _lightOffWhite,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Leading Cause',
                          value: _leadingCause,
                          icon: Icons.warning,
                          color: _primaryAqua,
                          textColor: _lightOffWhite,
                          isSmallText: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Verification Rate',
                          value: '${_verificationRate.toStringAsFixed(1)}%',
                          icon: Icons.verified,
                          color: _primaryAqua,
                          textColor: _lightOffWhite,
                        ),
                      ),
                    ],
                  ),
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
    bool isSmallText = false,
  }) {
    return AppMetricCard(label: title, value: value, icon: icon);
  }

  // Graphs Section
  Widget _buildGraphsSection() {
    if (!_isDataLoaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: CircularProgressIndicator(color: _primaryAqua),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Statistical Analysis',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),

        // Monthly Trends (Line Graph)
        if (_monthlyTrends.isNotEmpty)
          _buildGraphCard(
            title: 'Monthly Trends',
            icon: Icons.show_chart,
            showLastUpdated: true,
            child: SizedBox(
              height: 250,
              child: charts.LineChart(
                [
                  charts.Series<MonthlyTrend, int>(
                    id: 'Deaths',
                    colorFn: (_, _) => charts.MaterialPalette.blue.shadeDefault,
                    domainFn: (MonthlyTrend trend, int? index) => index ?? 0,
                    measureFn: (MonthlyTrend trend, _) => trend.deaths,
                    data: _monthlyTrends,
                  ),
                ],
                animate: true,
                defaultRenderer: charts.LineRendererConfig(
                  includeArea: true,
                  stacked: false,
                ),
                domainAxis: charts.NumericAxisSpec(
                  renderSpec: charts.GridlineRendererSpec(
                    labelStyle: charts.TextStyleSpec(
                      color: charts.Color.white,
                      fontSize: 11,
                    ),
                  ),
                ),
                primaryMeasureAxis: charts.NumericAxisSpec(
                  tickFormatterSpec: charts.BasicNumericTickFormatterSpec(
                    (num? value) => value?.toString() ?? '',
                  ),
                  renderSpec: charts.GridlineRendererSpec(
                    labelStyle: charts.TextStyleSpec(
                      color: charts.Color.white,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_causeData.isNotEmpty && _ageDistributions.isNotEmpty)
          const SizedBox(height: 16),

        if (_causeData.isNotEmpty && _ageDistributions.isNotEmpty)
          Column(
            children: [
              // Leading Causes (Pie Chart)
              _buildGraphCard(
                title: 'Leading Causes',
                icon: Icons.pie_chart,
                showLastUpdated: true,
                child: Column(
                  children: [
                    SizedBox(
                      height: 200,
                      child: _causeData.isEmpty
                          ? Center(
                              child: Text(
                                'No data available',
                                style: TextStyle(
                                  color: _lightOffWhite.withValues(alpha: 0.6),
                                ),
                              ),
                            )
                          : charts.PieChart<String>(
                              [
                                charts.Series<CauseData, String>(
                                  id: 'Causes',
                                  domainFn: (CauseData data, _) => data.cause,
                                  measureFn: (CauseData data, _) => data.count,
                                  data: _causeData,
                                  labelAccessorFn: (CauseData data, _) =>
                                      '${data.percentage.toStringAsFixed(1)}%',
                                  colorFn: (CauseData data, _) =>
                                      charts.MaterialPalette.teal.shadeDefault,
                                ),
                              ],
                              animate: true,
                              animationDuration: const Duration(
                                milliseconds: 800,
                              ),
                              defaultRenderer: charts.ArcRendererConfig<String>(
                                arcWidth: 60,
                                arcRendererDecorators: [
                                  charts.ArcLabelDecorator<String>(
                                    labelPosition: charts.ArcLabelPosition.auto,
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _lightOffWhite.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Total: ${_causeData.fold<int>(0, (sum, item) => sum + item.count)} cases',
                        style: TextStyle(
                          fontSize: 12,
                          color: _primaryAqua,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Age Distribution (Bar Chart)
              _buildGraphCard(
                title: 'Age Distribution',
                icon: Icons.bar_chart,
                showLastUpdated: true,
                child: Column(
                  children: [
                    SizedBox(
                      height: 200,
                      child: _ageDistributions.isEmpty
                          ? Center(
                              child: Text(
                                'No data available',
                                style: TextStyle(
                                  color: _lightOffWhite.withValues(alpha: 0.6),
                                ),
                              ),
                            )
                          : charts.BarChart(
                              [
                                charts.Series<AgeDistribution, String>(
                                  id: 'Ages',
                                  colorFn: (AgeDistribution data, _) {
                                    // Color gradient based on count
                                    if (data.count > 3) {
                                      return charts
                                          .MaterialPalette
                                          .green
                                          .shadeDefault;
                                    } else if (data.count > 1) {
                                      return charts
                                          .MaterialPalette
                                          .yellow
                                          .shadeDefault;
                                    } else {
                                      return charts
                                          .MaterialPalette
                                          .gray
                                          .shadeDefault;
                                    }
                                  },
                                  domainFn: (AgeDistribution dist, _) =>
                                      dist.ageRange,
                                  measureFn: (AgeDistribution dist, _) =>
                                      dist.count,
                                  data: _ageDistributions,
                                ),
                              ],
                              animate: true,
                              animationDuration: const Duration(
                                milliseconds: 800,
                              ),
                              vertical: true,
                              primaryMeasureAxis: charts.NumericAxisSpec(
                                tickFormatterSpec:
                                    charts.BasicNumericTickFormatterSpec(
                                      (num? value) =>
                                          value?.toInt().toString() ?? '',
                                    ),
                                renderSpec: charts.GridlineRendererSpec(
                                  labelStyle: charts.TextStyleSpec(
                                    color: charts.Color.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              domainAxis: charts.OrdinalAxisSpec(
                                renderSpec: charts.SmallTickRendererSpec(
                                  labelStyle: charts.TextStyleSpec(
                                    color: charts.Color.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _lightOffWhite.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Total: ${_ageDistributions.fold<int>(0, (sum, item) => sum + item.count)} records',
                        style: TextStyle(
                          fontSize: 12,
                          color: _primaryAqua,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  String _getLastUpdatedText() {
    final now = DateTime.now();
    final difference = now.difference(_lastUpdated);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  Widget _buildGraphCard({
    required String title,
    required IconData icon,
    required Widget child,
    bool showLastUpdated = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (showLastUpdated)
                Tooltip(
                  message: 'Last updated: ${_lastUpdated.toString()}',
                  child: Text(
                    _getLastUpdatedText(),
                    style: TextStyle(
                      fontSize: 12,
                      color: _primaryAqua,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // Tables Section
  Widget _buildTablesSection() {
    if (!_isDataLoaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: CircularProgressIndicator(color: _primaryAqua),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Detailed Statistics',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),

        // Cause of Death Table
        _buildCauseTable(),
        const SizedBox(height: 16),

        // Age Distribution Table
        _buildAgeTable(),
      ],
    );
  }

  Widget _buildCauseTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.table_chart, color: _primaryAqua, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Cause of Death Breakdown',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Tooltip(
                  message: 'Last updated: ${_lastUpdated.toString()}',
                  child: Text(
                    _getLastUpdatedText(),
                    style: TextStyle(
                      fontSize: 11,
                      color: _primaryAqua,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                _primaryAqua.withValues(alpha: 0.1),
              ),
              columns: [
                DataColumn(
                  label: Text(
                    'Cause of Death',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Percentage',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Progress',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Death Count',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
              rows: _causeData.map((cause) {
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        cause.cause,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${cause.percentage.toStringAsFixed(1)}%',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 100,
                        child: LinearProgressIndicator(
                          value: cause.percentage / 100,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _primaryAqua,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        cause.count.toString(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgeTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.table_rows, color: _primaryAqua, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Age Distribution',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Tooltip(
                  message: 'Last updated: ${_lastUpdated.toString()}',
                  child: Text(
                    _getLastUpdatedText(),
                    style: TextStyle(
                      fontSize: 11,
                      color: _primaryAqua,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                _primaryAqua.withValues(alpha: 0.1),
              ),
              columns: [
                DataColumn(
                  label: Text(
                    'Age Range',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Death Count',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Percentage',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
              rows: _ageDistributions.map((age) {
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        age.ageRange,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    DataCell(
                      Text(
                        age.count.toString(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${age.percentage.toStringAsFixed(1)}%',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // Search Bar with Burger Menu and Status Filter
  Widget _buildSearchBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mortality Records',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: _lightOffWhite,
          ),
        ),
        const SizedBox(height: 12),
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
              child: PopupMenuButton<String>(
                color: _darkDeepTeal,
                icon: Icon(Icons.menu, color: _lightOffWhite, size: 24),
                onSelected: (value) {
                  switch (value) {
                    case 'all':
                      setState(() {
                        _statusFilter = 'All';
                        _searchController.clear();
                        _searchQuery = '';
                        _filterRecords('');
                      });
                      break;
                    case 'clear':
                      setState(() {
                        _statusFilter = 'All';
                        _searchController.clear();
                        _searchQuery = '';
                        _filterRecords('');
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
              child: MobileSearchField(
                controller: _searchController,
                hintText:
                    'Search by name, cause, place, or verification status...',
                onChanged: _filterRecords,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Verification Filter Dropdown
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
            value: _statusFilter,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            dropdownColor: Colors.white,
            iconEnabledColor: AppDesign.navy,
            items:
                [
                  'All',
                  'Verified',
                  'Pending certification',
                  'Under Review',
                  'Certified',
                ].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(
                      value,
                      style: TextStyle(
                        color: AppDesign.navy,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  );
                }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _statusFilter = newValue;
                  _filterRecords(_searchQuery);
                });
              }
            },
          ),
        ),
      ],
    );
  }

  // Records Table
  Widget _buildRecordCards() {
    if (_filteredRecords.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: _mutedCoolGray.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isEmpty
                    ? 'No records found'
                    : 'No results for "$_searchQuery"',
                style: TextStyle(fontSize: 16, color: _mutedCoolGray),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        ..._pagedFilteredRecords.map((record) {
          final name = record['name']?.toString().trim();
          final identifier = record['patientId']?.toString().trim();
          final patientLabel = name?.isNotEmpty == true
              ? name!
              : identifier?.isNotEmpty == true
              ? identifier!
              : 'Unknown record';
          final verification =
              record['verification']?.toString() ?? 'Pending certification';
          return HealthRecordCard(
            recordLabel: 'Mortality record',
            patientName: patientLabel,
            location:
                record['barangay']?.toString() ??
                record['address']?.toString() ??
                'Location not recorded',
            accentColor: AppDesign.checkUp,
            status: verification,
            onTap: () => _showMortalityHistory(context, record),
            onLongPress: () => _showRecordActionModal(context, record),
            onAction: () => _showRecordActionModal(context, record),
            metadata: [
              RecordMetadata(
                label: 'Age',
                value: record['age']?.toString() ?? 'Not recorded',
                icon: Icons.cake_outlined,
              ),
              RecordMetadata(
                label: 'Date of death',
                value: HealthRecordDate.format(
                  record['date'] ?? record['dateReported'],
                ),
                icon: Icons.event_outlined,
              ),
              RecordMetadata(
                label: 'Recorded cause',
                value:
                    record['causeOfDeath']?.toString().trim().isNotEmpty == true
                    ? record['causeOfDeath'].toString()
                    : 'No cause recorded',
                icon: Icons.description_outlined,
                emphasize: true,
              ),
              RecordMetadata(
                label: 'Place of death',
                value: record['place']?.toString() ?? 'Not recorded',
                icon: Icons.place_outlined,
              ),
              RecordMetadata(
                label: 'Classification',
                value: record['classification']?.toString() ?? 'Not recorded',
                icon: Icons.category_outlined,
              ),
              RecordMetadata(
                label: 'Recorded by',
                value:
                    record['recordedBy']?.toString() ??
                    record['reportedBy']?.toString() ??
                    'Not recorded',
                icon: Icons.badge_outlined,
              ),
            ],
          );
        }),
        if (false)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _primaryAqua.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  _primaryAqua.withValues(alpha: 0.12),
                ),
                dataRowColor: WidgetStateProperty.all(Colors.transparent),
                columns: const [
                  DataColumn(
                    label: Text(
                      'Name',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _lightOffWhite,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Age / Gender',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _lightOffWhite,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Cause',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _lightOffWhite,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Place',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _lightOffWhite,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Date',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _lightOffWhite,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Verification',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _lightOffWhite,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Actions',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _lightOffWhite,
                      ),
                    ),
                  ),
                ],
                rows: _pagedFilteredRecords.map((record) {
                  final nameValue = record['name']?.toString().trim() ?? '';
                  final name = nameValue.isEmpty ? 'Unknown' : nameValue;
                  final age = record['age']?.toString() ?? 'N/A';
                  final gender = record['gender']?.toString() ?? 'N/A';
                  final causeValue =
                      record['causeOfDeath']?.toString().trim() ?? '';
                  final cause = causeValue.isEmpty
                      ? 'No cause recorded'
                      : causeValue;
                  final placeValue = record['place']?.toString().trim() ?? '';
                  final place = placeValue.isEmpty
                      ? 'No place recorded'
                      : placeValue;
                  final date = _formatDate(
                    (record['date'] ?? record['dateReported'] ?? '').toString(),
                  );
                  final verification =
                      record['verification']?.toString() ?? 'Pending';
                  final verificationColor = _getVerificationColor(verification);

                  return DataRow(
                    onLongPress: () => _showRecordActionModal(context, record),
                    cells: [
                      DataCell(
                        Text(
                          name,
                          style: const TextStyle(color: _lightOffWhite),
                        ),
                        onTap: () => _showMortalityHistory(context, record),
                      ),
                      DataCell(
                        Text(
                          '$age / $gender',
                          style: const TextStyle(color: _lightOffWhite),
                        ),
                        onTap: () => _showMortalityHistory(context, record),
                      ),
                      DataCell(
                        SizedBox(
                          width: 210,
                          child: Text(
                            cause,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _lightOffWhite),
                          ),
                        ),
                        onTap: () => _showMortalityHistory(context, record),
                      ),
                      DataCell(
                        SizedBox(
                          width: 180,
                          child: Text(
                            place,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _lightOffWhite),
                          ),
                        ),
                        onTap: () => _showMortalityHistory(context, record),
                      ),
                      DataCell(
                        Text(
                          date,
                          style: const TextStyle(color: _lightOffWhite),
                        ),
                        onTap: () => _showMortalityHistory(context, record),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: verificationColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: verificationColor.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            verification,
                            style: TextStyle(
                              color: verificationColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.history,
                                color: _primaryAqua,
                                size: 20,
                              ),
                              tooltip: 'History',
                              onPressed: () =>
                                  _showMortalityHistory(context, record),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.edit,
                                color: Colors.orange,
                                size: 20,
                              ),
                              tooltip: 'Edit',
                              onPressed: () => _editRecord(record),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.verified,
                                color: Color(0xFF4CAF50),
                                size: 20,
                              ),
                              tooltip: 'Verify',
                              onPressed: () => _verifyRecord(record),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.print,
                                color: Color(0xFF607D8B),
                                size: 20,
                              ),
                              tooltip: 'Print',
                              onPressed: () => _printRecord(record),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        const SizedBox(height: 12),
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

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.month}/${date.day}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  // Action Methods
  List<Map<String, dynamic>> _getMortalityHistory(Map<String, dynamic> record) {
    return PatientHistoryDialogs.collectHistory(
      seedRecord: record,
      records: _mortalityRecords,
      idKeys: const ['linkedPatientId', 'patientId', 'id'],
      nameKeys: const ['name', 'patientName', 'patient'],
      sortDateKeys: const ['dateReported', 'date'],
    );
  }

  Map<String, dynamic> _buildPatientHistorySeed(Map<String, dynamic> record) {
    final patientName =
        (record['patientName'] ?? record['name'] ?? record['patient'] ?? '')
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

  void _showMortalityHistory(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final history = _getMortalityHistory(record);
    PatientHistoryDialogs.showModuleHistoryDialog(
      context: context,
      moduleTitle: 'Mortality',
      seedRecord: record,
      history: history,
      description:
          'Review existing mortality reports for this patient before saving another death-related record.',
      addButtonLabel: 'Add Another Mortality Record',
      titleBuilder: (entry) =>
          (entry['causeOfDeath'] ?? 'Mortality report').toString(),
      subtitleBuilder: (entry) =>
          (entry['verification'] ?? 'Pending verification').toString(),
      metaBuilder: (entry) =>
          'Age: ${(entry['age'] ?? 'N/A').toString()} | Place: ${(entry['place'] ?? 'N/A').toString()}',
      dateKeys: const ['dateReported', 'date'],
      secondaryActionLabel: 'Medical History',
      onSecondaryAction: () => _showPatientMedicalHistory(context, record),
      onAddAnother: () => _showAddRecordDialog(
        patientSeed: history.isNotEmpty ? history.first : record,
      ),
      onOpenRecord: (entry) => _viewRecordDetails(entry),
    );
  }

  void _showRecordActionModal(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final rawName = record['name']?.toString().trim() ?? '';
    final patientName = rawName.isEmpty ? 'Record Details' : rawName;

    MobileRecordActionSheet.show(
      context: context,
      title: patientName,
      headerIcon: Icons.event_busy,
      actions: [
        MobileRecordAction(
          label: 'View Record Details',
          icon: Icons.visibility_outlined,
          tone: MobileRecordActionTone.primary,
          onPressed: () => _viewRecordDetails(record),
        ),
        MobileRecordAction(
          label: 'View Patient History',
          icon: Icons.history_rounded,
          onPressed: () => _showMortalityHistory(context, record),
        ),
        MobileRecordAction(
          label: 'Edit Record',
          icon: Icons.edit_outlined,
          onPressed: () => _editRecord(record),
        ),
        MobileRecordAction(
          label: 'Verify Record',
          icon: Icons.verified_outlined,
          tone: MobileRecordActionTone.success,
          onPressed: () => _verifyRecord(record),
        ),
        MobileRecordAction(
          label: 'Print Record',
          icon: Icons.print_outlined,
          onPressed: () => _printRecord(record),
        ),
      ],
    );
  }

  void _showAddRecordDialog({Map<String, dynamic>? patientSeed}) {
    final nameController = TextEditingController(
      text:
          (patientSeed?['name'] ??
                  patientSeed?['patientName'] ??
                  patientSeed?['fullName'] ??
                  patientSeed?['patient'] ??
                  '')
              .toString(),
    );
    final ageController = TextEditingController(
      text: (patientSeed?['age'] ?? '').toString(),
    );
    final causeController = TextEditingController(
      text:
          (patientSeed?['cause'] ??
                  patientSeed?['causeOfDeath'] ??
                  patientSeed?['diagnosis'] ??
                  patientSeed?['disease'] ??
                  '')
              .toString(),
    );
    final placeController = TextEditingController(
      text:
          (patientSeed?['place'] ??
                  patientSeed?['placeOfDeath'] ??
                  patientSeed?['address'] ??
                  '')
              .toString(),
    );
    final reportedByController = TextEditingController(
      text: (patientSeed?['reportedBy'] ?? '').toString(),
    );
    final rawGender = (patientSeed?['gender'] ?? patientSeed?['sex'] ?? 'Male')
        .toString();
    String selectedGender =
        (rawGender.toLowerCase() == 'female' || rawGender.toLowerCase() == 'f')
        ? 'Female'
        : 'Male';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final labelStyle = TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: _lightOffWhite,
          );

          InputDecoration buildDialogInputDecoration({
            required String hint,
            required IconData icon,
          }) {
            return InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: _lightOffWhite.withValues(alpha: 0.4),
                fontSize: 14,
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
                vertical: 12,
                horizontal: 16,
              ),
            );
          }

          return AlertDialog(
            backgroundColor: _darkDeepTeal,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: _lightOffWhite.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            title: Row(
              children: [
                const Icon(Icons.add_circle, color: _lightOffWhite, size: 28),
                const SizedBox(width: 12),
                Text(
                  patientSeed == null
                      ? 'New Mortality Record'
                      : 'Add Another Mortality Record',
                  style: const TextStyle(
                    color: _lightOffWhite,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Theme(
                data: Theme.of(context).copyWith(canvasColor: _darkDeepTeal),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('Patient Name *', style: labelStyle),
                    ),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: _lightOffWhite),
                      cursorColor: _primaryAqua,
                      decoration: buildDialogInputDecoration(
                        hint: 'Enter full name',
                        icon: Icons.person,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Age *', style: labelStyle),
                              const SizedBox(height: 6),
                              TextField(
                                controller: ageController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: _lightOffWhite),
                                cursorColor: _primaryAqua,
                                decoration: buildDialogInputDecoration(
                                  hint: 'e.g., 65',
                                  icon: Icons.calendar_today,
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
                              Text('Gender *', style: labelStyle),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: selectedGender,
                                isExpanded: true,
                                dropdownColor: _darkDeepTeal,
                                iconEnabledColor: _lightOffWhite,
                                style: const TextStyle(
                                  color: _lightOffWhite,
                                  fontWeight: FontWeight.w600,
                                ),
                                onChanged: (newValue) {
                                  setState(() {
                                    selectedGender = newValue ?? 'Male';
                                  });
                                },
                                items: ['Male', 'Female', 'Other']
                                    .map(
                                      (gender) => DropdownMenuItem<String>(
                                        value: gender,
                                        child: Text(
                                          gender,
                                          style: const TextStyle(
                                            color: _lightOffWhite,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                decoration:
                                    buildDialogInputDecoration(
                                      hint: 'Select gender',
                                      icon: Icons.wc,
                                    ).copyWith(
                                      prefixIcon: null,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('Cause of Death *', style: labelStyle),
                    ),
                    TextField(
                      controller: causeController,
                      maxLines: 2,
                      style: const TextStyle(color: _lightOffWhite),
                      cursorColor: _primaryAqua,
                      decoration: buildDialogInputDecoration(
                        hint: 'e.g., Myocardial Infarction, Stroke, Cancer',
                        icon: Icons.warning,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('Place of Death', style: labelStyle),
                    ),
                    TextField(
                      controller: placeController,
                      style: const TextStyle(color: _lightOffWhite),
                      cursorColor: _primaryAqua,
                      decoration: buildDialogInputDecoration(
                        hint: 'e.g., City General Hospital, Home, Clinic',
                        icon: Icons.location_on,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('Reported By', style: labelStyle),
                    ),
                    TextField(
                      controller: reportedByController,
                      style: const TextStyle(color: _lightOffWhite),
                      cursorColor: _primaryAqua,
                      decoration: buildDialogInputDecoration(
                        hint: 'e.g., Dr. John Smith',
                        icon: Icons.person_outline,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '* Required fields',
                      style: TextStyle(
                        fontSize: 11,
                        color: _lightOffWhite.withValues(alpha: 0.72),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: _lightOffWhite),
                child: const Text('Cancel', style: TextStyle(fontSize: 14)),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final saved = await _addNewRecord(
                    nameController.text,
                    ageController.text,
                    selectedGender,
                    causeController.text,
                    placeController.text,
                    reportedByController.text,
                  );
                  if (saved && mounted) {
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.save, size: 18, color: _lightOffWhite),
                label: const Text(
                  'Save Record',
                  style: TextStyle(fontSize: 14, color: _lightOffWhite),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryAqua,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _addNewRecord(
    String name,
    String age,
    String gender,
    String cause,
    String place,
    String reportedBy,
  ) async {
    if (name.isEmpty || age.isEmpty || cause.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill in all required fields (Name, Age, Cause of Death)',
          ),
          backgroundColor: Color(0xFFD84315),
        ),
      );
      return false;
    }

    try {
      final parsedAge = int.parse(age);
      final newRecord = {
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'name': name,
        'date': DateTime.now().toString().split(' ')[0],
        'month': _getMonthName(DateTime.now().month),
        'age': parsedAge.toString(),
        'ageRange': _getAgeRange(parsedAge),
        'gender': gender,
        'causeOfDeath': cause,
        'place': place,
        'reportedBy': reportedBy,
        'verification': 'Pending',
        'dateReported': DateTime.now().toIso8601String(),
      };

      // Insert record into database
      await _mortalityHelper.insertRecord(newRecord);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Record added successfully'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );

      // Trigger data reload to update metrics and charts
      _loadData();
      return true;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding record: $e'),
          backgroundColor: Color(0xFFD84315),
        ),
      );
      return false;
    }
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  String _getAgeRange(int age) {
    if (age <= 18) return '0-18';
    if (age <= 40) return '19-40';
    if (age <= 60) return '41-60';
    if (age <= 80) return '61-80';
    return '81+';
  }

  void _viewRecordDetails(Map<String, dynamic> record) {
    final nameValue = record['name']?.toString().trim() ?? '';
    final name = nameValue.isEmpty ? 'Unknown' : nameValue;

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
            maxHeight: MediaQuery.of(context).size.height * 0.82,
            maxWidth: 520,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _secondaryIceBlue,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                      child: Center(
                        child: Text(
                          _getInitials(name),
                          style: const TextStyle(
                            color: _lightOffWhite,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mortality Record Details',
                            style: TextStyle(
                              color: _lightOffWhite,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            name,
                            style: TextStyle(
                              color: _lightOffWhite.withValues(alpha: 0.8),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close,
                        color: _lightOffWhite.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoSection(
                        title: 'Patient Information',
                        icon: Icons.person,
                        children: [
                          _buildInfoItem('Name', name),
                          _buildInfoItem(
                            'Age',
                            '${record['age']?.toString() ?? 'N/A'} years',
                          ),
                          _buildInfoItem(
                            'Gender',
                            record['gender']?.toString() ?? 'N/A',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildInfoSection(
                        title: 'Record Details',
                        icon: Icons.description_outlined,
                        children: [
                          _buildInfoItem(
                            'Record ID',
                            record['id']?.toString() ?? 'N/A',
                          ),
                          _buildInfoItem(
                            'Date of Death',
                            _formatDate(record['date']?.toString() ?? ''),
                          ),
                          _buildInfoItem(
                            'Cause of Death',
                            record['causeOfDeath']?.toString() ?? 'N/A',
                          ),
                          _buildInfoItem(
                            'Place',
                            record['place']?.toString() ?? 'N/A',
                          ),
                          _buildInfoItem(
                            'Reported By',
                            record['reportedBy']?.toString() ?? 'N/A',
                          ),
                          _buildInfoItem(
                            'Verification Status',
                            record['verification']?.toString() ?? 'N/A',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: _lightOffWhite),
                    label: const Text(
                      'Close',
                      style: TextStyle(
                        color: _lightOffWhite,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: _lightOffWhite.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _buildInfoSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _lightOffWhite.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _lightOffWhite.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _lightOffWhite, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: _lightOffWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Divider(height: 20, color: _lightOffWhite.withValues(alpha: 0.12)),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _lightOffWhite.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
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

  void _editRecord(Map<String, dynamic> record) {
    final nameController = TextEditingController(text: record['name']);
    final causeController = TextEditingController(text: record['causeOfDeath']);
    final placeController = TextEditingController(text: record['place']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Edit Record - ${record['name']}',
          style: TextStyle(color: _darkDeepTeal, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Patient Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: causeController,
                decoration: InputDecoration(
                  labelText: 'Cause of Death',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: placeController,
                decoration: InputDecoration(
                  labelText: 'Place of Death',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: _mutedCoolGray)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                record['name'] = nameController.text;
                record['causeOfDeath'] = causeController.text;
                record['place'] = placeController.text;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Record updated successfully'),
                  backgroundColor: Color(0xFF4CAF50),
                ),
              );
              _loadData();
            },
            style: ElevatedButton.styleFrom(backgroundColor: _primaryAqua),
            child: const Text(
              'Save Changes',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _verifyRecord(Map<String, dynamic> record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Verify Record',
          style: TextStyle(color: _darkDeepTeal, fontWeight: FontWeight.bold),
        ),
        content: Text('Mark "${record['name']}" record as verified?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: _mutedCoolGray)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                record['verification'] = 'Verified';
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Record verified successfully'),
                  backgroundColor: Color(0xFF4CAF50),
                ),
              );
              _loadData();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
            ),
            child: const Text('Verify', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _printRecord(Map<String, dynamic> record) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Printing death certificate for ${record['name']}'),
        backgroundColor: const Color(0xFF607D8B),
      ),
    );
  }
}

// Data Models for Charts
class MonthlyTrend {
  final String month;
  final int deaths;

  MonthlyTrend(this.month, this.deaths);
}

class CauseData {
  final String cause;
  final int count;
  final double percentage;

  CauseData(this.cause, this.count, this.percentage);
}

class AgeDistribution {
  final String ageRange;
  final int count;
  final double percentage;

  AgeDistribution(this.ageRange, this.count, this.percentage);
}
