import 'package:flutter/material.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart'
    as charts;
import 'package:mycapstone_project/app/features/surveillance/morbidity/morbidity_database_helper.dart';
import 'package:mycapstone_project/app/features/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/shared/current_table_record_utils.dart';
import 'package:mycapstone_project/app/shared/widgets/ocr_record_action.dart';

const Color _primaryAqua = Color(0xFF00A8B5);
const Color _secondaryIceBlue = Color(0xFF1E5A7A);
const Color _darkDeepTeal = Color(0xFF0A1F24);
const Color _mutedCoolGray = Color(0xFF546E7A);
const Color _lightOffWhite = Color(0xFFF5F5F5);

class MorbidityPage extends StatefulWidget {
  final bool? analyticsOnly;
  final bool? listOnly;

  const MorbidityPage({
    super.key,
    this.analyticsOnly = false,
    this.listOnly = false,
  });

  @override
  State<MorbidityPage> createState() => _MorbidityPageState();
}

class _MorbidityPageState extends State<MorbidityPage> {
  // Metrics
  int _totalCases = 0;
  String _mostCommonDisease = '';
  int _activePatients = 0;
  double _recoveryRate = 0.0;
  bool _isLoadingMetrics = false;
  bool _isDataLoaded = false;
  DateTime? _lastUpdated;

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Data
  List<Map<String, dynamic>> _morbidityRecords = [];
  List<Map<String, dynamic>> _filteredRecords = [];
  List<MonthlyTrend> _monthlyTrends = [];
  List<DiseaseData> _diseaseData = [];
  final List<AgeDistribution> _ageDistributions = [];

  // Database helper
  final MorbidityDatabaseHelper _dbHelper = MorbidityDatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    // Load data asynchronously to avoid blocking UI
    Future.microtask(() => _loadData());

    // Start connectivity listener for sync
    _dbHelper.startConnectivityListener();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() => _isLoadingMetrics = true);

    try {
      // Load from local database
      final allRecords = await _dbHelper.getAllRecords();

      // Try to sync from Firebase
      await _dbHelper.syncFromFirebase();

      // Reload after sync
      final updatedRecords = await _dbHelper.getAllRecords();

      // Calculate statistics
      final stats = await _dbHelper.calculateDiseaseStats();

      // Get monthly trends
      final monthlyTrendsData = await _dbHelper.getMonthlyTrends();

      setState(() {
        _morbidityRecords = updatedRecords;
        _filteredRecords = _collapseCurrentRecords(updatedRecords);
        _totalCases = stats['totalRecords'] ?? 0;
        _activePatients = stats['activePatients'] ?? 0;
        _recoveryRate =
            double.tryParse(stats['recoveryRate']?.toString() ?? '0') ?? 0.0;
        _lastUpdated = DateTime.now();

        // Build disease distribution data
        final diseaseStats =
            stats['diseaseStats'] as Map<String, dynamic>? ?? {};
        final total = _totalCases > 0 ? _totalCases : 1;

        _diseaseData = diseaseStats.entries.map((entry) {
          final count = entry.value as int;
          return DiseaseData(entry.key, count, (count / total * 100));
        }).toList();

        // Sort by count descending
        _diseaseData.sort((a, b) => b.count.compareTo(a.count));

        // Set most common disease
        if (_diseaseData.isNotEmpty) {
          _mostCommonDisease = _diseaseData.first.name;
        }

        // Build monthly trends data
        _monthlyTrends = monthlyTrendsData.map((trend) {
          return MonthlyTrend(trend['month'] ?? '', trend['count'] ?? 0);
        }).toList();

        _isDataLoaded = true;
      });
    } catch (e) {
      print('Error loading data: $e');
    } finally {
      setState(() => _isLoadingMetrics = false);
    }
  }

  void _applySearch() {
    setState(() {
      if (_searchQuery.isEmpty) {
        _filteredRecords = _collapseCurrentRecords(_morbidityRecords);
      } else {
        final filtered = _morbidityRecords
            .where(
              (record) =>
                  (record['patientName'] ?? record['patient'] ?? record['name'])
                      .toString()
                      .toLowerCase()
                      .contains(_searchQuery.toLowerCase()) ||
                  record['disease'].toString().toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  ) ||
                  record['id'].toString().contains(_searchQuery),
            )
            .toList();
        _filteredRecords = _collapseCurrentRecords(filtered);
      }
    });
  }

  List<Map<String, dynamic>> _collapseCurrentRecords(
    List<Map<String, dynamic>> records,
  ) {
    return CurrentTableRecordUtils.collapseToLatestPerEntity(
      records,
      idKeys: const ['linkedPatientId', 'patientId'],
      nameKeys: const ['patientName', 'patient', 'name'],
      dateKeys: const ['reportedDate', 'datetime', 'dateReported', 'date'],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkDeepTeal,
      appBar: AppBar(
        backgroundColor: _darkDeepTeal,
        elevation: 0,
        title: Text(
          widget.analyticsOnly == true
              ? 'Morbidity Analytics'
              : widget.listOnly == true
              ? 'Morbidity List'
              : 'Morbidity Records',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: _lightOffWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: _lightOffWhite),
        actions: widget.analyticsOnly == true || widget.listOnly == true
            ? [
                IconButton(
                  onPressed: _loadData,
                  tooltip: 'Refresh analytics',
                  icon: const Icon(Icons.refresh, color: _primaryAqua),
                ),
              ]
            : [
                Tooltip(
                  message: _lastUpdated != null
                      ? 'Last updated: ${_lastUpdated!.hour}:${_lastUpdated!.minute.toString().padLeft(2, '0')}'
                      : 'Updating...',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Center(
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => _loadData(),
                            child: _isLoadingMetrics
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        _primaryAqua,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    Icons.refresh,
                                    color: _primaryAqua,
                                    size: 24,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () async {
                              await _dbHelper.seedData();
                              _loadData();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      '✅ 100 sample records seeded',
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Tooltip(
                              message: 'Seed 100 test records',
                              child: Icon(
                                Icons.grain,
                                color: _primaryAqua,
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
      ),
      floatingActionButton: widget.analyticsOnly == true
          ? null
          : RecordCreationFabGroup(
              moduleLabel: 'Morbidity',
              manualLabel: 'New Record',
              onManualCreate: () => _showNewMorbidityModal(context),
            ),
      body: _isLoadingMetrics
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
                            if (widget.analyticsOnly != true) ...[
                              _buildSearchBar(),
                              const SizedBox(height: 24),
                            ],

                            if (widget.listOnly != true) ...[
                              _buildMetricsCards(),
                              const SizedBox(height: 24),
                              _buildChartssection(),
                              const SizedBox(height: 24),
                            ],

                            if (widget.analyticsOnly != true) ...[
                              _MorbidityTable(
                                records: _filteredRecords,
                                onView: (record) =>
                                    _showMorbidityHistory(context, record),
                                onLongPress: (record) =>
                                    _showRecordActionModal(context, record),
                              ),
                              const SizedBox(height: 80),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMetricsCards() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildMetricCard(
            title: 'Total Cases',
            value: '$_totalCases',
            icon: Icons.people,
            color: _primaryAqua,
          ),
          const SizedBox(width: 16),
          _buildMetricCard(
            title: 'Active Patients',
            value: '$_activePatients',
            icon: Icons.local_hospital,
            color: _secondaryIceBlue,
          ),
          const SizedBox(width: 16),
          _buildMetricCard(
            title: 'Recovery Rate',
            value: '${_recoveryRate.toStringAsFixed(1)}%',
            icon: Icons.trending_up,
            color: _primaryAqua,
          ),
          const SizedBox(width: 16),
          _buildMetricCard(
            title: 'Most Common',
            value: _mostCommonDisease,
            icon: Icons.warning_amber,
            color: _secondaryIceBlue,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: _lightOffWhite,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildChartssection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Disease Trends & Analytics',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: _lightOffWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildChartsGrid(),
      ],
    );
  }

  Widget _buildChartsGrid() {
    // Calculate trend analysis
    final totalCasesThisMonth = _monthlyTrends.isNotEmpty
        ? _monthlyTrends.last.count
        : 0;
    final totalCasesLastMonth = _monthlyTrends.length > 1
        ? _monthlyTrends[_monthlyTrends.length - 2].count
        : 0;
    final monthlyGrowth = totalCasesLastMonth > 0
        ? ((totalCasesThisMonth - totalCasesLastMonth) /
              totalCasesLastMonth *
              100)
        : 0.0;
    final avgCasesPerMonth = _monthlyTrends.isNotEmpty
        ? _monthlyTrends.fold<int>(0, (sum, item) => sum + item.count) ~/
              _monthlyTrends.length
        : 0;
    final peakMonth = _monthlyTrends.isNotEmpty
        ? _monthlyTrends.reduce((a, b) => a.count > b.count ? a : b)
        : null;

    return Column(
      children: [
        // Trend Analysis Summary Cards
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTrendAnalysisCard(
                title: 'This Month Cases',
                value: '$totalCasesThisMonth',
                subtitle: 'Current month total',
                icon: Icons.calendar_today,
                color: _primaryAqua,
              ),
              const SizedBox(width: 16),
              _buildTrendAnalysisCard(
                title: 'Monthly Growth',
                value: '${monthlyGrowth.toStringAsFixed(1)}%',
                subtitle: monthlyGrowth > 0
                    ? 'Increase vs last month'
                    : 'Decrease vs last month',
                icon: monthlyGrowth > 0
                    ? Icons.trending_up
                    : Icons.trending_down,
                color: monthlyGrowth > 0 ? Colors.red : Colors.green,
              ),
              const SizedBox(width: 16),
              _buildTrendAnalysisCard(
                title: 'Average Per Month',
                value: '$avgCasesPerMonth',
                subtitle: 'Historical average',
                icon: Icons.bar_chart,
                color: _secondaryIceBlue,
              ),
              const SizedBox(width: 16),
              if (peakMonth != null)
                _buildTrendAnalysisCard(
                  title: 'Peak Month',
                  value: '${peakMonth.count}',
                  subtitle: peakMonth.month,
                  icon: Icons.show_chart,
                  color: Colors.orange,
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Monthly Trends Chart with Enhanced Details
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _primaryAqua.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monthly Case Trends',
                        style: TextStyle(
                          color: _lightOffWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Case distribution across months',
                        style: TextStyle(color: _mutedCoolGray, fontSize: 11),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Total: $_totalCases',
                      style: const TextStyle(
                        color: _primaryAqua,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 280,
                child: charts.BarChart(
                  _buildMonthlyTrendsChart(),
                  animate: true,
                  barGroupingType: charts.BarGroupingType.groupedStacked,
                  behaviors: [
                    charts.ChartTitle(
                      'Month',
                      behaviorPosition: charts.BehaviorPosition.bottom,
                      titleStyleSpec: const charts.TextStyleSpec(
                        color: charts.Color.white,
                        fontSize: 12,
                      ),
                    ),
                    charts.ChartTitle(
                      'Number of Cases',
                      behaviorPosition: charts.BehaviorPosition.start,
                      titleStyleSpec: const charts.TextStyleSpec(
                        color: charts.Color.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  primaryMeasureAxis: const charts.NumericAxisSpec(
                    showAxisLine: true,
                    renderSpec: charts.GridlineRendererSpec(
                      labelStyle: charts.TextStyleSpec(
                        color: charts.Color.white,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Monthly Breakdown Table
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _darkDeepTeal.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _primaryAqua.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly Breakdown',
                      style: TextStyle(
                        color: _lightOffWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_monthlyTrends.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          'No data available',
                          style: TextStyle(color: _mutedCoolGray, fontSize: 11),
                        ),
                      )
                    else
                      ..._monthlyTrends.map((trend) {
                        final percentage = _totalCases > 0
                            ? (trend.count / _totalCases * 100).toStringAsFixed(
                                1,
                              )
                            : '0.0';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    trend.month,
                                    style: const TextStyle(
                                      color: _lightOffWhite,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _primaryAqua.withValues(
                                            alpha: 0.2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          '${trend.count} cases',
                                          style: const TextStyle(
                                            color: _primaryAqua,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '$percentage%',
                                        style: const TextStyle(
                                          color: _mutedCoolGray,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: _totalCases > 0
                                      ? trend.count / _totalCases
                                      : 0,
                                  minHeight: 4,
                                  backgroundColor: _primaryAqua.withValues(
                                    alpha: 0.1,
                                  ),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _primaryAqua,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Disease Distribution Pie Chart
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _primaryAqua.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Disease Distribution',
                        style: TextStyle(
                          color: _lightOffWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Disease breakdown analysis',
                        style: TextStyle(color: _mutedCoolGray, fontSize: 11),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _secondaryIceBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_diseaseData.length} diseases',
                      style: const TextStyle(
                        color: _secondaryIceBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 250,
                child: charts.PieChart(
                  _buildDiseaseDistributionChart(),
                  animate: true,
                ),
              ),
              const SizedBox(height: 16),
              // Color Legend for Pie Chart
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _darkDeepTeal.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _secondaryIceBlue.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chart Legend & Key',
                      style: TextStyle(
                        color: _lightOffWhite,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        ..._diseaseData.asMap().entries.map((entry) {
                          final index = entry.key;
                          final disease = entry.value;
                          final colors = [
                            _primaryAqua,
                            _secondaryIceBlue,
                            Color(0xFF64B5F6),
                            Color(0xFF81C784),
                            Color(0xFFFFB74D),
                            Color(0xFFE57373),
                            Color(0xFF9575CD),
                          ];
                          final color = colors[index % colors.length];

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                disease.name,
                                style: const TextStyle(
                                  color: _lightOffWhite,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Disease Breakdown List
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _darkDeepTeal.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _secondaryIceBlue.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Detailed Disease Breakdown',
                      style: TextStyle(
                        color: _lightOffWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_diseaseData.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          'No disease data available',
                          style: TextStyle(color: _mutedCoolGray, fontSize: 11),
                        ),
                      )
                    else
                      SizedBox(
                        height: 200,
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              ..._diseaseData.map((disease) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6.0,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          disease.name,
                                          style: const TextStyle(
                                            color: _lightOffWhite,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _secondaryIceBlue.withValues(
                                            alpha: 0.2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          '${disease.count}',
                                          style: const TextStyle(
                                            color: _secondaryIceBlue,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _primaryAqua.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          '${disease.percentage.toStringAsFixed(1)}%',
                                          style: const TextStyle(
                                            color: _primaryAqua,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrendAnalysisCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 20),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.arrow_upward, color: color, size: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: _lightOffWhite,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: _lightOffWhite,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: _mutedCoolGray, fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  List<charts.Series<MonthlyTrend, String>> _buildMonthlyTrendsChart() {
    return [
      charts.Series(
        id: 'Cases',
        colorFn: (_, _) => charts.ColorUtil.fromDartColor(_primaryAqua),
        domainFn: (MonthlyTrend trend, _) => trend.month,
        measureFn: (MonthlyTrend trend, _) => trend.count,
        data: _monthlyTrends,
      ),
    ];
  }

  List<charts.Series<DiseaseData, String>> _buildDiseaseDistributionChart() {
    return [
      charts.Series(
        id: 'Disease',
        colorFn: (DiseaseData row, _) {
          final colors = [
            _primaryAqua,
            _secondaryIceBlue,
            Color(0xFF64B5F6),
            Color(0xFF81C784),
            Color(0xFFFFB74D),
            Color(0xFFE57373),
            Color(0xFF9575CD),
          ];
          return charts.ColorUtil.fromDartColor(
            colors[_diseaseData.indexOf(row) % colors.length],
          );
        },
        domainFn: (DiseaseData disease, _) => disease.name,
        measureFn: (DiseaseData disease, _) => disease.count,
        data: _diseaseData,
        labelAccessorFn: (DiseaseData disease, _) =>
            '${disease.count} (${disease.percentage.toStringAsFixed(1)}%)',
      ),
    ];
  }

  List<Map<String, dynamic>> _getMorbidityHistory(Map<String, dynamic> record) {
    return PatientHistoryDialogs.collectHistory(
      seedRecord: record,
      records: _morbidityRecords,
      idKeys: const ['linkedPatientId', 'patientId', 'id'],
      nameKeys: const ['patientName', 'patient', 'name'],
      sortDateKeys: const ['dateReported', 'date', 'time'],
    );
  }

  void _showMorbidityHistory(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final history = _getMorbidityHistory(record);
    PatientHistoryDialogs.showModuleHistoryDialog(
      context: context,
      moduleTitle: 'Morbidity',
      seedRecord: record,
      history: history,
      description:
          'Review previous morbidity reports for this patient before recording another disease episode.',
      titleBuilder: (entry) =>
          (entry['disease'] ?? 'Morbidity record').toString(),
      subtitleBuilder: (entry) =>
          '${(entry['severity'] ?? 'Unspecified').toString()} | ${(entry['status'] ?? 'Pending').toString()}',
      metaBuilder: (entry) =>
          'Facility: ${(entry['healthFacility'] ?? 'N/A').toString()} | Reported by: ${(entry['reportedBy'] ?? 'N/A').toString()}',
      dateKeys: const ['dateReported', 'date', 'time'],
      onOpenRecord: (entry) => _showMorbidityDetails(context, entry),
    );
  }

  void _showRecordActionModal(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final rawName =
        (record['patientName'] ?? record['patient'] ?? record['name'] ?? '')
            .toString()
            .trim();
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
                    _showMorbidityHistory(context, record);
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
                    _showMorbidityDetails(context, record);
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
                      Icon(Icons.visibility, size: 20, color: _primaryAqua),
                      SizedBox(width: 8),
                      Text(
                        'View Record Details',
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
                    _showNewMorbidityModal(context);
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
                        Icons.add_circle_outline,
                        size: 20,
                        color: Color(0xFF4ECDC4),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Add New Morbidity Record',
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
                    _showDeleteConfirmationDialog(context, record);
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
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteConfirmationDialog(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final rawName =
        (record['patientName'] ?? record['patient'] ?? record['name'] ?? '')
            .toString()
            .trim();
    final patientName = rawName.isEmpty ? 'Unknown' : rawName;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
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
                      onPressed: () => Navigator.pop(dialogContext),
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
                        Navigator.pop(dialogContext);
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

                        try {
                          await _dbHelper.deleteRecord(id);
                          await _loadData();

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

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: _darkDeepTeal,
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
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: _lightOffWhite),
        onChanged: (value) {
          _searchQuery = value;
          _applySearch();
        },
        decoration: InputDecoration(
          hintText: 'Search by patient name, disease, or record ID...',
          hintStyle: TextStyle(color: _lightOffWhite.withValues(alpha: 0.5)),
          prefixIcon: const Icon(Icons.search, color: _lightOffWhite),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: _lightOffWhite),
                  onPressed: () {
                    _searchController.clear();
                    _searchQuery = '';
                    _applySearch();
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
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: _lightOffWhite, width: 2),
          ),
          filled: true,
          fillColor: _darkDeepTeal,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

class _MorbidityTable extends StatefulWidget {
  final List<Map<String, dynamic>> records;
  final void Function(Map<String, dynamic>) onView;
  final void Function(Map<String, dynamic>) onLongPress;

  const _MorbidityTable({
    required this.records,
    required this.onView,
    required this.onLongPress,
  });

  @override
  State<_MorbidityTable> createState() => _MorbidityTableState();
}

class _MorbidityTableState extends State<_MorbidityTable> {
  static const int _recordsPerPage = 10;
  int _currentPage = 0;

  @override
  void didUpdateWidget(covariant _MorbidityTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records != widget.records) {
      _currentPage = 0;
    }
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

  Color _getAvatarColor(int index) {
    final colors = [
      const Color(0xFF00A8B5),
      const Color(0xFF1E5A7A),
      const Color(0xFFFF6B6B),
      const Color(0xFF4ECDC4),
      const Color(0xFFFFBE5B),
      const Color(0xFF845EC2),
    ];
    return colors[index % colors.length];
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'mild':
        return Colors.green;
      case 'moderate':
        return Colors.orange;
      case 'severe':
        return Colors.red;
      default:
        return _mutedCoolGray;
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) return 'N/A';
    final raw = value.toString().trim();
    if (raw.isEmpty) return 'N/A';
    if (raw.contains('T')) {
      return raw.split('T').first;
    }
    return raw.split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    final records = widget.records;
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
                'Add a new morbidity record to get started',
                style: TextStyle(color: _mutedCoolGray, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final totalPages = (records.length / _recordsPerPage).ceil();
    final safePage = _currentPage.clamp(0, totalPages - 1).toInt();
    final startIndex = safePage * _recordsPerPage;
    final endIndex = (startIndex + _recordsPerPage)
        .clamp(0, records.length)
        .toInt();
    final pageRecords = records.sublist(startIndex, endIndex);

    return Column(
      children: [
        ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: pageRecords.length,
          itemBuilder: (context, index) {
            final record = pageRecords[index];
            final absoluteIndex = startIndex + index;
            final patientNameValue =
                (record['patientName'] ??
                        record['patient'] ??
                        record['name'] ??
                        '')
                    .toString()
                    .trim();
            final patientName = patientNameValue.isEmpty
                ? 'Unknown'
                : patientNameValue;
            final disease = (record['disease'] ?? 'N/A').toString();
            final age = (record['age'] ?? 'N/A').toString();
            final severity = (record['severity'] ?? 'Mild').toString();
            final dateReported = _formatDate(
              record['dateReported'] ?? record['date'],
            );
            final severityColor = _getSeverityColor(severity);

            return GestureDetector(
              onTap: () => widget.onView(record),
              onLongPress: () => widget.onLongPress(record),
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
                      color: _lightOffWhite.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
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
                              Text(
                                disease,
                                style: TextStyle(
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
                                  ),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: 'Date: ',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: _lightOffWhite.withValues(
                                                alpha: 0.7,
                                              ),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          TextSpan(
                                            text: dateReported,
                                            style: const TextStyle(
                                              fontSize: 14,
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
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: severityColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: severityColor.withValues(
                                      alpha: 0.35,
                                    ),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  'Severity: $severity',
                                  style: TextStyle(
                                    color: severityColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
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
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${startIndex + 1}–$endIndex of ${records.length}',
              style: TextStyle(
                color: _lightOffWhite.withValues(alpha: 0.70),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: safePage > 0
                      ? () => setState(() => _currentPage = safePage - 1)
                      : null,
                  tooltip: 'Previous page',
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: _primaryAqua,
                  disabledColor: _mutedCoolGray.withValues(alpha: 0.35),
                ),
                Text(
                  '${safePage + 1} / $totalPages',
                  style: const TextStyle(
                    color: _lightOffWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: safePage < totalPages - 1
                      ? () => setState(() => _currentPage = safePage + 1)
                      : null,
                  tooltip: 'Next page',
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: _primaryAqua,
                  disabledColor: _mutedCoolGray.withValues(alpha: 0.35),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

// Data Models
class MonthlyTrend {
  final String month;
  final int count;

  MonthlyTrend(this.month, this.count);
}

class DiseaseData {
  final String name;
  final int count;
  final double percentage;

  DiseaseData(this.name, this.count, this.percentage);
}

class AgeDistribution {
  final String ageGroup;
  final int count;
  final double percentage;

  AgeDistribution(this.ageGroup, this.count, this.percentage);
}

// Modal Functions
void _showNewMorbidityModal(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: _darkDeepTeal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: _lightOffWhite.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        title: Text(
          'New Morbidity Record',
          style: TextStyle(color: _lightOffWhite, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModalTextField('Patient Name'),
              const SizedBox(height: 12),
              _buildModalTextField('Age'),
              const SizedBox(height: 12),
              _buildModalTextField('Disease'),
              const SizedBox(height: 12),
              _buildModalTextField('Health Facility'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _lightOffWhite),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryAqua,
              foregroundColor: _darkDeepTeal,
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}

Widget _buildModalTextField(String label) {
  return TextField(
    style: const TextStyle(
      color: _lightOffWhite,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _lightOffWhite),
      filled: true,
      fillColor: Colors.transparent,
      border: OutlineInputBorder(
        borderSide: BorderSide(color: _lightOffWhite.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: _lightOffWhite.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: _lightOffWhite, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}

void _showMorbidityDetails(BuildContext context, Map<String, dynamic> record) {
  final patientNameValue = record['patientName']?.toString().trim() ?? '';
  final patientName = patientNameValue.isEmpty ? 'Unknown' : patientNameValue;

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
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    child: const Icon(
                      Icons.local_hospital,
                      color: _lightOffWhite,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Morbidity Record Details',
                          style: TextStyle(
                            color: _lightOffWhite,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          patientName,
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
                    _buildMorbidityDetailSection('Patient Information', [
                      _buildMorbidityDetailRow('Patient Name', patientName),
                      _buildMorbidityDetailRow(
                        'Patient ID',
                        record['patientId']?.toString() ?? 'N/A',
                      ),
                      _buildMorbidityDetailRow(
                        'Age',
                        record['age']?.toString() ?? 'N/A',
                      ),
                      _buildMorbidityDetailRow(
                        'Gender',
                        record['gender']?.toString() ?? 'N/A',
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _buildMorbidityDetailSection('Clinical Details', [
                      _buildMorbidityDetailRow(
                        'Disease',
                        record['disease']?.toString() ?? 'N/A',
                      ),
                      _buildMorbidityDetailRow(
                        'Severity',
                        record['severity']?.toString() ?? 'N/A',
                      ),
                      _buildMorbidityDetailRow(
                        'Status',
                        record['status']?.toString() ?? 'N/A',
                      ),
                      _buildMorbidityDetailRow(
                        'Treatment',
                        record['treatment']?.toString() ?? 'N/A',
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _buildMorbidityDetailSection('Reporting Details', [
                      _buildMorbidityDetailRow(
                        'Health Facility',
                        record['healthFacility']?.toString() ?? 'N/A',
                      ),
                      _buildMorbidityDetailRow(
                        'Reported By',
                        record['reportedBy']?.toString() ?? 'N/A',
                      ),
                      _buildMorbidityDetailRow(
                        'Date Reported',
                        record['dateReported']?.toString().split('T').first ??
                            'N/A',
                      ),
                      _buildMorbidityDetailRow(
                        'Time',
                        record['time']?.toString() ?? 'N/A',
                      ),
                      _buildMorbidityDetailRow(
                        'Record ID',
                        record['id']?.toString() ?? 'N/A',
                      ),
                    ]),
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

Widget _buildMorbidityDetailSection(String title, List<Widget> children) {
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
        Text(
          title,
          style: const TextStyle(
            color: _lightOffWhite,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        Divider(height: 20, color: _lightOffWhite.withValues(alpha: 0.12)),
        ...children,
      ],
    ),
  );
}

Widget _buildMorbidityDetailRow(String label, String value) {
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
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: const TextStyle(
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
