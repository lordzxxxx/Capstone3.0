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
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _darkDeepTeal = AppDesign.page;
const Color _lightOffWhite = AppDesign.ink;

class HealthMetricsPage extends StatefulWidget {
  const HealthMetricsPage({super.key});

  @override
  State<HealthMetricsPage> createState() => _HealthMetricsPageState();
}

class _HealthMetricsPageState extends State<HealthMetricsPage> {
  late final Future<UserAccessScope> _accessScopeFuture;
  bool _loading = false;
  String _summary = '';
  String _summaryTitle = '';
  DateTime _selectedDate = DateTime.now();
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  String _mode = 'Daily'; // Daily, Monthly, Yearly

  @override
  void initState() {
    super.initState();
    _accessScopeFuture = UserAccessScopeService.instance.loadCurrentScope();
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    try {
      String result;
      String period;
      String type;
      if (_mode == 'Daily') {
        result = await ai.generateDailySummaryForCurrentUser(_selectedDate);
        _summaryTitle =
            'Daily Summary - ${DateFormat.yMMMd().format(_selectedDate)}';
        period = DateFormat('yyyy-MM-dd').format(_selectedDate);
        type = 'daily';
      } else if (_mode == 'Monthly') {
        result = await ai.generateMonthlySummaryForCurrentUser(
          _selectedYear,
          _selectedMonth,
        );
        _summaryTitle =
            'Monthly Summary - $_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';
        period = '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';
        type = 'monthly';
      } else {
        result = await ai.generateYearlySummaryForCurrentUser(_selectedYear);
        _summaryTitle = 'Yearly Summary - $_selectedYear';
        period = '$_selectedYear';
        type = 'yearly';
      }

      setState(() => _summary = result);
      await _saveSummaryToFirestore(
        type: type,
        period: period,
        title: _summaryTitle,
        text: result,
      );
    } catch (e) {
      setState(() => _summary = 'Error generating summary: $e');
    } finally {
      setState(() => _loading = false);
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
    } catch (_) {}
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _savedSummaryStream(
    UserAccessScope accessScope,
  ) {
    final firestore = getFirestoreInstance();
    return buildScopedRecordQuery(
      firestore,
      'summary_records',
      accessScope,
    ).orderBy('generatedAt', descending: true).limit(12).snapshots();
  }

  void _copySummaryToClipboard() {
    if (_summary.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _summary));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Summary copied to clipboard')),
    );
  }

  void _clearSummary() {
    setState(() {
      _summary = '';
      _summaryTitle = '';
    });
  }

  Widget _buildSummaryControls() {
    return Card(
      color: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _primaryAqua.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DropdownButton<String>(
                  value: _mode,
                  dropdownColor: _darkDeepTeal,
                  style: const TextStyle(color: _lightOffWhite),
                  items: const [
                    DropdownMenuItem(
                      value: 'Daily',
                      child: Text(
                        'Daily',
                        style: TextStyle(color: _lightOffWhite),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Monthly',
                      child: Text(
                        'Monthly',
                        style: TextStyle(color: _lightOffWhite),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Yearly',
                      child: Text(
                        'Yearly',
                        style: TextStyle(color: _lightOffWhite),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _mode = value);
                  },
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _generate,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_loading ? 'Generating...' : 'Generate'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_mode == 'Daily')
              Row(
                children: [
                  const Text(
                    'Date: ',
                    style: TextStyle(
                      color: _lightOffWhite,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                      }
                    },
                    child: Text(DateFormat.yMMMd().format(_selectedDate)),
                  ),
                ],
              )
            else if (_mode == 'Monthly')
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Month: ',
                    style: TextStyle(
                      color: _lightOffWhite,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  DropdownButton<int>(
                    value: _selectedMonth,
                    dropdownColor: _darkDeepTeal,
                    style: const TextStyle(color: _lightOffWhite),
                    items: List.generate(12, (index) => index + 1)
                        .map(
                          (month) => DropdownMenuItem(
                            value: month,
                            child: Text(
                              DateFormat.MMMM().format(DateTime(0, month)),
                              style: const TextStyle(color: _lightOffWhite),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedMonth = value);
                      }
                    },
                  ),
                  DropdownButton<int>(
                    value: _selectedYear,
                    dropdownColor: _darkDeepTeal,
                    style: const TextStyle(color: _lightOffWhite),
                    items:
                        List.generate(6, (index) => DateTime.now().year - index)
                            .map(
                              (year) => DropdownMenuItem(
                                value: year,
                                child: Text(
                                  '$year',
                                  style: const TextStyle(color: _lightOffWhite),
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedYear = value);
                      }
                    },
                  ),
                ],
              )
            else
              Row(
                children: [
                  const Text(
                    'Year: ',
                    style: TextStyle(
                      color: _lightOffWhite,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  DropdownButton<int>(
                    value: _selectedYear,
                    dropdownColor: _darkDeepTeal,
                    style: const TextStyle(color: _lightOffWhite),
                    items:
                        List.generate(6, (index) => DateTime.now().year - index)
                            .map(
                              (year) => DropdownMenuItem(
                                value: year,
                                child: Text(
                                  '$year',
                                  style: const TextStyle(color: _lightOffWhite),
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedYear = value);
                      }
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkDeepTeal,
      appBar: AppBar(
        backgroundColor: AppDesign.navy,
        title: Text(
          'Summary Generation',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _primaryAqua.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Text(
                'Generate concise operational summaries from encoded health records. '
                'Use this for reporting, trend awareness, and faster case monitoring.',
                style: TextStyle(
                  color: _lightOffWhite.withValues(alpha: 0.85),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _SectionTitle('Summary Generation Controls'),
            const SizedBox(height: 8),
            _buildSummaryControls(),
            const SizedBox(height: 12),
            Card(
              color: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: _primaryAqua.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _summaryTitle.isEmpty
                                ? 'No summary report generated'
                                : _summaryTitle,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: _lightOffWhite,
                                ),
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: _summary.isEmpty
                                  ? null
                                  : _copySummaryToClipboard,
                              icon: const Icon(
                                Icons.copy,
                                color: _lightOffWhite,
                              ),
                              tooltip: 'Copy',
                            ),
                            IconButton(
                              onPressed: _summary.isEmpty
                                  ? null
                                  : _clearSummary,
                              icon: const Icon(
                                Icons.clear,
                                color: _lightOffWhite,
                              ),
                              tooltip: 'Clear',
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _primaryAqua.withValues(alpha: 0.3),
                        ),
                      ),
                      child: _summary.isNotEmpty
                          ? SelectableText(
                              _summary,
                              style: const TextStyle(
                                height: 1.4,
                                color: _lightOffWhite,
                              ),
                            )
                          : Text(
                              'Run Summary Generation to view system-aligned insights, '
                              'key trends, and potential risk signals.',
                              style: TextStyle(
                                color: _lightOffWhite.withValues(alpha: 0.7),
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<UserAccessScope>(
                      future: _accessScopeFuture,
                      builder: (context, accessScopeSnapshot) {
                        if (!accessScopeSnapshot.hasData) {
                          return const SizedBox();
                        }

                        final currentUserId =
                            FirebaseAuth.instance.currentUser?.uid ??
                            'anonymous';
                        final activeType = _mode.toLowerCase();
                        final activePeriod = _mode == 'Daily'
                            ? DateFormat('yyyy-MM-dd').format(_selectedDate)
                            : _mode == 'Monthly'
                            ? '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}'
                            : '$_selectedYear';

                        return StreamBuilder<
                          QuerySnapshot<Map<String, dynamic>>
                        >(
                          stream: _savedSummaryStream(
                            accessScopeSnapshot.data!,
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const SizedBox();
                            }
                            if (!snapshot.hasData) {
                              return const SizedBox();
                            }

                            final docs = snapshot.data!.docs.where((doc) {
                              final data = doc.data();
                              return data['patientId'] == currentUserId &&
                                  data['type'] == activeType &&
                                  data['period'] == activePeriod;
                            }).toList();

                            if (docs.isEmpty) {
                              return const SizedBox();
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Divider(),
                                const Text(
                                  'Recent saved summary',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _lightOffWhite,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...docs.take(3).map((doc) {
                                  final data = doc.data();
                                  final text = (data['text'] as String?) ?? '';
                                  final ts = data['generatedAt'] as Timestamp?;
                                  final when = ts != null
                                      ? DateFormat.yMMMd().add_jm().format(
                                          ts.toDate(),
                                        )
                                      : 'recent';

                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      when,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _lightOffWhite,
                                      ),
                                    ),
                                    subtitle: Text(
                                      text,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _lightOffWhite.withValues(
                                          alpha: 0.8,
                                        ),
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.open_in_new,
                                        color: _lightOffWhite,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _summary = text;
                                          _summaryTitle =
                                              (data['title'] as String?) ??
                                              'Saved - $when';
                                        });
                                      },
                                    ),
                                  );
                                }),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
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
