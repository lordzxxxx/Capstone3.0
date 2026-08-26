import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/shared/components/web_navigation_item.dart';

void main() {
  testWidgets('navigation item is keyboard/focus capable and reports state', (
    tester,
  ) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WebNavigationItem(
            icon: Icons.dashboard_outlined,
            label: 'Dashboard',
            isCollapsed: false,
            isActive: true,
            onTap: () => taps++,
          ),
        ),
      ),
    );

    expect(find.text('Dashboard'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Dashboard')),
      matchesSemantics(
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
        label: 'Dashboard navigation item\nDashboard',
      ),
    );

    await tester.tap(find.text('Dashboard'));
    await tester.pump();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed navigation item keeps a usable target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WebNavigationItem(
            icon: Icons.people_alt_outlined,
            label: 'Patient Records',
            isCollapsed: true,
            onTap: _noop,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.people_alt_outlined), findsOneWidget);
    final targetSize = tester.getSize(find.byType(InkWell));
    expect(targetSize.width, greaterThanOrEqualTo(44));
    expect(targetSize.height, greaterThanOrEqualTo(44));
  });

  testWidgets('expanded navigation item uses compact desktop density', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WebNavigationItem(
            icon: Icons.dashboard_outlined,
            label: 'Dashboard',
            isCollapsed: false,
            onTap: _noop,
          ),
        ),
      ),
    );

    expect(find.text('Dashboard'), findsOneWidget);
    final targetSize = tester.getSize(find.byType(InkWell));
    expect(targetSize.height, lessThanOrEqualTo(42));
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
