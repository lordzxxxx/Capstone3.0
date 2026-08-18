import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/features/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';
import 'package:mycapstone_project/shared/widgets/spring_data_motion.dart';

const _accent = AppDesign.blue;
const _background = AppDesign.page;
const _surface = AppDesign.surface;
const _foreground = AppDesign.ink;
const _barPalette = AppDesign.chartPalette;

class NonCommunicableAnalyticsPage extends StatefulWidget {
  const NonCommunicableAnalyticsPage({super.key});

  @override
  State<NonCommunicableAnalyticsPage> createState() =>
      _NonCommunicableAnalyticsPageState();
}

class _NonCommunicableAnalyticsPageState
    extends State<NonCommunicableAnalyticsPage> {
  final _database = DatabaseHelper.instance;
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;

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
        return type == 'non-communicable' ||
            type == 'non communicable' ||
            type == 'non-communicable disease';
      }).toList();
      if (!mounted) return;
      setState(() {
        _records = records;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _v(Map<String, dynamic> row, String key) =>
      (row[key] ?? '').toString().trim();

  DateTime? _date(Map<String, dynamic> row) =>
      DateTime.tryParse(_v(row, 'datetime')) ??
      DateTime.tryParse(_v(row, 'date'));

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
    for (final key in const [
      'disease',
      'condition',
      'diagnosis',
      'type',
      'ai_category',
    ]) {
      final value = _v(row, key);
      if (value.isNotEmpty && !value.toLowerCase().contains('communicable'))
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
        : age <= 29
        ? '18-29'
        : age <= 44
        ? '30-44'
        : age <= 59
        ? '45-59'
        : '60+';
  });

  Map<String, int> _sex() => _group((row) {
    final value = _v(row, 'gender').isNotEmpty
        ? _v(row, 'gender')
        : _v(row, 'sex');
    return value.isEmpty ? 'Not specified' : value;
  });

  Map<String, int> _severity() => _group((row) {
    final raw =
        (_v(row, 'ai_severity').isNotEmpty
                ? _v(row, 'ai_severity')
                : _v(row, 'severity'))
            .toLowerCase();
    return raw.contains('severe') || raw.contains('critical')
        ? 'Severe'
        : raw.contains('moderate')
        ? 'Moderate'
        : 'Mild';
  });

  Map<String, int> _aiRisk() => _group((row) {
    final age = int.tryParse(_v(row, 'age')) ?? 0;
    final severity = (_v(row, 'ai_severity') + _v(row, 'severity'))
        .toLowerCase();
    final bmi = double.tryParse(_v(row, 'bmi')) ?? 0;
    final bp = _v(row, 'bloodPressure') + _v(row, 'vitalsigns');
    final highBp = RegExp(r'1[4-9]\d/').hasMatch(bp);
    return severity.contains('severe') || age >= 60 || bmi >= 30 || highBp
        ? 'High'
        : severity.contains('moderate') || age >= 45 || bmi >= 25
        ? 'Moderate'
        : 'Low';
  });

  Map<String, int> _control() => _group((row) {
    final raw = _v(row, 'status').toLowerCase();
    return raw.contains('uncontrolled') || raw.contains('critical')
        ? 'Uncontrolled'
        : raw.contains('monitor') || raw.contains('pending')
        ? 'Under Monitoring'
        : 'Controlled';
  });

  Map<String, int> _riskFactors() {
    final result = <String, int>{};
    for (final row in _records) {
      final raw = [
        _v(row, 'riskFactors'),
        _v(row, 'details'),
        _v(row, 'symptoms'),
      ].join(',');
      const known = [
        'Smoking',
        'Obesity',
        'Physical Inactivity',
        'High Cholesterol',
        'Alcohol Consumption',
      ];
      for (final factor in known) {
        if (raw.toLowerCase().contains(factor.toLowerCase())) {
          result[factor] = (result[factor] ?? 0) + 1;
        }
      }
    }
    return result;
  }

  Map<String, int> _followup() => _group((row) {
    final raw =
        (_v(row, 'followupStatus').isNotEmpty
                ? _v(row, 'followupStatus')
                : _v(row, 'followup'))
            .toLowerCase();
    return raw.contains('complete')
        ? 'Completed'
        : raw.contains('miss')
        ? 'Missed'
        : 'Pending';
  });

  Map<String, int> _medication() => _group((row) {
    final raw = _v(row, 'medicationAdherence').toLowerCase();
    return raw.contains('stop')
        ? 'Stopped Medication'
        : raw.contains('irregular') || raw.contains('miss')
        ? 'Irregular'
        : 'Taking Regularly';
  });

  Map<String, int> _referrals() => _group((row) {
    final raw = [
      _v(row, 'referralOutcome'),
      _v(row, 'referralStatus'),
      _v(row, 'plan'),
    ].join(' ').toLowerCase();
    return raw.contains('emergency')
        ? 'Emergency Referral'
        : raw.contains('hospital') || raw.contains('refer')
        ? 'Referred to Hospital'
        : 'Managed at Barangay';
  });

  @override
  Widget build(BuildContext context) {
    final diseases = _group(_disease);
    final barangays = _group(_barangay);
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: AppDesign.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Non-Communicable Analytics',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        actions: [
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
                  _line(
                    'Monthly Non-Communicable Disease Cases',
                    'New NCD cases during the last 12 months',
                    _monthly(),
                  ),
                  _gap(),
                  _bar(
                    'Cases by Disease Type',
                    'Most prevalent non-communicable diseases',
                    diseases,
                  ),
                  _gap(),
                  _bar(
                    'Cases by Barangay',
                    'Communities with higher chronic-disease burden',
                    barangays,
                  ),
                  _gap(),
                  _pie(
                    'Disease Distribution',
                    'Overall NCD prevalence by disease',
                    diseases,
                  ),
                  _gap(),
                  _bar(
                    'Cases by Age Group',
                    'Cases grouped by patient age',
                    _ages(),
                  ),
                  _gap(),
                  _pie('Cases by Sex', 'NCD prevalence by sex', _sex()),
                  _gap(),
                  _bar(
                    'Disease Severity Distribution',
                    'Mild, moderate, and severe cases',
                    _severity(),
                  ),
                  _gap(),
                  _bar(
                    'AI High-Risk Patient Assessment',
                    'Risk-assessment aid—not a definitive diagnosis',
                    _aiRisk(),
                  ),
                  _gap(),
                  _pie(
                    'Controlled vs Uncontrolled Cases',
                    'Treatment-control status',
                    _control(),
                  ),
                  _gap(),
                  _bar(
                    'Common Risk Factors',
                    'Lifestyle and clinical factors linked to NCDs',
                    _riskFactors(),
                  ),
                  _gap(),
                  _bar(
                    'Follow-up Compliance',
                    'Adherence to scheduled consultations',
                    _followup(),
                  ),
                  _gap(),
                  _pie(
                    'Medication Adherence',
                    'Reported chronic medication adherence',
                    _medication(),
                  ),
                  _gap(),
                  _bar(
                    'Hospital Referral Rate',
                    'Primary-care and hospital referral outcomes',
                    _referrals(),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _gap() => const SizedBox(height: 16);

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
      border: Border.all(color: _accent.withValues(alpha: 0.2)),
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
        SpringDataMotion(dataKey: child, child: child),
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
                      color: _foreground.withValues(alpha: 0.55),
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
                    '${entry.key}\n${entry.value}',
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
    if (entries.isEmpty) return _card(title, subtitle, _empty());
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    const colors = [
      AppDesign.blue,
      AppDesign.navy,
      AppDesign.skyBlue,
      Color(0xFF8FAFD6),
      Color(0xFFB8C9DB),
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
                sections: List.generate(entries.length, (index) {
                  final sliceColor = colors[index % colors.length];
                  return PieChartSectionData(
                    value: entries[index].value.toDouble(),
                    color: sliceColor,
                    radius: 62,
                    title:
                        '${(entries[index].value / total * 100).toStringAsFixed(0)}%',
                    titleStyle: TextStyle(
                      color: sliceColor.computeLuminance() > 0.42
                          ? _foreground
                          : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }),
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

  Widget _empty() => Text(
    'No data available.',
    style: TextStyle(color: _foreground.withValues(alpha: 0.6)),
  );
}
