import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/app/shared/widgets/health_record_card.dart';
import 'package:mycapstone_project/app/theme/app_theme.dart';

void main() {
  testWidgets('health record card preserves module-specific information', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.theme(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: HealthRecordCard(
              recordLabel: 'Prenatal care',
              patientName: 'Maria Santos',
              location: 'Barangay 1, Malaybalay',
              accentColor: AppDesign.prenatal,
              status: 'High Risk',
              metadata: [
                RecordMetadata(
                  label: 'Gestational age',
                  value: '28 weeks',
                  icon: Icons.pregnant_woman,
                ),
                RecordMetadata(
                  label: 'Blood pressure',
                  value: '120/80 mmHg',
                  icon: Icons.monitor_heart_outlined,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('MARIA SANTOS'), findsNothing);
    expect(find.text('Maria Santos'), findsOneWidget);
    expect(find.text('PRENATAL CARE'), findsOneWidget);
    expect(find.text('HIGH RISK'), findsOneWidget);
    expect(find.text('28 weeks'), findsOneWidget);
    expect(find.text('120/80 mmHg'), findsOneWidget);
  });

  test('record date formatting is readable and safe', () {
    expect(HealthRecordDate.format('2026-08-11T14:30:00'), 'Aug 11, 2026');
    expect(HealthRecordDate.time('2026-08-11T14:30:00'), '2:30 PM');
    expect(HealthRecordDate.format(null), 'Not recorded');
  });
}
