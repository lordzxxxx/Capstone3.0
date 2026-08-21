/// Lightweight, non-diagnostic detection of abnormal vital-sign readings from
/// a check-up record's freeform `vitalsigns` label string (e.g.
/// "BP: 150/95, Temp: 38.6°C, HR: 110 bpm, O2: 90%").
///
/// This is decision-support only: it never blocks, auto-fills, or auto-submits
/// anything. Thresholds are intentionally duplicated from the alert logic in
/// `ai_summary.dart` rather than shared, since that generator's output is also
/// consumed by the mobile app and must not take on a web-only UI dependency.
library;

double? _extractLabeledValue(String text, List<String> labels) {
  for (final label in labels) {
    final pattern = RegExp(
      '${RegExp.escape(label)}\\s*[:=-]?\\s*(-?\\d+(?:\\.\\d+)?)',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(text);
    if (match != null) {
      final parsed = double.tryParse(match.group(1)!);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

double? _extractSystolicBp(String text) {
  final match = RegExp(r'(\d{2,3})\s*/\s*\d{2,3}').firstMatch(text);
  if (match == null) return null;
  return double.tryParse(match.group(1)!);
}

/// Returns short human-readable flags for vital readings that cross known
/// abnormal thresholds, or an empty list if none apply or the text can't be
/// parsed.
List<String> detectAbnormalVitalFlags(String? vitalSignsText) {
  final text = vitalSignsText?.trim() ?? '';
  if (text.isEmpty) return const <String>[];

  final flags = <String>[];

  final temperature = _extractLabeledValue(text, const ['Temp', 'Temperature']);
  if (temperature != null && temperature >= 38.0) {
    flags.add('Fever range');
  }

  final oxygen = _extractLabeledValue(text, const [
    'O2',
    'SpO2',
    'Oxygen',
    'Oxygen Saturation',
  ]);
  if (oxygen != null && oxygen < 92) {
    flags.add('Low oxygen saturation');
  }

  final systolic = _extractSystolicBp(text);
  if (systolic != null && systolic >= 140) {
    flags.add('Elevated blood pressure');
  }

  final heartRate = _extractLabeledValue(text, const ['HR', 'Heart Rate', 'Pulse']);
  if (heartRate != null && (heartRate < 50 || heartRate > 100)) {
    flags.add('Abnormal heart rate');
  }

  return flags;
}
