import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/shared/widgets/spring_data_motion.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_firestore_paths.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_first_service_selector.dart';
import 'package:mycapstone_project/web/shared/components/app_buttons.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/shared/components/web_responsive_body.dart';
import 'package:mycapstone_project/web/shared/components/web_data_components.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';
import 'package:mycapstone_project/web/shared/utils/web_file_picker.dart';
import 'package:mycapstone_project/web/shared/utils/referral_pdf.dart';
import 'package:mycapstone_project/web/shared/utils/report_download.dart';

const _aqua = AppColors.primary;
const _background = AppColors.backgroundLight;
const _surface = AppColors.surfaceLight;
const _surfaceAlt = AppColors.surfaceSubtle;
const _text = AppColors.textPrimary;
const _muted = AppColors.textSecondary;
const _lightField = Colors.white;
const _darkFieldText = AppColors.textPrimary;

class BhwReferralPage extends StatefulWidget {
  const BhwReferralPage({
    super.key,
    this.initialPatient,
    this.initialObservations,
    this.embedded = false,
    this.onClose,
  });

  final Map<String, dynamic>? initialPatient;

  /// Pre-fills the Observations field (e.g. vitals/symptoms carried over from
  /// the check-up that triggered this referral). Still fully editable.
  final String? initialObservations;

  /// When true, renders just the referral-creation transaction (no sidebar,
  /// no Dashboard/Records/Follow-up tabs) so it can be dropped into a dialog
  /// over the page that triggered it — e.g. Check-ups — instead of
  /// navigating to a separate route. Closes via [onClose] once the referral
  /// is submitted (or the BHW cancels), returning straight to that page
  /// with no back-navigation involved.
  final bool embedded;
  final VoidCallback? onClose;

  @override
  State<BhwReferralPage> createState() => _BhwReferralPageState();
}

class _BhwReferralPageState extends State<BhwReferralPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = getFirestoreInstance();
  final PatientCenteredHistoryService _historyService =
      PatientCenteredHistoryService();
  final _reasonController = TextEditingController();
  final _observationsController = TextEditingController();
  final _notesController = TextEditingController();
  final _destinationController = TextEditingController();
  final _patientFilterController = TextEditingController();

  UserAccessScope _scope = UserAccessScope.unauthenticated;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream;
  Map<String, dynamic>? _patient;
  PatientModuleHistorySnapshot? _history;
  List<Map<String, dynamic>> _attachments = [];
  String _priority = 'routine';
  String _statusFilter = 'all';
  String _priorityFilter = 'all';
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _draftReferralId;
  String? _editingReferralId;
  int _view = 0;
  bool _loading = true;
  bool _loadingPatient = false;
  bool _submitting = false;
  bool _uploading = false;
  String? _error;

  static const _views = [
    'Dashboard',
    'Create Referral',
    'Referral Records',
    'Follow-up',
  ];

  @override
  void initState() {
    super.initState();
    _loadScope();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _observationsController.dispose();
    _notesController.dispose();
    _destinationController.dispose();
    _patientFilterController.dispose();
    super.dispose();
  }

  Future<void> _loadScope() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final scope = await UserAccessScopeService.instance
          .loadCurrentScope(forceRefresh: true)
          .timeout(const Duration(seconds: 12));
      if (!scope.isAuthenticated || scope.role != 'bhw') {
        throw StateError('A verified BHW account is required.');
      }
      if (!mounted) return;
      setState(() {
        _scope = scope;
        _stream = _firestore
            .collection('referrals')
            .where('createdByUid', isEqualTo: scope.userId)
            .snapshots();
        _loading = false;
      });
      if (widget.initialPatient != null && _patient == null) {
        await _openPatient(widget.initialPatient!);
        if (!mounted) return;
        if (widget.initialObservations?.trim().isNotEmpty == true) {
          _observationsController.text = widget.initialObservations!.trim();
        }
        setState(() => _view = 1);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _embeddedBody();

    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : user?.email?.split('@').first ?? 'BHW';
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _background,
      body: WebResponsiveBody(
        sidebar: WebAppSidebar(
          userName: userName,
          activeItem: WebSidebarItem.referrals,
        ),
        title: 'Referral Management',
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _aqua))
            : _error != null
            ? _errorState()
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _stream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _errorState(message: snapshot.error.toString());
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: _aqua),
                    );
                  }
                  final records =
                      snapshot.data!.docs.map(_BhwReferralRecord.new).toList()
                        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                  return _workspace(records);
                },
              ),
      ),
    );
  }

  /// Full-screen dialog body used when this page is opened as a same-page
  /// overlay (see [BhwReferralPage.embedded]) instead of a route. One
  /// transaction — create this referral, then close — with no tabs, no
  /// sidebar, and no navigation stack entry to back out of.
  Widget _embeddedBody() {
    final screenSize = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Container(
        width: screenSize.width,
        height: screenSize.height,
        color: _background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
              decoration: const BoxDecoration(
                color: AppColors.secondary,
                border: Border(
                  bottom: BorderSide(color: Color(0x20FFFFFF), width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Refer to CHO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Submitting keeps you on Check-ups — this closes automatically when done.',
                          style: TextStyle(
                            color: AppColors.textOnDarkMuted,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _aqua))
                  : _error != null
                  ? _errorState()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 38),
                      child: _createReferral(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState({String? message}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: AppColors.textSecondary,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            message ?? _error ?? 'Referral data could not be loaded.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _text),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _loadScope,
            style: AppButtonStyles.primary(),
            child: const Text('Retry'),
          ),
        ],
      ),
    ),
  );

  Widget _workspace(List<_BhwReferralRecord> records) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: 18),
          _tabs(),
          const SizedBox(height: 18),
          switch (_view) {
            0 => _dashboard(records),
            1 => _createReferral(),
            2 => _records(records),
            _ => _followUps(records),
          },
        ],
      ),
    );
  }

  Widget _header() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: AppColors.secondary,
      borderRadius: BorderRadius.circular(20),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'BHW SERVICES / REFERRAL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Referral Management',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 23 : 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Create patient-linked requests for CHO review and monitor higher-level care. BHWs cannot approve, assign providers, diagnose, or prescribe.',
                    style: TextStyle(color: Colors.white, height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _tabs() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: List.generate(_views.length, (index) {
          final selected = _view == index;
          final icons = [
            Icons.dashboard_outlined,
            Icons.add_circle_outline,
            Icons.list_alt_outlined,
            Icons.home_work_outlined,
          ];
          return TextButton.icon(
            onPressed: () => setState(() => _view = index),
            icon: Icon(icons[index], size: 18),
            label: Text(_views[index]),
            style: TextButton.styleFrom(
              foregroundColor: selected ? Colors.white : _muted,
              // Navigation selection follows the shared clinical-blue system
              // palette. The referral accent remains reserved for escalation
              // actions, not for routine page navigation.
              backgroundColor: selected ? _aqua : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }),
      ),
    ),
  );

  Widget _dashboard(List<_BhwReferralRecord> records) {
    int count(bool Function(_BhwReferralRecord) test) =>
        records.where(test).length;
    final recent = records.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kpiGrid([
          _kpi('Total Referrals', records.length, Icons.swap_horiz_rounded),
          _kpi(
            'Pending CHO Review',
            count((r) => r.isPending),
            Icons.rate_review_outlined,
          ),
          _kpi(
            'Approved Referrals',
            count((r) => r.isApproved),
            Icons.verified_outlined,
          ),
          _kpi(
            'Returned Referrals',
            count((r) => r.isReturned),
            Icons.undo_rounded,
          ),
          _kpi(
            'Completed Referrals',
            count((r) => r.isCompleted),
            Icons.task_alt_rounded,
          ),
          _kpi(
            'Follow-ups Required',
            count((r) => r.followUpRequired),
            Icons.home_work_outlined,
          ),
        ]),
        const SizedBox(height: 18),
        _panel(
          title: 'Recent Referrals',
          subtitle: 'Latest requests and CHO status updates',
          child: recent.isEmpty
              ? _empty(
                  'No referrals submitted yet',
                  'Create a referral after selecting a registered patient.',
                )
              : Column(
                  children: recent
                      .map((record) => _recentReferral(record))
                      .toList(),
                ),
        ),
      ],
    );
  }

  Widget _kpiGrid(List<Widget> cards) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1100
          ? 3
          : constraints.maxWidth >= 650
          ? 2
          : 1;
      final width = (constraints.maxWidth - 14 * (columns - 1)) / columns;
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: cards
            .map((card) => SizedBox(width: width, child: card))
            .toList(),
      );
    },
  );

  Widget _kpi(String label, int value, IconData icon, {Color color = _aqua}) =>
      Container(
        height: 142,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const Spacer(),
            Text(
              '$value',
              style: const TextStyle(
                color: _text,
                fontSize: 27,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );

  Widget _recentReferral(_BhwReferralRecord record) => Container(
    padding: const EdgeInsets.symmetric(vertical: 13),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: _aqua.withValues(alpha: 0.13),
          child: const Icon(Icons.person_outline, color: _aqua),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.patientName,
                style: const TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${record.reason} • ${_date(record.createdAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _statusBadge(record.statusLabel),
      ],
    ),
  );

  Widget _createReferral() {
    if (_patient == null) return _patientGate();
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_editingReferralId != null) _returnedNotice(),
          _patientProfile(),
          const SizedBox(height: 16),
          _clinicalSnapshot(),
          const SizedBox(height: 16),
          _panel(
            title: _editingReferralId == null
                ? 'Create Referral'
                : 'Correct Returned Referral',
            subtitle:
                'Provide observations and the reason higher-level healthcare services are needed.',
            child: Column(
              children: [
                _responsiveFields([
                  _field(
                    label: 'Referral Reason',
                    controller: _reasonController,
                    maxLines: 3,
                    required: true,
                  ),
                  _priorityField(),
                  _field(
                    label: 'Observations',
                    controller: _observationsController,
                    maxLines: 3,
                    required: true,
                  ),
                  _field(
                    label: 'Supporting Notes',
                    controller: _notesController,
                    maxLines: 3,
                    required: true,
                  ),
                  _field(
                    label: 'Destination Facility (Optional)',
                    controller: _destinationController,
                  ),
                ]),
                const SizedBox(height: 16),
                _attachmentPanel(),
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _clearDraft,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Clear Draft'),
                      style: AppButtonStyles.outline(),
                    ),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      style: AppButtonStyles.primary(),
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                      label: Text(
                        _submitting
                            ? 'Submitting...'
                            : _editingReferralId == null
                            ? 'Submit to CHO'
                            : 'Resubmit Correction',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _patientGate() => _panel(
    title: 'Search Existing Patient',
    subtitle: 'Every referral must start from the registered Patient module.',
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.person_search_rounded, color: _aqua, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Select a registered patient before creating a referral',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'If the patient does not exist, register the patient first.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _choosePatient,
              style: AppButtonStyles.primary(),
              icon: const Icon(Icons.search_rounded),
              label: const Text('Search and Select Patient'),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _choosePatient() async {
    final patient = await PatientFirstServiceSelector.selectRegisteredPatient(
      context,
      serviceLabel: 'Referral',
      patientService: _historyService,
      onRegisterPatient: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PatientRecordPage(openRegistrationOnLoad: true),
        ),
      ),
    );
    if (patient != null) await _openPatient(patient);
  }

  Future<void> _openPatient(Map<String, dynamic> patient) async {
    if (mounted) setState(() => _loadingPatient = true);
    try {
      final history = await _historyService.loadPatientHistory(patient);
      if (!mounted) return;
      setState(() {
        _patient = patient;
        _history = history;
        _loadingPatient = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _patient = patient;
        _history = null;
        _loadingPatient = false;
      });
      _snack(
        'Patient selected, but clinical history could not be loaded: $error',
      );
    }
  }

  Widget _patientProfile() => _panel(
    title: 'Patient Profile',
    subtitle: 'Registered patient information',
    trailing: TextButton.icon(
      onPressed: _choosePatient,
      icon: const Icon(Icons.swap_horiz_rounded),
      label: const Text('Change Patient'),
    ),
    child: _infoGrid([
      MapEntry('Patient ID', _patientText(['patientId', 'id'])),
      MapEntry('Patient', _patientName(_patient!)),
      MapEntry('Date of Birth', _patientText(['dateOfBirth', 'dob'])),
      MapEntry('Age', _patientText(['age'])),
      MapEntry('Sex', _patientText(['sex', 'gender'])),
      MapEntry(
        'Barangay',
        _patientText(['barangay'], fallback: _scope.barangay),
      ),
      MapEntry('Address', _patientText(['address', 'fullAddress'])),
      MapEntry('Contact', _patientText(['contactNumber', 'phone'])),
    ]),
  );

  Widget _clinicalSnapshot() {
    if (_loadingPatient) {
      return const Center(child: CircularProgressIndicator(color: _aqua));
    }
    final checkup = _latest(_history?.checkUpHistory);
    final prenatal = _latest(_history?.prenatalHistory);
    final morbidity = _latest(_history?.morbidityHistory);
    return _panel(
      title: 'Auto-loaded Clinical Context',
      subtitle: 'Read-only information from the patient’s existing records',
      child: _infoGrid([
        MapEntry(
          'Latest Check-up',
          _recordSummary(checkup, [
            'datetime',
            'date',
            'type',
            'details',
            'status',
          ]),
        ),
        MapEntry('Latest Vital Signs', _vitalSummary(checkup)),
        MapEntry(
          'Existing Prenatal Information',
          _recordSummary(prenatal, [
            'registrationDate',
            'gestationalAge',
            'riskLevel',
            'status',
          ]),
        ),
        MapEntry(
          'Existing Morbidity',
          _recordSummary(morbidity, [
            'reportedDate',
            'disease',
            'symptoms',
            'severity',
            'status',
          ]),
        ),
        MapEntry('Existing Home Care', _homeCare(checkup)),
      ]),
    );
  }

  Widget _returnedNotice() => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.orangeAccent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.4)),
    ),
    child: const Row(
      children: [
        Icon(Icons.edit_note_rounded, color: Colors.orangeAccent),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'This referral was returned by CHO. Only returned referrals can be corrected and resubmitted.',
            style: TextStyle(color: _text),
          ),
        ),
      ],
    ),
  );

  Widget _field({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
    bool required = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _fieldLabel(label),
      const SizedBox(height: 6),
      TextFormField(
        controller: controller,
        minLines: maxLines,
        maxLines: maxLines,
        style: const TextStyle(color: _darkFieldText),
        decoration: _inputDecoration('Enter $label'),
        validator: required
            ? (value) =>
                  value?.trim().isEmpty == true ? '$label is required.' : null
            : null,
      ),
    ],
  );

  Widget _priorityField() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _fieldLabel('Priority'),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        initialValue: _priority,
        isExpanded: true,
        dropdownColor: _lightField,
        style: const TextStyle(color: _darkFieldText),
        decoration: _inputDecoration('Select priority'),
        items: const [
          DropdownMenuItem(value: 'routine', child: Text('Routine')),
          DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
          DropdownMenuItem(value: 'emergency', child: Text('Emergency')),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _priority = value);
        },
      ),
    ],
  );

  Widget _attachmentPanel() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _background.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Attachments (Optional)',
                style: TextStyle(color: _text, fontWeight: FontWeight.w700),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pickAttachment,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.attach_file_rounded),
              label: Text(_uploading ? 'Uploading...' : 'Add File'),
            ),
          ],
        ),
        if (_attachments.isEmpty)
          const Text(
            'No files attached.',
            style: TextStyle(color: _muted, fontSize: 12),
          )
        else
          ..._attachments.asMap().entries.map(
            (entry) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined, color: _aqua),
              title: Text(
                _textOf(entry.value, ['name'], fallback: 'Attachment'),
                style: const TextStyle(color: _text),
              ),
              trailing: IconButton(
                tooltip: 'Remove attachment',
                onPressed: () =>
                    setState(() => _attachments.removeAt(entry.key)),
                icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
              ),
            ),
          ),
      ],
    ),
  );

  Future<void> _pickAttachment() async {
    final file = await pickWebFile(accept: '.pdf,.jpg,.jpeg,.png');
    if (file == null) return;
    if (file.size > 10 * 1024 * 1024) {
      _snack('Attachment must be 10 MB or smaller.');
      return;
    }
    setState(() => _uploading = true);
    try {
      final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final referralId =
          _editingReferralId ??
          (_draftReferralId ??= _firestore.collection('referrals').doc().id);
      final path =
          'referral_attachments/${_scope.userId}/$referralId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final reference = FirebaseStorage.instance.ref(path);
      await reference.putData(
        file.bytes,
        SettableMetadata(contentType: file.mimeType),
      );
      if (!mounted) return;
      setState(
        () => _attachments.add({
          'name': file.name,
          'storagePath': path,
          'contentType': file.mimeType,
          'size': file.size,
        }),
      );
    } catch (error) {
      _snack('Attachment upload failed: $error');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    if (_patient == null || !_formKey.currentState!.validate()) return;
    if (_uploading || _submitting) return;
    setState(() => _submitting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('Your session has expired.');
      final patientId = _patientText(['patientId', 'id']);
      final checkup = _latest(_history?.checkUpHistory);
      final prenatal = _latest(_history?.prenatalHistory);
      final morbidity = _latest(_history?.morbidityHistory);
      final payload = <String, dynamic>{
        'patientId': patientId,
        'patientRecordId': patientId,
        'linkedPatientId': patientId,
        'patientName': _patientName(_patient!),
        'patientInformation': Map<String, dynamic>.from(_patient!),
        'latestCheckup': checkup ?? <String, dynamic>{},
        'latestVitalSigns': _vitalSummary(checkup),
        'prenatalInformation': prenatal ?? <String, dynamic>{},
        'morbidityInformation': morbidity ?? <String, dynamic>{},
        'homeCare': _homeCare(checkup),
        'referralReason': _reasonController.text.trim(),
        'priority': _priority,
        'observations': _observationsController.text.trim(),
        'bhwNotes': _notesController.text.trim(),
        'supportingNotes': _notesController.text.trim(),
        'destinationFacility': _destinationController.text.trim(),
        'attachments': _attachments,
        'status': 'pending_review',
        'submissionStatus': 'submitted',
        'barangay': _scope.barangay,
        'barangayCode': _scope.barangayCode,
        'barangayDistrict': _scope.barangayDistrict,
        'createdByUid': user.uid,
        'createdByRole': 'bhw',
        'createdByEmail': user.email,
        'createdByName': user.displayName ?? user.email?.split('@').first,
        'updatedAt': FieldValue.serverTimestamp(),
        'submittedAt': FieldValue.serverTimestamp(),
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'pending_review',
            'at': Timestamp.now(),
            'by': user.uid,
            'role': 'bhw',
          },
        ]),
      };
      if (_editingReferralId == null) {
        final reference = _draftReferralId == null
            ? _firestore.collection('referrals').doc()
            : _firestore.collection('referrals').doc(_draftReferralId);
        final batch = _firestore.batch();
        batch.set(reference, {
          ...payload,
          'createdAt': FieldValue.serverTimestamp(),
        });
        final mirror = _mirror(reference.id);
        if (mirror != null) {
          batch.set(mirror, {
            ...payload,
            'createdAt': FieldValue.serverTimestamp(),
            'rootReferralPath': reference.path,
            'storedUnderBarangay': true,
          });
        }
        await batch.commit();
      } else {
        final reference = _firestore
            .collection('referrals')
            .doc(_editingReferralId);
        await _firestore.runTransaction((transaction) async {
          final snapshot = await transaction.get(reference);
          final currentStatus = _normalizeStatus(
            snapshot.data()?['status']?.toString() ?? '',
          );
          if (currentStatus != 'returned') {
            throw StateError(
              'Only referrals returned by CHO can be edited and resubmitted.',
            );
          }
          transaction.set(reference, payload, SetOptions(merge: true));
        });
        final mirror = _mirror(_editingReferralId!);
        if (mirror != null) {
          await mirror.set({
            ...payload,
            'rootReferralPath': reference.path,
          }, SetOptions(merge: true));
        }
      }
      if (!mounted) return;
      _snack('Referral submitted to CHO for review.');
      _clearDraft();
      if (widget.embedded) {
        widget.onClose?.call();
      } else {
        setState(() => _view = 2);
      }
    } catch (_) {
      _snack(
        'The referral could not be submitted. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  DocumentReference<Map<String, dynamic>>? _mirror(String referralId) {
    final code = _scope.barangayCode.trim().toUpperCase();
    if (code.isEmpty) return null;
    return _firestore
        .collection(BarangayFirestorePaths.barangaysCollection)
        .doc(code)
        .collection('referrals')
        .doc(referralId);
  }

  void _clearDraft() {
    setState(() {
      _patient = null;
      _history = null;
      _reasonController.clear();
      _observationsController.clear();
      _notesController.clear();
      _destinationController.clear();
      _priority = 'routine';
      _attachments = [];
      _draftReferralId = null;
      _editingReferralId = null;
    });
  }

  Widget _records(List<_BhwReferralRecord> records) {
    final filtered = records.where((record) {
      final patientQuery = _patientFilterController.text.trim().toLowerCase();
      final matchesPatient =
          patientQuery.isEmpty ||
          record.patientName.toLowerCase().contains(patientQuery) ||
          record.id.toLowerCase().contains(patientQuery);
      final matchesStatus =
          _statusFilter == 'all' || record.status == _statusFilter;
      final matchesPriority =
          _priorityFilter == 'all' || record.priority == _priorityFilter;
      final date = record.createdAt;
      final matchesFrom = _fromDate == null || !date.isBefore(_fromDate!);
      final matchesTo =
          _toDate == null ||
          date.isBefore(_toDate!.add(const Duration(days: 1)));
      return matchesPatient &&
          matchesStatus &&
          matchesPriority &&
          matchesFrom &&
          matchesTo;
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _recordFilters(),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          _empty(
            'No referral records found',
            'Adjust the filters or create a new referral.',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 900) {
                return Column(
                  children: filtered
                      .map((record) => _mobileRecord(record))
                      .toList(),
                );
              }
              return _recordsTable(filtered);
            },
          ),
      ],
    );
  }

  Widget _recordFilters() => _panel(
    title: 'Referral Records',
    subtitle: 'Your submitted referrals and CHO review results',
    child: WebFilterSurface(
      padding: EdgeInsets.zero,
      children: [
        WebSearchField(
          controller: _patientFilterController,
          width: 250,
          hintText: 'Patient name or referral ID',
          onChanged: (_) => setState(() {}),
          onClear: () {
            _patientFilterController.clear();
            setState(() {});
          },
        ),
        _filterDropdown(
          label: 'Status',
          value: _statusFilter,
          values: const {
            'all': 'All Statuses',
            'pending_review': 'Pending CHO Review',
            'approved': 'Approved',
            'waiting_consultation': 'Waiting Consultation',
            'returned': 'Returned for Correction',
            'completed': 'Completed',
          },
          onChanged: (value) => setState(() => _statusFilter = value),
        ),
        _filterDropdown(
          label: 'Priority',
          value: _priorityFilter,
          values: const {
            'all': 'All Priorities',
            'routine': 'Routine',
            'urgent': 'Urgent',
            'emergency': 'Emergency',
          },
          onChanged: (value) => setState(() => _priorityFilter = value),
        ),
        OutlinedButton.icon(
          onPressed: _pickDateRange,
          icon: const Icon(Icons.date_range_outlined),
          label: Text(
            _fromDate == null
                ? 'Filter by Date'
                : '${_date(_fromDate!)} – ${_date(_toDate ?? _fromDate!)}',
          ),
        ),
        if (_fromDate != null)
          IconButton(
            tooltip: 'Clear date filter',
            onPressed: () => setState(() {
              _fromDate = null;
              _toDate = null;
            }),
            icon: const Icon(Icons.close_rounded),
          ),
      ],
    ),
  );

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _fromDate == null
          ? null
          : DateTimeRange(start: _fromDate!, end: _toDate ?? _fromDate!),
    );
    if (range != null) {
      setState(() {
        _fromDate = range.start;
        _toDate = range.end;
      });
    }
  }

  Widget _recordsTable(List<_BhwReferralRecord> records) => WebTableSurface(
    minWidth: 1040,
    child: SpringDataMotion(
      dataKey: records,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(_surfaceAlt),
        columns: const [
          DataColumn(label: Text('Referral ID')),
          DataColumn(label: Text('Patient')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Priority')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('CHO Remarks')),
          DataColumn(label: Text('Actions')),
        ],
        rows: records
            .map(
              (record) => DataRow(
                cells: [
                  DataCell(Text(record.shortId)),
                  DataCell(Text(record.patientName)),
                  DataCell(Text(_date(record.createdAt))),
                  DataCell(_statusBadge(record.priorityLabel)),
                  DataCell(_statusBadge(record.statusLabel)),
                  DataCell(
                    SizedBox(
                      width: 220,
                      child: Text(
                        record.choRemarks,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(_recordActions(record)),
                ],
              ),
            )
            .toList(),
      ),
    ),
  );

  Widget _mobileRecord(_BhwReferralRecord record) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                record.patientName,
                style: const TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _statusBadge(record.statusLabel),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${record.shortId} • ${_date(record.createdAt)}',
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Text(
          'CHO Remarks: ${record.choRemarks}',
          style: const TextStyle(color: _text),
        ),
        const SizedBox(height: 12),
        _recordActions(record),
      ],
    ),
  );

  Widget _recordActions(_BhwReferralRecord record) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      TextButton.icon(
        onPressed: () => _showDetails(record),
        icon: const Icon(Icons.visibility_outlined, size: 17),
        label: const Text('View Details'),
      ),
      OutlinedButton.icon(
        onPressed: () => _downloadReferralPdf(record),
        icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
        label: const Text('A4 / QR PDF'),
        style: AppButtonStyles.outline(),
      ),
      if (record.isReturned)
        FilledButton.icon(
          onPressed: () => _editReturned(record),
          icon: const Icon(Icons.edit_note_rounded, size: 17),
          label: const Text('Correct'),
        ),
    ],
  );

  Future<void> _downloadReferralPdf(_BhwReferralRecord record) async {
    try {
      final data = <String, dynamic>{...record.data, 'id': record.id};
      final bytes = await buildReferralPdfBytes(data);
      final downloaded = downloadReportFile(
        bytes: bytes,
        filename: buildReferralPdfFilename(data),
        mimeType: 'application/pdf',
      );
      _snack(
        downloaded
            ? 'A4 referral PDF with QR code downloaded.'
            : 'PDF download is unavailable on this platform.',
      );
    } catch (error) {
      _snack('Could not generate the referral PDF: $error');
    }
  }

  void _showDetails(_BhwReferralRecord record) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        title: Text(record.patientName, style: const TextStyle(color: _text)),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: _infoGrid([
              MapEntry('Referral ID', record.id),
              MapEntry('Date', _date(record.createdAt)),
              MapEntry('Priority', record.priorityLabel),
              MapEntry('Status', record.statusLabel),
              MapEntry('Referral Reason', record.reason),
              MapEntry('Observations', record.observations),
              MapEntry('Supporting Notes', record.notes),
              MapEntry('Destination Facility', record.destination),
              MapEntry('CHO Remarks', record.choRemarks),
              MapEntry('Assigned Hospital', record.hospital),
              MapEntry('Assigned Doctor', record.doctor),
              MapEntry('Doctor Recommendation', record.doctorRecommendation),
              MapEntry('Treatment Summary', record.treatmentSummary),
              MapEntry('Follow-up Schedule', record.followUpSchedule),
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _editReturned(_BhwReferralRecord record) async {
    final patient = record.patientInformation.isNotEmpty
        ? record.patientInformation
        : {'patientId': record.patientId, 'patientName': record.patientName};
    await _openPatient(patient);
    if (!mounted) return;
    setState(() {
      _editingReferralId = record.id;
      _reasonController.text = record.reason;
      _observationsController.text = record.observations;
      _notesController.text = record.notes;
      _destinationController.text = record.destination;
      _priority = record.priority;
      _attachments = record.attachmentData;
      _view = 1;
    });
  }

  Widget _followUps(List<_BhwReferralRecord> records) {
    final followUps = records
        .where((record) => record.followUpRequired)
        .toList();
    if (followUps.isEmpty) {
      return _empty(
        'No follow-ups required',
        'Completed consultations requiring a BHW home visit will appear here.',
      );
    }
    return Column(
      children: followUps.map((record) => _followUpCard(record)).toList(),
    );
  }

  Widget _followUpCard(_BhwReferralRecord record) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _aqua.withValues(alpha: 0.2)),
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
                color: _text,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            _statusBadge(
              record.homeVisitCompleted
                  ? 'Home Visit Completed'
                  : 'Home Visit Required',
            ),
          ],
        ),
        const SizedBox(height: 14),
        _infoGrid([
          MapEntry('Doctor Recommendation', record.doctorRecommendation),
          MapEntry('Treatment Summary', record.treatmentSummary),
          MapEntry('Follow-up Schedule', record.followUpSchedule),
          MapEntry('Latest Home Visit Notes', record.latestFollowUpNotes),
        ]),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => _recordFollowUp(record),
          style: AppButtonStyles.primary(),
          icon: const Icon(Icons.home_work_outlined),
          label: Text(
            record.homeVisitCompleted
                ? 'Record Another Home Visit'
                : 'Conduct Home Visit',
          ),
        ),
      ],
    ),
  );

  Future<void> _recordFollowUp(_BhwReferralRecord record) async {
    final controller = TextEditingController();
    var completed = false;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _surface,
          title: const Text(
            'Record Home Visit',
            style: TextStyle(color: _text),
          ),
          content: SizedBox(
            width: 580,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.patientName,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 4,
                  maxLines: 6,
                  style: const TextStyle(color: _darkFieldText),
                  decoration: _inputDecoration('Follow-up notes'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: completed,
                  activeColor: _aqua,
                  title: const Text(
                    'Mark home visit completed',
                    style: TextStyle(color: _text),
                  ),
                  onChanged: (value) =>
                      setDialogState(() => completed = value ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  _snack('Enter follow-up notes.');
                  return;
                }
                Navigator.pop(context, true);
              },
              style: AppButtonStyles.primary(),
              child: const Text('Save Home Visit'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      final user = FirebaseAuth.instance.currentUser;
      final entry = {
        'notes': controller.text.trim(),
        'homeVisitCompleted': completed,
        'conductedAt': Timestamp.now(),
        'conductedByUid': user?.uid,
        'conductedByName': user?.displayName ?? user?.email,
      };
      final payload = {
        'followUps': FieldValue.arrayUnion([entry]),
        'latestFollowUpNotes': controller.text.trim(),
        'homeVisitCompleted': completed,
        if (completed) 'homeVisitCompletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await record.reference.set(payload, SetOptions(merge: true));
      final mirror = _mirror(record.id);
      if (mirror != null) {
        await mirror.set(payload, SetOptions(merge: true));
      }
      if (mounted) _snack('Home visit follow-up saved.');
    }
    controller.dispose();
  }

  Widget _panel({
    required String title,
    required String subtitle,
    required Widget child,
    Widget? trailing,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _aqua.withValues(alpha: 0.16)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final heading = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            );
            if (trailing == null) return heading;
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 8), trailing],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heading),
                const SizedBox(width: 10),
                trailing,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );

  Widget _empty(String title, String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 45, horizontal: 20),
    child: Column(
      children: [
        const Icon(Icons.inbox_outlined, color: _muted, size: 46),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _text,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted),
        ),
      ],
    ),
  );

  Widget _infoGrid(List<MapEntry<String, String>> items) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 820
          ? 3
          : constraints.maxWidth >= 520
          ? 2
          : 1;
      final width = (constraints.maxWidth - 14 * (columns - 1)) / columns;
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: items
            .map(
              (item) => SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.key,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.value.trim().isEmpty ? 'Not provided' : item.value,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _text, height: 1.35),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      );
    },
  );

  Widget _responsiveFields(List<Widget> fields) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760 ? 2 : 1;
      final width = (constraints.maxWidth - 14 * (columns - 1)) / columns;
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: fields
            .map((field) => SizedBox(width: width, child: field))
            .toList(),
      );
    },
  );

  Widget _filterDropdown({
    required String label,
    required String value,
    required Map<String, String> values,
    required ValueChanged<String> onChanged,
  }) => WebFilterDropdown<String>(
    label: label,
    value: value,
    width: 210,
    items: values.entries
        .map(
          (entry) => DropdownMenuItem<String>(
            value: entry.key,
            child: Text(entry.value, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: (item) {
      if (item != null) onChanged(item);
    },
  );

  Widget _fieldLabel(String value) => Text(
    value,
    style: const TextStyle(
      color: _text,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    ),
  );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF6B7D84)),
    filled: true,
    fillColor: _lightField,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFB7C7CC)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _aqua, width: 2),
    ),
  );

  Widget _statusBadge(String value) {
    final normalized = value.toLowerCase();
    final color = normalized.contains('return')
        ? Colors.orangeAccent
        : normalized.contains('complete') || normalized.contains('approved')
        ? Colors.greenAccent
        : normalized.contains('emergency') || normalized.contains('urgent')
        ? Colors.redAccent
        : _aqua;
    return Tooltip(
      message: value,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 180),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Map<String, dynamic>? _latest(List<Map<String, dynamic>>? records) =>
      records == null || records.isEmpty ? null : records.first;

  String _patientText(List<String> keys, {String fallback = 'Not provided'}) =>
      _textOf(_patient ?? const {}, keys, fallback: fallback);

  String _recordSummary(Map<String, dynamic>? record, List<String> keys) {
    if (record == null) return 'No linked record';
    final values = <String>[];
    for (final key in keys) {
      final value = record[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && !values.contains(value)) values.add(value);
    }
    return values.isEmpty ? 'Linked record available' : values.join(' • ');
  }

  String _vitalSummary(Map<String, dynamic>? record) {
    if (record == null) return 'No linked vital signs';
    final direct = _textOf(record, [
      'completeVitalSigns',
      'vitalSigns',
      'vitals',
      'vital_signs',
    ]);
    if (direct.isNotEmpty) return direct;
    final values = <String>[];
    void add(String label, List<String> keys) {
      final value = _textOf(record, keys);
      if (value.isNotEmpty) values.add('$label: $value');
    }

    add('BP', ['bloodPressure', 'blood_pressure', 'bp']);
    add('Temp', ['temperature', 'temp']);
    add('Pulse', ['pulseRate', 'pulse']);
    add('SpO₂', ['oxygenSaturation', 'spo2']);
    return values.isEmpty ? 'No linked vital signs' : values.join(' • ');
  }

  String _homeCare(Map<String, dynamic>? record) {
    if (record == null) return 'No existing home-care guidance';
    final direct = _textOf(record, ['homeCare', 'home_care', 'selfCare']);
    if (direct.isNotEmpty) return direct;
    final raw = record['recoveryPlan'] ?? record['recovery_plan'];
    dynamic decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {}
    }
    if (decoded is Map) {
      final value = decoded['home_care'] ?? decoded['homeCare'];
      if (value is Iterable) return value.join(', ');
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return 'No existing home-care guidance';
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _BhwReferralRecord {
  _BhwReferralRecord(this.document) : data = document.data();

  final QueryDocumentSnapshot<Map<String, dynamic>> document;
  final Map<String, dynamic> data;

  String get id => document.id;
  String get shortId => id.length <= 10 ? id : id.substring(0, 10);
  DocumentReference<Map<String, dynamic>> get reference => document.reference;
  String get status =>
      _normalizeStatus(_textOf(data, ['status'], fallback: 'pending_review'));
  String get statusLabel => status == 'returned'
      ? 'Returned for Correction'
      : _title(status == 'pending_review' ? 'pending_cho_review' : status);
  String get priority => _textOf(data, [
    'priority',
    'referralPriority',
  ], fallback: 'routine').toLowerCase();
  String get priorityLabel => _title(priority);
  String get patientId =>
      _textOf(data, ['patientRecordId', 'patientId', 'linkedPatientId']);
  String get patientName => _textOf(data, [
    'patientName',
  ], fallback: _patientName(patientInformation));
  Map<String, dynamic> get patientInformation {
    final value = data['patientInformation'];
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  String get reason =>
      _textOf(data, ['referralReason', 'reason'], fallback: 'Not provided');
  String get observations => _textOf(data, [
    'observations',
    'chiefComplaint',
    'chiefComplaints',
  ], fallback: 'Not provided');
  String get notes => _textOf(data, [
    'bhwNotes',
    'supportingNotes',
    'notes',
  ], fallback: 'Not provided');
  String get destination => _textOf(data, [
    'destinationFacility',
    'referredTo',
  ], fallback: 'Not specified');
  String get choRemarks => _textOf(data, [
    'choReviewNotes',
    'choRemarks',
    'reviewNotes',
  ], fallback: 'No CHO remarks yet');
  String get hospital => _textOf(data, [
    'assignedHospital',
    'receivingHospital',
  ], fallback: 'Not assigned');
  String get doctor => _textOf(data, [
    'assignedDoctorName',
    'receivingDoctor',
  ], fallback: 'Not assigned');
  String get doctorRecommendation => _textOf(data, [
    'doctorRecommendation',
    'doctorNotes',
  ], fallback: 'Awaiting doctor recommendation');
  String get treatmentSummary => _textOf(data, [
    'treatmentSummary',
    'doctorTreatment',
  ], fallback: 'Awaiting treatment summary');
  String get followUpSchedule => _textOf(data, [
    'followUpSchedule',
    'followupSchedule',
    'followUpDate',
  ], fallback: 'Not scheduled');
  bool get followUpRequired {
    final value = data['followUpRequired'];
    return value == true ||
        value?.toString().toLowerCase() == 'true' ||
        (isCompleted && followUpSchedule != 'Not scheduled');
  }

  bool get homeVisitCompleted => data['homeVisitCompleted'] == true;
  String get latestFollowUpNotes => _textOf(data, [
    'latestFollowUpNotes',
  ], fallback: 'No home visit recorded');
  List<Map<String, dynamic>> get attachmentData {
    final value = data['attachments'];
    if (value is! Iterable) return [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  bool get isPending => status == 'pending_review';
  bool get isApproved => const {
    'approved',
    'hospital_assigned',
    'doctor_assigned',
    'assigned',
    'waiting_consultation',
    'consulted',
  }.contains(status);
  bool get isReturned => status == 'returned';
  bool get isCompleted => status == 'completed';
  DateTime get createdAt =>
      _asDate(
        data['createdAt'] ?? data['submittedAt'] ?? data['referralDateTime'],
      ) ??
      DateTime.fromMillisecondsSinceEpoch(0);
  DateTime get updatedAt =>
      _asDate(data['updatedAt'] ?? data['createdAt']) ?? createdAt;
}

String _textOf(
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

String _patientName(Map<String, dynamic> patient) {
  final direct = _textOf(patient, ['patientName', 'fullName', 'name']);
  if (direct.isNotEmpty) return direct;
  final first = _textOf(patient, ['firstName', 'patientFirstName']);
  final middle = _textOf(patient, ['middleName', 'patientMiddleName']);
  final surname = _textOf(patient, [
    'surname',
    'lastName',
    'patientSurname',
    'patientLastName',
  ]);
  final result = [
    first,
    middle,
    surname,
  ].where((value) => value.isNotEmpty).join(' ');
  return result.isEmpty ? 'Unnamed patient' : result;
}

String _normalizeStatus(String status) {
  final value = status.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
  return switch (value) {
    'draft' => 'draft',
    'submitted' || 'pending' || 'under_review' => 'pending_review',
    'return_for_correction' || 'returned_for_correction' => 'returned',
    'waiting' => 'waiting_consultation',
    'in_treatment' => 'consulted',
    _ => value,
  };
}

DateTime? _asDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}

String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _title(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
