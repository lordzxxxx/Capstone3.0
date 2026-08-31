import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:get/get.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_firestore_paths.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/shared/services/account_policy_service.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_history_dialogs.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_identity_utils.dart';
import 'package:mycapstone_project/app/shared/services/clinical_form_pdf_service.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';
import 'package:mycapstone_project/app/shared/widgets/app_metric_card.dart';
import 'package:mycapstone_project/app/shared/navigation/mobile_routes.dart';

const Color _primaryAqua = AppDesign.blue;
const Color _darkDeepTeal = AppDesign.page;
const Color _panelSurface = AppDesign.surface;
const Color _panelAlt = AppDesign.blueSoft;
const Color _lightOffWhite = AppDesign.ink;
const Color _mutedCoolGray = AppDesign.muted;

class ReferralsPage extends StatefulWidget {
  const ReferralsPage({
    super.key,
    this.initialPatient,
    this.initialObservations,
    this.initialRecord,
  });

  final Map<String, dynamic>? initialPatient;
  final String? initialObservations;
  final Map<String, dynamic>? initialRecord;

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

  FirebaseFirestore get _firestore {
    try {
      return getFirestoreInstance();
    } catch (_) {
      return FirebaseFirestore.instance;
    }
  }

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
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _doctorDocs =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  final Set<String> _selectedReferralCategories = <String>{};
  final Set<String> _selectedReferralReasons = <String>{};
  bool? _hasSurgicalOperations;
  bool? _hasHealthInsuranceCoverage;
  String? _selectedPreferredDoctorUid;
  bool _autoAssignDoctor = true;
  Timer? _sharedPatientSearchDebounce;
  List<Map<String, dynamic>> _sharedPatientMatches = <Map<String, dynamic>>[];
  bool _isSearchingSharedPatients = false;
  Map<String, dynamic>? _selectedPatientSeed;

  int _selectedTab = 0;
  static const List<String> _views = [
    'Dashboard',
    'Create Referral',
    'Referral Records',
    'Follow-up',
  ];
  String _priority = 'routine';
  String _statusFilter = 'all';
  String _priorityFilter = 'all';
  DateTime? _recordsFromDate;
  DateTime? _recordsToDate;
  final TextEditingController _recordSearchController = TextEditingController();
  String _followUpStatusFilter = 'all';
  final TextEditingController _followUpSearchController =
      TextEditingController();

  bool get _isDoctor => _scope.role == 'doctor';
  bool get _isBhw => _scope.role == 'bhw';
  bool get _isChoOperator => _scope.isChoAdmin;

  @override
  void initState() {
    super.initState();
    _referralDateTimeController.text = _formatDateTimeInput(DateTime.now());
    final syncSeed = widget.initialRecord ?? widget.initialPatient;
    if (syncSeed != null) {
      _selectedTab = 1;
      _prefillFromRecordOrPatient(
        syncSeed,
        observations: widget.initialObservations,
      );
    }
    _loadScope();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final seed =
          widget.initialRecord ??
          widget.initialPatient ??
          (Get.arguments is Map<String, dynamic>
              ? Get.arguments as Map<String, dynamic>
              : (Get.arguments is Map
                    ? Map<String, dynamic>.from(Get.arguments as Map)
                    : null));
      if (seed != null) {
        _selectedTab = 1;
        _prefillFromRecordOrPatient(
          seed,
          observations: widget.initialObservations,
        );
      }
    });
  }

  void _applyPatientSeed(Map<String, dynamic> patient) {
    final patientName =
        (patient['patientName'] ?? patient['name'] ?? patient['patient'] ?? '')
            .toString()
            .trim();
    final parts = patientNameParts({
      'firstName': patient['firstName'] ?? patient['first_name'] ?? '',
      'surname': patient['surname'] ?? patient['last_name'] ?? '',
      'fullName': patientName,
    });

    _selectedPatientSeed = {
      ...patient,
      'patientName': patientName,
      'isRegisteredPatient': true,
    };

    _patientLookupController.text = patientName;
    _patientSurnameController.text = parts.surname;
    _patientFirstNameController.text = parts.firstName;
    if ((patient['middleName'] ?? '').toString().trim().isNotEmpty) {
      _patientMiddleNameController.text = (patient['middleName'] ?? '')
          .toString()
          .trim();
    }

    final age = (patient['age'] ?? '').toString().trim();
    if (age.isNotEmpty) {
      _patientAgeController.text = age;
    }

    final gender = (patient['gender'] ?? patient['sex'] ?? '')
        .toString()
        .trim();
    if (gender.isNotEmpty) {
      _patientSexController.text = gender;
    }

    final addr = (patient['address'] ?? '').toString().trim();
    final brgy = (patient['barangay'] ?? '').toString().trim();
    if (addr.isNotEmpty && brgy.isNotEmpty) {
      _patientAddressController.text =
          addr.toLowerCase().contains(brgy.toLowerCase())
          ? addr
          : '$addr, $brgy';
    } else if (addr.isNotEmpty) {
      _patientAddressController.text = addr;
    } else if (brgy.isNotEmpty) {
      _patientAddressController.text = brgy;
    }

    _sharedPatientMatches = <Map<String, dynamic>>[];
    if (mounted) {
      setState(() {});
    }
  }

  void _prefillFromRecordOrPatient(
    Map<String, dynamic> data, {
    String? observations,
  }) {
    _applyPatientSeed(data);

    final symptoms =
        (data['symptoms'] ??
                data['chiefComplaint'] ??
                data['chiefComplaints'] ??
                '')
            .toString()
            .trim();
    final diagnosis =
        (data['diagnosis'] ??
                data['disease'] ??
                data['diseaseType'] ??
                data['impression'] ??
                data['ai_category'] ??
                '')
            .toString()
            .trim();
    final plan =
        (data['plan'] ??
                data['treatment'] ??
                data['treatmentPlan'] ??
                data['actionTaken'] ??
                '')
            .toString()
            .trim();
    final vitalsRaw =
        (data['vitalsigns'] ??
                data['vitalSigns'] ??
                data['completeVitalSigns'] ??
                '')
            .toString()
            .trim();

    if (symptoms.isNotEmpty) {
      _chiefComplaintController.text = symptoms;
    } else if (observations?.isNotEmpty == true) {
      _chiefComplaintController.text = observations!;
    }

    if (diagnosis.isNotEmpty && diagnosis != 'General') {
      _impressionController.text = diagnosis;
    }

    if (plan.isNotEmpty) {
      _actionTakenController.text = plan;
    }

    if (vitalsRaw.isNotEmpty) {
      _completeVitalSignsController.text = vitalsRaw;
    } else {
      final bp = (data['bloodPressure'] ?? data['bp'] ?? '').toString().trim();
      final temp = (data['temperature'] ?? data['temp'] ?? '')
          .toString()
          .trim();
      final hr = (data['heartRate'] ?? data['hr'] ?? '').toString().trim();
      final rr = (data['respiratoryRate'] ?? data['rr'] ?? '')
          .toString()
          .trim();
      final spo2 = (data['oxygenSaturation'] ?? data['spo2'] ?? '')
          .toString()
          .trim();
      final wt = (data['weight'] ?? data['wt'] ?? '').toString().trim();
      final ht = (data['height'] ?? data['ht'] ?? '').toString().trim();
      final parts = <String>[
        if (bp.isNotEmpty) 'BP: $bp',
        if (temp.isNotEmpty) 'Temp: $temp°C',
        if (hr.isNotEmpty) 'HR: $hr bpm',
        if (rr.isNotEmpty) 'RR: $rr',
        if (spo2.isNotEmpty) 'SpO2: $spo2%',
        if (wt.isNotEmpty) 'Weight: $wt kg',
        if (ht.isNotEmpty) 'Height: $ht cm',
      ];
      if (parts.isNotEmpty) {
        _completeVitalSignsController.text = parts.join(' | ');
      }
    }

    final reason = (data['referralReason'] ?? data['reason'] ?? '').toString();
    if (reason.isNotEmpty) {
      if (_referralReasonOptions.contains(reason)) {
        _selectedReferralReasons.add(reason);
      } else {
        _selectedReferralReasons.add('Others');
        _referralReasonOtherController.text = reason;
      }
    } else if (_selectedReferralReasons.isEmpty) {
      _selectedReferralReasons.add('Hospital Capability');
    }

    final severity = (data['ai_severity'] ?? data['priority'] ?? '')
        .toString()
        .toLowerCase();
    final category = (data['ai_category'] ?? '').toString().toLowerCase();
    if (severity == 'critical' ||
        severity == 'emergency' ||
        category.contains('emergency')) {
      _priority = 'emergency';
      _selectedReferralCategories.add('Emergency');
    } else if (severity == 'high' || severity == 'urgent') {
      _priority = 'urgent';
      if (_selectedReferralCategories.isEmpty) {
        _selectedReferralCategories.add('Ambulatory');
      }
    } else {
      _priority = 'routine';
      if (_selectedReferralCategories.isEmpty) {
        _selectedReferralCategories.add('Ambulatory');
      }
    }

    if (mounted) {
      setState(() {});
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
    _recordSearchController.dispose();
    _followUpSearchController.dispose();
    super.dispose();
  }

  String _normalizeSearchValue(String value) => value.trim().toLowerCase();

  bool _matchesCurrentBarangay(Map<String, dynamic> patient) {
    final scopeBarangay = _normalizeSearchValue(_scope.barangay);
    if (scopeBarangay.isEmpty) return true;
    final patientBarangay = _normalizeSearchValue(
      (patient['barangay'] ?? '').toString(),
    );
    if (patientBarangay.isNotEmpty) return patientBarangay == scopeBarangay;
    final address = _normalizeSearchValue(
      (patient['address'] ?? '').toString(),
    );
    return address.contains(scopeBarangay);
  }

  Future<void> _showSharedPatientTimeline(Map<String, dynamic> patient) async {
    final snapshot = await _patientHistoryService.loadPatientHistory(patient);
    if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _sharedPatientMatches = <Map<String, dynamic>>[];
        _isSearchingSharedPatients = false;
      });
      return;
    }

    setState(() => _isSearchingSharedPatients = true);

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

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _availableDoctorDocs {
    return _doctorDocs
        .where((doctorDoc) {
          final data = doctorDoc.data();
          final accountStatus = (data['accountStatus'] ?? 'active')
              .toString()
              .trim()
              .toLowerCase();
          final availability = _doctorAvailability(data);
          return accountStatus != 'disabled' &&
              accountStatus != 'archived' &&
              availability != 'unavailable';
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
        if (kDebugMode) {
          if (!mounted) return;
          setState(() {
            _scope = const UserAccessScope(
              userId: 'test_bhw',
              role: 'bhw',
              barangay: 'Casisang',
              barangayCode: 'CAS',
              barangayDistrict: '',
              dataVisibleFrom: null,
            );
            _isLoading = false;
          });
          return;
        }
        if (!mounted) return;
        Get.offAllNamed(MobileRoutes.login);
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
        Get.offAllNamed(MobileRoutes.login);
        return;
      }

      List<QueryDocumentSnapshot<Map<String, dynamic>>> doctorDocs =
          <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      try {
        final doctors = await _firestore
            .collection('users')
            .where('role', whereIn: const <String>['DOCTOR', 'doctor'])
            .get();
        doctorDocs = doctors.docs;
        doctorDocs.sort((a, b) {
          final aName = _doctorDisplayName(a.data()).toLowerCase();
          final bName = _doctorDisplayName(b.data()).toLowerCase();
          return aName.compareTo(bName);
        });
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
      if (kDebugMode) {
        if (!mounted) return;
        setState(() {
          _scope = const UserAccessScope(
            userId: 'test_bhw',
            role: 'bhw',
            barangay: 'Casisang',
            barangayCode: 'CAS',
            barangayDistrict: '',
            dataVisibleFrom: null,
          );
          _isLoading = false;
          _loadErrorMessage = null;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadErrorMessage = 'Could not initialize the referral page: $e';
      });
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _referralsStream() {
    try {
      final collection = _firestore.collection('referrals');
      if (_isChoOperator) {
        return collection.snapshots();
      }
      if (_isDoctor) {
        return collection
            .where('assignedDoctorUid', isEqualTo: _scope.userId)
            .snapshots();
      }
      return collection
          .where('createdByUid', isEqualTo: _scope.userId)
          .snapshots();
    } catch (_) {
      return const Stream.empty();
    }
  }

  Future<void> _submitReferral() async {
    if (_selectedPatientSeed == null ||
        _selectedPatientSeed!['isRegisteredPatient'] != true) {
      _showReferralValidationError(
        'Search and select a registered patient before submitting the referral.',
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
        'priority': _priority,
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
      if ((_selectedPreferredDoctorUid?.isNotEmpty ?? false) ||
          _autoAssignDoctor) {
        try {
          assignmentResult = await _accountPolicyService.assignDoctorToReferral(
            referralId: referralRef.id,
            preferredDoctorUid: _isBhw ? null : _selectedPreferredDoctorUid,
          );
        } catch (_) {}
      }

      if (mounted) {
        _resetReferralForm();
      }

      final assignedDoctorName =
          assignmentResult?.recommendation?.doctorName ?? '';
      final assignedDoctorNotice = assignedDoctorName.isNotEmpty
          ? ' Assigned to $assignedDoctorName.'
          : '';

      Get.snackbar(
        'Referral submitted',
        'The referral was sent to CHO for real-time review.$assignedDoctorNotice',
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
                            (doctorData['username'] ??
                                    doctorData['email'] ??
                                    'Doctor')
                                .toString();
                        return DropdownMenuItem<String>(
                          value: doctorDoc.id,
                          child: Text(label),
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
                        color: _darkDeepTeal,
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
                                  'AI-assisted doctor assignment',
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
                                ? 'Use workload, specialization, and availability signals to preselect the strongest doctor candidate, then save or override manually.'
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
                      'assignedDoctorName':
                          (doctorData['username'] ??
                                  doctorData['email'] ??
                                  'Doctor')
                              .toString(),
                      'assignedDoctorEmail': (doctorData['email'] ?? '')
                          .toString(),
                      'assignmentMode':
                          selectedDoctorUid == smartSuggestedDoctorUid
                          ? 'smart'
                          : 'manual',
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
                    await doc.reference.set(
                      updatePayload,
                      SetOptions(merge: true),
                    );
                    await _syncBarangayReferralMirror(
                      referralId: doc.id,
                      payload: {...data, ...updatePayload},
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
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final updatePayload = <String, dynamic>{
                      'doctorDiagnosis': diagnosisController.text.trim(),
                      'doctorTreatment': treatmentController.text.trim(),
                      'doctorMedication': medicationController.text.trim(),
                      'doctorNotes': notesController.text.trim(),
                      'status': status,
                      'doctorUpdatedAt': FieldValue.serverTimestamp(),
                      'updatedAt': FieldValue.serverTimestamp(),
                    };
                    await doc.reference.set(
                      updatePayload,
                      SetOptions(merge: true),
                    );
                    await _syncBarangayReferralMirror(
                      referralId: doc.id,
                      payload: {...data, ...updatePayload},
                    );

                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    Get.snackbar(
                      'Care updated',
                      'Your diagnosis, treatment, and medication updates are now synchronized to CHO and the referring BHW.',
                      backgroundColor: Colors.green,
                      colorText: Colors.white,
                    );
                  },
                  child: const Text('Save update'),
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
      } else {
        values.add(reason);
      }
    }
    return values.join(', ');
  }

  void _resetReferralForm() {
    _referralFormKey.currentState?.reset();
    _referralDateTimeController.text = _formatDateTimeInput(DateTime.now());
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
      _autoAssignDoctor = true;
      _priority = 'routine';
    });
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _lightOffWhite),
      filled: true,
      fillColor: _darkDeepTeal,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
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
        color: AppDesign.navy,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(color: AppDesign.blueSoft, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityPill(String label, String value, Color color) {
    final isSelected = _priority == value;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _priority = value;
            if (value == 'emergency') {
              _selectedReferralCategories.add('Emergency');
            }
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.25) : _darkDeepTeal,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.3),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? color : _lightOffWhite.withValues(alpha: 0.7),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReferralForm() {
    if (!_isBhw) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _panelSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
        ),
        child: Center(
          child: Text(
            'Referral submission is reserved for Barangay Health Workers (BHWs). As ${_scope.role.toUpperCase()}, please use the Referral Records tab to review and manage referrals.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _lightOffWhite, height: 1.4),
          ),
        ),
      );
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
            _buildFormSection('Triage Priority Level', [
              Row(
                children: [
                  _buildPriorityPill('Routine', 'routine', Colors.blue),
                  const SizedBox(width: 8),
                  _buildPriorityPill('Urgent', 'urgent', Colors.amber),
                  const SizedBox(width: 8),
                  _buildPriorityPill(
                    'Emergency',
                    'emergency',
                    Colors.redAccent,
                  ),
                ],
              ),
            ]),
            _buildFormSection('Registered Patient Lookup & Timeline', [
              TextFormField(
                controller: _patientLookupController,
                style: const TextStyle(color: _lightOffWhite),
                decoration:
                    _inputDecoration(
                      'Search registered patient by name...',
                    ).copyWith(
                      prefixIcon: const Icon(
                        Icons.person_search_outlined,
                        color: _primaryAqua,
                      ),
                      suffixIcon: _isSearchingSharedPatients
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _primaryAqua,
                                ),
                              ),
                            )
                          : (_selectedPatientSeed != null
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.history_edu_rounded,
                                      color: Colors.greenAccent,
                                    ),
                                    tooltip: 'View Patient History Timeline',
                                    onPressed: () => _showSharedPatientTimeline(
                                      _selectedPatientSeed!,
                                    ),
                                  )
                                : null),
                    ),
                onChanged: _scheduleSharedPatientSearch,
              ),
              if (_sharedPatientMatches.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(
                    color: _darkDeepTeal,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _primaryAqua.withValues(alpha: 0.2),
                    ),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _sharedPatientMatches.length,
                    separatorBuilder: (_, _) => Divider(
                      color: _primaryAqua.withValues(alpha: 0.1),
                      height: 1,
                    ),
                    itemBuilder: (context, index) {
                      final match = _sharedPatientMatches[index];
                      final name =
                          (match['patientName'] ?? match['name'] ?? 'Unnamed')
                              .toString();
                      final age = (match['age'] ?? '').toString();
                      final sex = (match['gender'] ?? match['sex'] ?? '')
                          .toString();
                      final brgy = (match['barangay'] ?? '').toString();
                      return ListTile(
                        dense: true,
                        title: Text(
                          name,
                          style: const TextStyle(
                            color: _lightOffWhite,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '$age yrs • $sex • $brgy',
                          style: const TextStyle(
                            color: _mutedCoolGray,
                            fontSize: 11,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.timeline_rounded,
                                color: _primaryAqua,
                                size: 18,
                              ),
                              tooltip: 'Patient Timeline',
                              onPressed: () =>
                                  _showSharedPatientTimeline(match),
                            ),
                            const Icon(
                              Icons.touch_app_outlined,
                              color: Colors.greenAccent,
                              size: 18,
                            ),
                          ],
                        ),
                        onTap: () => _applyPatientSeed(match),
                      );
                    },
                  ),
                ),
              ],
              if (_selectedPatientSeed != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: Colors.greenAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Linked Patient: ${_selectedPatientSeed!['patientName'] ?? _selectedPatientSeed!['name']}',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            _showSharedPatientTimeline(_selectedPatientSeed!),
                        icon: const Icon(
                          Icons.history,
                          size: 15,
                          color: Colors.greenAccent,
                        ),
                        label: const Text(
                          'Timeline',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ]),
            _buildFormSection('Referral Type', [
              Wrap(
                spacing: 10,
                runSpacing: 10,
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
              const SizedBox(height: 14),
              TextFormField(
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _patientAddressController,
                maxLines: 2,
                style: const TextStyle(color: _lightOffWhite),
                decoration: _inputDecoration('Address'),
                validator: (value) => _requiredValidator('Address', value),
              ),
            ]),
            _buildFormSection("Patient's Name", [
              TextFormField(
                controller: _patientSurnameController,
                style: const TextStyle(color: _lightOffWhite),
                decoration: _inputDecoration('Surname'),
                validator: (value) => _requiredValidator('Surname', value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _patientFirstNameController,
                style: const TextStyle(color: _lightOffWhite),
                decoration: _inputDecoration('First Name'),
                validator: (value) => _requiredValidator('First Name', value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _patientMiddleNameController,
                style: const TextStyle(color: _lightOffWhite),
                decoration: _inputDecoration('Middle Name'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _patientAgeController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: _inputDecoration('Age'),
                      validator: (value) => _requiredValidator('Age', value),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _patientSexController,
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: _inputDecoration('Sex'),
                      validator: (value) => _requiredValidator('Sex', value),
                    ),
                  ),
                ],
              ),
            ]),
            _buildFormSection('Clinical Information', [
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
                validator: (value) =>
                    _requiredValidator('Last Meal Time', value),
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
            ]),
            _buildFormSection('Reason for Referral', [
              Wrap(
                spacing: 10,
                runSpacing: 10,
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
            ]),
            const SizedBox(height: 4),
            _buildDoctorMatchingPanel(),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitReferral,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryAqua,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Submit Referral to CHO',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
                OutlinedButton(
                  onPressed: _resetReferralForm,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _lightOffWhite,
                    side: BorderSide(
                      color: _primaryAqua.withValues(alpha: 0.32),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Reset Form'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoctorMatchingPanel() {
    final availableDocs = _availableDoctorDocs;
    final selectedDoctor = _selectedPreferredDoctorData;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _darkDeepTeal,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Doctor & Specialist Destination',
            style: TextStyle(
              color: _lightOffWhite,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _doctorDocs.isEmpty
                ? 'No registered doctor accounts yet. Referrals will still be sent to CHO for centralized review.'
                : _isBhw
                ? 'The system automatically assigns each referral to an approved, active, available doctor using the lowest active referral workload. CHO Admin can reassign later.'
                : 'Select an available doctor or let the system route automatically after review.',
            style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.72)),
          ),
          if (_doctorDocs.isNotEmpty && !_isBhw) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _selectedPreferredDoctorUid,
              dropdownColor: _panelAlt,
              style: const TextStyle(color: _lightOffWhite),
              decoration: _inputDecoration('Preferred doctor (optional)'),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Auto-assign by system (recommended)'),
                ),
                ...availableDocs.map((doctorDoc) {
                  final data = doctorDoc.data();
                  final name = _doctorDisplayName(data);
                  final spec = _doctorSpecialization(data);
                  final avail = _doctorAvailability(data);
                  return DropdownMenuItem<String>(
                    value: doctorDoc.id,
                    child: Text(
                      '$name • $spec (${_doctorAvailabilityLabel(avail)})',
                    ),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() => _selectedPreferredDoctorUid = value);
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _autoAssignDoctor,
              activeThumbColor: _primaryAqua,
              title: const Text(
                'Auto-assign doctor on submission',
                style: TextStyle(color: _lightOffWhite),
              ),
              subtitle: Text(
                _selectedPreferredDoctorUid == null
                    ? 'The system will match this referral to the strongest doctor after submission.'
                    : 'Keep this on to let the server validate and finalize your preferred doctor.',
                style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.68)),
              ),
              onChanged: (value) {
                setState(() => _autoAssignDoctor = value);
              },
            ),
            if (selectedDoctor != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildInfoChip(_doctorDisplayName(selectedDoctor)),
                  _buildInfoChip(_doctorSpecialization(selectedDoctor)),
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
    );
  }

  Widget _buildFormSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _darkDeepTeal,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.9),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildCheckboxOption({
    required String label,
    required bool selected,
    required ValueChanged<bool> onChanged,
  }) {
    return SizedBox(
      width: 170,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(!selected),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
          spacing: 10,
          runSpacing: 10,
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
    int followUpNeeded = 0;

    for (final doc in docs) {
      final data = doc.data();
      final status = (data['status'] ?? 'submitted').toString();
      if (status == 'assigned' || status == 'doctor_assigned') {
        assigned++;
      } else if (status == 'in_treatment' ||
          status == 'waiting_consultation' ||
          status == 'consulted') {
        inTreatment++;
      } else if (status == 'completed') {
        completed++;
      } else {
        submitted++;
      }

      if (data['followUpRequired'] == true ||
          (status == 'completed' && data['followUpCompleted'] != true)) {
        followUpNeeded++;
      }
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 1180
        ? 6
        : screenWidth > 820
        ? 3
        : 2;

    final summaries = <({String label, String value, IconData icon})>[
      (
        label: 'Total Referrals',
        value: '${docs.length}',
        icon: Icons.swap_horiz_rounded,
      ),
      (
        label: 'Pending CHO Review',
        value: '$submitted',
        icon: Icons.rate_review_outlined,
      ),
      (
        label: 'Doctor Assigned',
        value: '$assigned',
        icon: Icons.assignment_ind_outlined,
      ),
      (
        label: 'In Care / Consulted',
        value: '$inTreatment',
        icon: Icons.medical_services_outlined,
      ),
      (label: 'Completed', value: '$completed', icon: Icons.task_alt_rounded),
      (
        label: 'Follow-ups Required',
        value: '$followUpNeeded',
        icon: Icons.home_work_outlined,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 140,
      ),
      itemCount: summaries.length,
      itemBuilder: (context, index) {
        final summary = summaries[index];
        return _buildSummaryCard(summary.label, summary.value, summary.icon);
      },
    );
  }

  Widget _buildSummaryCard(String label, String value, IconData icon) {
    return AppMetricCard(label: label, value: value, icon: icon);
  }

  Widget _buildTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _panelSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _primaryAqua.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: List.generate(_views.length, (index) {
            final selected = _selectedTab == index;
            final icons = [
              Icons.dashboard_outlined,
              Icons.add_circle_outline,
              Icons.list_alt_outlined,
              Icons.home_work_outlined,
            ];
            return TextButton.icon(
              onPressed: () => setState(() => _selectedTab = index),
              icon: Icon(icons[index], size: 18),
              label: Text(_views[index]),
              style: TextButton.styleFrom(
                foregroundColor: selected ? Colors.white : _lightOffWhite,
                backgroundColor: selected ? _primaryAqua : Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildDashboardTab(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final recentDocs = docs.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryCards(docs),
        const SizedBox(height: 20),
        // Quick Action Shortcuts
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _panelSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Quick Actions',
                style: TextStyle(
                  color: _lightOffWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _selectedTab = 1),
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Create New Referral'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryAqua,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _selectedTab = 2),
                    icon: const Icon(Icons.list_alt_outlined, size: 18),
                    label: const Text('View Live Referral Queue'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _lightOffWhite,
                      side: BorderSide(
                        color: _primaryAqua.withValues(alpha: 0.3),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => ClinicalFormPdfService.showExportDialog(
                      context,
                      formType: ClinicalFormType.referral,
                    ),
                    icon: const Icon(
                      Icons.picture_as_pdf_outlined,
                      color: _primaryAqua,
                      size: 18,
                    ),
                    label: const Text('Export Blank Form (REF-2026)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _lightOffWhite,
                      side: BorderSide(
                        color: _primaryAqua.withValues(alpha: 0.3),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Live Recent Activity
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _panelSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Referrals',
                    style: TextStyle(
                      color: _lightOffWhite,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selectedTab = 2),
                    child: const Text('See all records →'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (recentDocs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No referrals submitted yet. Tap "+ Create New Referral" to start.',
                      style: TextStyle(color: _mutedCoolGray),
                    ),
                  ),
                )
              else
                ...recentDocs.map(_buildReferralCard),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCreateReferralTab() {
    return _buildReferralForm();
  }

  Widget _buildRecordsTab(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final query = _recordSearchController.text.trim().toLowerCase();

    final filteredDocs = docs.where((doc) {
      final data = doc.data();
      final status = (data['status'] ?? 'submitted').toString().toLowerCase();
      final priority = (data['priority'] ?? 'routine').toString().toLowerCase();
      final name = (data['patientName'] ?? '').toString().toLowerCase();
      final patientId = (data['patientId'] ?? '').toString().toLowerCase();
      final complaint = (data['chiefComplaint'] ?? '').toString().toLowerCase();
      final reason = (data['referralReason'] ?? '').toString().toLowerCase();

      // Search match
      if (query.isNotEmpty) {
        final matchesQuery =
            name.contains(query) ||
            patientId.contains(query) ||
            complaint.contains(query) ||
            reason.contains(query) ||
            doc.id.toLowerCase().contains(query);
        if (!matchesQuery) return false;
      }

      // Status filter
      if (_statusFilter != 'all') {
        if (_statusFilter == 'pending' &&
            !(status == 'submitted' ||
                status == 'pending_review' ||
                status == 'under_review')) {
          return false;
        }
        if (_statusFilter == 'assigned' &&
            !(status == 'assigned' || status == 'doctor_assigned')) {
          return false;
        }
        if (_statusFilter == 'in_treatment' &&
            !(status == 'in_treatment' ||
                status == 'waiting_consultation' ||
                status == 'consulted')) {
          return false;
        }
        if (_statusFilter == 'completed' && status != 'completed') {
          return false;
        }
        if (_statusFilter == 'returned' &&
            status != 'returned_for_correction') {
          return false;
        }
      }

      // Priority filter
      if (_priorityFilter != 'all') {
        if (priority != _priorityFilter) return false;
      }

      // Date range filter
      if (_recordsFromDate != null || _recordsToDate != null) {
        final ts = data['createdAt'];
        if (ts is Timestamp) {
          final dt = ts.toDate();
          if (_recordsFromDate != null && dt.isBefore(_recordsFromDate!)) {
            return false;
          }
          if (_recordsToDate != null &&
              dt.isAfter(_recordsToDate!.add(const Duration(days: 1)))) {
            return false;
          }
        }
      }

      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search & Filter Panel
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _panelSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _recordSearchController,
                style: const TextStyle(color: _lightOffWhite),
                decoration:
                    _inputDecoration(
                      'Search referral by patient name, ID, or symptoms...',
                    ).copyWith(
                      prefixIcon: const Icon(Icons.search, color: _primaryAqua),
                      suffixIcon: _recordSearchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear,
                                color: _mutedCoolGray,
                              ),
                              onPressed: () {
                                _recordSearchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              // Status Filters
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text(
                      'Status: ',
                      style: TextStyle(
                        color: _mutedCoolGray,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    ...[
                      ('All', 'all'),
                      ('Pending', 'pending'),
                      ('Assigned', 'assigned'),
                      ('In Care', 'in_treatment'),
                      ('Completed', 'completed'),
                      ('Returned', 'returned'),
                    ].map((item) {
                      final isSelected = _statusFilter == item.$2;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(
                            item.$1,
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? Colors.white : _lightOffWhite,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: _primaryAqua,
                          backgroundColor: _darkDeepTeal,
                          onSelected: (_) =>
                              setState(() => _statusFilter = item.$2),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Priority Filters
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text(
                      'Priority: ',
                      style: TextStyle(
                        color: _mutedCoolGray,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    ...[
                      ('All', 'all'),
                      ('Routine', 'routine'),
                      ('Urgent', 'urgent'),
                      ('Emergency', 'emergency'),
                    ].map((item) {
                      final isSelected = _priorityFilter == item.$2;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(
                            item.$1,
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? Colors.white : _lightOffWhite,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: _primaryAqua,
                          backgroundColor: _darkDeepTeal,
                          onSelected: (_) =>
                              setState(() => _priorityFilter = item.$2),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        // Live Queue Results
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _panelSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Referral Records (${filteredDocs.length})',
                    style: const TextStyle(
                      color: _lightOffWhite,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_statusFilter != 'all' ||
                      _priorityFilter != 'all' ||
                      _recordSearchController.text.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.filter_alt_off, size: 15),
                      label: const Text(
                        'Clear Filters',
                        style: TextStyle(fontSize: 12),
                      ),
                      onPressed: () {
                        setState(() {
                          _statusFilter = 'all';
                          _priorityFilter = 'all';
                          _recordSearchController.clear();
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (filteredDocs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.search_off_rounded,
                          size: 42,
                          color: _mutedCoolGray,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'No referral records match your search or filter criteria.',
                          style: TextStyle(color: _mutedCoolGray),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...filteredDocs.map(_buildReferralCard),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFollowUpTab(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final followUpDocs = docs.where((doc) {
      final data = doc.data();
      final status = (data['status'] ?? '').toString();
      final isNeeded =
          data['followUpRequired'] == true || status == 'completed';
      if (!isNeeded) return false;

      final isDone = data['followUpCompleted'] == true;
      if (_followUpStatusFilter == 'pending' && isDone) return false;
      if (_followUpStatusFilter == 'completed' && !isDone) return false;

      final query = _followUpSearchController.text.trim().toLowerCase();
      if (query.isNotEmpty) {
        final name = (data['patientName'] ?? '').toString().toLowerCase();
        final addr = (data['patientAddress'] ?? '').toString().toLowerCase();
        if (!name.contains(query) && !addr.contains(query)) return false;
      }

      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Follow-up search & filter header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _panelSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _followUpSearchController,
                style: const TextStyle(color: _lightOffWhite),
                decoration:
                    _inputDecoration(
                      'Search follow-up patients by name or address...',
                    ).copyWith(
                      prefixIcon: const Icon(Icons.search, color: _primaryAqua),
                      suffixIcon: _followUpSearchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear,
                                color: _mutedCoolGray,
                              ),
                              onPressed: () {
                                _followUpSearchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text(
                      'Follow-up Status: ',
                      style: TextStyle(
                        color: _mutedCoolGray,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    ...[
                      ('All', 'all'),
                      ('Pending Visit', 'pending'),
                      ('Completed', 'completed'),
                    ].map((item) {
                      final isSelected = _followUpStatusFilter == item.$2;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(
                            item.$1,
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? Colors.white : _lightOffWhite,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: _primaryAqua,
                          backgroundColor: _darkDeepTeal,
                          onSelected: (_) =>
                              setState(() => _followUpStatusFilter = item.$2),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _panelSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Community Follow-up Queue (${followUpDocs.length})',
                style: const TextStyle(
                  color: _lightOffWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Track discharged or high-risk referred patients who require home visits and recovery check-ins.',
                style: TextStyle(
                  color: _lightOffWhite.withValues(alpha: 0.72),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              if (followUpDocs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No patients currently pending post-referral community follow-up.',
                      style: TextStyle(color: _mutedCoolGray),
                    ),
                  ),
                )
              else
                ...followUpDocs.map(_buildFollowUpCard),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFollowUpCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final patientName = (data['patientName'] ?? 'Patient').toString();
    final isDone = data['followUpCompleted'] == true;
    final doctorDiagnosis = (data['doctorDiagnosis'] ?? '').toString();
    final doctorNotes = (data['doctorNotes'] ?? '').toString();
    final recoveryStatus = (data['followUpRecoveryStatus'] ?? 'Pending visit')
        .toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _darkDeepTeal,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDone
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.amber.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  patientName,
                  style: const TextStyle(
                    color: _lightOffWhite,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isDone
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isDone ? Colors.greenAccent : Colors.amberAccent,
                  ),
                ),
                child: Text(
                  isDone ? 'COMPLETED' : 'FOLLOW-UP NEEDED',
                  style: TextStyle(
                    color: isDone ? Colors.greenAccent : Colors.amberAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Address: ${(data['patientAddress'] ?? 'Barangay ${_scope.barangay}').toString()}',
            style: const TextStyle(color: _mutedCoolGray, fontSize: 12.5),
          ),
          if (doctorDiagnosis.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Hospital Diagnosis: $doctorDiagnosis',
              style: const TextStyle(color: _lightOffWhite, fontSize: 13),
            ),
          ],
          if (doctorNotes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Discharge Instructions: $doctorNotes',
              style: TextStyle(
                color: _lightOffWhite.withValues(alpha: 0.8),
                fontSize: 12.5,
              ),
            ),
          ],
          if (isDone) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _panelSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recorded by ${data['followUpCompletedBy'] ?? 'BHW'} • Recovery: $recoveryStatus',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if ((data['followUpNotes'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Notes: ${data['followUpNotes']}',
                      style: const TextStyle(
                        color: _lightOffWhite,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () => _showFollowUpModal(doc),
                icon: const Icon(Icons.edit_note, size: 18),
                label: Text(
                  isDone ? 'Edit Follow-up Record' : 'Record Home Visit',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryAqua,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showReferralDetailsDialog(doc),
                icon: const Icon(Icons.info_outline, size: 16),
                label: const Text('View Referral Details'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _lightOffWhite,
                  side: BorderSide(color: _primaryAqua.withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showFollowUpModal(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final patientName = (data['patientName'] ?? 'Patient').toString();
    final isAlreadyCompleted = data['followUpCompleted'] == true;

    DateTime followUpDate = DateTime.now();
    final bpCtrl = TextEditingController(
      text: (data['followUpBp'] ?? '').toString(),
    );
    final tempCtrl = TextEditingController(
      text: (data['followUpTemp'] ?? '').toString(),
    );
    final pulseCtrl = TextEditingController(
      text: (data['followUpPulse'] ?? '').toString(),
    );
    final spo2Ctrl = TextEditingController(
      text: (data['followUpSpo2'] ?? '').toString(),
    );
    final notesCtrl = TextEditingController(
      text: (data['followUpNotes'] ?? '').toString(),
    );
    String recoveryStatus = (data['followUpRecoveryStatus'] ?? 'Improving')
        .toString();
    bool markCompleted = isAlreadyCompleted ? true : true;
    bool isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: _darkDeepTeal,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: _primaryAqua.withValues(alpha: 0.2)),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Record Community Follow-up',
                                style: TextStyle(
                                  color: _lightOffWhite,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Patient: $patientName',
                                style: const TextStyle(
                                  color: _mutedCoolGray,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: _lightOffWhite),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Follow-up Visit Date',
                        style: TextStyle(color: _lightOffWhite, fontSize: 14),
                      ),
                      subtitle: Text(
                        '${followUpDate.year}-${followUpDate.month.toString().padLeft(2, '0')}-${followUpDate.day.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: _primaryAqua,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.calendar_month,
                        color: _primaryAqua,
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: followUpDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) {
                          setSheetState(() => followUpDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: bpCtrl,
                            style: const TextStyle(color: _lightOffWhite),
                            decoration: _inputDecoration('Blood Pressure (BP)'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: tempCtrl,
                            style: const TextStyle(color: _lightOffWhite),
                            decoration: _inputDecoration('Temp (°C)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: pulseCtrl,
                            style: const TextStyle(color: _lightOffWhite),
                            decoration: _inputDecoration('Pulse / HR (bpm)'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: spo2Ctrl,
                            style: const TextStyle(color: _lightOffWhite),
                            decoration: _inputDecoration('SpO2 (%)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: recoveryStatus,
                      dropdownColor: _panelSurface,
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: _inputDecoration('Patient Recovery Status'),
                      items:
                          const [
                                'Improving',
                                'Stable',
                                'Needs Attention',
                                'Re-referral Required',
                              ]
                              .map(
                                (s) =>
                                    DropdownMenuItem(value: s, child: Text(s)),
                              )
                              .toList(),
                      onChanged: (v) {
                        if (v != null) setSheetState(() => recoveryStatus = v);
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: notesCtrl,
                      maxLines: 4,
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: _inputDecoration(
                        'BHW Observations & Home Visit Notes',
                      ),
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Mark Follow-up as Completed',
                        style: TextStyle(color: _lightOffWhite, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Confirms home visit and post-care monitoring has occurred',
                        style: TextStyle(color: _mutedCoolGray, fontSize: 12),
                      ),
                      value: markCompleted,
                      activeThumbColor: _primaryAqua,
                      onChanged: (v) => setSheetState(() => markCompleted = v),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryAqua,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: isSaving
                            ? null
                            : () async {
                                setSheetState(() => isSaving = true);
                                try {
                                  final user =
                                      FirebaseAuth.instance.currentUser;
                                  final payload = {
                                    'followUpCompleted': markCompleted,
                                    'followUpCompletedAt': markCompleted
                                        ? FieldValue.serverTimestamp()
                                        : null,
                                    'followUpCompletedBy':
                                        user?.displayName ??
                                        user?.email ??
                                        'BHW',
                                    'followUpVisitDate':
                                        '${followUpDate.year}-${followUpDate.month.toString().padLeft(2, '0')}-${followUpDate.day.toString().padLeft(2, '0')}',
                                    'followUpBp': bpCtrl.text.trim(),
                                    'followUpTemp': tempCtrl.text.trim(),
                                    'followUpPulse': pulseCtrl.text.trim(),
                                    'followUpSpo2': spo2Ctrl.text.trim(),
                                    'followUpRecoveryStatus': recoveryStatus,
                                    'followUpNotes': notesCtrl.text.trim(),
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  };
                                  await doc.reference.update(payload);

                                  final mirrorRef =
                                      _barangayReferralMirrorReference(
                                        barangayCode: _scope.barangayCode,
                                        referralId: doc.id,
                                      );
                                  if (mirrorRef != null) {
                                    await mirrorRef.update(payload);
                                  }

                                  if (sheetContext.mounted) {
                                    Navigator.of(sheetContext).pop();
                                  }
                                  Get.snackbar(
                                    'Follow-up saved',
                                    'Patient follow-up record successfully updated.',
                                    backgroundColor: Colors.green,
                                    colorText: Colors.white,
                                  );
                                } catch (e) {
                                  setSheetState(() => isSaving = false);
                                  Get.snackbar(
                                    'Error saving follow-up',
                                    '$e',
                                    backgroundColor: Colors.redAccent,
                                    colorText: Colors.white,
                                  );
                                }
                              },
                        child: isSaving
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              )
                            : const Text(
                                'Save Follow-up Record',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showReferralDetailsDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final patientName = (data['patientName'] ?? 'Unnamed Patient').toString();
    final referralId = doc.id;
    final status = (data['status'] ?? 'submitted').toString();
    final priority = (data['priority'] ?? 'routine').toString();
    final doctorName = (data['assignedDoctorName'] ?? 'Unassigned').toString();
    final doctorSpecialization =
        (data['assignedDoctorSpecialization'] ?? 'General Medicine').toString();
    final doctorDiagnosis = (data['doctorDiagnosis'] ?? '').toString();
    final doctorTreatment = (data['doctorTreatment'] ?? '').toString();
    final doctorMedication = (data['doctorMedication'] ?? '').toString();
    final doctorNotes = (data['doctorNotes'] ?? '').toString();
    final choNotes = (data['choReviewNotes'] ?? '').toString();

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: _panelSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patientName,
                    style: const TextStyle(
                      color: _lightOffWhite,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Referral ID: $referralId',
                    style: const TextStyle(color: _mutedCoolGray, fontSize: 12),
                  ),
                ],
              ),
            ),
            _buildPriorityBadge(priority),
            const SizedBox(width: 6),
            _buildStatusChip(status),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailSection('Demographics & Intake', [
                  _buildDetailRow(
                    'Age / Sex',
                    '${data['patientAge'] ?? 'N/A'} • ${data['patientSex'] ?? 'N/A'}',
                  ),
                  _buildDetailRow(
                    'Barangay',
                    (data['barangay'] ?? 'N/A').toString(),
                  ),
                  _buildDetailRow(
                    'Address',
                    (data['patientAddress'] ?? 'N/A').toString(),
                  ),
                  _buildDetailRow(
                    'Date & Time',
                    (data['referralDateTime'] ?? 'N/A').toString(),
                  ),
                ]),
                const SizedBox(height: 12),
                _buildDetailSection('Clinical Findings', [
                  _buildDetailRow(
                    'Chief Complaint',
                    (data['chiefComplaint'] ?? 'None').toString(),
                  ),
                  _buildDetailRow(
                    'Medical History',
                    (data['medicalHistory'] ?? 'None').toString(),
                  ),
                  _buildDetailRow(
                    'Vital Signs',
                    (data['completeVitalSigns'] ?? 'N/A').toString(),
                  ),
                  _buildDetailRow(
                    'Impression',
                    (data['impression'] ?? 'N/A').toString(),
                  ),
                  _buildDetailRow(
                    'Action Taken',
                    (data['actionTaken'] ?? 'N/A').toString(),
                  ),
                  _buildDetailRow(
                    'Last Meal',
                    (data['lastMealTime'] ?? 'N/A').toString(),
                  ),
                  _buildDetailRow(
                    'Surgical History',
                    data['hasSurgicalOperations'] == true
                        ? 'Yes - ${data['surgicalProcedure']}'
                        : 'No',
                  ),
                  _buildDetailRow(
                    'Insurance',
                    data['hasHealthInsuranceCoverage'] == true
                        ? 'Yes - ${data['healthInsuranceCoverageType']}'
                        : 'No',
                  ),
                ]),
                const SizedBox(height: 12),
                _buildDetailSection('Routing & Doctor Care', [
                  _buildDetailRow(
                    'Assigned Doctor',
                    '$doctorName ($doctorSpecialization)',
                  ),
                  if (doctorDiagnosis.isNotEmpty)
                    _buildDetailRow('Doctor Diagnosis', doctorDiagnosis),
                  if (doctorTreatment.isNotEmpty)
                    _buildDetailRow('Doctor Treatment', doctorTreatment),
                  if (doctorMedication.isNotEmpty)
                    _buildDetailRow('Prescribed Meds', doctorMedication),
                  if (doctorNotes.isNotEmpty)
                    _buildDetailRow('Doctor Notes', doctorNotes),
                  if (choNotes.isNotEmpty)
                    _buildDetailRow('CHO Review Notes', choNotes),
                  _buildDetailRow(
                    'Submitted By',
                    '${data['createdByName'] ?? data['createdByEmail'] ?? 'BHW'} (${_formatTimestamp(data['createdAt'])})',
                  ),
                ]),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => ClinicalFormPdfService.showExportDialog(
              context,
              formType: ClinicalFormType.referral,
              record: {...data, 'id': doc.id},
            ),
            icon: const Icon(
              Icons.picture_as_pdf_outlined,
              color: _primaryAqua,
              size: 18,
            ),
            label: const Text('Export PDF'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityBadge(String priority) {
    Color color;
    switch (priority.toLowerCase()) {
      case 'emergency':
        color = Colors.redAccent;
        break;
      case 'urgent':
        color = Colors.amberAccent;
        break;
      default:
        color = _primaryAqua;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _darkDeepTeal,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _primaryAqua,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: _mutedCoolGray, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: _lightOffWhite, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferralCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final status = (data['status'] ?? 'submitted').toString();
    final priority = (data['priority'] ?? 'routine').toString();
    final doctorName = (data['assignedDoctorName'] ?? 'Unassigned').toString();
    final doctorDiagnosis = (data['doctorDiagnosis'] ?? '').toString();
    final doctorTreatment = (data['doctorTreatment'] ?? '').toString();
    final doctorMedication = (data['doctorMedication'] ?? '').toString();
    final assignmentMode = (data['assignmentMode'] ?? 'manual').toString();
    final assignmentRationale = (data['assignmentRationale'] ?? '').toString();

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
                (data['patientName'] ?? 'Unnamed patient').toString(),
                style: const TextStyle(
                  color: _lightOffWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              _buildPriorityBadge(priority),
              _buildStatusChip(status),
              if ((data['barangay'] ?? '').toString().isNotEmpty)
                _buildInfoChip((data['barangay'] ?? '').toString()),
              _buildInfoChip('Doctor: $doctorName'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Complaint: ${(data['chiefComplaint'] ?? 'No complaint').toString()}',
            style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.88)),
          ),
          const SizedBox(height: 6),
          Text(
            'Referral reason: ${(data['referralReason'] ?? 'Not provided').toString()}',
            style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _buildMetaBlock(
                'Current diagnosis',
                (data['currentDiagnosis'] ?? 'Not recorded').toString(),
              ),
              _buildMetaBlock(
                'Current treatment',
                (data['currentTreatment'] ?? 'Not recorded').toString(),
              ),
              _buildMetaBlock(
                'Current medication',
                (data['currentMedication'] ?? 'Not recorded').toString(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_hasDoctorUpdate(data))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _darkDeepTeal,
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
              '${assignmentMode == 'smart' ? 'Smart assignment' : 'Manual assignment'}: $assignmentRationale',
              style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.72)),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showReferralDetailsDialog(doc),
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('View Details'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _lightOffWhite,
                  side: BorderSide(color: _primaryAqua.withValues(alpha: 0.32)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showFollowUpModal(doc),
                icon: const Icon(Icons.home_work_outlined, size: 16),
                label: const Text('Follow-up'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amberAccent,
                  side: BorderSide(color: Colors.amber.withValues(alpha: 0.4)),
                ),
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
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.greenAccent,
                    side: const BorderSide(color: Colors.greenAccent),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => ClinicalFormPdfService.showExportDialog(
                  context,
                  formType: ClinicalFormType.referral,
                  record: {...data, 'id': doc.id},
                ),
                icon: const Icon(
                  Icons.picture_as_pdf_outlined,
                  color: _primaryAqua,
                  size: 16,
                ),
                label: const Text('Export PDF'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _lightOffWhite,
                  side: BorderSide(color: _primaryAqua.withValues(alpha: 0.32)),
                ),
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
        color: _darkDeepTeal,
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
    return Scaffold(
      backgroundColor: _darkDeepTeal,
      appBar: AppBar(
        backgroundColor: AppDesign.navy,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: const Text(
          'Referral Management',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loadScope,
            icon: const Icon(Icons.refresh, color: Colors.white),
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

                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _primaryAqua),
                  );
                }

                final docs = snapshot.hasData
                    ? _sortedDocs(snapshot.data!.docs)
                    : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 18),
                      _buildTabs(),
                      const SizedBox(height: 18),
                      switch (_selectedTab) {
                        0 => _buildDashboardTab(docs),
                        1 => _buildCreateReferralTab(),
                        2 => _buildRecordsTab(docs),
                        _ => _buildFollowUpTab(docs),
                      },
                    ],
                  ),
                );
              },
            ),
    );
  }
}
