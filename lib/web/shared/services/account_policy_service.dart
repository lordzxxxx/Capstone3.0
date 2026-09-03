import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/web/shared/services/rbac_policy.dart';

class RegistrationValidationResult {
  final bool emailExists;
  final bool usernameExists;
  final bool barangayUnavailable;
  final String duplicateAccountMessage;
  final String barangayMessage;

  const RegistrationValidationResult({
    required this.emailExists,
    required this.usernameExists,
    required this.barangayUnavailable,
    required this.duplicateAccountMessage,
    required this.barangayMessage,
  });

  bool get hasConflict => emailExists || usernameExists || barangayUnavailable;

  factory RegistrationValidationResult.fromMap(Map<Object?, Object?> map) {
    return RegistrationValidationResult(
      emailExists: map['emailExists'] == true,
      usernameExists: map['usernameExists'] == true,
      barangayUnavailable: map['barangayUnavailable'] == true,
      duplicateAccountMessage:
          (map['duplicateAccountMessage'] ??
                  'This account is already registered. Please log in instead.')
              .toString(),
      barangayMessage:
          (map['barangayMessage'] ??
                  'This barangay is already registered under another account.')
              .toString(),
    );
  }
}

class RegistrationAccountResult {
  final String uid;
  final String registrationNonce;
  final String customToken;

  const RegistrationAccountResult({
    required this.uid,
    required this.registrationNonce,
    required this.customToken,
  });

  factory RegistrationAccountResult.fromMap(Map<Object?, Object?> map) {
    return RegistrationAccountResult(
      uid: (map['uid'] ?? '').toString(),
      registrationNonce: (map['registrationNonce'] ?? '').toString(),
      customToken: (map['customToken'] ?? '').toString(),
    );
  }
}

class BarangayAvailabilityStatus {
  final String barangayCode;
  final String barangayName;
  final String username;
  final String email;
  final String accountStatus;
  final String approvalStatus;
  final bool isAvailable;

  const BarangayAvailabilityStatus({
    required this.barangayCode,
    required this.barangayName,
    required this.username,
    required this.email,
    required this.accountStatus,
    required this.approvalStatus,
    required this.isAvailable,
  });

  String get availabilityLabel =>
      isAvailable ? 'Available' : 'Already Registered';

  factory BarangayAvailabilityStatus.fromMap(Map<Object?, Object?> map) {
    return BarangayAvailabilityStatus(
      barangayCode: (map['barangayCode'] ?? '').toString(),
      barangayName: (map['barangay'] ?? '').toString(),
      username: (map['username'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      accountStatus: (map['accountStatus'] ?? 'active').toString(),
      approvalStatus: (map['approvalStatus'] ?? 'pending').toString(),
      isAvailable: map['isAvailable'] == true,
    );
  }
}

class DoctorAssignmentSuggestion {
  final String doctorUid;
  final String doctorName;
  final String doctorEmail;
  final String specialization;
  final String availability;
  final int workload;
  final int score;
  final List<String> rationale;

  const DoctorAssignmentSuggestion({
    required this.doctorUid,
    required this.doctorName,
    required this.doctorEmail,
    required this.specialization,
    required this.availability,
    required this.workload,
    required this.score,
    required this.rationale,
  });

  factory DoctorAssignmentSuggestion.fromMap(Map<Object?, Object?> map) {
    final rawRationale = map['rationale'];
    return DoctorAssignmentSuggestion(
      doctorUid: (map['doctorUid'] ?? '').toString(),
      doctorName: (map['doctorName'] ?? '').toString(),
      doctorEmail: (map['doctorEmail'] ?? '').toString(),
      specialization: (map['specialization'] ?? 'General Medicine').toString(),
      availability: (map['availability'] ?? 'available').toString(),
      workload: int.tryParse((map['workload'] ?? 0).toString()) ?? 0,
      score: int.tryParse((map['score'] ?? 0).toString()) ?? 0,
      rationale: rawRationale is List
          ? rawRationale.map((entry) => entry.toString()).toList()
          : const <String>[],
    );
  }
}

class DoctorAssignmentSuggestionResult {
  final DoctorAssignmentSuggestion? recommendation;
  final List<DoctorAssignmentSuggestion> rankedDoctors;

  const DoctorAssignmentSuggestionResult({
    required this.recommendation,
    required this.rankedDoctors,
  });

  factory DoctorAssignmentSuggestionResult.fromMap(Map<Object?, Object?> map) {
    final recommendationMap = map['recommendation'];
    final rankedRaw = map['rankedDoctors'];
    return DoctorAssignmentSuggestionResult(
      recommendation: recommendationMap is Map<Object?, Object?>
          ? DoctorAssignmentSuggestion.fromMap(recommendationMap)
          : null,
      rankedDoctors: rankedRaw is List
          ? rankedRaw
                .whereType<Map<Object?, Object?>>()
                .map(DoctorAssignmentSuggestion.fromMap)
                .toList()
          : const <DoctorAssignmentSuggestion>[],
    );
  }
}

class ManagedAccountResult {
  final bool success;
  final String uid;
  final String role;
  final String email;
  final String fullName;
  final bool activationEmailSent;
  final String activationEmailReason;
  final String accessRoleKey;

  const ManagedAccountResult({
    required this.success,
    required this.uid,
    required this.role,
    required this.email,
    required this.fullName,
    required this.activationEmailSent,
    required this.activationEmailReason,
    this.accessRoleKey = '',
  });

  factory ManagedAccountResult.fromMap(Map<Object?, Object?> map) {
    return ManagedAccountResult(
      success: map['success'] == true,
      uid: (map['uid'] ?? '').toString(),
      role: (map['role'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      fullName: (map['fullName'] ?? '').toString(),
      activationEmailSent: map['activationEmailSent'] == true,
      activationEmailReason: (map['activationEmailReason'] ?? '').toString(),
      accessRoleKey: (map['accessRoleKey'] ?? '').toString(),
    );
  }
}

class DoctorAssignmentExecutionResult {
  final bool success;
  final String assignmentMode;
  final String assignmentSource;
  final DoctorAssignmentSuggestion? recommendation;
  final List<DoctorAssignmentSuggestion> rankedDoctors;

  const DoctorAssignmentExecutionResult({
    required this.success,
    required this.assignmentMode,
    required this.assignmentSource,
    required this.recommendation,
    required this.rankedDoctors,
  });

  factory DoctorAssignmentExecutionResult.fromMap(Map<Object?, Object?> map) {
    final recommendationMap = map['recommendation'];
    final rankedRaw = map['rankedDoctors'];
    return DoctorAssignmentExecutionResult(
      success: map['success'] == true,
      assignmentMode: (map['assignmentMode'] ?? 'manual').toString(),
      assignmentSource: (map['assignmentSource'] ?? 'manual').toString(),
      recommendation: recommendationMap is Map<Object?, Object?>
          ? DoctorAssignmentSuggestion.fromMap(recommendationMap)
          : null,
      rankedDoctors: rankedRaw is List
          ? rankedRaw
                .whereType<Map<Object?, Object?>>()
                .map(DoctorAssignmentSuggestion.fromMap)
                .toList()
          : const <DoctorAssignmentSuggestion>[],
    );
  }
}

class ReferralEmailResult {
  final bool success;
  final bool sent;
  final String reason;
  final String message;

  const ReferralEmailResult({
    required this.success,
    required this.sent,
    required this.reason,
    required this.message,
  });

  factory ReferralEmailResult.fromMap(Map<Object?, Object?> map) {
    return ReferralEmailResult(
      success: map['success'] == true,
      sent: map['sent'] == true,
      reason: (map['reason'] ?? '').toString(),
      message: (map['message'] ?? '').toString(),
    );
  }
}

class DoctorReferralActionResult {
  final bool success;
  final String action;
  final String referralId;
  final String status;
  final bool alreadyProcessed;
  final bool notificationSent;

  const DoctorReferralActionResult({
    required this.success,
    required this.action,
    required this.referralId,
    required this.status,
    required this.alreadyProcessed,
    required this.notificationSent,
  });

  factory DoctorReferralActionResult.fromMap(Map<Object?, Object?> map) {
    return DoctorReferralActionResult(
      success: map['success'] == true,
      action: (map['action'] ?? '').toString(),
      referralId: (map['referralId'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      alreadyProcessed: map['alreadyProcessed'] == true,
      notificationSent: map['notificationSent'] == true,
    );
  }
}

class AccountPolicyService {
  AccountPolicyService._();

  static final AccountPolicyService instance = AccountPolicyService._();

  static const String _functionsRegion = 'us-central1';
  static const String _barangayRegistrationStatusCollection =
      'barangay_registration_status';

  FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(
    app: Firebase.app(),
    region: _functionsRegion,
  );
  String _normalizeBarangayCode(String? value) =>
      (value ?? '').trim().toUpperCase();

  Future<Map<String, BarangayAvailabilityStatus>>
  _getBarangayAvailabilityFromFirestore() async {
    final snapshot = await getFirestoreInstance()
        .collection(_barangayRegistrationStatusCollection)
        .get();
    final results = <String, BarangayAvailabilityStatus>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = BarangayAvailabilityStatus.fromMap(
        Map<Object?, Object?>.from({
          ...data,
          'barangayCode': data['barangayCode'] ?? doc.id,
        }),
      );
      if (status.isAvailable) {
        continue;
      }
      results[status.barangayCode] = status;
    }

    return results;
  }

  Future<RegistrationValidationResult> validateRegistrationPolicy({
    String? email,
    String? username,
    String? role,
    String? barangayCode,
  }) async {
    final callable = _functions.httpsCallable('validateRegistrationPolicy');
    final response = await callable.call(<String, dynamic>{
      'email': email?.trim(),
      'username': username?.trim(),
      'role': role?.trim(),
      'barangayCode': barangayCode?.trim(),
    });

    return RegistrationValidationResult.fromMap(
      Map<Object?, Object?>.from(response.data as Map),
    );
  }

  Future<RegistrationAccountResult> createRegistrationAccount({
    required String email,
    required String username,
    required String password,
    required String role,
    String? barangayCode,
  }) async {
    final callable = _functions.httpsCallable('createRegistrationAccount');
    final response = await callable.call(<String, dynamic>{
      'email': email.trim().toLowerCase(),
      'username': username.trim(),
      'password': password,
      'role': role.trim(),
      'barangayCode': barangayCode?.trim(),
    });
    return RegistrationAccountResult.fromMap(
      Map<Object?, Object?>.from(response.data as Map),
    );
  }

  Future<Map<String, BarangayAvailabilityStatus>>
  getBarangayAvailability() async {
    try {
      final callable = _functions.httpsCallable('getBarangayAvailability');
      final response = await callable.call();
      final raw = Map<Object?, Object?>.from(response.data as Map);
      final items = raw['items'];
      final results = <String, BarangayAvailabilityStatus>{};
      if (items is List) {
        for (final item in items.whereType<Map>()) {
          final status = BarangayAvailabilityStatus.fromMap(
            Map<Object?, Object?>.from(item),
          );
          results[status.barangayCode] = status;
        }
      }
      return results;
    } on FirebaseException {
      return _getBarangayAvailabilityFromFirestore();
    }
  }

  Future<BarangayAvailabilityStatus?> getBarangayAvailabilityStatus(
    String barangayCode,
  ) async {
    final normalizedBarangayCode = _normalizeBarangayCode(barangayCode);
    if (normalizedBarangayCode.isEmpty) {
      return null;
    }

    final snapshot = await getFirestoreInstance()
        .collection(_barangayRegistrationStatusCollection)
        .doc(normalizedBarangayCode)
        .get();
    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data() ?? <String, dynamic>{};
    return BarangayAvailabilityStatus.fromMap(
      Map<Object?, Object?>.from({
        ...data,
        'barangayCode': data['barangayCode'] ?? normalizedBarangayCode,
      }),
    );
  }

  Future<void> completeRegistration({
    required String uid,
    required String username,
    required String email,
    required String role,
    String? barangay,
    String? barangayCode,
    String? barangayDistrict,
    required String registrationNonce,
    Map<String, dynamic>? profile,
  }) async {
    final callable = _functions.httpsCallable('completeRegistration');
    await callable.call(<String, dynamic>{
      'uid': uid,
      'username': username.trim(),
      'email': email.trim(),
      'role': role.trim(),
      'barangay': barangay?.trim(),
      'barangayCode': barangayCode?.trim(),
      'barangayDistrict': barangayDistrict?.trim(),
      'registrationNonce': registrationNonce.trim(),
      if (profile != null) 'profile': profile,
    });
  }

  Future<DoctorAssignmentSuggestionResult> suggestDoctorAssignment({
    required String referralId,
  }) async {
    final callable = _functions.httpsCallable('suggestDoctorAssignment');
    final response = await callable.call(<String, dynamic>{
      'referralId': referralId,
    });
    return DoctorAssignmentSuggestionResult.fromMap(
      Map<Object?, Object?>.from(response.data as Map),
    );
  }

  Future<ManagedAccountResult> createChoAccount({
    required String fullName,
    required String email,
    required String role,
    String specialization = '',
    String availability = 'available',
    String accountStatus = 'active',
    String? accessRoleKey,
  }) async {
    final callable = _functions.httpsCallable('createChoAccount');
    final response = await callable.call(<String, dynamic>{
      'fullName': fullName.trim(),
      'email': email.trim(),
      'role': role.trim().toUpperCase(),
      'specialization': specialization.trim(),
      'availability': availability.trim().toLowerCase(),
      'accountStatus': accountStatus.trim().toLowerCase(),
      if (accessRoleKey != null && accessRoleKey.trim().isNotEmpty)
        'accessRoleKey': accessRoleKey.trim().toUpperCase(),
    });
    return ManagedAccountResult.fromMap(
      Map<Object?, Object?>.from(response.data as Map),
    );
  }

  Future<void> updateChoAccount({
    required String uid,
    String? role,
    String? accountStatus,
    String? barangay,
    String? barangayCode,
    String? barangayDistrict,
    String? fullName,
    String? username,
    String? contactNumber,
    String? assignedPurok,
    String? specialization,
    String? availability,
    String? accessRoleKey,
  }) async {
    final callable = _functions.httpsCallable('updateChoAccount');
    await callable.call(<String, dynamic>{
      'uid': uid,
      if (role != null) 'role': role.trim().toUpperCase(),
      if (accountStatus != null)
        'accountStatus': accountStatus.trim().toLowerCase(),
      if (barangay != null) 'barangay': barangay,
      if (barangayCode != null) 'barangayCode': barangayCode,
      if (barangayDistrict != null) 'barangayDistrict': barangayDistrict,
      if (fullName != null) 'fullName': fullName.trim(),
      if (username != null) 'username': username.trim(),
      if (contactNumber != null) 'contactNumber': contactNumber.trim(),
      if (assignedPurok != null) 'assignedPurok': assignedPurok.trim(),
      if (specialization != null) 'specialization': specialization,
      if (availability != null) 'availability': availability,
      if (accessRoleKey != null && accessRoleKey.trim().isNotEmpty)
        'accessRoleKey': accessRoleKey.trim().toUpperCase(),
    });
  }

  Future<void> archiveChoAccount({required String uid}) async {
    final callable = _functions.httpsCallable('archiveChoAccount');
    await callable.call(<String, dynamic>{'uid': uid.trim()});
  }

  Future<void> updateOwnBhwProfile({
    required String fullName,
    required String username,
    required String contactNumber,
  }) async {
    final callable = _functions.httpsCallable('updateOwnBhwProfile');
    await callable.call(<String, dynamic>{
      'fullName': fullName.trim(),
      'username': username.trim(),
      'contactNumber': contactNumber.trim(),
    });
  }

  Future<void> updateOwnChoProfile({
    required String fullName,
    required String username,
    required String contactNumber,
  }) async {
    final callable = _functions.httpsCallable('updateOwnChoProfile');
    await callable.call(<String, dynamic>{
      'fullName': fullName.trim(),
      'username': username.trim(),
      'contactNumber': contactNumber.trim(),
    });
  }

  Future<DoctorReferralActionResult> doctorReferralAction({
    required String referralId,
    required String action,
    String? reason,
    String? targetDoctorUid,
    String? operationId,
    String? status,
    String? doctorDiagnosis,
    String? doctorTreatment,
    String? doctorMedication,
    String? doctorNotes,
  }) async {
    final callable = _functions.httpsCallable('doctorReferralAction');
    final response = await callable.call(<String, dynamic>{
      'referralId': referralId.trim(),
      'action': action.trim(),
      if (reason != null) 'reason': reason.trim(),
      if (targetDoctorUid != null) 'targetDoctorUid': targetDoctorUid.trim(),
      if (operationId != null) 'operationId': operationId.trim(),
      if (status != null) 'status': status.trim(),
      if (doctorDiagnosis != null) 'doctorDiagnosis': doctorDiagnosis.trim(),
      if (doctorTreatment != null) 'doctorTreatment': doctorTreatment.trim(),
      if (doctorMedication != null) 'doctorMedication': doctorMedication.trim(),
      if (doctorNotes != null) 'doctorNotes': doctorNotes.trim(),
    });
    return DoctorReferralActionResult.fromMap(
      Map<Object?, Object?>.from(response.data as Map),
    );
  }

  Future<List<Map<String, dynamic>>> listDoctorTransferTargets() async {
    final callable = _functions.httpsCallable('listDoctorTransferTargets');
    final response = await callable.call();
    final raw = (response.data as Map)['doctors'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((doctor) => Map<String, dynamic>.from(doctor))
        .toList(growable: false);
  }

  Future<void> updateOwnDoctorProfile({
    required String fullName,
    required String username,
    required String contactNumber,
    required String professionalTitle,
    required String specialization,
  }) async {
    final callable = _functions.httpsCallable('updateOwnDoctorProfile');
    await callable.call(<String, dynamic>{
      'fullName': fullName.trim(),
      'username': username.trim(),
      'contactNumber': contactNumber.trim(),
      'professionalTitle': professionalTitle.trim(),
      'specialization': specialization.trim(),
    });
  }

  Future<void> reviewBhwRegistration({
    required String uid,
    required bool approved,
    String? rejectionReason,
  }) async {
    final callable = _functions.httpsCallable('reviewBhwRegistration');
    await callable.call(<String, dynamic>{
      'uid': uid,
      'approved': approved,
      if (rejectionReason != null) 'rejectionReason': rejectionReason.trim(),
    });
  }

  Future<RbacRoleCatalog> listAccessRoles() async {
    final callable = _functions.httpsCallable('listAccessRoles');
    final response = await callable.call();
    return RbacRoleCatalog.fromMap(
      Map<Object?, Object?>.from(response.data as Map),
    );
  }

  Future<RbacRoleDefinition> saveAccessRole({
    String? roleKey,
    required String name,
    required String description,
    required String baseRole,
    required List<String> permissions,
  }) async {
    final callable = _functions.httpsCallable('saveAccessRole');
    final response = await callable.call(<String, dynamic>{
      if (roleKey != null && roleKey.trim().isNotEmpty)
        'roleKey': roleKey.trim().toUpperCase(),
      'name': name.trim(),
      'description': description.trim(),
      'baseRole': baseRole.trim().toUpperCase(),
      'permissions': permissions,
    });
    final result = Map<Object?, Object?>.from(response.data as Map);
    return RbacRoleDefinition(
      roleKey: (result['roleKey'] ?? roleKey ?? '').toString(),
      name: name.trim(),
      description: description.trim(),
      baseRole: (result['baseRole'] ?? baseRole).toString(),
      permissions: result['permissions'] is List
          ? (result['permissions'] as List)
                .map((value) => value.toString())
                .toList()
          : permissions,
      isSystem: false,
      isProtected: false,
      active: true,
    );
  }

  Future<void> deleteAccessRole(String roleKey) async {
    final callable = _functions.httpsCallable('deleteAccessRole');
    await callable.call(<String, dynamic>{
      'roleKey': roleKey.trim().toUpperCase(),
    });
  }

  Future<DoctorAssignmentExecutionResult> assignDoctorToReferral({
    required String referralId,
    String? preferredDoctorUid,
  }) async {
    final callable = _functions.httpsCallable('assignDoctorToReferral');
    final response = await callable.call(<String, dynamic>{
      'referralId': referralId,
      'preferredDoctorUid': preferredDoctorUid?.trim(),
    });
    return DoctorAssignmentExecutionResult.fromMap(
      Map<Object?, Object?>.from(response.data as Map),
    );
  }

  Future<ReferralEmailResult> sendReferralAssignmentEmail({
    required String referralId,
    bool forceResend = false,
  }) async {
    final callable = _functions.httpsCallable('sendReferralAssignmentEmail');
    final response = await callable.call(<String, dynamic>{
      'referralId': referralId.trim(),
      'forceResend': forceResend,
    });
    return ReferralEmailResult.fromMap(
      Map<Object?, Object?>.from(response.data as Map),
    );
  }
}
