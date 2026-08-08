import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:mycapstone_project/firebase_helper.dart';

class _MetricSpec {
  final String label;
  final String unit;
  final int precision;

  const _MetricSpec({required this.label, this.unit = '', this.precision = 1});
}

const Map<String, _MetricSpec> _metricSpecs = {
  'heart_rate': _MetricSpec(label: 'Heart rate', unit: 'bpm'),
  'blood_pressure_sys': _MetricSpec(label: 'Systolic pressure', unit: 'mmHg'),
  'blood_pressure_dia': _MetricSpec(label: 'Diastolic pressure', unit: 'mmHg'),
  'temperature': _MetricSpec(label: 'Temperature', unit: 'C'),
  'oxygen': _MetricSpec(label: 'Oxygen saturation', unit: '%'),
  'respiratory_rate': _MetricSpec(label: 'Respiratory rate', unit: 'brpm'),
  'weight': _MetricSpec(label: 'Weight', unit: 'kg'),
  'bmi': _MetricSpec(label: 'BMI'),
  'gestational_age': _MetricSpec(label: 'Gestational age', unit: 'weeks'),
  'cases': _MetricSpec(label: 'Cases identified', precision: 0),
  'cases_resolved': _MetricSpec(label: 'Cases resolved', precision: 0),
  'mortality_count': _MetricSpec(label: 'Mortality count', precision: 0),
};

const List<String> _metricPriority = [
  'heart_rate',
  'blood_pressure_sys',
  'blood_pressure_dia',
  'temperature',
  'oxygen',
  'respiratory_rate',
  'weight',
  'bmi',
  'gestational_age',
  'cases',
  'cases_resolved',
  'mortality_count',
];

String _formatNumber(double value, {int precision = 1}) {
  return value.toStringAsFixed(precision);
}

String _formatValueWithUnit(double value, _MetricSpec spec) {
  final formatted = _formatNumber(value, precision: spec.precision);
  return spec.unit.isEmpty ? formatted : '$formatted ${spec.unit}';
}

double? _extractDouble(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is num) {
    return value.toDouble();
  }

  final text = value.toString().trim();
  if (text.isEmpty) {
    return null;
  }

  final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(text.replaceAll(',', ''));
  if (match == null) {
    return null;
  }

  return double.tryParse(match.group(0)!);
}

Map<String, double>? _extractBloodPressure(dynamic value) {
  if (value == null) {
    return null;
  }

  final text = value.toString();
  final match = RegExp(r'(\d{2,3})\s*/\s*(\d{2,3})').firstMatch(text);
  if (match == null) {
    return null;
  }

  final systolic = double.tryParse(match.group(1)!);
  final diastolic = double.tryParse(match.group(2)!);
  if (systolic == null || diastolic == null) {
    return null;
  }

  return {'blood_pressure_sys': systolic, 'blood_pressure_dia': diastolic};
}

double? _extractLabeledValue(String text, List<String> labels) {
  if (text.trim().isEmpty) {
    return null;
  }

  for (final label in labels) {
    final pattern = RegExp(
      '${RegExp.escape(label)}\\s*[:=-]?\\s*(-?\\d+(?:\\.\\d+)?)',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(text);
    if (match != null) {
      final parsed = double.tryParse(match.group(1)!);
      if (parsed != null) {
        return parsed;
      }
    }
  }

  return null;
}

DateTime? _parseDate(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is Timestamp) {
    return value.toDate();
  }

  if (value is DateTime) {
    return value;
  }

  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final direct = DateTime.tryParse(trimmed);
    if (direct != null) {
      return direct;
    }

    final normalized = trimmed
        .replaceAll(RegExp(r'[^\x00-\x7F]'), '')
        .replaceAll(',', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final patterns = <String>[
      'yyyy-MM-dd HH:mm:ss',
      'yyyy-MM-dd HH:mm',
      'yyyy-MM-dd',
      'MM/dd/yyyy',
      'M/d/yyyy',
      'MM-dd-yyyy',
      'M-d-yyyy',
      'MMM d yyyy',
      'MMMM d yyyy',
    ];

    for (final pattern in patterns) {
      try {
        return DateFormat(pattern).parseLoose(normalized);
      } catch (_) {
        // Continue trying alternate date formats.
      }
    }
  }

  return null;
}

String? _cleanText(dynamic value) {
  if (value == null) {
    return null;
  }

  final text = value.toString().trim();
  if (text.isEmpty) {
    return null;
  }

  final lowered = text.toLowerCase();
  if (lowered == 'n/a' ||
      lowered == 'na' ||
      lowered == 'unknown' ||
      lowered == 'none' ||
      lowered == 'null') {
    return null;
  }

  return text;
}

String _capitalizeWords(String value) {
  return value
      .split(' ')
      .where((segment) => segment.isNotEmpty)
      .map(
        (segment) =>
            segment[0].toUpperCase() + segment.substring(1).toLowerCase(),
      )
      .join(' ');
}

String _prettyCollectionName(String source) {
  final mapped = <String, String>{
    'checkup_records': 'Check-up records',
    'patient_records': 'Patient records',
    'prenatal_records': 'Prenatal records',
    'barangay_records': 'Barangay records',
    'immunization_records': 'Immunization records',
    'morbidity_records': 'Morbidity records',
    'mortality_records': 'Mortality records',
  };

  if (mapped.containsKey(source)) {
    return mapped[source]!;
  }

  return _capitalizeWords(source.replaceAll('_', ' '));
}

String _formatDateRange(DateTime start, DateTime endExclusive) {
  final end = endExclusive.subtract(const Duration(days: 1));
  if (start.year == end.year &&
      start.month == end.month &&
      start.day == end.day) {
    return DateFormat.yMMMd().format(start);
  }

  if (start.year == end.year && start.month == end.month) {
    return '${DateFormat.MMM().format(start)} ${start.day}-${end.day}, ${start.year}';
  }

  if (start.year == end.year) {
    return '${DateFormat.MMMd().format(start)} - ${DateFormat.MMMd().format(end)}, ${start.year}';
  }

  return '${DateFormat.yMMMd().format(start)} - ${DateFormat.yMMMd().format(end)}';
}

Map<String, int> _countByField(List<Map<String, dynamic>> records, String key) {
  final counts = <String, int>{};
  for (final record in records) {
    final value = _cleanText(record[key]);
    if (value == null) {
      continue;
    }
    counts[value] = (counts[value] ?? 0) + 1;
  }
  return counts;
}

List<MapEntry<String, int>> _sortedEntries(Map<String, int> counts) {
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final countComparison = b.value.compareTo(a.value);
      if (countComparison != 0) {
        return countComparison;
      }
      return a.key.compareTo(b.key);
    });
  return entries;
}

String? _topCountLabel(Map<String, int> counts) {
  final entries = _sortedEntries(counts);
  if (entries.isEmpty) {
    return null;
  }
  return '${entries.first.key} (${entries.first.value})';
}

Map<String, Map<String, double>> _aggregateNumeric(
  List<Map<String, dynamic>> records,
) {
  final sum = <String, double>{};
  final count = <String, int>{};
  final min = <String, double>{};
  final max = <String, double>{};

  for (final record in records) {
    for (final key in _metricSpecs.keys) {
      final value = record[key];
      if (value is! num) {
        continue;
      }

      final numericValue = value.toDouble();
      sum[key] = (sum[key] ?? 0) + numericValue;
      count[key] = (count[key] ?? 0) + 1;

      final currentMin = min[key];
      if (currentMin == null || numericValue < currentMin) {
        min[key] = numericValue;
      }

      final currentMax = max[key];
      if (currentMax == null || numericValue > currentMax) {
        max[key] = numericValue;
      }
    }
  }

  final output = <String, Map<String, double>>{};
  for (final key in sum.keys) {
    output[key] = {
      'avg': sum[key]! / (count[key] ?? 1),
      'min': min[key] ?? 0,
      'max': max[key] ?? 0,
      'count': (count[key] ?? 0).toDouble(),
    };
  }

  return output;
}

List<Map<String, dynamic>> _filterRecordsByRange(
  List<Map<String, dynamic>> records,
  DateTime start,
  DateTime endExclusive,
) {
  return records
      .where((record) {
        final timestamp = record['timestamp'];
        if (timestamp is! DateTime) {
          return false;
        }
        return !timestamp.isBefore(start) && timestamp.isBefore(endExclusive);
      })
      .toList(growable: false);
}

int _countMetric(
  List<Map<String, dynamic>> records,
  String key,
  bool Function(double value) predicate,
) {
  var count = 0;
  for (final record in records) {
    final value = record[key];
    if (value is num && predicate(value.toDouble())) {
      count++;
    }
  }
  return count;
}

Map<String, dynamic> _normalizeRecord(
  String source,
  String recordId,
  Map<String, dynamic> doc,
) {
  final out = <String, dynamic>{'source': source, 'record_id': recordId};

  void putNumber(String key, dynamic value) {
    final parsed = _extractDouble(value);
    if (parsed != null) {
      out[key] = parsed;
    }
  }

  void putText(String key, dynamic value) {
    final cleaned = _cleanText(value);
    if (cleaned != null) {
      out[key] = cleaned;
    }
  }

  putNumber('heart_rate', doc['heartRate'] ?? doc['hr'] ?? doc['pulse']);
  putNumber(
    'temperature',
    doc['bodyTemperature'] ?? doc['temperature'] ?? doc['temp'],
  );
  putNumber('oxygen', doc['oxygenSaturation'] ?? doc['oxygen'] ?? doc['spo2']);
  putNumber('bmi', doc['bmi']);
  putNumber('weight', doc['weight'] ?? doc['wt']);
  putNumber('respiratory_rate', doc['respiratoryRate'] ?? doc['rr']);
  putNumber('gestational_age', doc['gestationalAge'] ?? doc['aog']);
  putNumber('cases', doc['cases'] ?? doc['count'] ?? doc['casesIdentified']);
  putNumber('cases_resolved', doc['casesResolved']);
  putNumber('mortality_count', doc['mortalityCount'] ?? doc['deaths']);

  final systolic = _extractDouble(
    doc['bpSystolic'] ?? doc['systolic'] ?? doc['bp_systolic'],
  );
  final diastolic = _extractDouble(
    doc['bpDiastolic'] ?? doc['diastolic'] ?? doc['bp_diastolic'],
  );
  if (systolic != null) {
    out['blood_pressure_sys'] = systolic;
  }
  if (diastolic != null) {
    out['blood_pressure_dia'] = diastolic;
  }

  final combinedVitalsText = [
    doc['bloodPressure'],
    doc['bp'],
    doc['vitalsigns'],
    doc['details'],
  ].where((value) => value != null).join(' | ');

  final bloodPressure = _extractBloodPressure(combinedVitalsText);
  if (bloodPressure != null) {
    if (!out.containsKey('blood_pressure_sys') &&
        bloodPressure['blood_pressure_sys'] != null) {
      out['blood_pressure_sys'] = bloodPressure['blood_pressure_sys'];
    }
    if (!out.containsKey('blood_pressure_dia') &&
        bloodPressure['blood_pressure_dia'] != null) {
      out['blood_pressure_dia'] = bloodPressure['blood_pressure_dia'];
    }
  }

  final temperatureFromText = _extractLabeledValue(combinedVitalsText, const [
    'Temp',
    'Temperature',
  ]);
  final heartRateFromText = _extractLabeledValue(combinedVitalsText, const [
    'HR',
    'Heart Rate',
    'Pulse',
  ]);
  final respiratoryRateFromText = _extractLabeledValue(
    combinedVitalsText,
    const ['RR', 'Respiratory Rate'],
  );
  final oxygenFromText = _extractLabeledValue(combinedVitalsText, const [
    'O2',
    'SpO2',
    'Oxygen',
    'Oxygen Saturation',
  ]);
  final weightFromText = _extractLabeledValue(combinedVitalsText, const [
    'Weight',
    'Wt',
  ]);

  if (!out.containsKey('temperature') && temperatureFromText != null) {
    out['temperature'] = temperatureFromText;
  }
  if (!out.containsKey('heart_rate') && heartRateFromText != null) {
    out['heart_rate'] = heartRateFromText;
  }
  if (!out.containsKey('respiratory_rate') && respiratoryRateFromText != null) {
    out['respiratory_rate'] = respiratoryRateFromText;
  }
  if (!out.containsKey('oxygen') && oxygenFromText != null) {
    out['oxygen'] = oxygenFromText;
  }
  if (!out.containsKey('weight') && weightFromText != null) {
    out['weight'] = weightFromText;
  }

  putText(
    'patient_name',
    doc['patient'] ?? doc['patientName'] ?? doc['fullName'] ?? doc['name'],
  );
  putText('status', doc['status']);
  putText('risk_level', doc['riskLevel'] ?? doc['ai_severity']);
  putText('disease', doc['disease'] ?? doc['diagnosis'] ?? doc['diseaseType']);
  putText('cause_of_death', doc['causeOfDeath']);
  putText(
    'vaccine',
    doc['vaccineName'] ?? doc['vaccineType'] ?? doc['vaccine'],
  );
  putText('barangay', doc['barangay'] ?? doc['barangayName']);
  putText('type', doc['type']);

  final timestamp =
      _parseDate(doc['timestamp']) ??
      _parseDate(doc['dateReported']) ??
      _parseDate(doc['datetime']) ??
      _parseDate(doc['registrationDate']) ??
      _parseDate(doc['administrationDate']) ??
      _parseDate(doc['createdAt']) ??
      _parseDate(doc['date']) ??
      _parseDate(doc['lastVisit']) ??
      _parseDate(doc['lastCheckup']);

  if (timestamp != null) {
    out['timestamp'] = timestamp;
  }

  return out;
}

String _generateSummary({
  required String title,
  required String periodLabel,
  required List<Map<String, dynamic>> records,
  required int sourceRecordCount,
}) {
  final buffer = StringBuffer()
    ..writeln(title.toUpperCase())
    ..writeln('Period: $periodLabel')
    ..writeln();

  if (records.isEmpty) {
    buffer
      ..writeln('OVERVIEW')
      ..writeln(
        sourceRecordCount == 0
            ? 'No records were available to summarize for the active account.'
            : 'No records with recognizable timestamps matched the selected period.',
      )
      ..writeln();

    buffer
      ..writeln('RECOMMENDED ACTIONS')
      ..writeln(
        '- Confirm that records include valid date fields such as datetime, registrationDate, administrationDate, or dateReported.',
      )
      ..writeln(
        '- Try a wider summary window like monthly or yearly to verify overall data coverage.',
      );

    return buffer.toString().trim();
  }

  final sourceCounts = _countByField(records, 'source');
  final sortedSourceCounts = _sortedEntries(sourceCounts);
  final metrics = _aggregateNumeric(records);

  final timestamps =
      records
          .map((record) => record['timestamp'])
          .whereType<DateTime>()
          .toList()
        ..sort();

  final earliest = timestamps.first;
  final latest = timestamps.last;

  buffer
    ..writeln('OVERVIEW')
    ..writeln(
      '${records.length} records matched the selected period across ${sourceCounts.length} source collection${sourceCounts.length == 1 ? '' : 's'}.',
    )
    ..writeln(
      'Observed activity window: ${DateFormat.yMMMd().format(earliest)} to ${DateFormat.yMMMd().format(latest)}.',
    )
    ..writeln();

  buffer.writeln('SOURCE COVERAGE');
  for (final entry in sortedSourceCounts) {
    buffer.writeln('- ${_prettyCollectionName(entry.key)}: ${entry.value}');
  }
  buffer.writeln();

  buffer.writeln('KEY METRICS');
  var metricLines = 0;
  for (final key in _metricPriority) {
    final stats = metrics[key];
    final spec = _metricSpecs[key];
    if (stats == null || spec == null) {
      continue;
    }

    metricLines++;
    buffer.writeln(
      '- ${spec.label}: avg ${_formatValueWithUnit(stats['avg']!, spec)} (min ${_formatValueWithUnit(stats['min']!, spec)}, max ${_formatValueWithUnit(stats['max']!, spec)})',
    );
  }
  if (metricLines == 0) {
    buffer.writeln(
      '- Limited numeric vital-sign data was available in the matched records.',
    );
  }
  buffer.writeln();

  final operationalSignals = <String>[];
  final activePrenatal = records.where((record) {
    final source = record['source']?.toString();
    final status = record['status']?.toString().toLowerCase();
    return source == 'prenatal_records' && status == 'active';
  }).length;
  if (activePrenatal > 0) {
    operationalSignals.add(
      'Active prenatal records in scope: $activePrenatal.',
    );
  }

  final highRiskPrenatal = records.where((record) {
    final source = record['source']?.toString();
    final risk = record['risk_level']?.toString().toLowerCase() ?? '';
    return source == 'prenatal_records' && risk.contains('high');
  }).length;
  if (highRiskPrenatal > 0) {
    operationalSignals.add(
      'High-risk prenatal records detected: $highRiskPrenatal.',
    );
  }

  final leadingDisease = _topCountLabel(_countByField(records, 'disease'));
  if (leadingDisease != null) {
    operationalSignals.add(
      'Most frequent documented disease or diagnosis: $leadingDisease.',
    );
  }

  final leadingCause = _topCountLabel(_countByField(records, 'cause_of_death'));
  if (leadingCause != null) {
    operationalSignals.add('Leading documented cause of death: $leadingCause.');
  }

  final leadingVaccine = _topCountLabel(_countByField(records, 'vaccine'));
  if (leadingVaccine != null) {
    operationalSignals.add(
      'Most frequently documented vaccine entry: $leadingVaccine.',
    );
  }

  final dominantStatus = _topCountLabel(_countByField(records, 'status'));
  if (dominantStatus != null) {
    operationalSignals.add('Most common workflow status: $dominantStatus.');
  }

  final topBarangay = _topCountLabel(_countByField(records, 'barangay'));
  if (topBarangay != null) {
    operationalSignals.add(
      'Most represented barangay in this window: $topBarangay.',
    );
  }

  buffer.writeln('OPERATIONAL SIGNALS');
  if (operationalSignals.isEmpty) {
    buffer.writeln(
      '- No strong operational clustering was detected in the matched records.',
    );
  } else {
    for (final line in operationalSignals) {
      buffer.writeln('- $line');
    }
  }
  buffer.writeln();

  final alerts = <String>[];
  final feverCount = _countMetric(
    records,
    'temperature',
    (value) => value >= 38.0,
  );
  if (feverCount > 0) {
    alerts.add(
      '$feverCount record${feverCount == 1 ? '' : 's'} show fever-range temperature readings.',
    );
  }

  final lowOxygenCount = _countMetric(records, 'oxygen', (value) => value < 92);
  if (lowOxygenCount > 0) {
    alerts.add(
      '$lowOxygenCount record${lowOxygenCount == 1 ? '' : 's'} show oxygen saturation below 92%.',
    );
  }

  final elevatedSystolicCount = _countMetric(
    records,
    'blood_pressure_sys',
    (value) => value >= 140,
  );
  if (elevatedSystolicCount > 0) {
    alerts.add(
      '$elevatedSystolicCount record${elevatedSystolicCount == 1 ? '' : 's'} show elevated systolic blood pressure.',
    );
  }

  final abnormalHeartRateCount = _countMetric(
    records,
    'heart_rate',
    (value) => value < 50 || value > 100,
  );
  if (abnormalHeartRateCount > 0) {
    alerts.add(
      '$abnormalHeartRateCount record${abnormalHeartRateCount == 1 ? '' : 's'} show outside-range heart rate readings.',
    );
  }

  if (highRiskPrenatal > 0) {
    alerts.add(
      '$highRiskPrenatal prenatal record${highRiskPrenatal == 1 ? '' : 's'} are tagged as high risk.',
    );
  }

  buffer.writeln('ALERTS');
  if (alerts.isEmpty) {
    buffer.writeln(
      '- No high-priority abnormal vital patterns were detected in the selected window.',
    );
  } else {
    for (final line in alerts) {
      buffer.writeln('- $line');
    }
  }
  buffer.writeln();

  final recommendations = <String>{};
  if (alerts.isNotEmpty) {
    recommendations.add(
      'Review the flagged records and confirm that follow-up, referral, or escalation was documented.',
    );
  }
  if (highRiskPrenatal > 0) {
    recommendations.add(
      'Prioritize active monitoring for high-risk prenatal cases and verify appointment adherence.',
    );
  }
  if (leadingDisease != null) {
    recommendations.add(
      'Track the leading disease pattern for outreach, supply planning, and early surge detection.',
    );
  }
  if (metricLines == 0) {
    recommendations.add(
      'Capture vital signs in structured fields consistently so future summaries can generate stronger clinical insights.',
    );
  }
  if (recommendations.isEmpty) {
    recommendations.add(
      'Continue routine monitoring and regenerate this report after new encounters are encoded.',
    );
  }

  buffer.writeln('RECOMMENDED ACTIONS');
  for (final line in recommendations) {
    buffer.writeln('- $line');
  }

  return buffer.toString().trim();
}

String generateDailySummary(DateTime day, List<Map<String, dynamic>> records) {
  final start = DateTime(day.year, day.month, day.day);
  final end = start.add(const Duration(days: 1));
  final filtered = _filterRecordsByRange(records, start, end);
  return _generateSummary(
    title: 'Daily Summary',
    periodLabel: _formatDateRange(start, end),
    records: filtered,
    sourceRecordCount: records.length,
  );
}

String generateMonthlySummary(
  int year,
  int month,
  List<Map<String, dynamic>> records,
) {
  final start = DateTime(year, month, 1);
  final end = month == 12
      ? DateTime(year + 1, 1, 1)
      : DateTime(year, month + 1, 1);
  final filtered = _filterRecordsByRange(records, start, end);
  return _generateSummary(
    title: 'Monthly Summary',
    periodLabel: _formatDateRange(start, end),
    records: filtered,
    sourceRecordCount: records.length,
  );
}

String generateYearlySummary(int year, List<Map<String, dynamic>> records) {
  final start = DateTime(year, 1, 1);
  final end = DateTime(year + 1, 1, 1);
  final filtered = _filterRecordsByRange(records, start, end);
  return _generateSummary(
    title: 'Yearly Summary',
    periodLabel: _formatDateRange(start, end),
    records: filtered,
    sourceRecordCount: records.length,
  );
}

Future<List<Map<String, dynamic>>> _fetchFromCollection(
  String collection, {
  String? userId,
  String? email,
}) async {
  final firestore = getFirestoreInstance();
  final out = <Map<String, dynamic>>[];
  final seenDocIds = <String>{};

  void addDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    if (!seenDocIds.add(doc.id)) {
      return;
    }

    final normalized = _normalizeRecord(collection, doc.id, doc.data());
    if (normalized.length > 2) {
      out.add(normalized);
    }
  }

  Future<void> runQuery(
    Future<QuerySnapshot<Map<String, dynamic>>> Function() action,
  ) async {
    try {
      final snapshot = await action();
      for (final doc in snapshot.docs) {
        addDoc(doc);
      }
    } catch (_) {
      // Firestore query availability varies by collection and indexes.
    }
  }

  if (userId != null && userId.isNotEmpty) {
    try {
      final doc = await firestore.collection(collection).doc(userId).get();
      if (doc.exists && doc.data() != null && seenDocIds.add(doc.id)) {
        final normalized = _normalizeRecord(collection, doc.id, doc.data()!);
        if (normalized.length > 2) {
          out.add(normalized);
        }
      }
    } catch (_) {
      // Continue with field-based lookups.
    }

    await runQuery(
      () => firestore
          .collection(collection)
          .where('patientId', isEqualTo: userId)
          .get(),
    );
    await runQuery(
      () =>
          firestore.collection(collection).where('id', isEqualTo: userId).get(),
    );
    await runQuery(
      () => firestore
          .collection(collection)
          .where('userId', isEqualTo: userId)
          .get(),
    );
  }

  if (email != null && email.isNotEmpty) {
    await runQuery(
      () => firestore
          .collection(collection)
          .where('emailAddress', isEqualTo: email)
          .get(),
    );
    await runQuery(
      () => firestore
          .collection(collection)
          .where('email', isEqualTo: email)
          .get(),
    );
  }

  if (out.isEmpty) {
    await runQuery(() => firestore.collection(collection).limit(120).get());
  }

  return out;
}

Future<List<Map<String, dynamic>>> fetchRecordsForUser({
  String? userId,
  String? email,
}) async {
  const collections = [
    'checkup_records',
    'patient_records',
    'prenatal_records',
    'barangay_records',
    'immunization_records',
    'morbidity_records',
    'mortality_records',
  ];

  final results = await Future.wait(
    collections.map(
      (collection) =>
          _fetchFromCollection(collection, userId: userId, email: email),
    ),
  );

  final unique = <String, Map<String, dynamic>>{};
  for (final records in results) {
    for (final record in records) {
      final timestamp =
          (record['timestamp'] as DateTime?)?.toIso8601String() ?? '';
      final key = [
        record['source'] ?? '',
        record['record_id'] ?? '',
        record['patient_name'] ?? '',
        record['disease'] ?? '',
        timestamp,
      ].join('|');

      unique.putIfAbsent(key, () => record);
    }
  }

  return unique.values.toList(growable: false);
}

Future<String> generateDailySummaryForCurrentUser(DateTime day) async {
  final user = FirebaseAuth.instance.currentUser;
  final records = await fetchRecordsForUser(
    userId: user?.uid,
    email: user?.email,
  );
  return generateDailySummary(day, records);
}

Future<String> generateMonthlySummaryForCurrentUser(int year, int month) async {
  final user = FirebaseAuth.instance.currentUser;
  final records = await fetchRecordsForUser(
    userId: user?.uid,
    email: user?.email,
  );
  return generateMonthlySummary(year, month, records);
}

Future<String> generateYearlySummaryForCurrentUser(int year) async {
  final user = FirebaseAuth.instance.currentUser;
  final records = await fetchRecordsForUser(
    userId: user?.uid,
    email: user?.email,
  );
  return generateYearlySummary(year, records);
}
