import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/shared/navigation/web_navigation_coordinator.dart';

void main() {
  testWidgets('ignores competing navigation requests while one is running', (
    tester,
  ) async {
    final gate = Completer<void>();
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) =>
              ElevatedButton(onPressed: () {}, child: const Text('Navigate')),
        ),
      ),
    );

    final context = tester.element(find.text('Navigate'));
    final first = WebNavigationCoordinator.run(context, () async {
      calls += 1;
      await gate.future;
    });

    final second = WebNavigationCoordinator.run(
      context,
      () async => calls += 1,
    );
    expect(WebNavigationCoordinator.isNavigating, isTrue);
    expect(calls, 0);
    gate.complete();
    await Future.wait<void>([first, second]);
    expect(calls, 1);
    expect(WebNavigationCoordinator.isNavigating, isFalse);
  });
}
