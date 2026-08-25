import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/features/referrals/referrals.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Check-Up to Referral Mobile Handoff Tests', () {
    testWidgets('ReferralsPage prefills patient demographics and clinical snapshot from checkup record',
        (WidgetTester tester) async {
      final sampleCheckupRecord = {
        'id': 'CHK-2026-9901',
        'patient': 'Santos, Maria Clara',
        'patientId': 'PAT-2026-0044',
        'linkedPatientId': 'PAT-2026-0044',
        'age': '28',
        'gender': 'Female',
        'address': 'Purok 2, Barangay Casisang',
        'barangay': 'Casisang',
        'symptoms': 'High fever for 4 days, petechial rash on extremities',
        'diagnosis': 'Suspected Dengue with Warning Signs',
        'plan': 'Oral rehydration therapy, CBC monitoring, strict bed rest',
        'vitalsigns': 'BP: 100/70 | Temp: 39.2°C | HR: 98 bpm | RR: 20 | SpO2: 98% | Weight: 54 kg | Height: 158 cm',
        'ai_severity': 'High',
        'ai_category': 'Emergency',
      };

      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: ReferralsPage(
              initialRecord: sampleCheckupRecord,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify that the referral page loaded
      expect(find.byType(ReferralsPage), findsOneWidget);

      // Verify patient surname and first name are populated in EditableText fields
      expect(
        find.byWidgetPredicate(
          (w) => w is EditableText && w.controller.text == 'Santos',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is EditableText && w.controller.text == 'Maria Clara',
        ),
        findsOneWidget,
      );

      // Verify symptoms / chief complaint are populated
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is EditableText &&
              w.controller.text.contains(
                'High fever for 4 days, petechial rash on extremities',
              ),
        ),
        findsOneWidget,
      );

      // Verify diagnosis / impression is populated
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is EditableText &&
              w.controller.text.contains(
                'Suspected Dengue with Warning Signs',
              ),
        ),
        findsOneWidget,
      );

      // Verify vital signs are populated
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is EditableText &&
              w.controller.text.contains('BP: 100/70'),
        ),
        findsOneWidget,
      );
    });
  });
}
