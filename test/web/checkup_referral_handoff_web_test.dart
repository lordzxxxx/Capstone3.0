import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/roles/bhw/referrals/bhw_referral_management.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Check-Up to Referral Web Handoff Tests', () {
    testWidgets(
      'BhwReferralPage prefills patient demographics, clinical snapshot, and triage priority from checkup record',
      (WidgetTester tester) async {
        final sampleCheckupRecord = {
          'id': 'CHK-2026-9901',
          'patient': 'Santos, Maria Clara',
          'patientId': 'PAT-2026-0044',
          'linkedPatientId': 'PAT-2026-0044',
          'age': '28',
          'gender': 'Female',
          'sex': 'Female',
          'address': 'Purok 2, Barangay Casisang',
          'barangay': 'Casisang',
          'symptoms': 'High fever for 4 days, petechial rash on extremities',
          'diagnosis': 'Suspected Dengue with Warning Signs',
          'plan': 'Oral rehydration therapy, CBC monitoring, strict bed rest',
          'vitalsigns':
              'BP: 100/70 | Temp: 39.2°C | HR: 98 bpm | RR: 20 | SpO2: 98% | Weight: 54 kg | Height: 158 cm',
          'ai_severity': 'High',
          'ai_category': 'Emergency',
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BhwReferralPage(
                embedded: true,
                initialRecord: sampleCheckupRecord,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify BhwReferralPage loaded in embedded mode
        expect(find.byType(BhwReferralPage), findsOneWidget);

        // Verify patient demographics are rendered
        expect(find.text('PAT-2026-0044'), findsWidgets);
        expect(find.text('Santos, Maria Clara'), findsWidgets);
        expect(find.text('28'), findsWidgets);
        expect(find.text('Female'), findsWidgets);
        expect(find.text('Purok 2, Barangay Casisang'), findsWidgets);
        expect(find.text('Casisang'), findsWidgets);

        // Verify Referral Reason TextFormField contains diagnosis
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

        // Verify Observations TextFormField contains symptoms and vitals
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
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is EditableText && w.controller.text.contains('BP: 100/70'),
          ),
          findsOneWidget,
        );

        // Verify Supporting Notes TextFormField contains treatment plan
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is EditableText &&
                w.controller.text.contains(
                  'Oral rehydration therapy, CBC monitoring, strict bed rest',
                ),
          ),
          findsOneWidget,
        );

        // Verify Priority is set to emergency based on triage flags
        expect(
          find.text('Emergency'),
          findsWidgets,
        );
      },
    );

    testWidgets(
      'BhwReferralPage sets priority to Urgent when checkup indicates high risk',
      (WidgetTester tester) async {
        final urgentRecord = {
          'id': 'CHK-2026-9902',
          'patient': 'Dela Cruz, Juan',
          'patientId': 'PAT-2026-0099',
          'symptoms': 'Hypertension with headache',
          'diagnosis': 'Stage 2 Hypertension',
          'vitalsigns': 'BP: 160/100 | Temp: 37.0°C | HR: 88 bpm',
          'ai_severity': 'High',
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BhwReferralPage(
                embedded: true,
                initialRecord: urgentRecord,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(BhwReferralPage), findsOneWidget);
        expect(find.text('PAT-2026-0099'), findsWidgets);
        expect(find.text('Dela Cruz, Juan'), findsWidgets);
        expect(find.text('Urgent'), findsWidgets);
      },
    );
  });
}
