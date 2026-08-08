import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/web/shared/models/doctor_note.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';

/// Reads and writes the append-only `doctor_notes` collection.
///
/// See firestore.rules for the authorization model this mirrors: CHO and
/// any DOCTOR account may read every note (continuity of care requires a
/// later doctor to see an earlier doctor's notes, regardless of which
/// referral or barangay originated them); BHW accounts may read notes for
/// patients in their own barangay. Notes may only be created — never
/// edited or deleted — by a signed-in CHO or DOCTOR account, as themselves.
class DoctorNotesService {
  DoctorNotesService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? getFirestoreInstance();

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('doctor_notes');

  /// Live stream of notes for one check-up, oldest first — a readable
  /// chronological log of what each attending clinician observed.
  Stream<List<DoctorNote>> watchNotesForCheckup(String checkupId) {
    if (checkupId.isEmpty) {
      return Stream.value(const <DoctorNote>[]);
    }
    return _collection
        .where('checkupId', isEqualTo: checkupId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(DoctorNote.fromFirestore).toList(),
        );
  }

  /// One-off fetch of every note for a patient across all of their
  /// check-ups, newest first. Used to fold notes into the patient's overall
  /// health history timeline.
  Future<List<DoctorNote>> fetchNotesForPatient(String patientId) async {
    if (patientId.isEmpty) {
      return const <DoctorNote>[];
    }
    final snapshot = await _collection
        .where('patientId', isEqualTo: patientId)
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs.map(DoctorNote.fromFirestore).toList();
  }

  /// Adds a new note. The author is always the currently signed-in user —
  /// callers cannot attribute a note to anyone else. [patientBarangayCode]
  /// must come from the patient record (not the author), so BHWs serving
  /// that barangay retain read access regardless of who authored the note.
  Future<void> addNote({
    required String patientId,
    required String patientName,
    required String checkupId,
    required String patientBarangayCode,
    required String note,
  }) async {
    final trimmedNote = note.trim();
    if (trimmedNote.isEmpty) {
      throw ArgumentError('Note text cannot be empty.');
    }
    if (checkupId.isEmpty) {
      throw ArgumentError('A note must be linked to a check-up.');
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to add a doctor note.');
    }

    final scope = await UserAccessScopeService.instance.loadCurrentScope();
    final authorName = await _resolveAuthorName(user);

    await _collection.add(
      DoctorNote(
        id: '',
        patientId: patientId,
        patientName: patientName,
        checkupId: checkupId,
        barangayCode: patientBarangayCode,
        authorUid: user.uid,
        authorName: authorName,
        authorRole: scope.role,
        note: trimmedNote,
        createdAt: null,
      ).toFirestore(),
    );
  }

  Future<String> _resolveAuthorName(User user) async {
    final displayName = (user.displayName ?? '').trim();
    if (displayName.isNotEmpty) {
      return displayName;
    }

    try {
      final profile = await _firestore.collection('users').doc(user.uid).get();
      final data = profile.data();
      for (final candidate in [
        data?['username'],
        data?['fullName'],
        data?['displayName'],
      ]) {
        final text = (candidate ?? '').toString().trim();
        if (text.isNotEmpty) {
          return text;
        }
      }
    } catch (_) {
      // Fall through to the email/uid fallback below.
    }

    final email = (user.email ?? '').trim();
    return email.isNotEmpty ? email : 'Unknown';
  }
}
