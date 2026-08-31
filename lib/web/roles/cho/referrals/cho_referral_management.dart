import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_navigation.dart';
import 'package:mycapstone_project/web/shared/components/web_responsive_body.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_components.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_config.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/shared/services/account_policy_service.dart';
import 'package:mycapstone_project/web/shared/components/app_buttons.dart';
import 'package:mycapstone_project/web/shared/components/web_data_components.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/shared/utils/csv_download.dart';
import 'package:mycapstone_project/web/shared/utils/clinical_record_mapping.dart';

/// CHO referral monitoring workspace — reached from the sidebar
/// "Referrals" destination (`cho_navigation.dart`). Owns the referral
/// display state (`_ReferralRecord`, including submitted /
/// hospital_assigned / doctor_assigned / waiting_consultation / consulted
/// / completed). Normal referrals are routed by the backend; CHO Admin can
/// inspect details and reassign only when an exception requires it.
class _DoctorDirectoryEntry {
  _DoctorDirectoryEntry({required this.data, required this.references});

  final Map<String, dynamic> data;
  final List<DocumentReference<Map<String, dynamic>>> references;
}

class CHOPreferralPage extends StatefulWidget {
  const CHOPreferralPage({super.key});

  @override
  State<CHOPreferralPage> createState() => _CHOPreferralPageState();
}

class _CHOPreferralPageState extends State<CHOPreferralPage> {
  final FirebaseFirestore _firestore = getFirestoreInstance();
  final PatientCenteredHistoryService _patientHistoryService =
      PatientCenteredHistoryService();
  final AccountPolicyService _accountPolicyService =
      AccountPolicyService.instance;
  int _view = 0;
  bool _loadingScope = true;
  String? _accessError;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream;
  List<_DoctorDirectoryEntry> _doctorDirectory = <_DoctorDirectoryEntry>[];
  bool _loadingDoctorDirectory = false;
  bool _isChoAdmin = false;
  String? _requestedReferralId;
  bool _requestedReferralOpened = false;

  static const _tabs = <String>[
    'Insights',
    'Submitted / Awaiting Assignment',
    'Assigned / In Progress',
    'Completed Referrals',
  ];

  @override
  void initState() {
    super.initState();
    _requestedReferralId = Uri.base.queryParameters['referralId']?.trim();
    final requestedView = int.tryParse(Uri.base.queryParameters['view'] ?? '');
    if (requestedView != null &&
        requestedView >= 0 &&
        requestedView < _tabs.length) {
      _view = requestedView;
    }
    _loadScope();
  }

  Future<void> _loadScope() async {
    if (mounted) {
      setState(() {
        _loadingScope = true;
        _accessError = null;
      });
    }
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
        throw StateError('A verified CHO account is required.');
      }
      if (!mounted) return;
      setState(() {
        _stream = _firestore.collection('referrals').snapshots();
        _isChoAdmin = scope.isChoAdmin;
        _loadingScope = false;
      });
      unawaited(_loadDoctorDirectory());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _accessError = error.toString().replaceFirst('Bad state: ', '');
        _loadingScope = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChoColors.background,
      body: WebResponsiveBody(
        sidebar: const ChoNavigationDrawer(current: ChoDestination.referrals),
        title: 'CHO Referral Management',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const heading = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CHO Referral Management',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: ChoColors.text,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Monitor automatic referral routing and track clinical referrals across all health facilities.',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12,
                          color: ChoColors.muted,
                        ),
                      ),
                    ],
                  );
                  final actions = Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const ChoStatusBadge('City Health Office'),
                      IconButton(
                        onPressed: _loadScope,
                        tooltip: 'Refresh referrals',
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: ChoColors.text,
                        ),
                      ),
                    ],
                  );
                  if (constraints.maxWidth < 680) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [heading, const SizedBox(height: 10), actions],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: heading),
                      const SizedBox(width: 12),
                      actions,
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1, color: ChoColors.border),
            Expanded(
              child: _loadingScope
                  ? const ChoLoadingSkeleton()
                  : _accessError != null
                  ? ChoErrorState(message: _accessError!, onRetry: _loadScope)
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _stream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return ChoErrorState(
                            message:
                                'Referral records could not be loaded. Check your connection and try again.',
                            onRetry: _loadScope,
                          );
                        }
                        if (!snapshot.hasData) {
                          return const ChoLoadingSkeleton();
                        }
                        final records =
                            snapshot.data!.docs
                                .map(_ReferralRecord.new)
                                .toList()
                              ..sort(
                                (a, b) => b.updatedAt.compareTo(a.updatedAt),
                              );
                        _openRequestedReferralIfNeeded(records);
                        return _content(records);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _openRequestedReferralIfNeeded(List<_ReferralRecord> records) {
    final requestedId = _requestedReferralId;
    if (_requestedReferralOpened ||
        requestedId == null ||
        requestedId.isEmpty) {
      return;
    }
    _ReferralRecord? match;
    for (final record in records) {
      if (record.id == requestedId) {
        match = record;
        break;
      }
    }
    if (match == null) return;
    final target = match;
    _requestedReferralOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _details(target);
    });
  }

  Widget _content(List<_ReferralRecord> records) {
    final pending = records.where((record) => record.isPending).toList();
    final active = records.where((record) => record.isActive).toList();
    final completed = records.where((record) => record.isClosed).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChoPageHeader(
            title: 'Referral Management',
            description:
                'Monitor validated BHW referrals, automatic doctor assignments, and referral progress. CHO intervention is limited to exceptions and reassignment.',
            icon: Icons.assignment_turned_in_outlined,
            actions: [
              FilledButton.icon(
                onPressed: () => _exportReport(records),
                style: AppButtonStyles.report(),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Generate report'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ChoViewTabs(
            tabs: _tabs,
            selectedIndex: _view,
            onChanged: (value) => setState(() => _view = value),
          ),
          const SizedBox(height: 12),
          if (_view == 0) ...[
            _doctorDirectoryPanel(),
            const SizedBox(height: 12),
          ],
          switch (_view) {
            0 => _insights(records),
            1 => _queue(
              pending,
              title: 'Submitted / Awaiting Assignment',
              emptyMessage: 'No referrals are currently awaiting doctor assignment.',
              mode: _QueueMode.pending,
            ),
            2 => _queue(
              active,
              title: 'Assigned / In Progress',
              emptyMessage: 'No referrals are currently active.',
              mode: _QueueMode.active,
            ),
            _ => _queue(
              completed,
              title: 'Completed Referrals',
              emptyMessage: 'No completed or closed referrals were found.',
              mode: _QueueMode.completed,
            ),
          },
        ],
      ),
    );
  }

  Future<void> _loadDoctorDirectory() async {
    if (mounted) setState(() => _loadingDoctorDirectory = true);
    try {
      final entries = <String, _DoctorDirectoryEntry>{};

      String keyFor(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
        final data = doc.data();
        final uid = _s(data, ['userUid', 'uid', 'userId']).toLowerCase();
        if (uid.isNotEmpty) return 'uid:$uid';
        final email = _s(data, ['email']).toLowerCase();
        if (email.isNotEmpty) return 'email:$email';
        final name = _s(data, [
          'fullName',
          'username',
          'displayName',
        ]).toLowerCase();
        if (name.isNotEmpty) return 'name:$name';
        return doc.reference.path;
      }

      void mergeDocs(
        Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
        for (final doc in docs) {
          final key = keyFor(doc);
          final existing = entries[key];
          if (existing == null) {
            entries[key] = _DoctorDirectoryEntry(
              data: <String, dynamic>{...doc.data()},
              references: <DocumentReference<Map<String, dynamic>>>[
                doc.reference,
              ],
            );
          } else {
            // Prefer the users record for overlapping account fields, while
            // retaining registry-only fields such as availability/specialty.
            existing.data.addAll(doc.data());
            existing.references.add(doc.reference);
          }
        }
      }

      final registrySnapshot = await _firestore
          .collection('doctor_registry')
          .get();
      mergeDocs(registrySnapshot.docs);
      final usersSnapshot = await _firestore
          .collection('users')
          .where('role', whereIn: const <String>['DOCTOR', 'doctor'])
          .get();
      mergeDocs(usersSnapshot.docs);

      final doctors = entries.values.toList()
        ..sort(
          (a, b) =>
              _s(a.data, [
                'fullName',
                'username',
                'displayName',
                'email',
              ], fallback: 'Doctor').toLowerCase().compareTo(
                _s(b.data, [
                  'fullName',
                  'username',
                  'displayName',
                  'email',
                ], fallback: 'Doctor').toLowerCase(),
              ),
        );
      if (mounted) {
        setState(() {
          _doctorDirectory = doctors;
          _loadingDoctorDirectory = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDoctorDirectory = false);
    }
  }

  Widget _doctorDirectoryPanel() {
    final activeDoctors = _doctorDirectory
        .where((doctor) {
          final data = doctor.data;
          final accountStatus = _s(data, [
            'accountStatus',
          ], fallback: 'active').toLowerCase().replaceAll('-', '_');
          final approvalStatus = _s(data, [
            'approvalStatus',
          ], fallback: 'pending').toLowerCase();
          return approvalStatus == 'approved' && accountStatus == 'active';
        })
        .toList(growable: false);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ChoColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ChoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Doctor Directory',
                style: TextStyle(
                  color: ChoColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${activeDoctors.length} active doctors',
                style: const TextStyle(
                  color: ChoColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_isChoAdmin)
                FilledButton.icon(
                  onPressed: _showCreateDoctorDialog,
                  style: AppButtonStyles.primary(background: ChoColors.ice),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Add doctor'),
                ),
              IconButton(
                tooltip: 'Refresh doctors',
                onPressed: _loadDoctorDirectory,
                icon: const Icon(Icons.refresh_rounded),
                color: ChoColors.text,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingDoctorDirectory)
            const LinearProgressIndicator()
          else if (activeDoctors.isEmpty)
            const Text(
              'No active doctor records are available. Add a doctor or update an existing account.',
              style: TextStyle(color: ChoColors.muted),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 980
                    ? 3
                    : constraints.maxWidth >= 620
                    ? 2
                    : 1;
                final width = columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 12 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: activeDoctors
                      .map(
                        (doc) => SizedBox(
                          width: width,
                          child: _doctorDirectoryCard(doc),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _doctorDirectoryCard(_DoctorDirectoryEntry doctor) {
    final data = doctor.data;
    final name = _s(data, [
      'fullName',
      'username',
      'displayName',
      'email',
    ], fallback: 'Doctor');
    final email = _s(data, ['email'], fallback: 'No email provided');
    final specialization = _s(data, [
      'specialization',
      'doctorSpecialization',
    ], fallback: 'General Medicine');
    final availability = _s(data, [
      'availability',
      'doctorAvailability',
      'status',
    ], fallback: 'available').toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    final unavailable =
        availability.contains('unavailable') ||
        availability.contains('leave') ||
        availability == 'busy' ||
        availability == 'inactive';
    final statusIcon = unavailable ? Icons.cancel : Icons.check_circle;
    final statusLabel = unavailable ? 'Not available' : 'Available';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ChoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ChoColors.text,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Email address',
            style: TextStyle(
              color: ChoColors.text,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: ChoColors.text, fontSize: 12),
          ),
          const SizedBox(height: 10),
          const Text(
            'Specialization',
            style: TextStyle(
              color: ChoColors.text,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _doctorDetailPill(
                icon: Icons.medical_services_outlined,
                label: specialization,
              ),
              _doctorDetailPill(icon: statusIcon, label: statusLabel),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showEditDoctorDialog(doctor),
                style: _doctorOutlineButtonStyle(),
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Edit'),
              ),
              OutlinedButton.icon(
                onPressed: () => _showDoctorAvailabilityDialog(doctor),
                style: _doctorOutlineButtonStyle(),
                icon: const Icon(Icons.event_available_outlined, size: 17),
                label: const Text('Availability'),
              ),
              OutlinedButton.icon(
                onPressed: () => _deactivateDoctor(doctor),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  minimumSize: const Size(48, 44),
                ),
                icon: const Icon(Icons.person_off_outlined, size: 17),
                label: const Text('Deactivate'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _doctorDetailPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ChoColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: ChoColors.text, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: ChoColors.text,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _doctorOutlineButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: ChoColors.text,
      backgroundColor: Colors.white,
      side: const BorderSide(color: ChoColors.border),
      minimumSize: const Size(48, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );
  }

  Future<void> _showCreateDoctorDialog() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final specialization = TextEditingController(text: 'General Medicine');
    var availability = 'available';
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: ChoColors.surface,
          title: const Text(
            'Add Doctor',
            style: TextStyle(color: ChoColors.text),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: _lightDecoration('Full name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: email,
                  decoration: _lightDecoration('Email address'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: specialization,
                  decoration: _lightDecoration('Specialization'),
                ),
                const SizedBox(height: 10),
                _lightDropdown(
                  label: 'Availability',
                  value: availability,
                  values: const {
                    'available': 'Available',
                    'busy': 'Busy',
                    'limited': 'Limited',
                    'on_leave': 'On leave',
                    'unavailable': 'Unavailable',
                  },
                  onChanged: (value) =>
                      setDialogState(() => availability = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty ||
                          email.text.trim().isEmpty) {
                        _snack('Doctor name and email are required.');
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await _accountPolicyService.createChoAccount(
                          fullName: name.text,
                          email: email.text,
                          role: 'DOCTOR',
                          specialization: specialization.text,
                          availability: availability,
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        await _loadDoctorDirectory();
                        _snack(
                          'Doctor account created and added to the directory.',
                        );
                      } catch (error) {
                        if (dialogContext.mounted) {
                          setDialogState(() => saving = false);
                        }
                        _snack('Could not add doctor: $error');
                      }
                    },
              style: AppButtonStyles.primary(),
              child: Text(saving ? 'Saving...' : 'Add doctor'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    email.dispose();
    specialization.dispose();
  }

  Future<void> _showEditDoctorDialog(_DoctorDirectoryEntry doctor) async {
    final data = doctor.data;
    final name = TextEditingController(
      text: _s(data, [
        'fullName',
        'username',
        'displayName',
      ], fallback: 'Doctor'),
    );
    final email = TextEditingController(text: _s(data, ['email']));
    final specialization = TextEditingController(
      text: _s(data, [
        'specialization',
        'doctorSpecialization',
      ], fallback: 'General Medicine'),
    );
    var availability = _s(data, [
      'availability',
      'doctorAvailability',
      'status',
    ], fallback: 'available').toLowerCase();
    if (!{
      'available',
      'busy',
      'limited',
      'on_leave',
      'unavailable',
    }.contains(availability)) {
      availability = 'available';
    }
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: ChoColors.surface,
          title: const Text(
            'Edit Doctor',
            style: TextStyle(color: ChoColors.text),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: _lightDecoration('Full name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: email,
                  readOnly: true,
                  decoration: _lightDecoration(
                    'Email address (managed by Auth)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: specialization,
                  decoration: _lightDecoration('Specialization'),
                ),
                const SizedBox(height: 10),
                _lightDropdown(
                  label: 'Availability',
                  value: availability,
                  values: const {
                    'available': 'Available',
                    'busy': 'Busy',
                    'limited': 'Limited',
                    'on_leave': 'On leave',
                    'unavailable': 'Unavailable',
                  },
                  onChanged: (value) =>
                      setDialogState(() => availability = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty ||
                          specialization.text.trim().isEmpty) {
                        _snack('Doctor name and specialization are required.');
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        final update = <String, dynamic>{
                          'fullName': name.text.trim(),
                          'username': name.text.trim(),
                          'displayName': name.text.trim(),
                          'specialization': specialization.text.trim(),
                          'doctorSpecialization': specialization.text.trim(),
                          'availability': availability,
                          'doctorAvailability': availability,
                          'status': availability,
                          'updatedAt': FieldValue.serverTimestamp(),
                        };
                        await Future.wait(
                          doctor.references.map(
                            (reference) =>
                                reference.set(update, SetOptions(merge: true)),
                          ),
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        await _loadDoctorDirectory();
                        _snack('Doctor details updated.');
                      } catch (error) {
                        if (dialogContext.mounted) {
                          setDialogState(() => saving = false);
                        }
                        _snack('Could not update doctor details: $error');
                      }
                    },
              style: AppButtonStyles.primary(),
              child: Text(saving ? 'Saving...' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    email.dispose();
    specialization.dispose();
  }

  Future<void> _showDoctorAvailabilityDialog(
    _DoctorDirectoryEntry doctor,
  ) async {
    final data = doctor.data;
    var availability = _s(data, [
      'availability',
      'doctorAvailability',
      'status',
    ], fallback: 'available').toLowerCase();
    if (!{
      'available',
      'busy',
      'limited',
      'on_leave',
      'unavailable',
    }.contains(availability)) {
      availability = 'available';
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: ChoColors.surface,
          title: const Text(
            'Update availability',
            style: TextStyle(color: ChoColors.text),
          ),
          content: _lightDropdown(
            label: 'Doctor availability',
            value: availability,
            values: const {
              'available': 'Available',
              'busy': 'Busy',
              'limited': 'Limited',
              'on_leave': 'On leave',
              'unavailable': 'Unavailable',
            },
            onChanged: (value) => setDialogState(() => availability = value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: AppButtonStyles.primary(),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await _accountPolicyService.updateChoAccount(
      uid: _s(data, ['userUid', 'uid', 'userId']),
      availability: availability,
    );
    await _loadDoctorDirectory();
    if (mounted) _snack('Doctor availability updated.');
  }

  Future<void> _deactivateDoctor(_DoctorDirectoryEntry doctor) async {
    final data = doctor.data;
    final name = _s(doctor.data, [
      'fullName',
      'username',
      'displayName',
    ], fallback: 'this doctor');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ChoColors.surface,
        title: const Text(
          'Deactivate doctor',
          style: TextStyle(color: ChoColors.text),
        ),
        content: Text(
          'Deactivate $name? The account will remain in history but will not receive new referrals.',
          style: const TextStyle(color: ChoColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              minimumSize: const Size(48, 44),
            ),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _accountPolicyService.updateChoAccount(
      uid: _s(data, ['userUid', 'uid', 'userId']),
      accountStatus: 'disabled',
      availability: 'unavailable',
    );
    await _loadDoctorDirectory();
    if (mounted) _snack('Doctor deactivated and removed from new assignments.');
  }

  Widget _insights(List<_ReferralRecord> records) {
    int count(bool Function(_ReferralRecord) predicate) =>
        records.where(predicate).length;
    final statuses = _counts(records, (record) => record.statusLabel);
    final priorities = _counts(records, (record) => record.priorityLabel);
    final barangays = _counts(records, (record) => record.barangay);
    final months = _monthlyCounts(records);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChoKpiGrid(
          children: [
            _kpi('Total Referrals', records.length, Icons.swap_horiz_rounded),
            _kpi(
              'Awaiting Assignment',
              count((r) => r.isPending),
              Icons.rate_review_outlined,
            ),
            _kpi(
              'Approved',
              count((r) => r.status == 'approved'),
              Icons.verified_outlined,
            ),
            _kpi(
              'Returned',
              count((r) => r.status == 'returned'),
              Icons.undo_rounded,
            ),
            _kpi(
              'Rejected',
              count((r) => r.status == 'rejected'),
              Icons.block_outlined,
            ),
            _kpi(
              'Waiting Consultation',
              count((r) => r.status == 'waiting_consultation'),
              Icons.event_outlined,
            ),
            _kpi(
              'Completed',
              count((r) => r.status == 'completed'),
              Icons.task_alt_rounded,
            ),
            _kpi(
              'Urgent Referrals',
              count((r) => r.isUrgent),
              Icons.emergency_outlined,
              color: Colors.redAccent,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _chartGrid([
          _ChartPanel(
            title: 'Referral Trend',
            subtitle: 'Monthly referral submissions',
            child: _ReferralLineChart(values: months),
          ),
          _ChartPanel(
            title: 'Referral by Barangay',
            subtitle: 'Top submitting barangays',
            child: _ReferralBarChart(values: _top(barangays, 7)),
          ),
          _ChartPanel(
            title: 'Referral Priority',
            subtitle: 'Routine to urgent workload',
            child: _ReferralBarChart(values: priorities),
          ),
          _ChartPanel(
            title: 'Referral Status Distribution',
            subtitle: 'Current operational stage',
            child: _ReferralBarChart(values: _top(statuses, 8)),
          ),
        ]),
      ],
    );
  }

  Widget _kpi(String label, int value, IconData icon, {Color? color}) {
    return ChoKpiCard(
      label: label,
      value: '$value',
      icon: icon,
      color: color ?? ChoColors.aqua,
    );
  }

  Widget _chartGrid(List<Widget> charts) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980 ? 2 : 1;
        final width = (constraints.maxWidth - 14 * (columns - 1)) / columns;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: charts
              .map((chart) => SizedBox(width: width, child: chart))
              .toList(),
        );
      },
    );
  }

  Widget _queue(
    List<_ReferralRecord> records, {
    required String title,
    required String emptyMessage,
    required _QueueMode mode,
  }) {
    if (records.isEmpty) {
      return ChoEmptyState(
        icon: Icons.inbox_outlined,
        title: title,
        message: emptyMessage,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: ChoColors.text,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${records.length} referral${records.length == 1 ? '' : 's'}',
          style: const TextStyle(color: ChoColors.muted),
        ),
        const SizedBox(height: 14),
        WebTableSurface(
          minWidth: 1120,
          child: Column(
            children: records
                .map(
                  (record) => _ReferralCard(
                    record: record,
                    mode: mode,
                    onDetails: () => _details(record),
                    onReassign: _isChoAdmin &&
                        (record.isPending || record.isActive)
                        ? () => _reassign(record)
                        : null,
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }

  Future<void> _reassign(_ReferralRecord record) async {
    final doctors = await _doctorOptions();
    if (!mounted) return;
    if (doctors.isEmpty) {
      _snack(
        'No approved and available doctors are eligible for reassignment.',
      );
      return;
    }
    var selectedUid = doctors.any((doctor) => doctor.id == record.doctorUid)
        ? record.doctorUid
        : doctors.first.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: ChoColors.surface,
          title: const Text(
            'Reassign referral',
            style: TextStyle(color: ChoColors.text),
          ),
          content: _lightDropdown(
            label: 'Approved available doctor',
            value: selectedUid,
            values: {for (final doctor in doctors) doctor.id: doctor.label},
            onChanged: (value) => setState(() => selectedUid = value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Reassign'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _accountPolicyService.assignDoctorToReferral(
        referralId: record.id,
        preferredDoctorUid: selectedUid,
      );
      if (mounted) {
        _snack(
          'Referral reassigned and the doctor notification was processed.',
        );
      }
    } catch (error) {
      if (mounted) _snack('Could not reassign referral: $error');
    }
  }

  Future<List<_Option>> _doctorOptions() async {
    try {
      final snapshot = await _firestore.collection('users').get();
      final values = snapshot.docs
          .where((doc) {
            final data = doc.data();
            final role = _s(data, ['role']).toLowerCase();
            final availability = _s(data, [
              'availability',
              'doctorAvailability',
              'status',
            ]).toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
            final accountStatus = _s(data, [
              'accountStatus',
            ], fallback: 'active').toLowerCase().replaceAll('-', '_');
            final approvalStatus = _s(data, [
              'approvalStatus',
            ], fallback: 'pending').toLowerCase();
            final unavailable =
                availability.contains('unavailable') ||
                availability.contains('on_leave') ||
                availability == 'leave' ||
                const {
                  'disabled',
                  'archived',
                  'inactive',
                  'deactivated',
                }.contains(accountStatus);
            return role == 'doctor' &&
                approvalStatus == 'approved' &&
                accountStatus == 'active' &&
                !unavailable;
          })
          .map((doc) {
            final data = doc.data();
            final name = _s(data, [
              'fullName',
              'username',
              'displayName',
              'email',
            ], fallback: 'Doctor');
            final specialty = _s(data, [
              'specialization',
            ], fallback: 'General Medicine');
            return _Option(doc.id, name, '$name — $specialty');
          })
          .toList();
      if (values.isNotEmpty) return values;
    } catch (_) {}
    return const <_Option>[];
  }

  void _details(_ReferralRecord record) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ChoColors.surface,
        title: Text(
          record.patientName,
          style: const TextStyle(color: ChoColors.text),
        ),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: _ReferralDetails(record: record, expanded: true),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _showPatientHistory(record);
            },
            icon: const Icon(Icons.history),
            label: const Text('Patient history'),
            style: OutlinedButton.styleFrom(
              foregroundColor: ChoColors.aqua,
              side: const BorderSide(color: ChoColors.aqua, width: 1.4),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPatientHistory(_ReferralRecord record) async {
    final patientId = _s(record.data, [
      'patientId',
      'linkedPatientId',
      'patientRecordId',
    ]);
    final patient = <String, dynamic>{
      ...record.data,
      ...record.patientInformation,
      'id': patientId.isEmpty ? record.id : patientId,
      'patientId': patientId.isEmpty ? record.id : patientId,
      'patientName': record.patientName,
      'fullName': record.patientName,
      'barangay': record.barangay,
      'barangayCode': record.barangayCode,
    };

    try {
      final snapshot = await _patientHistoryService.loadPatientHistory(patient);
      if (!mounted) return;
      await PatientHistoryDialogs.showPatientTimelineDialog(
        context: context,
        patient: patient,
        snapshot: snapshot,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load patient history: $error')),
      );
    }
  }

  InputDecoration _lightDecoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF7FAFC),
    hintStyle: const TextStyle(color: Color(0xFF6B7D84)),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  );

  Widget _lightDropdown({
    required String label,
    required String value,
    required Map<String, String> values,
    required ValueChanged<String> onChanged,
  }) {
    final safeValue = values.containsKey(value) ? value : values.keys.first;
    return WebFilterDropdown<String>(
      label: label,
      value: safeValue,
      width: double.infinity,
      items: values.entries
          .map(
            (entry) => DropdownMenuItem<String>(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(growable: false),
      onChanged: (item) {
        if (item != null) onChanged(item);
      },
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _exportReport(List<_ReferralRecord> records) {
    String escape(String value) => '"${value.replaceAll('"', '""')}"';
    final rows = <List<String>>[
      const [
        'Referral ID',
        'Patient',
        'Barangay',
        'Reason',
        'Priority',
        'Status',
        'Hospital',
        'Doctor',
        'Consultation Date',
        'Outcome',
      ],
      ...records.map(
        (record) => [
          record.id,
          record.patientName,
          record.barangay,
          record.reason,
          record.priorityLabel,
          record.statusLabel,
          record.hospital,
          record.doctor,
          record.consultationDate == null
              ? ''
              : _date(record.consultationDate!),
          record.outcome,
        ],
      ),
    ];
    final csv = rows.map((row) => row.map(escape).join(',')).join('\r\n');
    final downloaded = downloadCsvFile(
      bytes: utf8.encode(csv),
      filename: 'cho_referrals_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    _snack(
      downloaded
          ? 'Referral report downloaded.'
          : 'Report download is unavailable on this platform.',
    );
  }
}

enum _QueueMode { pending, active, completed }

class _ReferralCard extends StatelessWidget {
  const _ReferralCard({
    required this.record,
    required this.mode,
    required this.onDetails,
    this.onReassign,
  });
  final _ReferralRecord record;
  final _QueueMode mode;
  final VoidCallback onDetails;
  final VoidCallback? onReassign;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ChoColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: record.isUrgent
              ? Colors.redAccent.withValues(alpha: 0.5)
              : ChoColors.aqua.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                record.patientName,
                style: const TextStyle(
                  color: ChoColors.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              ChoStatusBadge(record.statusLabel),
              ChoStatusBadge(record.priorityLabel),
              Text(
                record.barangay,
                style: const TextStyle(color: ChoColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ReferralDetails(
            record: record,
            expanded: mode == _QueueMode.pending,
            mode: mode,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onDetails,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('View details'),
              ),
              if (onReassign != null)
                OutlinedButton.icon(
                  onPressed: onReassign,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Reassign doctor'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReferralDetails extends StatelessWidget {
  const _ReferralDetails({
    required this.record,
    required this.expanded,
    this.mode,
  });
  final _ReferralRecord record;
  final bool expanded;
  final _QueueMode? mode;

  @override
  Widget build(BuildContext context) {
    final allItems = <MapEntry<String, String>>[
      MapEntry('Patient ID', record.patientId),
      MapEntry('Patient', record.patientName),
      MapEntry('Date of Birth', record.patientDateOfBirth),
      MapEntry('Sex', record.patientSex),
      MapEntry('Contact Number', record.patientContactNumber),
      MapEntry('Barangay', record.barangay),
      MapEntry('Address', record.patientAddress),
      MapEntry('Referral Reason', record.reason),
      MapEntry('Symptoms', record.symptoms),
      MapEntry('Latest Check-up', record.latestCheckup),
      MapEntry('Vital Signs', record.vitals),
      MapEntry('Prenatal Information', record.prenatal),
      MapEntry('BHW Notes', record.bhwNotes),
      MapEntry('Attachments', record.attachments),
      MapEntry('Submitted decision-support category', record.aiPrediction),
      if (record.hospital.isNotEmpty)
        MapEntry('Assigned Hospital', record.hospital),
      if (record.doctor.isNotEmpty) MapEntry('Assigned Doctor', record.doctor),
      if (record.consultationDate != null)
        MapEntry('Consultation Date', _date(record.consultationDate!)),
      if (record.progress.isNotEmpty)
        MapEntry('Referral Progress', record.progress),
      if (record.doctorRecommendation.isNotEmpty)
        MapEntry('Doctor Recommendation', record.doctorRecommendation),
      if (record.consultationResult.isNotEmpty)
        MapEntry('Consultation Result', record.consultationResult),
      if (record.outcome.isNotEmpty) MapEntry('Outcome', record.outcome),
      if (record.followUp.isNotEmpty)
        MapEntry('Follow-up Required', record.followUp),
    ];
    final activeItems = <MapEntry<String, String>>[
      MapEntry(
        'Assigned Hospital',
        record.hospital.isEmpty ? 'Pending assignment' : record.hospital,
      ),
      MapEntry(
        'Assigned Doctor',
        record.doctor.isEmpty ? 'Pending assignment' : record.doctor,
      ),
      MapEntry('Current Status', record.statusLabel),
      MapEntry(
        'Consultation Date',
        record.consultationDate == null
            ? 'Not scheduled'
            : _date(record.consultationDate!),
      ),
      MapEntry('Referral Progress', record.progress),
      MapEntry(
        'Doctor Recommendation',
        record.doctorRecommendation.isEmpty
            ? 'Awaiting doctor update'
            : record.doctorRecommendation,
      ),
    ];
    final completedItems = <MapEntry<String, String>>[
      MapEntry(
        'Consultation Result',
        record.consultationResult.isEmpty
            ? 'Not recorded'
            : record.consultationResult,
      ),
      MapEntry(
        'Doctor Recommendation',
        record.doctorRecommendation.isEmpty
            ? 'Not recorded'
            : record.doctorRecommendation,
      ),
      MapEntry(
        'Outcome',
        record.outcome.isEmpty ? record.statusLabel : record.outcome,
      ),
      MapEntry(
        'Follow-up Required',
        record.followUp.isEmpty ? 'Not specified' : record.followUp,
      ),
    ];
    final visible = expanded
        ? allItems
        : mode == _QueueMode.active
        ? activeItems
        : mode == _QueueMode.completed
        ? completedItems
        : allItems.take(9);
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth >= 720
            ? (constraints.maxWidth - 14) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 14,
          runSpacing: 12,
          children: visible
              .map(
                (item) => SizedBox(
                  width: itemWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.key,
                        style: const TextStyle(
                          color: ChoColors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.value,
                        maxLines: expanded ? 5 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ChoColors.text,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _ChartPanel extends StatelessWidget {
  const _ChartPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    height: 300,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: ChoColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: ChoColors.aqua.withValues(alpha: 0.16)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: ChoColors.text,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(color: ChoColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 18),
        Expanded(child: child),
      ],
    ),
  );
}

class _ReferralLineChart extends StatelessWidget {
  const _ReferralLineChart({required this.values});
  final Map<String, int> values;
  @override
  Widget build(BuildContext context) {
    if (values.values.every((value) => value == 0)) {
      return const Center(
        child: Text(
          'No trend data yet',
          style: TextStyle(color: ChoColors.muted),
        ),
      );
    }
    final entries = values.entries.toList();
    return LineChart(
      LineChartData(
        minY: 0,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                return index >= 0 && index < entries.length
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          entries[index].key,
                          style: const TextStyle(
                            color: ChoColors.muted,
                            fontSize: 10,
                          ),
                        ),
                      )
                    : const SizedBox.shrink();
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              entries.length,
              (index) =>
                  FlSpot(index.toDouble(), entries[index].value.toDouble()),
            ),
            color: ChoColors.aqua,
            barWidth: 3,
            isCurved: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: ChoColors.aqua.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferralBarChart extends StatelessWidget {
  const _ReferralBarChart({required this.values});
  final Map<String, int> values;
  @override
  Widget build(BuildContext context) {
    final entries = values.entries.toList();
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          'No distribution data yet',
          style: TextStyle(color: ChoColors.muted),
        ),
      );
    }
    final maxValue = entries
        .map((entry) => entry.value)
        .fold<int>(1, (a, b) => a > b ? a : b);
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Row(
          children: [
            SizedBox(
              width: 112,
              child: Text(
                entry.key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: ChoColors.muted, fontSize: 11),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: entry.value / maxValue,
                  minHeight: 14,
                  color: ChoColors.aqua,
                  backgroundColor: ChoColors.border,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 28,
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
        );
      },
    );
  }
}

class _ReferralRecord {
  _ReferralRecord(this.document) : data = document.data();
  final QueryDocumentSnapshot<Map<String, dynamic>> document;
  final Map<String, dynamic> data;
  String get id => document.id;
  DocumentReference<Map<String, dynamic>> get reference => document.reference;
  String get status =>
      _normalizeStatus(_s(data, ['status'], fallback: 'submitted'));
  String get statusLabel => _title(status);
  String get priority => _s(data, [
    'priority',
    'referralPriority',
  ], fallback: 'routine').toLowerCase();
  String get priorityLabel => _title(priority);
  bool get isUrgent => priority.contains('urgent') || _bool(data['urgent']);
  bool get isPending => const {
    'submitted',
    'awaiting_doctor_assignment',
    'pending_review',
    'under_review',
    'additional_information_requested',
  }.contains(status);
  bool get isActive => const {
    'approved',
    'hospital_assigned',
    'doctor_assigned',
    'assigned',
    'waiting_consultation',
    'consulted',
    'doctor_reviewing',
    'in_treatment',
  }.contains(status);
  bool get isClosed =>
      const {'completed', 'returned', 'rejected'}.contains(status);
  Map<String, dynamic> get patientInformation {
    final value = data['patientInformation'];
    return value is Map ? Map<String, dynamic>.from(value) : const {};
  }

  String get patientName => _s(
    data,
    ['patientName', 'fullName'],
    fallback: _s(patientInformation, [
      'patientName',
      'fullName',
      'name',
      'patientRecordId',
    ], fallback: 'Unnamed patient'),
  );

  String get patientId => _s(data, [
    'patientId',
    'linkedPatientId',
    'patientRecordId',
  ], fallback: id);
  String get patientDateOfBirth => _s(
    patientInformation,
    ['dateOfBirth', 'dob', 'patientDateOfBirth'],
    fallback: _s(data, [
      'dateOfBirth',
      'dob',
      'patientDateOfBirth',
    ], fallback: 'Not provided'),
  );
  String get patientSex => _s(
    patientInformation,
    ['sex', 'gender', 'patientSex'],
    fallback: _s(data, [
      'sex',
      'gender',
      'patientSex',
    ], fallback: 'Not provided'),
  );
  String get patientContactNumber => _s(
    patientInformation,
    ['contactNumber', 'phoneNumber', 'phone', 'patientContactNumber'],
    fallback: _s(data, [
      'contactNumber',
      'phoneNumber',
      'phone',
      'patientContactNumber',
    ], fallback: 'Not provided'),
  );
  String get patientAddress => _s(
    patientInformation,
    ['address', 'street', 'fullAddress', 'patientAddress'],
    fallback: _s(data, [
      'address',
      'street',
      'fullAddress',
      'patientAddress',
    ], fallback: 'Not provided'),
  );
  String get barangay =>
      _s(data, ['barangay', 'barangayName'], fallback: 'Unassigned barangay');
  String get barangayCode => _s(data, ['barangayCode', 'assignedBarangayCode']);
  String get reason =>
      _s(data, ['referralReason', 'reason'], fallback: 'Not provided');
  String get symptoms =>
      _s(data, ['symptoms', 'chiefComplaint'], fallback: 'Not provided');
  String get latestCheckup => _s(data, [
    'latestCheckup',
    'checkupSummary',
    'lastCheckupDate',
  ], fallback: 'Not linked');
  String get vitals => summarizeVitalSigns(
    data,
    fallbackRecord: data['latestCheckup'] is Map
        ? Map<String, dynamic>.from(data['latestCheckup'] as Map)
        : null,
    fallback: 'Not provided',
  );
  String get prenatal => _s(data, [
    'prenatalInformation',
    'prenatalSummary',
  ], fallback: 'Not applicable / not linked');
  String get bhwNotes => _s(data, [
    'bhwNotes',
    'notes',
    'createdByNotes',
  ], fallback: 'No BHW notes');
  String get attachments =>
      _listText(data['attachments'], fallback: 'No attachments');
  String get aiPrediction => _s(data, [
    'aiPrediction',
    'predictedDisease',
    'prediction',
  ], fallback: 'No AI guidance attached');
  String get hospital =>
      _s(data, ['assignedHospital', 'receivingHospital', 'referredTo']);
  String get doctor => _s(data, ['assignedDoctorName', 'receivingDoctor']);
  String get doctorUid => _s(data, ['assignedDoctorUid']);
  DateTime? get consultationDate =>
      _asDate(data['expectedConsultationDate'] ?? data['consultationDate']);
  String get reviewNotes => _s(data, ['choReviewNotes']);
  String get progress =>
      _s(data, ['referralProgress', 'progress'], fallback: statusLabel);
  String get doctorRecommendation =>
      _s(data, ['doctorRecommendation', 'doctorNotes']);
  String get consultationResult =>
      _s(data, ['consultationResult', 'doctorConsultationResult']);
  String get outcome => _s(data, ['outcome', 'referralOutcome']);
  String get followUp => _s(data, ['followUpRequired', 'followUp']);
  String get createdByUid => _s(data, ['createdByUid', 'bhwUid']);
  DateTime get updatedAt =>
      _asDate(data['updatedAt'] ?? data['createdAt']) ??
      DateTime.fromMillisecondsSinceEpoch(0);
  DateTime get createdAt =>
      _asDate(
        data['createdAt'] ?? data['referralDateTime'] ?? data['updatedAt'],
      ) ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

class _Option {
  const _Option(this.id, this.name, this.label);
  final String id;
  final String name;
  final String label;
}

Map<String, int> _counts(
  List<_ReferralRecord> records,
  String Function(_ReferralRecord) key,
) {
  final result = <String, int>{};
  for (final record in records) {
    final label = key(record);
    result[label] = (result[label] ?? 0) + 1;
  }
  return result;
}

Map<String, int> _top(Map<String, int> values, int limit) {
  final entries = values.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return {for (final entry in entries.take(limit)) entry.key: entry.value};
}

Map<String, int> _monthlyCounts(List<_ReferralRecord> records) {
  final now = DateTime.now();
  final result = <String, int>{};
  for (var offset = 5; offset >= 0; offset--) {
    final date = DateTime(now.year, now.month - offset);
    result[_month(date.month)] = 0;
  }
  for (final record in records) {
    final key = _month(record.createdAt.month);
    if (record.createdAt.year >= now.year - 1 && result.containsKey(key)) {
      result[key] = result[key]! + 1;
    }
  }
  return result;
}

String _s(
  Map<String, dynamic> data,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = data[key];
    if (value == null) continue;
    if (value is Iterable) {
      final text = value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .join(', ');
      if (text.isNotEmpty) return text;
    } else if (value is Map) {
      final text = value.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join(', ');
      if (text.isNotEmpty) return text;
    } else if (value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return fallback;
}

String _listText(dynamic value, {required String fallback}) {
  if (value is Iterable) {
    final result = value
        .map(
          (item) => item is Map
              ? _s(Map<String, dynamic>.from(item), [
                  'name',
                  'fileName',
                  'url',
                ], fallback: 'Attachment')
              : item.toString(),
        )
        .join(', ');
    return result.isEmpty ? fallback : result;
  }
  return value?.toString().trim().isNotEmpty == true
      ? value.toString()
      : fallback;
}

bool _bool(dynamic value) =>
    value == true || value?.toString().toLowerCase() == 'true';

DateTime? _asDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}

String _normalizeStatus(String status) {
  final value = status.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
  return switch (value) {
    'pending' || 'submitted' || 'new' => 'submitted',
    'under_review' => 'pending_review',
    'return_for_correction' => 'returned',
    'waiting' => 'waiting_consultation',
    'in_treatment' => 'consulted',
    _ => value,
  };
}

String _title(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _month(int value) => const [
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
][value - 1];
