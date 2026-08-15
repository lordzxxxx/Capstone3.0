import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/shell/web_startup.dart';

void main() {
  testWidgets('renders the loading shell before MaterialApp exists', (
    tester,
  ) async {
    final initialization = Completer<void>();

    await tester.pumpWidget(
      WebStartupGate(
        initialize: () => initialization.future,
        child: const SizedBox.shrink(),
      ),
    );

    expect(find.text('Preparing your AI-DSUHIS workspace…'), findsOneWidget);
    expect(
      Directionality.of(
        tester.element(find.text('Preparing your AI-DSUHIS workspace…')),
      ),
      TextDirection.ltr,
    );
  });

  testWidgets('renders a recoverable startup error without red-screen errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      WebStartupGate(
        initialize: () async => throw StateError('test startup failure'),
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pump();

    expect(find.text('Workspace could not be prepared'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(
      Directionality.of(
        tester.element(find.text('Workspace could not be prepared')),
      ),
      TextDirection.ltr,
    );
  });

  testWidgets('does not build the application before web services finish', (
    tester,
  ) async {
    final initialization = Completer<void>();
    var childBuilt = false;

    await tester.pumpWidget(
      MaterialApp(
        home: WebStartupGate(
          initialize: () => initialization.future,
          child: Builder(
            builder: (context) {
              childBuilt = true;
              return const Text('Application ready');
            },
          ),
        ),
      ),
    );

    expect(childBuilt, isFalse);
    expect(find.text('Preparing your AI-DSUHIS workspace…'), findsOneWidget);
    expect(find.text('Application ready'), findsNothing);

    initialization.complete();
    await tester.pump();

    expect(childBuilt, isTrue);
    expect(find.text('Application ready'), findsOneWidget);
  });
}
