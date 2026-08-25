import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/shared/components/role_decision_support_panel.dart';

void main() {
  Widget host(DecisionSupportAudience audience) => MaterialApp(
    home: Scaffold(
      body: RoleDecisionSupportPanel(
        audience: audience,
        summary: 'Role-specific summary',
        items: const <DecisionSupportItem>[
          DecisionSupportItem(
            label: 'Priority',
            value: '2 records',
            icon: Icons.flag_outlined,
          ),
        ],
      ),
    ),
  );

  testWidgets('BHW receives patient-level language only', (tester) async {
    await tester.pumpWidget(host(DecisionSupportAudience.bhw));

    expect(find.text('Patient decision support'), findsOneWidget);
    expect(find.text('CHO planning decision support'), findsNothing);
    expect(find.textContaining('follow-up or referral'), findsOneWidget);
    expect(find.textContaining('not a confirmed diagnosis'), findsOneWidget);
  });

  testWidgets('CHO receives aggregated planning language only', (tester) async {
    await tester.pumpWidget(host(DecisionSupportAudience.cho));

    expect(find.text('CHO planning decision support'), findsOneWidget);
    expect(find.text('Patient decision support'), findsNothing);
    expect(find.textContaining('prioritize barangays'), findsOneWidget);
  });

  testWidgets('doctor receives clinical review context', (tester) async {
    await tester.pumpWidget(host(DecisionSupportAudience.doctor));

    expect(find.text('Clinical review context'), findsOneWidget);
    expect(find.textContaining('clinical assessment'), findsOneWidget);
  });
}
