import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/features/immunization/immunization_database_helper.dart';

const _aqua = Color(0xFF8ED7DA);
const _background = Color(0xFF0A1F24);
const _panel = Color(0xFF102A31);
const _text = Color(0xFFF1F1EE);
const _barPalette = <Color>[
  Color(0xFF8ED7DA),
  Color(0xFF5EC7FF),
  Color(0xFFFFB74D),
  Color(0xFFEC407A),
  Color(0xFF7E57C2),
  Color(0xFF66BB6A),
  Color(0xFFFF7043),
];

class ImmunizationAnalyticsPage extends StatefulWidget {
  const ImmunizationAnalyticsPage({super.key});

  @override
  State<ImmunizationAnalyticsPage> createState() =>
      _ImmunizationAnalyticsPageState();
}

class _ImmunizationAnalyticsPageState
    extends State<ImmunizationAnalyticsPage> {
  final _database = ImmunizationDatabaseHelper.instance;
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

  void _toggleDemoData() {
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

  String _v(Map<String, dynamic> record, String key) =>
      (record[key] ?? '').toString().trim();

  DateTime? _date(Map<String, dynamic> record, List<String> keys) {
    for (final key in keys) {
      final raw = _v(record, key);
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return null;
  }

  String _month(DateTime date) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return names[date.month - 1];
  }

  List<Map<String, dynamic>> _demoRecords() {
    final now = DateTime.now();
    const vaccines = ['BCG', 'Hepatitis B', 'Pentavalent', 'OPV', 'MMR'];
    const barangays = ['Central', 'San Isidro', 'Mabini', 'Rizal', 'Maligaya'];
    const events = ['', '', '', 'Fever', 'Swelling', 'Rash'];
    const statuses = [
      'Fully Immunized',
      'Fully Immunized',
      'Partially Immunized',
      'Not Yet Immunized',
    ];
    return List.generate(60, (index) {
      final administered = DateTime(
        now.year,
        now.month - index % 6,
        2 + index % 24,
      );
      final due = DateTime(
        now.year,
        now.month + (index % 5) - 2,
        3 + index % 23,
      );
      return <String, dynamic>{
        'id': 'demo-immunization-$index',
        'patientName': 'Demo Child ${index + 1}',
        'age': '${2 + index % 58} months',
        'vaccine': vaccines[index % vaccines.length],
        'administrationDate': administered.toIso8601String(),
        'nextDoseDueDate': due.toIso8601String(),
        'status': statuses[index % statuses.length],
        'barangay': barangays[index % barangays.length],
        'adverseEvents': events[index % events.length],
        'stockRemaining': 35 + (index * 13) % 120,
      };
    });
  }

  Map<String, int> _countBy(String key, {String fallback = 'Not specified'}) {
    final result = <String, int>{};
    for (final record in _records) {
      final value = _v(record, key);
      final label = value.isEmpty ? fallback : value;
      result[label] = (result[label] ?? 0) + 1;
    }
    return result;
  }

  Map<String, int> _monthly({bool upcoming = false}) {
    final now = DateTime.now();
    final result = <String, int>{};
    for (var i = 0; i < 6; i++) {
      final date = DateTime(now.year, now.month + (upcoming ? i : i - 5));
      result[_month(date)] = 0;
    }
    for (final record in _records) {
      final date = _date(
        record,
        upcoming
            ? const ['nextDoseDueDate']
            : const ['administrationDate', 'date'],
      );
      if (date != null && result.containsKey(_month(date))) {
        result[_month(date)] = result[_month(date)]! + 1;
      }
    }
    return result;
  }

  Map<String, int> _coverage() {
    final counts = _countBy('vaccine');
    final maximum = counts.values.isEmpty
        ? 1
        : counts.values.reduce((a, b) => a > b ? a : b);
    return counts.map(
      (key, value) => MapEntry(key, (value / maximum * 100).round()),
    );
  }

  Map<String, int> _status() {
    final result = <String, int>{
      'Fully Immunized': 0,
      'Partially Immunized': 0,
      'Not Yet Immunized': 0,
    };
    for (final record in _records) {
      final raw = _v(record, 'status').toLowerCase();
      final label = raw.contains('fully') || raw.contains('complete')
          ? 'Fully Immunized'
          : raw.contains('partial') || raw.contains('ongoing')
          ? 'Partially Immunized'
          : 'Not Yet Immunized';
      result[label] = result[label]! + 1;
    }
    return result;
  }

  Map<String, int> _missedByVaccine() {
    final now = DateTime.now();
    final result = <String, int>{};
    for (final record in _records) {
      final due = _date(record, const ['nextDoseDueDate']);
      if (due == null || !due.isBefore(now)) continue;
      final vaccine = _v(record, 'vaccine');
      result[vaccine] = (result[vaccine] ?? 0) + 1;
    }
    return result;
  }

  Map<String, int> _barangays() {
    final result = <String, int>{};
    for (final record in _records) {
      var value = _v(record, 'barangay');
      if (value.isEmpty) {
        value = _v(record, 'address').split(',').first.trim();
      }
      value = value.isEmpty ? 'Not specified' : value;
      result[value] = (result[value] ?? 0) + 1;
    }
    return result;
  }

  Map<String, int> _ages() {
    final result = <String, int>{
      '0-6 months': 0,
      '7-12 months': 0,
      '1-2 years': 0,
      '2-5 years': 0,
      'Unknown': 0,
    };
    for (final record in _records) {
      final raw = _v(record, 'age').toLowerCase();
      final number = int.tryParse(RegExp(r'\d+').firstMatch(raw)?.group(0) ?? '');
      final months = number == null
          ? null
          : raw.contains('year')
          ? number * 12
          : number;
      final label = months == null
          ? 'Unknown'
          : months <= 6
          ? '0-6 months'
          : months <= 12
          ? '7-12 months'
          : months <= 24
          ? '1-2 years'
          : '2-5 years';
      result[label] = result[label]! + 1;
    }
    return result;
  }

  Map<String, int> _overdue() {
    final now = DateTime.now();
    final result = <String, int>{
      '1 month overdue': 0,
      '2 months overdue': 0,
      '3+ months overdue': 0,
    };
    for (final record in _records) {
      final due = _date(record, const ['nextDoseDueDate']);
      if (due == null || !due.isBefore(now)) continue;
      final days = now.difference(due).inDays;
      final label = days <= 30
          ? '1 month overdue'
          : days <= 60
          ? '2 months overdue'
          : '3+ months overdue';
      result[label] = result[label]! + 1;
    }
    return result;
  }

  Map<String, int> _risk() {
    final result = <String, int>{'Low': 0, 'Medium': 0, 'High': 0};
    final now = DateTime.now();
    for (final record in _records) {
      final due = _date(record, const ['nextDoseDueDate']);
      final status = _v(record, 'status').toLowerCase();
      final overdueDays = due != null && due.isBefore(now)
          ? now.difference(due).inDays
          : 0;
      final label = overdueDays > 60 || status.contains('not yet')
          ? 'High'
          : overdueDays > 0 || status.contains('partial')
          ? 'Medium'
          : 'Low';
      result[label] = result[label]! + 1;
    }
    return result;
  }

  Map<String, int> _stock() {
    final vaccines = _countBy('vaccine').keys;
    final result = <String, int>{};
    for (final vaccine in vaccines) {
      final matching = _records.where((r) => _v(r, 'vaccine') == vaccine);
      final explicit = matching
          .map((r) => int.tryParse(_v(r, 'stockRemaining')))
          .whereType<int>()
          .toList();
      result[vaccine] = explicit.isEmpty
          ? (120 - matching.length).clamp(0, 120).toInt()
          : explicit.last;
    }
    return result;
  }

  Map<String, int> _aefi() {
    final result = <String, int>{};
    for (final record in _records) {
      final raw = _v(record, 'adverseEvents');
      if (raw.isEmpty || raw.toLowerCase().contains('none')) continue;
      for (final event in raw.split(RegExp(r'[,;]'))) {
        final label = event.trim();
        if (label.isNotEmpty) result[label] = (result[label] ?? 0) + 1;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: const Text(
          'Immunization Analytics',
          style: TextStyle(color: _text, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _toggleDemoData,
            tooltip: _demo ? 'Show real data' : 'Show dummy data',
            icon: Icon(
              _demo ? Icons.storage_rounded : Icons.science_rounded,
              color: _demo ? const Color(0xFFFFB74D) : _aqua,
            ),
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh analytics',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _aqua))
          : RefreshIndicator(
              onRefresh: _load,
              color: _aqua,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  if (_demo) _demoBanner(),
                  _linePanel(
                    'Monthly Immunizations Administered',
                    'Vaccination performance over the last six months',
                    _monthly(),
                  ),
                  _gap(),
                  _barPanel('Vaccine Coverage Rate', 'Relative coverage percentage by vaccine', _coverage(), suffix: '%'),
                  _gap(),
                  _piePanel('Fully vs Partially Immunized', 'Overall child immunization status', _status()),
                  _gap(),
                  _barPanel('Missed Vaccinations', 'Vaccines most frequently overdue', _missedByVaccine()),
                  _gap(),
                  _barPanel('Immunization by Barangay', 'Vaccination records across communities', _barangays()),
                  _gap(),
                  _barPanel('Age Distribution of Vaccinated Children', 'Vaccinated children grouped by age', _ages()),
                  _gap(),
                  _linePanel('Upcoming Vaccination Schedule', 'Children due over the coming six months', _monthly(upcoming: true)),
                  _gap(),
                  _barPanel('Overdue Immunizations', 'Children requiring immediate follow-up', _overdue()),
                  _gap(),
                  _barPanel('AI Immunization Risk Prediction', 'Predicted incomplete-immunization risk', _risk()),
                  _gap(),
                  _barPanel('Vaccine Stock Monitoring', 'Estimated remaining inventory by vaccine', _stock()),
                  _gap(),
                  _barPanel('Adverse Events Following Immunization', 'Reported AEFI cases', _aefi()),
                ],
              ),
            ),
    );
  }

  Widget _gap() => const SizedBox(height: 16);

  Widget _demoBanner() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFB74D).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFB74D).withValues(alpha: 0.35)),
        ),
        child: const Text(
          'Showing analytics demo data because no immunization records are available.',
          style: TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );

  List<MapEntry<String, int>> _entries(Map<String, int> data) {
    final values = data.entries.where((entry) => entry.value > 0).toList();
    return values.take(7).toList();
  }

  Widget _card(String title, String subtitle, Widget chart) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _aqua.withValues(alpha: 0.20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: _text.withValues(alpha: 0.58), fontSize: 11)),
            const SizedBox(height: 18),
            chart,
          ],
        ),
      );

  Widget _barPanel(String title, String subtitle, Map<String, int> data, {String suffix = ''}) {
    final entries = _entries(data);
    if (entries.isEmpty) return _card(title, subtitle, _empty());
    final maxY = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b) + 1.0;
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
              getDrawingHorizontalLine: (_) => FlLine(color: Colors.white.withValues(alpha: 0.08)),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (value, meta) => Text('${value.toInt()}$suffix', style: TextStyle(color: _text.withValues(alpha: 0.55), fontSize: 8)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 52,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= entries.length) return const SizedBox();
                    return SideTitleWidget(
                      meta: meta,
                      space: 8,
                      child: SizedBox(
                        width: 52,
                        child: Text(entries[index].key, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(color: _text.withValues(alpha: 0.70), fontSize: 8)),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => const Color(0xFF071A1F),
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final entry = entries[group.x.toInt()];
                  return BarTooltipItem('${entry.key}\n${entry.value}$suffix', const TextStyle(color: _text, fontWeight: FontWeight.bold));
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

  Widget _linePanel(String title, String subtitle, Map<String, int> data) {
    final entries = data.entries.toList();
    final maxY = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b) + 1.0;
    return _card(
      title,
      subtitle,
      SizedBox(
        height: 260,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY,
            gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.white.withValues(alpha: 0.08))),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (value, meta) => Text('${value.toInt()}', style: TextStyle(color: _text.withValues(alpha: 0.55), fontSize: 9)))),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= entries.length || value != index.toDouble()) return const SizedBox();
                return SideTitleWidget(meta: meta, child: Text(entries[index].key, style: TextStyle(color: _text.withValues(alpha: 0.70), fontSize: 9)));
              })),
            ),
            lineBarsData: [LineChartBarData(
              spots: List.generate(entries.length, (i) => FlSpot(i.toDouble(), entries[i].value.toDouble())),
              isCurved: true,
              color: _aqua,
              barWidth: 3,
              dotData: FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: _aqua.withValues(alpha: 0.14)),
            )],
          ),
          duration: const Duration(milliseconds: 600),
        ),
      ),
    );
  }

  Widget _piePanel(String title, String subtitle, Map<String, int> data) {
    final entries = _entries(data);
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    const colors = [Color(0xFF66BB6A), Color(0xFFFFB74D), Color(0xFFEF5350), Color(0xFF5EC7FF)];
    return _card(
      title,
      subtitle,
      Column(
        children: [
          SizedBox(
            height: 210,
            child: PieChart(PieChartData(
              centerSpaceRadius: 44,
              sectionsSpace: 3,
              sections: List.generate(entries.length, (index) {
                final entry = entries[index];
                return PieChartSectionData(
                  value: entry.value.toDouble(),
                  color: colors[index % colors.length],
                  radius: 62,
                  title: '${(entry.value / total * 100).toStringAsFixed(0)}%',
                  titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                );
              }),
            )),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: List.generate(entries.length, (index) => Text('● ${entries[index].key}: ${entries[index].value}', style: TextStyle(color: colors[index % colors.length], fontSize: 11, fontWeight: FontWeight.w600))),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Text('No data available.', style: TextStyle(color: _text.withValues(alpha: 0.60)));
}
