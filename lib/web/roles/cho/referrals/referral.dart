import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_navigation.dart';
import 'package:mycapstone_project/web/roles/cho/portal/cho_portal_config.dart';
import 'package:mycapstone_project/shared/barangay_firestore_paths.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/shared/services/account_policy_service.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/shared/utils/referral_pdf.dart';
import 'package:mycapstone_project/web/shared/utils/report_download.dart';
import 'package:mycapstone_project/web/shared/utils/report_print.dart';
import 'package:mycapstone_project/web/shared/components/app_metric_card.dart';
import 'package:mycapstone_project/web/shared/components/web_data_components.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';

const Color _primaryAqua = Color(0xFF2F80ED);
const Color _darkDeepTeal = Color(0xFF071A33);
const Color _panelSurface = Color(0xFF0D274D);
const Color _panelAlt = Color(0xFF163B66);
const Color _lightOffWhite = Color(0xFFF5F5F5);
const Color _mutedCoolGray = Color(0xFF8EA5AE);
const List<String> _doctorSpecializationOptions = <String>[
  'General Medicine',
  'General Practice',
  'Cardiology',
  'Pediatrics',
  'Obstetrics',
  'Pulmonology',
  'Infectious Disease',
  'Family Medicine',
];
const List<String> _doctorAvailabilityOptions = <String>[
  'available',
  'busy',
  'limited',
  'unavailable',
];

/// CHO doctor-directory and filtered-referral browsing workspace.
///
/// This was previously named `CHOPreferralPage`, identically to the class
/// in `cho_referral_management.dart` — a naming collision, not a shared
/// implementation. That other page (reached from the sidebar "Referrals"
/// destination) owns the referral review/approval state machine
/// (`_ReferralRecord`, statuses: pending_review / hospital_assigned /
/// doctor_assigned / waiting_consultation / consulted / completed) and its
/// status vocabulary is the one `firestore.rules`' `canUpdateReferral`
/// actually checks (see `pending_review` / `returned_for_correction`
/// there). This page instead uses its own, different status vocabulary
/// (submitted / under_review / assigned / in_treatment / completed) and
/// adds doctor-registry management (register/edit/archive/restore),
/// referral filters, summary cards, and PDF printing that the sidebar page
/// does not have.
///
/// Both pages read/write the same root `referrals` collection, so a
/// referral's displayed status can differ depending on which page a CHO
/// user is looking at it from. Reconciling the two status vocabularies
/// into one is a real, pre-existing issue — deliberately not attempted in
/// the August 2026 panel-revision pass because it touches referral
/// creation (BHW app), both CHO pages, the doctor-facing view, and PDF
/// export, and a rushed merge risked breaking the referral workflow this
/// close to the deadline. Recommended follow-up: treat
/// `cho_referral_management.dart`'s vocabulary as authoritative (it's
/// what the deployed security rules assume) and port this page's
/// doctor-registry/filter/PDF features into that file, then retire this
/// one.
class CHOReferralWorkspacePage extends StatefulWidget {
  const CHOReferralWorkspacePage({super.key});

  @override
  State<CHOReferralWorkspacePage> createState() =>
      _CHOReferralWorkspacePageState();
}

class _CHOReferralWorkspacePageState extends State<CHOReferralWorkspacePage> {
  final FirebaseFirestore _firestore = getFirestoreInstance();
  final AccountPolicyService _accountPolicyService =
      AccountPolicyService.instance;
  final TextEditingController _searchController = TextEditingController();
  Stream<QuerySnapshot<Map<String, dynamic>>>? _referralsStream;

  UserAccessScope _scope = UserAccessScope.unauthenticated;
  bool _isLoading = true;
  bool _isRecoveringReferralsStream = false;
  int _referralsRecoveryAttempts = 0;
  String? _loadErrorMessage;
  String _selectedStatus = 'all';
  String _selectedBarangay = 'all';
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _doctorDocs =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  List<Map<String, dynamic>> _registeredDoctors = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _archivedDoctors = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _referralsStream = _createReferralsStream();
    _loadScope();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  String _formatDoctorRegistrationError(Object error) {
    if (error is FirebaseFunctionsException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        return message;
      }
      return error.code.replaceAll('-', ' ');
    }
    return error.toString();
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
  _loadDoctorDirectory({bool includeArchived = false}) async {
    final doctors = await _firestore
        .collection('users')
        .where('role', whereIn: const <String>['DOCTOR', 'doctor'])
        .get();
    final doctorDocs = includeArchived
        ? doctors.docs.toList(growable: false)
        : doctors.docs
              .where((doc) => !_isDoctorArchived(doc.data()))
              .toList(growable: false);
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

  bool _isDoctorArchived(Map<String, dynamic> data) {
    final accountStatus = (data['accountStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final isArchived = data['isArchived'] == true;
    return isArchived || accountStatus == 'archived';
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

  DocumentReference<Map<String, dynamic>>? _resolveDoctorUserRefFromCache(
    Map<String, dynamic> doctor,
  ) {
    final candidateUserUid = (doctor['userUid'] ?? doctor['uid'] ?? '')
        .toString()
        .trim();
    if (candidateUserUid.isNotEmpty) {
      for (final userDoc in _doctorDocs) {
        if (userDoc.id == candidateUserUid) {
          return userDoc.reference;
        }
      }
    }

    final candidateId = (doctor['id'] ?? '').toString().trim();
    if (candidateId.isNotEmpty) {
      for (final userDoc in _doctorDocs) {
        if (userDoc.id == candidateId) {
          return userDoc.reference;
        }
      }
    }

    final normalizedEmail = (doctor['email'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (normalizedEmail.isNotEmpty) {
      for (final userDoc in _doctorDocs) {
        final docEmail = (userDoc.data()['email'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (docEmail.isNotEmpty && docEmail == normalizedEmail) {
          return userDoc.reference;
        }
      }
    }

    return null;
  }

  Future<DocumentReference<Map<String, dynamic>>?> _resolveDoctorRegistryRef(
    Map<String, dynamic> doctor, {
    String? fallbackUserUid,
  }) async {
    final registryDocId = (doctor['registryDocId'] ?? '').toString().trim();
    if (registryDocId.isNotEmpty) {
      final registryRef = _firestore
          .collection('doctor_registry')
          .doc(registryDocId);
      final registryDoc = await registryRef.get();
      if (registryDoc.exists) {
        return registryRef;
      }
    }

    final candidateId = (doctor['id'] ?? '').toString().trim();
    if (candidateId.isNotEmpty) {
      final candidateRef = _firestore
          .collection('doctor_registry')
          .doc(candidateId);
      final candidateDoc = await candidateRef.get();
      if (candidateDoc.exists) {
        return candidateRef;
      }
    }

    final resolvedUserUid =
        (fallbackUserUid ?? doctor['userUid'] ?? doctor['uid'] ?? '')
            .toString()
            .trim();
    if (resolvedUserUid.isNotEmpty) {
      final byUserUid = await _firestore
          .collection('doctor_registry')
          .where('userUid', isEqualTo: resolvedUserUid)
          .limit(1)
          .get();
      if (byUserUid.docs.isNotEmpty) {
        return byUserUid.docs.first.reference;
      }

      final byUid = await _firestore
          .collection('doctor_registry')
          .where('uid', isEqualTo: resolvedUserUid)
          .limit(1)
          .get();
      if (byUid.docs.isNotEmpty) {
        return byUid.docs.first.reference;
      }
    }

    final email = (doctor['email'] ?? '').toString().trim();
    final normalizedEmail = email.toLowerCase();
    if (normalizedEmail.isNotEmpty) {
      final byEmailLower = await _firestore
          .collection('doctor_registry')
          .where('emailLower', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      if (byEmailLower.docs.isNotEmpty) {
        return byEmailLower.docs.first.reference;
      }

      final byEmail = await _firestore
          .collection('doctor_registry')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (byEmail.docs.isNotEmpty) {
        return byEmail.docs.first.reference;
      }
    }

    return null;
  }

  Future<void> _refreshDoctorDirectoryState() async {
    final allDoctorDocs = await _loadDoctorDirectory(includeArchived: true);
    final doctorDocs = allDoctorDocs
        .where((doc) => !_isDoctorArchived(doc.data()))
        .toList(growable: false);
    List<Map<String, dynamic>> registeredDoctors;
    List<Map<String, dynamic>> archivedDoctors;
    try {
      final registrySnapshot = await _firestore
          .collection('doctor_registry')
          .get();
      registeredDoctors = _mergeDoctorSources(
        userDoctors: doctorDocs,
        registrySnapshot: registrySnapshot,
        includeArchived: false,
      );
      archivedDoctors = _mergeDoctorSources(
        userDoctors: allDoctorDocs,
        registrySnapshot: registrySnapshot,
        includeArchived: true,
      );
    } catch (_) {
      registeredDoctors = _doctorListFromUserDocs(doctorDocs);
      final archivedUserDocs = allDoctorDocs
          .where((doc) => _isDoctorArchived(doc.data()))
          .toList(growable: false);
      archivedDoctors = _doctorListFromUserDocs(archivedUserDocs);
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _doctorDocs = doctorDocs;
      _registeredDoctors = registeredDoctors;
      _archivedDoctors = archivedDoctors;
    });
  }

  Future<void> _applyDoctorDirectoryUpdate({
    required Map<String, dynamic> doctor,
    required String fullName,
    required String specialization,
    required String availability,
    required bool archive,
  }) async {
    final normalizedName = fullName.trim();
    final normalizedSpecialization = specialization.trim().isEmpty
        ? 'General Medicine'
        : specialization.trim();
    final normalizedAvailability = availability.trim().toLowerCase();
    final availabilityState = archive ? 'unavailable' : normalizedAvailability;

    final userRef = _resolveDoctorUserRefFromCache(doctor);
    final registryRef = await _resolveDoctorRegistryRef(
      doctor,
      fallbackUserUid: userRef?.id,
    );

    if (userRef == null && registryRef == null) {
      throw StateError('Doctor record could not be resolved.');
    }

    final doctorEmail = (doctor['email'] ?? '').toString().trim();
    final doctorEmailLower = doctorEmail.toLowerCase();
    final timestamp = FieldValue.serverTimestamp();

    final payload = <String, dynamic>{
      'fullName': normalizedName,
      'username': normalizedName,
      'displayName': normalizedName,
      'specialization': normalizedSpecialization,
      'doctorSpecialization': normalizedSpecialization,
      'availability': availabilityState,
      'doctorAvailability': availabilityState,
      'status': availabilityState,
      'accountStatus': archive ? 'archived' : 'active',
      'isArchived': archive,
      'updatedAt': timestamp,
      'archivedAt': archive ? timestamp : FieldValue.delete(),
    };

    final batch = _firestore.batch();

    if (userRef != null) {
      final userPayload = <String, dynamic>{...payload};
      if (doctorEmailLower.isNotEmpty) {
        userPayload['emailLower'] = doctorEmailLower;
      }
      batch.set(userRef, userPayload, SetOptions(merge: true));
    }

    if (registryRef != null) {
      final registryPayload = <String, dynamic>{...payload};
      if (doctorEmail.isNotEmpty) {
        registryPayload['email'] = doctorEmail;
        registryPayload['emailLower'] = doctorEmailLower;
      }
      if (userRef != null) {
        registryPayload['userUid'] = userRef.id;
        registryPayload['uid'] = userRef.id;
      }
      batch.set(registryRef, registryPayload, SetOptions(merge: true));
    }

    await batch.commit();
    await _refreshDoctorDirectoryState();
  }

  Future<void> _showEditDoctorDialog(Map<String, dynamic> doctor) async {
    final formKey = GlobalKey<FormState>();
    final fullNameController = TextEditingController(
      text: (doctor['fullName'] ?? 'Doctor').toString(),
    );

    String selectedSpecialization = _doctorSpecialization(doctor);
    if (!_doctorSpecializationOptions.contains(selectedSpecialization)) {
      selectedSpecialization = _doctorSpecializationOptions.first;
    }

    String selectedAvailability = _doctorAvailability(doctor);
    if (!_doctorAvailabilityOptions.contains(selectedAvailability)) {
      selectedAvailability = _doctorAvailabilityOptions.first;
    }

    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: _panelSurface,
              title: const Text(
                'Edit Doctor',
                style: TextStyle(color: _lightOffWhite),
              ),
              content: SizedBox(
                width: 520,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: fullNameController,
                        style: const TextStyle(color: _lightOffWhite),
                        decoration: _inputDecoration('Doctor full name'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Doctor name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedSpecialization,
                        dropdownColor: _panelAlt,
                        style: const TextStyle(color: _lightOffWhite),
                        decoration: _inputDecoration('Specialization'),
                        items: _doctorSpecializationOptions
                            .map(
                              (value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => selectedSpecialization = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedAvailability,
                        dropdownColor: _panelAlt,
                        style: const TextStyle(color: _lightOffWhite),
                        decoration: _inputDecoration('Availability'),
                        items: _doctorAvailabilityOptions
                            .map(
                              (value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(_doctorAvailabilityLabel(value)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => selectedAvailability = value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }

                          setDialogState(() => isSaving = true);

                          try {
                            await _applyDoctorDirectoryUpdate(
                              doctor: doctor,
                              fullName: fullNameController.text.trim(),
                              specialization: selectedSpecialization,
                              availability: selectedAvailability,
                              archive: false,
                            );

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }

                            if (!mounted) {
                              return;
                            }
                            Get.snackbar(
                              'Doctor updated',
                              '${fullNameController.text.trim()} was updated successfully.',
                              backgroundColor: Colors.green,
                              colorText: Colors.white,
                            );
                          } catch (error) {
                            setDialogState(() => isSaving = false);
                            Get.snackbar(
                              'Update failed',
                              'Could not update doctor details: $error',
                              backgroundColor: Colors.redAccent,
                              colorText: Colors.white,
                            );
                          }
                        },
                  icon: isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(isSaving ? 'Saving' : 'Save changes'),
                ),
              ],
            );
          },
        );
      },
    );

    fullNameController.dispose();
  }

  Future<void> _archiveDoctorFromDirectory(Map<String, dynamic> doctor) async {
    final doctorName = (doctor['fullName'] ?? 'this doctor').toString().trim();
    final shouldArchive = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _panelSurface,
          title: const Text(
            'Archive Doctor',
            style: TextStyle(color: _lightOffWhite),
          ),
          content: Text(
            'Archive $doctorName from the active CHO doctor list? This keeps the record for history but removes it from active assignment.',
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.82),
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.archive_outlined),
              label: const Text('Archive'),
            ),
          ],
        );
      },
    );

    if (shouldArchive != true) {
      return;
    }

    try {
      await _applyDoctorDirectoryUpdate(
        doctor: doctor,
        fullName: doctorName.isEmpty ? 'Doctor' : doctorName,
        specialization: _doctorSpecialization(doctor),
        availability: 'unavailable',
        archive: true,
      );

      if (!mounted) {
        return;
      }
      Get.snackbar(
        'Doctor archived',
        '$doctorName was archived and removed from active assignment.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
    } catch (error) {
      Get.snackbar(
        'Archive failed',
        'Could not archive doctor: $error',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _restoreDoctorFromDirectory(Map<String, dynamic> doctor) async {
    final doctorName = _doctorDisplayName(doctor).trim().isEmpty
        ? 'Doctor'
        : _doctorDisplayName(doctor).trim();
    final shouldRestore = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _panelSurface,
          title: const Text(
            'Restore Doctor',
            style: TextStyle(color: _lightOffWhite),
          ),
          content: Text(
            'Restore $doctorName to the active CHO doctor list?',
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.82),
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Restore'),
            ),
          ],
        );
      },
    );

    if (shouldRestore != true) {
      return;
    }

    try {
      var restoredAvailability = _doctorAvailability(doctor);
      if (restoredAvailability.isEmpty ||
          restoredAvailability == 'unavailable') {
        restoredAvailability = 'available';
      }
      if (!_doctorAvailabilityOptions.contains(restoredAvailability)) {
        restoredAvailability = 'available';
      }

      await _applyDoctorDirectoryUpdate(
        doctor: doctor,
        fullName: doctorName,
        specialization: _doctorSpecialization(doctor),
        availability: restoredAvailability,
        archive: false,
      );

      if (!mounted) {
        return;
      }
      Get.snackbar(
        'Doctor restored',
        '$doctorName is active again and can receive referrals.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (error) {
      Get.snackbar(
        'Restore failed',
        'Could not restore doctor: $error',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
    }
  }

  String _assignmentModeLabel(String mode, String source) {
    if (mode == 'smart' && source == 'bhw_auto') {
      return 'AI auto-assignment';
    }
    if (mode == 'smart') {
      return 'Smart assignment';
    }
    if (mode == 'manual' && source == 'bhw_selected') {
      return 'BHW-selected doctor';
    }
    return 'Manual assignment';
  }

  String _doctorOptionLabel(Map<String, dynamic> data) {
    return '${_doctorDisplayName(data)} • ${_doctorSpecialization(data)} • ${_doctorAvailabilityLabel(_doctorAvailability(data))}';
  }

  Future<void> _showDoctorRegistrationResultDialog(
    DoctorRegistrationResult result,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _panelSurface,
          title: const Text(
            'Doctor Ready',
            style: TextStyle(color: _lightOffWhite),
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${result.doctorName} is now listed in the referral directory as ${result.specialization}.',
                  style: TextStyle(
                    color: _lightOffWhite.withValues(alpha: 0.82),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                _buildInfoChip(result.email),
                _buildInfoChip(result.specialization),
                _buildInfoChip(_doctorAvailabilityLabel(result.availability)),
                if (result.resetLink != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Password setup link',
                    style: TextStyle(
                      color: _lightOffWhite.withValues(alpha: 0.92),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _darkDeepTeal,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SelectableText(
                      result.resetLink!,
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.8),
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDoctorRegistryDialog() async {
    final formKey = GlobalKey<FormState>();
    final fullNameController = TextEditingController();
    final emailController = TextEditingController();
    String specialization = _doctorSpecializationOptions.first;
    String availability = _doctorAvailabilityOptions.first;
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: _panelSurface,
              title: const Text(
                'Doctor Registry',
                style: TextStyle(color: _lightOffWhite),
              ),
              content: SizedBox(
                width: 560,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _darkDeepTeal,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _primaryAqua.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Text(
                          'Add a doctor account directly from CHO so referrals can be matched by specialization and availability immediately.',
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.8),
                            height: 1.45,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: fullNameController,
                        style: const TextStyle(color: _lightOffWhite),
                        decoration: _inputDecoration('Doctor full name'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Doctor name is required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: _lightOffWhite),
                        decoration: _inputDecoration('Doctor email'),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) {
                            return 'Doctor email is required';
                          }
                          if (!text.contains('@')) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: specialization,
                        dropdownColor: _panelAlt,
                        style: const TextStyle(color: _lightOffWhite),
                        decoration: _inputDecoration('Specialization'),
                        items: _doctorSpecializationOptions
                            .map(
                              (value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => specialization = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: availability,
                        dropdownColor: _panelAlt,
                        style: const TextStyle(color: _lightOffWhite),
                        decoration: _inputDecoration('Availability'),
                        items: _doctorAvailabilityOptions
                            .map(
                              (value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(_doctorAvailabilityLabel(value)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => availability = value);
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Current doctor roster',
                        style: TextStyle(
                          color: _lightOffWhite.withValues(alpha: 0.92),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Submitting an existing doctor email updates that doctor\'s specialization and availability in this directory.',
                        style: TextStyle(
                          color: _lightOffWhite.withValues(alpha: 0.7),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: SingleChildScrollView(
                          child: Column(
                            children: _doctorDocs
                                .map((doctorDoc) {
                                  final doctorData = doctorDoc.data();
                                  final availabilityColor =
                                      _doctorAvailabilityColor(
                                        _doctorAvailability(doctorData),
                                      );
                                  return Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: _darkDeepTeal,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: _primaryAqua.withValues(
                                          alpha: 0.12,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _doctorDisplayName(doctorData),
                                                style: const TextStyle(
                                                  color: _lightOffWhite,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                (doctorData['email'] ?? '')
                                                    .toString(),
                                                style: TextStyle(
                                                  color: _lightOffWhite
                                                      .withValues(alpha: 0.66),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            _buildInfoChip(
                                              _doctorSpecialization(doctorData),
                                            ),
                                            const SizedBox(height: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: availabilityColor
                                                    .withValues(alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border: Border.all(
                                                  color: availabilityColor
                                                      .withValues(alpha: 0.32),
                                                ),
                                              ),
                                              child: Text(
                                                _doctorAvailabilityLabel(
                                                  _doctorAvailability(
                                                    doctorData,
                                                  ),
                                                ),
                                                style: TextStyle(
                                                  color: availabilityColor,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                })
                                .toList(growable: false),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }
                          setDialogState(() => isSubmitting = true);
                          try {
                            final result = await _accountPolicyService
                                .registerDoctorAccount(
                                  fullName: fullNameController.text.trim(),
                                  email: emailController.text.trim(),
                                  specialization: specialization,
                                  availability: availability,
                                );
                            await _refreshDoctorDirectoryState();
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                            Get.snackbar(
                              'Doctor registered',
                              '${result.doctorName} is now available for referral assignment.',
                              backgroundColor: Colors.green,
                              colorText: Colors.white,
                            );
                            await _showDoctorRegistrationResultDialog(result);
                          } catch (error) {
                            setDialogState(() => isSubmitting = false);
                            Get.snackbar(
                              'Registration failed',
                              'Could not register doctor: ${_formatDoctorRegistrationError(error)}',
                              backgroundColor: Colors.redAccent,
                              colorText: Colors.white,
                            );
                          }
                        },
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(isSubmitting ? 'Saving' : 'Register doctor'),
                ),
              ],
            );
          },
        );
      },
    );

    fullNameController.dispose();
    emailController.dispose();
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

      if (!scope.canViewAllBarangays) {
        if (!mounted) return;
        Get.snackbar(
          'Access denied',
          'Only CHO accounts can open the referral receiving page.',
          backgroundColor: Colors.redAccent,
          colorText: Colors.white,
        );
        Get.offAllNamed(WebRoutes.login);
        return;
      }

      List<QueryDocumentSnapshot<Map<String, dynamic>>> allDoctorDocs =
          <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> doctorDocs =
          <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      List<Map<String, dynamic>> registeredDoctors = <Map<String, dynamic>>[];
      List<Map<String, dynamic>> archivedDoctors = <Map<String, dynamic>>[];
      try {
        allDoctorDocs = await _loadDoctorDirectory(includeArchived: true);
        doctorDocs = allDoctorDocs
            .where((doc) => !_isDoctorArchived(doc.data()))
            .toList(growable: false);
      } catch (_) {
        allDoctorDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        doctorDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      }

      try {
        final registrySnapshot = await _firestore
            .collection('doctor_registry')
            .get();
        registeredDoctors = _mergeDoctorSources(
          userDoctors: doctorDocs,
          registrySnapshot: registrySnapshot,
          includeArchived: false,
        );
        archivedDoctors = _mergeDoctorSources(
          userDoctors: allDoctorDocs,
          registrySnapshot: registrySnapshot,
          includeArchived: true,
        );
      } catch (_) {
        registeredDoctors = _doctorListFromUserDocs(doctorDocs);
        final archivedUserDocs = allDoctorDocs
            .where((doc) => _isDoctorArchived(doc.data()))
            .toList(growable: false);
        archivedDoctors = _doctorListFromUserDocs(archivedUserDocs);
      }

      if (!mounted) return;
      setState(() {
        _scope = scope;
        _doctorDocs = doctorDocs;
        _registeredDoctors = registeredDoctors;
        _archivedDoctors = archivedDoctors;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadErrorMessage =
            'Could not initialize the CHO referral receiving page: $error';
        _registeredDoctors = <Map<String, dynamic>>[];
        _archivedDoctors = <Map<String, dynamic>>[];
      });
    }
  }

  List<Map<String, dynamic>> _doctorListFromUserDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> userDoctors,
  ) {
    final doctors = userDoctors
        .map((doctorDoc) {
          final data = doctorDoc.data();
          return <String, dynamic>{
            'id': doctorDoc.id,
            'uid': doctorDoc.id,
            'userUid': doctorDoc.id,
            'registryDocId': '',
            'fullName':
                (data['username'] ??
                        data['fullName'] ??
                        data['email'] ??
                        'Doctor')
                    .toString(),
            'email': (data['email'] ?? '').toString(),
            'specialization': (data['specialization'] ?? 'General Medicine')
                .toString(),
            'availability':
                (data['availability'] ?? data['status'] ?? 'Available')
                    .toString(),
            'accountStatus': (data['accountStatus'] ?? 'active').toString(),
            'isArchived': data['isArchived'] == true,
          };
        })
        .toList(growable: false);

    doctors.sort((a, b) {
      final aName = (a['fullName'] ?? '').toString().toLowerCase();
      final bName = (b['fullName'] ?? '').toString().toLowerCase();
      return aName.compareTo(bName);
    });
    return doctors;
  }

  List<Map<String, dynamic>> _mergeDoctorSources({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> userDoctors,
    required QuerySnapshot<Map<String, dynamic>> registrySnapshot,
    bool includeArchived = false,
  }) {
    final merged = <String, Map<String, dynamic>>{};

    for (final registryDoc in registrySnapshot.docs) {
      final data = registryDoc.data();
      final isArchived = _isDoctorArchived(data);
      if (includeArchived != isArchived) {
        continue;
      }
      final fullName =
          (data['fullName'] ?? data['username'] ?? data['email'] ?? 'Doctor')
              .toString();
      final email = (data['email'] ?? '').toString();
      final key = email.trim().toLowerCase().isEmpty
          ? 'registry-${registryDoc.id}'
          : email.trim().toLowerCase();
      merged[key] = <String, dynamic>{
        'id': registryDoc.id,
        'uid': (data['userUid'] ?? data['uid'] ?? '').toString(),
        'userUid': (data['userUid'] ?? data['uid'] ?? '').toString(),
        'registryDocId': registryDoc.id,
        'fullName': fullName,
        'email': email,
        'specialization': (data['specialization'] ?? 'General Medicine')
            .toString(),
        'availability': (data['availability'] ?? data['status'] ?? 'Available')
            .toString(),
        'accountStatus': (data['accountStatus'] ?? 'active').toString(),
        'isArchived': data['isArchived'] == true,
      };
    }

    for (final userDoc in userDoctors) {
      final data = userDoc.data();
      final isArchived = _isDoctorArchived(data);
      if (includeArchived != isArchived) {
        continue;
      }
      final fullName =
          (data['username'] ?? data['fullName'] ?? data['email'] ?? 'Doctor')
              .toString();
      final email = (data['email'] ?? '').toString();
      final key = email.trim().toLowerCase().isEmpty
          ? 'users-${userDoc.id}'
          : email.trim().toLowerCase();
      merged.putIfAbsent(
        key,
        () => <String, dynamic>{
          'id': userDoc.id,
          'uid': userDoc.id,
          'userUid': userDoc.id,
          'registryDocId': '',
          'fullName': fullName,
          'email': email,
          'specialization': (data['specialization'] ?? 'General Medicine')
              .toString(),
          'availability':
              (data['availability'] ?? data['status'] ?? 'Available')
                  .toString(),
          'accountStatus': (data['accountStatus'] ?? 'active').toString(),
          'isArchived': data['isArchived'] == true,
        },
      );

      final mergedDoctor = merged[key]!;
      mergedDoctor['userUid'] = userDoc.id;
      mergedDoctor['uid'] = userDoc.id;
      if ((mergedDoctor['email'] ?? '').toString().trim().isEmpty) {
        mergedDoctor['email'] = email;
      }
      if ((mergedDoctor['fullName'] ?? '').toString().trim().isEmpty) {
        mergedDoctor['fullName'] = fullName;
      }
    }

    final doctors = merged.values.toList(growable: false);
    doctors.sort((a, b) {
      final aName = (a['fullName'] ?? '').toString().toLowerCase();
      final bName = (b['fullName'] ?? '').toString().toLowerCase();
      return aName.compareTo(bName);
    });
    return doctors;
  }

  List<Map<String, dynamic>> _safeRegisteredDoctors() {
    try {
      final dynamic cached = _registeredDoctors;
      if (cached is List<Map<String, dynamic>>) {
        return cached;
      }
      if (cached is List) {
        return cached
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList(growable: false);
      }
      return _doctorListFromUserDocs(_doctorDocs);
    } catch (_) {
      // Hot reload can leave newly added state fields uninitialized on web.
      return _doctorListFromUserDocs(_doctorDocs);
    }
  }

  List<Map<String, dynamic>> _safeArchivedDoctors() {
    try {
      final dynamic cached = _archivedDoctors;
      if (cached is List<Map<String, dynamic>>) {
        return cached;
      }
      if (cached is List) {
        return cached
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList(growable: false);
      }
      return const <Map<String, dynamic>>[];
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  bool _matchesAvailableStatus({
    required dynamic status,
    required dynamic availability,
  }) {
    final statusText = (status ?? '').toString().trim();
    final availabilityText = (availability ?? '').toString().trim();
    final normalized = (statusText.isNotEmpty ? statusText : availabilityText)
        .toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized.contains('unavailable') || normalized.contains('limited')) {
      return false;
    }
    return normalized == 'available' || normalized.startsWith('available');
  }

  Future<List<Map<String, dynamic>>>
  _fetchAvailableDoctorsFromFirestore() async {
    final usersSnapshot = await _firestore
        .collection('users')
        .where('role', whereIn: const <String>['DOCTOR', 'doctor'])
        .get();
    final registrySnapshot = await _firestore
        .collection('doctor_registry')
        .get();

    final usersByEmail =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final userDoc in usersSnapshot.docs) {
      final email = (userDoc.data()['email'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (email.isNotEmpty) {
        usersByEmail[email] = userDoc;
      }
    }

    final seenKeys = <String>{};
    final availableDoctors = <Map<String, dynamic>>[];

    for (final registryDoc in registrySnapshot.docs) {
      final registryData = registryDoc.data();
      if (_isDoctorArchived(registryData)) {
        continue;
      }
      final isAvailable = _matchesAvailableStatus(
        status: registryData['status'],
        availability: registryData['availability'],
      );
      if (!isAvailable) {
        continue;
      }

      final email = (registryData['email'] ?? '').toString().trim();
      final userDoc = email.isEmpty ? null : usersByEmail[email.toLowerCase()];
      final linkedUserData = userDoc?.data();
      final doctorKey = userDoc?.id ?? 'registry-${registryDoc.id}';

      if (seenKeys.contains(doctorKey)) {
        continue;
      }
      seenKeys.add(doctorKey);

      availableDoctors.add(<String, dynamic>{
        'uid': doctorKey,
        'userUid': userDoc?.id ?? '',
        'registryDocId': registryDoc.id,
        'fullName':
            (registryData['fullName'] ??
                    linkedUserData?['username'] ??
                    linkedUserData?['fullName'] ??
                    email)
                .toString(),
        'email': email,
        'specialization':
            (registryData['specialization'] ??
                    linkedUserData?['specialization'] ??
                    'General Medicine')
                .toString(),
        'availability':
            (registryData['availability'] ??
                    registryData['status'] ??
                    'Available')
                .toString(),
      });
    }

    for (final userDoc in usersSnapshot.docs) {
      final userData = userDoc.data();
      if (_isDoctorArchived(userData)) {
        continue;
      }
      final isAvailable = _matchesAvailableStatus(
        status: userData['status'],
        availability: userData['availability'],
      );
      if (!isAvailable || seenKeys.contains(userDoc.id)) {
        continue;
      }

      final email = (userData['email'] ?? '').toString().trim();
      seenKeys.add(userDoc.id);
      availableDoctors.add(<String, dynamic>{
        'uid': userDoc.id,
        'userUid': userDoc.id,
        'registryDocId': '',
        'fullName': (userData['username'] ?? userData['fullName'] ?? email)
            .toString(),
        'email': email,
        'specialization': (userData['specialization'] ?? 'General Medicine')
            .toString(),
        'availability':
            (userData['availability'] ?? userData['status'] ?? 'Available')
                .toString(),
      });
    }

    availableDoctors.sort((a, b) {
      final aName = (a['fullName'] ?? '').toString().toLowerCase();
      final bName = (b['fullName'] ?? '').toString().toLowerCase();
      return aName.compareTo(bName);
    });
    return availableDoctors;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _createReferralsStream() {
    return _firestore.collection('referrals').snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _ensureReferralsStream() {
    return _referralsStream ??= _createReferralsStream();
  }

  bool _isReferralsTargetConflict(Object? error) {
    final message = (error ?? '').toString().toLowerCase();
    return message.contains('target id already exists') ||
        message.contains('[cloud_firestore/already-exists]');
  }

  void _recoverReferralsStream() {
    if (!mounted || _isRecoveringReferralsStream) {
      return;
    }

    setState(() => _isRecoveringReferralsStream = true);
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _referralsStream = _createReferralsStream();
        _referralsRecoveryAttempts += 1;
        _isRecoveringReferralsStream = false;
      });
    });
  }

  int _timestampMillis(dynamic value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }
    return 0;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortedDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = docs.toList();
    sorted.sort((left, right) {
      final leftData = left.data();
      final rightData = right.data();
      final leftMillis = _timestampMillis(
        leftData['updatedAt'] ?? leftData['createdAt'],
      );
      final rightMillis = _timestampMillis(
        rightData['updatedAt'] ?? rightData['createdAt'],
      );
      return rightMillis.compareTo(leftMillis);
    });
    return sorted;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    return docs
        .where((doc) {
          final data = doc.data();
          final barangay = (data['barangay'] ?? 'Unassigned barangay')
              .toString();
          final status = (data['status'] ?? 'submitted').toString();
          final matchesBarangay =
              _selectedBarangay == 'all' ||
              barangay.toLowerCase() == _selectedBarangay.toLowerCase();
          final matchesStatus =
              _selectedStatus == 'all' || status == _selectedStatus;
          final matchesSearch =
              query.isEmpty ||
              <String>[
                (data['patientName'] ?? '').toString(),
                (data['patientRecordId'] ?? '').toString(),
                (data['chiefComplaint'] ?? '').toString(),
                (data['referralReason'] ?? '').toString(),
                (data['createdByName'] ?? data['createdByEmail'] ?? '')
                    .toString(),
                barangay,
              ].any((field) => field.toLowerCase().contains(query));
          return matchesBarangay && matchesStatus && matchesSearch;
        })
        .toList(growable: false);
  }

  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _groupByBarangay(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final grouped =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in docs) {
      final barangay = (doc.data()['barangay'] ?? 'Unassigned barangay')
          .toString()
          .trim();
      final key = barangay.isEmpty ? 'Unassigned barangay' : barangay;
      grouped.putIfAbsent(
        key,
        () => <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      );
      grouped[key]!.add(doc);
    }
    final sortedKeys = grouped.keys.toList()..sort();
    return <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{
      for (final key in sortedKeys) key: grouped[key]!,
    };
  }

  String _formatTimestamp(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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

  bool _hasDoctorUpdate(Map<String, dynamic> data) {
    return (data['doctorDiagnosis'] ?? '').toString().trim().isNotEmpty ||
        (data['doctorTreatment'] ?? '').toString().trim().isNotEmpty ||
        (data['doctorMedication'] ?? '').toString().trim().isNotEmpty ||
        (data['doctorNotes'] ?? '').toString().trim().isNotEmpty;
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

  Future<void> _showReviewAssignDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    List<Map<String, dynamic>> availableDoctors;
    try {
      availableDoctors = await _fetchAvailableDoctorsFromFirestore();
    } catch (error) {
      Get.snackbar(
        'Verification failed',
        'Could not verify available doctors from Firestore: $error',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
      return;
    }

    if (availableDoctors.isEmpty) {
      Get.snackbar(
        'No available doctors',
        'No doctors with status "available" were found in Firestore.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    final existingData = doc.data();
    String? selectedDoctorUid;
    bool isAssigning = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: _panelSurface,
              title: const Text(
                'Select Available Doctor',
                style: TextStyle(color: _lightOffWhite),
              ),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select a doctor from Available doctors. Assignment will be saved automatically.',
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.78),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: selectedDoctorUid,
                      dropdownColor: _panelAlt,
                      style: const TextStyle(color: _lightOffWhite),
                      decoration: _inputDecoration('Available doctor'),
                      items: availableDoctors.map((doctor) {
                        final fullName = (doctor['fullName'] ?? 'Doctor')
                            .toString();
                        final specialization =
                            (doctor['specialization'] ?? 'General Medicine')
                                .toString();
                        final availability =
                            (doctor['availability'] ?? 'Available').toString();
                        return DropdownMenuItem<String>(
                          value: (doctor['uid'] ?? '').toString(),
                          child: Text(
                            '$fullName - $specialization ($availability)',
                          ),
                        );
                      }).toList(),
                      onChanged: isAssigning
                          ? null
                          : (value) {
                              if (value == null || value.isEmpty) {
                                return;
                              }

                              setDialogState(() {
                                selectedDoctorUid = value;
                                isAssigning = true;
                              });

                              () async {
                                final selectedDoctor = availableDoctors
                                    .firstWhere(
                                      (doctor) =>
                                          (doctor['uid'] ?? '').toString() ==
                                          value,
                                    );
                                final selectedDoctorName =
                                    (selectedDoctor['fullName'] ?? 'Doctor')
                                        .toString();
                                final selectedDoctorEmail =
                                    (selectedDoctor['email'] ?? '').toString();
                                final selectedDoctorSpecialization =
                                    (selectedDoctor['specialization'] ??
                                            'General Medicine')
                                        .toString();
                                final assignedDoctorUid =
                                    ((selectedDoctor['userUid'] ?? '')
                                        .toString()
                                        .trim()
                                        .isNotEmpty)
                                    ? (selectedDoctor['userUid'] ?? '')
                                          .toString()
                                          .trim()
                                    : (selectedDoctor['uid'] ?? '')
                                          .toString()
                                          .trim();

                                DocumentReference<Map<String, dynamic>>
                                registryRef;
                                final registryDocId =
                                    (selectedDoctor['registryDocId'] ?? '')
                                        .toString()
                                        .trim();
                                if (registryDocId.isNotEmpty) {
                                  registryRef = _firestore
                                      .collection('doctor_registry')
                                      .doc(registryDocId);
                                } else if (selectedDoctorEmail.isNotEmpty) {
                                  final existingRegistry = await _firestore
                                      .collection('doctor_registry')
                                      .where(
                                        'email',
                                        isEqualTo: selectedDoctorEmail,
                                      )
                                      .limit(1)
                                      .get();
                                  registryRef = existingRegistry.docs.isNotEmpty
                                      ? existingRegistry.docs.first.reference
                                      : _firestore
                                            .collection('doctor_registry')
                                            .doc();
                                } else {
                                  registryRef = _firestore
                                      .collection('doctor_registry')
                                      .doc();
                                }

                                final updatePayload = <String, dynamic>{
                                  'assignedDoctorUid': assignedDoctorUid,
                                  'assignedDoctorName': selectedDoctorName,
                                  'assignedDoctorEmail': selectedDoctorEmail,
                                  'status': 'assigned',
                                  'assignmentMode': 'manual',
                                  'assignmentRationale':
                                      'Assigned by CHO from available doctor list.',
                                  'assignedByUid':
                                      FirebaseAuth.instance.currentUser?.uid,
                                  'assignedAt': FieldValue.serverTimestamp(),
                                  'updatedAt': FieldValue.serverTimestamp(),
                                };

                                try {
                                  await _firestore.runTransaction((
                                    transaction,
                                  ) async {
                                    final registrySnapshot = await transaction
                                        .get(registryRef);
                                    if (registrySnapshot.exists) {
                                      final registryData = registrySnapshot
                                          .data();
                                      final stillAvailable =
                                          _matchesAvailableStatus(
                                            status: registryData?['status'],
                                            availability:
                                                registryData?['availability'],
                                          );
                                      if (!stillAvailable) {
                                        throw StateError(
                                          'Selected doctor is no longer available. Please choose another doctor.',
                                        );
                                      }
                                    }

                                    transaction.set(
                                      doc.reference,
                                      updatePayload,
                                      SetOptions(merge: true),
                                    );

                                    transaction
                                        .set(registryRef, <String, dynamic>{
                                          'fullName': selectedDoctorName,
                                          'username': selectedDoctorName,
                                          'email': selectedDoctorEmail,
                                          'specialization':
                                              selectedDoctorSpecialization,
                                          'availability': 'Unavailable',
                                          'status': 'unavailable',
                                          'role': 'DOCTOR',
                                          'updatedAt':
                                              FieldValue.serverTimestamp(),
                                          if (!registrySnapshot.exists)
                                            'createdAt':
                                                FieldValue.serverTimestamp(),
                                        }, SetOptions(merge: true));
                                  });

                                  await _syncBarangayReferralMirror(
                                    referralId: doc.id,
                                    payload: {
                                      ...existingData,
                                      ...updatePayload,
                                    },
                                  );
                                  await _loadScope();
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                  Get.snackbar(
                                    'Doctor assigned',
                                    '$selectedDoctorName is now assigned and marked unavailable.',
                                    backgroundColor: Colors.green,
                                    colorText: Colors.white,
                                  );
                                } catch (error) {
                                  if (dialogContext.mounted) {
                                    setDialogState(() => isAssigning = false);
                                  }
                                  Get.snackbar(
                                    'Assignment failed',
                                    'Could not assign doctor: $error',
                                    backgroundColor: Colors.redAccent,
                                    colorText: Colors.white,
                                  );
                                }
                              }();
                            },
                    ),
                    if (isAssigning) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Assigning selected doctor...',
                            style: TextStyle(
                              color: _lightOffWhite.withValues(alpha: 0.84),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isAssigning
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAssignmentDialog([
    QueryDocumentSnapshot<Map<String, dynamic>>? doc,
  ]) async {
    final sourceReferralId = doc?.id;

    final formKey = GlobalKey<FormState>();
    final fullNameController = TextEditingController();
    final emailController = TextEditingController();
    const specializationOptions = <String>[
      'Cardiology',
      'Pediatrics',
      'Obstetrics',
      'Pulmonology',
      'Infectious Disease',
      'General Practice',
      'Family Medicine',
    ];
    const availabilityOptions = <String>[
      'Available',
      'Limited Availability',
      'Unavailable',
    ];

    String selectedSpecialization = specializationOptions.first;
    String selectedAvailability = availabilityOptions.first;
    bool isRegistering = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: _panelSurface,
              title: const Text(
                'Doctor Registry',
                style: TextStyle(color: _lightOffWhite),
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: fullNameController,
                          style: const TextStyle(color: _lightOffWhite),
                          decoration: _inputDecoration('Full Name'),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Full Name is required.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: _lightOffWhite),
                          decoration: _inputDecoration('Email'),
                          validator: (value) {
                            final trimmed = value?.trim() ?? '';
                            if (trimmed.isEmpty) {
                              return 'Email is required.';
                            }
                            final emailPattern = RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            );
                            if (!emailPattern.hasMatch(trimmed)) {
                              return 'Enter a valid email address.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: selectedSpecialization,
                          dropdownColor: _panelAlt,
                          style: const TextStyle(color: _lightOffWhite),
                          decoration: _inputDecoration('Specialization'),
                          items: specializationOptions.map((specialization) {
                            return DropdownMenuItem<String>(
                              value: specialization,
                              child: Text(specialization),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(
                              () => selectedSpecialization = value,
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: selectedAvailability,
                          dropdownColor: _panelAlt,
                          style: const TextStyle(color: _lightOffWhite),
                          decoration: _inputDecoration('Availability'),
                          items: availabilityOptions.map((availability) {
                            return DropdownMenuItem<String>(
                              value: availability,
                              child: Text(availability),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() => selectedAvailability = value);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isRegistering
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }

                          setDialogState(() => isRegistering = true);

                          try {
                            final registeredName = fullNameController.text
                                .trim();
                            final registeredEmail = emailController.text.trim();

                            QueryDocumentSnapshot<Map<String, dynamic>>?
                            linkedUserDoc;
                            for (final userDoc in _doctorDocs) {
                              final userEmail = (userDoc.data()['email'] ?? '')
                                  .toString()
                                  .trim()
                                  .toLowerCase();
                              if (userEmail.isNotEmpty &&
                                  userEmail == registeredEmail.toLowerCase()) {
                                linkedUserDoc = userDoc;
                                break;
                              }
                            }

                            final linkedUserUid = linkedUserDoc?.id ?? '';
                            final registryRef = _firestore
                                .collection('doctor_registry')
                                .doc();

                            await registryRef.set({
                              'fullName': registeredName,
                              'username': registeredName,
                              'email': registeredEmail,
                              'specialization': selectedSpecialization,
                              'availability': selectedAvailability,
                              'status': selectedAvailability.toLowerCase(),
                              'role': 'DOCTOR',
                              'userUid': linkedUserUid,
                              if (sourceReferralId != null &&
                                  sourceReferralId.isNotEmpty)
                                'sourceReferralId': sourceReferralId,
                              'registeredByUid':
                                  FirebaseAuth.instance.currentUser?.uid,
                              'createdAt': FieldValue.serverTimestamp(),
                              'updatedAt': FieldValue.serverTimestamp(),
                            });

                            DocumentSnapshot<Map<String, dynamic>>?
                            targetReferralDoc;
                            if (sourceReferralId != null &&
                                sourceReferralId.isNotEmpty) {
                              final sourceDoc = await _firestore
                                  .collection('referrals')
                                  .doc(sourceReferralId)
                                  .get();
                              if (sourceDoc.exists) {
                                final sourceData =
                                    sourceDoc.data() ?? <String, dynamic>{};
                                final sourceStatus =
                                    (sourceData['status'] ?? 'submitted')
                                        .toString();
                                final sourceAssignedUid =
                                    (sourceData['assignedDoctorUid'] ?? '')
                                        .toString()
                                        .trim();
                                final canAssignSource =
                                    sourceAssignedUid.isEmpty &&
                                    (sourceStatus == 'submitted' ||
                                        sourceStatus == 'under_review');
                                if (canAssignSource) {
                                  targetReferralDoc = sourceDoc;
                                }
                              }
                            }

                            if (targetReferralDoc == null) {
                              final referralsSnapshot = await _firestore
                                  .collection('referrals')
                                  .get();
                              final pendingReferrals = referralsSnapshot.docs
                                  .where((entry) {
                                    final data = entry.data();
                                    final status =
                                        (data['status'] ?? 'submitted')
                                            .toString();
                                    final assignedUid =
                                        (data['assignedDoctorUid'] ?? '')
                                            .toString()
                                            .trim();
                                    return assignedUid.isEmpty &&
                                        (status == 'submitted' ||
                                            status == 'under_review');
                                  })
                                  .toList();

                              pendingReferrals.sort((a, b) {
                                final aMillis = _timestampMillis(
                                  a.data()['createdAt'] ??
                                      a.data()['updatedAt'],
                                );
                                final bMillis = _timestampMillis(
                                  b.data()['createdAt'] ??
                                      b.data()['updatedAt'],
                                );
                                return aMillis.compareTo(bMillis);
                              });

                              if (pendingReferrals.isNotEmpty) {
                                targetReferralDoc = pendingReferrals.first;
                              }
                            }

                            bool didAutoAssign = false;
                            String assignedPatientLabel = '';
                            bool assignmentEmailSent = false;
                            String? assignmentEmailIssue;
                            if (targetReferralDoc != null) {
                              final referralData =
                                  targetReferralDoc.data() ??
                                  <String, dynamic>{};
                              final assignedDoctorUid = linkedUserUid.isNotEmpty
                                  ? linkedUserUid
                                  : 'registry-${registryRef.id}';
                              final assignmentPayload = <String, dynamic>{
                                'assignedDoctorUid': assignedDoctorUid,
                                'assignedDoctorName': registeredName,
                                'assignedDoctorEmail': registeredEmail,
                                'status': 'assigned',
                                'assignmentMode': 'manual',
                                'assignmentRationale':
                                    'Assigned automatically after doctor registration.',
                                'assignedByUid':
                                    FirebaseAuth.instance.currentUser?.uid,
                                'assignedAt': FieldValue.serverTimestamp(),
                                'updatedAt': FieldValue.serverTimestamp(),
                              };

                              await targetReferralDoc.reference.set(
                                assignmentPayload,
                                SetOptions(merge: true),
                              );
                              await _syncBarangayReferralMirror(
                                referralId: targetReferralDoc.id,
                                payload: {
                                  ...referralData,
                                  ...assignmentPayload,
                                },
                              );
                              await registryRef.set({
                                'availability': 'Unavailable',
                                'status': 'unavailable',
                                'activeReferralId': targetReferralDoc.id,
                                'updatedAt': FieldValue.serverTimestamp(),
                              }, SetOptions(merge: true));

                              didAutoAssign = true;
                              assignedPatientLabel =
                                  (referralData['patientName'] ??
                                          referralData['patientRecordId'] ??
                                          targetReferralDoc.id)
                                      .toString();

                              try {
                                final emailResult = await _accountPolicyService
                                    .sendDoctorReferralAssignmentEmail(
                                      referralId: targetReferralDoc.id,
                                      doctorEmail: registeredEmail,
                                      doctorName: registeredName,
                                    );
                                assignmentEmailSent =
                                    emailResult.success && emailResult.sent;
                                if (!assignmentEmailSent) {
                                  assignmentEmailIssue =
                                      emailResult.reason ?? emailResult.message;
                                }
                              } catch (error) {
                                assignmentEmailIssue =
                                    _formatDoctorRegistrationError(error);
                              }
                            }

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                            await _loadScope();
                            if (didAutoAssign) {
                              final emailSuffix = assignmentEmailSent
                                  ? ' Assignment email sent to $registeredEmail.'
                                  : '';
                              Get.snackbar(
                                'Doctor registered & assigned',
                                '$registeredName was automatically assigned to $assignedPatientLabel and is now unavailable.$emailSuffix',
                                backgroundColor: Colors.green,
                                colorText: Colors.white,
                              );
                              if (!assignmentEmailSent &&
                                  assignmentEmailIssue != null &&
                                  assignmentEmailIssue.trim().isNotEmpty) {
                                Get.snackbar(
                                  'Assignment email not sent',
                                  'Doctor assignment was saved, but email notification could not be sent: ${assignmentEmailIssue.trim()}',
                                  backgroundColor: Colors.orange,
                                  colorText: Colors.white,
                                );
                              }
                            } else {
                              Get.snackbar(
                                'Doctor registered',
                                'No pending referral was found for automatic assignment.',
                                backgroundColor: Colors.green,
                                colorText: Colors.white,
                              );
                            }
                          } catch (error) {
                            if (dialogContext.mounted) {
                              setDialogState(() => isRegistering = false);
                            }
                            Get.snackbar(
                              'Registration failed',
                              'Could not register doctor: $error',
                              backgroundColor: Colors.redAccent,
                              colorText: Colors.white,
                            );
                          }
                        },
                  child: Text(isRegistering ? 'Registering...' : 'Register'),
                ),
              ],
            );
          },
        );
      },
    );

    fullNameController.dispose();
    emailController.dispose();
  }

  Future<void> _printReferralForm(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    try {
      final record = <String, dynamic>{...doc.data(), 'id': doc.id};
      final bytes = await buildReferralPdfBytes(record);
      final filename = buildReferralPdfFilename(record);
      final downloaded = downloadReportFile(
        bytes: bytes,
        filename: filename,
        mimeType: 'application/pdf',
      );

      if (!downloaded) {
        Get.snackbar(
          'Download unavailable',
          'Could not trigger file download on this platform.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }

      Get.snackbar(
        'Print form generated',
        'Referral form PDF was generated successfully.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (error) {
      Get.snackbar(
        'Print form failed',
        'Could not generate referral PDF: $error',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
    }
  }

  Widget _buildHeader() {
    final doctors = _safeRegisteredDoctors();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _darkDeepTeal,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _darkDeepTeal.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'CHO Receiving Center',
              style: TextStyle(
                color: _primaryAqua,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Barangay Referral Inbox',
            style: TextStyle(
              color: _lightOffWhite,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Receive referrals sent by BHWs, review each case by barangay, and assign the right doctor for follow-through care.',
            style: TextStyle(
              color: _lightOffWhite.withValues(alpha: 0.78),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildInfoChip(
                'Scope: ${_scope.barangay.isEmpty ? 'All barangays' : _scope.barangay}',
              ),
              _buildInfoChip('Doctors ready: ${doctors.length}'),
            ],
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () => _showAssignmentDialog(),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Register Doctor'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryAqua,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final barangays =
        docs
            .map(
              (doc) =>
                  (doc.data()['barangay'] ?? 'Unassigned barangay').toString(),
            )
            .toSet()
            .toList()
          ..sort();

    return WebFilterSurface(
      children: [
        WebSearchField(
          controller: _searchController,
          width: 320,
          hintText: 'Search patient, barangay, complaint',
          onChanged: (_) => setState(() {}),
          onClear: () {
            _searchController.clear();
            setState(() {});
          },
        ),
        WebFilterDropdown<String>(
          label: 'Status',
          value: _selectedStatus,
          width: 220,
          items:
              const <String>[
                'all',
                'submitted',
                'under_review',
                'assigned',
                'in_treatment',
                'completed',
              ].map((value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(
                    value == 'all'
                        ? 'All statuses'
                        : value.replaceAll('_', ' '),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _selectedStatus = value);
          },
        ),
        WebFilterDropdown<String>(
          label: 'Barangay',
          value: _selectedBarangay,
          width: 220,
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem<String>(
              value: 'all',
              child: Text('All barangays'),
            ),
            ...barangays.map(
              (barangay) => DropdownMenuItem<String>(
                value: barangay,
                child: Text(barangay, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _selectedBarangay = value);
          },
        ),
        OutlinedButton.icon(
          onPressed: () {
            _searchController.clear();
            setState(() {
              _selectedStatus = 'all';
              _selectedBarangay = 'all';
            });
          },
          icon: const Icon(Icons.filter_alt_off_rounded),
          label: const Text('Clear filters'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _primaryAqua,
            side: BorderSide(color: _primaryAqua.withValues(alpha: 0.28)),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    int pendingReview = 0;
    int activeCases = 0;
    for (final doc in docs) {
      final status = (doc.data()['status'] ?? 'submitted').toString();
      if (status == 'assigned' || status == 'in_treatment') {
        activeCases++;
      } else if (status != 'completed') {
        pendingReview++;
      }
    }

    final barangayCount = docs
        .map(
          (doc) => (doc.data()['barangay'] ?? 'Unassigned barangay').toString(),
        )
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .length;

    final cards = <Widget>[
      _buildSummaryCard(
        'Visible referrals',
        '${docs.length}',
        Icons.folder_shared_outlined,
      ),
      _buildSummaryCard(
        'Awaiting review',
        '$pendingReview',
        Icons.mark_email_unread_outlined,
      ),
      _buildSummaryCard(
        'Assigned / Active',
        '$activeCases',
        Icons.assignment_ind_outlined,
      ),
      _buildSummaryCard(
        'Barangays sending',
        '$barangayCount',
        Icons.location_city_outlined,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1280
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

  Widget _buildDoctorListSection() {
    final doctors = _safeRegisteredDoctors();
    final archivedDoctors = _safeArchivedDoctors();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
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
                'Doctors List',
                style: TextStyle(
                  color: _lightOffWhite,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              _buildInfoChip('${doctors.length} available'),
            ],
          ),
          const SizedBox(height: 14),
          if (doctors.isEmpty)
            Text(
              'No doctors available yet. Use Register Doctor to add one.',
              style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.74)),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth;
                final cardWidth = maxWidth >= 1200
                    ? (maxWidth - 24) / 3
                    : maxWidth >= 760
                    ? (maxWidth - 12) / 2
                    : maxWidth;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: doctors
                      .map(
                        (doctor) => SizedBox(
                          width: cardWidth,
                          child: _buildDoctorListCard(doctor),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Archived Doctors',
                style: TextStyle(
                  color: _lightOffWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _buildInfoChip('${archivedDoctors.length} archived'),
            ],
          ),
          const SizedBox(height: 12),
          if (archivedDoctors.isEmpty)
            Text(
              'No archived doctors.',
              style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.68)),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth;
                final cardWidth = maxWidth >= 1200
                    ? (maxWidth - 24) / 3
                    : maxWidth >= 760
                    ? (maxWidth - 12) / 2
                    : maxWidth;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: archivedDoctors
                      .map(
                        (doctor) => SizedBox(
                          width: cardWidth,
                          child: _buildDoctorListCard(
                            doctor,
                            showActions: false,
                            archived: true,
                          ),
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

  Widget _buildDoctorListCard(
    Map<String, dynamic> doctor, {
    bool showActions = true,
    bool archived = false,
  }) {
    final fullName = (doctor['fullName'] ?? 'Doctor').toString();
    final email = (doctor['email'] ?? '').toString();
    final specialization = (doctor['specialization'] ?? 'General Medicine')
        .toString();
    final availability = _doctorAvailability(doctor);
    final availabilityLabel = _doctorAvailabilityLabel(availability);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _darkDeepTeal.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: archived
              ? Colors.orangeAccent.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fullName,
            style: const TextStyle(
              color: _lightOffWhite,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            email.isEmpty ? 'No email provided' : email,
            style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.78)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildInfoChip('Specialization: $specialization'),
              _buildInfoChip('Availability: $availabilityLabel'),
            ],
          ),
          if (archived) ...[
            const SizedBox(height: 10),
            _buildInfoChip('Archived record'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _restoreDoctorFromDirectory(doctor),
              icon: const Icon(Icons.restore_rounded, size: 16),
              label: const Text('Restore'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.greenAccent,
                side: BorderSide(
                  color: Colors.greenAccent.withValues(alpha: 0.52),
                ),
              ),
            ),
          ],
          if (showActions && !archived) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showEditDoctorDialog(doctor),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryAqua,
                    side: BorderSide(
                      color: _primaryAqua.withValues(alpha: 0.52),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _archiveDoctorFromDirectory(doctor),
                  icon: const Icon(Icons.archive_outlined, size: 16),
                  label: const Text('Archive'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orangeAccent,
                    side: BorderSide(
                      color: Colors.orangeAccent.withValues(alpha: 0.52),
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

  Widget _buildBarangaySection(
    String barangay,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final awaitingReview = docs.where((doc) {
      final status = (doc.data()['status'] ?? 'submitted').toString();
      return status == 'submitted' || status == 'under_review';
    }).length;
    final activeCases = docs.where((doc) {
      final status = (doc.data()['status'] ?? 'submitted').toString();
      return status == 'assigned' || status == 'in_treatment';
    }).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(20),
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
                barangay,
                style: const TextStyle(
                  color: _lightOffWhite,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              _buildInfoChip('${docs.length} referrals'),
              _buildInfoChip('$awaitingReview awaiting review'),
              _buildInfoChip('$activeCases active'),
            ],
          ),
          const SizedBox(height: 16),
          ...docs.map(_buildReferralCard),
        ],
      ),
    );
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
    final data = doc.data();
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
        color: _darkDeepTeal.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
              _buildInfoChip(
                (data['barangay'] ?? 'Unassigned barangay').toString(),
              ),
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
              _buildMetaBlock('Referred to', referredTo),
              _buildMetaBlock('Date & Time', referralDateTime),
              _buildMetaBlock(
                'Age / Sex',
                '${(data['patientAge'] ?? 'N/A').toString()} / ${(data['patientSex'] ?? 'N/A').toString()}',
              ),
              _buildMetaBlock(
                'Submitted by',
                (data['createdByName'] ??
                        data['createdByEmail'] ??
                        'Unknown sender')
                    .toString(),
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
            style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.74)),
          ),
          const SizedBox(height: 12),
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
          if (_hasDoctorUpdate(data)) ...[
            const SizedBox(height: 12),
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
          ],
          if ((data['choReviewNotes'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'CHO notes: ${(data['choReviewNotes'] ?? '').toString()}',
              style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.76)),
            ),
          ],
          if (assignmentRationale.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${_assignmentModeLabel(assignmentMode, assignmentSource)}: $assignmentRationale',
              style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.72)),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Received ${_formatTimestamp(data['createdAt'])}',
            style: const TextStyle(color: _mutedCoolGray),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showReviewAssignDialog(doc),
                icon: const Icon(Icons.assignment_ind_outlined),
                label: const Text('Review/Assign'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryAqua,
                  side: BorderSide(color: _primaryAqua.withValues(alpha: 0.32)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _printReferralForm(doc),
                icon: const Icon(Icons.print_rounded),
                label: const Text('Print Form'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _lightOffWhite,
                  side: BorderSide(
                    color: _lightOffWhite.withValues(alpha: 0.28),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaBlock(String label, String value) {
    return SizedBox(
      width: 250,
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

  Widget _buildReferralsContent(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> rawDocs,
  ) {
    final docs = _sortedDocs(rawDocs);
    final filteredDocs = _filteredDocs(docs);
    final groupedDocs = _groupByBarangay(filteredDocs);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          _buildFilterPanel(docs),
          const SizedBox(height: 20),
          _buildSummaryCards(filteredDocs),
          const SizedBox(height: 20),
          _buildDoctorListSection(),
          const SizedBox(height: 20),
          if (filteredDocs.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _panelSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _primaryAqua.withValues(alpha: 0.16)),
              ),
              child: Text(
                'No referrals match the current barangay, status, or search filters.',
                style: TextStyle(color: _lightOffWhite.withValues(alpha: 0.74)),
              ),
            )
          else
            ...groupedDocs.entries.map(
              (entry) => _buildBarangaySection(entry.key, entry.value),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkDeepTeal,
      drawer: const ChoNavigationDrawer(current: ChoDestination.referrals),
      appBar: AppBar(
        backgroundColor: _darkDeepTeal,
        title: const Text('CHO Referral Receiving'),
        actions: [
          IconButton(
            onPressed: () {
              _loadScope();
              setState(() {
                _referralsRecoveryAttempts = 0;
                _referralsStream = _createReferralsStream();
              });
            },
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh referrals',
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
              stream: _ensureReferralsStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  final isTargetConflict = _isReferralsTargetConflict(
                    snapshot.error,
                  );

                  if (isTargetConflict && _referralsRecoveryAttempts < 2) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _recoverReferralsStream();
                    });
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              color: _primaryAqua,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Recovering referral stream... (${_referralsRecoveryAttempts + 1}/2)',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: _lightOffWhite),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (isTargetConflict) {
                    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      future: _firestore.collection('referrals').get(),
                      builder: (context, fallbackSnapshot) {
                        if (fallbackSnapshot.hasData) {
                          return _buildReferralsContent(
                            fallbackSnapshot.data!.docs,
                          );
                        }

                        if (fallbackSnapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Could not load referrals: ${fallbackSnapshot.error}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: _lightOffWhite,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        _referralsRecoveryAttempts = 0;
                                        _referralsStream =
                                            _createReferralsStream();
                                      });
                                    },
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return const Center(
                          child: CircularProgressIndicator(color: _primaryAqua),
                        );
                      },
                    );
                  }

                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Could not load referrals: ${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: _lightOffWhite),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _referralsRecoveryAttempts = 0;
                                _referralsStream = _createReferralsStream();
                              });
                            },
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

                return _buildReferralsContent(snapshot.data!.docs);
              },
            ),
    );
  }
}
