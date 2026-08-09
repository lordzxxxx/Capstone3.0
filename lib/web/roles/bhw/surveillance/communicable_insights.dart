import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

const _accent = Color(0xFF2F80ED);
const _panel = Color(0xFF0D274D);
const _foreground = Color(0xFFF5F5F5);
const _palette = <Color>[
  Color(0xFF2F80ED),
  Color(0xFF5EC7FF),
  Color(0xFFFFB74D),
  Color(0xFF66BB6A),
  Color(0xFFEC407A),
  Color(0xFF7E57C2),
];

/// Analytics calculated exclusively from the communicable records supplied by
/// the parent records page. No demo or fallback values are generated here.
class CommunicableInsights extends StatelessWidget {
  const CommunicableInsights({
    super.key,
    required this.records,
    this.caseLabel = 'Communicable',
  });

  final List<Map<String, dynamic>> records;
  final String caseLabel;

  @override
  Widget build(BuildContext context) {
    final normalizedCaseLabel = caseLabel.toLowerCase();
    final monthly = _monthlyCases();
    final diseaseGroups = _groupedBy(_disease);
    final diseases = diseaseGroups.take(7).toList(growable: false);
    final statuses = _groupedBy(_status);
    final ages = _ageDistribution();
    final barangays = _groupedBy(_barangay).take(7).toList(growable: false);
    final active = records
        .where((record) => _status(record) == 'Active')
        .length;
    final recovered = records
        .where((record) => _status(record) == 'Recovered')
        .length;
    final followUps = records.where(_needsFollowUp).length;
    final recoveryRate = records.isEmpty
        ? 0
        : (recovered / records.length * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _metricGrid(
          context,
          items: [
            _Metric(
              'Total Cases',
              '${records.length}',
              Icons.coronavirus_rounded,
              _accent,
            ),
            _Metric(
              'Active Cases',
              '$active',
              Icons.monitor_heart_outlined,
              const Color(0xFFFFB74D),
            ),
            _Metric(
              'Recovered',
              '$recovered',
              Icons.health_and_safety_outlined,
              const Color(0xFF66BB6A),
            ),
            _Metric(
              'Recovery Rate',
              '$recoveryRate%',
              Icons.trending_up_rounded,
              const Color(0xFF5EC7FF),
            ),
            _Metric(
              'Disease Types',
              '${diseaseGroups.length}',
              Icons.biotech_outlined,
              const Color(0xFF7E57C2),
            ),
            _Metric(
              'Follow-ups Due',
              '$followUps',
              Icons.event_repeat_rounded,
              const Color(0xFFEC407A),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _chartGrid(
          context,
          charts: [
            _chartCard(
              title: 'Monthly $caseLabel Cases',
              subtitle: 'Cases recorded during the latest six-month period',
              icon: Icons.show_chart_rounded,
              child: _lineChart(monthly),
            ),
            _chartCard(
              title: 'Cases by Disease',
              subtitle:
                  'Most frequently recorded $normalizedCaseLabel conditions',
              icon: Icons.bar_chart_rounded,
              child: _barChart(
                diseases,
                emptyMessage: 'Disease information has not been recorded yet.',
              ),
            ),
            _chartCard(
              title: 'Case Status Distribution',
              subtitle: 'Active, recovered, and other recorded case outcomes',
              icon: Icons.pie_chart_outline_rounded,
              child: _pieChart(statuses),
            ),
            _chartCard(
              title: 'Patient Age Distribution',
              subtitle: '$caseLabel cases grouped by patient age',
              icon: Icons.groups_2_outlined,
              child: _barChart(
                ages,
                emptyMessage: 'Valid patient ages have not been recorded yet.',
              ),
            ),
            _chartCard(
              title: 'Cases by Barangay',
              subtitle: 'Recorded $normalizedCaseLabel cases by barangay',
              icon: Icons.location_on_outlined,
              child: _barChart(
                barangays,
                emptyMessage: 'Barangay information has not been recorded yet.',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metricGrid(BuildContext context, {required List<_Metric> items}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1180
            ? 3
            : constraints.maxWidth >= 680
            ? 2
            : 1;
        const spacing = 14.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _panel,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: item.color.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: item.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(item.icon, color: item.color, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.value,
                                style: const TextStyle(
                                  color: _foreground,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.label,
                                style: TextStyle(
                                  color: _foreground.withValues(alpha: 0.62),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }

  Widget _chartGrid(BuildContext context, {required List<Widget> charts}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980 ? 2 : 1;
        const spacing = 16.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: charts
              .map((chart) => SizedBox(width: width, child: chart))
              .toList(growable: false),
        );
      },
    );
  }

  Widget _chartCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      height: 360,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _accent, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _foreground.withValues(alpha: 0.58),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _lineChart(List<MapEntry<String, int>> entries) {
    final maxY = _chartMax(entries.map((entry) => entry.value));
    final interval = math.max(1, (maxY / 4).ceil()).toDouble();
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (entries.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withValues(alpha: 0.08),
            strokeWidth: 1,
          ),
        ),
        titlesData: _titles(
          entries.map((entry) => entry.key).toList(growable: false),
          interval,
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF163B66),
            getTooltipItems: (spots) => spots
                .map(
                  (spot) => LineTooltipItem(
                    '${entries[spot.x.toInt()].key}\n${spot.y.toInt()} case${spot.y == 1 ? '' : 's'}',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            color: _accent,
            barWidth: 3,
            spots: List.generate(
              entries.length,
              (index) =>
                  FlSpot(index.toDouble(), entries[index].value.toDouble()),
            ),
            dotData: FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: _accent.withValues(alpha: 0.14),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 450),
    );
  }

  Widget _barChart(
    List<MapEntry<String, int>> entries, {
    required String emptyMessage,
  }) {
    final visible = entries.where((entry) => entry.value > 0).toList();
    if (visible.isEmpty) return _empty(emptyMessage);
    final maxY = _chartMax(visible.map((entry) => entry.value));
    final interval = math.max(1, (maxY / 4).ceil()).toDouble();
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.white.withValues(alpha: 0.08)),
        ),
        titlesData: _titles(
          visible
              .map((entry) => _shortLabel(entry.key))
              .toList(growable: false),
          interval,
          bottomReservedSize: 48,
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF163B66),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final entry = visible[group.x];
              return BarTooltipItem(
                '${entry.key}\n${entry.value} case${entry.value == 1 ? '' : 's'}',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
        ),
        barGroups: List.generate(
          visible.length,
          (index) => BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: visible[index].value.toDouble(),
                width: visible.length > 5 ? 18 : 26,
                gradient: const LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xFF008895), Color(0xFF35D4DE)],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
            ],
          ),
        ),
      ),
      duration: const Duration(milliseconds: 450),
    );
  }

  Widget _pieChart(List<MapEntry<String, int>> entries) {
    final visible = entries.where((entry) => entry.value > 0).toList();
    if (visible.isEmpty) {
      return _empty('Case status information has not been recorded yet.');
    }
    final total = visible.fold<int>(0, (sum, entry) => sum + entry.value);
    return Column(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 42,
              sectionsSpace: 3,
              sections: List.generate(
                visible.length,
                (index) => PieChartSectionData(
                  value: visible[index].value.toDouble(),
                  color: _palette[index % _palette.length],
                  radius: 62,
                  title:
                      '${(visible[index].value / total * 100).toStringAsFixed(0)}%',
                  titleStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            duration: const Duration(milliseconds: 450),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: List.generate(
            visible.length,
            (index) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _palette[index % _palette.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '${visible[index].key}: ${visible[index].value}',
                  style: TextStyle(
                    color: _foreground.withValues(alpha: 0.75),
                    fontSize: 10.5,
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

  FlTitlesData _titles(
    List<String> labels,
    double interval, {
    double bottomReservedSize = 34,
  }) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 30,
          interval: interval,
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
          reservedSize: bottomReservedSize,
          interval: 1,
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (index < 0 ||
                index >= labels.length ||
                value != index.toDouble()) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              meta: meta,
              space: 8,
              child: SizedBox(
                width: 58,
                child: Text(
                  labels[index],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _foreground.withValues(alpha: 0.65),
                    fontSize: 9,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<MapEntry<String, int>> _monthlyCases() {
    final now = DateTime.now();
    final months = List.generate(
      6,
      (index) => DateTime(now.year, now.month - 5 + index),
    );
    return months
        .map((month) {
          final count = records.where((record) {
            final date = _date(record);
            return date != null &&
                date.year == month.year &&
                date.month == month.month;
          }).length;
          return MapEntry(_monthLabel(month), count);
        })
        .toList(growable: false);
  }

  List<MapEntry<String, int>> _groupedBy(
    String Function(Map<String, dynamic>) labelFor,
  ) {
    final counts = <String, int>{};
    for (final record in records) {
      final label = labelFor(record);
      counts[label] = (counts[label] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount == 0 ? a.key.compareTo(b.key) : byCount;
      });
    return entries;
  }

  List<MapEntry<String, int>> _ageDistribution() {
    final counts = <String, int>{
      '0-5': 0,
      '6-17': 0,
      '18-44': 0,
      '45-64': 0,
      '65+': 0,
    };
    for (final record in records) {
      final match = RegExp(r'\d+').firstMatch(_value(record, 'age'));
      final age = match == null ? null : int.tryParse(match.group(0)!);
      if (age == null || age < 0 || age > 130) continue;
      final range = age <= 5
          ? '0-5'
          : age <= 17
          ? '6-17'
          : age <= 44
          ? '18-44'
          : age <= 64
          ? '45-64'
          : '65+';
      counts[range] = counts[range]! + 1;
    }
    return counts.entries.toList(growable: false);
  }

  String _disease(Map<String, dynamic> record) {
    for (final key in const ['condition', 'diagnosis', 'type', 'ai_category']) {
      final value = _value(record, key);
      final normalized = value.toLowerCase();
      const classificationLabels = {
        'communicable',
        'communicable disease',
        'non-communicable',
        'non communicable',
        'non-communicable disease',
      };
      if (value.isNotEmpty && !classificationLabels.contains(normalized)) {
        return value;
      }
    }
    return 'Not specified';
  }

  String _status(Map<String, dynamic> record) {
    final raw = _value(
      record,
      'currentStatus',
      fallback: _value(record, 'status'),
    ).toLowerCase();
    if (raw.contains('recover') || raw.contains('complete')) return 'Recovered';
    if (raw.contains('death') || raw.contains('deceased')) return 'Deceased';
    if (raw.contains('pending') || raw.contains('review')) return 'Pending';
    return 'Active';
  }

  String _barangay(Map<String, dynamic> record) {
    final direct = _value(record, 'barangay');
    if (direct.isNotEmpty) return direct;
    final address = _value(record, 'address');
    if (address.isEmpty) return 'Not specified';
    return address.split(',').first.trim();
  }

  bool _needsFollowUp(Map<String, dynamic> record) {
    final status = _status(record);
    if (status == 'Recovered' || status == 'Deceased') return false;
    final nextVisit =
        _dateFromValue(record['nextVisit']) ??
        _dateFromValue(record['followup']);
    return nextVisit != null &&
        !nextVisit.isAfter(DateTime.now().add(const Duration(days: 7)));
  }

  DateTime? _date(Map<String, dynamic> record) {
    for (final key in const [
      'datetime',
      'date',
      'lastVisit',
      'createdAt',
      'updatedAt',
    ]) {
      final parsed = _dateFromValue(record[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  DateTime? _dateFromValue(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    try {
      final dynamic converted = raw.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      // The value is not a Firestore Timestamp.
    }
    final value = raw.toString().trim();
    if (value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  String _value(
    Map<String, dynamic> record,
    String key, {
    String fallback = '',
  }) {
    final value = record[key]?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
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
    return months[date.month - 1];
  }

  String _shortLabel(String value) {
    final trimmed = value.trim();
    return trimmed.length <= 12 ? trimmed : '${trimmed.substring(0, 10)}...';
  }

  double _chartMax(Iterable<int> values) {
    final largest = values.fold<int>(0, math.max);
    return math
        .max(4, largest + math.max(1, (largest * 0.25).ceil()))
        .toDouble();
  }

  Widget _empty(String message) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _foreground.withValues(alpha: 0.55),
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon, this.color);

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}
