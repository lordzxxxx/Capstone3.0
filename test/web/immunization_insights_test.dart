import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/roles/bhw/immunization/immunization_insights.dart';

void main() {
  testWidgets('immunization insights exposes all requested chart types', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ImmunizationInsights(
              records: [
                {
                  'patientId': 'P-001',
                  'age': '8 months',
                  'vaccine': 'BCG Vaccine',
                  'administrationDate': now.toIso8601String(),
                  'nextDoseDueDate': DateTime(
                    now.year,
                    now.month + 1,
                    10,
                  ).toIso8601String(),
                  'status': 'Completed',
                  'stockRemaining': 42,
                  'adverseEvents': 'Mild fever',
                },
                {
                  'patientId': 'P-002',
                  'age': '2 years',
                  'vaccine': 'MMR Vaccine',
                  'administrationDate': DateTime(
                    now.year,
                    now.month - 1,
                    5,
                  ).toIso8601String(),
                  'nextDoseDueDate': DateTime(
                    now.year,
                    now.month - 1,
                    20,
                  ).toIso8601String(),
                  'status': 'Overdue',
                  'stockRemaining': 18,
                  'adverseEvents': 'None',
                },
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total Records'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.text('In Progress'), findsNothing);
    expect(find.text('Monthly Immunizations Administered'), findsOneWidget);
    expect(find.text('Vaccine Coverage Rate'), findsOneWidget);
    expect(find.text('Fully vs Partially Immunized'), findsOneWidget);
    expect(
      find.text('Age Distribution of Vaccinated Children'),
      findsOneWidget,
    );
    expect(find.text('Upcoming Vaccination Schedule'), findsOneWidget);
    expect(find.text('Overdue Immunizations'), findsOneWidget);
    expect(find.text('Vaccine Stock Monitoring'), findsOneWidget);
    expect(find.text('Adverse Events Following Immunization'), findsOneWidget);
    expect(find.byType(LineChart), findsNWidgets(2));
    expect(find.byType(BarChart), findsNWidgets(5));
    expect(find.byType(PieChart), findsOneWidget);
  });
}
