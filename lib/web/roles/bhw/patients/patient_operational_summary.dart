import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_identity_utils.dart';

class PatientOperationalSummary extends StatelessWidget {
  const PatientOperationalSummary({
    super.key,
    required this.patients,
    required this.onViewPatient,
    required this.onViewAll,
  });

  final List<Map<String, dynamic>> patients;
  final ValueChanged<Map<String, dynamic>> onViewPatient;
  final VoidCallback onViewAll;

  static const _accent = Color(0xFF00A8B5);
  static const _surface = Color(0xFF0E2F34);
  static const _text = Color(0xFFF5F7FA);

  String _textValue(dynamic value) => value?.toString().trim() ?? '';

  int _age(Map<String, dynamic> patient) =>
      int.tryParse(_textValue(patient['age'])) ?? -1;

  bool _truthy(dynamic value) {
    final normalized = _textValue(value).toLowerCase();
    return const {'true', 'yes', '1', 'active'}.contains(normalized);
  }

  DateTime? _date(dynamic value) {
    if (value is DateTime) return value;
    if (value == null) return null;
    try {
      final dynamic converted = value.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      // The value is not a Firestore Timestamp.
    }
    return DateTime.tryParse(value.toString());
  }

  bool _hasText(Map<String, dynamic> patient, List<String> keys) =>
      keys.any((key) {
        final value = _textValue(patient[key]).toLowerCase();
        return value.isNotEmpty &&
            !const {'none', 'n/a', 'no', 'false', '0'}.contains(value);
      });

  bool _wasUpdated(Map<String, dynamic> patient) {
    final updated = _date(patient['updatedAt']);
    final registered = _date(
      patient['registrationDate'] ?? patient['createdAt'],
    );
    if (updated == null || registered == null) return false;
    return updated.difference(registered).abs() > const Duration(minutes: 1);
  }

  bool _isHighRisk(Map<String, dynamic> patient) {
    final risk = [
      patient['riskLevel'],
      patient['morbidityRiskLevel'],
      patient['pregnancyRiskLevel'],
    ].map(_textValue).join(' ').toLowerCase();
    return risk.contains('high') || _truthy(patient['highRisk']);
  }

  bool _isPregnant(Map<String, dynamic> patient) {
    final status = _textValue(patient['pregnancyStatus']).toLowerCase();
    return _truthy(patient['isPregnant']) ||
        status == 'pregnant' ||
        status == 'active';
  }

  bool _isPwd(Map<String, dynamic> patient) =>
      _truthy(patient['isPwd']) ||
      _hasText(patient, const ['disability', 'pwdType']);

  @override
  Widget build(BuildContext context) {
    if (patients.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _accent.withValues(alpha: 0.18)),
        ),
        child: const Column(
          children: [
            Icon(Icons.people_outline_rounded, color: _accent, size: 44),
            SizedBox(height: 14),
            Text(
              'No Firebase patient records available',
              style: TextStyle(
                color: _text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Insights and graphs will appear after patient records are registered in this barangay.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final male = patients
        .where((patient) => _sex(patient).startsWith('male'))
        .length;
    final female = patients
        .where((patient) => _sex(patient).startsWith('female'))
        .length;
    final recent = [...patients]
      ..sort(
        (left, right) => (_date(right['registrationDate']) ?? DateTime(1900))
            .compareTo(_date(left['registrationDate']) ?? DateTime(1900)),
      );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Patient Overview',
          'Patients assigned to the current BHW workspace.',
        ),
        _metricGrid(context, [
          _Metric('Total Registered Patients', patients.length, Icons.people),
          _Metric('Male Patients', male, Icons.male_rounded),
          _Metric('Female Patients', female, Icons.female_rounded),
          _Metric(
            'Senior Citizens',
            patients.where((patient) => _age(patient) >= 60).length,
            Icons.elderly_rounded,
          ),
          _Metric(
            'Children (0–5)',
            patients
                .where((patient) => _age(patient) >= 0 && _age(patient) <= 5)
                .length,
            Icons.child_care_rounded,
          ),
          _Metric(
            'Pregnant Women',
            patients.where(_isPregnant).length,
            Icons.pregnant_woman_rounded,
          ),
          _Metric(
            'Persons With Disabilities',
            patients.where(_isPwd).length,
            Icons.accessible_rounded,
          ),
          _Metric(
            'High-Risk Patients',
            patients.where(_isHighRisk).length,
            Icons.warning_amber_rounded,
            color: Colors.orange,
          ),
        ]),
        _gap,
        _sectionTitle('Registration Summary', 'Patient registry maintenance.'),
        _metricGrid(context, [
          _Metric(
            'New Patients This Month',
            patients.where((patient) {
              final date = _date(patient['registrationDate']);
              return date?.year == now.year && date?.month == now.month;
            }).length,
            Icons.person_add_alt_1_rounded,
          ),
          _Metric(
            'Updated Patient Records',
            patients.where(_wasUpdated).length,
            Icons.edit_note_rounded,
          ),
          _Metric(
            'Inactive Patients',
            patients
                .where(
                  (patient) =>
                      _textValue(patient['status']).toLowerCase() == 'inactive',
                )
                .length,
            Icons.person_off_outlined,
            color: Colors.redAccent,
          ),
        ]),
        _gap,
        _sectionTitle(
          'Demographic Overview',
          'Simple assigned-patient counts.',
        ),
        _responsivePair(
          context,
          _chartCard(
            title: 'Age Distribution',
            subtitle: 'Registered patients grouped by age range',
            icon: Icons.bar_chart_rounded,
            chart: _ageChart(),
          ),
          _chartCard(
            title: 'Sex Distribution',
            subtitle: 'Registered patients grouped by recorded sex',
            icon: Icons.donut_large_rounded,
            chart: _sexChart(male, female),
          ),
        ),
        _gap,
        _recentCard(recent.take(5).toList(growable: false)),
        const SizedBox(height: 40),
      ],
    );
  }

  String _sex(Map<String, dynamic> patient) =>
      _textValue(patient['sex'] ?? patient['gender']).toLowerCase();

  static const _gap = SizedBox(height: 26);

  Widget _sectionTitle(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _text,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(color: Colors.white60)),
      ],
    ),
  );

  Widget _metricGrid(BuildContext context, List<_Metric> metrics) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1150
              ? 4
              : constraints.maxWidth >= 700
              ? 2
              : 1;
          final width = (constraints.maxWidth - ((columns - 1) * 12)) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: metrics
                .map(
                  (metric) =>
                      SizedBox(width: width, child: _metricCard(metric)),
                )
                .toList(growable: false),
          );
        },
      );

  Widget _metricCard(_Metric metric) => Semantics(
    label: '${metric.title}: ${metric.value}',
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: metric.color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(metric.icon, color: metric.color, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${metric.value}',
                  style: const TextStyle(
                    color: _text,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  metric.title,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _responsivePair(BuildContext context, Widget first, Widget second) =>
      LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 820) {
            return Column(
              children: [first, const SizedBox(height: 12), second],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 12),
              Expanded(child: second),
            ],
          );
        },
      );

  Widget _chartCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget chart,
  }) => Container(
    height: 360,
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _accent.withValues(alpha: 0.18)),
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
                      color: _text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(child: chart),
      ],
    ),
  );

  Widget _ageChart() {
    final counts = [
      patients
          .where((patient) => _age(patient) >= 0 && _age(patient) <= 5)
          .length,
      patients
          .where((patient) => _age(patient) >= 6 && _age(patient) <= 17)
          .length,
      patients
          .where((patient) => _age(patient) >= 18 && _age(patient) <= 59)
          .length,
      patients.where((patient) => _age(patient) >= 60).length,
    ];
    if (counts.every((count) => count == 0)) {
      return const Center(
        child: Text(
          'No patient age data recorded in Firebase.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60),
        ),
      );
    }
    final largest = mathMax(counts);
    final paddedMax = largest + (largest * 0.25).ceil();
    final maxY = (paddedMax < 4 ? 4 : paddedMax).toDouble();
    final interval = (maxY / 4).ceilToDouble();
    return Semantics(
      label:
          'Age distribution: 0 to 5 ${counts[0]}, 6 to 17 ${counts[1]}, 18 to 59 ${counts[2]}, 60 plus ${counts[3]}',
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
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
                reservedSize: 32,
                interval: interval,
                getTitlesWidget: (value, _) => Text(
                  value.toInt().toString(),
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    const ['0–5', '6–17', '18–59', '60+'][value.toInt()],
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF173C43),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final count = counts[group.x];
                return BarTooltipItem(
                  '$count patient${count == 1 ? '' : 's'}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ),
          barGroups: List.generate(
            counts.length,
            (index) => BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: counts[index].toDouble(),
                  width: 24,
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
      ),
    );
  }

  Widget _sexChart(int male, int female) {
    final total = male + female;
    const maleColor = Color(0xFF008895);
    const femaleColor = Color(0xFF35D4DE);
    if (total == 0) {
      return const Center(
        child: Text(
          'No patient sex data recorded in Firebase.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60),
        ),
      );
    }
    return Semantics(
      label: 'Sex distribution: Male $male, Female $female',
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                centerSpaceRadius: 52,
                sectionsSpace: 3,
                sections: [
                  PieChartSectionData(
                    value: male.toDouble(),
                    color: maleColor,
                    showTitle: false,
                    radius: 28,
                  ),
                  PieChartSectionData(
                    value: female.toDouble(),
                    color: femaleColor,
                    showTitle: false,
                    radius: 28,
                  ),
                ],
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _legend('Male', male, maleColor),
              const SizedBox(height: 12),
              _legend('Female', female, femaleColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(String label, int value, Color color) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 7),
      Text('$label  $value', style: const TextStyle(color: Colors.white70)),
    ],
  );

  Widget _recentCard(List<Map<String, dynamic>> recent) => _listCard(
    title: 'Recent Registrations',
    icon: Icons.person_add_alt_1_rounded,
    emptyText: 'No patient registrations yet.',
    trailing: TextButton(onPressed: onViewAll, child: const Text('View All')),
    children: recent
        .map(
          (patient) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              patientDisplayName(patient),
              style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${_textValue(patient['age'])} years • ${_textValue(patient['sex'] ?? patient['gender'])} • ${_textValue(patient['barangay'])}\n${_formatDate(_date(patient['registrationDate']))}',
              style: const TextStyle(color: Colors.white60),
            ),
            isThreeLine: true,
            trailing: TextButton(
              onPressed: () => onViewPatient(patient),
              child: const Text('View Profile'),
            ),
          ),
        )
        .toList(growable: false),
  );

  Widget _listCard({
    required String title,
    required IconData icon,
    required String emptyText,
    required List<Widget> children,
    Widget? trailing,
  }) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: _accent),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 10),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                emptyText,
                style: const TextStyle(color: Colors.white60),
              ),
            ),
          )
        else
          ...children,
      ],
    ),
  );

  String _formatDate(DateTime? date) {
    if (date == null) return 'Registration date unavailable';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.month)}/${two(date.day)}/${date.year}';
  }
}

class _Metric {
  const _Metric(
    this.title,
    this.value,
    this.icon, {
    this.color = const Color(0xFF00A8B5),
  });

  final String title;
  final int value;
  final IconData icon;
  final Color color;
}

int mathMax(List<int> values) {
  var maximum = 0;
  for (final value in values) {
    if (value > maximum) maximum = value;
  }
  return maximum;
}
