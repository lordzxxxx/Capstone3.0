import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/core/services/mobile_sync_utils.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';

void main() {
  test(
    'mobile sync queue serializes every concurrent call and remains reusable',
    () async {
      final queue = MobileSyncQueue();
      final events = <String>[];

      final first = queue.run(() async {
        events.add('first-start');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        events.add('first-end');
      });
      final second = queue.run(() async {
        events.add('second-start');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        events.add('second-end');
      });
      final third = queue.run(() async {
        events.add('third-start');
        events.add('third-end');
      });

      await Future.wait([first, second, third]);
      expect(events, [
        'first-start',
        'first-end',
        'second-start',
        'second-end',
        'third-start',
        'third-end',
      ]);

      await queue
          .run(() async {
            throw StateError('expected test failure');
          })
          .catchError((_) {});
      await queue.run(() async => events.add('after-failure'));
      expect(events.last, 'after-failure');
    },
  );

  test('a failed module does not prevent later modules from synchronizing',
      () async {
    final attempted = <String>[];

    final results = await runMobileSyncOperations({
      'check-ups': () async {
        attempted.add('check-ups');
        throw StateError('migration failed');
      },
      'patients': () async => attempted.add('patients'),
    });

    expect(attempted, ['check-ups', 'patients']);
    expect(results.map((result) => result.succeeded), [false, true]);
    expect(results.first.error, isA<StateError>());
  });

  test('mobile BHW writes use the authenticated barangay scope', () {
    const scope = UserAccessScope(
      userId: 'bhw-1',
      role: 'bhw',
      barangay: 'Aglayan',
      barangayCode: 'AGLAYAN',
      barangayDistrict: 'South Highway District',
      dataVisibleFrom: null,
    );

    final scoped = applyMobileFirestoreScope(
      {'id': 'PAT-1', 'barangay': 'Bangcud', 'barangayCode': 'BANGCUD'},
      accessScope: scope,
      currentUserId: 'bhw-1',
    );

    expect(scoped['barangay'], 'Aglayan');
    expect(scoped['barangayCode'], 'AGLAYAN');
    expect(scoped['barangayDistrict'], 'South Highway District');
    expect(scoped['createdBy'], 'bhw-1');
  });

  test('mobile CHO writes preserve an explicitly scoped record', () {
    const scope = UserAccessScope(
      userId: 'cho-1',
      role: 'cho',
      barangay: '',
      barangayCode: '',
      barangayDistrict: '',
      dataVisibleFrom: null,
    );

    final scoped = applyMobileFirestoreScope(
      {'barangay': 'Bangcud', 'barangayCode': 'BANGCUD'},
      accessScope: scope,
      currentUserId: 'cho-1',
    );

    expect(scoped['barangay'], 'Bangcud');
    expect(scoped['barangayCode'], 'BANGCUD');
    expect(scoped['createdBy'], 'cho-1');
  });

  test('mobile sync refuses an unauthenticated scope', () {
    expect(
      () => applyMobileFirestoreScope(const {
        'id': 'PAT-1',
      }, accessScope: UserAccessScope.unauthenticated),
      throwsStateError,
    );
  });
}
