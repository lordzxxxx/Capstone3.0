import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_centered_history_service.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_first_service_selector.dart';

class _FakePatientService extends PatientCenteredHistoryService {
  _FakePatientService(this.results);

  final List<Map<String, dynamic>> results;

  @override
  Future<List<Map<String, dynamic>>> searchRegisteredPatients(
    String query,
  ) async {
    return results;
  }
}

void main() {
  testWidgets('requires a registered patient selection before continuing', (
    tester,
  ) async {
    final service = _FakePatientService([
      {
        'patientName': 'Ana Santos',
        'patientId': 'PAT-001',
        'age': '28',
        'barangay': 'Laguitas',
        'isRegisteredPatient': true,
      },
    ]);
    Future<PatientSelectionResult?>? selection;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              selection = PatientFirstServiceSelector.show(
                context,
                serviceLabel: 'Check-up',
                patientService: service,
              );
            },
            child: const Text('Add Check-up'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add Check-up'));
    await tester.pumpAndSettle();
    expect(find.text('Select Patient for Check-up'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Ana');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Ana Santos'), findsOneWidget);
    expect(find.textContaining('PAT-001'), findsOneWidget);

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    final result = await selection;
    expect(result?.patient?['patientId'], 'PAT-001');
    expect(result?.registerPatient, isFalse);
  });

  testWidgets('offers registration when no canonical patient exists', (
    tester,
  ) async {
    final service = _FakePatientService(const []);
    Future<PatientSelectionResult?>? selection;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              selection = PatientFirstServiceSelector.show(
                context,
                serviceLabel: 'Immunization',
                patientService: service,
              );
            },
            child: const Text('Add Immunization'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add Immunization'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Missing Patient');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Patient not found'), findsOneWidget);
    expect(find.text('Register New Patient'), findsOneWidget);
    await tester.tap(find.text('Register New Patient'));
    await tester.pumpAndSettle();
    final result = await selection;
    expect(result?.registerPatient, isTrue);
    expect(result?.patient, isNull);
  });
}
