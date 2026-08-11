import 'package:flutter/material.dart';
import 'package:mycapstone_project/app/features/patients/patient_database_helper.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

class PatientAnalyticsPage extends StatefulWidget {
  const PatientAnalyticsPage({super.key});

  @override
  State<PatientAnalyticsPage> createState() => _PatientAnalyticsPageState();
}

class _PatientAnalyticsPageState extends State<PatientAnalyticsPage> {
  final PatientDatabaseHelper _database = PatientDatabaseHelper.instance;
  List<Map<String, dynamic>> _records = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      try {
        await _database.syncFromFirebase();
      } catch (_) {
        // The local cache keeps analytics available while offline.
      }
      final records = await _database.getAllRecords();
      if (!mounted) return;
      setState(() {
        _records = records;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Patient analytics could not be loaded.';
        _isLoading = false;
      });
    }
  }

  int get _activePatients => _records.where((record) {
    return _value(record, 'status').toLowerCase() != 'inactive';
  }).length;

  int get _registeredThisMonth {
    final now = DateTime.now();
    return _records.where((record) {
      final date = DateTime.tryParse(_value(record, 'registrationDate'));
      return date != null && date.year == now.year && date.month == now.month;
    }).length;
  }

  String get _averageAge {
    final ages = _records
        .map((record) => double.tryParse(_value(record, 'age')))
        .whereType<double>()
        .toList(growable: false);
    if (ages.isEmpty) return '—';
    return (ages.reduce((a, b) => a + b) / ages.length).toStringAsFixed(1);
  }

  Map<String, int> _countsFor(
    String field, {
    String fallback = 'Not recorded',
  }) {
    final counts = <String, int>{};
    for (final record in _records) {
      final raw = _value(record, field).trim();
      final label = raw.isEmpty ? fallback : raw;
      counts[label] = (counts[label] ?? 0) + 1;
    }
    return Map.fromEntries(
      counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  Map<String, int> get _ageGroups {
    final counts = <String, int>{
      '0–17': 0,
      '18–35': 0,
      '36–59': 0,
      '60+': 0,
      'Not recorded': 0,
    };
    for (final record in _records) {
      final age = int.tryParse(_value(record, 'age'));
      final group = age == null
          ? 'Not recorded'
          : age < 18
          ? '0–17'
          : age < 36
          ? '18–35'
          : age < 60
          ? '36–59'
          : '60+';
      counts[group] = counts[group]! + 1;
    }
    return counts;
  }

  String _value(Map<String, dynamic> record, String key) =>
      (record[key] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Records Analytics'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadRecords,
            tooltip: 'Refresh analytics',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _AnalyticsError(message: _error!, onRetry: _loadRecords)
          : RefreshIndicator(
              onRefresh: _loadRecords,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                children: [
                  const _AnalyticsHeader(
                    icon: Icons.folder_shared_rounded,
                    title: 'Patient population overview',
                    subtitle:
                        'Registration volume and demographic distribution from patient records.',
                  ),
                  const SizedBox(height: 16),
                  _MetricGrid(
                    metrics: [
                      _Metric(
                        'Total patients',
                        '${_records.length}',
                        Icons.people_alt_outlined,
                      ),
                      _Metric(
                        'Active patients',
                        '$_activePatients',
                        Icons.verified_user_outlined,
                      ),
                      _Metric(
                        'New this month',
                        '$_registeredThisMonth',
                        Icons.person_add_alt_1_outlined,
                      ),
                      _Metric('Average age', _averageAge, Icons.cake_outlined),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _DistributionCard(
                    title: 'Age distribution',
                    icon: Icons.bar_chart_rounded,
                    values: _ageGroups,
                    total: _records.length,
                  ),
                  const SizedBox(height: 16),
                  _DistributionCard(
                    title: 'Gender distribution',
                    icon: Icons.wc_rounded,
                    values: _countsFor('gender'),
                    total: _records.length,
                  ),
                  const SizedBox(height: 16),
                  _DistributionCard(
                    title: 'Record status',
                    icon: Icons.fact_check_outlined,
                    values: _countsFor('status'),
                    total: _records.length,
                  ),
                ],
              ),
            ),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});
  final List<_Metric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: metrics
              .map((metric) {
                return SizedBox(
                  width: width,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(metric.icon, color: AppDesign.patientRecords),
                          const SizedBox(height: 12),
                          Text(
                            metric.value,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            metric.label,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppDesign.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              })
              .toList(growable: false),
        );
      },
    );
  }
}

class _AnalyticsHeader extends StatelessWidget {
  const _AnalyticsHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppDesign.informationBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppDesign.blue.withValues(alpha: .18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppDesign.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppDesign.patientRecords),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppDesign.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({
    required this.title,
    required this.icon,
    required this.values,
    required this.total,
  });
  final String title;
  final IconData icon;
  final Map<String, int> values;
  final int total;

  @override
  Widget build(BuildContext context) {
    final entries = values.entries.where((entry) => entry.value > 0).toList();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppDesign.patientRecords),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (entries.isEmpty)
              const Text(
                'No data available yet.',
                style: TextStyle(color: AppDesign.muted),
              )
            else
              ...entries.map((entry) {
                final ratio = total == 0 ? 0.0 : entry.value / total;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(entry.key)),
                          Text(
                            '${entry.value}  ${(ratio * 100).round()}%',
                            style: const TextStyle(
                              color: AppDesign.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      LinearProgressIndicator(
                        value: ratio,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(99),
                        color: AppDesign.patientRecords,
                        backgroundColor: AppDesign.blueSoft,
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsError extends StatelessWidget {
  const _AnalyticsError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppDesign.danger,
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
