import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mycapstone_project/app/features/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _darkDeepTeal = AppDesign.page;
const Color _lightOffWhite = AppDesign.ink;
const Color _panelTop = AppDesign.surface;
const Color _panelBottom = AppDesign.surface;
const Color _panelStroke = AppDesign.border;

enum _VolumeTrendRange { last7Days, last30Days, last12Months }

enum _AgeRangePeriod { last7Days, last30Days, allTime }

const _monthLabels = [
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

const _symptomLineColors = [
  Color(0xFF5E35B1),
  AppDesign.teal,
  Color(0xFFE65100),
  Color(0xFF43A047),
  Color(0xFF1E88E5),
  Color(0xFFFF6B6B),
  Color(0xFFFFE66D),
  Color(0xFF4ECDC4),
];

const _ageRangeColors = {
  '0-17': Color(0xFF1E88E5),
  '18-35': Color(0xFF43A047),
  '36-50': Color(0xFFE65100),
  '51+': Color(0xFF5E35B1),
};

class CheckUpAnalyticsPage extends StatefulWidget {
  const CheckUpAnalyticsPage({super.key});

  @override
  State<CheckUpAnalyticsPage> createState() => _CheckUpAnalyticsPageState();
}

class _CheckUpAnalyticsPageState extends State<CheckUpAnalyticsPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = true;
  _VolumeTrendRange _volumeTrendRange = _VolumeTrendRange.last30Days;
  _VolumeTrendRange _symptomTrendRange = _VolumeTrendRange.last30Days;
  int _symptomTopCount = 5;
  _AgeRangePeriod _ageRangePeriod = _AgeRangePeriod.allTime;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    try {
      await _dbHelper.syncFromFirebase();
    } catch (_) {
      // Continue with the local cache when Firebase is unavailable.
    }
    final records = await _dbHelper.getAllRecords();
    if (mounted) {
      setState(() {
        _records = records;
        _isLoading = false;
      });
    }
  }

  int get _totalCheckups => _records.length;

  int get _dailyCheckups {
    final today = DateTime.now();
    return _records.where((record) {
      try {
        final date = DateTime.parse(record['datetime'] ?? '');
        return date.year == today.year &&
            date.month == today.month &&
            date.day == today.day;
      } catch (_) {
        return false;
      }
    }).length;
  }

  int get _weeklyCheckups {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    return _records.where((record) {
      try {
        final date = DateTime.parse(record['datetime'] ?? '');
        return date.isAfter(startOfWeek.subtract(const Duration(days: 1))) &&
            date.isBefore(now.add(const Duration(days: 1)));
      } catch (_) {
        return false;
      }
    }).length;
  }

  int get _monthlyCheckups {
    final now = DateTime.now();
    return _records.where((record) {
      try {
        final date = DateTime.parse(record['datetime'] ?? '');
        return date.year == now.year && date.month == now.month;
      } catch (_) {
        return false;
      }
    }).length;
  }

  int get _yearlyCheckups {
    final now = DateTime.now();
    return _records.where((record) {
      try {
        final date = DateTime.parse(record['datetime'] ?? '');
        return date.year == now.year;
      } catch (_) {
        return false;
      }
    }).length;
  }

  Map<String, int> get _symptomTrend {
    final counts = <String, int>{};
    for (final record in _recordsInSymptomRange) {
      for (final symptom in _parseSymptoms(record)) {
        counts[symptom] = (counts[symptom] ?? 0) + 1;
      }
    }
    final sorted = Map.fromEntries(
      counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
    return sorted;
  }

  Iterable<Map<String, dynamic>> get _recordsInSymptomRange => _records.where(
    (record) => _isRecordInTrendRange(record, _symptomTrendRange),
  );

  Iterable<Map<String, dynamic>> get _recordsInAgeRange =>
      _records.where((record) => _isRecordInAgePeriod(record, _ageRangePeriod));

  List<String> _parseSymptoms(Map<String, dynamic> record) {
    final symptoms = (record['symptoms'] ?? '').toString();
    if (symptoms.isEmpty) return const [];
    return symptoms
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  DateTime? _parseRecordDate(Map<String, dynamic> record) {
    try {
      final parsed = DateTime.parse(record['datetime'] ?? '');
      return DateTime(parsed.year, parsed.month, parsed.day);
    } catch (_) {
      return null;
    }
  }

  bool _isRecordInTrendRange(
    Map<String, dynamic> record,
    _VolumeTrendRange range,
  ) {
    final date = _parseRecordDate(record);
    if (date == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (range == _VolumeTrendRange.last12Months) {
      final windowStart = DateTime(today.year, today.month - 11, 1);
      return !date.isBefore(windowStart) &&
          date.isBefore(today.add(const Duration(days: 1)));
    }

    final dayCount = range == _VolumeTrendRange.last7Days ? 7 : 30;
    final daysAgo = today.difference(date).inDays;
    return daysAgo >= 0 && daysAgo < dayCount;
  }

  bool _isRecordInAgePeriod(
    Map<String, dynamic> record,
    _AgeRangePeriod period,
  ) {
    if (period == _AgeRangePeriod.allTime) return true;
    final range = period == _AgeRangePeriod.last7Days
        ? _VolumeTrendRange.last7Days
        : _VolumeTrendRange.last30Days;
    return _isRecordInTrendRange(record, range);
  }

  List<MapEntry<String, int>> _buildTrendBuckets(_VolumeTrendRange range) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (range == _VolumeTrendRange.last12Months) {
      final buckets = <String, int>{};
      final orderedKeys = <String>[];

      for (var i = 11; i >= 0; i--) {
        final monthDate = DateTime(today.year, today.month - i, 1);
        final key =
            '${_monthLabels[monthDate.month - 1]} \'${monthDate.year % 100}';
        orderedKeys.add(key);
        buckets[key] = 0;
      }
      return orderedKeys.map((key) => MapEntry(key, buckets[key]!)).toList();
    }

    final dayCount = range == _VolumeTrendRange.last7Days ? 7 : 30;
    return List.generate(dayCount, (index) {
      final date = today.subtract(Duration(days: dayCount - 1 - index));
      return MapEntry(_formatVolumeDate(date, dayCount), 0);
    });
  }

  int? _bucketIndexForDate(DateTime date, _VolumeTrendRange range) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (range == _VolumeTrendRange.last12Months) {
      final windowStart = DateTime(today.year, today.month - 11, 1);
      if (date.isBefore(windowStart) ||
          date.isAfter(today.add(const Duration(days: 1)))) {
        return null;
      }
      final monthOffset =
          (date.year - windowStart.year) * 12 +
          (date.month - windowStart.month);
      return monthOffset.clamp(0, 11);
    }

    final dayCount = range == _VolumeTrendRange.last7Days ? 7 : 30;
    final daysAgo = today.difference(date).inDays;
    if (daysAgo < 0 || daysAgo >= dayCount) return null;
    return dayCount - 1 - daysAgo;
  }

  ({List<String> labels, List<MapEntry<String, List<int>>> series})
  get _symptomTimeSeriesData {
    final buckets = _buildTrendBuckets(_symptomTrendRange);
    final labels = buckets.map((entry) => entry.key).toList();
    final counts = <String, List<int>>{};

    for (final record in _recordsInSymptomRange) {
      final date = _parseRecordDate(record);
      if (date == null) continue;

      final bucketIndex = _bucketIndexForDate(date, _symptomTrendRange);
      if (bucketIndex == null) continue;

      for (final symptom in _parseSymptoms(record)) {
        counts.putIfAbsent(symptom, () => List.filled(labels.length, 0));
        counts[symptom]![bucketIndex]++;
      }
    }

    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final totalA = a.value.fold<int>(0, (sum, value) => sum + value);
        final totalB = b.value.fold<int>(0, (sum, value) => sum + value);
        return totalB.compareTo(totalA);
      });

    final series = ranked
        .take(_symptomTopCount)
        .map((entry) => MapEntry(entry.key, entry.value))
        .toList();

    return (labels: labels, series: series);
  }

  Map<String, int> get _ageRangeCounts {
    final counts = <String, int>{'0-17': 0, '18-35': 0, '36-50': 0, '51+': 0};
    for (final record in _recordsInAgeRange) {
      final ageValue = (record['age'] ?? '').toString();
      final age = int.tryParse(ageValue.replaceAll(RegExp(r'[^0-9]'), ''));
      if (age == null) continue;
      if (age <= 17) {
        counts['0-17'] = counts['0-17']! + 1;
      } else if (age <= 35) {
        counts['18-35'] = counts['18-35']! + 1;
      } else if (age <= 50) {
        counts['36-50'] = counts['36-50']! + 1;
      } else {
        counts['51+'] = counts['51+']! + 1;
      }
    }
    return counts;
  }

  List<MapEntry<String, int>> get _volumeTrendData {
    final buckets = _buildTrendBuckets(_volumeTrendRange);

    if (_volumeTrendRange == _VolumeTrendRange.last12Months) {
      final counts = {for (final bucket in buckets) bucket.key: 0};

      for (final record in _records) {
        final date = _parseRecordDate(record);
        if (date == null) continue;

        final bucketIndex = _bucketIndexForDate(date, _volumeTrendRange);
        if (bucketIndex == null) continue;

        final key = buckets[bucketIndex].key;
        counts[key] = counts[key]! + 1;
      }

      return buckets
          .map((bucket) => MapEntry(bucket.key, counts[bucket.key]!))
          .toList();
    }

    final counts = List<MapEntry<String, int>>.from(buckets);

    for (final record in _records) {
      final date = _parseRecordDate(record);
      if (date == null) continue;

      final bucketIndex = _bucketIndexForDate(date, _volumeTrendRange);
      if (bucketIndex == null) continue;

      counts[bucketIndex] = MapEntry(
        counts[bucketIndex].key,
        counts[bucketIndex].value + 1,
      );
    }

    return counts;
  }

  String _formatVolumeDate(DateTime date, int dayCount) {
    if (dayCount <= 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[date.weekday - 1];
    }
    return '${date.month}/${date.day}';
  }

  Map<String, int> get _vitalSignsCounts {
    final counts = <String, int>{};
    for (final record in _records) {
      final details = (record['details'] ?? '').toString();
      if (details.contains('BP:')) {
        counts['Blood Pressure'] = (counts['Blood Pressure'] ?? 0) + 1;
      }
      if (details.contains('Temp:')) {
        counts['Temperature'] = (counts['Temperature'] ?? 0) + 1;
      }
      if (details.contains('HR:')) {
        counts['Heart Rate'] = (counts['Heart Rate'] ?? 0) + 1;
      }
      if (details.contains('SpO2:')) {
        counts['Oxygen Saturation'] = (counts['Oxygen Saturation'] ?? 0) + 1;
      }
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _darkDeepTeal,
        appBar: AppBar(
          title: const Text('Check-up Analytics'),
          backgroundColor: _darkDeepTeal,
          foregroundColor: _lightOffWhite,
          elevation: 0,
          iconTheme: const IconThemeData(color: _lightOffWhite),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: _primaryAqua),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Check-up Analytics'),
        backgroundColor: _darkDeepTeal,
        foregroundColor: _lightOffWhite,
        elevation: 0,
        iconTheme: const IconThemeData(color: _lightOffWhite),
      ),
      backgroundColor: _darkDeepTeal,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_panelTop, _panelBottom],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: _panelStroke.withValues(alpha: 0.7),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Check-up Performance Dashboard',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: _lightOffWhite,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Executive summary of totals, trends, demographics, and vital sign activity.',
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.78),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: _primaryAqua.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.insights_rounded,
                      color: _primaryAqua,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatCard(
                  title: 'Total Check-ups',
                  value: '$_totalCheckups',
                  icon: Icons.fact_check_rounded,
                  color: AppDesign.teal,
                  subtitle: 'All records',
                ),
              ],
            ),
            const SizedBox(height: 20),
            _AnalyticsCard(
              title: 'Check-up Volume Trend',
              subtitle: 'Track check-up activity over time',
              icon: Icons.show_chart_rounded,
              badge: 'Interactive',
              child: SizedBox(height: 340, child: _buildVolumeLineChart()),
            ),
            const SizedBox(height: 16),
            _AnalyticsCard(
              title: 'Symptoms Trends',
              subtitle: 'Top symptoms over time',
              icon: Icons.sick_rounded,
              badge: 'Interactive',
              child: SizedBox(height: 380, child: _buildSymptomsLineChart()),
            ),
            const SizedBox(height: 16),
            _AnalyticsCard(
              title: 'Age Range',
              subtitle: 'Patient distribution by age group',
              icon: Icons.groups_rounded,
              badge: 'Interactive',
              child: SizedBox(height: 340, child: _buildAgeBarChart()),
            ),
            const SizedBox(height: 16),
            _AnalyticsCard(
              title: 'Vital Signs',
              subtitle: 'Recorded vital sign categories',
              icon: Icons.monitor_heart_rounded,
              badge: 'Summary',
              child: _buildListSummary(_vitalSignsCounts),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color accentColor = _primaryAqua,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: 0.22)
                : _lightOffWhite.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? accentColor.withValues(alpha: 0.55)
                  : _lightOffWhite.withValues(alpha: 0.10),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? _lightOffWhite
                  : _lightOffWhite.withValues(alpha: 0.72),
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVolumePeriodChip(String label, _VolumeTrendRange range) {
    return _buildPeriodChip(
      label: label,
      selected: _volumeTrendRange == range,
      onTap: () => setState(() => _volumeTrendRange = range),
    );
  }

  Widget _buildSymptomPeriodChip(String label, _VolumeTrendRange range) {
    return _buildPeriodChip(
      label: label,
      selected: _symptomTrendRange == range,
      onTap: () => setState(() => _symptomTrendRange = range),
      accentColor: const Color(0xFF5E35B1),
    );
  }

  Widget _buildSymptomCountChip(int count) {
    return _buildPeriodChip(
      label: 'Top $count',
      selected: _symptomTopCount == count,
      onTap: () => setState(() => _symptomTopCount = count),
      accentColor: const Color(0xFF5E35B1),
    );
  }

  Widget _buildAgePeriodChip(String label, _AgeRangePeriod period) {
    return _buildPeriodChip(
      label: label,
      selected: _ageRangePeriod == period,
      onTap: () => setState(() => _ageRangePeriod = period),
      accentColor: const Color(0xFF1E88E5),
    );
  }

  Widget _buildSummaryChip(
    String label,
    String value,
    IconData icon, {
    Color iconColor = _primaryAqua,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _lightOffWhite.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _lightOffWhite.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: iconColor.withValues(alpha: 0.9)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.62),
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      color: _lightOffWhite,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
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

  Widget _buildVolumeLineChart() {
    final data = _volumeTrendData;
    final total = data.fold<int>(0, (sum, entry) => sum + entry.value);
    final peak = data.fold<int>(
      0,
      (max, entry) => entry.value > max ? entry.value : max,
    );
    final average = data.isEmpty ? 0.0 : total / data.length;
    final hasActivity = total > 0;

    if (!hasActivity) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildVolumePeriodChip('7D', _VolumeTrendRange.last7Days),
              _buildVolumePeriodChip('30D', _VolumeTrendRange.last30Days),
              _buildVolumePeriodChip('12M', _VolumeTrendRange.last12Months),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.timeline_rounded,
                    size: 36,
                    color: _lightOffWhite.withValues(alpha: 0.28),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No check-ups in this period',
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Try a wider range or record new check-ups.',
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.48),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final maxY = (peak + 2).toDouble();
    final labelStep = data.length <= 7
        ? 1
        : data.length <= 14
        ? 2
        : 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildVolumePeriodChip('7D', _VolumeTrendRange.last7Days),
            _buildVolumePeriodChip('30D', _VolumeTrendRange.last30Days),
            _buildVolumePeriodChip('12M', _VolumeTrendRange.last12Months),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildSummaryChip('Total', '$total', Icons.summarize_rounded),
            const SizedBox(width: 8),
            _buildSummaryChip('Peak', '$peak', Icons.arrow_upward_rounded),
            const SizedBox(width: 8),
            _buildSummaryChip(
              'Average',
              average.toStringAsFixed(1),
              Icons.functions_rounded,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (data.length - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              backgroundColor: Colors.transparent,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: peak <= 5 ? 1 : (peak / 4).ceilToDouble(),
                verticalInterval: 1,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: _lightOffWhite.withValues(alpha: 0.08),
                    strokeWidth: 1,
                  );
                },
                getDrawingVerticalLine: (value) {
                  return FlLine(
                    color: _lightOffWhite.withValues(alpha: 0.04),
                    strokeWidth: 1,
                  );
                },
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  left: BorderSide(
                    color: _lightOffWhite.withValues(alpha: 0.16),
                  ),
                  bottom: BorderSide(
                    color: _lightOffWhite.withValues(alpha: 0.16),
                  ),
                ),
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: average,
                    color: AppDesign.teal.withValues(alpha: 0.45),
                    strokeWidth: 1.5,
                    dashArray: [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      padding: const EdgeInsets.only(right: 4, bottom: 4),
                      style: TextStyle(
                        color: AppDesign.teal.withValues(alpha: 0.85),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                      labelResolver: (_) => 'Avg ${average.toStringAsFixed(1)}',
                    ),
                  ),
                ],
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: peak <= 5 ? 1 : (peak / 4).ceilToDouble(),
                    getTitlesWidget: (value, meta) {
                      if (value != value.roundToDouble()) {
                        return const SizedBox();
                      }
                      return Text(
                        '${value.toInt()}',
                        style: TextStyle(
                          color: _lightOffWhite.withValues(alpha: 0.62),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= data.length) {
                        return const SizedBox();
                      }
                      if (index % labelStep != 0 && index != data.length - 1) {
                        return const SizedBox();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          data[index].key,
                          style: TextStyle(
                            fontSize: 9,
                            color: _lightOffWhite.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                enabled: true,
                handleBuiltInTouches: true,
                getTouchedSpotIndicator: (barData, spotIndexes) {
                  return spotIndexes.map((index) {
                    return TouchedSpotIndicatorData(
                      FlLine(
                        color: _primaryAqua.withValues(alpha: 0.35),
                        strokeWidth: 1.5,
                        dashArray: [4, 4],
                      ),
                      FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, i) {
                          return FlDotCirclePainter(
                            radius: 6,
                            color: _primaryAqua,
                            strokeWidth: 2,
                            strokeColor: _lightOffWhite,
                          );
                        },
                      ),
                    );
                  }).toList();
                },
                touchTooltipData: LineTouchTooltipData(
                  tooltipBorderRadius: BorderRadius.circular(12),
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  getTooltipColor: (_) => _panelBottom.withValues(alpha: 0.96),
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots
                        .map((spot) {
                          final index = spot.x.toInt();
                          if (index < 0 || index >= data.length) {
                            return null;
                          }
                          final label = data[index].key;
                          final count = spot.y.toInt();
                          return LineTooltipItem(
                            '$label\n$count check-up${count == 1 ? '' : 's'}',
                            const TextStyle(
                              color: _lightOffWhite,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          );
                        })
                        .whereType<LineTooltipItem>()
                        .toList();
                  },
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  curveSmoothness: 0.22,
                  preventCurveOverShooting: true,
                  gradient: const LinearGradient(
                    colors: [AppDesign.teal, _primaryAqua],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  barWidth: 3.5,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: data.length <= 12 ? 4 : 3,
                        color: _primaryAqua,
                        strokeWidth: 2,
                        strokeColor: _lightOffWhite.withValues(alpha: 0.9),
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        _primaryAqua.withValues(alpha: 0.28),
                        _primaryAqua.withValues(alpha: 0.04),
                        Colors.transparent,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                  spots: data.asMap().entries.map((entry) {
                    return FlSpot(
                      entry.key.toDouble(),
                      entry.value.value.toDouble(),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSymptomsLineChart() {
    final trendData = _symptomTimeSeriesData;
    final labels = trendData.labels;
    final series = trendData.series;
    final totalReports = series.fold<int>(
      0,
      (sum, entry) =>
          sum + entry.value.fold<int>(0, (inner, value) => inner + value),
    );
    final uniqueSymptoms = _symptomTrend.length;
    final topSymptom = series.isEmpty ? '—' : series.first.key;
    final peak = series.fold<int>(0, (max, entry) {
      final localMax = entry.value.fold<int>(
        0,
        (innerMax, value) => value > innerMax ? value : innerMax,
      );
      return localMax > max ? localMax : max;
    });

    if (series.isEmpty || totalReports == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSymptomPeriodChip('7D', _VolumeTrendRange.last7Days),
              _buildSymptomPeriodChip('30D', _VolumeTrendRange.last30Days),
              _buildSymptomPeriodChip('12M', _VolumeTrendRange.last12Months),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.sick_outlined,
                    size: 36,
                    color: _lightOffWhite.withValues(alpha: 0.28),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No symptom data in this period',
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Try a wider range or add check-ups with symptoms.',
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.48),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final maxY = (peak + 2).toDouble();
    final labelStep = labels.length <= 7
        ? 1
        : labels.length <= 14
        ? 2
        : 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildSymptomPeriodChip('7D', _VolumeTrendRange.last7Days),
            _buildSymptomPeriodChip('30D', _VolumeTrendRange.last30Days),
            _buildSymptomPeriodChip('12M', _VolumeTrendRange.last12Months),
            _buildSymptomCountChip(3),
            _buildSymptomCountChip(5),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildSummaryChip(
              'Reports',
              '$totalReports',
              Icons.report_rounded,
              iconColor: const Color(0xFF5E35B1),
            ),
            const SizedBox(width: 8),
            _buildSummaryChip(
              'Unique',
              '$uniqueSymptoms',
              Icons.category_rounded,
              iconColor: const Color(0xFF5E35B1),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _buildSummaryChip(
                'Top',
                topSymptom,
                Icons.star_rounded,
                iconColor: const Color(0xFF5E35B1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: series.asMap().entries.map((entry) {
            final color =
                _symptomLineColors[entry.key % _symptomLineColors.length];
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    entry.value.key,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.78),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (labels.length - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              backgroundColor: Colors.transparent,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: peak <= 5 ? 1 : (peak / 4).ceilToDouble(),
                verticalInterval: 1,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: _lightOffWhite.withValues(alpha: 0.08),
                    strokeWidth: 1,
                  );
                },
                getDrawingVerticalLine: (value) {
                  return FlLine(
                    color: _lightOffWhite.withValues(alpha: 0.04),
                    strokeWidth: 1,
                  );
                },
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  left: BorderSide(
                    color: _lightOffWhite.withValues(alpha: 0.16),
                  ),
                  bottom: BorderSide(
                    color: _lightOffWhite.withValues(alpha: 0.16),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: peak <= 5 ? 1 : (peak / 4).ceilToDouble(),
                    getTitlesWidget: (value, meta) {
                      if (value != value.roundToDouble()) {
                        return const SizedBox();
                      }
                      return Text(
                        '${value.toInt()}',
                        style: TextStyle(
                          color: _lightOffWhite.withValues(alpha: 0.62),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= labels.length) {
                        return const SizedBox();
                      }
                      if (index % labelStep != 0 &&
                          index != labels.length - 1) {
                        return const SizedBox();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          labels[index],
                          style: TextStyle(
                            fontSize: 9,
                            color: _lightOffWhite.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                enabled: true,
                handleBuiltInTouches: true,
                getTouchedSpotIndicator: (barData, spotIndexes) {
                  final color =
                      barData.gradient?.colors.first ??
                      barData.color ??
                      _symptomLineColors.first;
                  return spotIndexes.map((index) {
                    return TouchedSpotIndicatorData(
                      FlLine(
                        color: color.withValues(alpha: 0.35),
                        strokeWidth: 1.5,
                        dashArray: [4, 4],
                      ),
                      FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, i) {
                          return FlDotCirclePainter(
                            radius: 5,
                            color: color,
                            strokeWidth: 2,
                            strokeColor: _lightOffWhite,
                          );
                        },
                      ),
                    );
                  }).toList();
                },
                touchTooltipData: LineTouchTooltipData(
                  tooltipBorderRadius: BorderRadius.circular(12),
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  getTooltipColor: (_) => _panelBottom.withValues(alpha: 0.96),
                  getTooltipItems: (touchedSpots) {
                    if (touchedSpots.isEmpty) return [];

                    return touchedSpots
                        .map((spot) {
                          final xIndex = spot.x.toInt();
                          if (xIndex < 0 || xIndex >= labels.length) {
                            return null;
                          }
                          final symptomName = spot.barIndex < series.length
                              ? series[spot.barIndex].key
                              : 'Symptom';
                          final dateLabel = labels[xIndex];
                          final count = spot.y.toInt();
                          return LineTooltipItem(
                            '$symptomName\n$dateLabel: $count',
                            const TextStyle(
                              color: _lightOffWhite,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          );
                        })
                        .whereType<LineTooltipItem>()
                        .toList();
                  },
                ),
              ),
              lineBarsData: series.asMap().entries.map((entry) {
                final color =
                    _symptomLineColors[entry.key % _symptomLineColors.length];
                return LineChartBarData(
                  isCurved: true,
                  curveSmoothness: 0.2,
                  preventCurveOverShooting: true,
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.65)],
                  ),
                  barWidth: 2.8,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: labels.length <= 12,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 3.5,
                        color: color,
                        strokeWidth: 1.5,
                        strokeColor: _lightOffWhite.withValues(alpha: 0.9),
                      );
                    },
                  ),
                  belowBarData: BarAreaData(show: false),
                  spots: entry.value.value.asMap().entries.map((spotEntry) {
                    return FlSpot(
                      spotEntry.key.toDouble(),
                      spotEntry.value.toDouble(),
                    );
                  }).toList(),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAgeBarChart() {
    final data = _ageRangeCounts.entries.toList();
    final total = data.fold<int>(0, (sum, entry) => sum + entry.value);
    final topGroup = data.fold<MapEntry<String, int>>(
      data.first,
      (current, entry) => entry.value > current.value ? entry : current,
    );
    final topShare = total == 0 ? 0.0 : (topGroup.value / total) * 100;
    final hasAgeData = total > 0;

    if (!hasAgeData) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildAgePeriodChip('7D', _AgeRangePeriod.last7Days),
              _buildAgePeriodChip('30D', _AgeRangePeriod.last30Days),
              _buildAgePeriodChip('All', _AgeRangePeriod.allTime),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.groups_outlined,
                    size: 36,
                    color: _lightOffWhite.withValues(alpha: 0.28),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No age data in this period',
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Try a wider range or add patient ages to records.',
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.48),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final maxValue = data.fold<double>(
      0,
      (sum, entry) =>
          sum > entry.value.toDouble() ? sum : entry.value.toDouble(),
    );
    final maxY = maxValue + 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildAgePeriodChip('7D', _AgeRangePeriod.last7Days),
            _buildAgePeriodChip('30D', _AgeRangePeriod.last30Days),
            _buildAgePeriodChip('All', _AgeRangePeriod.allTime),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildSummaryChip(
              'Patients',
              '$total',
              Icons.people_rounded,
              iconColor: const Color(0xFF1E88E5),
            ),
            const SizedBox(width: 8),
            _buildSummaryChip(
              'Top Group',
              topGroup.key,
              Icons.leaderboard_rounded,
              iconColor: const Color(0xFF1E88E5),
            ),
            const SizedBox(width: 8),
            _buildSummaryChip(
              'Share',
              '${topShare.toStringAsFixed(0)}%',
              Icons.pie_chart_rounded,
              iconColor: const Color(0xFF1E88E5),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: data.map((entry) {
            final color = _ageRangeColors[entry.key] ?? _primaryAqua;
            final share = total == 0 ? 0.0 : (entry.value / total) * 100;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${entry.key} (${share.toStringAsFixed(0)}%)',
                  style: TextStyle(
                    color: _lightOffWhite.withValues(alpha: 0.78),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              backgroundColor: Colors.transparent,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxValue <= 5
                    ? 1
                    : (maxValue / 4).ceilToDouble(),
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: _lightOffWhite.withValues(alpha: 0.08),
                    strokeWidth: 1,
                  );
                },
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  left: BorderSide(
                    color: _lightOffWhite.withValues(alpha: 0.16),
                  ),
                  bottom: BorderSide(
                    color: _lightOffWhite.withValues(alpha: 0.16),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: maxValue <= 5 ? 1 : (maxValue / 4).ceilToDouble(),
                    getTitlesWidget: (value, meta) {
                      if (value != value.roundToDouble()) {
                        return const SizedBox();
                      }
                      return Text(
                        '${value.toInt()}',
                        style: TextStyle(
                          color: _lightOffWhite.withValues(alpha: 0.62),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= data.length) {
                        return const SizedBox();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          data[index].key,
                          style: TextStyle(
                            fontSize: 10,
                            color: _lightOffWhite.withValues(alpha: 0.78),
                            fontWeight: FontWeight.w600,
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
                  tooltipBorderRadius: BorderRadius.circular(12),
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  getTooltipColor: (_) => _panelBottom.withValues(alpha: 0.96),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final label = data[group.x.toInt()].key;
                    final count = rod.toY.toInt();
                    final share = total == 0 ? 0.0 : (count / total) * 100;
                    return BarTooltipItem(
                      '$label\n$count patients (${share.toStringAsFixed(0)}%)',
                      const TextStyle(
                        color: _lightOffWhite,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    );
                  },
                ),
              ),
              barGroups: data.asMap().entries.map((entry) {
                final color = _ageRangeColors[entry.value.key] ?? _primaryAqua;
                return BarChartGroupData(
                  x: entry.key,
                  barRods: [
                    BarChartRodData(
                      toY: entry.value.value.toDouble(),
                      width: 28,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                      gradient: LinearGradient(
                        colors: [color, color.withValues(alpha: 0.55)],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: maxY,
                        color: _lightOffWhite.withValues(alpha: 0.04),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListSummary(Map<String, int> data) {
    if (data.isEmpty) {
      return const Text('No data available yet.');
    }

    return Column(
      children: data.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  entry.key,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _lightOffWhite,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.14),
                  border: Border.all(
                    color: _primaryAqua.withValues(alpha: 0.24),
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${entry.value}',
                  style: const TextStyle(color: _lightOffWhite),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String subtitle;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _panelTop.withValues(alpha: 0.98),
            _panelBottom.withValues(alpha: 0.98),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _lightOffWhite,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String? badge;
  final Widget child;

  const _AnalyticsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _panelTop.withValues(alpha: 0.98),
            _panelBottom.withValues(alpha: 0.98),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _panelStroke.withValues(alpha: 0.7),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
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
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _lightOffWhite,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.72),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _lightOffWhite.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _lightOffWhite.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.82),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
