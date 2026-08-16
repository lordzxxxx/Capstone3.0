import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/roles/bhw/analytics/ai_summary.dart'
    as ai;
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/shared/components/app_buttons.dart';
import 'package:mycapstone_project/web/shared/components/web_data_components.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

const Color _primaryAqua = Color(0xFF2F80ED);
const Color _darkDeepTeal = Color(0xFF071A33);
const Color _panelTeal = Colors.white;
const Color _panelTealSoft = Color(0xFFEDF3FA);
const Color _lightOffWhite = Color(0xFF0B1F3A);
const Color _mutedCoolGray = Color(0xFF4B6075);
// Keep this operational page on the shared clinical-blue palette. Semantic
// warning/success colors belong to actual status messages, not decoration.
const Color _signalGreen = _primaryAqua;
const Color _signalAmber = _primaryAqua;

class HealthMetricsPage extends StatefulWidget {
  const HealthMetricsPage({super.key});

  @override
  State<HealthMetricsPage> createState() => _HealthMetricsPageState();
}

class _HealthMetricsPageState extends State<HealthMetricsPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final Future<UserAccessScope> _accessScopeFuture;

  String _selectedPeriod = 'Daily';
  DateTime _selectedDate = DateTime.now();
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;

  bool _isLoading = false;
  String _summary = '';
  String _summaryTitle = '';
  DateTime? _generatedAt;

  @override
  void initState() {
    super.initState();
    _accessScopeFuture = UserAccessScopeService.instance.loadCurrentScope();
    _normalizeSelectionState();
  }

  String get _effectivePeriod {
    try {
      final period = _selectedPeriod;
      if (period == 'Daily' || period == 'Monthly' || period == 'Yearly') {
        return period;
      }
    } catch (_) {}
    return 'Daily';
  }

  DateTime _fallbackNow() => DateTime.now();

  DateTime get _effectiveSelectedDate {
    DateTime rawDate;
    try {
      rawDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
    } catch (_) {
      rawDate = _fallbackNow();
    }

    final safeYear = _readSafeYear(rawDate);
    final safeMonth = _readSafeMonth(rawDate);
    final maxDay = DateTime(safeYear, safeMonth + 1, 0).day;
    final safeDay = rawDate.day.clamp(1, maxDay).toInt();

    return DateTime(safeYear, safeMonth, safeDay);
  }

  int get _effectiveYear => _readSafeYear(_effectiveSelectedDate);

  int get _effectiveMonth => _readSafeMonth(_effectiveSelectedDate);

  int _readSafeYear(DateTime fallbackDate) {
    try {
      final year = _selectedYear;
      if (year >= 1 && year <= 9999) {
        return year;
      }
    } catch (_) {}
    return fallbackDate.year;
  }

  int _readSafeMonth(DateTime fallbackDate) {
    try {
      final month = _selectedMonth;
      if (month >= 1 && month <= 12) {
        return month;
      }
    } catch (_) {}
    return fallbackDate.month;
  }

  void _normalizeSelectionState() {
    final safeDate = _effectiveSelectedDate;
    _selectedDate = safeDate;
    _selectedYear = safeDate.year;
    _selectedMonth = safeDate.month;
    _selectedPeriod = _effectivePeriod;
  }

  String get _effectiveSummary {
    try {
      final value = _summary;
      return value;
    } catch (_) {
      return '';
    }
  }

  String get _effectiveSummaryTitle {
    try {
      final value = _summaryTitle;
      return value;
    } catch (_) {
      return '';
    }
  }

  DateTime? get _effectiveGeneratedAt {
    try {
      final value = _generatedAt;
      if (value is! DateTime) {
        return null;
      }
      return DateTime(
        value.year,
        value.month,
        value.day,
        value.hour,
        value.minute,
        value.second,
        value.millisecond,
        value.microsecond,
      );
    } catch (_) {
      return null;
    }
  }

  String get _storageType => _effectivePeriod.toLowerCase();

  String get _storagePeriod {
    if (_effectivePeriod == 'Daily') {
      return DateFormat('yyyy-MM-dd').format(_effectiveSelectedDate);
    }
    if (_effectivePeriod == 'Monthly') {
      return '$_effectiveYear-${_effectiveMonth.toString().padLeft(2, '0')}';
    }
    return '$_effectiveYear';
  }

  String get _currentPeriodLabel {
    if (_effectivePeriod == 'Daily') {
      return DateFormat.yMMMMd().format(_effectiveSelectedDate);
    }
    if (_effectivePeriod == 'Monthly') {
      return DateFormat.yMMMM().format(
        DateTime(_effectiveYear, _effectiveMonth),
      );
    }
    return _effectiveYear.toString();
  }

  String get _currentWindowHint {
    if (_effectivePeriod == 'Daily') {
      return 'Focuses on activity recorded on the selected day.';
    }
    if (_effectivePeriod == 'Monthly') {
      return 'Combines all records captured within the selected month.';
    }
    return 'Builds a wider operational view for the selected year.';
  }

  IconData get _currentPeriodIcon {
    if (_effectivePeriod == 'Daily') {
      return Icons.today_rounded;
    }
    if (_effectivePeriod == 'Monthly') {
      return Icons.calendar_view_month_rounded;
    }
    return Icons.date_range_rounded;
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveSelectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primaryAqua,
              onPrimary: _darkDeepTeal,
              surface: _lightOffWhite,
              onSurface: _darkDeepTeal,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _selectedDate = picked;
      _selectedYear = picked.year;
      _selectedMonth = picked.month;
    });
  }

  void _updateSelectedMonth(int month) {
    final baseDate = _effectiveSelectedDate;
    final baseYear = _effectiveYear;
    final daysInMonth = DateTime(baseYear, month + 1, 0).day;
    final safeDay = baseDate.day.clamp(1, daysInMonth).toInt();

    setState(() {
      _selectedMonth = month;
      _selectedDate = DateTime(baseYear, month, safeDay);
      _selectedYear = baseYear;
    });
  }

  void _updateSelectedYear(int year) {
    final baseDate = _effectiveSelectedDate;
    final baseMonth = _effectiveMonth;
    final daysInMonth = DateTime(year, baseMonth + 1, 0).day;
    final safeDay = baseDate.day.clamp(1, daysInMonth).toInt();

    setState(() {
      _selectedYear = year;
      _selectedMonth = baseMonth;
      _selectedDate = DateTime(year, baseMonth, safeDay);
    });
  }

  Future<void> _generateSummary() async {
    setState(() => _isLoading = true);

    try {
      final period = _effectivePeriod;
      final selectedDate = _effectiveSelectedDate;
      final selectedYear = _effectiveYear;
      final selectedMonth = _effectiveMonth;

      late final String result;
      late final String title;

      if (period == 'Daily') {
        result = await ai.generateDailySummaryForCurrentUser(selectedDate);
        title = 'Daily Summary - ${DateFormat.yMMMd().format(selectedDate)}';
      } else if (period == 'Monthly') {
        result = await ai.generateMonthlySummaryForCurrentUser(
          selectedYear,
          selectedMonth,
        );
        title =
            'Monthly Summary - ${DateFormat.yMMMM().format(DateTime(selectedYear, selectedMonth))}';
      } else {
        result = await ai.generateYearlySummaryForCurrentUser(selectedYear);
        title = 'Yearly Summary - $selectedYear';
      }

      final generatedAt = DateTime.now();
      if (!mounted) {
        return;
      }

      setState(() {
        _summary = result;
        _summaryTitle = title;
        _generatedAt = generatedAt;
      });

      await _saveSummaryToFirestore(
        type: _storageType,
        period: _storagePeriod,
        title: title,
        text: result,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _panelTealSoft,
          content: Text(
            'Summary generated for $_currentPeriodLabel',
            style: const TextStyle(color: _lightOffWhite),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF7A2F2F),
          content: Text(
            'Error generating summary: $e',
            style: const TextStyle(color: _lightOffWhite),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveSummaryToFirestore({
    required String type,
    required String period,
    required String title,
    required String text,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final firestore = getFirestoreInstance();
      final accessScope = await _accessScopeFuture;
      final payload = applyBarangayScopeToRecord({
        'patientId': user?.uid ?? 'anonymous',
        'generatedByUid': user?.uid,
        'generatedByEmail': user?.email,
        'type': type,
        'period': period,
        'title': title,
        'text': text,
        'generatedAt': FieldValue.serverTimestamp(),
      }, accessScope: accessScope);
      final documentId = firestore.collection('summary_records').doc().id;
      final documentRef = await resolveScopedRecordDocumentReference(
        firestore,
        'summary_records',
        documentId,
        accessScope: accessScope,
        record: payload,
      );

      await documentRef.set(payload, SetOptions(merge: true));
    } catch (_) {
      // Summary generation should still succeed even if history persistence fails.
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _savedSummaryStream(
    UserAccessScope accessScope,
  ) {
    final firestore = getFirestoreInstance();

    return buildScopedRecordQuery(
      firestore,
      'summary_records',
      accessScope,
    ).orderBy('generatedAt', descending: true).limit(24).snapshots();
  }

  void _copySummaryToClipboard() {
    final summary = _effectiveSummary;
    if (summary.isEmpty) {
      return;
    }

    Clipboard.setData(ClipboardData(text: summary));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Summary copied to clipboard')),
    );
  }

  void _clearSummary() {
    setState(() {
      _summary = '';
      _summaryTitle = '';
      _generatedAt = null;
    });
  }

  void _loadSavedSummary(Map<String, dynamic> data) {
    final generatedAt = data['generatedAt'];

    setState(() {
      _summary = (data['text'] as String?) ?? '';
      _summaryTitle =
          (data['title'] as String?) ?? 'Saved Summary - $_currentPeriodLabel';
      _generatedAt = generatedAt is Timestamp ? generatedAt.toDate() : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.email?.split('@')[0] ?? 'User';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.backgroundLight,
      drawer: WebAppSidebar(
        userName: userName,
        activeItem: WebSidebarItem.summaryGeneration,
      ),
      appBar: AppBar(
        backgroundColor: _darkDeepTeal,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Summary Generation',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Operational reporting workspace',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
      body: ColoredBox(
        color: AppColors.backgroundLight,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1320),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroSection(userName),
                  const SizedBox(height: 20),
                  _buildOverviewCards(),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 1080;

                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 4,
                              child: _buildControlPanel(context),
                            ),
                            const SizedBox(width: 24),
                            Expanded(flex: 6, child: _buildSummaryPanel()),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          _buildControlPanel(context),
                          const SizedBox(height: 24),
                          _buildSummaryPanel(),
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
    );
  }

  Widget _buildHeroSection(String userName) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _panelTeal,
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.22)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120B1F3A),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final vertical = constraints.maxWidth < 760;

              if (vertical) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroIntro(userName),
                    const SizedBox(height: 20),
                    _buildHeroScopeCard(),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: _buildHeroIntro(userName)),
                  const SizedBox(width: 20),
                  Expanded(flex: 4, child: _buildHeroScopeCard()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeroIntro(String userName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Generate cleaner, faster health summaries for $userName.',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: _lightOffWhite,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'This page pulls together check-up, patient, prenatal, immunization, morbidity, mortality, and barangay records into one reporting surface with reusable saved summaries.',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: _mutedCoolGray, height: 1.5),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ContextItem(
              icon: _currentPeriodIcon,
              label: _effectivePeriod,
              accent: _primaryAqua,
            ),
            _ContextItem(
              icon: Icons.event_available_rounded,
              label: _currentPeriodLabel,
              accent: _signalGreen,
            ),
            const _ContextItem(
              icon: Icons.save_rounded,
              label: 'Auto-save history',
              accent: _signalAmber,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeroScopeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panelTealSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.timeline_rounded, color: _primaryAqua),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Current reporting scope',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _lightOffWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ScopeLine(label: 'Window', value: _currentPeriodLabel),
          const SizedBox(height: 10),
          _ScopeLine(label: 'Mode', value: _effectivePeriod),
          const SizedBox(height: 10),
          _ScopeLine(label: 'Focus', value: _currentWindowHint),
        ],
      ),
    );
  }

  Widget _buildOverviewCards() {
    final summary = _effectiveSummary;
    final generatedAt = _effectiveGeneratedAt;
    final generatedLabel = generatedAt == null
        ? 'Not generated'
        : DateFormat.yMMMd().add_jm().format(generatedAt);

    final cards = [
      _DashboardInfoCard(
        label: 'Selected Mode',
        value: _effectivePeriod,
        icon: _currentPeriodIcon,
        accent: _primaryAqua,
      ),
      _DashboardInfoCard(
        label: 'Scope',
        value: _currentPeriodLabel,
        icon: Icons.filter_alt_rounded,
        accent: _signalGreen,
      ),
      _DashboardInfoCard(
        label: 'Summary Status',
        value: summary.isEmpty ? 'Ready to run' : 'Generated',
        icon: summary.isEmpty ? Icons.pending_actions : Icons.check_circle,
        accent: summary.isEmpty ? _signalAmber : _signalGreen,
      ),
      _DashboardInfoCard(
        label: 'Last Update',
        value: generatedLabel,
        icon: Icons.history_rounded,
        accent: _signalAmber,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1040
            ? 4
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        final width = (constraints.maxWidth - (14 * (columns - 1))) / columns;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: cards
              .map((card) => SizedBox(width: width, child: card))
              .toList(growable: false),
        );
      },
    );
  }

  Widget _buildControlPanel(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _primaryAqua.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.tune_rounded, color: _primaryAqua),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Generation Controls',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _lightOffWhite,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pick a reporting window, review the scope, then generate a structured operational summary.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _mutedCoolGray,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Summary Mode',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _lightOffWhite,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PeriodOptionButton(
                label: 'Daily',
                icon: Icons.today_rounded,
                isSelected: _effectivePeriod == 'Daily',
                onTap: () => setState(() => _selectedPeriod = 'Daily'),
              ),
              _PeriodOptionButton(
                label: 'Monthly',
                icon: Icons.calendar_view_month_rounded,
                isSelected: _effectivePeriod == 'Monthly',
                onTap: () => setState(() => _selectedPeriod = 'Monthly'),
              ),
              _PeriodOptionButton(
                label: 'Yearly',
                icon: Icons.date_range_rounded,
                isSelected: _effectivePeriod == 'Yearly',
                onTap: () => setState(() => _selectedPeriod = 'Yearly'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Date Context',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _lightOffWhite,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (_effectivePeriod == 'Daily') _buildDailyDateCard(context),
          if (_effectivePeriod == 'Monthly') _buildMonthlySelector(),
          if (_effectivePeriod == 'Yearly') _buildYearSelector(),
          const SizedBox(height: 20),
          _buildScopePreview(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _generateSummary,
              style: AppButtonStyles.report(),
              icon: _isLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(
                _isLoading ? 'Generating summary...' : 'Generate Summary',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Generated reports are saved so you can reopen the latest summary for the same period without rerunning immediately.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: _mutedCoolGray, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyDateCard(BuildContext context) {
    return InkWell(
      onTap: () => _selectDate(context),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _panelTealSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _primaryAqua.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.calendar_today_rounded,
                color: _primaryAqua,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected day',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: _mutedCoolGray),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat.yMMMMEEEEd().format(_effectiveSelectedDate),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _lightOffWhite,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_calendar_rounded, color: _primaryAqua),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlySelector() {
    return Column(
      children: [
        _buildDropdownField<int>(
          label: 'Month',
          value: _effectiveMonth,
          items: List.generate(12, (index) => index + 1)
              .map(
                (month) => DropdownMenuItem<int>(
                  value: month,
                  child: Text(DateFormat.MMMM().format(DateTime(2024, month))),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              _updateSelectedMonth(value);
            }
          },
        ),
        const SizedBox(height: 14),
        _buildDropdownField<int>(
          label: 'Year',
          value: _effectiveYear,
          items: List.generate(10, (index) => DateTime.now().year - index)
              .map(
                (year) => DropdownMenuItem<int>(
                  value: year,
                  child: Text(year.toString()),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              _updateSelectedYear(value);
            }
          },
        ),
      ],
    );
  }

  Widget _buildYearSelector() {
    return _buildDropdownField<int>(
      label: 'Year',
      value: _effectiveYear,
      items: List.generate(10, (index) => DateTime.now().year - index)
          .map(
            (year) => DropdownMenuItem<int>(
              value: year,
              child: Text(year.toString()),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          _updateSelectedYear(value);
        }
      },
    );
  }

  Widget _buildDropdownField<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return WebFilterDropdown<T>(
      label: label,
      value: value,
      width: double.infinity,
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildScopePreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panelTealSoft.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.visibility_rounded,
                color: _signalGreen,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Scope Preview',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _lightOffWhite,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _currentWindowHint,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _mutedCoolGray,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _MiniSourceTag(label: 'Check-up'),
              _MiniSourceTag(label: 'Patient'),
              _MiniSourceTag(label: 'Prenatal'),
              _MiniSourceTag(label: 'Immunization'),
              _MiniSourceTag(label: 'Morbidity'),
              _MiniSourceTag(label: 'Mortality'),
              _MiniSourceTag(label: 'Barangay'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryPanel() {
    final summary = _effectiveSummary;
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 760;
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSummaryHeaderText(),
                    const SizedBox(height: 14),
                    _buildSummaryActions(),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildSummaryHeaderText()),
                  const SizedBox(width: 16),
                  _buildSummaryActions(),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _panelTealSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: summary.isEmpty
                ? _buildEmptySummaryState()
                : _SummaryViewer(summary: summary),
          ),
          const SizedBox(height: 24),
          Text(
            'Saved History',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _lightOffWhite,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Recent summaries for the same period can be reopened below.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _mutedCoolGray),
          ),
          const SizedBox(height: 16),
          FutureBuilder<UserAccessScope>(
            future: _accessScopeFuture,
            builder: (context, accessScopeSnapshot) {
              if (accessScopeSnapshot.hasError) {
                return Text(
                  'Saved summaries could not be loaded right now.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: _mutedCoolGray),
                );
              }

              if (!accessScopeSnapshot.hasData) {
                return const SizedBox(
                  height: 44,
                  child: Center(
                    child: CircularProgressIndicator(color: _primaryAqua),
                  ),
                );
              }

              final currentUserId =
                  FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _savedSummaryStream(accessScopeSnapshot.data!),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text(
                      'Saved summaries could not be loaded right now.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: _mutedCoolGray),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const SizedBox(
                      height: 44,
                      child: Center(
                        child: CircularProgressIndicator(color: _primaryAqua),
                      ),
                    );
                  }

                  final docs = snapshot.data!.docs.where((doc) {
                    final data = doc.data();
                    return data['patientId'] == currentUserId &&
                        data['type'] == _storageType &&
                        data['period'] == _storagePeriod;
                  }).toList();

                  if (docs.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: _panelTealSoft.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _primaryAqua.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Text(
                        'No saved summaries for $_currentPeriodLabel yet.',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: _mutedCoolGray),
                      ),
                    );
                  }

                  return Column(
                    children: docs.take(3).map((doc) {
                      final data = doc.data();
                      final generatedAt = data['generatedAt'];
                      final when = generatedAt is Timestamp
                          ? DateFormat.yMMMd().add_jm().format(
                              generatedAt.toDate(),
                            )
                          : 'Recent';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SavedSummaryCard(
                          title: (data['title'] as String?) ?? 'Saved Summary',
                          subtitle: when,
                          excerpt: (data['text'] as String?) ?? '',
                          onOpen: () => _loadSavedSummary(data),
                        ),
                      );
                    }).toList(),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeaderText() {
    final summaryTitle = _effectiveSummaryTitle;
    final generatedAt = _effectiveGeneratedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          summaryTitle.isEmpty ? 'Generated Summary' : summaryTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: _lightOffWhite,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          generatedAt == null
              ? 'No summary report has been generated for this view yet.'
              : 'Generated ${DateFormat.yMMMd().add_jm().format(generatedAt)}',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: _mutedCoolGray),
        ),
      ],
    );
  }

  Widget _buildSummaryActions() {
    final summary = _effectiveSummary;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: summary.isEmpty ? null : _copySummaryToClipboard,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: _primaryAqua.withValues(alpha: 0.28)),
            foregroundColor: _lightOffWhite,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy'),
        ),
        OutlinedButton.icon(
          onPressed: summary.isEmpty ? null : _clearSummary,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: _signalAmber.withValues(alpha: 0.28)),
            foregroundColor: _lightOffWhite,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.clear_rounded, size: 18),
          label: const Text('Clear'),
        ),
      ],
    );
  }

  Widget _buildEmptySummaryState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _primaryAqua.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.summarize_rounded, color: _primaryAqua),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No summary generated yet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _lightOffWhite,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Run Summary Generation to produce a formatted report with metrics, alerts, and recommended actions.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _mutedCoolGray,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _EmptyStateBullet(
          text: 'Structured coverage by source collection',
        ),
        const SizedBox(height: 10),
        const _EmptyStateBullet(
          text: 'Health metrics and trend-oriented operational signals',
        ),
        const SizedBox(height: 10),
        const _EmptyStateBullet(
          text: 'Alert detection and follow-up recommendations',
        ),
      ],
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  final Widget child;

  const _SurfaceCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _panelTeal,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120B1F3A),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ContextItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _ContextItem({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: _lightOffWhite,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 2),
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
      ],
    );
  }
}

class _ScopeLine extends StatelessWidget {
  final String label;
  final String value;

  const _ScopeLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: _mutedCoolGray),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _lightOffWhite,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _DashboardInfoCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  const _DashboardInfoCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _mutedCoolGray),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _lightOffWhite,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodOptionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _PeriodOptionButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? _primaryAqua.withValues(alpha: 0.16)
              : _panelTealSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? _primaryAqua
                : _primaryAqua.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? _primaryAqua : _mutedCoolGray,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: _lightOffWhite,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniSourceTag extends StatelessWidget {
  final String label;

  const _MiniSourceTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _panelTealSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: _lightOffWhite,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SavedSummaryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String excerpt;
  final VoidCallback onOpen;

  const _SavedSummaryCard({
    required this.title,
    required this.subtitle,
    required this.excerpt,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _primaryAqua.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.description_rounded, color: _primaryAqua),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: _lightOffWhite,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: _mutedCoolGray),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    excerpt,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.open_in_new_rounded, color: _mutedCoolGray),
          ],
        ),
      ),
    );
  }
}

class _SummaryViewer extends StatelessWidget {
  final String summary;

  const _SummaryViewer({required this.summary});

  bool _isHeading(String line) {
    return line.isNotEmpty &&
        line == line.toUpperCase() &&
        !line.startsWith('- ') &&
        line.length <= 40;
  }

  @override
  Widget build(BuildContext context) {
    final lines = summary.split('\n');

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines.map((line) {
          final trimmed = line.trimRight();

          if (trimmed.isEmpty) {
            return const SizedBox(height: 12);
          }

          if (_isHeading(trimmed)) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                trimmed,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _primaryAqua,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            );
          }

          if (trimmed.startsWith('Period:')) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                trimmed,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _signalGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }

          if (trimmed.startsWith('- ')) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 7),
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: _primaryAqua,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      trimmed.substring(2),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _lightOffWhite,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              trimmed,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _lightOffWhite,
                height: 1.55,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _EmptyStateBullet extends StatelessWidget {
  final String text;

  const _EmptyStateBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 7),
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: _signalGreen,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
