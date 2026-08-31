import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_firestore_paths.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/shared/components/app_metric_card.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_first_service_selector.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/shared_patient_search_panel.dart';
import 'package:mycapstone_project/web/shared/services/account_policy_service.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/shared/services/web_record_sync.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/shared/components/app_buttons.dart';
import 'package:mycapstone_project/web/shared/utils/referral_pdf.dart';
import 'package:mycapstone_project/web/shared/utils/report_print.dart';
import 'package:mycapstone_project/web/shared/widgets/web_sync_status_badge.dart';
import 'package:mycapstone_project/web/shared/components/role_decision_support_panel.dart';

const Color _primaryAqua = Color(0xFF2F80ED);
const Color _darkDeepTeal = Color(0xFF071A33);
const Color _panelSurface = Colors.white;
const Color _panelAlt = Color(0xFFEDF3FA);
const Color _lightOffWhite = Color(0xFF0B1F3A);
const Color _mutedCoolGray = Color(0xFF4B6075);

class ReferralsPage extends StatefulWidget {
  const ReferralsPage({super.key, this.initialPatient});

  final Map<String, dynamic>? initialPatient;

  @override
  State<ReferralsPage> createState() => _ReferralsPageState();
}

class _ReferralsPageState extends State<ReferralsPage> {
  static const List<String> _referralCategoryOptions = <String>[
    'Emergency',
    'Ambulatory',
    'Medico-legal',
  ];
  static const List<String> _referralReasonOptions = <String>[
    'Hospital Capability',
    'Lack of Specialist',
    'Financial Constraint',
    'Others',
  ];
  static const List<String> _doctorCareStatuses = <String>[
    'doctor_assigned',
    'waiting_consultation',
    'consulted',
    'completed',
  ];

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FirebaseFirestore _firestore = getFirestoreInstance();
  final WebRecordWriteCoordinator _writeCoordinator = WebRecordWriteCoordinator(
    firestore: getFirestoreInstance(),
  );
  final AccountPolicyService _accountPolicyService =
      AccountPolicyService.instance;
  final PatientCenteredHistoryService _patientHistoryService =
      PatientCenteredHistoryService();
  final GlobalKey<FormState> _referralFormKey = GlobalKey<FormState>();

  final TextEditingController _referralDateTimeController =
      TextEditingController();
  final TextEditingController _patientLookupController =
      TextEditingController();
  final TextEditingController _patientAddressController =
      TextEditingController();
  final TextEditingController _patientSurnameController =
      TextEditingController();
  final TextEditingController _patientFirstNameController =
      TextEditingController();
  final TextEditingController _patientMiddleNameController =
      TextEditingController();
  final TextEditingController _patientAgeController = TextEditingController();
  final TextEditingController _patientSexController = TextEditingController();
  final TextEditingController _chiefComplaintController =
      TextEditingController();
  final TextEditingController _medicalHistoryController =
      TextEditingController();
  final TextEditingController _surgicalProcedureController =
      TextEditingController();
  final TextEditingController _lastMealTimeController = TextEditingController();
  final TextEditingController _completeVitalSignsController =
      TextEditingController();
  final TextEditingController _impressionController = TextEditingController();
  final TextEditingController _actionTakenController = TextEditingController();
  final TextEditingController _healthInsuranceCoverageTypeController =
      TextEditingController();
  final TextEditingController _referralReasonOtherController =
      TextEditingController();

  UserAccessScope _scope = UserAccessScope.unauthenticated;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadErrorMessage;
  final Set<String> _selectedReferralCategories = <String>{};
  final Set<String> _selectedReferralReasons = <String>{};
  bool? _hasSurgicalOperations;
  bool? _hasHealthInsuranceCoverage;
  Timer? _sharedPatientSearchDebounce;
  List<Map<String, dynamic>> _sharedPatientMatches = <Map<String, dynamic>>[];
  bool _isSearchingSharedPatients = false;
  Map<String, dynamic>? _selectedPatientSeed;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _doctorDocs =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  String? _selectedPreferredDoctorUid;
  bool _autoAssignDoctor = true;

  bool get _isDoctor => _scope.role == 'doctor';
  bool get _isBhw => _scope.role == 'bhw';
  bool get _isChoOperator => _scope.isChoAdmin;

  DocumentReference<Map<String, dynamic>>? _barangayReferralMirrorReference({
    required String barangayCode,
    required String referralId,
  }) {
    final normalizedBarangayCode = barangayCode.trim().toUpperCase();
    if (normalizedBarangayCode.isEmpty || referralId.trim().isEmpty) {
      return null;
    }

    return _firestore
        .collection(BarangayFirestorePaths.barangaysCollection)
        .doc(normalizedBarangayCode)
        .collection('referrals')
        .doc(referralId.trim());
  }

  Future<void> _syncBarangayReferralMirror({
    required String referralId,
    required Map<String, dynamic> payload,
  }) async {
    final barangayCode = (payload['barangayCode'] ?? '').toString().trim();
    final mirrorRef = _barangayReferralMirrorReference(
      barangayCode: barangayCode,
      referralId: referralId,
    );
    if (mirrorRef == null) {
      return;
    }

    await mirrorRef.set({
      ...payload,
      'rootReferralPath': 'referrals/$referralId',
      'storedUnderBarangay': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _loadDoctorDirectory() async {
    final doctors = await _firestore
        .collection('users')
        .where('role', whereIn: const <String>['DOCTOR', 'doctor'])
        .get();
    final doctorDocs = doctors.docs;
    doctorDocs.sort((a, b) {
      final aName = _doctorDisplayName(a.data()).toLowerCase();
      final bName = _doctorDisplayName(b.data()).toLowerCase();
      return aName.compareTo(bName);
    });
    return doctorDocs;
  }

  String _doctorDisplayName(Map<String, dynamic> data) {
    return (data['username'] ??
            data['fullName'] ??
            data['displayName'] ??
            data['email'] ??
            'Doctor')
        .toString();
  }

  String _doctorSpecialization(Map<String, dynamic> data) {
    final specialization =
        (data['specialization'] ??
                data['doctorSpecialization'] ??
                data['specialty'] ??
                'General Medicine')
            .toString()
            .trim();
    return specialization.isEmpty ? 'General Medicine' : specialization;
  }

  String _doctorAvailability(Map<String, dynamic> data) {
    final availability =
        (data['availability'] ?? data['doctorAvailability'] ?? 'available')
            .toString()
            .trim()
            .toLowerCase();
    return availability.isEmpty ? 'available' : availability;
  }

  String _doctorAvailabilityLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'busy':
        return 'Busy';
      case 'limited':
        return 'Limited';
      case 'unavailable':
        return 'Unavailable';
      default:
        return 'Available';
    }
  }

  Color _doctorAvailabilityColor(String value) {
    switch (value.trim().toLowerCase()) {
      case 'busy':
        return Colors.orangeAccent;
      case 'limited':
        return Colors.amberAccent;
      case 'unavailable':
        return Colors.redAccent;
      default:
        return Colors.greenAccent;
    }
  }

  String _assignmentModeLabel(String mode, String source) {
    if (mode == 'smart' && source == 'bhw_auto') {
      return 'Automatic assignment';
    }
    if (mode == 'smart') {
      return 'Smart assignment';
    }
    if (mode == 'manual' && source == 'bhw_selected') {
      return 'BHW-selected doctor';
    }
    return 'Manual assignment';
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _availableDoctorDocs {
    return _doctorDocs
        .where((doctorDoc) {
          final data = doctorDoc.data();
          final accountStatus = (data['accountStatus'] ?? 'active')
              .toString()
              .trim()
              .toLowerCase();
          final availability = _doctorAvailability(
            data,
          ).replaceAll(RegExp(r'[\s-]+'), '_');
          final normalizedAccountStatus = accountStatus.replaceAll('-', '_');
          final unavailableAccount = const {
            'disabled',
            'archived',
            'inactive',
            'deactivated',
          }.contains(normalizedAccountStatus);
          final unavailable =
              availability == 'unavailable' ||
              availability == 'on_leave' ||
              availability == 'leave';
          return !unavailableAccount && !unavailable;
        })
        .toList(growable: false);
  }

  Map<String, dynamic>? get _selectedPreferredDoctorData {
    final selectedUid = _selectedPreferredDoctorUid;
    if (selectedUid == null || selectedUid.isEmpty) {
      return null;
    }
    for (final doc in _availableDoctorDocs) {
      if (doc.id == selectedUid) {
        return doc.data();
      }
    }
    return null;
  }

  String _normalizeSearchValue(String value) {
    return value.trim().toLowerCase();
  }

  bool _matchesCurrentBarangay(Map<String, dynamic> patient) {
    final scopeBarangay = _normalizeSearchValue(_scope.barangay);
    if (scopeBarangay.isEmpty) {
      return true;
    }

    final patientBarangay = _normalizeSearchValue(
      (patient['barangay'] ?? '').toString(),
    );
    if (patientBarangay.isNotEmpty) {
      return patientBarangay == scopeBarangay;
    }

    final address = _normalizeSearchValue(
      (patient['address'] ?? '').toString(),
    );
    return address.contains(scopeBarangay);
  }

  Future<void> _showSharedPatientTimeline(Map<String, dynamic> patient) async {
    final snapshot = await _patientHistoryService.loadPatientHistory(patient);
    if (!mounted) {
      return;
    }

    await PatientHistoryDialogs.showPatientTimelineDialog(
      context: context,
      patient: patient,
      snapshot: snapshot,
    );
  }

  void _scheduleSharedPatientSearch(String query) {
    _sharedPatientSearchDebounce?.cancel();
    final normalizedQuery = query.trim();

    if (normalizedQuery.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sharedPatientMatches = <Map<String, dynamic>>[];
        _isSearchingSharedPatients = false;
      });
      return;
    }

    setState(() {
      _isSearchingSharedPatients = true;
    });

    _sharedPatientSearchDebounce = Timer(
      const Duration(milliseconds: 250),
      () async {
        final results = await _patientHistoryService.searchRegisteredPatients(
          normalizedQuery,
        );
        if (!mounted ||
            _patientLookupController.text.trim().toLowerCase() !=
                normalizedQuery.toLowerCase()) {
          return;
        }

        setState(() {
          _sharedPatientMatches = results
              .where(_matchesCurrentBarangay)
              .toList(growable: false);
          _isSearchingSharedPatients = false;
        });
      },
    );
  }

  void _applyPatientSeed(Map<String, dynamic> patient) {
    final patientName = (patient['patientName'] ?? patient['name'] ?? '')
        .toString()
        .trim();
    final surname = (patient['surname'] ?? '').toString().trim();
    final firstName = (patient['firstName'] ?? '').toString().trim();
    final middleName = (patient['middleName'] ?? '').toString().trim();

    setState(() {
      _selectedPatientSeed = Map<String, dynamic>.from(patient);
      if (surname.isNotEmpty || firstName.isNotEmpty) {
        _patientSurnameController.text = surname;
        _patientFirstNameController.text = firstName;
        _patientMiddleNameController.text = middleName;
      } else {
        final parts = patientName.split(',');
        if (parts.length > 1) {
          _patientSurnameController.text = parts.first.trim();
          final givenNames = parts.last.trim().split(' ');
          _patientFirstNameController.text = givenNames.isEmpty
              ? ''
              : givenNames.first.trim();
          _patientMiddleNameController.text = givenNames.length > 1
              ? givenNames.sublist(1).join(' ')
              : '';
        } else {
          final nameParts = patientName.split(' ');
          _patientFirstNameController.text = nameParts.isEmpty
              ? ''
              : nameParts.first.trim();
          _patientSurnameController.text = nameParts.length > 1
              ? nameParts.last.trim()
              : '';
          _patientMiddleNameController.text = nameParts.length > 2
              ? nameParts.sublist(1, nameParts.length - 1).join(' ')
              : '';
        }
      }
      _patientAgeController.text = (patient['age'] ?? '').toString();
      _patientSexController.text = (patient['gender'] ?? patient['sex'] ?? '')
          .toString();
      _patientAddressController.text =
          (patient['address'] ?? patient['barangay'] ?? '').toString();
      _patientLookupController.text = patientName;
      _sharedPatientMatches = <Map<String, dynamic>>[];
      _isSearchingSharedPatients = false;
    });
  }

  Future<void> _printReferralReport(Map<String, dynamic> referral) async {
    final printTarget = prepareReportPrintTarget();
    try {
      final pdfBytes = await buildReferralPdfBytes(referral);
      final filename = buildReferralPdfFilename(referral);
      final printed = printReportFile(
        bytes: pdfBytes,
        filename: filename,
        mimeType: 'application/pdf',
        target: printTarget,
      );
      Get.snackbar(
        printed ? 'Print view opened' : 'Print unavailable',
        printed
            ? 'The referral PDF was opened in a print-ready view.'
            : 'Printing is not supported on this platform.',
        backgroundColor: printed ? Colors.green : Colors.orange,
        colorText: Colors.white,
      );
    } catch (error) {
      closeReportPrintTarget(printTarget);
      Get.snackbar(
        'Print failed',
        'Could not prepare the referral report for printing: $error',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _referralDateTimeController.text = _formatDateTimeInput(DateTime.now());
    _loadScope();
    if (widget.initialPatient != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyPatientSeed(widget.initialPatient!);
      });
    }
  }

  @override
  void dispose() {
    _sharedPatientSearchDebounce?.cancel();
    _referralDateTimeController.dispose();
    _patientLookupController.dispose();
    _patientAddressController.dispose();
    _patientSurnameController.dispose();
    _patientFirstNameController.dispose();
    _patientMiddleNameController.dispose();
    _patientAgeController.dispose();
    _patientSexController.dispose();
    _chiefComplaintController.dispose();
    _medicalHistoryController.dispose();
    _surgicalProcedureController.dispose();
    _lastMealTimeController.dispose();
    _completeVitalSignsController.dispose();
    _impressionController.dispose();
    _actionTakenController.dispose();
    _healthInsuranceCoverageTypeController.dispose();
    _referralReasonOtherController.dispose();
    super.dispose();
  }

  Future<void> _loadScope() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadErrorMessage = null;
      });
    }

    try {
      final scope = await UserAccessScopeService.instance.loadCurrentScope();
      if (!scope.isAuthenticated) {
        if (!mounted) return;
        Get.offAllNamed(WebRoutes.login);
        return;
      }

      if (!scope.canViewAllBarangays &&
          scope.role != 'bhw' &&
          scope.role != 'doctor') {
        if (!mounted) return;
        Get.snackbar(
          'Access denied',
          'Only BHW, CHO, and doctor accounts can open the referral module.',
          backgroundColor: Colors.redAccent,
          colorText: Colors.white,
        );
        Get.offAllNamed(WebRoutes.login);
        return;
      }

      List<QueryDocumentSnapshot<Map<String, dynamic>>> doctorDocs =
          <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      try {
        doctorDocs = await _loadDoctorDirectory();
      } catch (_) {
        doctorDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      }

      if (!mounted) return;
      setState(() {
        _scope = scope;
        _doctorDocs = doctorDocs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadErrorMessage = 'Could not initialize the referral page: $e';
      });
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _referralsStream() {
    final collection = _firestore.collection('referrals');
    if (_isChoOperator) {
      return collection.snapshots(includeMetadataChanges: true);
    }
    if (_isDoctor) {
      return collection
          .where('assignedDoctorUid', isEqualTo: _scope.userId)
          .snapshots(includeMetadataChanges: true);
    }
    return collection
        .where('createdByUid', isEqualTo: _scope.userId)
        .snapshots(includeMetadataChanges: true);
  }

  Future<void> _submitReferral() async {
    if (_selectedPatientSeed == null ||
        _selectedPatientSeed!['isRegisteredPatient'] != true) {
      _showReferralValidationError(
        'Select a registered patient before completing the referral.',
      );
      return;
    }
    if (!_referralFormKey.currentState!.validate() || _isSubmitting) {
      return;
    }
    if (_selectedReferralCategories.isEmpty) {
      _showReferralValidationError(
        'Select at least one referral type before submitting.',
      );
      return;
    }
    if (_hasSurgicalOperations == null) {
      _showReferralValidationError(
        'Choose Yes or No for surgical operations before submitting.',
      );
      return;
    }
    if (_hasSurgicalOperations == true &&
        _surgicalProcedureController.text.trim().isEmpty) {
      _showReferralValidationError('Enter the surgical procedure performed.');
      return;
    }
    if (_hasHealthInsuranceCoverage == null) {
      _showReferralValidationError(
        'Choose Yes or No for health insurance coverage before submitting.',
      );
      return;
    }
    if (_hasHealthInsuranceCoverage == true &&
        _healthInsuranceCoverageTypeController.text.trim().isEmpty) {
      _showReferralValidationError(
        'State the type of health insurance coverage.',
      );
      return;
    }
    if (_selectedReferralReasons.isEmpty) {
      _showReferralValidationError(
        'Select at least one reason for referral before submitting.',
      );
      return;
    }
    if (_selectedReferralReasons.contains('Others') &&
        _referralReasonOtherController.text.trim().isEmpty) {
      _showReferralValidationError('Describe the other reason for referral.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final selectedDoctorData = _selectedPreferredDoctorData;

    setState(() => _isSubmitting = true);
    try {
      final referralRef = _firestore.collection('referrals').doc();
      final patientName = _composePatientName();
      final referralReasonSummary = _composeReferralReasonSummary();
      final referralCategorySummary = _selectedReferralCategories.join(', ');
      final payload = <String, dynamic>{
        'id': referralRef.id,
        'clientOperationId': referralRef.id,
        'recordVersion': 1,
        'referralCategories': _selectedReferralCategories.toList()..sort(),
        'referralCategorySummary': referralCategorySummary,
        'referredTo': _selectedPreferredDoctorUid?.isNotEmpty == true
            ? _doctorDisplayName(
                selectedDoctorData ?? const <String, dynamic>{},
              )
            : '',
        'referralDateTime': _referralDateTimeController.text.trim(),
        'patientAddress': _patientAddressController.text.trim(),
        'patientName': patientName,
        'patientSurname': _patientSurnameController.text.trim(),
        'patientFirstName': _patientFirstNameController.text.trim(),
        'patientMiddleName': _patientMiddleNameController.text.trim(),
        'patientRecordId':
            (_selectedPatientSeed?['patientId'] ??
                    _selectedPatientSeed?['linkedPatientId'] ??
                    '')
                .toString(),
        'patientId':
            (_selectedPatientSeed?['patientId'] ??
                    _selectedPatientSeed?['id'] ??
                    '')
                .toString(),
        'linkedPatientId':
            (_selectedPatientSeed?['linkedPatientId'] ??
                    _selectedPatientSeed?['patientId'] ??
                    _selectedPatientSeed?['id'] ??
                    '')
                .toString(),
        'patientAge': _patientAgeController.text.trim(),
        'patientSex': _patientSexController.text.trim(),
        'chiefComplaint': _chiefComplaintController.text.trim(),
        'chiefComplaints': _chiefComplaintController.text.trim(),
        'medicalHistory': _medicalHistoryController.text.trim(),
        'hasSurgicalOperations': _hasSurgicalOperations,
        'surgicalProcedure': _hasSurgicalOperations == true
            ? _surgicalProcedureController.text.trim()
            : '',
        'lastMealTime': _lastMealTimeController.text.trim(),
        'completeVitalSigns': _completeVitalSignsController.text.trim(),
        'impression': _impressionController.text.trim(),
        'actionTaken': _actionTakenController.text.trim(),
        'currentDiagnosis': _impressionController.text.trim(),
        'currentTreatment': _actionTakenController.text.trim(),
        'currentMedication': '',
        'hasHealthInsuranceCoverage': _hasHealthInsuranceCoverage,
        'healthInsuranceCoverageType': _hasHealthInsuranceCoverage == true
            ? _healthInsuranceCoverageTypeController.text.trim()
            : '',
        'referralReasonOptions': _selectedReferralReasons.toList()..sort(),
        'referralReasonOther': _selectedReferralReasons.contains('Others')
            ? _referralReasonOtherController.text.trim()
            : '',
        'referralReason': referralReasonSummary,
        'status': 'submitted',
        'preferredDoctorUid': _selectedPreferredDoctorUid ?? '',
        'preferredDoctorName': selectedDoctorData == null
            ? ''
            : _doctorDisplayName(selectedDoctorData),
        'preferredDoctorSpecialization': selectedDoctorData == null
            ? ''
            : _doctorSpecialization(selectedDoctorData),
        'preferredDoctorAvailability': selectedDoctorData == null
            ? ''
            : _doctorAvailability(selectedDoctorData),
        'autoAssignDoctor': _autoAssignDoctor,
        'barangay': _scope.barangay,
        'barangayCode': _scope.barangayCode,
        'barangayDistrict': _scope.barangayDistrict,
        'createdByUid': user.uid,
        'createdByRole': _scope.role,
        'createdByEmail': user.email,
        'createdByName': user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : user.email?.split('@').first,
        'medicalSnapshot': {
          'diagnosis': _impressionController.text.trim(),
          'treatment': _actionTakenController.text.trim(),
          'medication': '',
          'chiefComplaint': _chiefComplaintController.text.trim(),
          'medicalHistory': _medicalHistoryController.text.trim(),
          'vitalSigns': _completeVitalSignsController.text.trim(),
          'impression': _impressionController.text.trim(),
          'actionTaken': _actionTakenController.text.trim(),
        },
        'referralFormVersion': 2,
        'selectedPatientSourceModules': _selectedPatientSeed == null
            ? const <String>[]
            : List<String>.from(
                _selectedPatientSeed!['sourceModules'] as List? ??
                    const <String>[],
              ),
        'barangayReferralPath': _scope.barangayCode.trim().isEmpty
            ? ''
            : '${BarangayFirestorePaths.barangayDocumentPath(_scope.barangayCode)}/referrals/${referralRef.id}',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final batch = _firestore.batch();
      batch.set(referralRef, payload);

      final mirrorRef = _barangayReferralMirrorReference(
        barangayCode: _scope.barangayCode,
        referralId: referralRef.id,
      );
      if (mirrorRef != null) {
        batch.set(mirrorRef, {
          ...payload,
          'rootReferralPath': referralRef.path,
          'storedUnderBarangay': true,
        });
      }

      await batch.commit();

      DoctorAssignmentExecutionResult? assignmentResult;
      Object? assignmentError;
      if ((_selectedPreferredDoctorUid?.isNotEmpty ?? false) ||
          _autoAssignDoctor) {
        try {
          assignmentResult = await _accountPolicyService.assignDoctorToReferral(
            referralId: referralRef.id,
            preferredDoctorUid: _isBhw ? null : _selectedPreferredDoctorUid,
          );
        } catch (error) {
          assignmentError = error;
        }
      }

      if (mounted) {
        _resetReferralForm();
      }

      Get.snackbar(
        assignmentResult?.recommendation != null
            ? 'Referral submitted and assigned'
            : 'Referral submitted',
        assignmentResult?.recommendation != null
            ? 'The referral is now routed to ${assignmentResult!.recommendation!.doctorName} (${assignmentResult.recommendation!.specialization}) for follow-through care.'
            : assignmentError != null
            ? 'The referral was submitted, but doctor assignment is still pending. CHO can assign a doctor from the referral queue.'
            : 'The referral was sent to CHO for real-time review and doctor assignment.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (_) {
      Get.snackbar(
        'Submission failed',
        'The referral could not be submitted. Check your connection and try again.',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showReferralValidationError(String message) {
    Get.snackbar(
      'Incomplete referral form',
      message,
      backgroundColor: Colors.orange,
      colorText: Colors.white,
    );
  }

  String _composePatientName() {
    final surname = _patientSurnameController.text.trim();
    final firstName = _patientFirstNameController.text.trim();
    final middleName = _patientMiddleNameController.text.trim();
    final givenNames = <String>[
      firstName,
      if (middleName.isNotEmpty) middleName,
    ].where((value) => value.isNotEmpty).join(' ');
    if (surname.isEmpty) {
      return givenNames;
    }
    if (givenNames.isEmpty) {
      return surname;
    }
    return '$surname, $givenNames';
  }

  String _composeReferralReasonSummary() {
    final reasons = _selectedReferralReasons.toList()..sort();
    if (reasons.isEmpty) {
      return '';
    }

    final values = <String>[];
    for (final reason in reasons) {
      if (reason == 'Others') {
        final otherText = _referralReasonOtherController.text.trim();
        values.add(otherText.isEmpty ? 'Others' : 'Others: $otherText');
        continue;
      }
      values.add(reason);
    }
    return values.join(', ');
  }

  void _resetReferralForm() {
    _referralFormKey.currentState?.reset();
    _referralDateTimeController.text = _formatDateTimeInput(DateTime.now());
    _patientLookupController.clear();
    _patientAddressController.clear();
    _patientSurnameController.clear();
    _patientFirstNameController.clear();
    _patientMiddleNameController.clear();
    _patientAgeController.clear();
    _patientSexController.clear();
    _chiefComplaintController.clear();
    _medicalHistoryController.clear();
    _surgicalProcedureController.clear();
    _lastMealTimeController.clear();
    _completeVitalSignsController.clear();
    _impressionController.clear();
    _actionTakenController.clear();
    _healthInsuranceCoverageTypeController.clear();
    _referralReasonOtherController.clear();
    setState(() {
      _selectedReferralCategories.clear();
      _selectedReferralReasons.clear();
      _hasSurgicalOperations = null;
      _hasHealthInsuranceCoverage = null;
      _selectedPreferredDoctorUid = null;
      _selectedPatientSeed = null;
      _sharedPatientMatches = <Map<String, dynamic>>[];
      _isSearchingSharedPatients = false;
      _autoAssignDoctor = true;
    });
  }

  Future<void> _showAssignmentDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (_doctorDocs.isEmpty) {
      Get.snackbar(
        'No doctors available',
        'Create or assign at least one doctor account before assigning referrals.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    final data = doc.data();
    String? selectedDoctorUid = (data['assignedDoctorUid'] ?? '').toString();
    String? smartSuggestedDoctorUid;
    DoctorAssignmentSuggestion? smartSuggestion;
    final reviewNotesController = TextEditingController(
      text: (data['choReviewNotes'] ?? '').toString(),
    );
    String status = (data['status'] ?? 'under_review').toString();
    bool isLoadingSuggestion = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: _panelSurface,
              title: const Text(
                'Assign Doctor',
                style: TextStyle(color: _lightOffWhite),
              ),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue:
                          selectedDoctorUid == null ||
                              selectedDoctorUid!.isEmpty
                          ? null
                          : selectedDoctorUid,
                      dropdownColor: _panelAlt,
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: _inputDecoration('Assigned doctor'),
                      items: _doctorDocs.map((doctorDoc) {
                        final doctorData = doctorDoc.data();
                        final label =
                            '${_doctorDisplayName(doctorData)} • ${_doctorSpecialization(doctorData)} • ${_doctorAvailabilityLabel(_doctorAvailability(doctorData))}';
                        return DropdownMenuItem<String>(
                          value: doctorDoc.id,
                          child: Text(label, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedDoctorUid = value;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _panelAlt,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _primaryAqua.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Automatic doctor assignment',
                                  style: TextStyle(
                                    color: _lightOffWhite,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: isLoadingSuggestion
                                    ? null
                                    : () async {
                                        setDialogState(
                                          () => isLoadingSuggestion = true,
                                        );
                                        try {
                                          final suggestionResult =
                                              await _accountPolicyService
                                                  .suggestDoctorAssignment(
                                                    referralId: doc.id,
                                                  );
                                          if (!dialogContext.mounted) return;
                                          setDialogState(() {
                                            smartSuggestion =
                                                suggestionResult.recommendation;
                                            smartSuggestedDoctorUid =
                                                smartSuggestion?.doctorUid;
                                            if (smartSuggestion != null) {
                                              selectedDoctorUid =
                                                  smartSuggestion!.doctorUid;
                                              if (status == 'under_review') {
                                                status = 'assigned';
                                              }
                                            }
                                            isLoadingSuggestion = false;
                                          });
                                          if (suggestionResult.recommendation ==
                                              null) {
                                            Get.snackbar(
                                              'No recommendation available',
                                              'No eligible doctor could be suggested yet. You can still assign manually.',
                                              backgroundColor: Colors.orange,
                                              colorText: Colors.white,
                                            );
                                          }
                                        } catch (e) {
                                          if (!dialogContext.mounted) return;
                                          setDialogState(
                                            () => isLoadingSuggestion = false,
                                          );
                                          Get.snackbar(
                                            'Suggestion unavailable',
                                            'Could not compute a doctor recommendation: $e',
                                            backgroundColor: Colors.redAccent,
                                            colorText: Colors.white,
                                          );
                                        }
                                      },
                                icon: isLoadingSuggestion
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.auto_awesome_outlined),
                                label: Text(
                                  isLoadingSuggestion
                                      ? 'Analyzing'
                                      : 'Suggest best match',
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _primaryAqua,
                                  side: BorderSide(
                                    color: _primaryAqua.withValues(alpha: 0.32),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            smartSuggestion == null
                                ? 'Use the eligible doctor with the lowest active referral workload, then save or override manually.'
                                : 'Recommended: ${smartSuggestion!.doctorName} • ${smartSuggestion!.specialization} • workload ${smartSuggestion!.workload}',
                            style: TextStyle(
                              color: _lightOffWhite.withValues(alpha: 0.76),
                              height: 1.4,
                            ),
                          ),
                          if (smartSuggestion != null) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: smartSuggestion!.rationale
                                  .map(
                                    (reason) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _panelAlt,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        reason,
                                        style: const TextStyle(
                                          color: _lightOffWhite,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      dropdownColor: _panelAlt,
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: _inputDecoration('Referral status'),
                      items:
                          const <String>[
                                'under_review',
                                'assigned',
                                'in_treatment',
                                'completed',
                              ]
                              .map(
                                (value) => DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value.replaceAll('_', ' ')),
                                ),
                              )
                              .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => status = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: reviewNotesController,
                      maxLines: 4,
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: _inputDecoration('CHO review notes'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (selectedDoctorUid == null ||
                        selectedDoctorUid!.isEmpty) {
                      Get.snackbar(
                        'Doctor required',
                        'Select a doctor before saving the assignment.',
                        backgroundColor: Colors.orange,
                        colorText: Colors.white,
                      );
                      return;
                    }

                    final doctorDoc = _doctorDocs.firstWhere(
                      (entry) => entry.id == selectedDoctorUid,
                    );
                    final doctorData = doctorDoc.data();
                    final updatePayload = <String, dynamic>{
                      'assignedDoctorUid': doctorDoc.id,
                      'assignedDoctorName': _doctorDisplayName(doctorData),
                      'assignedDoctorEmail': (doctorData['email'] ?? '')
                          .toString(),
                      'assignedDoctorSpecialization': _doctorSpecialization(
                        doctorData,
                      ),
                      'assignedDoctorAvailability': _doctorAvailability(
                        doctorData,
                      ),
                      'assignmentMode':
                          selectedDoctorUid == smartSuggestedDoctorUid
                          ? 'smart'
                          : 'manual',
                      'assignmentSource':
                          selectedDoctorUid == smartSuggestedDoctorUid
                          ? 'cho_auto'
                          : 'cho_selected',
                      'assignmentRationale':
                          selectedDoctorUid == smartSuggestedDoctorUid &&
                              smartSuggestion != null
                          ? smartSuggestion!.rationale.join(' | ')
                          : 'Assigned manually by CHO operator.',
                      'assignmentScore':
                          selectedDoctorUid == smartSuggestedDoctorUid &&
                              smartSuggestion != null
                          ? smartSuggestion!.score
                          : null,
                      'assignedByUid': FirebaseAuth.instance.currentUser?.uid,
                      'assignedAt': FieldValue.serverTimestamp(),
                      'choReviewNotes': reviewNotesController.text.trim(),
                      'status': status,
                      'updatedAt': FieldValue.serverTimestamp(),
                    };
                    final nextVersion = await _writeCoordinator.update(
                      reference: doc.reference,
                      changes: updatePayload,
                      expectedVersion: recordVersionOf(data),
                    );
                    await _syncBarangayReferralMirror(
                      referralId: doc.id,
                      payload: {
                        ...data,
                        ...updatePayload,
                        'recordVersion': nextVersion,
                      },
                    );

                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    Get.snackbar(
                      'Assignment saved',
                      'The doctor assignment is now visible to CHO, the doctor, and the referring BHW.',
                      backgroundColor: Colors.green,
                      colorText: Colors.white,
                    );
                  },
                  child: const Text('Save assignment'),
                ),
              ],
            );
          },
        );
      },
    );

    reviewNotesController.dispose();
  }

  Future<void> _showDoctorUpdateDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final diagnosisController = TextEditingController(
      text: (data['doctorDiagnosis'] ?? '').toString(),
    );
    final treatmentController = TextEditingController(
      text: (data['doctorTreatment'] ?? '').toString(),
    );
    final medicationController = TextEditingController(
      text: (data['doctorMedication'] ?? '').toString(),
    );
    final notesController = TextEditingController(
      text: (data['doctorNotes'] ?? '').toString(),
    );
    String status = _normalizedDoctorCareStatus(data['status']);
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: _panelSurface,
              title: const Text(
                'Update Patient Care',
                style: TextStyle(color: _lightOffWhite),
              ),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: diagnosisController,
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: _inputDecoration('Diagnosis'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: treatmentController,
                      maxLines: 3,
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: _inputDecoration('Treatment plan'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: medicationController,
                      maxLines: 2,
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: _inputDecoration('Medication'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      maxLines: 4,
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: _inputDecoration('Doctor notes'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      dropdownColor: _panelAlt,
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: _inputDecoration('Case status'),
                      items: _allowedDoctorCareStatuses(status)
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value.replaceAll('_', ' ')),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => status = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() => isSaving = true);
                          try {
                            final updatePayload = <String, dynamic>{
                              'doctorDiagnosis': diagnosisController.text
                                  .trim(),
                              'doctorTreatment': treatmentController.text
                                  .trim(),
                              'doctorMedication': medicationController.text
                                  .trim(),
                              'doctorNotes': notesController.text.trim(),
                              'status': status,
                              'doctorUpdatedAt': FieldValue.serverTimestamp(),
                              'updatedAt': FieldValue.serverTimestamp(),
                              if (status == 'completed') ...{
                                'completionStatus': 'completed',
                                'completedAt': FieldValue.serverTimestamp(),
                                'completedByDoctorUid':
                                    FirebaseAuth.instance.currentUser?.uid,
                                'completedByDoctorName':
                                    FirebaseAuth
                                        .instance
                                        .currentUser
                                        ?.displayName ??
                                    FirebaseAuth.instance.currentUser?.email,
                              },
                            };
                            final nextVersion = await _writeCoordinator.update(
                              reference: doc.reference,
                              changes: updatePayload,
                              expectedVersion: recordVersionOf(data),
                            );
                            await _syncBarangayReferralMirror(
                              referralId: doc.id,
                              payload: {
                                ...data,
                                ...updatePayload,
                                'recordVersion': nextVersion,
                              },
                            );

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                            Get.snackbar(
                              status == 'completed'
                                  ? 'Referral completed'
                                  : 'Care updated',
                              status == 'completed'
                                  ? 'The referral is marked completed and synchronized to CHO and the referring BHW.'
                                  : 'Your diagnosis, treatment, and medication updates are now synchronized to CHO and the referring BHW.',
                              backgroundColor: Colors.green,
                              colorText: Colors.white,
                            );
                          } catch (error) {
                            if (dialogContext.mounted) {
                              setDialogState(() => isSaving = false);
                            }
                            Get.snackbar(
                              'Care update failed',
                              'The referral was not changed. Please try again.',
                              backgroundColor: Colors.redAccent,
                              colorText: Colors.white,
                            );
                          }
                        },
                  style: AppButtonStyles.primary(),
                  child: Text(isSaving ? 'Saving...' : 'Save update'),
                ),
              ],
            );
          },
        );
      },
    );

    diagnosisController.dispose();
    treatmentController.dispose();
    medicationController.dispose();
    notesController.dispose();
  }

  String _normalizedDoctorCareStatus(Object? value) {
    switch (value?.toString().trim().toLowerCase()) {
      case 'assigned':
      case 'hospital_assigned':
      case 'doctor_assigned':
        return 'doctor_assigned';
      case 'waiting_consultation':
        return 'waiting_consultation';
      case 'in_treatment':
      case 'consulted':
        return 'consulted';
      case 'completed':
        return 'completed';
      default:
        return 'doctor_assigned';
    }
  }

  List<String> _allowedDoctorCareStatuses(String currentStatus) {
    switch (_normalizedDoctorCareStatus(currentStatus)) {
      case 'doctor_assigned':
        return _doctorCareStatuses.take(3).toList(growable: false);
      case 'waiting_consultation':
        return _doctorCareStatuses.skip(1).take(2).toList(growable: false);
      case 'consulted':
        return _doctorCareStatuses.skip(2).toList(growable: false);
      case 'completed':
        return const <String>['completed'];
      default:
        return const <String>['doctor_assigned'];
    }
  }

  String? _requiredValidator(String label, String? value) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required';
    }
    return null;
  }

  Future<void> _pickReferralDateTime() async {
    final initialDateTime = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initialDateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDateTime),
    );
    if (time == null) {
      return;
    }

    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    _referralDateTimeController.text = _formatDateTimeInput(selected);
  }

  String _formatDateTimeInput(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _mutedCoolGray),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD9E5F2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD9E5F2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _primaryAqua, width: 2),
      ),
    );
  }

  String _formatTimestamp(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return 'Pending sync';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.greenAccent;
      case 'in_treatment':
        return Colors.amberAccent;
      case 'assigned':
        return Colors.lightBlueAccent;
      case 'under_review':
        return Colors.orangeAccent;
      default:
        return Colors.redAccent;
    }
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortedDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = docs.toList();
    sorted.sort((a, b) {
      final aTs = a.data()['updatedAt'];
      final bTs = b.data()['updatedAt'];
      final aMs = aTs is Timestamp ? aTs.millisecondsSinceEpoch : 0;
      final bMs = bTs is Timestamp ? bTs.millisecondsSinceEpoch : 0;
      return bMs.compareTo(aMs);
    });
    return sorted;
  }

  Widget _buildHeader() {
    final title = _isChoOperator
        ? 'CHO Referral Command Center'
        : _isDoctor
        ? 'Assigned Clinical Referrals'
        : 'Barangay Referral Workflow';
    final subtitle = _isChoOperator
        ? 'Receive referrals in real time, review them centrally, and assign the right doctor for each patient.'
        : _isDoctor
        ? 'Manage assigned referrals, document diagnosis and treatment, and keep CHO and BHW teams synchronized.'
        : 'Submit referrals to CHO, monitor doctor assignment, and follow the patient care lifecycle end to end.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _lightOffWhite,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.76),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoctorDecisionSupport(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) {
    final urgent = documents.where((document) {
      final priority =
          (document.data()['priority'] ??
                  document.data()['referralPriority'] ??
                  '')
              .toString()
              .toLowerCase();
      return priority.contains('urgent') || priority.contains('emergency');
    }).length;
    final awaitingReview = documents.where((document) {
      final status = (document.data()['status'] ?? '').toString().toLowerCase();
      return status.contains('assigned') ||
          status.contains('waiting') ||
          status.contains('review');
    }).length;

    return RoleDecisionSupportPanel(
      audience: DecisionSupportAudience.doctor,
      summary:
          'The queue summarizes information submitted by BHW and CHO users. Confirm symptoms, vitals, history, and urgency before documenting care.',
      items: <DecisionSupportItem>[
        DecisionSupportItem(
          label: 'Assigned cases',
          value: '${documents.length}',
          icon: Icons.assignment_ind_outlined,
        ),
        DecisionSupportItem(
          label: 'Urgent flags',
          value: '$urgent',
          icon: Icons.emergency_outlined,
          isPriority: urgent > 0,
        ),
        DecisionSupportItem(
          label: 'Awaiting clinical review',
          value: '$awaitingReview',
          icon: Icons.medical_information_outlined,
          isPriority: awaitingReview > 0,
        ),
      ],
    );
  }

  Widget _buildReferralForm() {
    if (!_isBhw) {
      return const SizedBox.shrink();
    }

    if (_selectedPatientSeed == null) {
      return _buildReferralPatientGate();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
      ),
      child: Form(
        key: _referralFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Submit Referral',
              style: TextStyle(
                color: _lightOffWhite,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This referral is automatically scoped to ${_scope.barangay}. CHO receives it instantly and can assign a doctor for follow-through care.',
              style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.72)),
            ),
            const SizedBox(height: 18),
            _buildFormSectionTitle('Referral Type'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _referralCategoryOptions
                  .map(
                    (option) => _buildCheckboxOption(
                      label: option,
                      selected: _selectedReferralCategories.contains(option),
                      onChanged: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedReferralCategories.add(option);
                          } else {
                            _selectedReferralCategories.remove(option);
                          }
                        });
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 16),
            _buildPatientReusePanel(),
            const SizedBox(height: 12),
            _buildSizedInput(
              width: 240,
              child: TextFormField(
                controller: _referralDateTimeController,
                readOnly: true,
                onTap: _pickReferralDateTime,
                style: const TextStyle(color: _lightOffWhite),
                decoration: _inputDecoration('Date & Time').copyWith(
                  suffixIcon: const Icon(
                    Icons.event_outlined,
                    color: _lightOffWhite,
                  ),
                ),
                validator: (value) => _requiredValidator('Date & Time', value),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _patientAddressController,
              maxLines: 2,
              style: const TextStyle(color: _lightOffWhite),
              decoration: _inputDecoration('Address'),
              validator: (value) => _requiredValidator('Address', value),
            ),
            const SizedBox(height: 16),
            _buildFormSectionTitle("Patient's Name"),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildSizedInput(
                  width: 220,
                  child: TextFormField(
                    controller: _patientSurnameController,
                    style: const TextStyle(color: _lightOffWhite),
                    decoration: _inputDecoration('Surname'),
                    validator: (value) => _requiredValidator('Surname', value),
                  ),
                ),
                _buildSizedInput(
                  width: 220,
                  child: TextFormField(
                    controller: _patientFirstNameController,
                    style: const TextStyle(color: _lightOffWhite),
                    decoration: _inputDecoration('First Name'),
                    validator: (value) =>
                        _requiredValidator('First Name', value),
                  ),
                ),
                _buildSizedInput(
                  width: 220,
                  child: TextFormField(
                    controller: _patientMiddleNameController,
                    style: const TextStyle(color: _lightOffWhite),
                    decoration: _inputDecoration('Middle Name'),
                  ),
                ),
                _buildSizedInput(
                  width: 120,
                  child: TextFormField(
                    controller: _patientAgeController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: _lightOffWhite),
                    decoration: _inputDecoration('Age'),
                    validator: (value) => _requiredValidator('Age', value),
                  ),
                ),
                _buildSizedInput(
                  width: 140,
                  child: TextFormField(
                    controller: _patientSexController,
                    style: const TextStyle(color: _lightOffWhite),
                    decoration: _inputDecoration('Sex'),
                    validator: (value) => _requiredValidator('Sex', value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _chiefComplaintController,
              maxLines: 3,
              style: const TextStyle(color: _lightOffWhite),
              decoration: _inputDecoration('Chief Complaints'),
              validator: (value) =>
                  _requiredValidator('Chief Complaints', value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _medicalHistoryController,
              maxLines: 3,
              style: const TextStyle(color: _lightOffWhite),
              decoration: _inputDecoration('Medical History'),
              validator: (value) =>
                  _requiredValidator('Medical History', value),
            ),
            const SizedBox(height: 12),
            _buildYesNoSelector(
              label: 'Surgical Operations?',
              value: _hasSurgicalOperations,
              onChanged: (value) {
                setState(() {
                  _hasSurgicalOperations = value;
                  if (!value) {
                    _surgicalProcedureController.clear();
                  }
                });
              },
            ),
            if (_hasSurgicalOperations == true) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _surgicalProcedureController,
                style: const TextStyle(color: _lightOffWhite),
                decoration: _inputDecoration('What procedure'),
                validator: (value) => _hasSurgicalOperations == true
                    ? _requiredValidator('What procedure', value)
                    : null,
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastMealTimeController,
              style: const TextStyle(color: _lightOffWhite),
              decoration: _inputDecoration('Last Meal Time'),
              validator: (value) => _requiredValidator('Last Meal Time', value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _completeVitalSignsController,
              maxLines: 3,
              style: const TextStyle(color: _lightOffWhite),
              decoration: _inputDecoration('Complete Vital Signs'),
              validator: (value) =>
                  _requiredValidator('Complete Vital Signs', value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _impressionController,
              maxLines: 3,
              style: const TextStyle(color: _lightOffWhite),
              decoration: _inputDecoration('Impression'),
              validator: (value) => _requiredValidator('Impression', value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _actionTakenController,
              maxLines: 3,
              style: const TextStyle(color: _lightOffWhite),
              decoration: _inputDecoration('Action taken (phone/RECO)'),
              validator: (value) =>
                  _requiredValidator('Action taken (phone/RECO)', value),
            ),
            const SizedBox(height: 12),
            _buildYesNoSelector(
              label: 'Health Insurance Coverage?',
              value: _hasHealthInsuranceCoverage,
              onChanged: (value) {
                setState(() {
                  _hasHealthInsuranceCoverage = value;
                  if (!value) {
                    _healthInsuranceCoverageTypeController.clear();
                  }
                });
              },
            ),
            if (_hasHealthInsuranceCoverage == true) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _healthInsuranceCoverageTypeController,
                style: const TextStyle(color: _lightOffWhite),
                decoration: _inputDecoration('State type of coverage'),
                validator: (value) => _hasHealthInsuranceCoverage == true
                    ? _requiredValidator('State type of coverage', value)
                    : null,
              ),
            ],
            const SizedBox(height: 16),
            _buildFormSectionTitle('Reason for Referral'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _referralReasonOptions
                  .map(
                    (option) => _buildCheckboxOption(
                      label: option,
                      selected: _selectedReferralReasons.contains(option),
                      onChanged: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedReferralReasons.add(option);
                          } else {
                            _selectedReferralReasons.remove(option);
                            if (option == 'Others') {
                              _referralReasonOtherController.clear();
                            }
                          }
                        });
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
            if (_selectedReferralReasons.contains('Others')) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _referralReasonOtherController,
                maxLines: 2,
                style: const TextStyle(color: _lightOffWhite),
                decoration: _inputDecoration('Other reason for referral'),
                validator: (value) =>
                    _selectedReferralReasons.contains('Others')
                    ? _requiredValidator('Other reason for referral', value)
                    : null,
              ),
            ],
            const SizedBox(height: 18),
            _buildDoctorMatchingPanel(),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitReferral,
                icon: const Icon(Icons.send_outlined),
                label: Text(_isSubmitting ? 'Submitting...' : 'Send referral'),
                style: AppButtonStyles.primary(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferralPatientGate() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _primaryAqua.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_search_rounded,
              color: _primaryAqua,
              size: 34,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Select a patient before creating a referral',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _lightOffWhite,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Search the Patient registry first. If the person is not registered, create the patient record before encoding referral details.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.68),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _selectReferralPatient,
            style: AppButtonStyles.primary(),
            icon: const Icon(Icons.search_rounded),
            label: const Text('Search and Select Patient'),
          ),
        ],
      ),
    );
  }

  Future<void> _selectReferralPatient() async {
    final patient = await PatientFirstServiceSelector.selectRegisteredPatient(
      context,
      serviceLabel: 'Referral',
      patientService: _patientHistoryService,
      onRegisterPatient: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PatientRecordPage(openRegistrationOnLoad: true),
        ),
      ),
    );
    if (!mounted || patient == null) return;
    _applyPatientSeed(patient);
  }

  Widget _buildDoctorMatchingPanel() {
    final availableDoctors = _availableDoctorDocs;
    final selectedDoctor = _selectedPreferredDoctorData;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panelAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Doctor Matching',
            style: TextStyle(
              color: _lightOffWhite,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isBhw
                ? 'The system assigns each BHW referral to an approved, active, available doctor using the lowest active referral workload. CHO Admin can reassign later.'
                : 'Choose a doctor directly when needed, or leave it open for automatic assignment to the eligible doctor with the lowest active referral workload.',
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.76),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          if (_isBhw)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _panelSurface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Automatic assignment is enabled for BHW referrals. Doctor selection is controlled by the CHO Admin workflow.',
                style: TextStyle(color: _lightOffWhite),
              ),
            )
          else if (availableDoctors.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _panelSurface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'No doctor accounts are available yet. You can still submit the referral and CHO can assign it later.',
                style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.76)),
              ),
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedPreferredDoctorUid,
              dropdownColor: _panelAlt,
              style: const TextStyle(color: _lightOffWhite),
              decoration: _inputDecoration('Preferred doctor (optional)'),
              items: <DropdownMenuItem<String>>[
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('Let AI choose the best doctor'),
                ),
                ...availableDoctors.map((doctorDoc) {
                  final doctorData = doctorDoc.data();
                  final label =
                      '${_doctorDisplayName(doctorData)} • ${_doctorSpecialization(doctorData)} • ${_doctorAvailabilityLabel(_doctorAvailability(doctorData))}';
                  return DropdownMenuItem<String>(
                    value: doctorDoc.id,
                    child: Text(label, overflow: TextOverflow.ellipsis),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedPreferredDoctorUid = value == null || value.isEmpty
                      ? null
                      : value;
                });
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _panelSurface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    color: _primaryAqua,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _autoAssignDoctor,
                          activeThumbColor: _primaryAqua,
                          title: const Text(
                            'Use automatic assignment',
                            style: TextStyle(color: _lightOffWhite),
                          ),
                          subtitle: Text(
                            _selectedPreferredDoctorUid == null
                                ? 'The system will assign the eligible doctor with the lowest active referral workload after submission.'
                                : 'Keep this on if you want the server to validate and finalize the selected doctor immediately.',
                            style: TextStyle(
                              color: _lightOffWhite.withValues(alpha: 0.68),
                            ),
                          ),
                          onChanged: (value) {
                            setState(() => _autoAssignDoctor = value);
                          },
                        ),
                        if (selectedDoctor != null) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildInfoChip(
                                _doctorDisplayName(selectedDoctor),
                              ),
                              _buildInfoChip(
                                _doctorSpecialization(selectedDoctor),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _doctorAvailabilityColor(
                                    _doctorAvailability(selectedDoctor),
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: _doctorAvailabilityColor(
                                      _doctorAvailability(selectedDoctor),
                                    ).withValues(alpha: 0.32),
                                  ),
                                ),
                                child: Text(
                                  _doctorAvailabilityLabel(
                                    _doctorAvailability(selectedDoctor),
                                  ),
                                  style: TextStyle(
                                    color: _doctorAvailabilityColor(
                                      _doctorAvailability(selectedDoctor),
                                    ),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPatientReusePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFormSectionTitle('Existing Barangay Patient Record'),
        TextField(
          controller: _patientLookupController,
          onChanged: (value) {
            setState(() {});
            _scheduleSharedPatientSearch(value);
          },
          style: const TextStyle(color: _lightOffWhite),
          decoration: _inputDecoration('Search patient by name or record ID')
              .copyWith(
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: _mutedCoolGray,
                ),
                suffixIcon: _patientLookupController.text.trim().isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _patientLookupController.clear();
                          _scheduleSharedPatientSearch('');
                          setState(() => _selectedPatientSeed = null);
                        },
                        icon: const Icon(
                          Icons.clear_rounded,
                          color: _lightOffWhite,
                        ),
                      ),
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Reuse an existing patient from ${_scope.barangay} to reduce encoding time and keep demographic data consistent.',
          style: TextStyle(
            color: _lightOffWhite.withValues(alpha: 0.72),
            height: 1.4,
          ),
        ),
        if (_selectedPatientSeed != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildInfoChip(
                (_selectedPatientSeed!['patientName'] ??
                        _selectedPatientSeed!['name'] ??
                        'Selected patient')
                    .toString(),
              ),
              if ((_selectedPatientSeed!['patientId'] ?? '')
                  .toString()
                  .isNotEmpty)
                _buildInfoChip(
                  'Record ${(_selectedPatientSeed!['patientId'] ?? '').toString()}',
                ),
            ],
          ),
        ],
        if (_patientLookupController.text.trim().isNotEmpty ||
            _isSearchingSharedPatients) ...[
          const SizedBox(height: 12),
          SharedPatientSearchPanel(
            query: _patientLookupController.text,
            results: _sharedPatientMatches,
            isLoading: _isSearchingSharedPatients,
            primaryActionLabel: 'View Medical History',
            onPrimaryAction: _showSharedPatientTimeline,
            secondaryActionLabel: 'Use Patient Record',
            onSecondaryAction: _applyPatientSeed,
          ),
        ],
      ],
    );
  }

  Widget _buildSizedInput({required double width, required Widget child}) {
    return SizedBox(width: width, child: child);
  }

  Widget _buildFormSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          color: _lightOffWhite.withValues(alpha: 0.9),
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildCheckboxOption({
    required String label,
    required bool selected,
    required ValueChanged<bool> onChanged,
  }) {
    return SizedBox(
      width: 210,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(!selected),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? _primaryAqua.withValues(alpha: 0.14)
                : _darkDeepTeal,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _primaryAqua.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: selected,
                onChanged: (value) => onChanged(value ?? false),
                fillColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? _primaryAqua
                      : Colors.transparent,
                ),
                checkColor: _darkDeepTeal,
                side: BorderSide(color: _primaryAqua.withValues(alpha: 0.36)),
              ),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: _lightOffWhite),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildYesNoSelector({
    required String label,
    required bool? value,
    required ValueChanged<bool> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _lightOffWhite.withValues(alpha: 0.9),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildCheckboxOption(
              label: 'Yes',
              selected: value == true,
              onChanged: (_) => onChanged(true),
            ),
            _buildCheckboxOption(
              label: 'No',
              selected: value == false,
              onChanged: (_) => onChanged(false),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCards(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    int submitted = 0;
    int assigned = 0;
    int inTreatment = 0;
    int completed = 0;

    for (final doc in docs) {
      switch ((doc.data()['status'] ?? 'submitted').toString()) {
        case 'assigned':
          assigned++;
          break;
        case 'in_treatment':
          inTreatment++;
          break;
        case 'completed':
          completed++;
          break;
        default:
          submitted++;
      }
    }

    final cards = <Widget>[
      _buildSummaryCard(
        'Visible referrals',
        '${docs.length}',
        Icons.folder_shared_outlined,
      ),
      _buildSummaryCard('Submitted', '$submitted', Icons.outbox_outlined),
      _buildSummaryCard(
        'Assigned / Active',
        '${assigned + inTreatment}',
        Icons.assignment_ind_outlined,
      ),
      _buildSummaryCard('Completed', '$completed', Icons.verified_outlined),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1180
            ? 4
            : constraints.maxWidth >= 680
            ? 2
            : 1;
        const spacing = 12.0;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map((card) => SizedBox(width: width, child: card))
              .toList(growable: false),
        );
      },
    );
  }

  Widget _buildSummaryCard(String label, String value, IconData icon) {
    return AppMetricCard(label: label, value: value, icon: icon);
  }

  List<String> _readStringList(dynamic value) {
    if (value is Iterable) {
      return value
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) {
      return const <String>[];
    }
    return text
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  bool? _readNullableBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    final normalized = (value ?? '').toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == 'no') {
      return false;
    }
    return null;
  }

  String _displayPatientName(Map<String, dynamic> data) {
    final surname = (data['patientSurname'] ?? '').toString().trim();
    final firstName = (data['patientFirstName'] ?? '').toString().trim();
    final middleName = (data['patientMiddleName'] ?? '').toString().trim();
    final combined = <String>[
      firstName,
      if (middleName.isNotEmpty) middleName,
    ].where((value) => value.isNotEmpty).join(' ');
    if (surname.isNotEmpty && combined.isNotEmpty) {
      return '$surname, $combined';
    }
    final storedName = (data['patientName'] ?? '').toString().trim();
    return storedName.isEmpty ? 'Unnamed patient' : storedName;
  }

  String _displayYesNo(bool? value, {String fallback = 'Not specified'}) {
    if (value == null) {
      return fallback;
    }
    return value ? 'Yes' : 'No';
  }

  Widget _buildReferralCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = attachWebSyncMetadata(
      <String, dynamic>{...doc.data(), 'id': doc.id},
      hasPendingWrites: doc.metadata.hasPendingWrites,
      isFromCache: doc.metadata.isFromCache,
    );
    final status = (data['status'] ?? 'submitted').toString();
    final doctorName = (data['assignedDoctorName'] ?? 'Unassigned').toString();
    final doctorSpecialization = (data['assignedDoctorSpecialization'] ?? '')
        .toString()
        .trim();
    final doctorDiagnosis = (data['doctorDiagnosis'] ?? '').toString();
    final doctorTreatment = (data['doctorTreatment'] ?? '').toString();
    final doctorMedication = (data['doctorMedication'] ?? '').toString();
    final assignmentMode = (data['assignmentMode'] ?? 'manual').toString();
    final assignmentSource = (data['assignmentSource'] ?? '').toString();
    final assignmentRationale = (data['assignmentRationale'] ?? '').toString();
    final patientName = _displayPatientName(data);
    final referralCategories = _readStringList(data['referralCategories']);
    final hasSurgicalOperations = _readNullableBool(
      data['hasSurgicalOperations'],
    );
    final hasHealthInsuranceCoverage = _readNullableBool(
      data['hasHealthInsuranceCoverage'],
    );
    final surgicalProcedure = (data['surgicalProcedure'] ?? '')
        .toString()
        .trim();
    final healthInsuranceCoverageType =
        (data['healthInsuranceCoverageType'] ?? '').toString().trim();
    final referralType = referralCategories.isEmpty
        ? 'Not selected'
        : referralCategories.join(', ');
    final referredTo = (data['referredTo'] ?? 'Not provided').toString();
    final effectiveReferredTo = doctorName != 'Unassigned'
        ? doctorName
        : referredTo.isEmpty
        ? 'System-assigned doctor'
        : referredTo;
    final referralDateTime = (data['referralDateTime'] ?? 'Not provided')
        .toString();
    final patientAddress = (data['patientAddress'] ?? 'Not provided')
        .toString();
    final medicalHistory = (data['medicalHistory'] ?? 'Not provided')
        .toString();
    final completeVitalSigns = (data['completeVitalSigns'] ?? 'Not provided')
        .toString();
    final impression =
        ((data['impression'] ?? data['currentDiagnosis']) ?? 'Not provided')
            .toString();
    final actionTaken =
        ((data['actionTaken'] ?? data['currentTreatment']) ?? 'Not provided')
            .toString();
    final lastMealTime = (data['lastMealTime'] ?? 'Not provided').toString();
    final referralReason = (data['referralReason'] ?? 'Not provided')
        .toString();
    final surgicalSummary =
        hasSurgicalOperations == true && surgicalProcedure.isNotEmpty
        ? 'Yes - $surgicalProcedure'
        : _displayYesNo(hasSurgicalOperations);
    final insuranceSummary =
        hasHealthInsuranceCoverage == true &&
            healthInsuranceCoverageType.isNotEmpty
        ? 'Yes - $healthInsuranceCoverageType'
        : _displayYesNo(hasHealthInsuranceCoverage);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                patientName,
                style: const TextStyle(
                  color: _lightOffWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              _buildStatusChip(status),
              WebSyncStatusBadge(record: data),
              if ((data['barangay'] ?? '').toString().isNotEmpty)
                _buildInfoChip((data['barangay'] ?? '').toString()),
              _buildInfoChip('Doctor: $doctorName'),
              if (doctorSpecialization.isNotEmpty)
                _buildInfoChip(doctorSpecialization),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _buildMetaBlock('Referral type', referralType),
              _buildMetaBlock('Referred to', effectiveReferredTo),
              _buildMetaBlock('Date & Time', referralDateTime),
              _buildMetaBlock(
                'Age / Sex',
                '${(data['patientAge'] ?? 'N/A').toString()} / ${(data['patientSex'] ?? 'N/A').toString()}',
              ),
              _buildMetaBlock('Address', patientAddress),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Chief complaints: ${(data['chiefComplaint'] ?? 'No complaint').toString()}',
            style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.88)),
          ),
          const SizedBox(height: 6),
          Text(
            'Medical history: $medicalHistory',
            style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _buildMetaBlock('Last Meal Time', lastMealTime),
              _buildMetaBlock('Complete Vital Signs', completeVitalSigns),
              _buildMetaBlock('Impression', impression),
              _buildMetaBlock('Action taken (phone/RECO)', actionTaken),
              _buildMetaBlock('Surgical Operations', surgicalSummary),
              _buildMetaBlock('Health Insurance Coverage', insuranceSummary),
              _buildMetaBlock('Reason for Referral', referralReason),
            ],
          ),
          const SizedBox(height: 12),
          if (_hasDoctorUpdate(data))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _panelAlt,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Doctor update',
                    style: TextStyle(
                      color: _lightOffWhite,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Diagnosis: ${doctorDiagnosis.isEmpty ? 'Pending' : doctorDiagnosis}',
                    style: const TextStyle(color: _lightOffWhite),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Treatment: ${doctorTreatment.isEmpty ? 'Pending' : doctorTreatment}',
                    style: const TextStyle(color: _lightOffWhite),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Medication: ${doctorMedication.isEmpty ? 'Pending' : doctorMedication}',
                    style: const TextStyle(color: _lightOffWhite),
                  ),
                  if ((data['doctorNotes'] ?? '')
                      .toString()
                      .trim()
                      .isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Notes: ${(data['doctorNotes'] ?? '').toString()}',
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Submitted by ${(data['createdByName'] ?? data['createdByEmail'] ?? 'Unknown').toString()} • ${_formatTimestamp(data['createdAt'])}',
            style: const TextStyle(color: _mutedCoolGray),
          ),
          if ((data['choReviewNotes'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'CHO notes: ${(data['choReviewNotes'] ?? '').toString()}',
              style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.76)),
            ),
          ],
          if (assignmentRationale.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${_assignmentModeLabel(assignmentMode, assignmentSource)}: $assignmentRationale',
              style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.72)),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () => _printReferralReport(data),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print form'),
                style: AppButtonStyles.outline(),
              ),
              if (_isChoOperator)
                OutlinedButton.icon(
                  onPressed: () => _showAssignmentDialog(doc),
                  icon: const Icon(Icons.assignment_ind_outlined),
                  label: const Text('Assign doctor'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryAqua,
                    side: BorderSide(
                      color: _primaryAqua.withValues(alpha: 0.32),
                    ),
                  ),
                ),
              if (_isDoctor)
                OutlinedButton.icon(
                  onPressed: () => _showDoctorUpdateDialog(doc),
                  icon: const Icon(Icons.medical_information_outlined),
                  label: const Text('Update care'),
                  style: AppButtonStyles.outline(),
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool _hasDoctorUpdate(Map<String, dynamic> data) {
    return (data['doctorDiagnosis'] ?? '').toString().trim().isNotEmpty ||
        (data['doctorTreatment'] ?? '').toString().trim().isNotEmpty ||
        (data['doctorMedication'] ?? '').toString().trim().isNotEmpty ||
        (data['doctorNotes'] ?? '').toString().trim().isNotEmpty;
  }

  Widget _buildMetaBlock(String label, String value) {
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _mutedCoolGray)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: _lightOffWhite)),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _statusColor(status).withValues(alpha: 0.32)),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          color: _statusColor(status),
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _panelAlt,
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(color: _lightOffWhite, fontSize: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : user?.email?.split('@').first ?? 'User';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F7FA),
      drawer: _isDoctor
          ? null
          : WebAppSidebar(
              userName: userName,
              activeItem: WebSidebarItem.referrals,
              forceExpanded: true,
            ),
      appBar: AppBar(
        backgroundColor: _darkDeepTeal,
        title: const Text('Referral Management'),
        leading: _isDoctor
            ? null
            : IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
        actions: [
          IconButton(
            onPressed: _loadScope,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryAqua))
          : _loadErrorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.orangeAccent,
                      size: 42,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _loadErrorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _lightOffWhite),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadScope,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _referralsStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_off_outlined,
                            color: _primaryAqua,
                            size: 42,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Referral records could not be loaded. Check your connection and try again.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _lightOffWhite),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => setState(() {}),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _primaryAqua),
                  );
                }

                final docs = _sortedDocs(snapshot.data!.docs);
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 20),
                      if (_isDoctor) ...[
                        _buildDoctorDecisionSupport(docs),
                        const SizedBox(height: 20),
                      ],
                      _buildReferralForm(),
                      if (_isBhw) const SizedBox(height: 20),
                      _buildSummaryCards(docs),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: _panelSurface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _primaryAqua.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Live Referral Queue',
                              style: TextStyle(
                                color: _lightOffWhite,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isChoOperator
                                  ? 'CHO can review all referred patients and route them to doctors in real time.'
                                  : _isDoctor
                                  ? 'Only referrals assigned to you appear here.'
                                  : 'Your submitted referrals remain visible here as CHO and doctors update patient care.',
                              style: TextStyle(
                                color: _lightOffWhite.withValues(alpha: 0.72),
                              ),
                            ),
                            const SizedBox(height: 18),
                            if (docs.isEmpty)
                              Text(
                                'No referrals available for your role yet.',
                                style: TextStyle(
                                  color: _lightOffWhite.withValues(alpha: 0.72),
                                ),
                              )
                            else
                              ...docs.map(_buildReferralCard),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
