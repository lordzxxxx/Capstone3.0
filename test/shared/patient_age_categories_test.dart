import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/shared/patient_age_categories.dart';

void main() {
  test('uses the shared patient demographic boundaries', () {
    expect(PatientAgeCategories.forYears(0)?.label, '0–5');
    expect(PatientAgeCategories.forYears(5)?.label, '0–5');
    expect(PatientAgeCategories.forYears(6)?.label, '6–17');
    expect(PatientAgeCategories.forYears(17)?.label, '6–17');
    expect(PatientAgeCategories.forYears(18)?.label, '18–59');
    expect(PatientAgeCategories.forYears(59)?.label, '18–59');
    expect(PatientAgeCategories.forYears(60)?.label, '60+');
  });

  test('parses stored age values without accepting malformed values', () {
    expect(PatientAgeCategories.forValue('17 years')?.label, '6–17');
    expect(PatientAgeCategories.forValue(' 60 '), isNotNull);
    expect(PatientAgeCategories.forValue('17abc'), isNull);
    expect(PatientAgeCategories.forYears(-1), isNull);
    expect(PatientAgeCategories.forYears(131), isNull);
  });

  test('calculates birth-date boundaries using the birthday', () {
    final today = DateTime(2026, 8, 28);
    expect(
      PatientAgeCategories.fromBirthDate(DateTime(2020, 8, 28), today: today),
      6,
    );
    expect(
      PatientAgeCategories.fromBirthDate(DateTime(2020, 8, 29), today: today),
      5,
    );
    expect(
      PatientAgeCategories.fromBirthDate(DateTime(2027, 1, 1), today: today),
      isNull,
    );
  });
}
