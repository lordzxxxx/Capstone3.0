import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/features/dashboard/widgets/modules_hub_view.dart';
import 'package:mycapstone_project/app/shared/widgets/mobile_clinical_ui.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

void main() {
  testWidgets(
    'clinical workspace keeps every primary workflow tappable on a narrow phone',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppDesign.theme(),
          home: const Scaffold(body: ModulesHubView()),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Care workspace'), findsOneWidget);
      expect(find.text('Check Up'), findsOneWidget);
      expect(find.text('Communicable Disease'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);
    },
  );

  testWidgets(
    'clinical loading skeleton is accessible and keeps a stable footprint',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppDesign.theme(),
          home: const Scaffold(
            body: ClinicalLoadingSkeleton(height: 120, margin: EdgeInsets.zero),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Loading clinical data'), findsOneWidget);
      expect(tester.getSize(find.byType(ClinicalLoadingSkeleton)).height, 120);
    },
  );
}
