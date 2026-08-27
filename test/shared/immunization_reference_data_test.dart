import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/shared/immunization_reference_data.dart';

void main() {
  test('keeps legacy vaccine values and includes reviewed additions', () {
    expect(kImmunizationVaccineOptions, contains('BCG Vaccine'));
    expect(kImmunizationVaccineOptions, contains('Hepatitis B'));
    expect(kImmunizationVaccineOptions, contains('IPV'));
    expect(kImmunizationVaccineOptions, contains('PCV'));
    expect(kImmunizationVaccineOptions, contains('Influenza'));
    expect(kImmunizationVaccineOptions, contains('Pneumococcal'));
    expect(
      kImmunizationVaccineOptions.toSet().length,
      kImmunizationVaccineOptions.length,
    );
  });
}
