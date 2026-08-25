import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart'
    as charts;
import 'package:mycapstone_project/web/roles/bhw/dashboard/homepage.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/mortality_database_helper.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/shared/components/app_metric_card.dart';
import 'package:mycapstone_project/web/shared/components/fullscreen_detail_table_dialog.dart';
import 'package:mycapstone_project/web/shared/components/module_view_components.dart';
import 'package:mycapstone_project/web/shared/components/web_data_components.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_first_service_selector.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_identity_utils.dart';
import 'package:mycapstone_project/web/shared/utils/file_download.dart';
import 'package:mycapstone_project/web/shared/utils/mortality_pdf.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/shared_patient_search_panel.dart';
import 'package:mycapstone_project/web/shared/utils/report_generation.dart';
import 'package:mycapstone_project/shared/current_table_record_utils.dart';
import 'package:mycapstone_project/web/shared/widgets/web_sync_status_badge.dart';

const Color _primaryAqua = Color(0xFF2F80ED);
const Color _secondaryIceBlue = Color(0xFF163B66);
const Color _darkDeepTeal = Color(0xFF071A33);
const Color _lightOffWhite = Color(0xFF0B1F3A);
const Color _mutedCoolGray = Color(0xFF4B6075);
const Color _sidebarDark = Color(0xFF0D274D);
const List<Color> _mortalityChartPalette = <Color>[
  _primaryAqua,
  _secondaryIceBlue,
  Color(0xFF5B8CC9),
  Color(0xFF1F5A91),
  Color(0xFF8FAFD6),
  Color(0xFFB8C9DB),
];

charts.Color _toChartsColor(Color color) => charts.Color(
  r: (color.r * 255).round().clamp(0, 255),
  g: (color.g * 255).round().clamp(0, 255),
  b: (color.b * 255).round().clamp(0, 255),
  a: (color.a * 255).round().clamp(0, 255),
);

class MortalityPage extends StatefulWidget {
  const MortalityPage({super.key, this.initialPatient});

  final Map<String, dynamic>? initialPatient;

  @override
  State<MortalityPage> createState() => _MortalityPageState();
}

class _MortalityPageState extends State<MortalityPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  // Database helper
  final _mortalityHelper = MortalityDatabaseHelper.instance;
  final PatientCenteredHistoryService _patientHistoryService =
      PatientCenteredHistoryService();

  // Metrics
  int _totalDeaths = 0;
  String _leadingCause = '';
  int _elderlyDeaths = 0;
  double _verificationRate = 0.0;
  bool _isLoadingMetrics = false;
  bool _isDataLoaded = false;

  // Search and Filters
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatusFilter = 'All';
  String _selectedBarangay = 'All';
  String _selectedCauseFilter = 'All';
  String _selectedAgeGroup = 'All';
  String _selectedSex = 'All';
  String _sortField = 'Name';
  bool _sortAscending = true;
  DateTime? _fromDate;
  DateTime? _toDate;
  final List<String> _statusFilterOptions = [
    'All',
    'Verified',
    'Unverified',
    'Pending',
  ];
  List<Map<String, dynamic>> _sharedPatientMatches = [];
  bool _isSearchingSharedPatients = false;
  Timer? _sharedPatientSearchDebounce;
  int _currentPage = 1;
  int _rowsPerPage = 10;

  // Data
  List<Map<String, dynamic>> _mortalityRecords = [];
  List<Map<String, dynamic>> _filteredRecords = [];
  List<MonthlyTrend> _monthlyTrends = [];
  List<CauseData> _causeData = [];
  List<AgeDistribution> _ageDistributions = [];

  // Insights Date Filter State
  DashboardDateFilterMode _insightsDateFilterMode =
      DashboardDateFilterMode.allTime;
  DateTime? _insightsCustomDate;
  DateTime? _insightsSelectedMonth;
  DateTime _insightsRangeStart = DateTime.now().subtract(
    const Duration(days: 6),
  );
  DateTime _insightsRangeEnd = DateTime.now();

  // Pie Chart Hover State
  CauseData? _selectedCause;
  late HealthModuleView _activeView;

  @override
  void initState() {
    super.initState();
    _insightsSelectedMonth ??= DateTime.now();
    _insightsRangeStart = DateTime.now().subtract(const Duration(days: 6));
    _insightsRangeEnd = DateTime.now();
    _activeView = healthModuleViewFromUrl();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => persistHealthModuleView(WebRoutes.bhwMortality, _activeView),
    );
    // Load data asynchronously to avoid blocking UI
    Future.microtask(() => _loadData());
    if (widget.initialPatient != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAddRecordDialog(patientSeed: widget.initialPatient);
      });
    }
  }

  void _setActiveView(HealthModuleView view) {
    if (_activeView == view) return;
    setState(() => _activeView = view);
    persistHealthModuleView(WebRoutes.bhwMortality, view);
  }

  @override
  void dispose() {
    _sharedPatientSearchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  DateTime? _parseMortalityDate(dynamic value) {
    if (value is DateTime) return value;
    if (value == null) return null;
    try {
      final dynamic converted = (value as dynamic).toDate();
      if (converted is DateTime) return converted;
    } catch (_) {}
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return parsed;
    return null;
  }

  DateTime? _coerceMortalityDate(Map<String, dynamic> record) {
    return _parseMortalityDate(record['dateOfDeath']) ??
        _parseMortalityDate(record['date']) ??
        _parseMortalityDate(record['datetime']) ??
        _parseMortalityDate(record['createdAt']) ??
        _parseMortalityDate(record['timestamp']);
  }

  bool _matchesInsightsDateFilter(DateTime? date) {
    if (_insightsDateFilterMode == DashboardDateFilterMode.allTime) return true;
    if (date == null) return false;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (_insightsDateFilterMode) {
      case DashboardDateFilterMode.today:
        return !date.isBefore(todayStart) && !date.isAfter(todayEnd);
      case DashboardDateFilterMode.last7Days:
        final start = todayStart.subtract(const Duration(days: 6));
        return !date.isBefore(start) && !date.isAfter(todayEnd);
      case DashboardDateFilterMode.last30Days:
        final start = todayStart.subtract(const Duration(days: 29));
        return !date.isBefore(start) && !date.isAfter(todayEnd);
      case DashboardDateFilterMode.thisMonth:
        final targetMonth = _insightsSelectedMonth ?? now;
        return date.year == targetMonth.year && date.month == targetMonth.month;
      case DashboardDateFilterMode.last6Months:
        final start = DateTime(now.year, now.month - 5, 1);
        return !date.isBefore(start) && !date.isAfter(todayEnd);
      case DashboardDateFilterMode.customDay:
        final target = _insightsCustomDate ?? now;
        final start = DateTime(target.year, target.month, target.day);
        final end = DateTime(target.year, target.month, target.day, 23, 59, 59);
        return !date.isBefore(start) && !date.isAfter(end);
      case DashboardDateFilterMode.customRange:
        final start = DateTime(
          _insightsRangeStart.year,
          _insightsRangeStart.month,
          _insightsRangeStart.day,
        );
        final end = DateTime(
          _insightsRangeEnd.year,
          _insightsRangeEnd.month,
          _insightsRangeEnd.day,
          23,
          59,
          59,
        );
        return !date.isBefore(start) && !date.isAfter(end);
      case DashboardDateFilterMode.allTime:
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

  String _activeInsightsWindowLabel([DashboardDateFilterMode? mode]) {
    final activeMode = mode ?? _insightsDateFilterMode;
    final now = DateTime.now();
    try {
      switch (activeMode) {
        case DashboardDateFilterMode.today:
          return 'Today (${_monthLabelShort(now.month)} ${now.day}, ${now.year})';
        case DashboardDateFilterMode.last7Days:
          final start = now.subtract(const Duration(days: 6));
          return 'Last 7 Days (${_monthLabelShort(start.month)} ${start.day} - ${_monthLabelShort(now.month)} ${now.day})';
        case DashboardDateFilterMode.last30Days:
          final start = now.subtract(const Duration(days: 29));
          return 'Last 30 Days (${_monthLabelShort(start.month)} ${start.day} - ${_monthLabelShort(now.month)} ${now.day})';
        case DashboardDateFilterMode.thisMonth:
          final target = _insightsSelectedMonth ?? now;
          return '${_monthLabelLong(target.month)} ${target.year}';
        case DashboardDateFilterMode.last6Months:
          final start = DateTime(now.year, now.month - 5, 1);
          return 'Last 6 Months (${_monthLabelShort(start.month)} ${start.year} - ${_monthLabelShort(now.month)} ${now.year})';
        case DashboardDateFilterMode.customDay:
          final d = _insightsCustomDate ?? now;
          return '${_monthLabelLong(d.month)} ${d.day}, ${d.year}';
        case DashboardDateFilterMode.customRange:
          final s = _insightsRangeStart;
          final e = _insightsRangeEnd;
          return '${_monthLabelShort(s.month)} ${s.day} - ${_monthLabelShort(e.month)} ${e.day}, ${e.year}';
        case DashboardDateFilterMode.allTime:
          return 'All Time History';
      }
    } catch (_) {}
    return 'All Time History';
  }

  void _recomputeMortalityInsightsMetrics() {
    final filtered = _mortalityRecords
        .where((r) => _matchesInsightsDateFilter(_coerceMortalityDate(r)))
        .toList(growable: false);
    final totalDeaths = filtered.length;
    final elderlyCount = filtered
        .where((r) => (int.tryParse(r['age']?.toString() ?? '0') ?? 0) >= 60)
        .length;
    final verifiedCount = filtered
        .where((r) => r['verification']?.toString().toLowerCase() == 'verified')
        .length;
    final verificationPercent = totalDeaths > 0
        ? (verifiedCount / totalDeaths) * 100
        : 0.0;

    final causeCounts = <String, int>{};
    for (final r in filtered) {
      final cause = (r['causeOfDeath'] ?? r['cause'] ?? 'Unspecified')
          .toString();
      causeCounts[cause] = (causeCounts[cause] ?? 0) + 1;
    }
    final sortedCauses = causeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final leadingCause = sortedCauses.isEmpty
        ? 'No data'
        : sortedCauses.first.key;

    final trends = _generateMonthlyTrends(filtered);
    final causes = _generateCauseData(filtered);
    final ages = _generateAgeDistribution(filtered);

    setState(() {
      _totalDeaths = totalDeaths;
      _leadingCause = leadingCause;
      _elderlyDeaths = elderlyCount;
      _verificationRate = verificationPercent;
      _monthlyTrends = trends;
      _causeData = causes;
      _ageDistributions = ages;
    });
  }

  Widget _buildInsightsFilterBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideHeader = constraints.maxWidth > 760;
        final filterBorderColor = Colors.black.withValues(alpha: 0.12);

        final headerCopy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mortality Surveillance & Trend Filter',
              style: TextStyle(
                color: _lightOffWhite,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Filter mortality records, verified counts, cause distributions, and monthly trends by date. Currently showing ${_activeInsightsWindowLabel().toLowerCase()}.',
              maxLines: isWideHeader ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _mutedCoolGray,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        );

        final activeWindowCard = Container(
          width: isWideHeader ? 230 : double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _primaryAqua.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _primaryAqua.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.filter_alt_rounded, size: 13, color: _primaryAqua),
                  SizedBox(width: 5),
                  Text(
                    'Active Window',
                    style: TextStyle(
                      color: _primaryAqua,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _activeInsightsWindowLabel(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _lightOffWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Charts & counts auto-synced',
                style: TextStyle(color: _mutedCoolGray, fontSize: 9.5),
              ),
            ],
          ),
        );

        final filterChips = <Widget>[
          _buildInsightsFilterChip(
            'All Time',
            Icons.all_inclusive_rounded,
            DashboardDateFilterMode.allTime,
          ),
          _buildInsightsFilterChip(
            'Today',
            Icons.today_rounded,
            DashboardDateFilterMode.today,
          ),
          _buildInsightsFilterChip(
            'Last 7 Days',
            Icons.calendar_view_week_rounded,
            DashboardDateFilterMode.last7Days,
          ),
          _buildInsightsFilterChip(
            'Last 30 Days',
            Icons.date_range_rounded,
            DashboardDateFilterMode.last30Days,
          ),
          _buildInsightsFilterChip(
            'This Month',
            Icons.calendar_month_rounded,
            DashboardDateFilterMode.thisMonth,
          ),
          _buildInsightsFilterChip(
            'Last 6 Months',
            Icons.stacked_bar_chart_rounded,
            DashboardDateFilterMode.last6Months,
          ),
          OutlinedButton.icon(
            onPressed: _showInsightsDateFilterPickerModal,
            icon: const Icon(Icons.tune_rounded, size: 14),
            label: Text(
              _insightsDateFilterMode == DashboardDateFilterMode.customDay ||
                      _insightsDateFilterMode ==
                          DashboardDateFilterMode.customRange
                  ? 'Custom (${_activeInsightsWindowLabel()})'
                  : 'Pick Date / Range...',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  (_insightsDateFilterMode ==
                          DashboardDateFilterMode.customDay ||
                      _insightsDateFilterMode ==
                          DashboardDateFilterMode.customRange)
                  ? _primaryAqua
                  : _lightOffWhite,
              backgroundColor:
                  (_insightsDateFilterMode ==
                          DashboardDateFilterMode.customDay ||
                      _insightsDateFilterMode ==
                          DashboardDateFilterMode.customRange)
                  ? _primaryAqua.withValues(alpha: 0.12)
                  : Colors.white,
              side: BorderSide(
                color:
                    (_insightsDateFilterMode ==
                            DashboardDateFilterMode.customDay ||
                        _insightsDateFilterMode ==
                            DashboardDateFilterMode.customRange)
                    ? _primaryAqua
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _primaryAqua.withValues(alpha: 0.15)),
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

  Widget _buildInsightsFilterChip(
    String label,
    IconData icon,
    DashboardDateFilterMode mode,
  ) {
    final isSelected = _insightsDateFilterMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        if (isSelected) return;
        setState(() {
          _insightsDateFilterMode = mode;
          if (mode == DashboardDateFilterMode.thisMonth) {
            _insightsSelectedMonth = DateTime.now();
          }
        });
        _recomputeMortalityInsightsMetrics();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _primaryAqua : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? _primaryAqua
                : Colors.black.withValues(alpha: 0.12),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _primaryAqua.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : _lightOffWhite,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : _lightOffWhite,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showInsightsDateFilterPickerModal() async {
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
                'Filter Mortality Insights',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _lightOffWhite,
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
                  color: _primaryAqua,
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
                    initialDate: _insightsCustomDate ?? now,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _insightsDateFilterMode = DashboardDateFilterMode.customDay;
                    _insightsCustomDate = picked;
                  });
                  _recomputeMortalityInsightsMetrics();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.calendar_month_rounded,
                  color: _primaryAqua,
                ),
                title: const Text(
                  'Select Month & Year',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Pick target month (Current: ${_monthLabelLong((_insightsSelectedMonth ?? DateTime.now()).month)})',
                ),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  final target = _insightsSelectedMonth ?? DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: target,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                    initialDatePickerMode: DatePickerMode.year,
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _insightsDateFilterMode = DashboardDateFilterMode.thisMonth;
                    _insightsSelectedMonth = DateTime(
                      picked.year,
                      picked.month,
                    );
                  });
                  _recomputeMortalityInsightsMetrics();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.date_range_outlined,
                  color: _primaryAqua,
                ),
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
                      start: _insightsRangeStart,
                      end: _insightsRangeEnd,
                    ),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked == null || !mounted) return;
                  setState(() {
                    _insightsDateFilterMode =
                        DashboardDateFilterMode.customRange;
                    _insightsRangeStart = picked.start;
                    _insightsRangeEnd = picked.end;
                  });
                  _recomputeMortalityInsightsMetrics();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(
                  Icons.all_inclusive_rounded,
                  color: _primaryAqua,
                ),
                title: const Text(
                  'Quick: All Time Records',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(dialogContext);
                  setState(() {
                    _insightsDateFilterMode = DashboardDateFilterMode.allTime;
                  });
                  _recomputeMortalityInsightsMetrics();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _loadData() async {
    setState(() => _isLoadingMetrics = true);

    try {
      // Load mortality records from database
      final recordsList = await _mortalityHelper.getAllRecords();
      _mortalityRecords = recordsList;
      _applyFilters();
      _isDataLoaded = true;
      _isLoadingMetrics = false;
      _recomputeMortalityInsightsMetrics();
    } catch (e) {
      debugPrint('Error loading data: $e');
      setState(() {
        _isLoadingMetrics = false;
        _isDataLoaded = true;
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _currentPage = 1;
      final filtered = _mortalityRecords.where((record) {
        // Status / Verification Filter
        if (_selectedStatusFilter != 'All') {
          final status = (record['verification'] ?? record['status'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          if (status != _selectedStatusFilter.toLowerCase()) {
            return false;
          }
        }

        // Barangay Filter
        if (_selectedBarangay != 'All') {
          final barangay =
              (record['place'] ?? record['barangay'] ?? record['address'] ?? '')
                  .toString()
                  .toLowerCase();
          if (!barangay.contains(_selectedBarangay.toLowerCase())) {
            return false;
          }
        }

        // Cause Filter
        if (_selectedCauseFilter != 'All') {
          final cause = (record['causeOfDeath'] ?? record['cause'] ?? '')
              .toString()
              .toLowerCase();
          if (!cause.contains(_selectedCauseFilter.toLowerCase())) {
            return false;
          }
        }

        // Age Group Filter
        if (_selectedAgeGroup != 'All') {
          final age = int.tryParse(record['age']?.toString() ?? '') ?? -1;
          if (age >= 0) {
            switch (_selectedAgeGroup) {
              case '0–17':
                if (age > 17) return false;
                break;
              case '18–59':
                if (age < 18 || age > 59) return false;
                break;
              case '60+':
                if (age < 60) return false;
                break;
            }
          }
        }

        // Sex / Gender Filter
        if (_selectedSex != 'All') {
          final sex = (record['gender'] ?? record['sex'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          if (sex != _selectedSex.toLowerCase()) {
            return false;
          }
        }

        // Date range filter
        if (_fromDate != null || _toDate != null) {
          final d = _coerceMortalityDate(record);
          if (d != null) {
            if (_fromDate != null && d.isBefore(_fromDate!)) {
              return false;
            }
            if (_toDate != null && d.isAfter(_toDate!)) {
              return false;
            }
          }
        }

        // Search Query filter
        if (_searchQuery.trim().isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          final name = (record['name'] ?? record['patientName'] ?? '')
              .toString()
              .toLowerCase();
          final id = (record['id'] ?? record['patientId'] ?? '')
              .toString()
              .toLowerCase();
          final cause = (record['causeOfDeath'] ?? record['cause'] ?? '')
              .toString()
              .toLowerCase();
          final place =
              (record['place'] ?? record['barangay'] ?? record['address'] ?? '')
                  .toString()
                  .toLowerCase();
          final verification =
              (record['verification'] ?? record['status'] ?? '')
                  .toString()
                  .toLowerCase();
          final reportedBy = (record['reportedBy'] ?? '')
              .toString()
              .toLowerCase();

          if (!name.contains(query) &&
              !id.contains(query) &&
              !cause.contains(query) &&
              !place.contains(query) &&
              !verification.contains(query) &&
              !reportedBy.contains(query)) {
            return false;
          }
        }

        return true;
      }).toList();

      // Sort
      filtered.sort((a, b) {
        int comparison = 0;
        switch (_sortField) {
          case 'Date of Death':
            final aDate = _coerceMortalityDate(a) ?? DateTime(1970);
            final bDate = _coerceMortalityDate(b) ?? DateTime(1970);
            comparison = aDate.compareTo(bDate);
            break;
          case 'Age':
            final aAge = int.tryParse(a['age']?.toString() ?? '') ?? 0;
            final bAge = int.tryParse(b['age']?.toString() ?? '') ?? 0;
            comparison = aAge.compareTo(bAge);
            break;
          case 'Cause':
            final aCause = (a['causeOfDeath'] ?? a['cause'] ?? '')
                .toString()
                .toLowerCase();
            final bCause = (b['causeOfDeath'] ?? b['cause'] ?? '')
                .toString()
                .toLowerCase();
            comparison = aCause.compareTo(bCause);
            break;
          case 'Name':
          default:
            final aName = (a['name'] ?? a['patientName'] ?? '')
                .toString()
                .toLowerCase();
            final bName = (b['name'] ?? b['patientName'] ?? '')
                .toString()
                .toLowerCase();
            comparison = aName.compareTo(bName);
            break;
        }
        return _sortAscending ? comparison : -comparison;
      });

      _filteredRecords = _collapseCurrentRecords(filtered);
    });
  }

  void _filterRecords(String query) {
    _searchQuery = query.toLowerCase();
    _applyFilters();
  }

  Future<void> _showSharedPatientTimeline(Map<String, dynamic> patient) async {
    final snapshot = await _patientHistoryService.loadPatientHistory(patient);
    if (!mounted) {
      return;
    }

    await PatientHistoryDialogs.showPatientTimelineDialog(
      context: context,
      patient: patient,
      snapshot: snapshot,
    );
  }

  void _scheduleSharedPatientSearch(String query) {
    _sharedPatientSearchDebounce?.cancel();
    final normalizedQuery = query.trim();

    if (normalizedQuery.isEmpty) {
      if (!mounted) {
        return;
      }

      setState(() {
        _sharedPatientMatches = [];
        _isSearchingSharedPatients = false;
      });
      return;
    }

    setState(() {
      _isSearchingSharedPatients = true;
    });

    _sharedPatientSearchDebounce = Timer(
      const Duration(milliseconds: 250),
      () async {
        final results = await _patientHistoryService.searchPatients(
          normalizedQuery,
        );
        if (!mounted ||
            _searchQuery.trim().toLowerCase() !=
                normalizedQuery.toLowerCase()) {
          return;
        }

        setState(() {
          _sharedPatientMatches = results;
          _isSearchingSharedPatients = false;
        });
      },
    );
  }

  List<Map<String, dynamic>> _collapseCurrentRecords(
    List<Map<String, dynamic>> records,
  ) {
    return CurrentTableRecordUtils.collapseToLatestPerEntity(
      records,
      idKeys: const ['linkedPatientId', 'patientId'],
      nameKeys: const ['name', 'patientName', 'patient'],
      dateKeys: const ['dateReported', 'date', 'createdAt', 'timestamp'],
    );
  }

  Future<void> _generateMortalityReport() {
    return generateReportPdf(
      context: context,
      moduleLabel: 'Mortality',
      records: _filteredRecords,
      dateResolver: (record) =>
          parseReportDateValue(record['date']) ??
          parseReportDateValue(record['dateReported']),
      columns: [
        ReportCsvColumn('Record ID', (record) => reportText(record['id'])),
        ReportCsvColumn('Name', (record) => reportText(record['name'])),
        ReportCsvColumn(
          'Date of Death',
          (record) => formatReportDateValue(record['date']),
        ),
        ReportCsvColumn(
          'Cause of Death',
          (record) => reportText(record['causeOfDeath']),
        ),
        ReportCsvColumn('Place', (record) => reportText(record['place'])),
        ReportCsvColumn('Age', (record) => reportText(record['age'])),
        ReportCsvColumn('Gender', (record) => reportText(record['gender'])),
        ReportCsvColumn(
          'Verification Status',
          (record) => reportText(record['verification']),
        ),
        ReportCsvColumn(
          'Reported By',
          (record) => reportText(record['reportedBy']),
        ),
        ReportCsvColumn(
          'Date Reported',
          (record) => formatReportDateValue(record['dateReported']),
        ),
      ],
      accentColor: _primaryAqua,
      dialogColor: _sidebarDark,
      textColor: Colors.white,
      mutedColor: Colors.white70,
      sectionTitleBuilder: (record, index) =>
          'Record ${index + 1}: ${reportText(record['name'], fallback: 'Record')}',
    );
  }

  Color _getVerificationColor(String verification) {
    return verification.toLowerCase() == 'verified'
        ? const Color(0xFF4CAF50)
        : const Color(0xFFFFA726);
  }

  List<MonthlyTrend> _generateMonthlyTrends(
    List<Map<String, dynamic>> records,
  ) {
    Map<String, int> monthCounts = {
      'Aug': 0,
      'Sep': 0,
      'Oct': 0,
      'Nov': 0,
      'Dec': 0,
      'Jan': 0,
    };

    for (var record in records) {
      try {
        final recordDate = DateTime.parse(record['dateReported'] as String);
        final monthKey = [
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
        ][recordDate.month - 1];
        if (monthCounts.containsKey(monthKey)) {
          monthCounts[monthKey] = monthCounts[monthKey]! + 1;
        }
      } catch (e) {
        debugPrint('Error parsing date: $e');
      }
    }

    return [
      MonthlyTrend('Aug', monthCounts['Aug']!),
      MonthlyTrend('Sep', monthCounts['Sep']!),
      MonthlyTrend('Oct', monthCounts['Oct']!),
      MonthlyTrend('Nov', monthCounts['Nov']!),
      MonthlyTrend('Dec', monthCounts['Dec']!),
      MonthlyTrend('Jan', monthCounts['Jan']!),
    ];
  }

  List<CauseData> _generateCauseData(List<Map<String, dynamic>> records) {
    Map<String, int> causeCounts = {};

    for (var record in records) {
      final cause = record['causeOfDeath'] ?? 'Unknown';
      causeCounts[cause] = (causeCounts[cause] ?? 0) + 1;
    }

    final total = records.isEmpty ? 1 : records.length;
    final sorted = causeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Keep top 5 causes and group the rest as "Other"
    final topCauses = sorted.take(5).toList();
    int otherCount = 0;
    for (var i = 5; i < sorted.length; i++) {
      otherCount += sorted[i].value;
    }

    final result = topCauses.map((entry) {
      return CauseData(entry.key, entry.value, (entry.value / total) * 100);
    }).toList();

    // Add "Other" category if there are more than 5 causes
    if (otherCount > 0) {
      result.add(
        CauseData('Other Causes', otherCount, (otherCount / total) * 100),
      );
    }

    return result;
  }

  List<AgeDistribution> _generateAgeDistribution(
    List<Map<String, dynamic>> records,
  ) {
    Map<String, int> ageRangeCounts = {
      '0-18': 0,
      '19-40': 0,
      '41-60': 0,
      '61-80': 0,
      '81+': 0,
    };

    for (var record in records) {
      try {
        final age = int.parse(record['age'].toString());
        String range;
        if (age <= 18) {
          range = '0-18';
        } else if (age <= 40) {
          range = '19-40';
        } else if (age <= 60) {
          range = '41-60';
        } else if (age <= 80) {
          range = '61-80';
        } else {
          range = '81+';
        }

        ageRangeCounts[range] = ageRangeCounts[range]! + 1;
      } catch (e) {
        // Skip invalid age values
      }
    }

    final total = records.isEmpty ? 1 : records.length;

    return [
      AgeDistribution(
        '0-18',
        ageRangeCounts['0-18']!,
        (ageRangeCounts['0-18']! / total) * 100,
      ),
      AgeDistribution(
        '19-40',
        ageRangeCounts['19-40']!,
        (ageRangeCounts['19-40']! / total) * 100,
      ),
      AgeDistribution(
        '41-60',
        ageRangeCounts['41-60']!,
        (ageRangeCounts['41-60']! / total) * 100,
      ),
      AgeDistribution(
        '61-80',
        ageRangeCounts['61-80']!,
        (ageRangeCounts['61-80']! / total) * 100,
      ),
      AgeDistribution(
        '81+',
        ageRangeCounts['81+']!,
        (ageRangeCounts['81+']! / total) * 100,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.email?.split('@')[0] ?? 'User';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F7FA),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WebAppSidebar(
            userName: userName,
            activeItem: WebSidebarItem.mortality,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HealthModuleViewHeader(
                      title: 'Mortality Monitoring',
                      description:
                          'Review mortality trends and verified indicators, or manage individual mortality records.',
                      activeView: _activeView,
                      onViewChanged: _setActiveView,
                      primaryColor: _primaryAqua,
                    ),
                    const SizedBox(height: 20),
                    if (_activeView == HealthModuleView.insights) ...[
                      _buildInsightsFilterBar(),
                      const SizedBox(height: 20),
                      if (_isDataLoaded && _mortalityRecords.isEmpty)
                        const ModuleEmptyState(
                          title: 'No mortality insights yet',
                          message:
                              'Mortality trends and cause distributions will appear when verified records are available.',
                          icon: Icons.query_stats_rounded,
                        )
                      else ...[
                        _buildOverviewDashboard(),
                        const SizedBox(height: 20),
                        _buildGraphsSection(),
                        const SizedBox(height: 20),
                        _buildTablesSection(),
                      ],
                    ] else
                      _buildRecordsTableSection(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Overview Dashboard
  Widget _buildOverviewDashboard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryAqua.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Mortality Overview',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: _lightOffWhite,
                    letterSpacing: 0.5,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _primaryAqua.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _primaryAqua, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.pie_chart_rounded,
                        color: _primaryAqua,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Real-time Data',
                        style: TextStyle(
                          color: _lightOffWhite,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_isLoadingMetrics)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: _primaryAqua),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1100
                      ? 4
                      : constraints.maxWidth >= 680
                      ? 2
                      : 1;
                  const spacing = 16.0;
                  final width = columns == 1
                      ? constraints.maxWidth
                      : (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                  final cards = <Widget>[
                    _buildWebMetricCard(
                      title: 'Total Deaths',
                      value: _totalDeaths.toString(),
                      icon: Icons.assignment_outlined,
                    ),
                    _buildWebMetricCard(
                      title: 'Elderly Deaths',
                      value: _elderlyDeaths.toString(),
                      icon: Icons.elderly_outlined,
                    ),
                    _buildWebMetricCard(
                      title: 'Verification Rate',
                      value: '${_verificationRate.toStringAsFixed(1)}%',
                      icon: Icons.verified_user_outlined,
                    ),
                    _buildWebMetricCard(
                      title: 'Leading Cause',
                      value: _leadingCause,
                      icon: Icons.warning_amber_outlined,
                    ),
                  ];
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: cards
                        .map((card) => SizedBox(width: width, child: card))
                        .toList(growable: false),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebMetricCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return AppMetricCard(label: title, value: value, icon: icon);
  }

  // Graphs Section
  Widget _buildGraphsSection() {
    if (!_isDataLoaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: CircularProgressIndicator(color: _primaryAqua),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatsWebBar(),
        const SizedBox(height: 20),

        // Monthly Trends (Full Width Line Graph)
        if (_monthlyTrends.isNotEmpty)
          _buildWebGraphCard(
            title: 'Monthly Death Trends',
            subtitle: 'Deaths reported over 6 months',
            icon: Icons.trending_up_rounded,
            child: SizedBox(
              height: 300,
              child: charts.BarChart(
                [
                  charts.Series<MonthlyTrend, String>(
                    id: 'Deaths',
                    colorFn: (_, _) =>
                        charts.Color(r: 100, g: 181, b: 246, a: 255),
                    domainFn: (MonthlyTrend trend, _) => trend.month,
                    measureFn: (MonthlyTrend trend, _) => trend.deaths,
                    data: _monthlyTrends,
                  ),
                ],
                animate: true,
                vertical: true,
                barGroupingType: charts.BarGroupingType.groupedStacked,
                primaryMeasureAxis: const charts.NumericAxisSpec(
                  renderSpec: charts.GridlineRendererSpec(
                    labelStyle: charts.TextStyleSpec(
                      color: charts.Color(r: 255, g: 255, b: 255),
                      fontSize: 12,
                    ),
                  ),
                ),
                domainAxis: const charts.OrdinalAxisSpec(
                  renderSpec: charts.SmallTickRendererSpec(
                    labelStyle: charts.TextStyleSpec(
                      color: charts.Color(r: 255, g: 255, b: 255),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_causeData.isNotEmpty && _ageDistributions.isNotEmpty)
          const SizedBox(height: 24),

        // Two-Column Layout for Charts
        if (_causeData.isNotEmpty && _ageDistributions.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Leading Causes (Pie Chart with Legend)
              Expanded(
                flex: 1,
                child: _buildWebGraphCard(
                  title: 'Leading Causes of Death',
                  subtitle: 'Distribution by cause (Top 5)',
                  icon: Icons.pie_chart_rounded,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Hover Details Box
                      if (_selectedCause != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _primaryAqua.withValues(alpha: 0.15),
                                _primaryAqua.withValues(alpha: 0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _primaryAqua.withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _primaryAqua.withValues(alpha: 0.2),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_rounded,
                                color: _primaryAqua,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _selectedCause != null
                                      ? '${_selectedCause!.cause}: ${_selectedCause!.count} deaths (${_selectedCause!.percentage.toStringAsFixed(1)}%)'
                                      : '',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(
                        height: 250,
                        child: charts.PieChart<String>(
                          [
                            charts.Series<CauseData, String>(
                              id: 'Causes',
                              domainFn: (CauseData data, _) => data.cause,
                              measureFn: (CauseData data, _) => data.count,
                              data: _causeData,
                              labelAccessorFn: (CauseData data, _) => '',
                              colorFn: (CauseData data, int? index) {
                                final colors = _mortalityChartPalette
                                    .map(_toChartsColor)
                                    .toList(growable: false);
                                return colors[(index ?? 0) % colors.length];
                              },
                            ),
                          ],
                          animate: true,
                          defaultRenderer: charts.ArcRendererConfig<String>(
                            arcWidth: 120,
                            arcRendererDecorators: [],
                          ),
                          selectionModels: [
                            charts.SelectionModelConfig(
                              type: charts.SelectionModelType.info,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Enhanced Legend with white text
                      SizedBox(
                        height: 150,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _primaryAqua.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: _causeData.asMap().entries.map((
                                  entry,
                                ) {
                                  int idx = entry.key;
                                  CauseData cause = entry.value;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: MouseRegion(
                                      onEnter: (_) {
                                        setState(() {
                                          _selectedCause = cause;
                                        });
                                      },
                                      onExit: (_) {
                                        setState(() {
                                          _selectedCause = null;
                                        });
                                      },
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 20,
                                            height: 20,
                                            decoration: BoxDecoration(
                                              color:
                                                  _mortalityChartPalette[idx %
                                                      _mortalityChartPalette
                                                          .length],
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              boxShadow: [
                                                BoxShadow(
                                                  color:
                                                      _mortalityChartPalette[idx %
                                                              _mortalityChartPalette
                                                                  .length]
                                                          .withValues(
                                                            alpha: 0.5,
                                                          ),
                                                  blurRadius: 6,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  cause.cause,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${cause.count} deaths',
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _primaryAqua.withValues(
                                                alpha: 0.2,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: _primaryAqua.withValues(
                                                  alpha: 0.5,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              '${cause.percentage.toStringAsFixed(1)}%',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // Age Distribution (Bar Chart)
              Expanded(
                flex: 1,
                child: _buildWebGraphCard(
                  title: 'Age Distribution',
                  subtitle: 'Deaths by age group',
                  icon: Icons.bar_chart_rounded,
                  child: SizedBox(
                    height: 280,
                    child: charts.BarChart(
                      [
                        charts.Series<AgeDistribution, String>(
                          id: 'Ages',
                          colorFn: (_, _) => _toChartsColor(_secondaryIceBlue),
                          domainFn: (AgeDistribution dist, _) => dist.ageRange,
                          measureFn: (AgeDistribution dist, _) => dist.count,
                          data: _ageDistributions,
                        ),
                      ],
                      animate: true,
                      vertical: true,
                      barGroupingType: charts.BarGroupingType.groupedStacked,
                      primaryMeasureAxis: const charts.NumericAxisSpec(
                        renderSpec: charts.GridlineRendererSpec(
                          labelStyle: charts.TextStyleSpec(
                            color: charts.Color(r: 255, g: 255, b: 255),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      domainAxis: const charts.OrdinalAxisSpec(
                        renderSpec: charts.SmallTickRendererSpec(
                          labelStyle: charts.TextStyleSpec(
                            color: charts.Color(r: 255, g: 255, b: 255),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildStatsWebBar() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_sidebarDark, _sidebarDark.withValues(alpha: 0.8)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryAqua.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Statistical Analysis Dashboard',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Comprehensive mortality statistics and trends',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                _buildWebBarButton(
                  icon: Icons.refresh_rounded,
                  label: 'Refresh',
                  onPressed: _loadData,
                ),
                const SizedBox(width: 12),
                _buildWebBarButton(
                  icon: Icons.download_rounded,
                  label: 'Export',
                  onPressed: _generateMortalityReport,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebBarButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        hoverColor: _primaryAqua.withValues(alpha: 0.1),
        splashColor: _primaryAqua.withValues(alpha: 0.2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: _primaryAqua.withValues(alpha: 0.4),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, color: _primaryAqua, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebGraphCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _sidebarDark.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: _primaryAqua.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _primaryAqua.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: _primaryAqua, size: 24),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: child,
          ),
        ],
      ),
    );
  }

  // Tables Section
  Widget _buildTablesSection() {
    if (!_isDataLoaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: CircularProgressIndicator(color: _primaryAqua),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Detailed Statistics',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),

        // Two Column Layout for Tables
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cause of Death Table (Left Column)
              Expanded(flex: 1, child: _buildCauseTable()),
              const SizedBox(width: 16),
              // Age Distribution Table (Right Column)
              Expanded(flex: 1, child: _buildAgeTable()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCauseTable() {
    return WebTableSurface(
      minWidth: 620,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.table_chart_outlined,
                  color: _primaryAqua,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Cause of Death Breakdown',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _lightOffWhite,
                  ),
                ),
              ],
            ),
          ),
          DataTable(
            columns: [
              DataColumn(
                label: const Text(
                  'Cause of Death',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _lightOffWhite,
                  ),
                ),
              ),
              DataColumn(
                label: const Text(
                  'Percentage',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _lightOffWhite,
                  ),
                ),
              ),
              DataColumn(
                label: const Text(
                  'Progress',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _lightOffWhite,
                  ),
                ),
              ),
              DataColumn(
                label: const Text(
                  'Death Count',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _lightOffWhite,
                  ),
                ),
              ),
            ],
            rows: _causeData.map((cause) {
              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      cause.cause,
                      style: const TextStyle(color: _lightOffWhite),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${cause.percentage.toStringAsFixed(1)}%',
                      style: const TextStyle(color: _lightOffWhite),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 100,
                      child: LinearProgressIndicator(
                        value: cause.percentage / 100,
                        backgroundColor: AppColors.border,
                        valueColor: AlwaysStoppedAnimation<Color>(_primaryAqua),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      cause.count.toString(),
                      style: const TextStyle(color: _lightOffWhite),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAgeTable() {
    return WebTableSurface(
      minWidth: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.table_rows_outlined,
                  color: _primaryAqua,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Age Distribution',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _lightOffWhite,
                  ),
                ),
              ],
            ),
          ),
          DataTable(
            columns: [
              DataColumn(
                label: const Text(
                  'Age Range',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _lightOffWhite,
                  ),
                ),
              ),
              DataColumn(
                label: const Text(
                  'Death Count',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _lightOffWhite,
                  ),
                ),
              ),
              DataColumn(
                label: const Text(
                  'Percentage',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _lightOffWhite,
                  ),
                ),
              ),
            ],
            rows: _ageDistributions.map((age) {
              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      age.ageRange,
                      style: const TextStyle(color: _lightOffWhite),
                    ),
                  ),
                  DataCell(
                    Text(
                      age.count.toString(),
                      style: const TextStyle(color: _lightOffWhite),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${age.percentage.toStringAsFixed(1)}%',
                      style: const TextStyle(color: _lightOffWhite),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // Search Bar
  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13),
        decoration: InputDecoration(
          hintText:
              'Search by name, ID, cause of death, place, or verification...',
          hintStyle: TextStyle(
            color: const Color(0xFF0F172A).withValues(alpha: 0.5),
            fontSize: 13,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: _primaryAqua.withValues(alpha: 0.8),
            size: 18,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _filterRecords('');
                    _scheduleSharedPatientSearch('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
        onChanged: (value) {
          _filterRecords(value);
          _scheduleSharedPatientSearch(value);
        },
      ),
    );
  }

  Widget _buildFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Primary Filter Bar - Status + Date Range
        Row(
          children: [
            // Status Dropdown Container
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF3FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF2F80ED).withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedStatusFilter,
                    icon: const Icon(
                      Icons.filter_list,
                      color: Color(0xFF2F80ED),
                      size: 20,
                    ),
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    items: _statusFilterOptions.map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedStatusFilter = newValue;
                        });
                        _applyFilters();
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Date Range Container
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2F80ED).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF2F80ED).withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.date_range,
                      size: 16,
                      color: Color(0xFF2F80ED),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDatePickerButton(
                        label: 'From',
                        date: _fromDate,
                        onTap: () => _selectDateForMortality(true),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildDatePickerButton(
                        label: 'To',
                        date: _toDate,
                        onTap: () => _selectDateForMortality(false),
                      ),
                    ),
                    if (_fromDate != null || _toDate != null)
                      IconButton(
                        icon: const Icon(
                          Icons.clear,
                          size: 16,
                          color: Colors.red,
                        ),
                        onPressed: () {
                          setState(() {
                            _fromDate = null;
                            _toDate = null;
                          });
                          _applyFilters();
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Advanced Filters
        _buildMortalityAdvancedFilters(),
      ],
    );
  }

  Widget _buildMortalityAdvancedFilters() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double itemWidth = constraints.maxWidth < 700
            ? (constraints.maxWidth - 24) / 2
            : constraints.maxWidth < 1100
            ? (constraints.maxWidth - 48) / 4
            : (constraints.maxWidth - 64) / 5;
        final responsiveWidth = itemWidth.clamp(132.0, 178.0);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _registryDropdown(
                label: 'Barangay',
                value: _selectedBarangay,
                items: const [
                  'All',
                  'Barangay 1',
                  'Barangay 2',
                  'Barangay 3',
                  'Barangay 4',
                  'Barangay 5',
                  'Barangay 6',
                  'Barangay 7',
                  'Barangay 8',
                ],
                width: responsiveWidth,
                onChanged: (val) {
                  setState(() => _selectedBarangay = val ?? 'All');
                  _applyFilters();
                },
              ),
              _registryDropdown(
                label: 'Cause of Death',
                value: _selectedCauseFilter,
                items: const [
                  'All',
                  'Cardiovascular Disease',
                  'Pneumonia',
                  'Cancer',
                  'Stroke',
                  'Diabetes',
                  'Kidney Disease',
                  'Respiratory Disease',
                  'Accident',
                  'Other',
                ],
                width: responsiveWidth,
                onChanged: (val) {
                  setState(() => _selectedCauseFilter = val ?? 'All');
                  _applyFilters();
                },
              ),
              _registryDropdown(
                label: 'Age Group',
                value: _selectedAgeGroup,
                items: const ['All', '0–17', '18–59', '60+'],
                width: responsiveWidth,
                onChanged: (val) {
                  setState(() => _selectedAgeGroup = val ?? 'All');
                  _applyFilters();
                },
              ),
              _registryDropdown(
                label: 'Sex',
                value: _selectedSex,
                items: const ['All', 'Male', 'Female'],
                width: responsiveWidth,
                onChanged: (val) {
                  setState(() => _selectedSex = val ?? 'All');
                  _applyFilters();
                },
              ),
              _registryDropdown(
                label: 'Sort By',
                value: _sortField,
                items: const ['Name', 'Date of Death', 'Age', 'Cause'],
                width: responsiveWidth,
                onChanged: (val) {
                  setState(() => _sortField = val ?? 'Name');
                  _applyFilters();
                },
              ),
              IconButton.filledTonal(
                tooltip: _sortAscending ? 'Ascending' : 'Descending',
                icon: Icon(
                  _sortAscending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 18,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFEDF3FA),
                  foregroundColor: const Color(0xFF2F80ED),
                  padding: const EdgeInsets.all(10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                onPressed: () {
                  setState(() => _sortAscending = !_sortAscending);
                  _applyFilters();
                },
              ),
              if (_selectedBarangay != 'All' ||
                  _selectedCauseFilter != 'All' ||
                  _selectedAgeGroup != 'All' ||
                  _selectedSex != 'All' ||
                  _sortField != 'Name' ||
                  !_sortAscending ||
                  _selectedStatusFilter != 'All' ||
                  _fromDate != null ||
                  _toDate != null)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedBarangay = 'All';
                      _selectedCauseFilter = 'All';
                      _selectedAgeGroup = 'All';
                      _selectedSex = 'All';
                      _sortField = 'Name';
                      _sortAscending = true;
                      _selectedStatusFilter = 'All';
                      _fromDate = null;
                      _toDate = null;
                    });
                    _applyFilters();
                  },
                  icon: const Icon(
                    Icons.filter_alt_off_outlined,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                  label: const Text(
                    'Clear Filters',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _registryDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    double width = 140,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        initialValue: items.contains(value) ? value : items.first,
        isDense: true,
        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
          floatingLabelStyle: const TextStyle(
            fontSize: 12,
            color: Color(0xFF2F80ED),
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: Color(0xFF2F80ED), width: 1.5),
          ),
        ),
        items: items
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Text(
                  item,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildDatePickerButton({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF2F80ED).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              date == null ? label : '${date.day}/${date.month}',
              style: TextStyle(
                color: date == null
                    ? const Color(0xFF0F172A).withValues(alpha: 0.6)
                    : const Color(0xFF0F172A),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Icon(
              Icons.calendar_today,
              size: 12,
              color: Color(0xFF2F80ED),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDateForMortality(bool isFromDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primaryAqua,
              onPrimary: Colors.white,
              onSurface: _darkDeepTeal,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isFromDate) {
          _fromDate = picked;
          if (_toDate != null && _toDate!.isBefore(_fromDate!)) {
            _toDate = picked;
          }
        } else {
          _toDate = picked;
        }
      });
      _applyFilters();
    }
  }

  Widget _buildRecordsTitle() {
    return const Text(
      'Mortality Records',
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: _lightOffWhite,
      ),
    );
  }

  Widget _buildAddRecordButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showAddRecordDialog,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _primaryAqua,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.add_circle_outline_rounded,
                color: Colors.white,
                size: 18,
              ),
              SizedBox(width: 6),
              Text(
                'Add Record',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddRecordButtonContainer() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _primaryAqua.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
      child: _buildAddRecordButton(),
    );
  }

  Widget _buildRecordsTableSection() {
    final effectiveRowsPerPage = _rowsPerPage > 0 ? _rowsPerPage : 10;
    final totalRecords = _filteredRecords.length;
    final totalPages = totalRecords == 0
        ? 1
        : ((totalRecords + effectiveRowsPerPage - 1) ~/ effectiveRowsPerPage);
    final currentPage = _currentPage < 1
        ? 1
        : (_currentPage > totalPages ? totalPages : _currentPage);
    final pageStartIndex = totalRecords == 0
        ? 0
        : (currentPage - 1) * effectiveRowsPerPage;
    final pageEndIndex = totalRecords == 0
        ? 0
        : ((pageStartIndex + effectiveRowsPerPage) < totalRecords
              ? (pageStartIndex + effectiveRowsPerPage)
              : totalRecords);
    final pagedRecords = totalRecords == 0
        ? <Map<String, dynamic>>[]
        : _filteredRecords.sublist(pageStartIndex, pageEndIndex);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header: Title + Add Button
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _buildRecordsTitle()),
                const SizedBox(width: 16),
                _buildAddRecordButtonContainer(),
              ],
            ),
            const SizedBox(height: 12),
            _buildSearchBar(),
            if (_searchQuery.trim().isNotEmpty ||
                _isSearchingSharedPatients) ...[
              const SizedBox(height: 12),
              SharedPatientSearchPanel(
                query: _searchQuery,
                results: _sharedPatientMatches,
                isLoading: _isSearchingSharedPatients,
                primaryActionLabel: 'View Medical History',
                onPrimaryAction: _showSharedPatientTimeline,
                secondaryActionLabel: 'Add Mortality Record',
                onSecondaryAction: (patient) =>
                    _showAddRecordDialog(patientSeed: patient),
              ),
            ],
            const SizedBox(height: 12),
            _buildFilterSection(),
            const SizedBox(height: 16),
            if (pagedRecords.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: _primaryAqua.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.inbox_rounded,
                          color: _primaryAqua,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty
                            ? 'No records found'
                            : 'No results for "$_searchQuery"',
                        style: const TextStyle(
                          color: _lightOffWhite,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Try adjusting your search or add a new mortality record',
                        style: TextStyle(color: _mutedCoolGray, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              _buildMortalityTableHeader(),
              _buildMortalityTable(pagedRecords),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Showing ${pageStartIndex + 1}-$pageEndIndex of ${_filteredRecords.length} records',
                      style: TextStyle(
                        fontSize: 12,
                        color: _mutedCoolGray,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _primaryAqua.withValues(alpha: 0.25),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        dropdownColor: Colors.white,
                        value: effectiveRowsPerPage,
                        style: const TextStyle(
                          color: _lightOffWhite,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        iconEnabledColor: _lightOffWhite,
                        items: const [
                          DropdownMenuItem(value: 10, child: Text('10 / page')),
                          DropdownMenuItem(value: 20, child: Text('20 / page')),
                          DropdownMenuItem(value: 50, child: Text('50 / page')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _rowsPerPage = value > 0 ? value : 10;
                            _currentPage = 1;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: currentPage > 1
                        ? () {
                            setState(() {
                              _currentPage = currentPage - 1;
                            });
                          }
                        : null,
                    icon: const Icon(Icons.chevron_left),
                    color: _lightOffWhite,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _primaryAqua.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      '$currentPage / $totalPages',
                      style: const TextStyle(
                        color: _lightOffWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: currentPage < totalPages
                        ? () {
                            setState(() {
                              _currentPage = currentPage + 1;
                            });
                          }
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    color: _lightOffWhite,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeaderCell(String label, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildTableHeaderDivider() {
    return Container(
      width: 1,
      height: 18,
      color: Colors.white.withValues(alpha: 0.2),
    );
  }

  Widget _buildMortalityTableHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF163B66),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          _buildTableHeaderCell('Patient', flex: 30),
          _buildTableHeaderDivider(),
          _buildTableHeaderCell('Mortality Details', flex: 40),
          _buildTableHeaderDivider(),
          _buildTableHeaderCell('Verification', flex: 18),
          _buildTableHeaderDivider(),
          const SizedBox(
            width: 148,
            child: Text(
              'Actions',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMortalityTable(List<Map<String, dynamic>> records) {
    return Column(
      children: List.generate(records.length, (index) {
        return _buildMortalityTableRow(records[index]);
      }),
    );
  }

  String _safeText(dynamic value, [String fallback = 'N/A']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    final normalized = text.toLowerCase();
    if (text.isEmpty || normalized == 'null' || normalized == 'undefined') {
      return fallback;
    }
    return text;
  }

  Color _verificationChipBackground(String verification) {
    final lower = verification.toLowerCase();
    if (lower.contains('verified')) return const Color(0xFFDDE9D4);
    if (lower.contains('pending')) return const Color(0xFFFCE8CC);
    return const Color(0xFFDDE4F3);
  }

  Widget _buildRowDivider() {
    return Container(width: 1, height: 70, color: AppColors.border);
  }

  Widget _buildRowActionButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _primaryAqua,
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(
            color: _primaryAqua.withValues(alpha: 0.24),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, color: Colors.white, size: 15),
          ),
        ),
      ),
    );
  }

  Widget _buildMortalityTableRow(Map<String, dynamic> record) {
    final name = _safeText(
      record['name'] ?? record['patientName'] ?? record['patient'],
      'Unknown Patient',
    );
    final age = _safeText(record['age'], '-');
    final gender = _safeText(record['gender'] ?? record['sex'], 'Unknown');
    final cause = _safeText(
      record['causeOfDeath'] ?? record['cause'] ?? record['underlyingCause'],
      'No cause recorded',
    );
    final place = _safeText(
      record['place'] ?? record['placeOfDeath'] ?? record['address'],
      'No place recorded',
    );
    final reportedBy = _safeText(
      record['reportedBy'] ?? record['informant'] ?? record['bhwName'],
      'Unknown',
    );
    final verification = _safeText(
      record['verification'] ??
          record['status'] ??
          record['verificationStatus'],
      'Pending',
    );
    final reportedDate = _formatDate(
      record['dateReported'] ??
          record['date'] ??
          record['dateOfDeath'] ??
          record['createdAt'],
    );

    const rowText = AppColors.textPrimary;
    const mutedText = AppColors.textSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 30,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: rowText,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Age: $age years | $gender',
                    style: const TextStyle(
                      color: mutedText,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Reported: $reportedDate',
                    style: TextStyle(
                      color: mutedText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            _buildRowDivider(),
            Expanded(
              flex: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cause,
                      style: const TextStyle(
                        color: Color(0xFFE53935),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      place,
                      style: const TextStyle(
                        color: rowText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Reported by: $reportedBy',
                      style: TextStyle(
                        color: mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            _buildRowDivider(),
            Expanded(
              flex: 18,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _verificationChipBackground(verification),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        verification,
                        style: const TextStyle(
                          color: Color(0xFF163B66),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 6),
                    WebSyncStatusBadge(record: record),
                  ],
                ),
              ),
            ),
            _buildRowDivider(),
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 2),
              child: SizedBox(
                width: 148,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildRowActionButton(
                      icon: Icons.history_rounded,
                      onTap: () => _showMortalityHistory(context, record),
                    ),
                    const SizedBox(width: 6),
                    _buildRowActionButton(
                      icon: Icons.edit_rounded,
                      onTap: () => _editRecord(record),
                    ),
                    const SizedBox(width: 6),
                    _buildRowActionButton(
                      icon: Icons.verified_rounded,
                      onTap: () => _verifyRecord(record),
                    ),
                    const SizedBox(width: 6),
                    _buildRowActionButton(
                      icon: Icons.picture_as_pdf_rounded,
                      onTap: () => _printRecord(record),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic dateValue) {
    final dateString = (dateValue ?? '').toString().trim();
    if (dateString.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return '${date.month}/${date.day}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  List<Map<String, dynamic>> _getMortalityHistory(Map<String, dynamic> record) {
    return PatientHistoryDialogs.collectHistory(
      seedRecord: record,
      records: _mortalityRecords,
      idKeys: const ['linkedPatientId', 'patientId', 'id'],
      nameKeys: const ['name', 'patientName', 'patient'],
      sortDateKeys: const ['dateReported', 'date'],
    );
  }

  Map<String, dynamic> _buildPatientHistorySeed(Map<String, dynamic> record) {
    final patientName = _safeText(
      record['patientName'] ?? record['name'] ?? record['patient'],
      '',
    );
    final nameParts = patientName.isEmpty
        ? <String>[]
        : patientName.split(RegExp(r'\s+'));

    return {
      'id': record['linkedPatientId'] ?? record['patientId'] ?? record['id'],
      'patientId': record['patientId'] ?? record['linkedPatientId'] ?? '',
      'patientCode': record['patientCode'] ?? '',
      'patientName': patientName,
      'firstName': nameParts.isNotEmpty ? nameParts.first : '',
      'surname': nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '',
    };
  }

  Future<void> _showPatientMedicalHistory(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    final patient = _buildPatientHistorySeed(record);
    final snapshot = await _patientHistoryService.loadPatientHistory(patient);
    if (!context.mounted) {
      return;
    }

    await PatientHistoryDialogs.showPatientTimelineDialog(
      context: context,
      patient: patient,
      snapshot: snapshot,
    );
  }

  void _showMortalityHistory(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final history = _getMortalityHistory(record);
    PatientHistoryDialogs.showModuleHistoryDialog(
      context: context,
      moduleTitle: 'Mortality',
      seedRecord: record,
      history: history,
      description:
          'Review existing mortality reports for this patient before saving another death-related record.',
      addButtonLabel: 'Add Another Mortality Record',
      titleBuilder: (entry) =>
          (entry['causeOfDeath'] ?? 'Mortality report').toString(),
      subtitleBuilder: (entry) =>
          (entry['verification'] ?? 'Pending verification').toString(),
      metaBuilder: (entry) =>
          'Age: ${(entry['age'] ?? 'N/A').toString()} | Place: ${(entry['place'] ?? 'N/A').toString()}',
      dateKeys: const ['dateReported', 'date'],
      secondaryActionLabel: 'Medical History',
      onSecondaryAction: () => _showPatientMedicalHistory(context, record),
      onAddAnother: () => _showAddRecordDialog(
        patientSeed: history.isNotEmpty ? history.first : record,
      ),
      onOpenRecord: (entry) => _viewRecordDetails(entry),
    );
  }

  // Action Methods
  Future<void> _showAddRecordDialog({Map<String, dynamic>? patientSeed}) async {
    patientSeed = await _patientHistoryService.resolveRegisteredPatient(
      patientSeed,
    );
    if (!mounted) return;
    if (patientSeed == null) {
      patientSeed = await PatientFirstServiceSelector.selectRegisteredPatient(
        context,
        serviceLabel: 'Mortality',
        patientService: _patientHistoryService,
        onRegisterPatient: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const PatientRecordPage(openRegistrationOnLoad: true),
          ),
        ),
      );
      if (!mounted || patientSeed == null) return;
    }
    _showMortalityRecordDialog(patientSeed: patientSeed);
  }

  void _showMortalityRecordDialog({
    Map<String, dynamic>? record,
    Map<String, dynamic>? patientSeed,
  }) {
    final isEditing = record != null;
    final seedRecord = record ?? patientSeed;
    final nameController = TextEditingController(
      text: seedRecord == null
          ? ''
          : patientDisplayName(seedRecord, fallback: ''),
    );
    final ageController = TextEditingController(
      text: _safeText(seedRecord?['age'], ''),
    );
    final causeController = TextEditingController(
      text: isEditing ? _safeText(record['causeOfDeath'], '') : '',
    );
    final placeController = TextEditingController(
      text: isEditing
          ? _safeText(record['place'], '')
          : _safeText(seedRecord?['place'], ''),
    );
    final reportedByController = TextEditingController(
      text: isEditing
          ? _safeText(record['reportedBy'], '')
          : _safeText(seedRecord?['reportedBy'], ''),
    );
    const genderOptions = ['Male', 'Female', 'Other'];
    final initialGender = _safeText(seedRecord?['gender'], 'Male');
    String selectedGender = genderOptions.contains(initialGender)
        ? initialGender
        : 'Male';
    final verification = _safeText(record?['verification'], 'Pending');
    final recordId = record == null
        ? 'Assigned on save'
        : _safeText(record['id'], 'Unavailable');
    final modeAccent = isEditing ? const Color(0xFFFF7043) : _primaryAqua;
    final statusColor = _getVerificationColor(verification);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            color: const Color(0xFFF5F7FA),
            child: Column(
              children: [
                // Modal Header Bar
                Container(
                  height: 76,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    color: _darkDeepTeal,
                    border: Border(
                      bottom: BorderSide(color: Color(0x20FFFFFF), width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEditing
                                  ? 'Edit Mortality Record'
                                  : 'Create Mortality Record',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isEditing
                                  ? 'Refine patient and incident details with complete surveillance context.'
                                  : 'Capture a new mortality case with complete reporting details.',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Close modal',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                // Form Content Area
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Meta Chips Row
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _buildMortalityDialogMetaChip(
                                  icon: isEditing
                                      ? Icons.edit_note_rounded
                                      : Icons.add_task_rounded,
                                  label: 'Mode',
                                  value: isEditing
                                      ? 'Editing live record'
                                      : 'New entry',
                                  accentColor: modeAccent,
                                ),
                                _buildMortalityDialogMetaChip(
                                  icon: Icons.verified_outlined,
                                  label: 'Status',
                                  value: isEditing
                                      ? verification
                                      : 'Pending on save',
                                  accentColor: statusColor,
                                  valueColor: statusColor,
                                ),
                                _buildMortalityDialogMetaChip(
                                  icon: Icons.tag_outlined,
                                  label: 'Record ID',
                                  value: recordId,
                                  accentColor: const Color(0xFF64B5F6),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isCompact = constraints.maxWidth < 620;
                                final sectionWidth = isCompact
                                    ? constraints.maxWidth
                                    : (constraints.maxWidth - 16) / 2;

                                Widget ageField() => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildMortalityDialogFieldLabel('Age *'),
                                    TextField(
                                      controller: ageController,
                                      cursorColor: _primaryAqua,
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(
                                        color: _lightOffWhite,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      decoration:
                                          _buildMortalityDialogInputDecoration(
                                            hintText: 'e.g., 65',
                                            icon: Icons.cake_outlined,
                                          ),
                                    ),
                                  ],
                                );

                                Widget genderField() => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildMortalityDialogFieldLabel('Gender *'),
                                    DropdownButtonFormField<String>(
                                      initialValue: selectedGender,
                                      isExpanded: true,
                                      borderRadius: BorderRadius.circular(14),
                                      onChanged: (newValue) {
                                        setState(() {
                                          selectedGender = newValue ?? 'Male';
                                        });
                                      },
                                      dropdownColor: Colors.white,
                                      style: const TextStyle(
                                        color: _lightOffWhite,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      iconEnabledColor: _primaryAqua,
                                      items: genderOptions
                                          .map(
                                            (gender) => DropdownMenuItem(
                                              value: gender,
                                              child: Text(
                                                gender,
                                                style: const TextStyle(
                                                  color: _lightOffWhite,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      decoration:
                                          _buildMortalityDialogInputDecoration(
                                            hintText: 'Select gender',
                                            icon: Icons.wc_outlined,
                                          ),
                                    ),
                                  ],
                                );

                                return Wrap(
                                  spacing: 16,
                                  runSpacing: 16,
                                  children: [
                                    SizedBox(
                                      width: sectionWidth,
                                      child: _buildMortalityDialogSection(
                                        title: 'Patient Profile',
                                        subtitle:
                                            'Basic identity details used throughout the record.',
                                        icon: Icons.person_outline_rounded,
                                        accentColor: const Color(0xFF2F80ED),
                                        children: [
                                          _buildMortalityDialogFieldLabel(
                                            'Patient Name *',
                                          ),
                                          TextField(
                                            controller: nameController,
                                            cursorColor: _primaryAqua,
                                            style: const TextStyle(
                                              color: _lightOffWhite,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            decoration:
                                                _buildMortalityDialogInputDecoration(
                                                  hintText: 'Enter full name',
                                                  icon: Icons
                                                      .person_outline_rounded,
                                                ),
                                          ),
                                          const SizedBox(height: 16),
                                          if (isCompact) ...[
                                            ageField(),
                                            const SizedBox(height: 16),
                                            genderField(),
                                          ] else
                                            Row(
                                              children: [
                                                Expanded(child: ageField()),
                                                const SizedBox(width: 14),
                                                Expanded(child: genderField()),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: sectionWidth,
                                      child: _buildMortalityDialogSection(
                                        title: 'Incident Details',
                                        subtitle:
                                            'Mortality event details for surveillance logs.',
                                        icon: Icons.monitor_heart_outlined,
                                        accentColor: const Color(0xFFE57373),
                                        children: [
                                          _buildMortalityDialogFieldLabel(
                                            'Cause of Death *',
                                          ),
                                          TextField(
                                            controller: causeController,
                                            cursorColor: _primaryAqua,
                                            maxLines: 3,
                                            style: const TextStyle(
                                              color: _lightOffWhite,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          _buildMortalityDialogInfoTile(
                                            icon: Icons.verified_user_outlined,
                                            label: 'Verification',
                                            value: isEditing
                                                ? verification
                                                : 'Pending after creation',
                                            accentColor: statusColor,
                                            valueColor: statusColor,
                                          ),
                                          const SizedBox(height: 12),
                                          _buildMortalityDialogInfoTile(
                                            icon: Icons.rule_folder_outlined,
                                            label: 'Required fields',
                                            value:
                                                'Patient Name, Age, and Cause of Death',
                                            accentColor: const Color(
                                              0xFFFF9800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Bottom Action Bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: Colors.black.withValues(alpha: 0.08),
                        width: 1,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _lightOffWhite,
                          side: BorderSide(
                            color: Colors.black.withValues(alpha: 0.18),
                            width: 1.2,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: isEditing
                              ? const Color(0xFFE67E22)
                              : _primaryAqua,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                        ),
                        icon: Icon(
                          isEditing
                              ? Icons.save_as_rounded
                              : Icons.library_add_check_rounded,
                          size: 18,
                        ),
                        label: Text(
                          isEditing ? 'Update Record' : 'Save Record',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        onPressed: () async {
                          final didSave = isEditing
                              ? await _updateExistingRecord(
                                  record,
                                  nameController.text,
                                  ageController.text,
                                  selectedGender,
                                  causeController.text,
                                  placeController.text,
                                  reportedByController.text,
                                )
                              : await _addNewRecord(
                                  nameController.text,
                                  ageController.text,
                                  selectedGender,
                                  causeController.text,
                                  placeController.text,
                                  reportedByController.text,
                                  patientSeed!,
                                );

                          if (didSave && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMortalityDialogMetaChip({
    required IconData icon,
    required String label,
    required String value,
    required Color accentColor,
    Color? valueColor,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accentColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _mutedCoolGray,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: valueColor ?? _lightOffWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMortalityDialogSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _primaryAqua.withValues(alpha: 0.16),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 20),
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
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _mutedCoolGray,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildMortalityDialogFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          color: _mutedCoolGray,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  InputDecoration _buildMortalityDialogInputDecoration({
    required String hintText,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: _mutedCoolGray.withValues(alpha: 0.55),
        fontSize: 13.5,
        fontWeight: FontWeight.normal,
      ),
      filled: true,
      fillColor: Colors.white,
      prefixIcon: Icon(icon, color: _primaryAqua, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.black.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.black.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: _primaryAqua, width: 2),
      ),
    );
  }

  Widget _buildMortalityDialogNote({
    required String label,
    required String value,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.info_outline_rounded,
              color: accentColor,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _mutedCoolGray,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: _lightOffWhite,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMortalityDialogInfoTile({
    required IconData icon,
    required String label,
    required String value,
    required Color accentColor,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accentColor, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _mutedCoolGray,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? _lightOffWhite,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _addNewRecord(
    String name,
    String age,
    String gender,
    String cause,
    String place,
    String reportedBy,
    Map<String, dynamic> registeredPatient,
  ) async {
    final trimmedName = name.trim();
    final trimmedAge = age.trim();
    final trimmedCause = cause.trim();
    final trimmedPlace = place.trim();
    final trimmedReportedBy = reportedBy.trim();

    if (trimmedName.isEmpty || trimmedAge.isEmpty || trimmedCause.isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Please fill in all required fields (Name, Age, Cause of Death)',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFD84315),
        colorText: Colors.white,
      );
      return false;
    }

    final parsedAge = int.tryParse(trimmedAge);
    if (parsedAge == null) {
      Get.snackbar(
        'Validation Error',
        'Please enter a valid age.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFD84315),
        colorText: Colors.white,
      );
      return false;
    }

    try {
      final currentDate = DateTime.now().toString().split(' ')[0];
      final patientId =
          (registeredPatient['patientId'] ?? registeredPatient['id'] ?? '')
              .toString()
              .trim();
      final linkedPatientId =
          (registeredPatient['linkedPatientId'] ?? patientId).toString().trim();
      final newRecord = {
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'name': trimmedName,
        if (patientId.isNotEmpty) 'patientId': patientId,
        if (linkedPatientId.isNotEmpty) 'linkedPatientId': linkedPatientId,
        'date': currentDate,
        'month': _monthLabelForDate(currentDate),
        'age': parsedAge.toString(),
        'ageRange': _getAgeRange(parsedAge),
        'gender': gender,
        'causeOfDeath': trimmedCause,
        'place': trimmedPlace,
        'reportedBy': trimmedReportedBy,
        'verification': 'Pending',
        'dateReported': DateTime.now().toIso8601String(),
      };

      await _mortalityHelper.insertRecord(newRecord);

      Get.snackbar(
        'Success',
        'Record added successfully',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF4CAF50),
        colorText: Colors.white,
      );

      await _loadData();
      return true;
    } catch (e) {
      Get.snackbar(
        'Error',
        'Error adding record: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFD84315),
        colorText: Colors.white,
      );
      return false;
    }
  }

  Future<bool> _updateExistingRecord(
    Map<String, dynamic> existingRecord,
    String name,
    String age,
    String gender,
    String cause,
    String place,
    String reportedBy,
  ) async {
    final trimmedName = name.trim();
    final trimmedAge = age.trim();
    final trimmedCause = cause.trim();
    final trimmedPlace = place.trim();
    final trimmedReportedBy = reportedBy.trim();

    if (trimmedName.isEmpty || trimmedAge.isEmpty || trimmedCause.isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Please fill in all required fields (Name, Age, Cause of Death)',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFD84315),
        colorText: Colors.white,
      );
      return false;
    }

    final parsedAge = int.tryParse(trimmedAge);
    if (parsedAge == null) {
      Get.snackbar(
        'Validation Error',
        'Please enter a valid age.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFD84315),
        colorText: Colors.white,
      );
      return false;
    }

    try {
      final preservedDate = _safeText(
        existingRecord['date'],
        DateTime.now().toString().split(' ')[0],
      );
      final updatedRecord = Map<String, dynamic>.from(existingRecord)
        ..addAll({
          'name': trimmedName,
          'date': preservedDate,
          'month': _monthLabelForDate(
            preservedDate,
            fallback: _safeText(existingRecord['month'], ''),
          ),
          'age': parsedAge.toString(),
          'ageRange': _getAgeRange(parsedAge),
          'gender': gender,
          'causeOfDeath': trimmedCause,
          'place': trimmedPlace,
          'reportedBy': trimmedReportedBy,
          'verification': _safeText(existingRecord['verification'], 'Pending'),
          'dateReported':
              existingRecord['dateReported']?.toString() ??
              DateTime.now().toIso8601String(),
        });

      await _mortalityHelper.updateRecord(updatedRecord);

      Get.snackbar(
        'Success',
        'Record updated successfully',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF4CAF50),
        colorText: Colors.white,
      );

      await _loadData();
      return true;
    } catch (e) {
      Get.snackbar(
        'Error',
        'Error updating record: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFD84315),
        colorText: Colors.white,
      );
      return false;
    }
  }

  String _getAgeRange(int age) {
    if (age <= 18) return '0-18';
    if (age <= 40) return '19-40';
    if (age <= 60) return '41-60';
    if (age <= 80) return '61-80';
    return '81+';
  }

  String _monthLabelForDate(String dateValue, {String fallback = ''}) {
    const monthLabels = [
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

    final normalizedDate = dateValue.trim();
    if (normalizedDate.isNotEmpty) {
      try {
        final parsedDate = DateTime.parse(normalizedDate);
        return monthLabels[parsedDate.month - 1];
      } catch (_) {}
    }

    if (fallback.trim().isNotEmpty) {
      return fallback.trim();
    }

    return monthLabels[DateTime.now().month - 1];
  }

  void _viewRecordDetails(Map<String, dynamic> record) {
    final name = _safeText(record['name'], 'Unknown');
    final age = _safeText(record['age'], '-');
    final gender = _safeText(record['gender'], 'Unknown');
    final cause = _safeText(record['causeOfDeath'], 'No cause recorded');
    final place = _safeText(record['place'], 'No place recorded');
    final reportedBy = _safeText(record['reportedBy'], 'Unknown');
    final verification = _safeText(record['verification'], 'Pending');
    final recordId = _safeText(record['id'], 'No record ID');
    final patientId = _safeText(
      record['linkedPatientId'] ?? record['patientId'],
      '',
    );
    final dateOfDeath = _formatDate(record['date']);
    final reportedDate = _formatDate(record['dateReported'] ?? record['date']);
    showFullscreenDetailTableDialog(
      context: context,
      title: 'Mortality Record Details',
      subject: name,
      items: [
        DetailTableItem(
          icon: Icons.badge_outlined,
          label: 'Record ID',
          value: recordId,
        ),
        DetailTableItem(
          icon: Icons.credit_card_outlined,
          label: 'Patient ID',
          value: patientId,
        ),
        DetailTableItem(
          icon: Icons.person_outline_rounded,
          label: 'Patient Name',
          value: name,
        ),
        DetailTableItem(icon: Icons.cake_outlined, label: 'Age', value: age),
        DetailTableItem(
          icon: Icons.wc_outlined,
          label: 'Gender',
          value: gender,
        ),
        DetailTableItem(
          icon: Icons.coronavirus_outlined,
          label: 'Cause of Death',
          value: cause,
        ),
        DetailTableItem(
          icon: Icons.place_outlined,
          label: 'Place',
          value: place,
        ),
        DetailTableItem(
          icon: Icons.event_busy_outlined,
          label: 'Date of Death',
          value: dateOfDeath,
        ),
        DetailTableItem(
          icon: Icons.calendar_today_outlined,
          label: 'Date Reported',
          value: reportedDate,
        ),
        DetailTableItem(
          icon: Icons.verified_outlined,
          label: 'Verification',
          value: verification,
        ),
        DetailTableItem(
          icon: Icons.person_pin_outlined,
          label: 'Reported By',
          value: reportedBy,
        ),
        DetailTableItem(
          icon: Icons.notes_outlined,
          label: 'Remarks',
          value: _safeText(record['remarks'], ''),
        ),
      ],
    );
    return;
  }

  void _editRecord(Map<String, dynamic> record) {
    _showMortalityRecordDialog(record: record);
  }

  void _verifyRecord(Map<String, dynamic> record) {
    final name = _safeText(record['name'], 'Unknown');
    final age = _safeText(record['age'], '-');
    final gender = _safeText(record['gender'], 'Unknown');
    final verification = _safeText(record['verification'], 'Pending');
    final place = _safeText(record['place'], 'No place recorded');
    final cause = _safeText(record['causeOfDeath'], 'No cause recorded');
    final reportedBy = _safeText(record['reportedBy'], 'Unknown');
    final reportedDate = _formatDate(record['dateReported'] ?? record['date']);
    final recordId = _safeText(record['id'], 'Unavailable');
    final alreadyVerified = verification.toLowerCase().contains('verified');
    final initials = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.substring(0, 1).toUpperCase())
        .join();

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (dialogContext) {
        final screenSize = MediaQuery.of(dialogContext).size;
        final isCompact = screenSize.width < 720;
        final primaryAccent = alreadyVerified
            ? const Color(0xFF66BB6A)
            : const Color(0xFF81C784);
        final secondaryAccent = alreadyVerified
            ? const Color(0xFF2E7D32)
            : const Color(0xFF43A047);
        final dialogBorderColor = primaryAccent.withValues(alpha: 0.22);

        Widget impactTile({
          required IconData icon,
          required String title,
          required String subtitle,
        }) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: primaryAccent.withValues(alpha: 0.12)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: primaryAccent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: primaryAccent, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.64),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(
            horizontal: isCompact ? 16 : 28,
            vertical: 24,
          ),
          child: Container(
            constraints: BoxConstraints(maxWidth: isCompact ? 520 : 640),
            decoration: BoxDecoration(
              color: _darkDeepTeal,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: dialogBorderColor, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.36),
                  blurRadius: 30,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(isCompact ? 20 : 22),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: alreadyVerified
                            ? const [Color(0xFF23443A), Color(0xFF10261F)]
                            : const [Color(0xFF1A4A38), Color(0xFF0D274D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [primaryAccent, secondaryAccent],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryAccent.withValues(
                                      alpha: 0.24,
                                    ),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: alreadyVerified
                                    ? const Icon(
                                        Icons.verified_rounded,
                                        color: Colors.white,
                                        size: 28,
                                      )
                                    : Text(
                                        initials.isEmpty ? 'MR' : initials,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    alreadyVerified
                                        ? 'Record Already Verified'
                                        : 'Confirm Verification',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 23,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    alreadyVerified
                                        ? 'This mortality record is already secured as verified and reflected in record status tracking.'
                                        : 'Review the record snapshot below before finalizing verification for this mortality case.',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.72,
                                      ),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => Navigator.of(dialogContext).pop(),
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                primaryAccent.withValues(alpha: 0.18),
                                Colors.white.withValues(alpha: 0.02),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: primaryAccent.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: primaryAccent.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  alreadyVerified
                                      ? Icons.fact_check_rounded
                                      : Icons.gpp_good_rounded,
                                  color: primaryAccent,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      alreadyVerified
                                          ? 'Verification already completed'
                                          : 'Ready to promote this case to verified',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      alreadyVerified
                                          ? 'No additional action is needed unless the record must be edited later.'
                                          : 'Confirming will change the case status from Pending to Verified and refresh the dashboard metrics.',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.68,
                                        ),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: primaryAccent.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  verification,
                                  style: TextStyle(
                                    color: primaryAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(isCompact ? 18 : 22),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final sectionWidth = isCompact
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 16) / 2;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _buildMortalityDialogMetaChip(
                                    icon: Icons.person_outline_rounded,
                                    label: 'Patient',
                                    value: name,
                                    accentColor: const Color(0xFF64B5F6),
                                  ),
                                  _buildMortalityDialogMetaChip(
                                    icon: Icons.calendar_today_outlined,
                                    label: 'Reported',
                                    value: reportedDate,
                                    accentColor: const Color(0xFFFFB74D),
                                  ),
                                  _buildMortalityDialogMetaChip(
                                    icon: Icons.verified_outlined,
                                    label: 'Status',
                                    value: verification,
                                    accentColor: primaryAccent,
                                    valueColor: primaryAccent,
                                  ),
                                  _buildMortalityDialogMetaChip(
                                    icon: Icons.tag_outlined,
                                    label: 'Record ID',
                                    value: recordId,
                                    accentColor: primaryAccent,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                children: [
                                  SizedBox(
                                    width: sectionWidth,
                                    child: _buildMortalityDialogSection(
                                      title: 'Record Snapshot',
                                      subtitle:
                                          'Core patient and reporting details used for verification review.',
                                      icon: Icons.folder_open_outlined,
                                      accentColor: const Color(0xFF64B5F6),
                                      children: [
                                        _buildMortalityDialogInfoTile(
                                          icon: Icons.person_outline_rounded,
                                          label: 'Patient',
                                          value: '$name, $age years, $gender',
                                          accentColor: const Color(0xFF64B5F6),
                                        ),
                                        const SizedBox(height: 12),
                                        _buildMortalityDialogInfoTile(
                                          icon: Icons.person_search_outlined,
                                          label: 'Reported By',
                                          value: reportedBy,
                                          accentColor: const Color(0xFF81C784),
                                        ),
                                        const SizedBox(height: 12),
                                        _buildMortalityDialogInfoTile(
                                          icon: Icons.location_on_outlined,
                                          label: 'Place',
                                          value: place,
                                          accentColor: const Color(0xFFFFB74D),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: sectionWidth,
                                    child: _buildMortalityDialogSection(
                                      title: alreadyVerified
                                          ? 'Verification Outcome'
                                          : 'Verification Impact',
                                      subtitle: alreadyVerified
                                          ? 'This case already meets the verified status requirement.'
                                          : 'These updates will happen immediately after you confirm.',
                                      icon: alreadyVerified
                                          ? Icons.verified_user_outlined
                                          : Icons.privacy_tip_outlined,
                                      accentColor: primaryAccent,
                                      children: [
                                        impactTile(
                                          icon: Icons.sync_alt_rounded,
                                          title: alreadyVerified
                                              ? 'Status already confirmed'
                                              : 'Status will switch to Verified',
                                          subtitle: alreadyVerified
                                              ? 'The record is no longer waiting for review.'
                                              : 'Pending will be replaced with Verified in the records table.',
                                        ),
                                        const SizedBox(height: 12),
                                        impactTile(
                                          icon: Icons
                                              .dashboard_customize_outlined,
                                          title:
                                              'Dashboard metrics stay aligned',
                                          subtitle:
                                              'Mortality totals and verification rate will reflect the latest saved status.',
                                        ),
                                        const SizedBox(height: 12),
                                        impactTile(
                                          icon: Icons.fact_check_outlined,
                                          title: 'Review confidence improves',
                                          subtitle:
                                              'Verified cases are easier to distinguish during audits, exports, and reporting.',
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildMortalityDialogSection(
                                title: 'Clinical Review',
                                subtitle: alreadyVerified
                                    ? 'Diagnosis and verification context already attached to this verified case.'
                                    : 'Use these case details as the last checkpoint before confirming verification.',
                                icon: Icons.monitor_heart_outlined,
                                accentColor: const Color(0xFFE57373),
                                children: [
                                  _buildMortalityDialogInfoTile(
                                    icon: Icons.coronavirus_outlined,
                                    label: 'Cause of Death',
                                    value: cause,
                                    accentColor: const Color(0xFFE57373),
                                  ),
                                  const SizedBox(height: 12),
                                  _buildMortalityDialogInfoTile(
                                    icon: Icons.verified_outlined,
                                    label: 'Current Status',
                                    value: verification,
                                    accentColor: primaryAccent,
                                    valueColor: primaryAccent,
                                  ),
                                  if (!alreadyVerified) ...[
                                    const SizedBox(height: 12),
                                    _buildMortalityDialogNote(
                                      label: 'Verification note',
                                      value:
                                          'Verification is best used after you have reviewed the patient details, cause of death, and reporting source for accuracy.',
                                      accentColor: primaryAccent,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      isCompact ? 18 : 22,
                      10,
                      isCompact ? 18 : 22,
                      isCompact ? 18 : 22,
                    ),
                    decoration: BoxDecoration(
                      color: _sidebarDark.withValues(alpha: 0.8),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.06),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.03,
                            ),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(alreadyVerified ? 'Close' : 'Cancel'),
                        ),
                        if (!alreadyVerified) ...[
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: primaryAccent,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryAccent.withValues(alpha: 0.24),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                Navigator.of(dialogContext).pop();
                                await _confirmRecordVerification(record);
                              },
                              icon: const Icon(
                                Icons.verified_user_rounded,
                                size: 18,
                              ),
                              label: const Text('Verify Record'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryAqua,
                                foregroundColor: Colors.white,
                                shadowColor: Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmRecordVerification(Map<String, dynamic> record) async {
    final name = _safeText(record['name'], 'Unknown');

    try {
      final updatedRecord = Map<String, dynamic>.from(record)
        ..['verification'] = 'Verified';

      await _mortalityHelper.updateRecord(updatedRecord);
      await _loadData();

      Get.snackbar(
        'Verification Complete',
        '$name has been marked as verified.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF4CAF50),
        colorText: Colors.white,
      );
    } catch (e) {
      Get.snackbar(
        'Verification Failed',
        'Unable to verify $name: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFFD84315),
        colorText: Colors.white,
      );
    }
  }

  Future<void> _printRecord(Map<String, dynamic> record) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF607D8B)),
      ),
    );

    // Let the loading dialog paint before running synchronous PDF work.
    await Future<void>.delayed(const Duration(milliseconds: 16));

    try {
      final pdfBytes = await buildMortalityPdfBytes(record);
      final filename = buildMortalityPdfFilename(record);
      final downloaded = downloadFile(
        bytes: pdfBytes,
        filename: filename,
        mimeType: 'application/pdf',
      );

      Get.snackbar(
        downloaded ? 'PDF Generated' : 'PDF Unsupported',
        downloaded
            ? 'PDF generated for ${record['name']}'
            : 'PDF generation is not supported on this platform.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: downloaded ? const Color(0xFF607D8B) : Colors.orange,
        colorText: Colors.white,
      );
    } catch (e) {
      Get.snackbar(
        'PDF Error',
        'Failed to generate mortality PDF: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }
}

// Data Models for Charts
class MonthlyTrend {
  final String month;
  final int deaths;

  MonthlyTrend(this.month, this.deaths);
}

class CauseData {
  final String cause;
  final int count;
  final double percentage;

  CauseData(this.cause, this.count, this.percentage);
}

class AgeDistribution {
  final String ageRange;
  final int count;
  final double percentage;

  AgeDistribution(this.ageRange, this.count, this.percentage);
}
