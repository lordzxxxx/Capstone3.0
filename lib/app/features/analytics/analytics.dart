import 'package:flutter/material.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart'
    as charts;
import 'package:mycapstone_project/app/features/checkups/checkup_analytics.dart';
import 'package:mycapstone_project/app/dev/barangay_test_data_seeder.dart';
import 'package:mycapstone_project/app/features/surveillance/communicable/communicable.dart';
import 'package:mycapstone_project/app/features/surveillance/communicable/communicable_analytics.dart';
import 'package:mycapstone_project/app/features/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/app/features/immunization/immunization.dart';
import 'package:mycapstone_project/app/features/immunization/immunization_analytics.dart';
import 'package:mycapstone_project/app/features/surveillance/morbidity/morbidity.dart';
import 'package:mycapstone_project/app/features/surveillance/mortality/mortality.dart';
import 'package:mycapstone_project/app/features/surveillance/mortality/mortality_analytics.dart';
import 'package:mycapstone_project/app/features/surveillance/non_communicable/non_communicable.dart';
import 'package:mycapstone_project/app/features/surveillance/non_communicable/non_communicable_analytics.dart';
import 'package:mycapstone_project/app/features/patients/patient_analytics.dart';
import 'package:mycapstone_project/app/features/patients/patient_database_helper.dart';
import 'package:mycapstone_project/app/features/prenatal/prenatal.dart';
import 'package:mycapstone_project/app/features/prenatal/prenatal_analytics.dart';
import 'package:mycapstone_project/app/features/prenatal/prenatal_database_helper.dart';
import 'package:mycapstone_project/app/features/immunization/immunization_database_helper.dart';
import 'package:mycapstone_project/app/features/surveillance/morbidity/morbidity_database_helper.dart';
import 'package:mycapstone_project/app/features/surveillance/mortality/mortality_database_helper.dart';
import 'package:mycapstone_project/app/features/referrals/referral_analytics.dart';
import 'dart:async';
import 'package:mycapstone_project/app/theme/app_theme.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _secondaryIceBlue = AppDesign.blueSoft;
const Color _darkDeepTeal = AppDesign.page;
const Color _mutedCoolGray = AppDesign.muted;
const Color _lightOffWhite = AppDesign.ink;
const Color _panelTop = AppDesign.surface;
const Color _panelBottom = AppDesign.surface;
const Color _panelStroke = AppDesign.border;

String _formatRelativeTime(DateTime dateTime) {
  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.inSeconds < 60) {
    return 'just now';
  } else if (difference.inMinutes < 60) {
    return '${difference.inMinutes}m ago';
  } else if (difference.inHours < 24) {
    return '${difference.inHours}h ago';
  } else {
    return '${difference.inDays}d ago';
  }
}

String _compactChartLabel(String value, {int maxLength = 12}) {
  final normalized = value.trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return '${normalized.substring(0, maxLength - 1)}…';
}

String _compactChartLabelAscii(String value, {int maxLength = 12}) {
  return _compactChartLabel(
    value,
    maxLength: maxLength,
  ).replaceAll('â€¦', '...');
}

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final DatabaseHelper _checkupDB = DatabaseHelper.instance;
  final PrenatalDatabaseHelper _prenatalDB = PrenatalDatabaseHelper.instance;
  final ImmunizationDatabaseHelper _immunizationDB =
      ImmunizationDatabaseHelper.instance;
  final MorbidityDatabaseHelper _morbidityDB = MorbidityDatabaseHelper.instance;
  final MortalityDatabaseHelper _mortalityDB = MortalityDatabaseHelper.instance;
  final PatientDatabaseHelper _patientDB = PatientDatabaseHelper.instance;

  List<Map<String, dynamic>> _checkupRecords = [];
  List<Map<String, dynamic>> _prenatalRecords = [];
  List<Map<String, dynamic>> _immunizationRecords = [];

  bool _isLoading = true;
  bool _isSeeding = false;
  Timer? _refreshTimer;
  DateTime? _lastUpdated;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _patientMetricsSectionKey = GlobalKey();
  final GlobalKey _keyStatisticsSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadAllData();
    // Refresh data every 5 seconds for real-time Blood Pressure updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadAllData(syncFirebase: false);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData({bool syncFirebase = true}) async {
    try {
      if (syncFirebase) await _syncAnalyticsSources();
      final checkup = await _checkupDB.getAllRecords();
      final prenatal = await _prenatalDB.getAllRecords();
      final immunization = await _immunizationDB.getAllRecords();

      if (mounted) {
        setState(() {
          _checkupRecords = checkup;
          _prenatalRecords = prenatal;
          _immunizationRecords = immunization;
          _lastUpdated = DateTime.now();
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading analytics data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _syncAnalyticsSources() async {
    final syncOperations = <Future<void> Function()>[
      _checkupDB.syncFromFirebase,
      _morbidityDB.syncFromFirebase,
      _prenatalDB.syncFromFirebase,
      _immunizationDB.syncFromFirebase,
      _mortalityDB.syncFromFirebase,
    ];

    for (final sync in syncOperations) {
      try {
        await sync();
      } catch (_) {
        // Preserve offline analytics by falling back to the local cache.
      }
    }
  }

  Future<void> _seedSharedModuleData() async {
    if (_isSeeding) return;
    setState(() => _isSeeding = true);

    try {
      final result = await BarangayTestDataSeeder.seed();

      await Future.wait([
        _checkupDB.syncFromFirebase(),
        _morbidityDB.syncFromFirebase(),
        _prenatalDB.syncFromFirebase(),
        _immunizationDB.syncFromFirebase(),
        _mortalityDB.syncFromFirebase(),
        _patientDB.syncFromFirebase(),
      ]);
      await _loadAllData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Seeded ${result.recordCount} test records for ${result.barangay}. Other barangays were not changed.',
            ),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to complete data seeding: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  int get _totalPatients => _checkupRecords.length + _prenatalRecords.length;
  int get _activePrenatalCases =>
      _prenatalRecords.where((r) => r['status'] == 'Active').length;
  int get _thisMonthCheckups {
    final now = DateTime.now();
    return _checkupRecords.where((record) {
      try {
        final date = DateTime.parse(record['datetime'] ?? '');
        return date.year == now.year && date.month == now.month;
      } catch (e) {
        return false;
      }
    }).length;
  }

  void _scrollToSection(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return;

    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildManagementModulesSection(BuildContext context) {
    final modules = <Map<String, dynamic>>[
      {
        'label': 'Check Up',
        'icon': Icons.medical_services_outlined,
        'color': AppDesign.checkUp,
        'onTap': () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CheckUpAnalyticsPage())),
      },
      {
        'label': 'Morbidity',
        'icon': Icons.healing_outlined,
        'color': AppDesign.morbidity,
        'onTap': () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const MorbidityPage(analyticsOnly: true),
          ),
        ),
      },
      {
        'label': 'Prenatal Care',
        'icon': Icons.pregnant_woman_rounded,
        'color': AppDesign.prenatal,
        'onTap': () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PrenatalAnalyticsPage()),
        ),
      },
      {
        'label': 'Immunization',
        'icon': Icons.vaccines_rounded,
        'color': AppDesign.immunization,
        'onTap': () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ImmunizationAnalyticsPage()),
        ),
      },
      {
        'label': 'Patient Records',
        'icon': Icons.folder_shared_rounded,
        'color': AppDesign.patientRecords,
        'onTap': () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PatientAnalyticsPage())),
      },
      {
        'label': 'Communicable',
        'icon': Icons.coronavirus_rounded,
        'color': AppDesign.communicable,
        'onTap': () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CommunicableAnalyticsPage()),
        ),
      },
      {
        'label': 'Non Communicable Disease',
        'icon': Icons.biotech_rounded,
        'color': AppDesign.nonCommunicable,
        'onTap': () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const NonCommunicableAnalyticsPage(),
          ),
        ),
      },
      {
        'label': 'Mortality',
        'icon': Icons.sick_rounded,
        'color': AppDesign.mortality,
        'onTap': () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MortalityAnalyticsPage()),
        ),
      },
      {
        'label': 'Referrals',
        'icon': Icons.call_split_rounded,
        'color': AppDesign.referrals,
        'onTap': () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ReferralAnalyticsPage()),
        ),
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Management Modules',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: _lightOffWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 18),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 18,
            mainAxisSpacing: 18,
            childAspectRatio: 1.15,
          ),
          itemCount: modules.length,
          itemBuilder: (context, index) {
            final module = modules[index];
            return _buildHubStyleButton(
              icon: module['icon'] as IconData,
              label: module['label'] as String,
              accent: _primaryAqua,
              onTap: module['onTap'] as void Function(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAnalyticsHubSection(BuildContext context) {
    final categories = <Map<String, dynamic>>[
      {
        'title': 'Patient Metrics',
        'subtitle':
            'BMI, blood pressure, demographics and immunization insights',
        'icon': Icons.bar_chart_rounded,
        'color': _primaryAqua,
        'buttons': <Map<String, dynamic>>[
          {
            'label': 'BMI Distribution',
            'icon': Icons.pie_chart_rounded,
            'onTap': () => _scrollToSection(_patientMetricsSectionKey),
          },
          {
            'label': 'Blood Pressure',
            'icon': Icons.monitor_heart_rounded,
            'onTap': () => _scrollToSection(_patientMetricsSectionKey),
          },
          {
            'label': 'Demographics',
            'icon': Icons.groups_rounded,
            'onTap': () => _scrollToSection(_patientMetricsSectionKey),
          },
          {
            'label': 'Immunization',
            'icon': Icons.vaccines_rounded,
            'onTap': () => _scrollToSection(_patientMetricsSectionKey),
          },
        ],
      },
      {
        'title': 'Key Statistics',
        'subtitle': 'Quick access to summary metrics and overview cards',
        'icon': Icons.insights_rounded,
        'color': AppDesign.teal,
        'buttons': <Map<String, dynamic>>[
          {
            'label': 'Summary Overview',
            'icon': Icons.dashboard_customize_rounded,
            'onTap': () => _scrollToSection(_keyStatisticsSectionKey),
          },
        ],
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Analytics Hub',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: _lightOffWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a category to open the related analytics view.',
          style: TextStyle(
            color: _lightOffWhite.withValues(alpha: 0.72),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 14),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: categories.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final category = categories[index];
            final buttons = category['buttons'] as List<Map<String, dynamic>>;
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _panelBottom.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (category['color'] as Color).withValues(alpha: 0.22),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (category['color'] as Color).withValues(
                            alpha: 0.16,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          category['icon'] as IconData,
                          color: category['color'] as Color,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              category['title'] as String,
                              style: const TextStyle(
                                color: _lightOffWhite,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              category['subtitle'] as String,
                              style: TextStyle(
                                color: _lightOffWhite.withValues(alpha: 0.72),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.12,
                        ),
                    itemCount: buttons.length,
                    itemBuilder: (context, buttonIndex) {
                      final button = buttons[buttonIndex];
                      return _buildHubStyleButton(
                        icon: button['icon'] as IconData,
                        label: button['label'] as String,
                        accent: category['color'] as Color,
                        onTap: button['onTap'] as void Function(),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHubStyleButton({
    required IconData icon,
    required String label,
    Color accent = AppDesign.blue,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: AppDesign.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppDesign.border),
            boxShadow: [
              BoxShadow(
                color: AppDesign.navy.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.45),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(icon, color: accent, size: 48),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _lightOffWhite,
                      fontSize: 12.8,
                      fontWeight: FontWeight.w800,
                      height: 1.18,
                      letterSpacing: 0.12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 380;
    final horizontalPadding = isCompact ? 14.0 : 16.0;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: _darkDeepTeal,
        appBar: AppBar(
          backgroundColor: _darkDeepTeal,
          title: Text(
            'Analytics',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: _lightOffWhite,
              fontWeight: FontWeight.bold,
            ),
          ),
          iconTheme: const IconThemeData(color: _lightOffWhite),
          elevation: 0,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: _primaryAqua),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _darkDeepTeal,
      appBar: AppBar(
        backgroundColor: _darkDeepTeal,
        title: Text(
          'Analytics',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: _lightOffWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: _lightOffWhite),
        elevation: 0,
        actions: [
          IconButton(
            icon: _isSeeding
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _primaryAqua,
                    ),
                  )
                : const Icon(Icons.science_rounded),
            tooltip: 'Seed assigned barangay test data',
            onPressed: _isSeeding ? null : _seedSharedModuleData,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: _loadAllData,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          isCompact ? 14 : 18,
          horizontalPadding,
          24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_buildManagementModulesSection(context)],
        ),
      ),
    );
  }
}

class _AnalyticsSummarySection extends StatelessWidget {
  final int totalPatients;
  final int activeCases;
  final int checkupsThisMonth;

  const _AnalyticsSummarySection({
    required this.totalPatients,
    required this.activeCases,
    required this.checkupsThisMonth,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            title: 'Total Patients',
            value: totalPatients.toString(),
            icon: Icons.people,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            title: 'Active Cases',
            value: activeCases.toString(),
            icon: Icons.assignment,
            color: Colors.orange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            title: 'Check-ups This Month',
            value: checkupsThisMonth.toString(),
            icon: Icons.calendar_today,
            color: Colors.purple,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _lightOffWhite.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _lightOffWhite,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              color: _lightOffWhite,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: _lightOffWhite,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _GraphCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? badge;
  final IconData icon;
  final double height;
  final Widget child;

  const _GraphCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.height,
    required this.child,
  }) : badge = null;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 360;
        final headerPadding = isCompact ? 16.0 : 18.0;

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _panelTop.withValues(alpha: 0.98),
                _panelBottom.withValues(alpha: 0.98),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _panelStroke.withValues(alpha: 0.75),
              width: 1.15,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: _primaryAqua.withValues(alpha: 0.06),
                blurRadius: 24,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  headerPadding,
                  headerPadding,
                  headerPadding,
                  14,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: isCompact ? 42 : 48,
                      height: isCompact ? 42 : 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          colors: [
                            _primaryAqua.withValues(alpha: 0.24),
                            _primaryAqua.withValues(alpha: 0.10),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: _primaryAqua.withValues(alpha: 0.26),
                        ),
                      ),
                      child: Icon(
                        icon,
                        color: _primaryAqua,
                        size: isCompact ? 19 : 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: isCompact ? 14 : 15,
                              fontWeight: FontWeight.w700,
                              color: _lightOffWhite,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: isCompact ? 11 : 12,
                              height: 1.4,
                              color: _lightOffWhite.withValues(alpha: 0.68),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _lightOffWhite.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _lightOffWhite.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Text(
                          badge!,
                          style: TextStyle(
                            fontSize: isCompact ? 10 : 11,
                            color: _lightOffWhite.withValues(alpha: 0.78),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Divider(height: 0, color: _lightOffWhite.withValues(alpha: 0.08)),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  headerPadding,
                  14,
                  headerPadding,
                  headerPadding,
                ),
                child: SizedBox(height: height, child: child),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChartStatusRow extends StatelessWidget {
  final DateTime? lastUpdated;
  final bool isUpdating;

  const _ChartStatusRow({required this.lastUpdated, required this.isUpdating});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _lightOffWhite.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _lightOffWhite.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(
            isUpdating ? Icons.sync_rounded : Icons.schedule_rounded,
            size: 15,
            color: isUpdating ? _primaryAqua : _mutedCoolGray,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              lastUpdated == null
                  ? 'Waiting for synced records'
                  : 'Updated ${_formatRelativeTime(lastUpdated!)}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: _mutedCoolGray,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          if (isUpdating)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(_primaryAqua),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _lightOffWhite,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _lightOffWhite.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendPill extends StatelessWidget {
  final String label;
  final String? value;
  final Color color;

  const _LegendPill({required this.label, required this.color, this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _lightOffWhite.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _lightOffWhite.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value == null ? label : '$label  $value',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _lightOffWhite.withValues(alpha: 0.84),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartEmptyState extends StatelessWidget {
  final String message;

  const _ChartEmptyState(this.message);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: _lightOffWhite.withValues(alpha: 0.66),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _BuildBMIChart extends StatefulWidget {
  final List<Map<String, dynamic>> records;
  final DateTime? lastUpdated;

  const _BuildBMIChart({required this.records}) : lastUpdated = null;

  @override
  State<_BuildBMIChart> createState() => _BuildBMIChartState();
}

class _BuildBMIChartState extends State<_BuildBMIChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  int _underweight = 0;
  int _normal = 0;
  int _overweight = 0;
  int _obese = 0;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _calculateBMIDistribution();
  }

  @override
  void didUpdateWidget(_BuildBMIChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload data when records change
    if (oldWidget.records != widget.records ||
        oldWidget.lastUpdated != widget.lastUpdated) {
      _calculateBMIDistribution();
    }
  }

  void _calculateBMIDistribution() {
    setState(() => _isUpdating = true);

    // Calculate BMI distribution from real data
    int underweight = 0, normal = 0, overweight = 0, obese = 0;

    for (var record in widget.records) {
      try {
        final bmiStr = record['bmi']?.toString() ?? '';
        if (bmiStr.isNotEmpty) {
          final bmi = double.tryParse(
            bmiStr.replaceAll(RegExp(r'[^0-9.]'), ''),
          );
          if (bmi != null) {
            if (bmi < 18.5) {
              underweight++;
            } else if (bmi < 25) {
              normal++;
            } else if (bmi < 30) {
              overweight++;
            } else {
              obese++;
            }
          }
        }
      } catch (e) {
        // Skip invalid entries
      }
    }

    setState(() {
      _underweight = underweight;
      _normal = normal;
      _overweight = overweight;
      _obese = obese;
      _isUpdating = false;
    });

    // Trigger animation
    _animationController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 380;
    final bmiData = <BarData>[
      BarData('Under', _underweight),
      BarData('Normal', _normal),
      BarData('Over', _overweight),
      BarData('Obese', _obese),
    ];

    if (_underweight + _normal + _overweight + _obese == 0) {
      return Column(
        children: [
          _ChartStatusRow(
            lastUpdated: widget.lastUpdated,
            isUpdating: _isUpdating,
          ),
          const SizedBox(height: 12),
          const Expanded(child: _ChartEmptyState('No BMI data available')),
        ],
      );
    }

    return Column(
      children: [
        _ChartStatusRow(
          lastUpdated: widget.lastUpdated,
          isUpdating: _isUpdating,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.95,
              end: 1.0,
            ).animate(_animationController),
            child: Container(
              padding: EdgeInsets.fromLTRB(
                isCompact ? 4 : 8,
                10,
                isCompact ? 10 : 12,
                4,
              ),
              decoration: BoxDecoration(
                color: _lightOffWhite.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _lightOffWhite.withValues(alpha: 0.08),
                ),
              ),
              child: charts.BarChart(
                [
                  charts.Series<BarData, String>(
                    id: 'BMI',
                    colorFn: (BarData data, _) {
                      switch (data.label) {
                        case 'Under':
                          return charts.MaterialPalette.indigo.shadeDefault;
                        case 'Normal':
                          return charts.MaterialPalette.green.shadeDefault;
                        case 'Over':
                          return charts.MaterialPalette.yellow.shadeDefault;
                        case 'Obese':
                          return charts.MaterialPalette.red.shadeDefault;
                        default:
                          return charts.MaterialPalette.blue.shadeDefault;
                      }
                    },
                    domainFn: (BarData data, _) => data.label,
                    measureFn: (BarData data, _) => data.value,
                    labelAccessorFn: (BarData data, _) => '${data.value}',
                    data: bmiData,
                  ),
                ],
                animate: true,
                animationDuration: const Duration(milliseconds: 800),
                barRendererDecorator: charts.BarLabelDecorator<String>(
                  insideLabelStyleSpec: charts.TextStyleSpec(
                    fontSize: isCompact ? 9 : 10,
                    fontWeight: 'bold',
                    color: charts.Color.white,
                  ),
                ),
                defaultRenderer: charts.BarRendererConfig<String>(
                  cornerStrategy: const charts.ConstCornerStrategy(10),
                  maxBarWidthPx: isCompact ? 26 : 32,
                ),
                primaryMeasureAxis: charts.NumericAxisSpec(
                  showAxisLine: false,
                  renderSpec: charts.GridlineRendererSpec(
                    labelStyle: charts.TextStyleSpec(
                      color: charts.Color.white,
                      fontSize: isCompact ? 8 : 10,
                    ),
                    lineStyle: charts.LineStyleSpec(
                      color: charts.Color(r: 255, g: 255, b: 255, a: 64),
                    ),
                  ),
                ),
                domainAxis: charts.OrdinalAxisSpec(
                  renderSpec: charts.SmallTickRendererSpec(
                    labelStyle: charts.TextStyleSpec(
                      color: charts.Color.white,
                      fontSize: isCompact ? 8 : 10,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricPill(
                label: 'Underweight',
                value: _underweight.toString(),
                color: Colors.indigo,
              ),
              _MetricPill(
                label: 'Normal',
                value: _normal.toString(),
                color: Colors.green,
              ),
              _MetricPill(
                label: 'Overweight',
                value: _overweight.toString(),
                color: Colors.amber,
              ),
              _MetricPill(
                label: 'Obese',
                value: _obese.toString(),
                color: Colors.red,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BuildBPChart extends StatefulWidget {
  final List<Map<String, dynamic>> records;
  final DateTime? lastUpdated;

  const _BuildBPChart({required this.records}) : lastUpdated = null;

  @override
  State<_BuildBPChart> createState() => _BuildBPChartState();
}

class _BuildBPChartState extends State<_BuildBPChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late List<LineData> _systolicData;
  late List<LineData> _diastolicData;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _loadBPData();
  }

  @override
  void didUpdateWidget(_BuildBPChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload data when records change
    if (oldWidget.records != widget.records ||
        oldWidget.lastUpdated != widget.lastUpdated) {
      _loadBPData();
    }
  }

  void _loadBPData() {
    setState(() => _isUpdating = true);

    // Extract BP data from records - parse both systolic and diastolic
    List<LineData> systolicData = [];
    List<LineData> diastolicData = [];

    // Sort records by date (most recent first)
    List<Map<String, dynamic>> sortedRecords = List.from(widget.records);
    sortedRecords.sort((a, b) {
      try {
        DateTime dateA = DateTime.parse(a['date'] ?? '');
        DateTime dateB = DateTime.parse(b['date'] ?? '');
        return dateB.compareTo(dateA);
      } catch (e) {
        return 0;
      }
    });

    // Take last 14 days of data (up to 14 readings)
    int dayCounter = 0;
    for (int i = 0; i < sortedRecords.length && dayCounter < 14; i++) {
      try {
        // Try different BP field formats
        String? bpStr =
            sortedRecords[i]['bp']?.toString() ??
            sortedRecords[i]['bloodPressure']?.toString() ??
            sortedRecords[i]['bpReading']?.toString() ??
            '';

        if (bpStr.contains('/')) {
          final parts = bpStr.split('/');
          final systolic = int.tryParse(parts[0].trim());
          final diastolic = int.tryParse(parts[1].trim());

          if (systolic != null && diastolic != null) {
            // Add data point (days from present, so older is to the left)
            systolicData.insert(0, LineData(dayCounter, systolic));
            diastolicData.insert(0, LineData(dayCounter, diastolic));
            dayCounter++;
          }
        }
      } catch (e) {
        // Skip invalid entries
      }
    }

    _systolicData = systolicData.isEmpty
        ? [LineData(0, 120), LineData(1, 118), LineData(2, 122)]
        : systolicData;

    _diastolicData = diastolicData.isEmpty
        ? [LineData(0, 80), LineData(1, 78), LineData(2, 82)]
        : diastolicData;

    // Trigger animation
    _animationController.forward(from: 0.0);

    setState(() => _isUpdating = false);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 380;
    final latestSystolic = _systolicData.isNotEmpty
        ? _systolicData.last.value.toString()
        : '--';
    final latestDiastolic = _diastolicData.isNotEmpty
        ? _diastolicData.last.value.toString()
        : '--';

    return Column(
      children: [
        _ChartStatusRow(
          lastUpdated: widget.lastUpdated,
          isUpdating: _isUpdating,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.95,
              end: 1.0,
            ).animate(_animationController),
            child: Container(
              padding: EdgeInsets.fromLTRB(
                isCompact ? 4 : 8,
                10,
                isCompact ? 10 : 12,
                4,
              ),
              decoration: BoxDecoration(
                color: _lightOffWhite.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _lightOffWhite.withValues(alpha: 0.08),
                ),
              ),
              child: charts.LineChart(
                [
                  charts.Series<LineData, int>(
                    id: 'Systolic',
                    colorFn: (_, _) => charts.MaterialPalette.red.shadeDefault,
                    domainFn: (LineData data, _) => data.day,
                    measureFn: (LineData data, _) => data.value,
                    data: _systolicData,
                  ),
                  charts.Series<LineData, int>(
                    id: 'Diastolic',
                    colorFn: (_, _) => charts.MaterialPalette.blue.shadeDefault,
                    domainFn: (LineData data, _) => data.day,
                    measureFn: (LineData data, _) => data.value,
                    data: _diastolicData,
                  ),
                ],
                animate: true,
                animationDuration: const Duration(milliseconds: 800),
                defaultRenderer: charts.LineRendererConfig(includePoints: true),
                primaryMeasureAxis: charts.NumericAxisSpec(
                  showAxisLine: false,
                  renderSpec: charts.GridlineRendererSpec(
                    labelStyle: charts.TextStyleSpec(
                      color: charts.Color.white,
                      fontSize: isCompact ? 8 : 10,
                    ),
                    lineStyle: charts.LineStyleSpec(
                      color: charts.Color(r: 255, g: 255, b: 255, a: 64),
                    ),
                  ),
                ),
                domainAxis: charts.NumericAxisSpec(
                  renderSpec: charts.SmallTickRendererSpec(
                    labelStyle: charts.TextStyleSpec(
                      color: charts.Color.white,
                      fontSize: isCompact ? 8 : 10,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _LegendPill(
                label: 'Systolic',
                value: '$latestSystolic mmHg',
                color: Colors.red,
              ),
              _LegendPill(
                label: 'Diastolic',
                value: '$latestDiastolic mmHg',
                color: Colors.blue,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BuildDemographicsChart extends StatefulWidget {
  final List<Map<String, dynamic>> records;
  final DateTime? lastUpdated;

  const _BuildDemographicsChart({required this.records}) : lastUpdated = null;

  @override
  State<_BuildDemographicsChart> createState() =>
      _BuildDemographicsChartState();
}

class _BuildDemographicsChartState extends State<_BuildDemographicsChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  int _age0to18 = 0;
  int _age18to35 = 0;
  int _age35to65 = 0;
  int _age65plus = 0;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _calculateDemographics();
  }

  @override
  void didUpdateWidget(_BuildDemographicsChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records != widget.records ||
        oldWidget.lastUpdated != widget.lastUpdated) {
      _calculateDemographics();
    }
  }

  void _calculateDemographics() {
    setState(() => _isUpdating = true);

    int age0to18 = 0, age18to35 = 0, age35to65 = 0, age65plus = 0;

    for (var record in widget.records) {
      try {
        final ageStr = record['age']?.toString() ?? '';
        final age = int.tryParse(ageStr.replaceAll(RegExp(r'[^0-9]'), ''));
        if (age != null) {
          if (age < 18) {
            age0to18++;
          } else if (age < 35) {
            age18to35++;
          } else if (age < 65) {
            age35to65++;
          } else {
            age65plus++;
          }
        }
      } catch (e) {
        // Skip invalid entries
      }
    }

    setState(() {
      _age0to18 = age0to18;
      _age18to35 = age18to35;
      _age35to65 = age35to65;
      _age65plus = age65plus;
      _isUpdating = false;
    });

    _animationController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _age0to18 + _age18to35 + _age35to65 + _age65plus;

    if (_age0to18 + _age18to35 + _age35to65 + _age65plus == 0) {
      return Column(
        children: [
          _ChartStatusRow(
            lastUpdated: widget.lastUpdated,
            isUpdating: _isUpdating,
          ),
          const SizedBox(height: 12),
          const Expanded(
            child: _ChartEmptyState('No demographic data available'),
          ),
        ],
      );
    }

    return Column(
      children: [
        _ChartStatusRow(
          lastUpdated: widget.lastUpdated,
          isUpdating: _isUpdating,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.95,
              end: 1.0,
            ).animate(_animationController),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _lightOffWhite.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _lightOffWhite.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                children: [
                  _DemographicItem(
                    label: '0-17 years',
                    value: _age0to18,
                    total: total,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 10),
                  _DemographicItem(
                    label: '18-34 years',
                    value: _age18to35,
                    total: total,
                    color: Colors.green,
                  ),
                  const SizedBox(height: 10),
                  _DemographicItem(
                    label: '35-64 years',
                    value: _age35to65,
                    total: total,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 10),
                  _DemographicItem(
                    label: '65+ years',
                    value: _age65plus,
                    total: total,
                    color: Colors.red,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DemographicItem extends StatelessWidget {
  final String label;
  final int value;
  final int total;
  final Color color;

  const _DemographicItem({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? value / total : 0.0;
    final percentage = total > 0 ? (ratio * 100).toStringAsFixed(1) : '0.0';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _lightOffWhite,
                  ),
                ),
              ),
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _lightOffWhite,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$percentage%',
                style: TextStyle(
                  fontSize: 10,
                  color: _lightOffWhite.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 9,
              backgroundColor: color.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

// Immunization Chart
class _BuildImmunizationChart extends StatefulWidget {
  final List<Map<String, dynamic>> records;
  final DateTime? lastUpdated;

  const _BuildImmunizationChart({required this.records}) : lastUpdated = null;

  @override
  State<_BuildImmunizationChart> createState() =>
      _BuildImmunizationChartState();
}

class _BuildImmunizationChartState extends State<_BuildImmunizationChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Map<String, int> _vaccineCounts;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _calculateVaccineCounts();
  }

  @override
  void didUpdateWidget(_BuildImmunizationChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records != widget.records ||
        oldWidget.lastUpdated != widget.lastUpdated) {
      _calculateVaccineCounts();
    }
  }

  void _calculateVaccineCounts() {
    setState(() => _isUpdating = true);

    Map<String, int> vaccineCounts = {};

    for (var record in widget.records) {
      final vaccine = record['vaccine']?.toString() ?? 'Unknown';
      vaccineCounts[vaccine] = (vaccineCounts[vaccine] ?? 0) + 1;
    }

    setState(() {
      _vaccineCounts = vaccineCounts;
      _isUpdating = false;
    });

    _animationController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_vaccineCounts.isEmpty) {
      return Column(
        children: [
          _ChartStatusRow(
            lastUpdated: widget.lastUpdated,
            isUpdating: _isUpdating,
          ),
          const SizedBox(height: 12),
          const Expanded(
            child: _ChartEmptyState('No immunization data available'),
          ),
        ],
      );
    }

    final sortedVaccines = _vaccineCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final chartEntries = sortedVaccines.length > 6
        ? <MapEntry<String, int>>[
            ...sortedVaccines.take(5),
            MapEntry(
              'Others',
              sortedVaccines
                  .skip(5)
                  .fold<int>(0, (sum, entry) => sum + entry.value),
            ),
          ]
        : sortedVaccines;

    final chartData = chartEntries
        .map((e) => BarData(_compactChartLabelAscii(e.key), e.value))
        .toList(growable: false);

    final palette = <Color>[
      _primaryAqua,
      Colors.greenAccent,
      Colors.orangeAccent,
      Colors.pinkAccent,
      Colors.blueAccent,
      Colors.amberAccent,
    ];

    return Column(
      children: [
        _ChartStatusRow(
          lastUpdated: widget.lastUpdated,
          isUpdating: _isUpdating,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: sortedVaccines
              .take(3)
              .toList()
              .asMap()
              .entries
              .map((entry) {
                return _MetricPill(
                  label: _compactChartLabelAscii(
                    entry.value.key,
                    maxLength: 16,
                  ),
                  value: entry.value.value.toString(),
                  color: palette[entry.key % palette.length],
                );
              })
              .toList(growable: false),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.95,
              end: 1.0,
            ).animate(_animationController),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 10, 12, 4),
              decoration: BoxDecoration(
                color: _lightOffWhite.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _lightOffWhite.withValues(alpha: 0.08),
                ),
              ),
              child: charts.BarChart(
                [
                  charts.Series<BarData, String>(
                    id: 'Vaccines',
                    colorFn: (BarData data, int? index) =>
                        charts.ColorUtil.fromDartColor(
                          palette[(index ?? 0) % palette.length],
                        ),
                    domainFn: (BarData data, _) => data.label,
                    measureFn: (BarData data, _) => data.value,
                    labelAccessorFn: (BarData data, _) => '${data.value}',
                    data: chartData,
                  ),
                ],
                animate: true,
                animationDuration: const Duration(milliseconds: 800),
                vertical: false,
                barRendererDecorator: charts.BarLabelDecorator<String>(
                  insideLabelStyleSpec: const charts.TextStyleSpec(
                    fontSize: 10,
                    fontWeight: 'bold',
                    color: charts.Color.white,
                  ),
                ),
                defaultRenderer: charts.BarRendererConfig<String>(
                  cornerStrategy: const charts.ConstCornerStrategy(10),
                ),
                primaryMeasureAxis: const charts.NumericAxisSpec(
                  showAxisLine: false,
                  renderSpec: charts.GridlineRendererSpec(
                    labelStyle: charts.TextStyleSpec(
                      color: charts.Color.white,
                      fontSize: 10,
                    ),
                    lineStyle: charts.LineStyleSpec(
                      color: charts.Color(r: 255, g: 255, b: 255, a: 64),
                    ),
                  ),
                ),
                domainAxis: const charts.OrdinalAxisSpec(
                  renderSpec: charts.SmallTickRendererSpec(
                    labelStyle: charts.TextStyleSpec(
                      color: charts.Color.white,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatisticsGrid extends StatefulWidget {
  final List<Map<String, dynamic>> checkupRecords;
  final List<Map<String, dynamic>> prenatalRecords;
  final DateTime? lastUpdated;

  const _StatisticsGrid({
    required this.checkupRecords,
    required this.prenatalRecords,
  }) : lastUpdated = null;

  @override
  State<_StatisticsGrid> createState() => _StatisticsGridState();
}

class _StatisticsGridState extends State<_StatisticsGrid> {
  late double _avgBPSystolic;
  late double _avgBPDiastolic;
  late double _avgHeartRate;
  late double _avgBMI;
  late double _avgTemp;

  @override
  void initState() {
    super.initState();
    _calculateStatistics();
  }

  @override
  void didUpdateWidget(_StatisticsGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checkupRecords != widget.checkupRecords ||
        oldWidget.prenatalRecords != widget.prenatalRecords ||
        oldWidget.lastUpdated != widget.lastUpdated) {
      _calculateStatistics();
    }
  }

  void _calculateStatistics() {
    // Combine all records
    final allRecords = [...widget.checkupRecords, ...widget.prenatalRecords];

    // Calculate Blood Pressure average
    double bpSystolicSum = 0;
    double bpDiastolicSum = 0;
    int bpCount = 0;

    for (var record in allRecords) {
      try {
        String? bpStr =
            record['bp']?.toString() ??
            record['bloodPressure']?.toString() ??
            record['bpReading']?.toString();
        if (bpStr != null && bpStr.contains('/')) {
          final parts = bpStr.split('/');
          final systolic = double.tryParse(parts[0].trim());
          final diastolic = double.tryParse(parts[1].trim());
          if (systolic != null && diastolic != null) {
            bpSystolicSum += systolic;
            bpDiastolicSum += diastolic;
            bpCount++;
          }
        }
      } catch (e) {}
    }

    // Calculate Heart Rate average
    double hrSum = 0;
    int hrCount = 0;
    for (var record in allRecords) {
      try {
        final hr = double.tryParse(
          (record['heartRate'] ?? record['pulse'] ?? '').toString(),
        );
        if (hr != null && hr > 0) {
          hrSum += hr;
          hrCount++;
        }
      } catch (e) {}
    }

    // Calculate BMI average
    double bmiSum = 0;
    int bmiCount = 0;
    for (var record in allRecords) {
      try {
        String? bmiStr = record['bmi']?.toString();
        if (bmiStr != null) {
          final bmi = double.tryParse(
            bmiStr.replaceAll(RegExp(r'[^0-9.]'), ''),
          );
          if (bmi != null && bmi > 0) {
            bmiSum += bmi;
            bmiCount++;
          }
        }
      } catch (e) {}
    }

    // Calculate Temperature average
    double tempSum = 0;
    int tempCount = 0;
    for (var record in allRecords) {
      try {
        final temp = double.tryParse(record['temperature']?.toString() ?? '');
        if (temp != null && temp > 0) {
          tempSum += temp;
          tempCount++;
        }
      } catch (e) {}
    }

    setState(() {
      _avgBPSystolic = bpCount > 0 ? bpSystolicSum / bpCount : 120;
      _avgBPDiastolic = bpCount > 0 ? bpDiastolicSum / bpCount : 80;
      _avgHeartRate = hrCount > 0 ? hrSum / hrCount : 72;
      _avgBMI = bmiCount > 0 ? bmiSum / bmiCount : 23.4;
      _avgTemp = tempCount > 0 ? tempSum / tempCount : 37.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _StatisticCard(
        title: 'Avg. Blood Pressure',
        value:
            '${_avgBPSystolic.toStringAsFixed(0)}/${_avgBPDiastolic.toStringAsFixed(0)}',
        unit: 'mmHg',
        trend: '+2.5%',
        icon: Icons.favorite_border,
        color: Colors.red,
      ),
      _StatisticCard(
        title: 'Avg. Heart Rate',
        value: _avgHeartRate.toStringAsFixed(0),
        unit: 'bpm',
        trend: '-1.2%',
        icon: Icons.favorite,
        color: Colors.pink,
      ),
      _StatisticCard(
        title: 'Avg. BMI',
        value: _avgBMI.toStringAsFixed(1),
        unit: 'kg/m²',
        trend: '+0.8%',
        icon: Icons.scale,
        color: Colors.orange,
      ),
      _StatisticCard(
        title: 'Avg. Temperature',
        value: _avgTemp.toStringAsFixed(1),
        unit: '°C',
        trend: '-0.5%',
        icon: Icons.thermostat,
        color: Colors.blue,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 360;

        return GridView.builder(
          itemCount: cards.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isCompact ? 1 : 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: isCompact ? 2.45 : 1.1,
          ),
          itemBuilder: (context, index) => cards[index],
        );
      },
    );
  }
}

class _StatisticCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final String trend;
  final IconData icon;
  final Color color;

  const _StatisticCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.trend,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isTrendPositive = !trend.contains('-');
    final displayUnit = unit.contains('kg/m')
        ? 'kg/m2'
        : unit.contains('C')
        ? 'C'
        : unit;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _lightOffWhite.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isTrendPositive
                      ? Colors.red.withValues(alpha: 0.15)
                      : Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isTrendPositive ? Icons.trending_up : Icons.trending_down,
                      size: 12,
                      color: isTrendPositive ? Colors.red : Colors.green,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      trend,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isTrendPositive ? Colors.red : Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _lightOffWhite,
                  ),
                ),
                TextSpan(
                  text: ' $displayUnit',
                  style: const TextStyle(fontSize: 11, color: _lightOffWhite),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: _lightOffWhite,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String title;
  final String description;
  final String value;
  final Color color;
  final IconData icon;

  const _InsightCard({
    required this.title,
    required this.description,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.08), Colors.transparent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _lightOffWhite.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _lightOffWhite,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(fontSize: 11, color: _lightOffWhite),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// Data classes for charts
class BarData {
  final String label;
  final int value;

  BarData(this.label, this.value);
}

class LineData {
  final int day;
  final int value;

  LineData(this.day, this.value);
}

class PieData {
  final String label;
  final int value;

  PieData(this.label, this.value);
}
