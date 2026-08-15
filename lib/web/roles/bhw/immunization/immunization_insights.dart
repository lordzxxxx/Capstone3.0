import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/shared/widgets/spring_data_motion.dart';

const _aqua = Color(0xFF2F80ED);
const _panel = Colors.white;
const _text = Color(0xFF0B1F3A);
const _muted = Color(0xFF4B6075);
const _palette = <Color>[
  Color(0xFF2F80ED),
  Color(0xFF163B66),
  Color(0xFF5B8CC9),
  Color(0xFF6F9DCE),
  Color(0xFF8FAFD6),
  Color(0xFFB8C9DB),
  Color(0xFF1F5A91),
  Color(0xFF2F80ED),
];

class ImmunizationInsights extends StatelessWidget {
  const ImmunizationInsights({super.key, required this.records});

  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) {
    final monthly = _monthlyAdministered();
    final coverage = _coverageRate();
    final status = _immunizationStatus();
    final ages = _ageDistribution();
    final upcoming = _upcomingSchedule();
    final overdue = _overdueByVaccine();
    final stock = _stockMonitoring();
    final adverseEvents = _adverseEvents();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _metricGrid(context),
        const SizedBox(height: 20),
        _responsiveChartGrid(
          context,
          charts: [
            _chartCard(
              title: 'Monthly Immunizations Administered',
              subtitle:
                  'Recorded vaccine administrations during the last six months',
              icon: Icons.show_chart_rounded,
              child: _lineChart(monthly, unit: 'dose'),
            ),
            _chartCard(
              title: 'Vaccine Coverage Rate',
              subtitle:
                  'Completed records as a percentage of saved records per vaccine',
              icon: Icons.bar_chart_rounded,
              child: _barChart(
                coverage,
                emptyMessage:
                    'Coverage appears after vaccine records are saved.',
                unit: '%',
                percentageScale: true,
              ),
            ),
            _chartCard(
              title: 'Fully vs Partially Immunized',
              subtitle:
                  'Completion status represented by the saved immunization records',
              icon: Icons.pie_chart_outline_rounded,
              child: _pieChart(status),
            ),
            _chartCard(
              title: 'Age Distribution of Vaccinated Children',
              subtitle: 'Children with recorded vaccinations grouped by age',
              icon: Icons.groups_2_outlined,
              child: _barChart(
                ages,
                emptyMessage:
                    'Age distribution appears after valid ages are saved.',
                unit: 'child',
              ),
            ),
            _chartCard(
              title: 'Upcoming Vaccination Schedule',
              subtitle: 'Next doses due over the coming six months',
              icon: Icons.event_available_outlined,
              child: _lineChart(upcoming, unit: 'appointment'),
            ),
            _chartCard(
              title: 'Overdue Immunizations',
              subtitle: 'Past-due next doses grouped by vaccine',
              icon: Icons.notification_important_outlined,
              child: _barChart(
                overdue,
                emptyMessage: 'No overdue next-dose schedules were found.',
                unit: 'overdue record',
                colors: const [Color(0xFF163B66), Color(0xFF2F80ED)],
              ),
            ),
            _chartCard(
              title: 'Vaccine Stock Monitoring',
              subtitle: stock.hasExplicitStock
                  ? 'Latest saved stock quantity for each vaccine'
                  : 'Recorded administered doses by vaccine for inventory planning',
              icon: Icons.inventory_2_outlined,
              child: _barChart(
                stock.entries,
                emptyMessage:
                    'Stock or vaccine-utilization data is not available yet.',
                unit: stock.hasExplicitStock ? 'dose in stock' : 'dose used',
                colors: const [Color(0xFF163B66), Color(0xFF8FAFD6)],
              ),
            ),
            _chartCard(
              title: 'Adverse Events Following Immunization',
              subtitle:
                  'Reported post-immunization events grouped by event type',
              icon: Icons.health_and_safety_outlined,
              child: _barChart(
                adverseEvents,
                emptyMessage: 'No adverse events have been reported.',
                unit: 'report',
                colors: const [Color(0xFF5B8CC9), Color(0xFFB8C9DB)],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metricGrid(BuildContext context) {
    final now = DateTime.now();
    final completedCount = records.where(_isCompleted).length;
    final scheduledCount = records.where((record) {
      final status = _value(record, 'status').toLowerCase();
      final due = _date(record, const ['nextDoseDueDate']);
      return status.contains('scheduled') ||
          status.contains('pending') ||
          status == 'due' ||
          (due != null && !due.isBefore(_startOfDay(now)));
    }).length;

    final cards = <Widget>[
      _metricCard(
        'Total Records',
        records.length,
        Icons.vaccines_rounded,
        _aqua,
      ),
      _metricCard(
        'Completed',
        completedCount,
        Icons.check_circle_outline_rounded,
        const Color(0xFF163B66),
      ),
      _metricCard(
        'Scheduled',
        scheduledCount,
        Icons.schedule_rounded,
        const Color(0xFF5B8CC9),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        const gap = 14.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: cards
              .map((card) => SizedBox(width: width, child: card))
              .toList(),
        );
      },
    );
  }

  Widget _metricCard(String label, int value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value.toString(),
                  style: const TextStyle(
                    color: _text,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _responsiveChartGrid(
    BuildContext context, {
    required List<Widget> charts,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980 ? 2 : 1;
        const gap = 20.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
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
      height: 370,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _aqua.withValues(alpha: 0.18)),
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
                  color: _aqua.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _aqua, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(color: _muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SpringDataMotion(dataKey: child, child: child),
          ),
        ],
      ),
    );
  }

  List<MapEntry<String, int>> _monthlyAdministered() {
    final months = _monthRange(past: true);
    return months
        .map((month) {
          final count = records.where((record) {
            final date = _date(record, const [
              'administrationDate',
              'date',
              'createdAt',
            ]);
            return date != null &&
                date.year == month.year &&
                date.month == month.month;
          }).length;
          return MapEntry(_monthLabel(month), count);
        })
        .toList(growable: false);
  }

  List<MapEntry<String, int>> _coverageRate() {
    final totals = <String, int>{};
    final completed = <String, int>{};
    for (final record in records) {
      final vaccine = _value(record, 'vaccine', fallback: 'Not specified');
      totals[vaccine] = (totals[vaccine] ?? 0) + 1;
      if (_isCompleted(record)) {
        completed[vaccine] = (completed[vaccine] ?? 0) + 1;
      }
    }
    final entries = totals.entries
        .map(
          (entry) => MapEntry(
            entry.key,
            ((completed[entry.key] ?? 0) / entry.value * 100).round(),
          ),
        )
        .toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries.take(8).toList(growable: false);
  }

  List<MapEntry<String, int>> _immunizationStatus() {
    var fully = 0;
    var partially = 0;
    for (final record in records) {
      if (_isCompleted(record)) {
        fully++;
      } else {
        partially++;
      }
    }
    return [
      MapEntry('Fully immunized', fully),
      MapEntry('Partially immunized', partially),
    ];
  }

  List<MapEntry<String, int>> _ageDistribution() {
    final counts = <String, int>{
      '0-6 mo': 0,
      '7-12 mo': 0,
      '1-2 yr': 0,
      '3-5 yr': 0,
      '6+ yr': 0,
    };
    for (final record in records) {
      final raw = _value(record, 'age').toLowerCase();
      final match = RegExp(r'\d+').firstMatch(raw);
      final number = match == null ? null : int.tryParse(match.group(0)!);
      if (number == null || number < 0) continue;
      final months = raw.contains('month') ? number : number * 12;
      final label = months <= 6
          ? '0-6 mo'
          : months <= 12
          ? '7-12 mo'
          : months <= 24
          ? '1-2 yr'
          : months <= 60
          ? '3-5 yr'
          : '6+ yr';
      counts[label] = counts[label]! + 1;
    }
    return counts.entries
        .where((entry) => entry.value > 0)
        .toList(growable: false);
  }

  List<MapEntry<String, int>> _upcomingSchedule() {
    final months = _monthRange(past: false);
    final today = _startOfDay(DateTime.now());
    return months
        .map((month) {
          final count = records.where((record) {
            final due = _date(record, const ['nextDoseDueDate']);
            return due != null &&
                !due.isBefore(today) &&
                due.year == month.year &&
                due.month == month.month;
          }).length;
          return MapEntry(_monthLabel(month), count);
        })
        .toList(growable: false);
  }

  List<MapEntry<String, int>> _overdueByVaccine() {
    final counts = <String, int>{};
    for (final record in records.where(_isOverdue)) {
      final vaccine = _value(record, 'vaccine', fallback: 'Not specified');
      counts[vaccine] = (counts[vaccine] ?? 0) + 1;
    }
    return _sortedEntries(counts);
  }

  _StockSeries _stockMonitoring() {
    const stockKeys = [
      'stockRemaining',
      'stockQuantity',
      'currentStock',
      'stock',
    ];
    final explicit = <String, int>{};
    final utilization = <String, int>{};
    for (final record in records) {
      final vaccine = _value(record, 'vaccine', fallback: 'Not specified');
      utilization[vaccine] = (utilization[vaccine] ?? 0) + 1;
      for (final key in stockKeys) {
        final value = int.tryParse(_value(record, key));
        if (value != null && value >= 0) {
          explicit[vaccine] = value;
          break;
        }
      }
    }
    return _StockSeries(
      entries: _sortedEntries(explicit.isNotEmpty ? explicit : utilization),
      hasExplicitStock: explicit.isNotEmpty,
    );
  }

  List<MapEntry<String, int>> _adverseEvents() {
    final counts = <String, int>{};
    const ignored = {'', 'none', 'none reported', 'no', 'n/a', 'na'};
    for (final record in records) {
      final raw = _value(record, 'adverseEvents');
      for (final part in raw.split(RegExp(r'[,;|\n]+'))) {
        final event = part.trim();
        if (ignored.contains(event.toLowerCase())) continue;
        final label = _titleCase(event);
        counts[label] = (counts[label] ?? 0) + 1;
      }
    }
    return _sortedEntries(counts);
  }

  bool _isCompleted(Map<String, dynamic> record) {
    final status = _value(record, 'status').toLowerCase();
    return status.contains('complete') ||
        status.contains('fully') ||
        status.contains('administered');
  }

  bool _isOverdue(Map<String, dynamic> record) {
    final status = _value(record, 'status').toLowerCase();
    if (status.contains('overdue') || status.contains('missed')) return true;
    final due = _date(record, const ['nextDoseDueDate']);
    return due != null && due.isBefore(_startOfDay(DateTime.now()));
  }

  List<DateTime> _monthRange({required bool past}) {
    final now = DateTime.now();
    return List.generate(6, (index) {
      final offset = past ? index - 5 : index;
      return DateTime(now.year, now.month + offset);
    });
  }

  DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime? _date(Map<String, dynamic> record, List<String> keys) {
    for (final key in keys) {
      final raw = record[key];
      if (raw == null) continue;
      if (raw is DateTime) return raw;
      try {
        final dynamic converted = raw.toDate();
        if (converted is DateTime) return converted;
      } catch (_) {
        // Cached web records normally store dates as ISO-8601 strings.
      }
      final parsed = DateTime.tryParse(raw.toString().trim());
      if (parsed != null) return parsed;
    }
    return null;
  }

  String _value(
    Map<String, dynamic> record,
    String key, {
    String fallback = '',
  }) {
    final value = record[key]?.toString().trim() ?? '';
    return value.isEmpty || value.toLowerCase() == 'null' ? fallback : value;
  }

  String _monthLabel(DateTime date) {
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
    return '${names[date.month - 1]} ${date.year % 100}';
  }

  String _titleCase(String value) {
    return value
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  List<MapEntry<String, int>> _sortedEntries(Map<String, int> values) {
    final entries = values.entries.toList()
      ..sort((a, b) {
        final countOrder = b.value.compareTo(a.value);
        return countOrder != 0 ? countOrder : a.key.compareTo(b.key);
      });
    return entries.take(8).toList(growable: false);
  }

  Widget _lineChart(
    List<MapEntry<String, int>> entries, {
    required String unit,
  }) {
    if (entries.isEmpty) return _empty('No timeline data is available yet.');
    final maxY = _maxY(entries.map((entry) => entry.value));
    final interval = math.max(1, (maxY / 4).ceil()).toDouble();
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(0, entries.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: _grid(interval),
        titlesData: _titles(
          entries.map((entry) => entry.key).toList(),
          interval,
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF163B66),
            getTooltipItems: (spots) => spots.map((spot) {
              final entry = entries[spot.x.toInt()];
              return LineTooltipItem(
                '${entry.key}\n${entry.value} $unit${entry.value == 1 ? '' : 's'}',
                const TextStyle(color: _text, fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              entries.length,
              (index) =>
                  FlSpot(index.toDouble(), entries[index].value.toDouble()),
            ),
            isCurved: true,
            color: _aqua,
            barWidth: 3,
            dotData: FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: _aqua.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 500),
    );
  }

  Widget _barChart(
    List<MapEntry<String, int>> entries, {
    required String emptyMessage,
    required String unit,
    bool percentageScale = false,
    List<Color> colors = const [_aqua, Color(0xFF163B66)],
  }) {
    final visible = entries.where((entry) => entry.value > 0).toList();
    if (visible.isEmpty) return _empty(emptyMessage);
    final maxY = percentageScale
        ? 100.0
        : _maxY(visible.map((entry) => entry.value));
    final interval = percentageScale
        ? 25.0
        : math.max(1, (maxY / 4).ceil()).toDouble();
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: _grid(interval),
        titlesData: _titles(
          visible.map((entry) => _shortLabel(entry.key)).toList(),
          interval,
          suffix: percentageScale ? '%' : '',
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF163B66),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final entry = visible[group.x];
              final value = percentageScale
                  ? '${entry.value}%'
                  : '${entry.value}';
              return BarTooltipItem(
                '${entry.key}\n$value $unit${entry.value == 1 || percentageScale ? '' : 's'}',
                const TextStyle(color: _text, fontWeight: FontWeight.w600),
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
                width: visible.length > 6 ? 16 : 24,
                color: colors[index % colors.length],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
            ],
          ),
        ),
      ),
      duration: const Duration(milliseconds: 500),
    );
  }

  Widget _pieChart(List<MapEntry<String, int>> entries) {
    final visible = entries.where((entry) => entry.value > 0).toList();
    final total = visible.fold<int>(0, (sum, entry) => sum + entry.value);
    if (total == 0) {
      return _empty('Immunization completion data is not available yet.');
    }
    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 48,
              sectionsSpace: 3,
              sections: List.generate(visible.length, (index) {
                final entry = visible[index];
                return PieChartSectionData(
                  value: entry.value.toDouble(),
                  color: _palette[index % _palette.length],
                  radius: 68,
                  title: '${(entry.value / total * 100).round()}%',
                  titleStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }),
            ),
            duration: const Duration(milliseconds: 500),
          ),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(visible.length, (index) {
              final entry = visible[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _palette[index % _palette.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${entry.key}: ${entry.value}',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  double _maxY(Iterable<int> values) {
    final largest = values.fold<int>(0, math.max);
    return math
        .max(4, largest + math.max(1, (largest * 0.25).ceil()))
        .toDouble();
  }

  FlGridData _grid(double interval) {
    return FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: interval,
      getDrawingHorizontalLine: (_) =>
          FlLine(color: const Color(0xFFD9E5F2), strokeWidth: 1),
    );
  }

  FlTitlesData _titles(
    List<String> labels,
    double interval, {
    String suffix = '',
  }) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 38,
          interval: interval,
          getTitlesWidget: (value, _) => Text(
            '${value.toInt()}$suffix',
            style: const TextStyle(color: _muted, fontSize: 9),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 48,
          interval: 1,
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (value != index.toDouble() ||
                index < 0 ||
                index >= labels.length) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              meta: meta,
              space: 8,
              child: SizedBox(
                width: 64,
                child: Text(
                  labels[index],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted, fontSize: 9),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _shortLabel(String value) {
    if (value.length <= 12) return value;
    final words = value.split(RegExp(r'\s+'));
    if (words.length > 1) {
      final initials = words.map((word) => word.isEmpty ? '' : word[0]).join();
      if (initials.length >= 2) return initials.toUpperCase();
    }
    return '${value.substring(0, 10)}…';
  }

  Widget _empty(String message) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: _muted, fontSize: 13),
      ),
    );
  }
}

class _StockSeries {
  const _StockSeries({required this.entries, required this.hasExplicitStock});

  final List<MapEntry<String, int>> entries;
  final bool hasExplicitStock;
}
