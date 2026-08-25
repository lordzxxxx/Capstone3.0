import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/shared/barangay_firestore_paths.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_navigation.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_components.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_config.dart';
import 'package:mycapstone_project/web/shared/components/web_data_components.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/shared/services/firestore_rest_reader.dart';

enum ChoSupportSection {
  bhwManagement,
  announcements,
  dataQuality,
  auditLogs,
  notifications,
  profile,
}

class ChoSupportCenter extends StatefulWidget {
  const ChoSupportCenter({super.key, required this.section});

  final ChoSupportSection section;

  @override
  State<ChoSupportCenter> createState() => _ChoSupportCenterState();
}

class _ChoSupportCenterState extends State<ChoSupportCenter> {
  final FirebaseFirestore _firestore = getFirestoreInstance();
  final FirestoreRestReader _restReader = const FirestoreRestReader();
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _error;
  int _bhwTab = 0;
  bool _checkingAccess = true;
  bool _authorized = false;
  Future<List<FirestoreRestDocument>>? _bhwAccountsRequest;

  @override
  void initState() {
    super.initState();
    _verifyAccess();
  }

  Future<void> _verifyAccess() async {
    try {
      final scope = await UserAccessScopeService.instance
          .loadCurrentScope(forceRefresh: true)
          .timeout(const Duration(seconds: 12));
      final allowed = const {
        'cho',
        'cho_super_admin',
        'super_admin',
        'admin',
      }.contains(scope.role);
      if (!mounted) return;
      setState(() {
        _authorized = scope.isAuthenticated && allowed;
        _checkingAccess = false;
        if (!_authorized) {
          _error = 'A verified CHO account is required for this workspace.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checkingAccess = false;
        _error = 'CHO access could not be verified: $error';
      });
    }
  }

  ChoDestination get _destination => switch (widget.section) {
    ChoSupportSection.bhwManagement => ChoDestination.bhwManagement,
    ChoSupportSection.announcements => ChoDestination.announcements,
    ChoSupportSection.dataQuality => ChoDestination.dataQuality,
    ChoSupportSection.auditLogs => ChoDestination.auditLogs,
    ChoSupportSection.notifications => ChoDestination.notifications,
    ChoSupportSection.profile => ChoDestination.profile,
  };

  String get _title => switch (widget.section) {
    ChoSupportSection.bhwManagement => 'BHW Management',
    ChoSupportSection.announcements => 'Announcements',
    ChoSupportSection.dataQuality => 'Data Quality',
    ChoSupportSection.auditLogs => 'Audit Logs',
    ChoSupportSection.notifications => 'Notifications',
    ChoSupportSection.profile => 'Profile and Settings',
  };

  IconData get _icon => switch (widget.section) {
    ChoSupportSection.bhwManagement => Icons.groups_2_outlined,
    ChoSupportSection.announcements => Icons.campaign_outlined,
    ChoSupportSection.dataQuality => Icons.rule_folder_outlined,
    ChoSupportSection.auditLogs => Icons.history_rounded,
    ChoSupportSection.notifications => Icons.notifications_outlined,
    ChoSupportSection.profile => Icons.manage_accounts_outlined,
  };

  String get _description => switch (widget.section) {
    ChoSupportSection.bhwManagement =>
      'Review BHW accounts, registration state, assignment, and operational access.',
    ChoSupportSection.announcements =>
      'Create and manage official CHO communications for health workers and barangays.',
    ChoSupportSection.dataQuality =>
      'Inspect incomplete, unmatched, duplicate-candidate, and validation-quality issues.',
    ChoSupportSection.auditLogs =>
      'Read-only review of recorded system activity and validation history.',
    ChoSupportSection.notifications =>
      'Review operational alerts, submitted records, referrals, and account events.',
    ChoSupportSection.profile =>
      'View CHO account identity, assigned area, contact information, and access activity.',
  };

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChoColors.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChoNavigationDrawer(current: _destination),
          Expanded(
            child: _checkingAccess
                ? const ChoLoadingSkeleton()
                : !_authorized
                ? ChoErrorState(
                    message: _error ?? 'Access denied.',
                    onRetry: _verifyAccess,
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      ChoPageHeader(
                        title: _title,
                        description: _description,
                        icon: _icon,
                        actions: [
                          if (widget.section == ChoSupportSection.announcements)
                            FilledButton.icon(
                              onPressed: _createAnnouncement,
                              icon: const Icon(Icons.add),
                              label: const Text('New Announcement'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (widget.section != ChoSupportSection.profile &&
                          widget.section != ChoSupportSection.dataQuality)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: WebFilterSurface(
                            padding: const EdgeInsets.all(10),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final width = constraints.maxWidth > 420
                                    ? 420.0
                                    : constraints.maxWidth;
                                return WebSearchField(
                                  controller: _search,
                                  width: width,
                                  hintText: 'Search this workspace',
                                  onChanged: (value) {
                                    _debounce?.cancel();
                                    _debounce = Timer(
                                      const Duration(milliseconds: 300),
                                      () {
                                        if (mounted) {
                                          setState(
                                            () => _query = value.toLowerCase(),
                                          );
                                        }
                                      },
                                    );
                                  },
                                  onClear: () {
                                    _search.clear();
                                    _debounce?.cancel();
                                    setState(() => _query = '');
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      if (widget.section ==
                          ChoSupportSection.bhwManagement) ...[
                        ChoViewTabs(
                          tabs: const [
                            'Active BHWs',
                            'Pending Registrations',
                            'Assignments',
                            'Activity Summary',
                          ],
                          selectedIndex: _bhwTab,
                          onChanged: (value) => setState(() => _bhwTab = value),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_error != null)
                        ChoErrorState(message: _error!, onRetry: _verifyAccess)
                      else
                        _body(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _body() => switch (widget.section) {
    ChoSupportSection.bhwManagement => _bhwManagement(),
    ChoSupportSection.announcements => _collectionList(
      collection: 'announcements',
      titleKeys: const ['title'],
      subtitleKeys: const ['message', 'audience', 'barangay'],
      emptyTitle: 'No CHO announcements',
    ),
    ChoSupportSection.auditLogs => _collectionList(
      collection: 'audit_logs',
      titleKeys: const ['action', 'summary'],
      subtitleKeys: const ['userName', 'role', 'module', 'recordId'],
      emptyTitle: 'No accessible audit entries',
      readOnly: true,
    ),
    ChoSupportSection.notifications => _collectionList(
      collection: 'notifications',
      titleKeys: const ['title', 'type'],
      subtitleKeys: const ['message', 'module', 'recordId'],
      emptyTitle: 'No CHO notifications',
    ),
    ChoSupportSection.dataQuality => _dataQuality(),
    ChoSupportSection.profile => _profile(),
  };

  String _value(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return '—';
  }

  bool _matches(Map<String, dynamic> row) {
    if (_query.isEmpty) return true;
    return row.values
        .map((value) => value?.toString().toLowerCase() ?? '')
        .join(' ')
        .contains(_query);
  }

  Widget _collectionList({
    required String collection,
    required List<String> titleKeys,
    required List<String> subtitleKeys,
    required String emptyTitle,
    bool readOnly = false,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection(collection).limit(150).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ChoErrorState(
            message:
                'The $collection integration is unavailable or your role lacks permission: ${snapshot.error}',
            onRetry: () => setState(() {}),
          );
        }
        if (!snapshot.hasData) return const ChoLoadingSkeleton();
        final docs = snapshot.data!.docs
            .where((doc) => _matches(doc.data()))
            .toList();
        if (docs.isEmpty) {
          return ChoEmptyState(
            title: emptyTitle,
            message:
                'Only records available through the existing Firestore integration are displayed.',
            icon: _icon,
          );
        }
        return WebTableSurface(
          minWidth: 760,
          child: Column(
            children: docs.map((doc) {
              final row = doc.data();
              return ListTile(
                leading: Icon(_icon, color: ChoColors.aqua),
                title: Text(
                  _value(row, titleKeys),
                  style: const TextStyle(
                    color: ChoColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  subtitleKeys
                      .map((key) => _value(row, [key]))
                      .where((value) => value != '—')
                      .join(' • '),
                  style: const TextStyle(color: ChoColors.muted),
                ),
                trailing: readOnly
                    ? const ChoStatusBadge('Read only')
                    : ChoStatusBadge(_value(row, const ['status', 'priority'])),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _bhwManagement() {
    return FutureBuilder<List<FirestoreRestDocument>>(
      future: _bhwAccountsRequest ??= _fetchBhwAccounts(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ChoErrorState(
            message: snapshot.error.toString(),
            onRetry: _refreshBhwAccounts,
          );
        }
        if (!snapshot.hasData) return const ChoLoadingSkeleton();
        final allDocs = snapshot.data!
            .where((doc) => _matches(doc.data()))
            .toList();
        final pending = allDocs.where((doc) {
          final status = _value(doc.data(), const [
            'status',
            'accountStatus',
          ]).toLowerCase();
          return status.contains('pending') ||
              doc.data()['isApproved'] == false;
        }).length;
        final docs = allDocs
            .where((doc) {
              final row = doc.data();
              final status = _value(row, const [
                'status',
                'accountStatus',
              ]).toLowerCase();
              final isPending =
                  status.contains('pending') || row['isApproved'] == false;
              if (_bhwTab == 0) {
                return !isPending && !status.contains('reject');
              }
              if (_bhwTab == 1) return isPending;
              return true;
            })
            .toList(growable: false);
        return Column(
          children: [
            ChoKpiGrid(
              children: [
                ChoKpiCard(
                  label: 'BHW Accounts',
                  value: '${allDocs.length}',
                  icon: Icons.groups_2_outlined,
                ),
                ChoKpiCard(
                  label: 'Pending Registrations',
                  value: '$pending',
                  icon: Icons.person_search_outlined,
                  color: Colors.orangeAccent,
                ),
                ChoKpiCard(
                  label: 'Active Accounts',
                  value: '${allDocs.length - pending}',
                  icon: Icons.verified_user_outlined,
                  color: Colors.greenAccent,
                ),
                ChoKpiCard(
                  label: 'Assigned Barangays',
                  value:
                      '${docs.map((doc) => _value(doc.data(), const ['barangay'])).where((value) => value != '—').toSet().length}',
                  icon: Icons.location_city_outlined,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (docs.isEmpty)
              const ChoEmptyState(
                title: 'No BHW accounts found',
                message: 'No authorized BHW user records are available.',
              )
            else
              WebTableSurface(
                minWidth: 980,
                child: Column(
                  children: docs.map((doc) {
                    final row = doc.data();
                    final status = _value(row, const [
                      'status',
                      'accountStatus',
                    ]);
                    final pendingAccount =
                        status.toLowerCase().contains('pending') ||
                        row['isApproved'] == false;
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: ChoColors.surfaceAlt,
                        child: Icon(Icons.person, color: ChoColors.aqua),
                      ),
                      title: Text(
                        _value(row, const ['fullName', 'name', 'email']),
                        style: const TextStyle(
                          color: ChoColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        '${_value(row, const ['email'])} • ${_value(row, const ['barangay'])}',
                        style: const TextStyle(color: ChoColors.muted),
                      ),
                      trailing: Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ChoStatusBadge(status),
                          IconButton(
                            tooltip: 'Review BHW application',
                            onPressed: () => _showBhwApplication(doc),
                            icon: const Icon(
                              Icons.folder_shared_outlined,
                              color: ChoColors.aqua,
                            ),
                          ),
                          if (_bhwTab == 2)
                            OutlinedButton.icon(
                              onPressed: () => _editAssignment(doc),
                              icon: const Icon(
                                Icons.edit_location_alt_outlined,
                              ),
                              label: const Text('Edit Assignment'),
                            ),
                          if (pendingAccount && _bhwTab != 2)
                            FilledButton(
                              onPressed: () =>
                                  _setBhwStatus(doc, approved: true),
                              child: const Text('Approve'),
                            ),
                          if (pendingAccount && _bhwTab != 2)
                            OutlinedButton(
                              onPressed: () =>
                                  _setBhwStatus(doc, approved: false),
                              child: const Text('Reject'),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<List<FirestoreRestDocument>> _fetchBhwAccounts() async {
    var users = <FirestoreRestDocument>[];
    var requests = <FirestoreRestDocument>[];
    Object? requestError;
    Object? usersError;
    try {
      requests = await _restReader.listCollection(
        'bhw_registration_requests',
        pageSize: 500,
      );
    } catch (error) {
      requestError = error;
      // Older deployed rules may not expose the dedicated request queue yet.
      // The users collection remains a backwards-compatible source.
    }
    try {
      users = await _restReader.listCollection('users', pageSize: 500);
    } catch (error) {
      usersError = error;
    }
    if (requests.isEmpty && users.isEmpty) {
      if (requestError != null && usersError != null) {
        throw StateError(
          'BHW registration records are not accessible. Publish the latest '
          'firestore.rules to database $kFirestoreDatabaseId, then sign out '
          'and sign back in. Request queue: $requestError; users: $usersError',
        );
      }
    }
    final byUid = <String, FirestoreRestDocument>{
      for (final document in users) document.id: document,
      for (final document in requests) document.id: document,
    };
    return byUid.values
        .where((document) {
          final role = (document.data()['role'] ?? '').toString().toLowerCase();
          return role == 'bhw';
        })
        .toList(growable: false);
  }

  void _refreshBhwAccounts() {
    if (!mounted) return;
    final request = _fetchBhwAccounts();
    setState(() {
      _bhwAccountsRequest = request;
    });
  }

  Future<void> _showBhwApplication(FirestoreRestDocument doc) async {
    final row = doc.data();
    final address = row['address'] is Map
        ? Map<String, dynamic>.from(row['address'] as Map)
        : <String, dynamic>{};
    final bhw = row['bhw'] is Map
        ? Map<String, dynamic>.from(row['bhw'] as Map)
        : <String, dynamic>{};
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: ChoColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: ChoColors.border),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 920,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * .88,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: ChoColors.surfaceAlt,
                      child: Icon(
                        Icons.person_search_outlined,
                        color: ChoColors.aqua,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'BHW Registration Review',
                            style: TextStyle(
                              color: ChoColors.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Application UID: ${doc.id}',
                            style: const TextStyle(
                              color: ChoColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close review',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close, color: ChoColors.text),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: ChoColors.border),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _reviewSection(
                        'Personal Information',
                        Icons.badge_outlined,
                        [
                          _reviewValue(
                            'Full Name',
                            _value(row, const ['fullName']),
                          ),
                          _reviewValue('Email', _value(row, const ['email'])),
                          _reviewValue(
                            'Contact',
                            _value(row, const ['contactNumber']),
                          ),
                          _reviewValue('Sex', _value(row, const ['sex'])),
                          _reviewValue(
                            'Civil Status',
                            _value(row, const ['civilStatus']),
                          ),
                          _reviewValue(
                            'Residential Address',
                            [
                                  row['residentialAddress'],
                                  address['sitio'],
                                  address['barangay'],
                                  address['municipality'],
                                  address['province'],
                                ]
                                .where(
                                  (item) =>
                                      item?.toString().trim().isNotEmpty ==
                                      true,
                                )
                                .join(', '),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _reviewSection(
                        'BHW Assignment',
                        Icons.medical_services_outlined,
                        [
                          _reviewValue(
                            'BHW ID',
                            (bhw['bhwId'] ?? 'Not assigned').toString(),
                          ),
                          _reviewValue(
                            'Assigned Barangay',
                            (bhw['assignedBarangay'] ?? row['barangay'] ?? '—')
                                .toString(),
                          ),
                          _reviewValue(
                            'Assigned Sitio/Purok',
                            (bhw['assignedSitio'] ?? '—').toString(),
                          ),
                          _reviewValue(
                            'Position',
                            (bhw['position'] ?? 'Barangay Health Worker')
                                .toString(),
                          ),
                          _reviewValue(
                            'Employment Status',
                            (bhw['employmentStatus'] ?? '—').toString(),
                          ),
                          _reviewValue(
                            'Years of Service',
                            (bhw['yearsOfService'] ?? '0').toString(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: ChoColors.border),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Close'),
                    ),
                    if (row['isApproved'] == false) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _setBhwStatus(doc, approved: false);
                        },
                        child: const Text('Reject'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _setBhwStatus(doc, approved: true);
                        },
                        icon: const Icon(Icons.verified_user_outlined),
                        label: const Text('Approve'),
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
  }

  Widget _reviewSection(String title, IconData icon, List<Widget> children) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: ChoColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ChoColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: ChoColors.aqua, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: ChoColors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 12, runSpacing: 12, children: children),
          ],
        ),
      );

  Widget _reviewValue(String label, String value) => SizedBox(
    width: 245,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: ChoColors.muted, fontSize: 11),
        ),
        const SizedBox(height: 3),
        Text(
          value.trim().isEmpty ? '—' : value,
          style: const TextStyle(
            color: ChoColors.text,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Future<void> _setBhwStatus(
    FirestoreRestDocument doc, {
    required bool approved,
  }) async {
    final reason = TextEditingController();
    final proceed =
        approved ||
        await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Reject BHW Registration'),
                content: TextField(
                  controller: reason,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Rejection reason',
                    border: OutlineInputBorder(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (reason.text.trim().isNotEmpty) {
                        Navigator.pop(dialogContext, true);
                      }
                    },
                    child: const Text('Reject'),
                  ),
                ],
              ),
            ) ==
            true;
    if (!proceed) {
      reason.dispose();
      return;
    }
    try {
      final data = doc.data();
      final barangayCode = BarangayFirestorePaths.normalizeBarangayCode(
        (data['barangayCode'] ?? '').toString(),
      );
      final updates = <String, dynamic>{
        'status': approved ? 'Active' : 'Rejected',
        'accountStatus': approved ? 'active' : 'rejected',
        'approvalStatus': approved ? 'approved' : 'rejected',
        'isApproved': approved,
        'updatedAt': FieldValue.serverTimestamp(),
        approved ? 'approvedBy' : 'reviewedBy':
            FirebaseAuth.instance.currentUser?.uid,
        approved ? 'approvedAt' : 'reviewedAt': FieldValue.serverTimestamp(),
        if (!approved) 'rejectionReason': reason.text.trim(),
        if (barangayCode.isNotEmpty) 'barangayCode': barangayCode,
      };
      final rootReference = _firestore.collection('users').doc(doc.id);
      final batch = _firestore.batch()..update(rootReference, updates);
      batch.set(
        _firestore.collection('bhw_registration_requests').doc(doc.id),
        {
          ...updates,
          'reviewStatus': approved ? 'approved' : 'rejected',
          'reviewedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (barangayCode.isNotEmpty) {
        batch.set(
          _firestore
              .collection('barangays')
              .doc(barangayCode)
              .collection('users')
              .doc(doc.id),
          {...data, ...updates, 'barangayCode': barangayCode},
          SetOptions(merge: true),
        );
      }
      await batch.commit();
      _refreshBhwAccounts();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account review failed: $error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      reason.dispose();
    }
  }

  Future<void> _editAssignment(FirestoreRestDocument doc) async {
    final current = doc.data();
    String initialValue(List<String> keys) {
      final value = _value(current, keys);
      return value.startsWith('—') ? '' : value;
    }

    final barangay = TextEditingController(
      text: initialValue(const ['barangay', 'assignedBarangay']),
    );
    final sitio = TextEditingController(
      text: initialValue(const ['sitio', 'purok', 'assignedPurok']),
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit BHW Assignment'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: barangay,
                decoration: const InputDecoration(
                  labelText: 'Assigned Barangay',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sitio,
                decoration: const InputDecoration(
                  labelText: 'Assigned Sitio / Purok',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (barangay.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Save Assignment'),
          ),
        ],
      ),
    );
    if (save == true) {
      try {
        final updates = <String, dynamic>{
          'barangay': barangay.text.trim(),
          'assignedBarangay': barangay.text.trim(),
          'sitio': sitio.text.trim(),
          'assignedPurok': sitio.text.trim(),
          'assignmentUpdatedBy': FirebaseAuth.instance.currentUser?.uid,
          'assignmentUpdatedAt': FieldValue.serverTimestamp(),
        };
        final batch = _firestore.batch();
        batch.update(_firestore.collection('users').doc(doc.id), updates);
        batch.set(
          _firestore.collection('bhw_registration_requests').doc(doc.id),
          updates,
          SetOptions(merge: true),
        );
        await batch.commit();
        _refreshBhwAccounts();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Assignment could not be updated: $error'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
    barangay.dispose();
    sitio.dispose();
  }

  Future<void> _createAnnouncement() async {
    final title = TextEditingController();
    final message = TextEditingController();
    String audience = 'All BHWs';
    String priority = 'Normal';
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New CHO Announcement'),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: message,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: audience,
                        decoration: const InputDecoration(
                          labelText: 'Audience',
                        ),
                        items: const ['All BHWs', 'Selected Barangays']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setDialogState(() => audience = value ?? audience),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: priority,
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                        ),
                        items: const ['Normal', 'Important', 'Urgent']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setDialogState(() => priority = value ?? priority),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (title.text.trim().isNotEmpty &&
                    message.text.trim().isNotEmpty) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Publish'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      try {
        await _firestore.collection('announcements').add({
          'title': title.text.trim(),
          'message': message.text.trim(),
          'audience': audience,
          'priority': priority,
          'status': 'Published',
          'publishedBy': FirebaseAuth.instance.currentUser?.uid,
          'publishDate': FieldValue.serverTimestamp(),
        });
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Announcement could not be published: $error'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
    title.dispose();
    message.dispose();
  }

  Widget _dataQuality() {
    return FutureBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
      future: _loadQualityRecords(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ChoErrorState(
            message: snapshot.error.toString(),
            onRetry: () => setState(() {}),
          );
        }
        if (!snapshot.hasData) return const ChoLoadingSkeleton();
        final records = snapshot.data!.expand((snap) => snap.docs).toList();
        final missingBarangay = records
            .where(
              (doc) =>
                  _value(doc.data(), const ['barangay', 'barangayName']) == '—',
            )
            .length;
        final missingPatient = records
            .where(
              (doc) =>
                  _value(doc.data(), const ['patientId', 'linkedPatientId']) ==
                  '—',
            )
            .length;
        final missingValidation = records
            .where(
              (doc) => _value(doc.data(), const ['validationStatus']) == '—',
            )
            .length;
        final invalidDates = records.where((doc) {
          final raw = doc.data()['date'] ?? doc.data()['createdAt'];
          return raw is String &&
              raw.isNotEmpty &&
              DateTime.tryParse(raw) == null;
        }).length;
        return ChoKpiGrid(
          children: [
            ChoKpiCard(
              label: 'Records Inspected',
              value: '${records.length}',
              icon: Icons.fact_check_outlined,
            ),
            ChoKpiCard(
              label: 'Missing Barangay',
              value: '$missingBarangay',
              icon: Icons.location_off_outlined,
              color: Colors.orangeAccent,
            ),
            ChoKpiCard(
              label: 'Unmatched Patient Reference',
              value: '$missingPatient',
              icon: Icons.person_off_outlined,
              color: Colors.redAccent,
            ),
            ChoKpiCard(
              label: 'Missing Validation Status',
              value: '$missingValidation',
              icon: Icons.pending_actions_outlined,
              color: Colors.orangeAccent,
            ),
            ChoKpiCard(
              label: 'Invalid Date Values',
              value: '$invalidDates',
              icon: Icons.event_busy_outlined,
              color: Colors.redAccent,
            ),
          ],
        );
      },
    );
  }

  Future<List<QuerySnapshot<Map<String, dynamic>>>>
  _loadQualityRecords() async {
    final scope = await UserAccessScopeService.instance.loadCurrentScope();
    const collections = [
      'patient_records',
      'checkup_records',
      'prenatal_records',
      'immunization_records',
      'morbidity_records',
      'mortality_records',
    ];
    return Future.wait(
      collections.map(
        (name) =>
            buildScopedRecordQuery(_firestore, name, scope).limit(100).get(),
      ),
    );
  }

  Widget _profile() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const ChoEmptyState(
        title: 'No authenticated account',
        message: 'Sign in with a CHO account to view profile settings.',
      );
    }
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _firestore
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 15)),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ChoErrorState(
            message: 'Profile information could not be loaded.',
            onRetry: () => setState(() {}),
          );
        }
        if (!snapshot.hasData) return const ChoLoadingSkeleton();
        final row = snapshot.data?.data() ?? <String, dynamic>{};
        final fields = <MapEntry<String, String>>[
          MapEntry(
            'Name',
            _value(row, const ['fullName', 'name', 'displayName']),
          ),
          MapEntry('Email', user.email ?? '—'),
          MapEntry(
            'Contact Number',
            _value(row, const ['contactNumber', 'phone']),
          ),
          MapEntry('Role', _value(row, const ['role'])),
          MapEntry(
            'Assigned Office / Area',
            _value(row, const [
              'office',
              'facility',
              'assignedArea',
              'barangay',
            ]),
          ),
          MapEntry(
            'Account Status',
            _value(row, const ['status', 'accountStatus']),
          ),
        ];
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: ChoColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 26,
                backgroundColor: ChoColors.surfaceAlt,
                child: Icon(Icons.person, color: ChoColors.aqua, size: 28),
              ),
              const SizedBox(height: 12),
              ...fields.map(
                (field) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    field.key,
                    style: const TextStyle(
                      color: ChoColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  subtitle: Text(
                    field.value,
                    style: const TextStyle(
                      color: ChoColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const Divider(color: ChoColors.border),
              const Text(
                'Role changes and permission management are not available in personal settings.',
                style: TextStyle(color: ChoColors.muted),
              ),
            ],
          ),
        );
      },
    );
  }
}
