import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/shell/mobile_startup.dart';

void main() {
  testWidgets('shows the attached loader only while startup is still pending', (
    tester,
  ) async {
    final initialization = Completer<void>();
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MobileStartupGate(
          initialize: () => initialization.future,
          child: const Text('Application ready'),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('mobile-startup-reveal')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const ValueKey('mobile-startup-json-loader')),
      findsOneWidget,
    );
    expect(find.text('Application ready'), findsNothing);

    initialization.complete();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Application ready'), findsOneWidget);
  });

  testWidgets('moves directly into the application when startup is ready', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MobileStartupGate(
          initialize: () async {},
          child: const Text('Application ready'),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Application ready'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-startup-json-loader')),
      findsNothing,
    );
  });
}
