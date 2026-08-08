import 'package:cloud_firestore/cloud_firestore.dart';

/// A single, immutable clinical note authored by a doctor (or CHO) about one
/// patient's specific check-up/consultation.
///
/// Notes are append-only: once written they are never edited or deleted
/// (enforced by firestore.rules), so any authorized clinician who later
/// treats the same patient sees the full, untampered history left by
/// previous doctors — this is the continuity-of-care mechanism.
class DoctorNote {
  const DoctorNote({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.checkupId,
    required this.barangayCode,
    required this.authorUid,
    required this.authorName,
    required this.authorRole,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String patientId;
  final String patientName;
  final String checkupId;

  /// The patient's barangay at the time the note was written, not the
  /// author's. Firestore rules scope a BHW's read access to notes for
  /// patients in their own barangay, so this must reflect the patient
  /// regardless of which role authored the note.
  final String barangayCode;

  final String authorUid;
  final String authorName;
  final String authorRole;
  final String note;
  final DateTime? createdAt;

  factory DoctorNote.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAtValue = data['createdAt'];
    return DoctorNote(
      id: doc.id,
      patientId: (data['patientId'] ?? '').toString(),
      patientName: (data['patientName'] ?? '').toString(),
      checkupId: (data['checkupId'] ?? '').toString(),
      barangayCode: (data['barangayCode'] ?? '').toString(),
      authorUid: (data['authorUid'] ?? '').toString(),
      authorName: (data['authorName'] ?? 'Unknown').toString(),
      authorRole: (data['authorRole'] ?? '').toString(),
      note: (data['note'] ?? '').toString(),
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'patientId': patientId,
      'patientName': patientName,
      'checkupId': checkupId,
      'barangayCode': barangayCode,
      'authorUid': authorUid,
      'authorName': authorName,
      'authorRole': authorRole,
      'note': note,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
