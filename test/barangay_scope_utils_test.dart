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

  test('marked BHW analytics demo can fill historical trend graphs', () {
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

    expect(
      recordMatchesAccessScope(
        record,
        boundedScope,
        allowHistoricalBhwAnalyticsDemo: true,
      ),
      isTrue,
    );
  });

  test('demo bypass never crosses the BHW barangay boundary', () {
    final record = <String, dynamic>{
      'barangay': 'Bangcud',
      'barangayCode': 'BANGCUD',
      'createdAt': DateTime.utc(2026, 3, 10),
      'isDemoData': true,
      'demoDataset': 'bhw-analytics-demo-v1',
    };

    expect(
      recordMatchesAccessScope(
        record,
        scope,
        allowHistoricalBhwAnalyticsDemo: true,
      ),
      isFalse,
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
