/// Shared mappings for clinical snapshots carried between BHW and CHO.
///
/// Check-up records have historically used several names for the same vital
/// signs field. Keeping the compatibility mapping here prevents one portal
/// from silently dropping a value written by another portal.
String summarizeVitalSigns(
  Map<String, dynamic>? record, {
  Map<String, dynamic>? fallbackRecord,
  String fallback = 'No linked vital signs',
}) {
  if (record == null && fallbackRecord == null) return fallback;

  final direct = _firstText(record, const [
    'latestVitalSigns',
    'vitalsigns',
    'completeVitalSigns',
    'vitalSigns',
    'vitals',
    'vital_signs',
  ]);
  if (direct.isNotEmpty) return direct;

  final source = record ?? fallbackRecord!;
  final values = <String>[];
  void add(String label, List<String> keys) {
    final value = _firstText(source, keys);
    if (value.isNotEmpty) values.add('$label: $value');
  }

  add('BP', const ['bloodPressure', 'blood_pressure', 'bp']);
  add('Temp', const ['temperature', 'temp']);
  add('Pulse', const ['pulseRate', 'pulse', 'heartRate']);
  add('Respiratory rate', const ['respiratoryRate']);
  add('SpO₂', const ['oxygenSaturation', 'spo2']);
  if (values.isNotEmpty) return values.join(' • ');

  if (record != null && fallbackRecord != null) {
    return summarizeVitalSigns(fallbackRecord, fallback: fallback);
  }
  return fallback;
}

String _firstText(Map<String, dynamic>? record, List<String> keys) {
  if (record == null) return '';
  for (final key in keys) {
    final value = record[key];
    if (value == null) continue;
    if (value is Iterable) {
      final text = value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .join(', ');
      if (text.isNotEmpty) return text;
    } else if (value is Map) {
      final text = value.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join(', ');
      if (text.isNotEmpty) return text;
    } else if (value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return '';
}
