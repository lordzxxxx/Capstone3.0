import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/features/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

const _accent = AppDesign.blue;
const _bg = AppDesign.page;
const _panel = AppDesign.surface;
const _text = AppDesign.ink;
const _barPalette = <Color>[
  AppDesign.skyBlue,
  Color(0xFF5EC7FF),
  Color(0xFFFFB74D),
  Color(0xFFEC407A),
  Color(0xFF7E57C2),
  Color(0xFF66BB6A),
  Color(0xFFFF7043),
];

class CommunicableAnalyticsPage extends StatefulWidget {
  const CommunicableAnalyticsPage({super.key});

  @override
  State<CommunicableAnalyticsPage> createState() =>
      _CommunicableAnalyticsPageState();
}

class _CommunicableAnalyticsPageState extends State<CommunicableAnalyticsPage> {
  final _database = DatabaseHelper.instance;
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
      final all = await _database.getAllRecords();
      final records = all.where((row) {
        final type = (row['diseaseType'] ?? '').toString().toLowerCase();
        return type == 'communicable' || type == 'communicable disease';
      }).toList();
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

  DateTime? _date(Map<String, dynamic> row) =>
      DateTime.tryParse(_v(row, 'datetime')) ??
      DateTime.tryParse(_v(row, 'date'));

  List<Map<String, dynamic>> _demoRecords() {
    final now = DateTime.now();
    const diseases = [
      'Dengue',
      'Tuberculosis',
      'Influenza',
      'COVID-19',
      'Measles',
    ];
    const barangays = ['Central', 'San Isidro', 'Mabini', 'Rizal', 'Maligaya'];
    const statuses = ['Active', 'Recovered', 'Recovered', 'Recovered', 'Death'];
    const sexes = ['Male', 'Female'];
    const coverage = ['High', 'Medium', 'Low'];
    return List.generate(84, (index) {
      final date = DateTime(now.year, now.month - index % 12, 2 + index % 24);
      return <String, dynamic>{
        'id': 'demo-communicable-$index',
        'diseaseType': 'Communicable',
        'condition': diseases[index % diseases.length],
        'type': diseases[index % diseases.length],
        'patient': 'Demo Patient ${index + 1}',
        'datetime': date.toIso8601String(),
        'age': '${2 + (index * 5) % 78}',
        'gender': sexes[index % sexes.length],
        'status': statuses[index % statuses.length],
        'barangay': barangays[index % barangays.length],
        'address': '${barangays[index % barangays.length]}, Demo City',
        'vaccinationCoverage': coverage[index % coverage.length],
        'populationDensity': 800 + index % 5 * 450,
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

  String _disease(Map<String, dynamic> row) {
    for (final key in const ['condition', 'diagnosis', 'type', 'ai_category']) {
      final value = _v(row, key);
      if (value.isNotEmpty && value.toLowerCase() != 'communicable')
        return value;
    }
    return 'Not specified';
  }

  String _barangay(Map<String, dynamic> row) {
    final direct = _v(row, 'barangay');
    if (direct.isNotEmpty) return direct;
    final address = _v(row, 'address');
    return address.isEmpty ? 'Not specified' : address.split(',').first.trim();
  }

  Map<String, int> _group(String Function(Map<String, dynamic>) label) {
    final result = <String, int>{};
    for (final row in _records) {
      final value = label(row);
      result[value] = (result[value] ?? 0) + 1;
    }
    return result;
  }

  Map<String, int> _ages() => _group((row) {
    final age = int.tryParse(_v(row, 'age'));
    return age == null
        ? 'Unknown'
        : age <= 5
        ? '0-5'
        : age <= 17
        ? '6-17'
        : age <= 44
        ? '18-44'
        : age <= 64
        ? '45-64'
        : '65+';
  });

  Map<String, int> _sex() => _group((row) {
    final value = _v(row, 'gender').isNotEmpty
        ? _v(row, 'gender')
        : _v(row, 'sex');
    return value.isEmpty ? 'Not specified' : value;
  });

  Map<String, int> _weekly() {
    final now = DateTime.now();
    final result = <String, int>{for (var i = 1; i <= 8; i++) 'Week $i': 0};
    for (final row in _records) {
      final date = _date(row);
      if (date == null) continue;
      final days = now.difference(date).inDays;
      if (days < 0 || days >= 56) continue;
      final week = 8 - (days ~/ 7);
      result['Week $week'] = result['Week $week']! + 1;
    }
    return result;
  }

  Map<String, int> _outcomes() => _group((row) {
    final status =
        (_v(row, 'currentStatus').isNotEmpty
                ? _v(row, 'currentStatus')
                : _v(row, 'status'))
            .toLowerCase();
    return status.contains('recover') || status.contains('complete')
        ? 'Recovered'
        : status.contains('death') || status.contains('deceased')
        ? 'Death'
        : 'Active';
  });

  Map<String, int> _outbreakRisk() {
    final cases = _group(_barangay);
    final result = <String, int>{'Low': 0, 'Moderate': 0, 'High': 0};
    if (cases.isEmpty) return result;
    final maxCases = cases.values.reduce((a, b) => a > b ? a : b);
    for (final count in cases.values) {
      final ratio = count / maxCases;
      final label = ratio >= 0.75
          ? 'High'
          : ratio >= 0.40
          ? 'Moderate'
          : 'Low';
      result[label] = result[label]! + 1;
    }
    return result;
  }

  Map<String, int> _coverageCases() => _group((row) {
    final coverage = _v(row, 'vaccinationCoverage');
    return coverage.isEmpty ? 'Not recorded' : coverage;
  });

  Map<String, int> _seasonal() => _group((row) {
    final month = _date(row)?.month;
    return month == null
        ? 'Unknown'
        : month >= 6 && month <= 11
        ? 'Rainy'
        : 'Dry';
  });

  @override
  Widget build(BuildContext context) {
    final diseases = _group(_disease);
    final barangays = _group(_barangay);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: const Text(
          'Communicable Analytics',
          style: TextStyle(color: _text, fontWeight: FontWeight.bold),
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
                  if (_demo) _notice(),
                  _line(
                    'Monthly Communicable Disease Cases',
                    'Reported cases during the last 12 months',
                    _monthly(),
                  ),
                  _gap(),
                  _bar(
                    'Cases by Disease Type',
                    'Most frequently reported communicable diseases',
                    diseases,
                  ),
                  _gap(),
                  _bar(
                    'Cases by Barangay',
                    'Communities with the highest reported burden',
                    barangays,
                  ),
                  _gap(),
                  _pie(
                    'Disease Distribution',
                    'Proportion of cases by disease',
                    diseases,
                  ),
                  _gap(),
                  _bar(
                    'Age Distribution of Cases',
                    'Cases grouped by patient age',
                    _ages(),
                  ),
                  _gap(),
                  _pie(
                    'Cases by Sex',
                    'Gender distribution among reported cases',
                    _sex(),
                  ),
                  _gap(),
                  _line(
                    'Weekly Disease Trend',
                    'Eight-week view for faster outbreak detection',
                    _weekly(),
                  ),
                  _gap(),
                  _bar(
                    'Recovery vs Active vs Death',
                    'Current communicable-disease outcomes',
                    _outcomes(),
                  ),
                  _gap(),
                  _bar(
                    'AI Outbreak Risk Prediction',
                    'Population-level barangay outbreak risk for planning',
                    _outbreakRisk(),
                  ),
                  _gap(),
                  _heatmap(barangays),
                  _gap(),
                  _bar(
                    'Vaccination vs Disease Cases',
                    'Cases grouped by recorded vaccine coverage',
                    _coverageCases(),
                  ),
                  _gap(),
                  _bar(
                    'Seasonal Disease Analysis',
                    'Reported cases during dry and rainy seasons',
                    _seasonal(),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _gap() => const SizedBox(height: 16);

  Widget _notice() => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFB74D).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: const Color(0xFFFFB74D).withValues(alpha: 0.35),
      ),
    ),
    child: const Text(
      'Showing demo communicable-disease data for analytics.',
      style: TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w600),
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
      color: _panel,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _accent.withValues(alpha: 0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _text,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(color: _text.withValues(alpha: 0.58), fontSize: 11),
        ),
        const SizedBox(height: 18),
        child,
      ],
    ),
  );

  Widget _bar(String title, String subtitle, Map<String, int> data) {
    final entries = _entries(data);
    if (entries.isEmpty) return _card(title, subtitle, _empty());
    final maxY =
        entries.map((e) => e.value).reduce((a, b) => a > b ? a : b) + 1.0;
    return _card(
      title,
      subtitle,
      SizedBox(
        height: 280,
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
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) => Text(
                    '${value.toInt()}',
                    style: TextStyle(
                      color: _text.withValues(alpha: 0.55),
                      fontSize: 9,
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
                            color: _text.withValues(alpha: 0.7),
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
                    '${entry.key}\n${entry.value}',
                    const TextStyle(color: _text, fontWeight: FontWeight.bold),
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
        height: 260,
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
                      color: _text.withValues(alpha: 0.55),
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
                          color: _text.withValues(alpha: 0.65),
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
    if (entries.isEmpty) return _card(title, subtitle, _empty());
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    const colors = [
      Color(0xFF5EC7FF),
      Color(0xFFEC407A),
      Color(0xFFFFB74D),
      Color(0xFF66BB6A),
      Color(0xFF7E57C2),
    ];
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

  Widget _heatmap(Map<String, int> data) {
    final entries = _entries(data);
    final maximum = entries.isEmpty ? 1 : entries.first.value;
    return _card(
      'Heat Map of Disease Cases',
      'Green indicates lower and red indicates higher intensity',
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
                          style: const TextStyle(color: _text),
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
    style: TextStyle(color: _text.withValues(alpha: 0.6)),
  );
}
