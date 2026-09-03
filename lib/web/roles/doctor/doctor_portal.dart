import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/malaybalay_barangays.dart';
import 'package:mycapstone_project/web/shared/components/web_responsive_body.dart';
import 'package:mycapstone_project/web/shared/navigation/web_navigation_coordinator.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/shared/services/account_policy_service.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

enum DoctorPortalTab { dashboard, archive, profile }

class DoctorPortalPage extends StatefulWidget {
  const DoctorPortalPage({super.key, this.tab = DoctorPortalTab.dashboard});

  final DoctorPortalTab tab;

  @override
  State<DoctorPortalPage> createState() => _DoctorPortalPageState();
}

class _DoctorPortalPageState extends State<DoctorPortalPage> {
  final FirebaseFirestore _firestore = getFirestoreInstance();
  final AccountPolicyService _accountPolicy = AccountPolicyService.instance;
  final Set<String> _busyReferralIds = <String>{};
  final TextEditingController _searchController = TextEditingController();
  Timer? _philippineClock;
  DateTime _philippineNow = _nowInPhilippines();
  Map<String, dynamic> _profile = <String, dynamic>{};
  bool _loadingProfile = true;
  String? _profileError;
  String _archiveStatus = '';
  String _archiveBarangay = '';
  String _archiveSex = '';
  DateTime? _archiveFrom;
  DateTime? _archiveTo;
  bool _openedDeepLink = false;

  static const Set<String> _historicalStatuses = <String>{
    'completed',
    'closed',
    'cancelled',
    'declined',
  };

  @override
  void initState() {
    super.initState();
    _philippineClock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _philippineNow = _nowInPhilippines());
    });
    _loadProfile();
  }

  @override
  void dispose() {
    _philippineClock?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  static DateTime _nowInPhilippines() =>
      DateTime.now().toUtc().add(const Duration(hours: 8));

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _loadingProfile = false;
          _profileError = 'No authenticated doctor session was found.';
        });
      }
      return;
    }
    try {
      final snapshot = await _firestore.collection('users').doc(user.uid).get();
      if (!mounted) return;
      setState(() {
        _profile = <String, dynamic>{
          ...(snapshot.data() ?? <String, dynamic>{}),
          'uid': user.uid,
          'email': snapshot.data()?['email'] ?? user.email ?? '',
        };
        _loadingProfile = false;
        _profileError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
        _profileError = 'Profile information could not be loaded.';
      });
    }
  }

  String _value(
    Map<String, dynamic> data,
    List<String> keys, {
    String fallback = 'Not provided',
  }) {
    for (final key in keys) {
      final value = data[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return fallback;
  }

  String get _displayName => _value(_profile, const [
    'fullName',
    'displayName',
    'username',
  ], fallback: 'Doctor');

  String get _specialization => _value(_profile, const [
    'specialization',
    'doctorSpecialization',
    'specialty',
  ], fallback: 'General Medicine');

  String get _doctorDisplayName {
    final name = _displayName.trim();
    return name.toLowerCase().startsWith('dr.') ||
            name.toLowerCase().startsWith('dr ')
        ? name
        : 'Dr. $name';
  }

  String get _timeGreeting {
    final hour = _philippineNow.hour;
    if (hour < 12) return 'Good Morning';
    if (hour == 12) return 'Good Noon';
    if (hour < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  String get _pageTitle => switch (widget.tab) {
    DoctorPortalTab.dashboard => 'Doctor Dashboard',
    DoctorPortalTab.archive => 'Referral Archive',
    DoctorPortalTab.profile => 'Doctor Profile',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: WebResponsiveBody(
        sidebar: _DoctorSidebar(
          userName: _displayName,
          specialization: _specialization,
          activeTab: widget.tab,
        ),
        title: _pageTitle,
        mobileBrandAsset: 'assets/newlogo_white.png',
        child: _loadingProfile
            ? const Center(child: CircularProgressIndicator())
            : _profileError != null
            ? _errorState()
            : switch (widget.tab) {
                DoctorPortalTab.dashboard => _referralWorkspace(archive: false),
                DoctorPortalTab.archive => _referralWorkspace(archive: true),
                DoctorPortalTab.profile => _profilePage(),
              },
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 44,
                color: AppColors.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Doctor portal unavailable',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _profileError ?? 'Please try again.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _loadProfile,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _referralWorkspace({required bool archive}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _errorState();
    final stream = _firestore
        .collection('referrals')
        .where('assignedDoctorUid', isEqualTo: user.uid)
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _workspaceError('Referrals could not be loaded.');
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final allRecords = snapshot.data!.docs.toList(growable: false);
        final records = allRecords
            .where((doc) {
              final data = doc.data();
              final status = _normalizedStatus(data);
              final isHistorical = _historicalStatuses.contains(status);
              if (archive != isHistorical) return false;
              if (_archiveStatus.isNotEmpty &&
                  archive &&
                  status != _archiveStatus) {
                return false;
              }
              if (archive &&
                  _archiveBarangay.isNotEmpty &&
                  !_sameBarangay(
                    _value(data, const ['barangay', 'barangayName']),
                    _archiveBarangay,
                  )) {
                return false;
              }
              if (archive &&
                  _archiveSex.isNotEmpty &&
                  _value(data, const ['sex', 'gender']).toLowerCase() !=
                      _archiveSex.toLowerCase()) {
                return false;
              }
              if (archive && (_archiveFrom != null || _archiveTo != null)) {
                final recordDate = _recordDate(data);
                if (recordDate == null) return false;
                if (_archiveFrom != null &&
                    recordDate.isBefore(DateUtils.dateOnly(_archiveFrom!))) {
                  return false;
                }
                if (_archiveTo != null &&
                    !recordDate.isBefore(
                      DateUtils.dateOnly(
                        _archiveTo!,
                      ).add(const Duration(days: 1)),
                    )) {
                  return false;
                }
              }
              final query = _searchController.text.trim().toLowerCase();
              if (query.isEmpty) return true;
              final searchable = [
                doc.id,
                _value(data, const ['patientName', 'patientInformation']),
                _value(data, const [
                  'createdByName',
                  'bhwName',
                  'createdByEmail',
                ], fallback: 'Referring BHW'),
                _value(data, const ['barangay', 'barangayName']),
                _value(data, const [
                  'referralReason',
                  'reason',
                  'chiefComplaint',
                ]),
                status,
              ].join(' ').toLowerCase();
              return searchable.contains(query);
            })
            .toList(growable: false);

        if (!_openedDeepLink) {
          final requestedId = Uri.base.queryParameters['referralId'];
          final requested = requestedId == null
              ? null
              : allRecords.where((doc) => doc.id == requestedId).firstOrNull;
          if (requested != null) {
            _openedDeepLink = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showDetails(requested);
            });
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _pageHeader(archive),
                  const SizedBox(height: AppSpacing.md),
                  if (!archive) _summaryCards(allRecords),
                  if (!archive) const SizedBox(height: AppSpacing.md),
                  if (archive) ...[
                    _archiveFilters(allRecords),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  _recordList(records, archive: archive),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _normalizedStatus(Map<String, dynamic> data) => _value(
    data,
    const ['status'],
    fallback: 'assigned',
  ).trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');

  Map<String, dynamic> _patientInformation(Map<String, dynamic> data) {
    final value = data['patientInformation'];
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  String _patientValue(
    Map<String, dynamic> data,
    List<String> keys, {
    String fallback = 'Not provided',
  }) {
    return _value(
      data,
      keys,
      fallback: _value(_patientInformation(data), keys, fallback: fallback),
    );
  }

  Widget _pageHeader(bool archive) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                archive ? 'Referral Archive' : 'Assigned Referrals',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                archive
                    ? 'Review completed and historical referrals assigned to your account.'
                    : 'Review and process the active referrals assigned to you.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (!archive) ...[
                const SizedBox(height: AppSpacing.md),
                _greetingPanel(),
              ],
            ],
          );
          final action = OutlinedButton.icon(
            onPressed: _loadProfile,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Refresh'),
          );
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: AppSpacing.md),
                action,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: title),
              action,
            ],
          );
        },
      ),
    );
  }

  Widget _greetingPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wb_sunny_outlined,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$_timeGreeting, $_doctorDisplayName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${DateFormat('h:mm a').format(_philippineNow)} PHT',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _summaryCards(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final active = docs
        .where(
          (doc) => !_historicalStatuses.contains(_normalizedStatus(doc.data())),
        )
        .length;
    final urgent = docs.where((doc) {
      if (_historicalStatuses.contains(_normalizedStatus(doc.data()))) {
        return false;
      }
      final priority = _value(doc.data(), const [
        'priority',
        'referralPriority',
      ], fallback: '').toLowerCase();
      return priority == 'urgent' || priority == 'high';
    }).length;
    final awaiting = docs
        .where((doc) => _normalizedStatus(doc.data()) == 'assigned')
        .length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 600
            ? constraints.maxWidth
            : (constraints.maxWidth - AppSpacing.md * 2) / 3;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            _metricCard(
              width,
              'Active referrals',
              active,
              Icons.assignment_outlined,
            ),
            _metricCard(
              width,
              'Priority attention',
              urgent,
              Icons.priority_high_rounded,
            ),
            _metricCard(
              width,
              'Awaiting review',
              awaiting,
              Icons.schedule_outlined,
            ),
          ],
        );
      },
    );
  }

  Widget _metricCard(double width, String label, int value, IconData icon) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$value', style: Theme.of(context).textTheme.titleLarge),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _archiveFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sexes =
        docs
            .map((doc) => _value(doc.data(), const ['sex', 'gender']))
            .where((value) => value != 'Not provided')
            .toSet()
            .toList()
          ..sort();
    final selectedSex = sexes.contains(_archiveSex) ? _archiveSex : '';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fieldWidth = constraints.maxWidth < 620
              ? constraints.maxWidth
              : (constraints.maxWidth - AppSpacing.md) / 2;
          return Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: fieldWidth,
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: _inputDecoration(
                    'Search patient, barangay, or referral',
                    prefixIcon: const Icon(Icons.search_rounded),
                  ),
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _showBarangayPicker,
                  child: InputDecorator(
                    decoration: _inputDecoration('Barangay'),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _archiveBarangay.isEmpty
                                ? 'All barangays'
                                : _displayBarangayName(_archiveBarangay),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.search_rounded, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: DropdownButtonFormField<String>(
                  initialValue: selectedSex,
                  decoration: _inputDecoration('Sex'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All sexes')),
                    ...sexes.map(
                      (sex) => DropdownMenuItem(
                        value: sex,
                        child: Text(sex, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _archiveSex = value ?? ''),
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: DropdownButtonFormField<String>(
                  initialValue: _archiveStatus,
                  decoration: _inputDecoration('Status'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All statuses')),
                    DropdownMenuItem(
                      value: 'completed',
                      child: Text('Completed'),
                    ),
                    DropdownMenuItem(value: 'closed', child: Text('Closed')),
                    DropdownMenuItem(
                      value: 'declined',
                      child: Text('Declined'),
                    ),
                    DropdownMenuItem(
                      value: 'cancelled',
                      child: Text('Cancelled'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _archiveStatus = value ?? ''),
                ),
              ),
              _archiveDateButton(
                width: fieldWidth,
                label: _archiveFrom == null
                    ? 'From date'
                    : 'From ${_formatDateOnly(_archiveFrom!)}',
                icon: Icons.calendar_today_outlined,
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: _archiveFrom ?? DateTime.now(),
                  );
                  if (picked != null && mounted) {
                    setState(() => _archiveFrom = DateUtils.dateOnly(picked));
                  }
                },
              ),
              _archiveDateButton(
                width: fieldWidth,
                label: _archiveTo == null
                    ? 'To date'
                    : 'To ${_formatDateOnly(_archiveTo!)}',
                icon: Icons.event_outlined,
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: _archiveTo ?? DateTime.now(),
                  );
                  if (picked != null && mounted) {
                    setState(() => _archiveTo = DateUtils.dateOnly(picked));
                  }
                },
              ),
              TextButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _archiveStatus = '';
                    _archiveBarangay = '';
                    _archiveSex = '';
                    _archiveFrom = null;
                    _archiveTo = null;
                  });
                },
                icon: const Icon(Icons.clear_all_rounded, size: 18),
                label: const Text('Reset filters'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _displayBarangayName(String value) {
    final barangay = _barangayReference(value);
    if (barangay == null) return value;
    return _barangayLabel(barangay);
  }

  BarangayReference? _barangayReference(String value) {
    final normalized = value.trim().toLowerCase();
    return MalaybalayBarangays.byName(value) ??
        MalaybalayBarangays.byCode(value) ??
        MalaybalayBarangays.all
            .where(
              (barangay) =>
                  _barangayLabel(barangay).toLowerCase() == normalized,
            )
            .firstOrNull;
  }

  String _barangayLabel(BarangayReference barangay) {
    switch (barangay.code) {
      case 'st-peter':
        return 'Saint Peter';
      case 'sto-nino':
        return 'Santo Niño';
      case 'silae':
        return 'Sila-e';
      default:
        final numbered = RegExp(
          r'^Barangay 0*(\d+)$',
        ).firstMatch(barangay.name);
        if (numbered != null) {
          return 'Barangay ${numbered.group(1)} (Poblacion)';
        }
        return barangay.name;
    }
  }

  List<BarangayReference> _searchBarangays(String query) {
    final normalized = query
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return MalaybalayBarangays.all;
    final terms = normalized.split(' ');
    return MalaybalayBarangays.all
        .where((barangay) {
          final haystack = [
            barangay.searchLabel,
            _barangayLabel(barangay),
          ].join(' ').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
          return terms.every((term) => haystack.contains(term));
        })
        .toList(growable: false);
  }

  bool _sameBarangay(String left, String right) {
    final leftReference = _barangayReference(left);
    final rightReference = _barangayReference(right);
    if (leftReference != null && rightReference != null) {
      return leftReference.code == rightReference.code;
    }
    return left.trim().toLowerCase() == right.trim().toLowerCase();
  }

  Future<void> _showBarangayPicker() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _BarangayPickerDialog(
        selectedBarangay: _archiveBarangay,
        searchBarangays: _searchBarangays,
        barangayLabel: _barangayLabel,
        sameBarangay: _sameBarangay,
      ),
    );
    if (selected != null && mounted) {
      setState(() => _archiveBarangay = selected);
    }
  }

  Widget _archiveDateButton({
    required double width,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: width,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label, overflow: TextOverflow.ellipsis),
        ),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size(48, 56),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {Widget? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: AppColors.surfaceLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }

  Widget _recordList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> records, {
    required bool archive,
  }) {
    if (records.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 54, horizontal: 24),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.inbox_outlined,
              size: 42,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              archive
                  ? 'No archived referrals found'
                  : 'No active referrals assigned',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              archive
                  ? 'Completed or historical referrals will appear here.'
                  : 'New assignments will appear here automatically after routing.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            '${records.length} referral${records.length == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ...records.map(
          (doc) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _referralCard(doc, archive: archive),
          ),
        ),
      ],
    );
  }

  Widget _referralCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required bool archive,
  }) {
    final data = doc.data();
    final status = _normalizedStatus(data);
    final patient = _value(data, const [
      'patientName',
    ], fallback: 'Patient record');
    final barangay = _value(data, const ['barangay', 'barangayName']);
    final reason = _value(data, const [
      'referralReason',
      'reason',
      'chiefComplaint',
    ]);
    final priority = _value(data, const [
      'priority',
      'referralPriority',
    ], fallback: 'Routine');
    final busy = _busyReferralIds.contains(doc.id);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : () => _showDetails(doc),
                icon: const Icon(Icons.visibility_outlined, size: 17),
                label: const Text('View details'),
              ),
              if (!archive &&
                  [
                    'assigned',
                    'doctor_assigned',
                    'approved',
                    'hospital_assigned',
                  ].contains(status))
                FilledButton.icon(
                  onPressed: busy ? null : () => _acceptReferral(doc),
                  icon: const Icon(Icons.check_rounded, size: 17),
                  label: const Text('Accept referral'),
                ),
              if (!archive &&
                  ![
                    'completed',
                    'closed',
                    'cancelled',
                    'declined',
                  ].contains(status))
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _showUpdateCare(doc),
                  icon: const Icon(Icons.edit_note_rounded, size: 17),
                  label: const Text('Update care'),
                ),
              if (!archive && ['consulted', 'in_treatment'].contains(status))
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _closeReferral(doc),
                  icon: const Icon(Icons.task_alt_rounded, size: 17),
                  label: const Text('Close referral'),
                ),
              if (!archive &&
                  [
                    'assigned',
                    'doctor_assigned',
                    'waiting_consultation',
                  ].contains(status))
                TextButton.icon(
                  onPressed: busy ? null : () => _declineReferral(doc),
                  icon: const Icon(Icons.block_outlined, size: 17),
                  label: const Text('Decline'),
                ),
              if (!archive &&
                  ![
                    'completed',
                    'closed',
                    'cancelled',
                    'declined',
                  ].contains(status))
                TextButton.icon(
                  onPressed: busy ? null : () => _showTransfer(doc),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                  label: const Text('Refer to another doctor'),
                ),
            ],
          );
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      patient,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _statusBadge(status),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.xs,
                children: [
                  _detailText(Icons.location_on_outlined, barangay),
                  _detailText(Icons.flag_outlined, priority),
                  _detailText(Icons.calendar_today_outlined, _dateValue(data)),
                ],
              ),
              if (reason != 'Not provided') ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  reason,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          );
          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summary,
                const SizedBox(height: AppSpacing.md),
                actions,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: summary),
              const SizedBox(width: AppSpacing.lg),
              Flexible(
                child: Align(alignment: Alignment.topRight, child: actions),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _detailText(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.xs),
        Text(value, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _statusBadge(String status) {
    final terminal = _historicalStatuses.contains(status);
    final color = terminal ? AppColors.textSecondary : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: terminal
            ? AppColors.surfaceSubtle
            : AppColors.primary.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: terminal
              ? AppColors.borderStrong
              : AppColors.primary.withValues(alpha: .35),
        ),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _dateValue(Map<String, dynamic> data) {
    final value = _recordDate(data);
    if (value != null) return _shortDate(value);
    final raw =
        data['referralDateTime'] ?? data['referralDate'] ?? data['createdAt'];
    return raw?.toString() ?? 'Date not provided';
  }

  DateTime? _recordDate(Map<String, dynamic> data) {
    final value =
        data['referralDateTime'] ?? data['referralDate'] ?? data['createdAt'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  String _formatDateOnly(DateTime value) =>
      '${value.month}/${value.day}/${value.year}';

  String _shortDate(DateTime value) =>
      DateFormat('M/d/yyyy h:mm a').format(value.toLocal());

  Widget _workspaceError(String message) {
    return Center(
      child: Text(
        message,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
    );
  }

  Future<void> _acceptReferral(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final confirmed = await _confirm(
      'Accept referral',
      'Accept this referral and move it to consultation review?',
    );
    if (confirmed != true) return;
    await _performAction(doc, 'accept');
  }

  Future<void> _closeReferral(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final confirmed = await _confirm(
      'Close referral',
      'Close this referral after documenting the consultation?',
    );
    if (confirmed != true) return;
    await _performAction(doc, 'close');
  }

  Future<void> _declineReferral(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final reason = await _reasonDialog(
      title: 'Decline referral',
      label: 'Reason for declining',
      required: true,
    );
    if (reason == null) return;
    await _performAction(doc, 'decline', reason: reason);
  }

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<String?> _reasonDialog({
    required String title,
    required String label,
    required bool required,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          decoration: _inputDecoration(label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (required && value.isEmpty) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<bool> _performAction(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String action, {
    String? reason,
    String? targetDoctorUid,
    String? status,
    String? doctorDiagnosis,
    String? doctorTreatment,
    String? doctorMedication,
    String? doctorNotes,
  }) async {
    if (_busyReferralIds.contains(doc.id)) return false;
    setState(() => _busyReferralIds.add(doc.id));
    try {
      final result = await _accountPolicy.doctorReferralAction(
        referralId: doc.id,
        action: action,
        reason: reason,
        targetDoctorUid: targetDoctorUid,
        operationId:
            '${doc.id}:$action:${DateTime.now().microsecondsSinceEpoch}',
        status: status,
        doctorDiagnosis: doctorDiagnosis,
        doctorTreatment: doctorTreatment,
        doctorMedication: doctorMedication,
        doctorNotes: doctorNotes,
      );
      if (!mounted) return true;
      final message = action == 'transfer'
          ? 'Referral transferred and the new doctor was notified.'
          : 'Referral ${result.status.replaceAll('_', ' ')}.';
      _snack(message);
      return true;
    } catch (error) {
      if (mounted) _snack('Could not update referral: $error');
      return false;
    } finally {
      if (mounted) setState(() => _busyReferralIds.remove(doc.id));
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showDetails(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final fields = <MapEntry<String, String>>[
      MapEntry('Patient', _value(data, const ['patientName'])),
      MapEntry(
        'Patient ID',
        _value(data, const ['patientId', 'patientRecordId']),
      ),
      MapEntry('Sex', _patientValue(data, const ['sex', 'gender'])),
      MapEntry('Age', _patientValue(data, const ['age', 'patientAge'])),
      MapEntry(
        'Date of birth',
        _patientValue(data, const ['dateOfBirth', 'dob', 'patientDateOfBirth']),
      ),
      MapEntry(
        'Contact',
        _patientValue(data, const [
          'contactNumber',
          'phoneNumber',
          'phone',
          'patientContactNumber',
        ]),
      ),
      MapEntry(
        'Barangay',
        _patientValue(data, const ['barangay', 'barangayName']),
      ),
      MapEntry(
        'Address',
        _patientValue(data, const [
          'address',
          'street',
          'fullAddress',
          'patientAddress',
        ]),
      ),
      MapEntry('Referral date', _dateValue(data)),
      MapEntry(
        'Referral source',
        _value(data, const [
          'createdByName',
          'bhwName',
          'createdByEmail',
        ], fallback: 'Referring BHW'),
      ),
      MapEntry(
        'Reason',
        _value(data, const ['referralReason', 'reason', 'chiefComplaint']),
      ),
      MapEntry(
        'Priority',
        _value(data, const [
          'priority',
          'referralPriority',
        ], fallback: 'Routine'),
      ),
      MapEntry('Status', _normalizedStatus(data).replaceAll('_', ' ')),
      MapEntry(
        'Assigned doctor',
        _value(data, const ['assignedDoctorName'], fallback: _displayName),
      ),
      MapEntry(
        'Vital signs',
        _value(data, const ['latestVitalSigns', 'vitalSigns']),
      ),
      MapEntry(
        'Assessment',
        _value(data, const ['doctorDiagnosis', 'impression']),
      ),
      MapEntry('Notes', _value(data, const ['doctorNotes', 'supportingNotes'])),
    ];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Referral details'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: fields
                  .map((field) => _detailRow(field.key, field.value))
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          if (!_historicalStatuses.contains(_normalizedStatus(data)))
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showUpdateCare(doc);
              },
              child: const Text('Update care'),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Future<void> _showUpdateCare(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final diagnosis = TextEditingController(
      text: _value(data, const ['doctorDiagnosis'], fallback: ''),
    );
    final treatment = TextEditingController(
      text: _value(data, const ['doctorTreatment'], fallback: ''),
    );
    final medication = TextEditingController(
      text: _value(data, const ['doctorMedication'], fallback: ''),
    );
    final notes = TextEditingController(
      text: _value(data, const ['doctorNotes'], fallback: ''),
    );
    var status = _normalizedStatus(data);
    var saving = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Update referral care'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: _inputDecoration('Referral status'),
                    items: const [
                      DropdownMenuItem(
                        value: 'assigned',
                        child: Text('Assigned'),
                      ),
                      DropdownMenuItem(
                        value: 'doctor_assigned',
                        child: Text('Doctor assigned'),
                      ),
                      DropdownMenuItem(
                        value: 'waiting_consultation',
                        child: Text('Waiting consultation'),
                      ),
                      DropdownMenuItem(
                        value: 'consulted',
                        child: Text('Consulted'),
                      ),
                      DropdownMenuItem(
                        value: 'in_treatment',
                        child: Text('In treatment'),
                      ),
                      DropdownMenuItem(
                        value: 'completed',
                        child: Text('Completed'),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) =>
                              setDialogState(() => status = value ?? status),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _dialogField(diagnosis, 'Assessment / diagnosis'),
                  _dialogField(treatment, 'Treatment / plan'),
                  _dialogField(medication, 'Medication'),
                  _dialogField(notes, 'Doctor notes'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      final succeeded = await _performAction(
                        doc,
                        'update_care',
                        status: status,
                        doctorDiagnosis: diagnosis.text,
                        doctorTreatment: treatment.text,
                        doctorMedication: medication.text,
                        doctorNotes: notes.text,
                      );
                      if (succeeded && dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
    diagnosis.dispose();
    treatment.dispose();
    medication.dispose();
    notes.dispose();
    if (result == true && mounted) setState(() {});
  }

  Widget _dialogField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: TextField(
        controller: controller,
        maxLines: 3,
        decoration: _inputDecoration(label),
      ),
    );
  }

  Future<void> _showTransfer(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    List<Map<String, dynamic>> doctors;
    try {
      doctors = await _accountPolicy.listDoctorTransferTargets();
    } catch (error) {
      if (mounted) _snack('Eligible doctors could not be loaded: $error');
      return;
    }
    if (!mounted) return;
    if (doctors.isEmpty) {
      _snack('No other active doctors are eligible for transfer.');
      return;
    }
    String? selectedUid = doctors.first['uid']?.toString();
    final reasonController = TextEditingController();
    var saving = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Refer to another doctor'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedUid,
                  decoration: _inputDecoration('Eligible doctor'),
                  items: doctors.map((doctor) {
                    final uid = doctor['uid']?.toString() ?? '';
                    final name = _value(doctor, const [
                      'fullName',
                      'displayName',
                      'username',
                      'email',
                    ], fallback: 'Doctor');
                    final specialty = _value(doctor, const [
                      'specialization',
                      'specialty',
                    ], fallback: 'General Medicine');
                    return DropdownMenuItem(
                      value: uid,
                      child: Text(
                        '$name · $specialty',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: saving
                      ? null
                      : (value) => setDialogState(() => selectedUid = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  decoration: _inputDecoration('Transfer reason'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  saving ||
                      selectedUid == null ||
                      reasonController.text.trim().isEmpty
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      final succeeded = await _performAction(
                        doc,
                        'transfer',
                        targetDoctorUid: selectedUid,
                        reason: reasonController.text,
                      );
                      if (succeeded && dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    },
              child: Text(saving ? 'Transferring…' : 'Confirm transfer'),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();
    if (result == true && mounted) setState(() {});
  }

  Widget _profilePage() {
    final email = _value(_profile, const ['email'], fallback: 'Not provided');
    final contact = _value(_profile, const [
      'contactNumber',
      'phoneNumber',
      'phone',
    ]);
    final title = _value(_profile, const [
      'professionalTitle',
      'title',
    ], fallback: 'Doctor');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Doctor Profile',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Manage your professional contact details. Account access remains CHO Admin-controlled.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final identity = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: AppColors.primary,
                          child: Text(
                            _displayName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$title · $_specialization',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textOnDarkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                    final editButton = OutlinedButton.icon(
                      onPressed: _showEditProfile,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit profile'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.transparent,
                        side: const BorderSide(
                          color: AppColors.textOnDarkMuted,
                        ),
                      ),
                    );
                    if (constraints.maxWidth < 560) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          identity,
                          const SizedBox(height: AppSpacing.md),
                          editButton,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: identity),
                        const SizedBox(width: AppSpacing.md),
                        editButton,
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _profileSection('Account information', [
                _profileRow('Registered email', email, Icons.email_outlined),
                _profileRow('Role', 'Doctor', Icons.medical_services_outlined),
                _profileRow(
                  'Access',
                  'Assigned referrals only',
                  Icons.lock_outline,
                ),
              ]),
              const SizedBox(height: AppSpacing.md),
              _profileSection('Professional information', [
                _profileRow('Full name', _displayName, Icons.person_outline),
                _profileRow('Professional title', title, Icons.badge_outlined),
                _profileRow(
                  'Specialization',
                  _specialization,
                  Icons.local_hospital_outlined,
                ),
                _profileRow('Contact number', contact, Icons.phone_outlined),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileSection(String title, List<Widget> rows) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          ...rows,
        ],
      ),
    );
  }

  Widget _profileRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditProfile() async {
    final name = TextEditingController(text: _displayName);
    final username = TextEditingController(
      text: _value(_profile, const ['username'], fallback: ''),
    );
    final contact = TextEditingController(
      text: _value(_profile, const [
        'contactNumber',
        'phoneNumber',
        'phone',
      ], fallback: ''),
    );
    final title = TextEditingController(
      text: _value(_profile, const [
        'professionalTitle',
        'title',
      ], fallback: 'Doctor'),
    );
    final specialty = TextEditingController(text: _specialization);
    var saving = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit doctor profile'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _dialogFieldSingle(name, 'Full name'),
                  _dialogFieldSingle(username, 'Username'),
                  _dialogFieldSingle(contact, 'Contact number'),
                  _dialogFieldSingle(title, 'Professional title'),
                  _dialogFieldSingle(specialty, 'Specialization'),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Email, role, access, account status, and referral eligibility remain CHO Admin-controlled.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty ||
                          username.text.trim().length < 3 ||
                          specialty.text.trim().isEmpty) {
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await _accountPolicy.updateOwnDoctorProfile(
                          fullName: name.text,
                          username: username.text,
                          contactNumber: contact.text,
                          professionalTitle: title.text,
                          specialization: specialty.text,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                        await _loadProfile();
                        if (mounted) _snack('Doctor profile updated.');
                      } catch (error) {
                        if (dialogContext.mounted) {
                          setDialogState(() => saving = false);
                        }
                        if (mounted) _snack('Could not update profile: $error');
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    username.dispose();
    contact.dispose();
    title.dispose();
    specialty.dispose();
    if (result == true && mounted) setState(() {});
  }

  Widget _dialogFieldSingle(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextField(
        controller: controller,
        decoration: _inputDecoration(label),
      ),
    );
  }
}

class _DoctorSidebar extends StatelessWidget {
  const _DoctorSidebar({
    required this.userName,
    required this.specialization,
    required this.activeTab,
  });

  final String userName;
  final String specialization;
  final DoctorPortalTab activeTab;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 268,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.backgroundDark,
        border: Border(right: BorderSide(color: Color(0xFF1C3D66), width: 1)),
        boxShadow: [
          BoxShadow(
            color: Color(0x2E163B66),
            blurRadius: 6,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Image.asset(
                      'assets/newlogo_white.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
                            child: Text(
                              'AI',
                              style: TextStyle(
                                color: AppColors.textOnDark,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .5,
                              ),
                            ),
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI-DSUHIS',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textOnDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Doctor Portal',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textOnDarkMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primary,
                    child: Icon(
                      Icons.person_outline,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Doctor · $specialization',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textOnDarkMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                'DOCTOR PORTAL',
                style: TextStyle(
                  color: AppColors.textOnDarkMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .7,
                ),
              ),
            ),
            const SizedBox(height: 4),
            _item(
              context,
              DoctorPortalTab.dashboard,
              Icons.dashboard_outlined,
              'Dashboard',
              WebRoutes.doctorDashboard,
            ),
            _item(
              context,
              DoctorPortalTab.archive,
              Icons.archive_outlined,
              'Archive',
              WebRoutes.doctorArchive,
            ),
            _item(
              context,
              DoctorPortalTab.profile,
              Icons.person_outline,
              'Profile',
              WebRoutes.doctorProfile,
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) Get.offAllNamed(WebRoutes.landing);
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Log out'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    DoctorPortalTab tab,
    IconData icon,
    String label,
    String route,
  ) {
    final active = tab == activeTab;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: active ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => WebNavigationCoordinator.goToNamed(context, route),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarangayPickerDialog extends StatefulWidget {
  const _BarangayPickerDialog({
    required this.selectedBarangay,
    required this.searchBarangays,
    required this.barangayLabel,
    required this.sameBarangay,
  });

  final String selectedBarangay;
  final List<BarangayReference> Function(String query) searchBarangays;
  final String Function(BarangayReference barangay) barangayLabel;
  final bool Function(String left, String right) sameBarangay;

  @override
  State<_BarangayPickerDialog> createState() => _BarangayPickerDialogState();
}

class _BarangayPickerDialogState extends State<_BarangayPickerDialog> {
  late final TextEditingController _queryController;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.searchBarangays(_queryController.text);
    final pickerHeight = (MediaQuery.sizeOf(context).height * .58)
        .clamp(280.0, 520.0)
        .toDouble();
    return AlertDialog(
      title: const Text('Select Barangay'),
      content: SizedBox(
        width: double.maxFinite,
        height: pickerHeight,
        child: Column(
          children: [
            TextField(
              controller: _queryController,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: _inputDecoration(
                'Search all barangays',
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: ListView.separated(
                itemCount: options.length + 1,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ListTile(
                      dense: true,
                      title: const Text('All barangays'),
                      leading: const Icon(Icons.public_outlined),
                      onTap: () => Navigator.pop(context, ''),
                    );
                  }
                  final barangay = options[index - 1];
                  return ListTile(
                    dense: true,
                    title: Text(widget.barangayLabel(barangay)),
                    subtitle: Text(barangay.district),
                    leading: const Icon(Icons.location_on_outlined),
                    selected: widget.sameBarangay(
                      widget.selectedBarangay,
                      barangay.name,
                    ),
                    onTap: () => Navigator.pop(context, barangay.name),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label, {Widget? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: AppColors.surfaceLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
