import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/features/auth/login.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_firestore_paths.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/shared/services/account_policy_service.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
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
  const ReferralsPage({super.key});

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

  final FirebaseFirestore _firestore = getFirestoreInstance();
  final AccountPolicyService _accountPolicyService =
      AccountPolicyService.instance;
  final GlobalKey<FormState> _referralFormKey = GlobalKey<FormState>();

  final TextEditingController _referralDateTimeController =
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

  bool get _isDoctor => _scope.role == 'doctor';
  bool get _isBhw => _scope.role == 'bhw';
  bool get _isChoOperator => _scope.canViewAllBarangays;

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

  @override
  void initState() {
    super.initState();
    _referralDateTimeController.text = _formatDateTimeInput(DateTime.now());
    _loadScope();
  }

  @override
  void dispose() {
    _referralDateTimeController.dispose();
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
  }

  Future<void> _submitReferral() async {
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
        'patientRecordId': '',
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

      if (mounted) {
        _resetReferralForm();
      }

      Get.snackbar(
        'Referral submitted',
        'The referral was sent to CHO for real-time review and doctor assignment.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      Get.snackbar(
        'Submission failed',
        'Could not submit referral: $e',
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
    String status = (data['status'] ?? 'assigned').toString();

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
                      items:
                          const <String>[
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

  Widget _buildReferralForm() {
    if (!_isBhw) {
      return const SizedBox.shrink();
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
            const SizedBox(height: 14),
            _buildFormSectionTitle("Patient's Name"),
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
            const SizedBox(height: 18),
            _buildDoctorMatchingPanel(),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitReferral,
                icon: const Icon(Icons.send_outlined),
                label: Text(_isSubmitting ? 'Submitting...' : 'Send referral'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryAqua,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoctorMatchingPanel() {
    final availableDoctors = _availableDoctorDocs;
    final selectedDoctor = _selectedPreferredDoctorData;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
            'Choose a doctor directly when needed, or leave it open and let AI assign the strongest available match.',
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.76),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          if (availableDoctors.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _panelSurface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'No doctor accounts are available yet. You can still submit and CHO can assign later.',
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
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _autoAssignDoctor,
              activeColor: _primaryAqua,
              title: const Text(
                'Use AI auto-assignment',
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
                activeColor: _primaryAqua,
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

  Widget _buildSizedInput({required double width, required Widget child}) {
    return SizedBox(width: width, child: child);
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

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 1180
        ? 4
        : screenWidth > 820
        ? 3
        : 2;

    final summaries = <({String label, String value, IconData icon})>[
      (
        label: 'Visible referrals',
        value: '${docs.length}',
        icon: Icons.folder_shared_outlined,
      ),
      (label: 'Submitted', value: '$submitted', icon: Icons.outbox_outlined),
      (
        label: 'Assigned / Active',
        value: '${assigned + inTreatment}',
        icon: Icons.assignment_ind_outlined,
      ),
      (label: 'Completed', value: '$completed', icon: Icons.verified_outlined),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        // Keep enough vertical room to prevent label/value overflow on mobile.
        mainAxisExtent: 150,
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

  Widget _buildReferralCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final status = (data['status'] ?? 'submitted').toString();
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
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
            spacing: 12,
            runSpacing: 12,
            children: [
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
        title: const Text('Referral Management'),
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
                    child: Text(
                      'Could not load referrals: ${snapshot.error}',
                      style: const TextStyle(color: _lightOffWhite),
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
