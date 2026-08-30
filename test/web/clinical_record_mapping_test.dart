import 'package:flutter_test/flutter_test.dart';
import 'package:mycapstone_project/web/shared/utils/clinical_record_mapping.dart';

void main() {
  test('summarizes the BHW check-up vitalsigns field', () {
    expect(
      summarizeVitalSigns({'vitalsigns': 'BP: 120/80, Temp: 36.7°C'}),
      'BP: 120/80, Temp: 36.7°C',
    );
  });

  test('supports the CHO latestVitalSigns snapshot and legacy keys', () {
    expect(
      summarizeVitalSigns({'latestVitalSigns': 'BP: 130/90'}),
      'BP: 130/90',
    );
    expect(
      summarizeVitalSigns(
        {'referralReason': 'follow-up'},
        fallbackRecord: {'heartRate': '88', 'oxygenSaturation': '98'},
        fallback: 'Not provided',
      ),
      'Pulse: 88 • SpO₂: 98',
    );
  });
}
