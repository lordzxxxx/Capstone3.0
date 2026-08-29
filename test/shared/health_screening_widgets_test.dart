import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/core/services/health_screening_engine.dart';
import 'package:mycapstone_project/shared/widgets/health_screening_insights_card.dart';
import 'package:mycapstone_project/shared/widgets/health_screening_panel.dart';

void main() {
  final flaggedRecord = HealthScreeningEngine.attachToRecord(
    {'id': 'checkup-1'},
    HealthScreeningEngine.evaluate({
      'age': 45,
      'bloodPressure': '195/125',
      'symptoms': 'chest pain',
    }),
  );

  for (final width in <double>[320, 375, 430, 768]) {
    testWidgets('screening panel has no overflow at $width px', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: HealthScreeningPanel(record: flaggedRecord),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('AI-assisted screening'), findsOneWidget);
      expect(find.text('URGENT ASSESSMENT'), findsWidgets);
      await tester.binding.setSurfaceSize(null);
    });
  }

  testWidgets('insight card exposes scoped aggregate metrics', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HealthScreeningInsightsCard(
              records: [flaggedRecord],
              scopeLabel: 'Assigned barangay',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Screenings'), findsOneWidget);
    expect(find.text('Referral suggestions'), findsOneWidget);
    expect(find.text('Assigned barangay'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
