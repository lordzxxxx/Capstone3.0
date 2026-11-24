import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';

void main() {
  const scope = UserAccessScope(
    userId: 'bhw-user',
    role: 'bhw',
    barangay: 'Aglayan',
    barangayCode: 'AGLAYAN',
    barangayDistrict: 'South Highway District',
    dataVisibleFrom: null,
  );

  test('ordinary historical record respects the initialization boundary', () {
    final boundedScope = UserAccessScope(
      userId: scope.userId,
      role: scope.role,
      barangay: scope.barangay,
      barangayCode: scope.barangayCode,
      barangayDistrict: scope.barangayDistrict,
      dataVisibleFrom: DateTime.utc(2026, 7, 16),
    );
    final record = <String, dynamic>{
      'barangay': 'Aglayan',
      'barangayCode': 'AGLAYAN',
      'createdAt': DateTime.utc(2026, 3, 10),
    };

    expect(recordMatchesAccessScope(record, boundedScope), isFalse);
  });

  test('synthetic records are always excluded from production views', () {
    final boundedScope = UserAccessScope(
      userId: scope.userId,
      role: scope.role,
      barangay: scope.barangay,
      barangayCode: scope.barangayCode,
      barangayDistrict: scope.barangayDistrict,
      dataVisibleFrom: DateTime.utc(2026, 7, 16),
    );
    final record = <String, dynamic>{
      'barangay': 'Aglayan',
      'barangayCode': 'AGLAYAN',
      'createdAt': DateTime.utc(2026, 3, 10),
      'isDemoData': true,
      'demoDataset': 'bhw-analytics-demo-v1',
    };

    expect(recordMatchesAccessScope(record, boundedScope), isFalse);
  });

  test('same-BHW imported record without a date remains visible', () {
    final boundedScope = UserAccessScope(
      userId: scope.userId,
      role: scope.role,
      barangay: scope.barangay,
      barangayCode: scope.barangayCode,
      barangayDistrict: scope.barangayDistrict,
      dataVisibleFrom: DateTime.utc(2026, 7, 16),
    );
    final record = <String, dynamic>{
      'barangay': 'Aglayan',
      'barangayCode': 'AGLAYAN',
      'createdByUid': scope.userId,
      'workspaceMirrorOf': 'patient_records/patient-1',
    };

    expect(recordMatchesAccessScope(record, boundedScope), isTrue);
  });

  test('undated record owned by another user remains bounded', () {
    final boundedScope = UserAccessScope(
      userId: scope.userId,
      role: scope.role,
      barangay: scope.barangay,
      barangayCode: scope.barangayCode,
      barangayDistrict: scope.barangayDistrict,
      dataVisibleFrom: DateTime.utc(2026, 7, 16),
    );
    final record = <String, dynamic>{
      'barangay': 'Aglayan',
      'barangayCode': 'AGLAYAN',
      'createdByUid': 'another-bhw',
    };

    expect(recordMatchesAccessScope(record, boundedScope), isFalse);
  });

  test('root and workspace mirrors are deduplicated by document ID', () {
    final unique = deduplicateFirestoreRecords([
      {
        'id': 'checkup-1',
        '_firestorePath': 'checkup_records/checkup-1',
        'patientId': 'patient-1',
      },
      {
        'id': 'checkup-1',
        '_firestorePath': 'barangays/AGLAYAN/checkup_records/checkup-1',
        'patientId': 'patient-1',
      },
      {
        'id': 'checkup-2',
        '_firestorePath': 'barangays/AGLAYAN/checkup_records/checkup-2',
        'patientId': 'patient-1',
      },
    ]);

    expect(unique, hasLength(2));
    expect(
      unique.firstWhere(
        (record) => record['id'] == 'checkup-1',
      )['_firestorePath'],
      startsWith('barangays/'),
    );
  });

  test('Firestore values are safe for the mobile SQLite cache', () {
    final normalized = sanitizeRecordForSqlite({
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 12)),
      'enabled': true,
      'tags': ['ocr', 'mobile'],
      'metadata': {'source': 'firebase'},
    });

    expect(normalized['createdAt'], '2026-08-01T12:00:00.000Z');
    expect(normalized['enabled'], 1);
    expect(normalized['tags'], '["ocr","mobile"]');
    expect(normalized['metadata'], '{"source":"firebase"}');
  });
}
