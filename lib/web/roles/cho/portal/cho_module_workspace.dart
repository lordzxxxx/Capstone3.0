import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_navigation.dart';
import 'package:mycapstone_project/web/shared/components/web_responsive_body.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_components.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_config.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/shared/components/app_buttons.dart';
import 'package:mycapstone_project/web/shared/components/web_data_components.dart';
import 'package:mycapstone_project/web/shared/utils/csv_download.dart';

class ChoModuleWorkspace extends StatefulWidget {
  const ChoModuleWorkspace({super.key, required this.config});

  final ChoModuleConfig config;

  @override
  State<ChoModuleWorkspace> createState() => _ChoModuleWorkspaceState();
}

class _ChoModuleWorkspaceState extends State<ChoModuleWorkspace> {
  final FirebaseFirestore _firestore = getFirestoreInstance();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream;
  int _tab = 0;
  int _page = 1;
  int _rowsPerPage = 10;
  String _search = '';
  String _barangay = 'All';
  String _status = 'All';
  bool _descending = true;
  String? _accessError;

  @override
  void initState() {
    super.initState();
    _loadScope();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadScope() async {
    try {
      final scope = await UserAccessScopeService.instance
          .loadCurrentScope(forceRefresh: true)
          .timeout(const Duration(seconds: 12));
      final allowed = const {
        'cho',
        'cho_admin',
        'cho_super_admin',
        'super_admin',
        'admin',
      }.contains(scope.role);
      if (!scope.isAuthenticated || !allowed) {
        if (mounted) {
          setState(() => _accessError = 'A verified CHO account is required.');
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _stream = buildScopedRecordQuery(
          _firestore,
          widget.config.collection,
          scope,
        ).limit(250).snapshots();
      });
    } catch (error) {
      if (mounted) setState(() => _accessError = error.toString());
    }
  }

  String _text(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) continue;
      if (value is Timestamp) return _dateLabel(value.toDate());
      if (value is DateTime) return _dateLabel(value);
      if (value is Iterable) {
        final output = value.map((item) => item.toString()).join(', ').trim();
        if (output.isNotEmpty) return output;
      }
      final output = value.toString().trim();
      if (output.isNotEmpty && output.toLowerCase() != 'null') return output;
    }
    return '—';
  }

  DateTime? _date(Map<String, dynamic> row, [List<String>? keys]) {
    for (final key in keys ?? widget.config.dateKeys) {
      final value = row[key];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value != null) {
        final parsed = DateTime.tryParse(value.toString());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  String _dateLabel(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${two(value.month)}/${two(value.day)}/${value.year}';
  }

  String _validation(Map<String, dynamic> row) =>
      _text(row, const ['validationStatus', 'reviewStatus', 'status']);

  String _risk(Map<String, dynamic> row) =>
      _text(row, const ['riskLevel', 'pregnancyRiskLevel', 'healthStatus']);

  String _barangayOf(Map<String, dynamic> row) =>
      _text(row, const ['barangay', 'barangayName']);

  bool _isPending(Map<String, dynamic> row) {
    final value = _validation(row).toLowerCase();
    return value.contains('pending') ||
        value.contains('submitted') ||
        value.contains('resubmitted');
  }

  bool _matchesTab(Map<String, dynamic> row) {
    final tab = widget.config.tabs[_tab].toLowerCase();
    if (tab.contains('pending validation')) return _isPending(row);
    if (tab.contains('high-risk')) {
      final risk = _risk(row).toLowerCase();
      return risk.contains('high') || risk.contains('critical');
    }
    if (tab.contains('communicable') && !tab.contains('non-')) {
      final category = _text(row, const [
        'diseaseType',
        'classification',
        'category',
      ]).toLowerCase();
      return category.contains('communicable') &&
          !category.contains('non-communicable') &&
          !category.contains('non communicable');
    }
    if (tab.contains('non-communicable')) {
      final category = _text(row, const [
        'diseaseType',
        'classification',
        'category',
      ]).toLowerCase();
      return category.contains('non-communicable') ||
          category.contains('non communicable');
    }
    if (tab.contains('due and missed')) {
      final status = _validation(row).toLowerCase();
      final due = _date(row, const [
        'nextDoseDueDate',
        'nextSchedule',
        'dueDate',
      ]);
      return status.contains('missed') ||
          status.contains('overdue') ||
          status.contains('incomplete') ||
          (due != null &&
              due.isBefore(DateTime.now().add(const Duration(days: 7))));
    }
    return true;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filtered(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final query = _search.toLowerCase();
    final rows = docs
        .where((doc) {
          final row = <String, dynamic>{'id': doc.id, ...doc.data()};
          if (!_matchesTab(row)) return false;
          if (_barangay != 'All' && _barangayOf(row) != _barangay) return false;
          if (_status != 'All' && _validation(row) != _status) return false;
          if (query.isNotEmpty) {
            final searchable = row.values
                .where((value) => value != null)
                .map((value) => value.toString().toLowerCase())
                .join(' ');
            if (!searchable.contains(query) &&
                !doc.id.toLowerCase().contains(query)) {
              return false;
            }
          }
          return true;
        })
        .toList(growable: false);
    rows.sort((left, right) {
      final leftDate = _date(left.data()) ?? DateTime(1900);
      final rightDate = _date(right.data()) ?? DateTime(1900);
      return _descending
          ? rightDate.compareTo(leftDate)
          : leftDate.compareTo(rightDate);
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChoColors.background,
      body: WebResponsiveBody(
        sidebar: ChoNavigationDrawer(current: widget.config.destination),
        title: '${widget.config.title} • CHO',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.config.title} • CHO',
                          style: const TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: ChoColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.config.description,
                          style: const TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 12,
                            color: ChoColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const ChoStatusBadge('City Health Office'),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'Refresh data',
                    onPressed: _loadScope,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: ChoColors.text,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: ChoColors.border),
            Expanded(
              child: _accessError != null
                  ? ChoErrorState(message: _accessError!, onRetry: _loadScope)
                  : _stream == null
                  ? const ChoLoadingSkeleton()
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _stream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return ChoErrorState(
                            message: snapshot.error.toString(),
                            onRetry: _loadScope,
                          );
                        }
                        if (!snapshot.hasData) {
                          return const ChoLoadingSkeleton();
                        }
                        return _content(snapshot.data!.docs);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final rows = _filtered(docs);
    final barangays =
        docs
            .map((doc) => _barangayOf(doc.data()))
            .where((value) => value != '—')
            .toSet()
            .toList()
          ..sort();
    final statuses =
        docs
            .map((doc) => _validation(doc.data()))
            .where((value) => value != '—')
            .toSet()
            .toList()
          ..sort();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        ChoPageHeader(
          title: widget.config.title,
          description: widget.config.description,
          icon: widget.config.icon,
          actions: [
            OutlinedButton.icon(
              onPressed: () => _export(rows),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export CSV'),
              style: AppButtonStyles.outline(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ChoViewTabs(
          tabs: widget.config.tabs,
          selectedIndex: _tab,
          onChanged: (value) => setState(() {
            _tab = value;
            _page = 1;
          }),
        ),
        const SizedBox(height: 12),
        if (_tab == 0) _summary(docs) else _records(rows, barangays, statuses),
      ],
    );
  }

  Widget _summary(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (docs.isEmpty) {
      return ChoEmptyState(
        title: 'No ${widget.config.title.toLowerCase()} data yet',
        message:
            'This summary will populate from authorized Firestore records. No placeholder values are displayed.',
        icon: widget.config.icon,
      );
    }
    final now = DateTime.now();
    final thisMonth = docs.where((doc) {
      final date = _date(doc.data());
      return date?.year == now.year && date?.month == now.month;
    }).length;
    final pending = docs.where((doc) => _isPending(doc.data())).length;
    final highRisk = docs.where((doc) {
      final risk = _risk(doc.data()).toLowerCase();
      return risk.contains('high') || risk.contains('critical');
    }).length;
    final barangayCounts = <String, int>{};
    for (final doc in docs) {
      final name = _barangayOf(doc.data());
      if (name != '—') barangayCounts[name] = (barangayCounts[name] ?? 0) + 1;
    }
    final ranked = barangayCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxCount = ranked.isEmpty ? 1 : ranked.first.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChoKpiGrid(
          children: [
            ChoKpiCard(
              label: 'Total Records',
              value: '${docs.length}',
              icon: widget.config.icon,
              supportingText: 'Authorized CHO scope',
            ),
            ChoKpiCard(
              label: 'Recorded This Month',
              value: '$thisMonth',
              icon: Icons.calendar_month_outlined,
              supportingText: 'Based on saved record dates',
              color: ChoColors.aqua,
            ),
            ChoKpiCard(
              label: 'Pending Validation',
              value: '$pending',
              icon: Icons.fact_check_outlined,
              supportingText: 'Submitted records awaiting review',
              color: ChoColors.aqua,
            ),
            ChoKpiCard(
              label: 'High-Risk Records',
              value: '$highRisk',
              icon: Icons.warning_amber_rounded,
              supportingText: 'Saved high or critical risk labels',
              color: ChoColors.aqua,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ChoColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ChoColors.aqua.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Records by Barangay',
                style: TextStyle(
                  color: ChoColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Current authorized-area distribution • live saved records',
                style: TextStyle(color: ChoColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (ranked.isEmpty)
                const ChoEmptyState(
                  title: 'No barangay information',
                  message:
                      'Barangay values have not been saved in these records.',
                )
              else
                ...ranked
                    .take(10)
                    .map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 145,
                              child: Text(
                                entry.key,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: ChoColors.text),
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  minHeight: 12,
                                  value: entry.value / maxCount,
                                  color: ChoColors.aqua,
                                  backgroundColor: ChoColors.border,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 36,
                              child: Text(
                                '${entry.value}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  color: ChoColors.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _records(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> rows,
    List<String> barangays,
    List<String> statuses,
  ) {
    final totalPages = rows.isEmpty
        ? 1
        : ((rows.length - 1) ~/ _rowsPerPage) + 1;
    final currentPage = _page.clamp(1, totalPages);
    final start = rows.isEmpty ? 0 : (currentPage - 1) * _rowsPerPage;
    final end = (start + _rowsPerPage).clamp(0, rows.length);
    final pageRows = rows.sublist(start, end);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ChoColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ChoColors.aqua.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _filters(barangays, statuses),
          const SizedBox(height: 12),
          if (pageRows.isEmpty)
            ChoEmptyState(
              title: 'No matching records',
              message:
                  'Adjust the search or filters. This screen does not generate placeholder records.',
              icon: Icons.search_off_rounded,
            )
          else
            WebTableSurface(
              minWidth: 1380,
              child: Column(
                children: [_tableHeader(), ...pageRows.map(_tableRow)],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  rows.isEmpty
                      ? '0 records'
                      : 'Showing ${start + 1}–$end of ${rows.length}',
                  style: const TextStyle(color: ChoColors.muted),
                ),
              ),
              DropdownButton<int>(
                value: _rowsPerPage,
                dropdownColor: ChoColors.surfaceAlt,
                items: const [10, 20, 50]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text('$value / page'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  _rowsPerPage = value ?? 10;
                  _page = 1;
                }),
              ),
              IconButton(
                tooltip: 'Previous page',
                onPressed: currentPage > 1
                    ? () => setState(() => _page = currentPage - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                '$currentPage / $totalPages',
                style: const TextStyle(color: ChoColors.text),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: currentPage < totalPages
                    ? () => setState(() => _page = currentPage + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filters(List<String> barangays, List<String> statuses) {
    return WebFilterSurface(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 700;
            final fullWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 330.0;
            final searchWidth = compact ? fullWidth : 330.0;
            final dropdownWidth = compact ? fullWidth : 190.0;

            return Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: searchWidth,
                  child: WebSearchField(
                    controller: _searchController,
                    hintText: 'Name, ID, contact, or household',
                    onChanged: (value) {
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 300),
                        () {
                          if (mounted) {
                            setState(() {
                              _search = value.trim();
                              _page = 1;
                            });
                          }
                        },
                      );
                    },
                    onClear: () {
                      _searchController.clear();
                      _searchDebounce?.cancel();
                      setState(() {
                        _search = '';
                        _page = 1;
                      });
                    },
                  ),
                ),
                _dropdown(
                  width: dropdownWidth,
                  value: _barangay,
                  label: 'Barangay',
                  values: ['All', ...barangays],
                  onChanged: (value) => setState(() {
                    _barangay = value;
                    _page = 1;
                  }),
                ),
                _dropdown(
                  width: dropdownWidth,
                  value: _status,
                  label: 'Status',
                  values: ['All', ...statuses],
                  onChanged: (value) => setState(() {
                    _status = value;
                    _page = 1;
                  }),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _descending = !_descending),
                  icon: Icon(_descending ? Icons.south : Icons.north),
                  label: Text(_descending ? 'Newest first' : 'Oldest first'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _dropdown({
    required double width,
    required String value,
    required String label,
    required List<String> values,
    required ValueChanged<String> onChanged,
  }) {
    return WebFilterDropdown<String>(
      label: label,
      value: values.contains(value) ? value : 'All',
      width: width,
      items: values
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Tooltip(
                message: item,
                child: Text(item, overflow: TextOverflow.ellipsis),
              ),
            ),
          )
          .toList(),
      onChanged: (item) {
        if (item != null) onChanged(item);
      },
    );
  }

  Widget _tableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      color: ChoColors.surfaceAlt,
      child: Row(
        children: [
          ...widget.config.columns.map(
            (column) => Expanded(
              flex: column.flex,
              child: Text(
                column.label,
                style: const TextStyle(
                  color: ChoColors.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(
            width: 160,
            child: Text(
              'Actions',
              style: TextStyle(
                color: ChoColors.text,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final row = <String, dynamic>{'id': doc.id, ...doc.data()};
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ChoColors.border)),
      ),
      child: Row(
        children: [
          ...widget.config.columns.map((column) {
            final value = _text(row, column.keys);
            final isStatus =
                column.label.toLowerCase().contains('status') ||
                column.label == 'Validation' ||
                column.label == 'Risk';
            return Expanded(
              flex: column.flex,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: isStatus
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: ChoStatusBadge(value),
                      )
                    : Tooltip(
                        message: value,
                        child: Text(
                          value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ChoColors.text,
                            fontSize: 12,
                          ),
                        ),
                      ),
              ),
            );
          }),
          SizedBox(
            width: 160,
            child: Wrap(
              spacing: 2,
              children: [
                IconButton(
                  tooltip: 'View full record',
                  onPressed: () => _showDetails(row),
                  icon: const Icon(
                    Icons.visibility_outlined,
                    color: ChoColors.aqua,
                  ),
                ),
                if (_isPending(row))
                  IconButton(
                    tooltip: 'Approve',
                    onPressed: () => _review(doc, 'Approved'),
                    icon: const Icon(
                      Icons.check_circle_outline,
                      color: ChoColors.aqua,
                    ),
                  ),
                if (_isPending(row))
                  IconButton(
                    tooltip: 'Return for correction',
                    onPressed: () => _review(
                      doc,
                      'Returned for Correction',
                      requireReason: true,
                    ),
                    icon: const Icon(
                      Icons.reply_outlined,
                      color: ChoColors.aqua,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _review(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String nextStatus, {
    bool requireReason = false,
  }) async {
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ChoColors.surface,
        title: Text(nextStatus),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Record ${doc.id}',
              style: const TextStyle(color: ChoColors.muted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: notes,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: requireReason
                    ? 'Reason (required)'
                    : 'Review note (optional)',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (requireReason && notes.text.trim().isEmpty) return;
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      notes.dispose();
      return;
    }
    final previous = _validation(doc.data());
    try {
      await doc.reference.update({
        'validationStatus': nextStatus,
        'reviewedBy': FirebaseAuth.instance.currentUser?.uid,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewNotes': notes.text.trim(),
        'previousValidationStatus': previous,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Record marked $nextStatus.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Review could not be saved: $error'),
            backgroundColor: ChoColors.aqua,
          ),
        );
      }
    } finally {
      notes.dispose();
    }
  }

  void _showDetails(Map<String, dynamic> row) {
    final hidden = {'password', 'token', 'accessToken', 'refreshToken'};
    final entries =
        row.entries.where((entry) => !hidden.contains(entry.key)).toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: ChoColors.background,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
          child: Column(
            children: [
              ListTile(
                title: Text(
                  '${widget.config.title} Record',
                  style: const TextStyle(
                    color: ChoColors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  _text(row, const ['recordId', 'patientId', 'caseId', 'id']),
                  style: const TextStyle(color: ChoColors.muted),
                ),
                trailing: IconButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ),
              if (widget.config.aiEnabled)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ChoColors.aqua.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.psychology_outlined, color: ChoColors.aqua),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This AI result is a decision-support output and is not a confirmed medical diagnosis.',
                          style: TextStyle(color: ChoColors.text),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(18),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) =>
                      const Divider(color: ChoColors.border),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 210,
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              color: ChoColors.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            _text(row, [entry.key]),
                            style: const TextStyle(color: ChoColors.text),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _export(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final headers = widget.config.columns
        .map((column) => column.label)
        .toList();
    String escape(String value) => '"${value.replaceAll('"', '""')}"';
    final lines = <String>[
      headers.map(escape).join(','),
      ...docs.map((doc) {
        final row = <String, dynamic>{'id': doc.id, ...doc.data()};
        return widget.config.columns
            .map((column) => escape(_text(row, column.keys)))
            .join(',');
      }),
    ];
    final success = downloadCsvFile(
      bytes: utf8.encode(lines.join('\r\n')),
      filename:
          'cho_${widget.config.collection}_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CSV download is unavailable on this platform.'),
        ),
      );
    }
  }
}
