import 'package:mycapstone_project/app/core/services/health_screening_engine.dart';

/// Compatibility adapter for older web record cards.
///
/// The screening thresholds live in [HealthScreeningEngine]. This adapter keeps
/// the existing short labels used by the table UI without maintaining a second
/// set of vital-sign rules.
List<String> detectAbnormalVitalFlags(String? vitalSignsText) {
  final text = vitalSignsText?.trim() ?? '';
  if (text.isEmpty) return const <String>[];

  final result = HealthScreeningEngine.evaluate({'vitalsigns': text});
  final flags = <String>[];
  for (final finding in result.findings) {
    if (finding.isInformational ||
        finding.status.priority <
            HealthScreeningStatus.needsAttention.priority) {
      continue;
    }
    final label = switch (finding.measurementKey) {
      'temperature' => 'Fever range',
      'oxygen_saturation' => 'Low oxygen saturation',
      'blood_pressure' => 'Elevated blood pressure',
      'heart_rate' => 'Abnormal heart rate',
      'respiratory_rate' => 'Abnormal respiratory rate',
      _ => finding.measurement,
    };
    if (!flags.contains(label)) flags.add(label);
  }
  return flags;
}
