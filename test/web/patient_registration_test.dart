import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/canonical_patient_details_modal.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/canonical_patient_registration_modal.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_database_helper.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_identity_utils.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_operational_summary.dart';

void main() {
  test('patient ID generation is stable and recognizable', () {
    final patientId = PatientDatabaseHelper.generatePatientId(
      DateTime(2026, 7, 21, 9, 8, 7, 456),
    );
    expect(patientId, 'PAT-20260721-090807-456');
  });

  test('patient names preserve first-name and surname positions', () {
    expect(
      patientNameParts({'firstName': 'Maria Elena', 'surname': 'Santos'}),
      (firstName: 'Maria Elena', middleName: '', surname: 'Santos'),
    );
    expect(patientNameParts({'fullName': 'Maria Elena Santos'}), (
      firstName: 'Maria Elena',
      middleName: '',
      surname: 'Santos',
    ));
    expect(
      patientNameParts({
        'firstName': 'Maria',
        'middleName': 'Elena',
        'surname': 'Santos',
      }),
      (firstName: 'Maria', middleName: 'Elena', surname: 'Santos'),
    );
  });

  testWidgets('registration form exposes the canonical patient fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CanonicalPatientRegistrationModal(
          patientId: 'PAT-TEST-001',
          initialBarangay: 'Laguitas',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('PAT-TEST-001'), findsOneWidget);
    expect(find.text('First Name'), findsOneWidget);
    expect(find.text('Middle Name'), findsOneWidget);
    expect(find.text('Surname'), findsOneWidget);
    expect(find.text('Date of Birth'), findsOneWidget);
    expect(find.text('Age'), findsOneWidget);
    expect(find.text('Sex'), findsOneWidget);
    expect(find.text('Address'), findsOneWidget);
    expect(find.text('Barangay'), findsOneWidget);
    expect(find.text('Household ID'), findsOneWidget);
    expect(find.text('Contact Number'), findsOneWidget);
    expect(find.text('Emergency Contact Name'), findsOneWidget);
    expect(find.text('Emergency Contact Relationship'), findsOneWidget);
    expect(find.text('Emergency Contact Number'), findsOneWidget);
    expect(find.text('Parent/Guardian Name (Optional)'), findsOneWidget);
    expect(find.text('Medical History'), findsOneWidget);
    expect(find.text('Allergies (Optional)'), findsOneWidget);
  });

  testWidgets(
    'edit mode uses the registration form and prefills patient data',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CanonicalPatientRegistrationModal(
            existingPatient: {
              'id': 'PAT-EDIT-001',
              'patientId': 'PAT-EDIT-001',
              'fullName': 'Maria Santos',
              'firstName': 'Maria',
              'middleName': 'Clara',
              'surname': 'Santos',
              'dateOfBirth': '1990-05-12',
              'age': '36',
              'sex': 'Female',
              'address': 'Purok 2',
              'barangay': 'Laguitas',
              'householdId': 'HH-100',
              'contactNumber': '09123456789',
              'emergencyContact': 'Juan Santos - 09987654321',
              'emergencyContactName': 'Juan Santos',
              'emergencyRelationship': 'Parent',
              'emergencyContactNumber': '09987654321',
              'medicalHistory': 'Hypertension',
              'allergies': 'Penicillin',
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Edit Patient'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);
      expect(find.text('PAT-EDIT-001'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Maria'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Clara'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Santos'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Parent'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Laguitas'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Hypertension'),
        findsOneWidget,
      );
    },
  );

  testWidgets('details view shows the canonical registration record', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CanonicalPatientDetailsModal(
          patient: {
            'patientId': 'PAT-VIEW-001',
            'fullName': 'Ana Reyes',
            'firstName': 'Ana',
            'middleName': 'Marie',
            'surname': 'Reyes',
            'dateOfBirth': '1995-03-01',
            'age': '31',
            'sex': 'Female',
            'address': 'Purok 4',
            'barangay': 'Laguitas',
            'householdId': 'HH-200',
            'contactNumber': '09170000000',
            'emergencyContact': 'Pedro Reyes',
            'emergencyContactName': 'Pedro Reyes',
            'emergencyRelationship': 'Sibling',
            'emergencyContactNumber': '09181111111',
            'medicalHistory': 'None',
            'allergies': 'None',
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Patient Details'), findsOneWidget);
    expect(find.textContaining('PAT-VIEW-001'), findsOneWidget);
    expect(find.text('Ana Marie Reyes'), findsOneWidget);
    expect(find.text('First Name'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Surname'), findsOneWidget);
    expect(find.text('Reyes'), findsOneWidget);
    expect(find.text('Middle Name'), findsOneWidget);
    expect(find.text('Marie'), findsOneWidget);
    expect(find.text('Address'), findsOneWidget);
    expect(find.text('Household ID'), findsOneWidget);
    expect(find.text('Emergency Contact Number'), findsOneWidget);
    expect(find.text('Emergency Contact Name'), findsOneWidget);
    expect(find.text('Emergency Contact Relationship'), findsOneWidget);
    expect(find.text('Sibling'), findsOneWidget);
    expect(find.text('09181111111'), findsOneWidget);
    expect(find.text('Medical History'), findsOneWidget);
    expect(find.text('Allergies'), findsOneWidget);
    expect(find.text('Health Timeline'), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
  });

  testWidgets('BHW patient summary contains operational registry sections', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PatientOperationalSummary(
              patients: const [
                {
                  'patientId': 'PAT-001',
                  'firstName': 'Ana',
                  'surname': 'Reyes',
                  'age': '31',
                  'sex': 'Female',
                  'barangay': 'Laguitas',
                  'householdId': 'HH-01',
                  'status': 'Active',
                  'registrationDate': '2026-07-01',
                },
              ],
              onViewPatient: (_) {},
              onViewAll: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Patient Overview'), findsOneWidget);
    expect(find.text('Registration Summary'), findsOneWidget);
    expect(find.text('Household Summary'), findsOneWidget);
    expect(find.text('Demographic Overview'), findsOneWidget);
    expect(find.text('Health Summary'), findsOneWidget);
    expect(find.text('Follow-up Summary'), findsOneWidget);
    expect(find.text('Patient Alerts'), findsOneWidget);
    expect(find.text('Recent Registrations'), findsOneWidget);
    expect(find.textContaining('AI'), findsNothing);
  });
}
