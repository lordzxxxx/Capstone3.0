import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mycapstone_project/web/shared/services/web_record_sync.dart';
import 'package:mycapstone_project/web/shared/widgets/web_sync_status_badge.dart';

void main() {
  test('sync status distinguishes every user-visible lifecycle state', () {
    expect(
      WebRecordSyncStatus.fromRecord(const {'_isFromCache': true}).state,
      WebRecordSyncState.savedLocally,
    );
    expect(
      WebRecordSyncStatus.fromRecord(const {'_hasPendingWrites': true}).state,
      WebRecordSyncState.pending,
    );
    expect(
      WebRecordSyncStatus.fromRecord(const {'_syncStatus': 'syncing'}).state,
      WebRecordSyncState.syncing,
    );
    expect(
      WebRecordSyncStatus.fromRecord(const {}).state,
      WebRecordSyncState.synchronized,
    );
    expect(
      WebRecordSyncStatus.fromRecord(const {'_syncError': 'unavailable'}).state,
      WebRecordSyncState.failed,
    );
    expect(
      WebRecordSyncStatus.fromRecord(const {'_hasConflict': true}).state,
      WebRecordSyncState.conflict,
    );
  });

  test('create metadata is stable and strips browser-only fields', () {
    final prepared = WebRecordWriteCoordinator.prepareCreate(const {
      'patient': 'Example',
      '_syncStatus': 'pending',
      'syncError': 'temporary',
    }, documentId: 'CHK-001');
    expect(prepared['id'], 'CHK-001');
    expect(prepared['clientOperationId'], 'CHK-001');
    expect(prepared['recordVersion'], 1);
    expect(prepared, isNot(contains('_syncStatus')));
    expect(prepared, isNot(contains('syncError')));
  });

  test('pending write registry retains only status and safe error text', () {
    WebPendingWriteRegistry.clearForTest();
    WebPendingWriteRegistry.mark(
      'CHK-002',
      WebRecordSyncState.failed,
      error: FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      ),
    );
    expect(
      WebPendingWriteRegistry.stateFor('CHK-002'),
      WebRecordSyncState.failed,
    );
    expect(
      WebPendingWriteRegistry.errorFor('CHK-002'),
      contains('not allowed'),
    );
  });

  testWidgets('conflict state is visible without relying on color', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WebSyncStatusBadge(record: {'_hasConflict': true}),
        ),
      ),
    );
    expect(find.text('Conflict—review required'), findsOneWidget);
    expect(find.byIcon(Icons.compare_arrows_rounded), findsOneWidget);
  });
}
