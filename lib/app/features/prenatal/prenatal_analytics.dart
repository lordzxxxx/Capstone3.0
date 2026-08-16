import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mycapstone_project/app/features/prenatal/prenatal_database_helper.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';
import 'package:mycapstone_project/shared/widgets/spring_data_motion.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _darkDeepTeal = AppDesign.page;
const Color _panelColor = AppDesign.surface;
const Color _lightOffWhite = AppDesign.ink;

class PrenatalAnalyticsPage extends StatefulWidget {
  const PrenatalAnalyticsPage({super.key});

  @override
  State<PrenatalAnalyticsPage> createState() => _PrenatalAnalyticsPageState();
}

class _PrenatalAnalyticsPageState extends State<PrenatalAnalyticsPage> {
  final PrenatalDatabaseHelper _database = PrenatalDatabaseHelper.instance;
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = true;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  DateTime? _recordDate(Map<String, dynamic> record, List<String> keys) {
    for (final key in keys) {
      final raw = _value(record, key);
      if (raw.isEmpty) continue;
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
      final parts = raw.split(RegExp(r'[/\-]'));
      if (parts.length == 3) {
        final a = int.tryParse(parts[0]);
        final b = int.tryParse(parts[1]);
        final c = int.tryParse(parts[2]);
        if (a != null && b != null && c != null) {
          try {
            return a > 31 ? DateTime(a, b, c) : DateTime(c, b, a);
          } catch (_) {}
        }
      }
    }
    return null;
  }

  String _monthLabel(DateTime date) {
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
    return '${months[date.month - 1]} ${date.year.toString().substring(2)}';
  }

  Map<String, int> _monthlyCounts(
    List<String> keys, {
    int months = 6,
    bool future = false,
  }) {
    final now = DateTime.now();
    final result = <String, int>{};
    for (var offset = 0; offset < months; offset++) {
      final delta = future ? offset : offset - (months - 1);
      final month = DateTime(now.year, now.month + delta);
      result[_monthLabel(month)] = 0;
    }
    for (final record in _records) {
      final date = _recordDate(record, keys);
      if (date == null) continue;
      final label = _monthLabel(DateTime(date.year, date.month));
      if (result.containsKey(label)) result[label] = result[label]! + 1;
    }
    return result;
  }

  String _riskLabel(Map<String, dynamic> record, {bool aiFirst = false}) {
    final raw =
        (aiFirst
                ? [_value(record, 'ai_severity'), _value(record, 'riskLevel')]
                : [_value(record, 'riskLevel'), _value(record, 'ai_severity')])
            .firstWhere(
              (value) => value.isNotEmpty,
              orElse: () => 'Not specified',
            )
            .toLowerCase();
    if (raw.contains('critical') || raw.contains('high')) return 'High Risk';
    if (raw.contains('moderate') || raw.contains('medium')) {
      return 'Moderate Risk';
    }
    if (raw.contains('low') || raw.contains('normal') || raw.contains('mild')) {
      return 'Low Risk';
    }
    return 'Not specified';
  }

  Map<String, int> _riskCounts({bool aiFirst = false}) {
    final result = <String, int>{
      'Low Risk': 0,
      'Moderate Risk': 0,
      'High Risk': 0,
    };
    for (final record in _records) {
      final label = _riskLabel(record, aiFirst: aiFirst);
      result[label] = (result[label] ?? 0) + 1;
    }
    return result;
  }

  String _barangay(Map<String, dynamic> record) {
    final direct = _value(record, 'barangay');
    if (direct.isNotEmpty) return direct;
    final address = _value(record, 'address');
    if (address.isEmpty) return 'Not specified';
    return address.split(',').first.trim();
  }

  Map<String, int> _highRiskBarangays() {
    final counts = <String, int>{};
    for (final record in _records) {
      if (_riskLabel(record) != 'High Risk') continue;
      final barangay = _barangay(record);
      counts[barangay] = (counts[barangay] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> _trimesterCounts() {
    final result = <String, int>{
      'First': 0,
      'Second': 0,
      'Third': 0,
      'Not specified': 0,
    };
    for (final record in _records) {
      final raw = _value(record, 'gestationalAge').isNotEmpty
          ? _value(record, 'gestationalAge')
          : _value(record, 'aog');
      final match = RegExp(r'\d+').firstMatch(raw);
      final weeks = match == null ? null : int.tryParse(match.group(0)!);
      final label = weeks == null
          ? 'Not specified'
          : weeks <= 13
          ? 'First'
          : weeks <= 27
          ? 'Second'
          : 'Third';
      result[label] = result[label]! + 1;
    }
    return result;
  }

  Map<String, int> _completionCounts() {
    final result = <String, int>{'Completed': 0, 'Ongoing': 0, 'Missed': 0};
    for (final record in _records) {
      final status = _value(record, 'status').toLowerCase();
      final label = status.contains('complete') || status.contains('deliver')
          ? 'Completed'
          : status.contains('miss') || status.contains('overdue')
          ? 'Missed'
          : 'Ongoing';
      result[label] = result[label]! + 1;
    }
    return result;
  }

  Map<String, int> _ageCounts() {
    final result = <String, int>{
      'Below 18': 0,
      '18-24': 0,
      '25-34': 0,
      '35+': 0,
      'Unknown': 0,
    };
    for (final record in _records) {
      final age = int.tryParse(_value(record, 'age'));
      final label = age == null
          ? 'Unknown'
          : age < 18
          ? 'Below 18'
          : age <= 24
          ? '18-24'
          : age <= 34
          ? '25-34'
          : '35+';
      result[label] = result[label]! + 1;
    }
    return result;
  }

  Map<String, int> _complicationCounts() {
    const terms = <String, List<String>>{
      'Hypertension': ['hypertension', 'high blood pressure'],
      'Gestational Diabetes': ['gestational diabetes', 'diabetes'],
      'Anemia': ['anemia', 'anaemia'],
      'Pre-eclampsia': ['pre-eclampsia', 'preeclampsia'],
      'Hemorrhage': ['hemorrhage', 'bleeding'],
    };
    final result = <String, int>{for (final label in terms.keys) label: 0};
    for (final record in _records) {
      final text = [
        _value(record, 'preExistingConditions'),
        _value(record, 'previousComplications'),
        _value(record, 'additionalNote'),
        _value(record, 'ai_category'),
      ].join(' ').toLowerCase();
      for (final entry in terms.entries) {
        if (entry.value.any(text.contains))
          result[entry.key] = result[entry.key]! + 1;
      }
    }
    return result;
  }

  Map<String, int> _referralCounts() {
    final result = <String, int>{'Referred': 0, 'Pending': 0, 'Completed': 0};
    for (final record in _records) {
      final raw =
          [
                _value(record, 'referralStatus'),
                _value(record, 'referral_status'),
                _value(record, 'referred'),
              ]
              .firstWhere((value) => value.isNotEmpty, orElse: () => 'Pending')
              .toLowerCase();
      final label = raw.contains('complete') || raw.contains('accepted')
          ? 'Completed'
          : raw.contains('refer') || raw == 'yes' || raw == 'true'
          ? 'Referred'
          : 'Pending';
      result[label] = result[label]! + 1;
    }
    return result;
  }

  Widget _monthlyVisitsChart() => _lineChartPanel(
    title: 'Monthly Prenatal Visits',
    subtitle: 'Attendance trend across the last six months',
    icon: Icons.show_chart_rounded,
    data: _monthlyCounts(const [
      'registrationDate',
      'date',
      'datetime',
      'createdAt',
    ]),
  );

  Widget _pregnancyRiskPieChart() => _pieChartPanel(
    title: 'Pregnancy Risk Distribution',
    subtitle: 'Percentage of mothers by risk category',
    icon: Icons.pie_chart_rounded,
    data: _riskCounts(),
  );

  Widget _highRiskByBarangayChart() => _barChartPanel(
    title: 'High-Risk Pregnancies by Barangay',
    subtitle: 'Areas requiring priority maternal-health resources',
    icon: Icons.location_city_rounded,
    data: _highRiskBarangays(),
  );

  Widget _gestationalAgeChart() => _barChartPanel(
    title: 'Gestational Age Distribution',
    subtitle: 'Mothers grouped by pregnancy trimester',
    icon: Icons.pregnant_woman_rounded,
    data: _trimesterCounts(),
  );

  Widget _expectedDeliveryChart() => _lineChartPanel(
    title: 'Expected Delivery by Month',
    subtitle: 'Expected births during the next six months',
    icon: Icons.event_available_rounded,
    data: _monthlyCounts(const ['eddDate', 'dueDate'], future: true),
  );

  Widget _completionRateChart() => _pieChartPanel(
    title: 'Prenatal Completion Rate',
    subtitle: 'Completed, ongoing, and missed prenatal care',
    icon: Icons.task_alt_rounded,
    data: _completionCounts(),
  );

  Widget _maternalAgeChart() => _barChartPanel(
    title: 'Maternal Age Distribution',
    subtitle: 'Teenage and advanced maternal-age visibility',
    icon: Icons.groups_2_rounded,
    data: _ageCounts(),
  );

  Widget _complicationsChart() => _barChartPanel(
    title: 'Pregnancy Complications',
    subtitle: 'Most common recorded maternal complications',
    icon: Icons.medical_information_rounded,
    data: _complicationCounts(),
  );

  Widget _aiRiskChart() => _barChartPanel(
    title: 'AI Risk Prediction Dashboard',
    subtitle: 'AI-generated and clinical pregnancy risk levels',
    icon: Icons.psychology_rounded,
    data: _riskCounts(aiFirst: true),
  );

  Widget _referralStatusChart() => _pieChartPanel(
    title: 'Referral Status',
    subtitle: 'Follow-through for higher-level maternal care',
    icon: Icons.forward_to_inbox_rounded,
    data: _referralCounts(),
  );

  Widget _geographicRiskPanel() {
    final entries = _highRiskBarangays().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxValue = entries.isEmpty ? 1 : entries.first.value;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader(
            'Geographic Risk Heat Map',
            'High-risk concentration by barangay',
            Icons.map_rounded,
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            _emptyState()
          else
            ...entries.take(8).map((entry) {
              final intensity = entry.value / maxValue;
              final color = Color.lerp(
                AppDesign.blueSoft,
                AppDesign.navy,
                intensity,
              )!;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.45)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on_rounded, color: color, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(color: _lightOffWhite),
                      ),
                    ),
                    Text(
                      '${entry.value}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
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

  Future<void> _loadRecords() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      try {
        await _database.syncFromFirebase();
      } catch (_) {
        // Continue with locally available records when sync is unavailable.
      }
      final records = await _database.getAllRecords();
      if (!mounted) return;
      setState(() {
        // An empty result is rendered as an empty state. Never replace real
        // application data with fabricated analytics records.
        _records = records;
        _lastUpdated = DateTime.now();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _value(Map<String, dynamic> record, String key) =>
      (record[key] ?? '').toString().trim();

  bool _matches(Map<String, dynamic> record, String key, String value) =>
      _value(record, key).toLowerCase() == value.toLowerCase();

  Map<String, int> _countsFor(String key, {String fallback = 'Not specified'}) {
    final counts = <String, int>{};
    for (final record in _records) {
      final raw = _value(record, key);
      final label = raw.isEmpty ? fallback : raw;
      counts[label] = (counts[label] ?? 0) + 1;
    }
    return counts;
  }

  int get _highRiskCount => _records.where((record) {
    final risk = _value(record, 'riskLevel').toLowerCase();
    final severity = _value(record, 'ai_severity').toLowerCase();
    return risk.contains('high') ||
        risk.contains('critical') ||
        severity.contains('high') ||
        severity.contains('critical');
  }).length;

  int get _activeCount => _records.where((record) {
    final status = _value(record, 'status').toLowerCase();
    return status.isEmpty || status == 'active' || status == 'ongoing';
  }).length;

  int get _dueSoonCount {
    final now = DateTime.now();
    final limit = now.add(const Duration(days: 30));
    return _records.where((record) {
      final raw = _value(record, 'eddDate').isNotEmpty
          ? _value(record, 'eddDate')
          : _value(record, 'dueDate');
      final date = DateTime.tryParse(raw);
      return date != null && !date.isBefore(now) && !date.isAfter(limit);
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkDeepTeal,
      appBar: AppBar(
        backgroundColor: AppDesign.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Prenatal Analytics',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadRecords,
            tooltip: 'Refresh analytics',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryAqua))
          : RefreshIndicator(
              onRefresh: _loadRecords,
              color: _primaryAqua,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  Text(
                    'Prenatal care insights',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: _lightOffWhite,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _lastUpdated == null
                        ? 'Current prenatal population overview'
                        : 'Updated ${_lastUpdated!.hour.toString().padLeft(2, '0')}:${_lastUpdated!.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.65),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.35,
                    children: [
                      _metric(
                        'Total Patients',
                        '${_records.length}',
                        Icons.groups_rounded,
                      ),
                      _metric(
                        'Active Cases',
                        '$_activeCount',
                        Icons.favorite_rounded,
                      ),
                      _metric(
                        'High Risk',
                        '$_highRiskCount',
                        Icons.warning_rounded,
                      ),
                      _metric(
                        'Due in 30 Days',
                        '$_dueSoonCount',
                        Icons.event_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _monthlyVisitsChart(),
                  const SizedBox(height: 16),
                  _pregnancyRiskPieChart(),
                  const SizedBox(height: 16),
                  _highRiskByBarangayChart(),
                  const SizedBox(height: 16),
                  _gestationalAgeChart(),
                  const SizedBox(height: 16),
                  _expectedDeliveryChart(),
                  const SizedBox(height: 16),
                  _completionRateChart(),
                  const SizedBox(height: 16),
                  _maternalAgeChart(),
                  const SizedBox(height: 16),
                  _complicationsChart(),
                  const SizedBox(height: 16),
                  _aiRiskChart(),
                  const SizedBox(height: 16),
                  _referralStatusChart(),
                  const SizedBox(height: 16),
                  _geographicRiskPanel(),
                  const SizedBox(height: 16),
                  _insightsPanel(),
                ],
              ),
            ),
    );
  }

  List<MapEntry<String, int>> _visibleEntries(Map<String, int> data) {
    final entries = data.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(7).toList();
  }

  Widget _barChartPanel({
    required String title,
    required String subtitle,
    required IconData icon,
    required Map<String, int> data,
  }) {
    final entries = _visibleEntries(data);
    final maxValue = entries.isEmpty
        ? 1.0
        : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b) + 1.0;
    const palette = AppDesign.chartPalette;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader(title, subtitle, icon),
          const SizedBox(height: 18),
          if (entries.isEmpty)
            _emptyState()
          else
            SizedBox(
              height: 280,
              child: BarChart(
                BarChartData(
                  minY: 0,
                  maxY: maxValue,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: AppDesign.border, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: maxValue <= 5 ? 1 : null,
                        getTitlesWidget: (value, meta) => Text(
                          '${value.toInt()}',
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.55),
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= entries.length)
                            return const SizedBox.shrink();
                          return SideTitleWidget(
                            meta: meta,
                            space: 8,
                            child: SizedBox(
                              width: 52,
                              child: Text(
                                entries[index].key,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _lightOffWhite.withValues(alpha: 0.68),
                                  fontSize: 8.5,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => AppDesign.surface,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final entry = entries[group.x.toInt()];
                        return BarTooltipItem(
                          '${entry.key}\n${entry.value}',
                          const TextStyle(
                            color: _lightOffWhite,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                  barGroups: List.generate(entries.length, (index) {
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: entries[index].value.toDouble(),
                          width: entries.length > 5 ? 16 : 24,
                          color: palette[index % palette.length],
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxValue,
                            color: AppDesign.blueSoft.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
              ),
            ),
        ],
      ),
    );
  }

  Widget _lineChartPanel({
    required String title,
    required String subtitle,
    required IconData icon,
    required Map<String, int> data,
  }) {
    final entries = data.entries.toList();
    final maxValue = entries.isEmpty
        ? 1.0
        : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b) + 1.0;
    final spots = List.generate(
      entries.length,
      (index) => FlSpot(index.toDouble(), entries[index].value.toDouble()),
    );
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader(title, subtitle, icon),
          const SizedBox(height: 18),
          if (entries.isEmpty)
            _emptyState()
          else
            SizedBox(
              height: 270,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (entries.length - 1).toDouble(),
                  minY: 0,
                  maxY: maxValue,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: AppDesign.border, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: maxValue <= 5 ? 1 : null,
                        getTitlesWidget: (value, meta) => Text(
                          '${value.toInt()}',
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.55),
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 ||
                              index >= entries.length ||
                              value != index.toDouble()) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            meta: meta,
                            space: 8,
                            child: Text(
                              entries[index].key,
                              style: TextStyle(
                                color: _lightOffWhite.withValues(alpha: 0.68),
                                fontSize: 8.5,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => AppDesign.surface,
                      getTooltipItems: (spots) => spots.map((spot) {
                        final entry = entries[spot.x.toInt()];
                        return LineTooltipItem(
                          '${entry.key}\n${entry.value}',
                          const TextStyle(
                            color: _lightOffWhite,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: _primaryAqua,
                      barWidth: 3,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: _primaryAqua.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
              ),
            ),
        ],
      ),
    );
  }

  Widget _pieChartPanel({
    required String title,
    required String subtitle,
    required IconData icon,
    required Map<String, int> data,
  }) {
    final entries = _visibleEntries(data);
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    const palette = AppDesign.chartPalette;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader(title, subtitle, icon),
          const SizedBox(height: 18),
          if (entries.isEmpty)
            _emptyState()
          else ...[
            SizedBox(
              height: 220,
              child: PieChart(
                PieChartData(
                  centerSpaceRadius: 48,
                  sectionsSpace: 3,
                  pieTouchData: PieTouchData(enabled: true),
                  sections: List.generate(entries.length, (index) {
                    final entry = entries[index];
                    final share = total == 0 ? 0.0 : entry.value / total * 100;
                    final sliceColor = palette[index % palette.length];
                    return PieChartSectionData(
                      value: entry.value.toDouble(),
                      color: sliceColor,
                      radius: 64,
                      title: '${share.toStringAsFixed(0)}%',
                      titleStyle: TextStyle(
                        color: sliceColor.computeLuminance() > 0.42
                            ? _lightOffWhite
                            : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  }),
                ),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
              ),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: List.generate(entries.length, (index) {
                final entry = entries[index];
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: palette[index % palette.length].withValues(
                      alpha: 0.11,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: palette[index % palette.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${entry.key}: ${entry.value}',
                        style: const TextStyle(
                          color: _lightOffWhite,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _powerBiRiskChart() {
    final entries = _countsFor('riskLevel').entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final visibleEntries = entries.take(5).toList();
    final highest = visibleEntries.isEmpty
        ? 1.0
        : visibleEntries
                  .map((entry) => entry.value)
                  .reduce((a, b) => a > b ? a : b)
                  .toDouble() +
              1;
    const colors = AppDesign.chartPalette;

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader(
            'Risk overview',
            'Top prenatal risk classifications',
            Icons.bar_chart_rounded,
          ),
          const SizedBox(height: 18),
          if (visibleEntries.isEmpty)
            _emptyState()
          else
            SizedBox(
              height: 280,
              child: BarChart(
                BarChartData(
                  minY: 0,
                  maxY: highest,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: AppDesign.border, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: highest <= 5 ? 1 : null,
                        getTitlesWidget: (value, meta) => Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.55),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= visibleEntries.length) {
                            return const SizedBox.shrink();
                          }
                          final label = visibleEntries[index].key;
                          return SideTitleWidget(
                            meta: meta,
                            space: 8,
                            child: SizedBox(
                              width: 58,
                              child: Text(
                                label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _lightOffWhite.withValues(alpha: 0.72),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => AppDesign.surface,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final entry = visibleEntries[group.x.toInt()];
                        return BarTooltipItem(
                          '${entry.key}\n${entry.value} patients',
                          const TextStyle(
                            color: _lightOffWhite,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                  barGroups: List.generate(visibleEntries.length, (index) {
                    final entry = visibleEntries[index];
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: entry.value.toDouble(),
                          width: 24,
                          color: colors[index % colors.length],
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(7),
                          ),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: highest,
                            color: AppDesign.blueSoft.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
              ),
            ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: _primaryAqua, size: 23),
          Text(
            value,
            style: const TextStyle(
              color: _lightOffWhite,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.65),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _distributionPanel({
    required String title,
    required String subtitle,
    required IconData icon,
    required Map<String, int> counts,
  }) {
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = counts.values.fold<int>(0, (sum, count) => sum + count);
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader(title, subtitle, icon),
          const SizedBox(height: 18),
          if (entries.isEmpty)
            _emptyState()
          else
            ...entries.map((entry) {
              final ratio = total == 0 ? 0.0 : entry.value / total;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _lightOffWhite),
                          ),
                        ),
                        Text(
                          '${entry.value}  ${(ratio * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: _primaryAqua,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 8,
                        backgroundColor: AppDesign.blueSoft,
                        color: _primaryAqua,
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

  Widget _insightsPanel() {
    final completed = _records
        .where((r) => _matches(r, 'status', 'Completed'))
        .length;
    final coverage = _records.isEmpty ? 0.0 : completed / _records.length * 100;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader(
            'Insights',
            'Highlights requiring care-team attention',
            Icons.lightbulb_rounded,
          ),
          const SizedBox(height: 16),
          _insight(
            Icons.warning_amber_rounded,
            '$_highRiskCount high-risk patients need close monitoring.',
          ),
          _insight(
            Icons.calendar_month_rounded,
            '$_dueSoonCount patients have an expected delivery within 30 days.',
          ),
          _insight(
            Icons.task_alt_rounded,
            '${coverage.toStringAsFixed(1)}% of records are marked completed.',
          ),
        ],
      ),
    );
  }

  Widget _insight(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _primaryAqua, size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: _lightOffWhite, height: 1.35),
          ),
        ),
      ],
    ),
  );

  Widget _panel({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _panelColor,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _primaryAqua.withValues(alpha: 0.20)),
    ),
    child: SpringDataMotion(dataKey: child, child: child),
  );

  Widget _panelHeader(String title, String subtitle, IconData icon) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: _primaryAqua.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: _primaryAqua, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _lightOffWhite,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(
                color: _lightOffWhite.withValues(alpha: 0.58),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _emptyState() => Text(
    'No prenatal data available yet.',
    style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.6)),
  );
}
