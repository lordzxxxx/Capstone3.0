import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/roles/bhw/dashboard/bhw_quick_actions.dart';

void main() {
  group('BHW Quick Actions preferences', () {
    test('sanitizes unknown, duplicate, and excess action IDs', () {
      final sanitized = BhwQuickActionsService.sanitizeIds([
        'add_patient',
        'unknown',
        'add_patient',
        'add_checkup',
        'prenatal',
        'immunization',
        'referrals',
        'analytics',
        'mortality',
      ]);

      expect(sanitized, [
        'add_patient',
        'add_checkup',
        'prenatal',
        'immunization',
        'referrals',
        'analytics',
      ]);
      expect(sanitized, hasLength(bhwQuickActionLimit));
    });

    test('catalog contains every supported BHW function exactly once', () {
      final ids = bhwQuickActionCatalog.map((action) => action.id).toList();
      expect(ids.toSet(), hasLength(11));
      expect(ids, containsAll(defaultBhwQuickActionIds));
      expect(ids, contains('communicable_diseases'));
      expect(ids, contains('non_communicable_diseases'));
      expect(ids, contains('morbidity'));
      expect(ids, contains('mortality'));
      expect(ids, contains('referrals'));
    });
  });

  testWidgets('renders six desktop slots as two rows of three', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            child: BhwQuickActionsSection(
              actionIds: defaultBhwQuickActionIds,
              onAction: (_) {},
              onEdit: () {},
              isLoading: false,
            ),
          ),
        ),
      ),
    );

    final centers = List<Offset>.generate(
      bhwQuickActionLimit,
      (index) => tester.getCenter(
        find.byKey(ValueKey('bhw-quick-action-slot-${index + 1}')),
      ),
    );
    final firstRowY = centers.first.dy;
    final secondRowY = centers[3].dy;

    expect(centers.take(3).every((center) => center.dy == firstRowY), isTrue);
    expect(centers.skip(3).every((center) => center.dy == secondRowY), isTrue);
    expect(centers[0].dx, lessThan(centers[1].dx));
    expect(centers[1].dx, lessThan(centers[2].dx));
    expect(secondRowY, greaterThan(firstRowY));
  });

  testWidgets('mobile layout stays within the viewport and keeps all slots', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BhwQuickActionsSection(
              actionIds: defaultBhwQuickActionIds,
              onAction: (_) {},
              onEdit: () {},
              isLoading: false,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    for (var position = 1; position <= bhwQuickActionLimit; position++) {
      final rect = tester.getRect(
        find.byKey(ValueKey('bhw-quick-action-slot-$position')),
      );
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
    }
  });
}
