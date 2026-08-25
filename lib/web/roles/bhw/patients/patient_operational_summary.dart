import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_identity_utils.dart';

enum PatientDateFilterMode {
  today,
  last7Days,
  last30Days,
  thisMonth,
  last6Months,
  customDay,
  customRange,
  allTime,
}

class PatientOperationalSummary extends StatefulWidget {
  const PatientOperationalSummary({
    super.key,
    required this.patients,
    required this.onViewPatient,
    required this.onViewAll,
  });

  final List<Map<String, dynamic>> patients;
  final ValueChanged<Map<String, dynamic>> onViewPatient;
  final VoidCallback onViewAll;

  @override
  State<PatientOperationalSummary> createState() =>
      _PatientOperationalSummaryState();
}

class _PatientOperationalSummaryState extends State<PatientOperationalSummary> {
  static const _accent = Color(0xFF2F80ED);
  static const _surface = Colors.white;
  static const _text = Color(0xFF0B1F3A);
  static const _muted = Color(0xFF4B6075);
  static const _primaryAqua = Color(0xFF008895);

  PatientDateFilterMode _dateFilterMode = PatientDateFilterMode.allTime;
  DateTime? _selectedCustomDate;
  DateTime? _selectedMonthDate;
  DateTime _selectedRangeStart = DateTime.now().subtract(
    const Duration(days: 6),
  );
  DateTime _selectedRangeEnd = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedMonthDate ??= DateTime.now();
    _selectedRangeStart = DateTime.now().subtract(const Duration(days: 6));
    _selectedRangeEnd = DateTime.now();
  }

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
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return parsed;

    final normalized = text.contains('T') ? text.split('T').first : text;
    final slashParts = normalized.split('/');
    if (slashParts.length == 3) {
      final first = int.tryParse(slashParts[0]);
      final second = int.tryParse(slashParts[1]);
      final third = int.tryParse(slashParts[2]);
      if (first != null && second != null && third != null) {
        if (slashParts[0].length == 4) {
          return DateTime(first, second, third);
        }
        return DateTime(third, first, second);
      }
    }
    final dashParts = normalized.split('-');
    if (dashParts.length == 3) {
      final first = int.tryParse(dashParts[0]);
      final second = int.tryParse(dashParts[1]);
      final third = int.tryParse(dashParts[2]);
      if (first != null && second != null && third != null) {
        if (dashParts[0].length == 4) {
          return DateTime(first, second, third);
        }
        return DateTime(third, first, second);
      }
    }
    return null;
  }

  DateTime? _coercePatientDate(Map<String, dynamic> patient) {
    return _date(patient['registrationDate']) ??
        _date(patient['createdAt']) ??
        _date(patient['date']) ??
        _date(patient['updatedAt']) ??
        _date(patient['timestamp']);
  }

  bool _matchesDateFilter(DateTime? date) {
    if (_dateFilterMode == PatientDateFilterMode.allTime) return true;
    if (date == null) return false;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (_dateFilterMode) {
      case PatientDateFilterMode.today:
        return !date.isBefore(todayStart) && !date.isAfter(todayEnd);
      case PatientDateFilterMode.last7Days:
        final start = todayStart.subtract(const Duration(days: 6));
        return !date.isBefore(start) && !date.isAfter(todayEnd);
      case PatientDateFilterMode.last30Days:
        final start = todayStart.subtract(const Duration(days: 29));
        return !date.isBefore(start) && !date.isAfter(todayEnd);
      case PatientDateFilterMode.thisMonth:
        final targetMonth = _selectedMonthDate ?? now;
        return date.year == targetMonth.year && date.month == targetMonth.month;
      case PatientDateFilterMode.last6Months:
        final start = DateTime(now.year, now.month - 5, 1);
        return !date.isBefore(start) && !date.isAfter(todayEnd);
      case PatientDateFilterMode.customDay:
        final target = _selectedCustomDate ?? now;
        final start = DateTime(target.year, target.month, target.day);
        final end = DateTime(target.year, target.month, target.day, 23, 59, 59);
        return !date.isBefore(start) && !date.isAfter(end);
      case PatientDateFilterMode.customRange:
        final start = DateTime(
          _selectedRangeStart.year,
          _selectedRangeStart.month,
          _selectedRangeStart.day,
        );
        final end = DateTime(
          _selectedRangeEnd.year,
          _selectedRangeEnd.month,
          _selectedRangeEnd.day,
          23,
          59,
          59,
        );
        return !date.isBefore(start) && !date.isAfter(end);
      case PatientDateFilterMode.allTime:
        return true;
    }
  }

  String _monthLabelShort(int month) {
    const labels = [
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
    if (month < 1 || month > 12) return '';
    return labels[month - 1];
  }

  String _monthLabelLong(int month) {
    const labels = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    if (month < 1 || month > 12) return '';
    return labels[month - 1];
  }

  String _activeWindowLabel([PatientDateFilterMode? mode]) {
    final activeMode = mode ?? _dateFilterMode;
    final now = DateTime.now();
    try {
      switch (activeMode) {
        case PatientDateFilterMode.today:
          return 'Today (${_monthLabelShort(now.month)} ${now.day}, ${now.year})';
        case PatientDateFilterMode.last7Days:
          final start = now.subtract(const Duration(days: 6));
          return 'Last 7 Days (${_monthLabelShort(start.month)} ${start.day} - ${_monthLabelShort(now.month)} ${now.day})';
        case PatientDateFilterMode.last30Days:
          final start = now.subtract(const Duration(days: 29));
          return 'Last 30 Days (${_monthLabelShort(start.month)} ${start.day} - ${_monthLabelShort(now.month)} ${now.day})';
        case PatientDateFilterMode.thisMonth:
          final target = _selectedMonthDate ?? now;
          return '${_monthLabelLong(target.month)} ${target.year}';
        case PatientDateFilterMode.last6Months:
          final start = DateTime(now.year, now.month - 5, 1);
          return 'Last 6 Months (${_monthLabelShort(start.month)} ${start.year} - ${_monthLabelShort(now.month)} ${now.year})';
        case PatientDateFilterMode.customDay:
          final d = _selectedCustomDate ?? now;
          return '${_monthLabelLong(d.month)} ${d.day}, ${d.year}';
        case PatientDateFilterMode.customRange:
          final s = _selectedRangeStart;
          final e = _selectedRangeEnd;
          return '${_monthLabelShort(s.month)} ${s.day} - ${_monthLabelShort(e.month)} ${e.day}, ${e.year}';
        case PatientDateFilterMode.allTime:
          return 'All Time History';
      }
    } catch (_) {}
    return 'All Time History';
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

  Widget _buildAnalyticsFilterBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideHeader = constraints.maxWidth > 760;
        final filterBorderColor = Colors.black.withValues(alpha: 0.12);

        final headerCopy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Patient Insights & Registry Filter',
              style: TextStyle(
                color: _text,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Filter patient demographics, registration statistics, age distribution, and alerts by date. Currently showing ${_activeWindowLabel().toLowerCase()}.',
              maxLines: isWideHeader ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _muted, fontSize: 11, height: 1.35),
            ),
          ],
        );

        final activeWindowCard = Container(
          width: isWideHeader ? 230 : double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _accent.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.filter_alt_rounded, size: 13, color: _accent),
                  SizedBox(width: 5),
                  Text(
                    'Active Window',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _activeWindowLabel(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _text,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Metrics and charts auto-synced',
                style: TextStyle(color: _muted, fontSize: 9.5),
              ),
            ],
          ),
        );

        final filterChips = <Widget>[
          _buildFilterChip(
            'All Time',
            Icons.all_inclusive_rounded,
            PatientDateFilterMode.allTime,
          ),
          _buildFilterChip(
            'Today',
            Icons.today_rounded,
            PatientDateFilterMode.today,
          ),
          _buildFilterChip(
            'Last 7 Days',
            Icons.calendar_view_week_rounded,
            PatientDateFilterMode.last7Days,
          ),
          _buildFilterChip(
            'Last 30 Days',
            Icons.date_range_rounded,
            PatientDateFilterMode.last30Days,
          ),
          _buildFilterChip(
            'This Month',
            Icons.calendar_month_rounded,
            PatientDateFilterMode.thisMonth,
          ),
          _buildFilterChip(
            'Last 6 Months',
            Icons.stacked_bar_chart_rounded,
            PatientDateFilterMode.last6Months,
          ),
          OutlinedButton.icon(
            onPressed: _showDateFilterPickerModal,
            icon: const Icon(Icons.tune_rounded, size: 14),
            label: Text(
              _dateFilterMode == PatientDateFilterMode.customDay ||
                      _dateFilterMode == PatientDateFilterMode.customRange
                  ? 'Custom (${_activeWindowLabel()})'
                  : 'Pick Date / Range...',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  (_dateFilterMode == PatientDateFilterMode.customDay ||
                      _dateFilterMode == PatientDateFilterMode.customRange)
                  ? _accent
                  : _text,
              backgroundColor:
                  (_dateFilterMode == PatientDateFilterMode.customDay ||
                      _dateFilterMode == PatientDateFilterMode.customRange)
                  ? _accent.withValues(alpha: 0.12)
                  : Colors.white,
              side: BorderSide(
                color:
                    (_dateFilterMode == PatientDateFilterMode.customDay ||
                        _dateFilterMode == PatientDateFilterMode.customRange)
                    ? _accent
                    : filterBorderColor,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ];

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _accent.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isWideHeader)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: headerCopy),
                    const SizedBox(width: 16),
                    activeWindowCard,
                  ],
                )
              else ...[
                headerCopy,
                const SizedBox(height: 10),
                activeWindowCard,
              ],
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: filterChips),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(
    String label,
    IconData icon,
    PatientDateFilterMode mode,
  ) {
    final isSelected = _dateFilterMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        if (isSelected) return;
        setState(() {
          _dateFilterMode = mode;
          if (mode == PatientDateFilterMode.thisMonth) {
            _selectedMonthDate = DateTime.now();
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _accent : _surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? _accent : Colors.black.withValues(alpha: 0.12),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : _text),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : _text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDateFilterPickerModal() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Text(
                'Filter Patient Insights',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _text,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.event_available_rounded,
                  color: _accent,
                ),
                title: const Text(
                  'Specific Calendar Date',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Filter records for a specific day'),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedCustomDate ?? now,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _dateFilterMode = PatientDateFilterMode.customDay;
                    _selectedCustomDate = picked;
                  });
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.calendar_month_rounded,
                  color: _accent,
                ),
                title: const Text(
                  'Select Month & Year',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Pick target month (Current: ${_monthLabelLong((_selectedMonthDate ?? DateTime.now()).month)})',
                ),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  final target = _selectedMonthDate ?? DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: target,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                    initialDatePickerMode: DatePickerMode.year,
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _dateFilterMode = PatientDateFilterMode.thisMonth;
                    _selectedMonthDate = DateTime(picked.year, picked.month);
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.date_range_outlined, color: _accent),
                title: const Text(
                  'Custom Date Range',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Select custom start and end dates'),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  final picked = await showDateRangePicker(
                    context: context,
                    initialDateRange: DateTimeRange(
                      start: _selectedRangeStart,
                      end: _selectedRangeEnd,
                    ),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _dateFilterMode = PatientDateFilterMode.customRange;
                    _selectedRangeStart = picked.start;
                    _selectedRangeEnd = picked.end;
                  });
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(
                  Icons.all_inclusive_rounded,
                  color: _primaryAqua,
                ),
                title: const Text(
                  'Quick: All Time Registry',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(dialogContext);
                  setState(() {
                    _dateFilterMode = PatientDateFilterMode.allTime;
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.patients.isEmpty) {
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
              style: TextStyle(color: _muted),
            ),
          ],
        ),
      );
    }

    final filteredPatients = widget.patients
        .where((patient) => _matchesDateFilter(_coercePatientDate(patient)))
        .toList(growable: false);

    final now = DateTime.now();
    final male = filteredPatients
        .where((patient) => _sex(patient).startsWith('male'))
        .length;
    final female = filteredPatients
        .where((patient) => _sex(patient).startsWith('female'))
        .length;
    final recent = [...filteredPatients]
      ..sort(
        (left, right) => (_coercePatientDate(right) ?? DateTime(1900))
            .compareTo(_coercePatientDate(left) ?? DateTime(1900)),
      );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAnalyticsFilterBar(),
        const SizedBox(height: 20),
        _sectionTitle(
          'Patient Overview',
          'Patients registered in the active reporting window: ${_activeWindowLabel().toLowerCase()}.',
        ),
        _metricGrid(context, [
          _Metric(
            _dateFilterMode == PatientDateFilterMode.allTime
                ? 'Total Registered Patients'
                : 'Patients in Window',
            filteredPatients.length,
            Icons.people,
          ),
          _Metric('Male Patients', male, Icons.male_rounded),
          _Metric('Female Patients', female, Icons.female_rounded),
          _Metric(
            'Senior Citizens',
            filteredPatients.where((patient) => _age(patient) >= 60).length,
            Icons.elderly_rounded,
          ),
          _Metric(
            'Children (0–5)',
            filteredPatients
                .where((patient) => _age(patient) >= 0 && _age(patient) <= 5)
                .length,
            Icons.child_care_rounded,
          ),
          _Metric(
            'Pregnant Women',
            filteredPatients.where(_isPregnant).length,
            Icons.pregnant_woman_rounded,
          ),
          _Metric(
            'Persons With Disabilities',
            filteredPatients.where(_isPwd).length,
            Icons.accessible_rounded,
          ),
          _Metric(
            'High-Risk Patients',
            filteredPatients.where(_isHighRisk).length,
            Icons.warning_amber_rounded,
            color: Colors.orange,
          ),
        ]),
        _gap,
        _sectionTitle(
          'Registration Summary',
          'Patient registry maintenance for ${_activeWindowLabel().toLowerCase()}.',
        ),
        _metricGrid(context, [
          _Metric(
            'New Patients This Month',
            filteredPatients.where((patient) {
              final date = _coercePatientDate(patient);
              return date?.year == now.year && date?.month == now.month;
            }).length,
            Icons.person_add_alt_1_rounded,
          ),
          _Metric(
            'Updated Patient Records',
            filteredPatients.where(_wasUpdated).length,
            Icons.edit_note_rounded,
          ),
          _Metric(
            'Inactive Patients',
            filteredPatients
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
        _householdSummary(filteredPatients),
        _gap,
        _healthSummary(filteredPatients),
        _gap,
        _followUpSummary(filteredPatients),
        _gap,
        _patientAlerts(filteredPatients),
        _gap,
        _sectionTitle(
          'Demographic Overview',
          'Assigned patient counts for ${_activeWindowLabel().toLowerCase()}.',
        ),
        _responsivePair(
          context,
          _chartCard(
            title: 'Age Distribution',
            subtitle:
                'Patients grouped by age range in ${_activeWindowLabel().toLowerCase()}',
            icon: Icons.bar_chart_rounded,
            chart: _ageChart(filteredPatients),
          ),
          _chartCard(
            title: 'Sex Distribution',
            subtitle:
                'Patients grouped by recorded sex in ${_activeWindowLabel().toLowerCase()}',
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
        Text(subtitle, style: const TextStyle(color: _muted)),
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
        border: Border.all(color: const Color(0xFFD9E5F2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: metric.color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(metric.icon, color: _accent, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.title,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${metric.value}',
                  style: const TextStyle(
                    color: _text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _responsivePair(BuildContext context, Widget left, Widget right) =>
      LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                const SizedBox(width: 16),
                Expanded(child: right),
              ],
            );
          }
          return Column(children: [left, const SizedBox(height: 16), right]);
        },
      );

  Widget _chartCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget chart,
  }) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFD9E5F2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: _accent, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SizedBox(height: 210, child: chart),
      ],
    ),
  );

  Widget _ageChart(List<Map<String, dynamic>> records) {
    final counts = [
      records
          .where((patient) => _age(patient) >= 0 && _age(patient) <= 5)
          .length,
      records
          .where((patient) => _age(patient) >= 6 && _age(patient) <= 17)
          .length,
      records
          .where((patient) => _age(patient) >= 18 && _age(patient) <= 59)
          .length,
      records.where((patient) => _age(patient) >= 60).length,
    ];
    if (counts.every((count) => count == 0)) {
      return const Center(
        child: Text(
          'No patient age data recorded for this period.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted),
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
            getDrawingHorizontalLine: (_) =>
                FlLine(color: const Color(0xFFD9E5F2), strokeWidth: 1),
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
                  style: const TextStyle(color: _muted, fontSize: 10),
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
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ),
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF163B66),
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
                  color: _accent,
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
          'No patient sex data recorded for this period.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted),
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
      Text('$label  $value', style: const TextStyle(color: _muted)),
    ],
  );

  Widget _recentCard(List<Map<String, dynamic>> recent) => _listCard(
    title: 'Recent Registrations',
    icon: Icons.person_add_alt_1_rounded,
    emptyText: 'No patient registrations in this period.',
    trailing: TextButton(
      onPressed: widget.onViewAll,
      child: const Text('View All'),
    ),
    children: recent
        .map(
          (patient) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              patientDisplayName(patient),
              style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${_textValue(patient['age'])} years • ${_textValue(patient['sex'] ?? patient['gender'])} • ${_textValue(patient['barangay'])}\n${_formatDate(_coercePatientDate(patient))}',
              style: const TextStyle(color: _muted),
            ),
            isThreeLine: true,
            trailing: TextButton(
              onPressed: () => widget.onViewPatient(patient),
              child: const Text('View Profile'),
            ),
          ),
        )
        .toList(growable: false),
  );

  Widget _householdSummary(List<Map<String, dynamic>> records) {
    final households = <String>{};
    for (final patient in records) {
      final household = _textValue(patient['householdId']);
      if (household.isNotEmpty) households.add(household);
    }
    return _listCard(
      title: 'Household Summary',
      icon: Icons.home_work_outlined,
      emptyText: 'No household assignments recorded in this period.',
      children: households.isEmpty
          ? const []
          : [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${households.length} household${households.length == 1 ? '' : 's'} represented',
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  '${records.length} registered patient${records.length == 1 ? '' : 's'} linked to household records.',
                  style: const TextStyle(color: _muted),
                ),
              ),
            ],
    );
  }

  Widget _healthSummary(List<Map<String, dynamic>> records) {
    final withHistory = records
        .where(
          (patient) =>
              _hasText(patient, const ['medicalHistory', 'healthHistory']),
        )
        .length;
    final withAllergies = records
        .where((patient) => _hasText(patient, const ['allergies', 'allergy']))
        .length;
    return _listCard(
      title: 'Health Summary',
      icon: Icons.health_and_safety_outlined,
      emptyText: 'No health information recorded in this period.',
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            '$withHistory with medical history',
            style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '$withAllergies with documented allergies or sensitivities.',
            style: const TextStyle(color: _muted),
          ),
        ),
      ],
    );
  }

  Widget _followUpSummary(List<Map<String, dynamic>> records) {
    final scheduled = records
        .where(
          (patient) => _hasText(patient, const [
            'followup',
            'followUp',
            'followupDate',
            'nextVisit',
            'lastCheckup',
          ]),
        )
        .length;
    return _listCard(
      title: 'Follow-up Summary',
      icon: Icons.event_available_outlined,
      emptyText: 'No follow-up schedule recorded in this period.',
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            '$scheduled patient${scheduled == 1 ? '' : 's'} with follow-up information',
            style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
          ),
          subtitle: const Text(
            'Review the patient history to confirm the next care action.',
            style: TextStyle(color: _muted),
          ),
        ),
      ],
    );
  }

  Widget _patientAlerts(List<Map<String, dynamic>> records) {
    final alerts = records.where(_isHighRisk).toList(growable: false);
    return _listCard(
      title: 'Patient Alerts',
      icon: Icons.notifications_active_outlined,
      emptyText: 'No high-risk patient alerts in this period.',
      children: alerts
          .take(5)
          .map(
            (patient) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
              ),
              title: Text(
                patientDisplayName(patient),
                style: const TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                _textValue(patient['riskLevel']).isEmpty
                    ? 'High-risk record requires review.'
                    : 'Risk level: ${_textValue(patient['riskLevel'])}',
                style: const TextStyle(color: _muted),
              ),
              trailing: TextButton(
                onPressed: () => widget.onViewPatient(patient),
                child: const Text('View Profile'),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

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
      border: Border.all(color: const Color(0xFFD9E5F2)),
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
              child: Text(emptyText, style: const TextStyle(color: _muted)),
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
    this.color = const Color(0xFF2F80ED),
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
