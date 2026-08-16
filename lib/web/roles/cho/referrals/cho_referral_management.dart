import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_firestore_paths.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_navigation.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_components.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_config.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/shared/components/app_buttons.dart';
import 'package:mycapstone_project/web/shared/components/web_data_components.dart';
import 'package:mycapstone_project/web/shared/utils/csv_download.dart';

/// CHO referral review/approval workspace — reached from the sidebar
/// "Referrals" destination (`cho_navigation.dart`). Owns the referral
/// state machine (`_ReferralRecord`, statuses: pending_review /
/// hospital_assigned / doctor_assigned / waiting_consultation / consulted
/// / completed), which matches what `firestore.rules`' `canUpdateReferral`
/// checks (see `pending_review` / `returned_for_correction` there) — this
/// is the authoritative referral status vocabulary.
///
/// `lib/web/roles/cho/referrals/referral.dart` defines a *different*
/// class, `CHOReferralWorkspacePage` (reached from CHO dashboard quick
/// actions), which uses its own incompatible status vocabulary and adds
/// doctor-registry management, filters, and PDF printing this page
/// doesn't have. See that file's doc comment for the full explanation —
/// this is a known, documented divergence, not an oversight.
class CHOPreferralPage extends StatefulWidget {
  const CHOPreferralPage({super.key});

  @override
  State<CHOPreferralPage> createState() => _CHOPreferralPageState();
}

class _CHOPreferralPageState extends State<CHOPreferralPage> {
  final FirebaseFirestore _firestore = getFirestoreInstance();
  final PatientCenteredHistoryService _patientHistoryService =
      PatientCenteredHistoryService();
  int _view = 0;
  bool _loadingScope = true;
  String? _accessError;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream;

  static const _tabs = <String>[
    'Insights',
    'Pending Review',
    'Active Referrals',
    'Completed Referrals',
  ];

  @override
  void initState() {
    super.initState();
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
        _loadingScope = false;
      });
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
      drawer: const ChoNavigationDrawer(current: ChoDestination.referrals),
      appBar: AppBar(
        backgroundColor: ChoColors.navBackground,
        foregroundColor: ChoColors.navText,
        title: const Text('CHO Referral Management'),
        actions: [
          IconButton(
            onPressed: _loadScope,
            tooltip: 'Refresh referrals',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loadingScope
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
                if (!snapshot.hasData) return const ChoLoadingSkeleton();
                final records =
                    snapshot.data!.docs.map(_ReferralRecord.new).toList()
                      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                return _content(records);
              },
            ),
    );
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
                'Validate BHW referrals, coordinate receiving facilities and doctors, and monitor referral progress. CHO review does not diagnose or prescribe.',
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
          switch (_view) {
            0 => _insights(records),
            1 => _queue(
              pending,
              title: 'Pending Review Queue',
              emptyMessage: 'No referrals currently require CHO review.',
              mode: _QueueMode.pending,
            ),
            2 => _queue(
              active,
              title: 'Active Referrals',
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
              'Pending Review',
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
                    onReview: () => _review(record),
                    onAdvance: () => _advance(record),
                    onDetails: () => _details(record),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }

  Future<void> _review(_ReferralRecord record) async {
    final notes = TextEditingController(text: record.reviewNotes);
    String priority = record.priority;
    String hospital = record.hospital;
    String doctor = record.doctor;
    String doctorUid = record.doctorUid;
    DateTime? consultationDate = record.consultationDate;
    var action = 'approved';
    final doctors = await _doctorOptions();
    final hospitals = await _hospitalOptions();
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: ChoColors.surface,
          title: const Text(
            'CHO Referral Review',
            style: TextStyle(color: ChoColors.text),
          ),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _permissionNotice(),
                  const SizedBox(height: 16),
                  _lightDropdown(
                    label: 'Review action',
                    value: action,
                    values: const {
                      'approved': 'Approve',
                      'returned': 'Return for Correction',
                      'rejected': 'Reject',
                      'additional_information_requested':
                          'Request Additional Information',
                    },
                    onChanged: (value) => setDialogState(() => action = value),
                  ),
                  const SizedBox(height: 12),
                  _lightDropdown(
                    label: 'Referral priority',
                    value: priority,
                    values: const {
                      'routine': 'Routine',
                      'priority': 'Priority',
                      'urgent': 'Urgent',
                    },
                    onChanged: (value) =>
                        setDialogState(() => priority = value),
                  ),
                  if (action == 'approved') ...[
                    const SizedBox(height: 12),
                    _lightDropdown(
                      label: 'Receiving hospital',
                      value: hospitals.contains(hospital)
                          ? hospital
                          : hospitals.first,
                      values: {for (final value in hospitals) value: value},
                      onChanged: (value) =>
                          setDialogState(() => hospital = value),
                    ),
                    const SizedBox(height: 12),
                    _lightDropdown(
                      label: 'Available doctor',
                      value: doctors.any((item) => item.id == doctorUid)
                          ? doctorUid
                          : doctors.first.id,
                      values: {for (final item in doctors) item.id: item.label},
                      onChanged: (value) => setDialogState(() {
                        doctorUid = value;
                        doctor = doctors
                            .firstWhere((item) => item.id == value)
                            .name;
                      }),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              consultationDate ??
                              DateTime.now().add(const Duration(days: 1)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) {
                          setDialogState(() => consultationDate = picked);
                        }
                      },
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        consultationDate == null
                            ? 'Set expected consultation date'
                            : _date(consultationDate!),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    minLines: 3,
                    maxLines: 5,
                    style: const TextStyle(color: Color(0xFF12252B)),
                    decoration: _lightDecoration('CHO review notes'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (notes.text.trim().isEmpty) {
                  _snack('Review notes are required.');
                  return;
                }
                if (action == 'approved' && consultationDate == null) {
                  _snack('Set the expected consultation date before approval.');
                  return;
                }
                await _saveReview(
                  record,
                  action: action,
                  priority: priority,
                  hospital: hospital.isEmpty ? hospitals.first : hospital,
                  doctor: doctor.isEmpty ? doctors.first.name : doctor,
                  doctorUid: doctorUid.isEmpty ? doctors.first.id : doctorUid,
                  consultationDate: consultationDate,
                  notes: notes.text.trim(),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              },
              style: AppButtonStyles.primary(),
              child: const Text('Save review'),
            ),
          ],
        ),
      ),
    );
    notes.dispose();
    if (saved == true && mounted) {
      _snack('Referral review saved and notification generated.');
    }
  }

  Future<void> _saveReview(
    _ReferralRecord record, {
    required String action,
    required String priority,
    required String hospital,
    required String doctor,
    required String doctorUid,
    required DateTime? consultationDate,
    required String notes,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final payload = <String, dynamic>{
      'status': action,
      'priority': priority,
      'choReviewNotes': notes,
      'reviewedByUid': user?.uid,
      'reviewedByEmail': user?.email,
      'reviewedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (action == 'approved') ...{
        'assignedHospital': hospital,
        'receivingHospital': hospital,
        'assignedDoctorName': doctor,
        'assignedDoctorUid': doctorUid,
        'expectedConsultationDate': Timestamp.fromDate(consultationDate!),
        'approvedAt': FieldValue.serverTimestamp(),
      },
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': action,
          'at': Timestamp.now(),
          'by': user?.uid,
          'notes': notes,
        },
      ]),
    };
    await record.reference.set(payload, SetOptions(merge: true));
    await _syncMirror(record, {...record.data, ...payload});
    await _firestore.collection('notifications').add({
      'type': 'referral_review',
      'referralId': record.id,
      'recipientUid': record.createdByUid,
      'title': 'Referral ${_title(action)}',
      'message': notes,
      'status': 'unread',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _advance(_ReferralRecord record) async {
    const next = {
      'approved': 'hospital_assigned',
      'hospital_assigned': 'doctor_assigned',
      'doctor_assigned': 'waiting_consultation',
      'assigned': 'waiting_consultation',
      'waiting_consultation': 'consulted',
      'consulted': 'completed',
    };
    final nextStatus = next[record.status];
    if (nextStatus == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ChoColors.surface,
        title: const Text(
          'Update referral progress',
          style: TextStyle(color: ChoColors.text),
        ),
        content: Text(
          'Move ${record.patientName} from ${record.statusLabel} to ${_title(nextStatus)}? This updates coordination status only.',
          style: const TextStyle(color: ChoColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: AppButtonStyles.primary(),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final payload = {
      'status': nextStatus,
      'updatedAt': FieldValue.serverTimestamp(),
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': nextStatus,
          'at': Timestamp.now(),
          'by': FirebaseAuth.instance.currentUser?.uid,
        },
      ]),
    };
    await record.reference.set(payload, SetOptions(merge: true));
    await _syncMirror(record, {...record.data, ...payload});
    if (mounted) _snack('Referral moved to ${_title(nextStatus)}.');
  }

  Future<void> _syncMirror(
    _ReferralRecord record,
    Map<String, dynamic> payload,
  ) async {
    final code = record.barangayCode.trim().toUpperCase();
    if (code.isEmpty) return;
    await _firestore
        .collection(BarangayFirestorePaths.barangaysCollection)
        .doc(code)
        .collection('referrals')
        .doc(record.id)
        .set({
          ...payload,
          'rootReferralPath': 'referrals/${record.id}',
        }, SetOptions(merge: true));
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
              'status',
            ]).toLowerCase();
            return role == 'doctor' && !availability.contains('unavailable');
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
    return const [_Option('unassigned', 'To be assigned', 'To be assigned')];
  }

  Future<List<String>> _hospitalOptions() async {
    try {
      final snapshot = await _firestore.collection('hospitals').get();
      final values =
          snapshot.docs
              .map(
                (doc) =>
                    _s(doc.data(), ['name', 'hospitalName', 'facilityName']),
              )
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      if (values.isNotEmpty) return values;
    } catch (_) {}
    return const ['City Health Office / Receiving Facility'];
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

  Widget _permissionNotice() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: ChoColors.aqua.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: ChoColors.aqua.withValues(alpha: 0.25)),
    ),
    child: const Row(
      children: [
        Icon(Icons.shield_outlined, color: ChoColors.aqua),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Coordination review only. CHO cannot diagnose, prescribe, or finalize medical treatment.',
            style: TextStyle(color: ChoColors.text),
          ),
        ),
      ],
    ),
  );

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
    required this.onReview,
    required this.onAdvance,
    required this.onDetails,
  });
  final _ReferralRecord record;
  final _QueueMode mode;
  final VoidCallback onReview;
  final VoidCallback onAdvance;
  final VoidCallback onDetails;

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
              if (mode == _QueueMode.pending)
                FilledButton.icon(
                  onPressed: onReview,
                  icon: const Icon(Icons.rate_review_outlined),
                  label: const Text('Review referral'),
                ),
              if (mode == _QueueMode.active)
                FilledButton.icon(
                  onPressed: onAdvance,
                  icon: const Icon(Icons.trending_flat_rounded),
                  label: const Text('Update progress'),
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
      MapEntry('Referral Reason', record.reason),
      MapEntry('Symptoms', record.symptoms),
      MapEntry('Latest Check-up', record.latestCheckup),
      MapEntry('Vital Signs', record.vitals),
      MapEntry('Prenatal Information', record.prenatal),
      MapEntry('BHW Notes', record.bhwNotes),
      MapEntry('Attachments', record.attachments),
      MapEntry('AI Prediction', record.aiPrediction),
      MapEntry('Prediction Confidence', record.confidence),
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
      _normalizeStatus(_s(data, ['status'], fallback: 'pending_review'));
  String get statusLabel => _title(status);
  String get priority => _s(data, [
    'priority',
    'referralPriority',
  ], fallback: 'routine').toLowerCase();
  String get priorityLabel => _title(priority);
  bool get isUrgent => priority.contains('urgent') || _bool(data['urgent']);
  bool get isPending => const {
    'pending_review',
    'under_review',
    'submitted',
    'additional_information_requested',
  }.contains(status);
  bool get isActive => const {
    'approved',
    'hospital_assigned',
    'doctor_assigned',
    'assigned',
    'waiting_consultation',
    'consulted',
  }.contains(status);
  bool get isClosed =>
      const {'completed', 'returned', 'rejected'}.contains(status);
  String get patientName => _s(data, [
    'patientName',
    'fullName',
    'patientRecordId',
  ], fallback: 'Unnamed patient');
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
  String get vitals => _s(data, [
    'completeVitalSigns',
    'vitalSigns',
    'vitals',
  ], fallback: 'Not provided');
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
  String get confidence =>
      _confidence(data['predictionConfidence'] ?? data['confidence']);
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

String _confidence(dynamic value) {
  if (value == null) return 'Not available';
  if (value is num) {
    return value <= 1
        ? '${(value * 100).toStringAsFixed(1)}%'
        : '${value.toStringAsFixed(1)}%';
  }
  return value.toString();
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
    'pending' || 'submitted' || 'new' => 'pending_review',
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
