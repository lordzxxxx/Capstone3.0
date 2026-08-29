import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/features/auth/landing_sections.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

Widget _buildSubject() {
  return MaterialApp(
    theme: AppTheme.light(isWeb: true),
    home: SingleChildScrollView(
      child: LandingSections(
        aboutKey: GlobalKey(),
        featuresKey: GlobalKey(),
        howItWorksKey: GlobalKey(),
        securityKey: GlobalKey(),
        contactKey: GlobalKey(),
        onAccessSystem: _noop,
        onOpenPrivacy: _noop,
        onOpenTerms: _noop,
      ),
    ),
  );
}

void _noop() {}

void main() {
  testWidgets('exposes the verified public sections and FAQ answers', (
    tester,
  ) async {
    await tester.pumpWidget(_buildSubject());

    expect(
      find.text('One connected workspace for community health teams'),
      findsOneWidget,
    );
    expect(
      find.text('From barangay information to coordinated review'),
      findsOneWidget,
    );
    expect(
      find.text('Tools that support the complete health-information workflow'),
      findsOneWidget,
    );
    expect(find.text('Security & data privacy'), findsOneWidget);
    expect(find.text('aidsuhis@gmail.com'), findsOneWidget);
    expect(find.text('Role-scoped workspace'), findsNothing);
    expect(find.text('No live records shown'), findsNothing);
    expect(find.text('Does AI-DSUHIS diagnose patients?'), findsOneWidget);
    expect(
      find.text(
        'No. AI-assisted output supports review by qualified health professionals. It is not a diagnosis, treatment, medication, or prescription tool.',
      ),
      findsNothing,
    );

    await tester.ensureVisible(find.text('Does AI-DSUHIS diagnose patients?'));
    await tester.tap(find.text('Does AI-DSUHIS diagnose patients?'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No. AI-assisted output supports review by qualified health professionals. It is not a diagnosis, treatment, medication, or prescription tool.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sections remain overflow-free at representative widths', (
    tester,
  ) async {
    for (final size in [
      const Size(320, 1200),
      const Size(375, 1200),
      const Size(430, 1200),
      const Size(768, 1200),
      const Size(1024, 1200),
      const Size(1440, 1200),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(_buildSubject());
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'width ${size.width}');
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
