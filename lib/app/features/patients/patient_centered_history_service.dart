import 'package:mycapstone_project/app/features/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/app/features/immunization/immunization_database_helper.dart';
import 'package:mycapstone_project/app/features/surveillance/morbidity/morbidity_database_helper.dart';
import 'package:mycapstone_project/app/features/surveillance/mortality/mortality_database_helper.dart';
import 'package:mycapstone_project/app/features/patients/patient_database_helper.dart';
import 'package:mycapstone_project/app/features/prenatal/prenatal_database_helper.dart';

class PatientTimelineEvent {
  final String module;
  final String recordId;
  final DateTime? eventDate;
  final String title;
  final String subtitle;
  final Map<String, dynamic> rawRecord;

  const PatientTimelineEvent({
    required this.module,
    required this.recordId,
    required this.eventDate,
    required this.title,
    required this.subtitle,
    required this.rawRecord,
  });
}

class PatientModuleHistorySnapshot {
  final Map<String, dynamic> patient;
  final List<Map<String, dynamic>> checkUpHistory;
  final List<Map<String, dynamic>> prenatalHistory;
  final List<Map<String, dynamic>> immunizationHistory;
  final List<Map<String, dynamic>> communicableHistory;
  final List<Map<String, dynamic>> nonCommunicableHistory;
  final List<Map<String, dynamic>> mortalityHistory;
  final List<Map<String, dynamic>> morbidityHistory;

  const PatientModuleHistorySnapshot({
    required this.patient,
    required this.checkUpHistory,
    required this.prenatalHistory,
    required this.immunizationHistory,
    required this.communicableHistory,
    required this.nonCommunicableHistory,
    required this.mortalityHistory,
    required this.morbidityHistory,
  });

  int get totalRecords =>
      checkUpHistory.length +
      prenatalHistory.length +
      immunizationHistory.length +
      communicableHistory.length +
      nonCommunicableHistory.length +
      mortalityHistory.length +
      morbidityHistory.length;

  List<PatientTimelineEvent> get timeline {
    final events = <PatientTimelineEvent>[];

    events.addAll(
      _buildTimeline(
        module: 'Check Up',
        records: checkUpHistory,
        dateKeys: const ['datetime', 'date', 'followup'],
        titleBuilder: (record) => _safeText(record['type'], fallback: 'Check-up'),
        subtitleBuilder: (record) => _safeText(
          record['details'],
          fallback: _safeText(record['status'], fallback: 'No notes'),
        ),
      ),
    );

    events.addAll(
      _buildTimeline(
        module: 'Prenatal',
        records: prenatalHistory,
        dateKeys: const ['registrationDate', 'dueDate', 'lmpDate'],
        titleBuilder: (record) => _safeText(
          record['riskLevel'],
          fallback: 'Prenatal visit',
        ),
        subtitleBuilder: (record) => _safeText(
          record['gestationalAge'],
          fallback: _safeText(record['status'], fallback: 'No status'),
        ),
      ),
    );

    events.addAll(
      _buildTimeline(
        module: 'Immunization',
        records: immunizationHistory,
        dateKeys: const ['administrationDate', 'date', 'time'],
        titleBuilder: (record) => _safeText(
          record['vaccine'],
          fallback: 'Immunization',
        ),
        subtitleBuilder: (record) {
          final dose = _safeText(record['doseNumber']);
          final status = _safeText(record['status']);
          if (dose.isNotEmpty && status.isNotEmpty) {
            return 'Dose $dose | $status';
          }
          return status.isNotEmpty ? status : 'No dose details';
        },
      ),
    );

    events.addAll(
      _buildTimeline(
        module: 'Communicable',
        records: communicableHistory,
        dateKeys: const ['datetime', 'date', 'followup'],
        titleBuilder: (record) => _safeText(
          record['symptoms'],
          fallback: _safeText(record['type'], fallback: 'Communicable case'),
        ),
        subtitleBuilder: (record) => _safeText(
          record['status'],
          fallback: _safeText(record['details'], fallback: 'No status'),
        ),
      ),
    );

    events.addAll(
      _buildTimeline(
        module: 'Non-Communicable',
        records: nonCommunicableHistory,
        dateKeys: const ['datetime', 'date', 'followup'],
        titleBuilder: (record) => _safeText(
          record['symptoms'],
          fallback: _safeText(record['type'], fallback: 'Chronic care'),
        ),
        subtitleBuilder: (record) => _safeText(
          record['status'],
          fallback: _safeText(record['details'], fallback: 'No status'),
        ),
      ),
    );

    events.addAll(
      _buildTimeline(
        module: 'Mortality',
        records: mortalityHistory,
        dateKeys: const ['dateReported', 'date'],
        titleBuilder: (record) => _safeText(
          record['causeOfDeath'],
          fallback: 'Mortality report',
        ),
        subtitleBuilder: (record) => _safeText(
          record['verification'],
          fallback: 'Verification pending',
        ),
      ),
    );

    events.addAll(
      _buildTimeline(
        module: 'Morbidity',
        records: morbidityHistory,
        dateKeys: const ['dateReported', 'date', 'time'],
        titleBuilder: (record) => _safeText(
          record['disease'],
          fallback: 'Morbidity record',
        ),
        subtitleBuilder: (record) => _safeText(
          record['status'],
          fallback: _safeText(record['severity'], fallback: 'No status'),
        ),
      ),
    );

    events.sort((left, right) => _compareDateDesc(left.eventDate, right.eventDate));
    return events;
  }

  static List<PatientTimelineEvent> _buildTimeline({
    required String module,
    required List<Map<String, dynamic>> records,
    required List<String> dateKeys,
    required String Function(Map<String, dynamic> record) titleBuilder,
    required String Function(Map<String, dynamic> record) subtitleBuilder,
  }) {
    return records.map((record) {
      return PatientTimelineEvent(
        module: module,
        recordId: _safeText(record['id'], fallback: ''),
        eventDate: _firstValidDate(record, dateKeys),
        title: titleBuilder(record),
        subtitle: subtitleBuilder(record),
        rawRecord: record,
      );
    }).toList();
  }

  static DateTime? _firstValidDate(
    Map<String, dynamic> record,
    List<String> keys,
  ) {
    for (final key in keys) {
      final parsed = _tryParseDate(record[key]);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  static DateTime? _tryParseDate(dynamic value) {
    final raw = _safeText(value);
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  static int _compareDateDesc(DateTime? left, DateTime? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return right.compareTo(left);
  }

  static String _safeText(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}

class PatientCenteredHistoryService {
  PatientCenteredHistoryService({
    PatientDatabaseHelper? patientHelper,
    DatabaseHelper? checkupHelper,
    PrenatalDatabaseHelper? prenatalHelper,
    ImmunizationDatabaseHelper? immunizationHelper,
    MortalityDatabaseHelper? mortalityHelper,
    MorbidityDatabaseHelper? morbidityHelper,
  }) : _patientHelper = patientHelper ?? PatientDatabaseHelper.instance,
       _checkupHelper = checkupHelper ?? DatabaseHelper.instance,
       _prenatalHelper = prenatalHelper ?? PrenatalDatabaseHelper.instance,
       _immunizationHelper =
           immunizationHelper ?? ImmunizationDatabaseHelper.instance,
       _mortalityHelper = mortalityHelper ?? MortalityDatabaseHelper.instance,
       _morbidityHelper = morbidityHelper ?? MorbidityDatabaseHelper.instance;

  final PatientDatabaseHelper _patientHelper;
  final DatabaseHelper _checkupHelper;
  final PrenatalDatabaseHelper _prenatalHelper;
  final ImmunizationDatabaseHelper _immunizationHelper;
  final MortalityDatabaseHelper _mortalityHelper;
  final MorbidityDatabaseHelper _morbidityHelper;

  Future<List<Map<String, dynamic>>> searchPatients(String query) async {
    final normalizedQuery = _normalize(query);
    final patients = await _patientHelper.getAllRecords();

    if (normalizedQuery.isEmpty) {
      return _sortPatients(patients);
    }

    final results = patients.where((patient) {
      final candidateFields = [
        patient['id'],
        patient['patientId'],
        patient['patientCode'],
        patient['firstName'],
        patient['surname'],
        _buildPatientName(patient),
        patient['dateOfBirth'],
        patient['phoneNumber'],
        patient['barangay'],
        patient['municipality'],
      ];

      return candidateFields.any(
        (value) => _normalize(value).contains(normalizedQuery),
      );
    }).toList();

    return _sortPatients(results);
  }

  Future<List<Map<String, dynamic>>> findDuplicateCandidates({
    required String firstName,
    required String surname,
    String? dateOfBirth,
    String? phoneNumber,
  }) async {
    final patients = await _patientHelper.getAllRecords();
    final normalizedName = _normalize('$firstName $surname');
    final normalizedDob = _normalize(dateOfBirth);
    final normalizedPhone = _normalize(phoneNumber);

    final matches = patients.where((patient) {
      final patientName = _normalize(_buildPatientName(patient));
      final sameName = patientName == normalizedName;
      final sameDob = normalizedDob.isNotEmpty &&
          _normalize(patient['dateOfBirth']) == normalizedDob;
      final samePhone = normalizedPhone.isNotEmpty &&
          _normalize(patient['phoneNumber']) == normalizedPhone;

      return sameName || (sameDob && samePhone);
    }).toList();

    return _sortPatients(matches);
  }

  Future<PatientModuleHistorySnapshot> loadPatientHistory(
    Map<String, dynamic> patient,
  ) async {
    final patientIdentifiers = _collectPatientIdentifiers(patient);
    final patientName = _normalize(_buildPatientName(patient));

    final results = await Future.wait<List<Map<String, dynamic>>>([
      _checkupHelper.getAllRecords(),
      _prenatalHelper.getAllRecords(),
      _immunizationHelper.getAllRecords(),
      _mortalityHelper.getAllRecords(),
      _morbidityHelper.getAllRecords(),
    ]);

    final allCheckups = results[0];
    final allPrenatal = results[1];
    final allImmunizations = results[2];
    final allMortality = results[3];
    final allMorbidity = results[4];

    final linkedCheckups = allCheckups.where((record) {
      return _recordMatchesPatient(
        record: record,
        patientIdentifiers: patientIdentifiers,
        patientName: patientName,
        idKeys: const ['linkedPatientId', 'patientId'],
        nameKeys: const ['patient', 'patientName'],
      );
    }).toList();

    final checkUpHistory = linkedCheckups.where((record) {
      final diseaseType = _normalize(record['diseaseType']);
      return diseaseType.isEmpty ||
          (diseaseType != 'communicable' &&
              diseaseType != 'non-communicable');
    }).toList();

    final communicableHistory = linkedCheckups.where((record) {
      return _normalize(record['diseaseType']) == 'communicable';
    }).toList();

    final nonCommunicableHistory = linkedCheckups.where((record) {
      return _normalize(record['diseaseType']) == 'non-communicable';
    }).toList();

    final prenatalHistory = allPrenatal.where((record) {
      return _recordMatchesPatient(
        record: record,
        patientIdentifiers: patientIdentifiers,
        patientName: patientName,
        idKeys: const ['linkedPatientId', 'patientId'],
        nameKeys: const ['patientName', 'patient'],
      );
    }).toList();

    final immunizationHistory = allImmunizations.where((record) {
      return _recordMatchesPatient(
        record: record,
        patientIdentifiers: patientIdentifiers,
        patientName: patientName,
        idKeys: const ['linkedPatientId', 'patientId'],
        nameKeys: const ['patientName', 'patient'],
      );
    }).toList();

    final mortalityHistory = allMortality.where((record) {
      return _recordMatchesPatient(
        record: record,
        patientIdentifiers: patientIdentifiers,
        patientName: patientName,
        idKeys: const ['linkedPatientId', 'patientId'],
        nameKeys: const ['name', 'patientName', 'patient'],
      );
    }).toList();

    final morbidityHistory = allMorbidity.where((record) {
      return _recordMatchesPatient(
        record: record,
        patientIdentifiers: patientIdentifiers,
        patientName: patientName,
        idKeys: const ['linkedPatientId', 'patientId'],
        nameKeys: const ['patientName', 'patient'],
      );
    }).toList();

    _sortRecordsByDate(
      checkUpHistory,
      const ['datetime', 'date', 'followup'],
    );
    _sortRecordsByDate(
      communicableHistory,
      const ['datetime', 'date', 'followup'],
    );
    _sortRecordsByDate(
      nonCommunicableHistory,
      const ['datetime', 'date', 'followup'],
    );
    _sortRecordsByDate(
      prenatalHistory,
      const ['registrationDate', 'dueDate', 'lmpDate'],
    );
    _sortRecordsByDate(
      immunizationHistory,
      const ['administrationDate', 'date', 'time'],
    );
    _sortRecordsByDate(mortalityHistory, const ['dateReported', 'date']);
    _sortRecordsByDate(
      morbidityHistory,
      const ['dateReported', 'date', 'time'],
    );

    return PatientModuleHistorySnapshot(
      patient: patient,
      checkUpHistory: checkUpHistory,
      prenatalHistory: prenatalHistory,
      immunizationHistory: immunizationHistory,
      communicableHistory: communicableHistory,
      nonCommunicableHistory: nonCommunicableHistory,
      mortalityHistory: mortalityHistory,
      morbidityHistory: morbidityHistory,
    );
  }

  List<Map<String, dynamic>> _sortPatients(List<Map<String, dynamic>> patients) {
    final sorted = List<Map<String, dynamic>>.from(patients);
    _sortRecordsByDate(sorted, const ['registrationDate']);
    return sorted;
  }

  void _sortRecordsByDate(
    List<Map<String, dynamic>> records,
    List<String> dateKeys,
  ) {
    records.sort((left, right) {
      final leftDate = _firstValidDate(left, dateKeys);
      final rightDate = _firstValidDate(right, dateKeys);
      return _compareDateDesc(leftDate, rightDate);
    });
  }

  bool _recordMatchesPatient({
    required Map<String, dynamic> record,
    required Set<String> patientIdentifiers,
    required String patientName,
    required List<String> idKeys,
    required List<String> nameKeys,
  }) {
    final hasIdMatch = idKeys.any((key) {
      final value = _normalize(record[key]);
      return value.isNotEmpty && patientIdentifiers.contains(value);
    });
    if (hasIdMatch) {
      return true;
    }

    if (patientName.isEmpty) {
      return false;
    }

    return nameKeys.any((key) => _normalize(record[key]) == patientName);
  }

  Set<String> _collectPatientIdentifiers(Map<String, dynamic> patient) {
    return {
      _normalize(patient['id']),
      _normalize(patient['patientId']),
      _normalize(patient['patientCode']),
    }.where((value) => value.isNotEmpty).toSet();
  }

  String _buildPatientName(Map<String, dynamic> patient) {
    final firstName = _safeText(patient['firstName']);
    final surname = _safeText(patient['surname']);
    final combined = '$firstName $surname'.trim();
    if (combined.isNotEmpty) {
      return combined;
    }
    return _safeText(
      patient['patientName'],
      fallback: _safeText(patient['name']),
    );
  }

  DateTime? _firstValidDate(
    Map<String, dynamic> record,
    List<String> keys,
  ) {
    for (final key in keys) {
      final parsed = _tryParseDate(record[key]);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  DateTime? _tryParseDate(dynamic value) {
    final raw = _safeText(value);
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  int _compareDateDesc(DateTime? left, DateTime? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return right.compareTo(left);
  }

  String _normalize(dynamic value) {
    return _safeText(value).toLowerCase();
  }

  String _safeText(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}
