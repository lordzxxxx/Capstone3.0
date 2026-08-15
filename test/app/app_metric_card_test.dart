import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/shared/widgets/app_metric_card.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

void main() {
  testWidgets('mobile metric card stays readable on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.theme(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: AppMetricCard(
              label: 'High Risk',
              value: '3',
              icon: Icons.warning_amber_outlined,
              supportingText: 'Requires closer monitoring',
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('High Risk'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Requires closer monitoring'), findsOneWidget);
  });
}
