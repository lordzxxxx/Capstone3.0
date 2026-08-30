import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/shared/immunization_record_utils.dart';
import 'package:mycapstone_project/shared/patient_age_categories.dart';

void main() {
  test('groups records by patient id before falling back to name', () {
    expect(
      immunizationPatientKey({'patientId': 'PAT-001', 'patientName': 'Same'}),
      'id:pat-001',
    );
    expect(
      immunizationPatientKey({'patientName': '  Same Patient  '}),
      'name:same patient',
    );
  });

  test('pediatric patients receive guardian snapshots, adults do not', () {
    final child = immunizationIdentitySnapshot(
      patient: {
        'patientId': 'child-1',
        'firstName': 'Child',
        'middleName': 'M',
        'surname': 'Patient',
        'age': '4',
        'guardian': 'Parent Patient',
      },
    );
    final adult = immunizationIdentitySnapshot(
      patient: {
        'patientId': 'adult-1',
        'fullName': 'Adult Patient',
        'age': '28',
        'guardian': 'Should not be copied',
      },
    );

    expect(child['middleName'], 'M');
    expect(child['parentGuardianName'], 'Parent Patient');
    expect(adult.containsKey('parentGuardianName'), isFalse);
    expect(
      immunizationIdentitySnapshot(
        patient: {'age': '16', 'guardian': 'Guardian A'},
      ),
      containsPair('parentGuardianName', 'Guardian A'),
    );
  });

  test(
    'preserves an existing custom dose while exposing structured options',
    () {
      expect(immunizationDoseOptions(existing: '2nd dose').first, '2nd dose');
      expect(immunizationDoseOptions(existing: '2nd dose'), contains('Dose 2'));
      expect(
        immunizationDoseOptions(existing: 'Dose 2'),
        kImmunizationDoseOptions,
      );
    },
  );

  test('classifies a patient from age or date of birth', () {
    expect(
      immunizationPatientAgeCategory({'age': '5'}),
      PatientAgeCategory.child,
    );
    expect(
      immunizationPatientAgeCategory({
        'dateOfBirth': '2000-01-01',
      }, today: DateTime(2026, 8, 30)),
      PatientAgeCategory.adult,
    );
  });

  test('detects same-patient vaccine and dose on the same date', () {
    final base = {
      'patientId': 'patient-1',
      'vaccine': 'BCG Vaccine',
      'doseNumber': 'Initial',
      'administrationDate': '2026-08-30T09:00:00.000Z',
    };
    expect(
      immunizationLooksLikeDuplicate(base, {
        ...base,
        'id': 'new-record',
        'administrationDate': '2026-08-30T14:00:00.000Z',
      }),
      isTrue,
    );
    expect(
      immunizationLooksLikeDuplicate(base, {...base, 'doseNumber': 'Dose 1'}),
      isFalse,
    );
  });
}
