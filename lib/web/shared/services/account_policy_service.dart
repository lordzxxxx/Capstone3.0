import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:mycapstone_project/firebase_helper.dart';

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

class DoctorRegistrationResult {
  final bool success;
  final bool created;
  final String uid;
  final String doctorName;
  final String email;
  final String specialization;
  final String availability;
  final String? resetLink;

  const DoctorRegistrationResult({
    required this.success,
    required this.created,
    required this.uid,
    required this.doctorName,
    required this.email,
    required this.specialization,
    required this.availability,
    required this.resetLink,
  });

  factory DoctorRegistrationResult.fromMap(Map<Object?, Object?> map) {
    return DoctorRegistrationResult(
      success: map['success'] == true,
      created: map['created'] == true,
      uid: (map['uid'] ?? '').toString(),
      doctorName: (map['doctorName'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      specialization: (map['specialization'] ?? 'General Medicine').toString(),
      availability: (map['availability'] ?? 'available').toString(),
      resetLink: (map['resetLink'] ?? '').toString().trim().isEmpty
          ? null
          : (map['resetLink'] ?? '').toString(),
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

  const ManagedAccountResult({
    required this.success,
    required this.uid,
    required this.role,
    required this.email,
    required this.fullName,
    required this.activationEmailSent,
    required this.activationEmailReason,
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

class DoctorAssignmentEmailResult {
  final bool success;
  final bool sent;
  final String message;
  final String? reason;

  const DoctorAssignmentEmailResult({
    required this.success,
    required this.sent,
    required this.message,
    required this.reason,
  });

  factory DoctorAssignmentEmailResult.fromMap(Map<Object?, Object?> map) {
    final reasonText = (map['reason'] ?? '').toString().trim();
    final messageText = (map['message'] ?? '').toString().trim();
    final sent = map['sent'] == true;
    return DoctorAssignmentEmailResult(
      success: map['success'] == true,
      sent: sent,
      message: messageText.isEmpty
          ? (sent
                ? 'Assignment email sent successfully.'
                : 'Assignment email was not sent.')
          : messageText,
      reason: reasonText.isEmpty ? null : reasonText,
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

  Future<DoctorRegistrationResult> registerDoctorAccount({
    required String fullName,
    required String email,
    required String specialization,
    required String availability,
  }) async {
    final callable = _functions.httpsCallable('registerDoctorAccount');
    final response = await callable.call(<String, dynamic>{
      'fullName': fullName.trim(),
      'email': email.trim(),
      'specialization': specialization.trim(),
      'availability': availability.trim(),
    });
    return DoctorRegistrationResult.fromMap(
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
  }) async {
    final callable = _functions.httpsCallable('createChoAccount');
    final response = await callable.call(<String, dynamic>{
      'fullName': fullName.trim(),
      'email': email.trim(),
      'role': role.trim().toUpperCase(),
      'specialization': specialization.trim(),
      'availability': availability.trim().toLowerCase(),
      'accountStatus': accountStatus.trim().toLowerCase(),
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
    String? specialization,
    String? availability,
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
      if (specialization != null) 'specialization': specialization,
      if (availability != null) 'availability': availability,
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

  Future<DoctorAssignmentEmailResult> sendDoctorReferralAssignmentEmail({
    required String referralId,
    String? doctorEmail,
    String? doctorName,
  }) async {
    final callable = _functions.httpsCallable(
      'sendDoctorReferralAssignmentEmail',
    );
    final response = await callable.call(<String, dynamic>{
      'referralId': referralId.trim(),
      'doctorEmail': doctorEmail?.trim(),
      'doctorName': doctorName?.trim(),
    });
    return DoctorAssignmentEmailResult.fromMap(
      Map<Object?, Object?>.from(response.data as Map),
    );
  }
}
