import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/shared/components/web_responsive_body.dart';

void main() {
  Widget buildSubject() {
    return MaterialApp(
      home: Scaffold(
        body: WebResponsiveBody(
          title: 'Check-up Management',
          sidebar: const SizedBox(
            width: 220,
            child: ColoredBox(
              color: Colors.indigo,
              child: Center(child: Text('Navigation menu')),
            ),
          ),
          child: const SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Full-width page content'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('uses full-width mobile header and drawer navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildSubject());

    expect(find.text('Check-up Management'), findsOneWidget);
    expect(find.text('Full-width page content'), findsOneWidget);
    expect(find.byTooltip('Open navigation menu'), findsOneWidget);
    expect(find.text('Navigation menu'), findsNothing);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(find.text('Navigation menu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps persistent navigation on desktop widths', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildSubject());

    expect(find.text('Navigation menu'), findsOneWidget);
    expect(find.byTooltip('Open navigation menu'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
