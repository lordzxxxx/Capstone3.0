import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/features/surveillance/mortality/mortality_database_helper.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

const _accent = AppDesign.blue;
const _background = AppDesign.page;
const _surface = AppDesign.surface;
const _foreground = AppDesign.ink;
const _barPalette = <Color>[
  AppDesign.skyBlue,
  Color(0xFF5EC7FF),
  Color(0xFFFFB74D),
  Color(0xFFEC407A),
  Color(0xFF7E57C2),
  Color(0xFF66BB6A),
  Color(0xFFFF7043),
];

class MortalityAnalyticsPage extends StatefulWidget {
  const MortalityAnalyticsPage({super.key});

  @override
  State<MortalityAnalyticsPage> createState() => _MortalityAnalyticsPageState();
}

class _MortalityAnalyticsPageState extends State<MortalityAnalyticsPage> {
  final _database = MortalityDatabaseHelper.instance;
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _realRecords = [];
  bool _loading = true;
  bool _demo = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      try {
        await _database.syncFromFirebase();
      } catch (_) {}
      final records = await _database.getAllRecords();
      if (!mounted) return;
      setState(() {
        _realRecords = records;
        _demo = records.isEmpty;
        _records = records.isEmpty ? _demoRecords() : records;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleDemo() {
    setState(() {
      if (_demo && _realRecords.isNotEmpty) {
        _demo = false;
        _records = _realRecords;
      } else {
        _demo = true;
        _records = _demoRecords();
      }
    });
  }

  String _v(Map<String, dynamic> row, String key) =>
      (row[key] ?? '').toString().trim();

  DateTime? _date(Map<String, dynamic> row) {
    for (final key in const ['date', 'dateReported']) {
      final value = DateTime.tryParse(_v(row, key));
      if (value != null) return value;
    }
    return null;
  }

  List<Map<String, dynamic>> _demoRecords() {
    final now = DateTime.now();
    const causes = [
      'Heart Disease',
      'Stroke',
      'Pneumonia',
      'Cancer',
      'Diabetes',
    ];
    const places = ['Hospital', 'Home', 'Health Center', 'Other'];
    const barangays = ['Central', 'San Isidro', 'Mabini', 'Rizal', 'Maligaya'];
    const populations = [8200, 6700, 5400, 7100, 4900];
    return List.generate(72, (index) {
      final date = DateTime(
        now.year - index % 4,
        1 + index % 12,
        2 + index % 24,
      );
      final barangayIndex = index % barangays.length;
      return <String, dynamic>{
        'id': 'demo-mortality-$index',
        'name': 'Demo Record ${index + 1}',
        'date': date.toIso8601String(),
        'dateReported': date.toIso8601String(),
        'month': '${date.month}',
        'age': '${index % 11 == 0 ? 0 : 8 + (index * 7) % 83}',
        'gender': index.isEven ? 'Male' : 'Female',
        'causeOfDeath': causes[index % causes.length],
        'place': places[index % places.length],
        'barangay': barangays[barangayIndex],
        'population': populations[barangayIndex],
      };
    });
  }

  String _month(DateTime date) {
    const names = [
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
    return names[date.month - 1];
  }

  Map<String, int> _monthly() {
    final now = DateTime.now();
    final result = <String, int>{};
    for (var i = 0; i < 12; i++) {
      final date = DateTime(now.year, now.month + i - 11);
      result['${_month(date)} ${date.year.toString().substring(2)}'] = 0;
    }
    for (final row in _records) {
      final date = _date(row);
      if (date == null) continue;
      final key = '${_month(date)} ${date.year.toString().substring(2)}';
      if (result.containsKey(key)) result[key] = result[key]! + 1;
    }
    return result;
  }

  Map<String, int> _count(String key, {String fallback = 'Not specified'}) {
    final result = <String, int>{};
    for (final row in _records) {
      final raw = _v(row, key);
      final label = raw.isEmpty ? fallback : raw;
      result[label] = (result[label] ?? 0) + 1;
    }
    return result;
  }

  Map<String, int> _ages() {
    final result = <String, int>{
      '<1 year': 0,
      '1-14': 0,
      '15-24': 0,
      '25-44': 0,
      '45-64': 0,
      '65+': 0,
      'Unknown': 0,
    };
    for (final row in _records) {
      final age = int.tryParse(_v(row, 'age'));
      final label = age == null
          ? 'Unknown'
          : age < 1
          ? '<1 year'
          : age <= 14
          ? '1-14'
          : age <= 24
          ? '15-24'
          : age <= 44
          ? '25-44'
          : age <= 64
          ? '45-64'
          : '65+';
      result[label] = result[label]! + 1;
    }
    return result;
  }

  String _barangay(Map<String, dynamic> row) {
    final direct = _v(row, 'barangay');
    if (direct.isNotEmpty) return direct;
    final address = _v(row, 'address');
    return address.isEmpty ? 'Not specified' : address.split(',').first.trim();
  }

  Map<String, int> _barangays() {
    final result = <String, int>{};
    for (final row in _records) {
      final name = _barangay(row);
      result[name] = (result[name] ?? 0) + 1;
    }
    return result;
  }

  String _category(String cause) {
    final value = cause.toLowerCase();
    if (value.contains('heart') ||
        value.contains('stroke') ||
        value.contains('cardio'))
      return 'Cardiovascular';
    if (value.contains('pneumonia') ||
        value.contains('respiratory') ||
        value.contains('lung'))
      return 'Respiratory';
    if (value.contains('cancer') || value.contains('tumor')) return 'Cancer';
    if (value.contains('infection') ||
        value.contains('sepsis') ||
        value.contains('dengue'))
      return 'Infectious Diseases';
    if (value.contains('maternal') || value.contains('pregnan'))
      return 'Maternal';
    if (value.contains('diabetes')) return 'Metabolic';
    return 'Other';
  }

  Map<String, int> _categories() {
    final result = <String, int>{};
    for (final row in _records) {
      final category = _category(_v(row, 'causeOfDeath'));
      result[category] = (result[category] ?? 0) + 1;
    }
    return result;
  }

  Map<String, int> _years() {
    final result = <String, int>{};
    for (final row in _records) {
      final year = _date(row)?.year.toString() ?? 'Unknown';
      result[year] = (result[year] ?? 0) + 1;
    }
    final entries = result.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Map.fromEntries(entries);
  }

  Map<String, int> _riskAssessment() {
    final result = <String, int>{'Low': 0, 'Moderate': 0, 'High': 0};
    for (final row in _records) {
      final age = int.tryParse(_v(row, 'age')) ?? 0;
      final category = _category(_v(row, 'causeOfDeath'));
      final label =
          age >= 65 || category == 'Cardiovascular' || category == 'Cancer'
          ? 'High'
          : age >= 45 || category == 'Respiratory' || category == 'Metabolic'
          ? 'Moderate'
          : 'Low';
      result[label] = result[label]! + 1;
    }
    return result;
  }

  Map<String, int> _rates() {
    final deaths = _barangays();
    final populations = <String, int>{};
    for (final row in _records) {
      final barangay = _barangay(row);
      final population = int.tryParse(_v(row, 'population'));
      if (population != null && population > 0)
        populations[barangay] = population;
    }
    return deaths.map((barangay, count) {
      final population = populations[barangay] ?? 10000;
      return MapEntry(barangay, (count / population * 1000 * 100).round());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        elevation: 0,
        iconTheme: const IconThemeData(color: _foreground),
        title: const Text(
          'Mortality Analytics',
          style: TextStyle(color: _foreground, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _toggleDemo,
            tooltip: _demo ? 'Show real data' : 'Show dummy data',
            icon: Icon(
              _demo ? Icons.storage_rounded : Icons.science_rounded,
              color: _demo ? const Color(0xFFFFB74D) : _accent,
            ),
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : RefreshIndicator(
              onRefresh: _load,
              color: _accent,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  if (_demo)
                    _notice('Showing demo mortality data for analytics.'),
                  _line(
                    'Monthly Mortality Trend',
                    'Deaths recorded during the last 12 months',
                    _monthly(),
                  ),
                  _gap(),
                  _bar(
                    'Leading Causes of Death',
                    'Most frequently reported causes',
                    _count('causeOfDeath'),
                  ),
                  _gap(),
                  _bar(
                    'Mortality by Age Group',
                    'Deaths across vulnerable age categories',
                    _ages(),
                  ),
                  _gap(),
                  _pie(
                    'Mortality by Sex',
                    'Comparison of male and female mortality',
                    _count('gender'),
                  ),
                  _gap(),
                  _bar(
                    'Mortality by Barangay',
                    'Communities with higher mortality counts',
                    _barangays(),
                  ),
                  _gap(),
                  _bar(
                    'Mortality by Disease Category',
                    'Broader public-health cause groupings',
                    _categories(),
                  ),
                  _gap(),
                  _line(
                    'Mortality by Year',
                    'Long-term mortality trend',
                    _years(),
                  ),
                  _gap(),
                  _pie(
                    'Place of Death',
                    'Where reported deaths occurred',
                    _count('place'),
                  ),
                  _gap(),
                  _heatmap(),
                  _gap(),
                  _bar(
                    'AI Mortality Risk Assessment',
                    'Population-level planning aid—not an individual death prediction',
                    _riskAssessment(),
                  ),
                  _gap(),
                  _bar(
                    'Mortality Rate per 1,000 Population',
                    'Rate shown to two decimal places; chart values are ×100',
                    _rates(),
                    valueScale: 0.01,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _gap() => const SizedBox(height: 16);

  Widget _notice(String message) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFB74D).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: const Color(0xFFFFB74D).withValues(alpha: 0.35),
      ),
    ),
    child: Text(
      message,
      style: const TextStyle(
        color: _foreground,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  List<MapEntry<String, int>> _entries(
    Map<String, int> data, {
    bool sort = true,
    int limit = 7,
  }) {
    final entries = data.entries.where((e) => e.value > 0).toList();
    if (sort) entries.sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  Widget _card(String title, String subtitle, Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _accent.withValues(alpha: 0.20)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _foreground,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: _foreground.withValues(alpha: 0.58),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 18),
        child,
      ],
    ),
  );

  Widget _bar(
    String title,
    String subtitle,
    Map<String, int> data, {
    double valueScale = 1,
  }) {
    final entries = _entries(data);
    if (entries.isEmpty) return _card(title, subtitle, _empty());
    final maxY =
        entries.map((e) => e.value).reduce((a, b) => a > b ? a : b) + 1.0;
    return _card(
      title,
      subtitle,
      SizedBox(
        height: 285,
        child: BarChart(
          BarChartData(
            maxY: maxY,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: AppDesign.border),
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
                  reservedSize: 34,
                  getTitlesWidget: (value, meta) => Text(
                    (value * valueScale).toStringAsFixed(
                      valueScale == 1 ? 0 : 1,
                    ),
                    style: TextStyle(
                      color: _foreground.withValues(alpha: 0.55),
                      fontSize: 8,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 54,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= entries.length)
                      return const SizedBox();
                    return SideTitleWidget(
                      meta: meta,
                      space: 8,
                      child: SizedBox(
                        width: 52,
                        child: Text(
                          entries[index].key,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _foreground.withValues(alpha: 0.7),
                            fontSize: 8,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppDesign.surface,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final entry = entries[group.x.toInt()];
                  return BarTooltipItem(
                    '${entry.key}\n${(entry.value * valueScale).toStringAsFixed(valueScale == 1 ? 0 : 2)}',
                    const TextStyle(
                      color: _foreground,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
            ),
            barGroups: List.generate(
              entries.length,
              (index) => BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: entries[index].value.toDouble(),
                    width: entries.length > 5 ? 16 : 24,
                    color: _barPalette[index % _barPalette.length],
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          duration: const Duration(milliseconds: 600),
        ),
      ),
    );
  }

  Widget _line(String title, String subtitle, Map<String, int> data) {
    final entries = _entries(data, sort: false, limit: 12);
    final maxY = entries.isEmpty
        ? 1.0
        : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b) + 1.0;
    return _card(
      title,
      subtitle,
      SizedBox(
        height: 265,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: AppDesign.border),
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
                  getTitlesWidget: (value, meta) => Text(
                    '${value.toInt()}',
                    style: TextStyle(
                      color: _foreground.withValues(alpha: 0.55),
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 ||
                        index >= entries.length ||
                        value != index.toDouble())
                      return const SizedBox();
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        entries[index].key,
                        style: TextStyle(
                          color: _foreground.withValues(alpha: 0.65),
                          fontSize: 8,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: List.generate(
                  entries.length,
                  (i) => FlSpot(i.toDouble(), entries[i].value.toDouble()),
                ),
                isCurved: true,
                color: _accent,
                barWidth: 3,
                dotData: FlDotData(show: true),
                belowBarData: BarAreaData(
                  show: true,
                  color: _accent.withValues(alpha: 0.14),
                ),
              ),
            ],
          ),
          duration: const Duration(milliseconds: 600),
        ),
      ),
    );
  }

  Widget _pie(String title, String subtitle, Map<String, int> data) {
    final entries = _entries(data);
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    const colors = [
      Color(0xFF5EC7FF),
      Color(0xFFEC407A),
      Color(0xFFFFB74D),
      Color(0xFF66BB6A),
      Color(0xFF7E57C2),
    ];
    if (entries.isEmpty) return _card(title, subtitle, _empty());
    return _card(
      title,
      subtitle,
      Column(
        children: [
          SizedBox(
            height: 210,
            child: PieChart(
              PieChartData(
                centerSpaceRadius: 44,
                sectionsSpace: 3,
                sections: List.generate(
                  entries.length,
                  (index) => PieChartSectionData(
                    value: entries[index].value.toDouble(),
                    color: colors[index % colors.length],
                    radius: 62,
                    title:
                        '${(entries[index].value / total * 100).toStringAsFixed(0)}%',
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: List.generate(
              entries.length,
              (index) => Text(
                '● ${entries[index].key}: ${entries[index].value}',
                style: TextStyle(
                  color: colors[index % colors.length],
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heatmap() {
    final entries = _entries(_barangays());
    final maximum = entries.isEmpty ? 1 : entries.first.value;
    return _card(
      'Mortality Heatmap by Barangay',
      'Green indicates lower and red indicates higher concentration',
      entries.isEmpty
          ? _empty()
          : Column(
              children: entries.map((entry) {
                final color = Color.lerp(
                  const Color(0xFF43A047),
                  const Color(0xFFE53935),
                  entry.value / maximum,
                )!;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: color.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.location_on_rounded, color: color, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.key,
                          style: const TextStyle(color: _foreground),
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
              }).toList(),
            ),
    );
  }

  Widget _empty() => Text(
    'No data available.',
    style: TextStyle(color: _foreground.withValues(alpha: 0.6)),
  );
}
