import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/web/roles/bhw/checkups/checkup_database_helper.dart';
import 'package:mycapstone_project/web/roles/bhw/immunization/immunization_database_helper.dart';
import 'package:mycapstone_project/web/roles/bhw/surveillance/mortality_database_helper.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_database_helper.dart';
import 'package:mycapstone_project/web/roles/bhw/patients/patient_identity_utils.dart';
import 'package:mycapstone_project/web/roles/bhw/prenatal/prenatal_database_helper.dart';
import 'package:mycapstone_project/web/shared/models/doctor_note.dart';
import 'package:mycapstone_project/web/shared/services/doctor_notes_service.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';

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
  final List<Map<String, dynamic>> referralHistory;
  final List<DoctorNote> doctorNotes;

  const PatientModuleHistorySnapshot({
    required this.patient,
    required this.checkUpHistory,
    required this.prenatalHistory,
    required this.immunizationHistory,
    required this.communicableHistory,
    required this.nonCommunicableHistory,
    required this.mortalityHistory,
    required this.morbidityHistory,
    required this.referralHistory,
    required this.doctorNotes,
  });

  int get totalRecords =>
      checkUpHistory.length +
      prenatalHistory.length +
      immunizationHistory.length +
      communicableHistory.length +
      nonCommunicableHistory.length +
      mortalityHistory.length +
      morbidityHistory.length +
      referralHistory.length;

  List<PatientTimelineEvent> get timeline {
    final events = <PatientTimelineEvent>[];

    events.addAll(
      _buildTimeline(
        module: 'Check Up',
        records: checkUpHistory,
        dateKeys: const ['datetime', 'date', 'followup'],
        titleBuilder: (record) =>
            _safeText(record['type'], fallback: 'Check-up'),
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
        titleBuilder: (record) =>
            _safeText(record['riskLevel'], fallback: 'Prenatal visit'),
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
        titleBuilder: (record) =>
            _safeText(record['vaccine'], fallback: 'Immunization'),
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
        titleBuilder: (record) =>
            _safeText(record['causeOfDeath'], fallback: 'Mortality report'),
        subtitleBuilder: (record) =>
            _safeText(record['verification'], fallback: 'Verification pending'),
      ),
    );

    events.addAll(
      _buildTimeline(
        module: 'Morbidity',
        records: morbidityHistory,
        dateKeys: const ['datetime', 'dateReported', 'date'],
        titleBuilder: (record) => _safeText(
          record['symptoms'],
          fallback: _safeText(record['disease'], fallback: 'Morbidity record'),
        ),
        subtitleBuilder: (record) => _safeText(
          record['status'],
          fallback: _safeText(record['details'], fallback: 'No status'),
        ),
      ),
    );

    events.addAll(
      _buildTimeline(
        module: 'Referral',
        records: referralHistory,
        dateKeys: const ['createdAt', 'referralDateTime'],
        titleBuilder: (record) => _safeText(
          record['referralReason'],
          fallback:
              'Referral ${_safeText(record['status'], fallback: 'submitted')}',
        ),
        subtitleBuilder: (record) {
          final status = _safeText(record['status'], fallback: 'submitted');
          final doctor = _safeText(record['assignedDoctorName']);
          return doctor.isNotEmpty
              ? 'Status: $status | Assigned: $doctor'
              : 'Status: $status';
        },
      ),
    );

    events.addAll(
      doctorNotes.map(
        (note) => PatientTimelineEvent(
          module: 'Doctor Note',
          recordId: note.id,
          eventDate: note.createdAt,
          title: note.authorName.isEmpty
              ? 'Doctor note'
              : '${note.authorName}${note.authorRole.isEmpty ? '' : ' (${note.authorRole})'}',
          subtitle: note.note.length > 140
              ? '${note.note.substring(0, 140)}…'
              : note.note,
          rawRecord: const <String, dynamic>{},
        ),
      ),
    );

    events.sort(
      (left, right) => _compareDateDesc(left.eventDate, right.eventDate),
    );
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
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();

    if (value is num) {
      final integer = value.toInt();
      return integer.abs() > 100000000000
          ? DateTime.fromMillisecondsSinceEpoch(integer)
          : DateTime.fromMillisecondsSinceEpoch(integer * 1000);
    }

    if (value is Map) {
      final seconds = value['seconds'] ?? value['_seconds'];
      final nanoseconds = value['nanoseconds'] ?? value['_nanoseconds'] ?? 0;
      if (seconds is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          (seconds * 1000).round() +
              (nanoseconds is num ? (nanoseconds / 1000000).round() : 0),
        );
      }
    }

    final raw = _safeText(value);
    if (raw.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed;

    final serializedTimestamp = RegExp(
      r'seconds\s*[=:]\s*(-?\d+)(?:.*nanoseconds\s*[=:]\s*(\d+))?',
      caseSensitive: false,
    ).firstMatch(raw);
    final seconds = int.tryParse(serializedTimestamp?.group(1) ?? '');
    if (seconds == null) return null;
    final nanoseconds = int.tryParse(serializedTimestamp?.group(2) ?? '') ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(
      (seconds * 1000) + (nanoseconds ~/ 1000000),
    );
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
  }) : _patientHelper = patientHelper ?? PatientDatabaseHelper.instance,
       _checkupHelper = checkupHelper ?? DatabaseHelper.instance,
       _prenatalHelper = prenatalHelper ?? PrenatalDatabaseHelper.instance,
       _immunizationHelper =
           immunizationHelper ?? ImmunizationDatabaseHelper.instance,
       _mortalityHelper = mortalityHelper ?? MortalityDatabaseHelper.instance;

  final PatientDatabaseHelper _patientHelper;
  final DatabaseHelper _checkupHelper;
  final PrenatalDatabaseHelper _prenatalHelper;
  final ImmunizationDatabaseHelper _immunizationHelper;
  final MortalityDatabaseHelper _mortalityHelper;

  Future<List<Map<String, dynamic>>> searchRegisteredPatients(
    String query,
  ) async {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final patients = await _patientHelper.getAllRecords();
    final matches = patients
        .where(
          (patient) => _candidateMatchesQuery(
            candidate: patient,
            normalizedQuery: normalizedQuery,
            extraFields: [
              patient['id'],
              patient['patientId'],
              patient['patientCode'],
              patient['fullName'],
              patient['firstName'],
              patient['middleName'],
              patient['surname'],
              _buildPatientName(patient),
              patient['dateOfBirth'],
              patient['phoneNumber'],
              patient['contactNumber'],
              patient['householdId'],
              patient['barangay'],
              patient['municipality'],
              patient['address'],
            ],
          ),
        )
        .map(
          (patient) => {
            ..._normalizePatientCandidate(patient),
            'sourceModules': const <String>['Patient Records'],
            'isRegisteredPatient': true,
          },
        )
        .toList(growable: false);
    return _sortPatients(matches);
  }

  Future<Map<String, dynamic>?> resolveRegisteredPatient(
    Map<String, dynamic>? seed,
  ) async {
    if (seed == null) return null;
    if (seed['isRegisteredPatient'] == true) {
      return Map<String, dynamic>.from(seed);
    }

    final seedKeys = _buildPatientLookupKeys(seed).toSet();
    if (seedKeys.isEmpty) return null;
    final patients = await _patientHelper.getAllRecords();
    for (final patient in patients) {
      final normalized = _normalizePatientCandidate(patient);
      final patientKeys = _buildPatientLookupKeys(normalized);
      if (patientKeys.any(seedKeys.contains)) {
        return {
          ...normalized,
          'sourceModules': const <String>['Patient Records'],
          'isRegisteredPatient': true,
        };
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> searchPatients(String query) async {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) {
      final patients = await _patientHelper.getAllRecords();
      return _sortPatients(patients);
    }

    final results = await Future.wait<dynamic>([
      _patientHelper.getAllRecords(),
      _checkupHelper.getAllRecords(),
      _prenatalHelper.getAllRecords(),
      _immunizationHelper.getAllRecords(),
      _mortalityHelper.getAllRecords(),
      _loadMorbidityRecords(),
    ]);

    final mergedPatients = <String, Map<String, dynamic>>{};
    final lookupIndex = <String, String>{};

    void addCandidate(
      Map<String, dynamic> candidate,
      String sourceModule,
      List<dynamic> searchableFields,
    ) {
      if (!_candidateMatchesQuery(
        candidate: candidate,
        normalizedQuery: normalizedQuery,
        extraFields: searchableFields,
      )) {
        return;
      }

      final lookupKeys = _buildPatientLookupKeys(candidate);
      if (lookupKeys.isEmpty) {
        return;
      }

      String? canonicalKey;
      for (final key in lookupKeys) {
        final matchedKey = lookupIndex[key];
        if (matchedKey != null) {
          canonicalKey = matchedKey;
          break;
        }
      }

      canonicalKey ??= _buildPatientMergeKey(candidate);
      if (canonicalKey.isEmpty) {
        return;
      }

      final existing = mergedPatients[canonicalKey];
      if (existing == null) {
        mergedPatients[canonicalKey] = {
          ...candidate,
          'sourceModules': <String>[sourceModule],
        };
      } else {
        _mergePatientCandidate(existing, candidate, sourceModule);
      }

      final mergedCandidate = mergedPatients[canonicalKey]!;
      for (final key in _buildPatientLookupKeys(mergedCandidate)) {
        lookupIndex[key] = canonicalKey;
      }
    }

    for (final patient in List<Map<String, dynamic>>.from(results[0] as List)) {
      addCandidate(_normalizePatientCandidate(patient), 'Patient Records', [
        patient['id'],
        patient['patientId'],
        patient['patientCode'],
        patient['firstName'],
        patient['surname'],
        _buildPatientName(patient),
        patient['dateOfBirth'],
        patient['phoneNumber'],
        patient['contactNumber'],
        patient['barangay'],
        patient['municipality'],
        patient['address'],
      ]);
    }

    for (final record in List<Map<String, dynamic>>.from(results[1] as List)) {
      addCandidate(
        _buildSearchCandidateFromRecord(
          record,
          patientNameKeys: const ['patientName', 'patient', 'name'],
          idKeys: const ['linkedPatientId', 'patientId', 'patientCode'],
          ageKeys: const ['age'],
          addressKeys: const ['address'],
          phoneKeys: const ['contactNumber', 'phoneNumber'],
          genderKeys: const ['gender', 'sex'],
          dateKeys: const ['datetime', 'followup', 'createdAt', 'timestamp'],
        ),
        'Check Up',
        [
          record['patientName'],
          record['patient'],
          record['name'],
          record['patientId'],
          record['linkedPatientId'],
          record['patientCode'],
          record['address'],
          record['contactNumber'],
        ],
      );
    }

    for (final record in List<Map<String, dynamic>>.from(results[2] as List)) {
      addCandidate(
        _buildSearchCandidateFromRecord(
          record,
          patientNameKeys: const ['patientName', 'patient', 'name'],
          idKeys: const ['linkedPatientId', 'patientId', 'patientCode'],
          ageKeys: const ['age'],
          addressKeys: const ['address'],
          phoneKeys: const ['contactNumber', 'phoneNumber'],
          genderKeys: const ['gender', 'sex'],
          dateKeys: const ['registrationDate', 'dueDate', 'createdAt'],
        ),
        'Prenatal',
        [
          record['patientName'],
          record['patient'],
          record['patientId'],
          record['address'],
          record['contactNumber'],
        ],
      );
    }

    for (final record in List<Map<String, dynamic>>.from(results[3] as List)) {
      addCandidate(
        _buildSearchCandidateFromRecord(
          record,
          patientNameKeys: const ['patientName', 'patient', 'name'],
          idKeys: const ['linkedPatientId', 'patientId', 'patientCode'],
          ageKeys: const ['age'],
          addressKeys: const ['address'],
          phoneKeys: const ['contactNumber', 'phoneNumber'],
          genderKeys: const ['gender', 'sex'],
          dateKeys: const ['administrationDate', 'date', 'createdAt'],
        ),
        'Immunization',
        [
          record['patientName'],
          record['patient'],
          record['patientId'],
          record['address'],
          record['contactNumber'],
        ],
      );
    }

    for (final record in List<Map<String, dynamic>>.from(results[4] as List)) {
      addCandidate(
        _buildSearchCandidateFromRecord(
          record,
          patientNameKeys: const ['name', 'patientName', 'patient'],
          idKeys: const ['linkedPatientId', 'patientId', 'patientCode'],
          ageKeys: const ['age'],
          addressKeys: const ['address', 'place'],
          phoneKeys: const ['contactNumber', 'phoneNumber'],
          genderKeys: const ['gender', 'sex'],
          dateKeys: const ['dateReported', 'date', 'createdAt'],
        ),
        'Mortality',
        [
          record['name'],
          record['patientName'],
          record['patientId'],
          record['linkedPatientId'],
          record['place'],
          record['address'],
        ],
      );
    }

    for (final record in List<Map<String, dynamic>>.from(results[5] as List)) {
      addCandidate(
        _buildSearchCandidateFromRecord(
          record,
          patientNameKeys: const ['patientName', 'patient', 'name'],
          idKeys: const ['linkedPatientId', 'patientId', 'patientCode'],
          ageKeys: const ['age'],
          addressKeys: const ['address'],
          phoneKeys: const ['contactNumber', 'phoneNumber'],
          genderKeys: const ['gender', 'sex'],
          dateKeys: const ['reportedDate', 'dateReported', 'datetime', 'date'],
        ),
        'Morbidity',
        [
          record['patientName'],
          record['patient'],
          record['patientId'],
          record['linkedPatientId'],
          record['address'],
        ],
      );
    }

    return _sortPatients(mergedPatients.values.toList());
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
      final sameDob =
          normalizedDob.isNotEmpty &&
          _normalize(patient['dateOfBirth']) == normalizedDob;
      final samePhone =
          normalizedPhone.isNotEmpty &&
          _normalize(patient['phoneNumber']) == normalizedPhone;

      return sameName && (sameDob || samePhone);
    }).toList();

    return _sortPatients(matches);
  }

  Future<PatientModuleHistorySnapshot> loadPatientHistory(
    Map<String, dynamic> patient,
  ) async {
    final patientIdentifiers = _collectPatientIdentifiers(patient);
    final patientName = _normalize(_buildPatientName(patient));
    final patientId = _safeText(
      patient['patientId'],
      fallback: _safeText(patient['id']),
    );

    final results = await Future.wait<List<Map<String, dynamic>>>([
      _checkupHelper.getAllRecords(),
      _prenatalHelper.getAllRecords(),
      _immunizationHelper.getAllRecords(),
      _mortalityHelper.getAllRecords(),
      _loadMorbidityRecords(),
      _loadReferralHistory(patient: patient, patientId: patientId),
    ]);

    final allCheckups = results[0];
    final allPrenatal = results[1];
    final allImmunizations = results[2];
    final allMortality = results[3];
    final allMorbidity = results[4];
    final referralHistory = results[5];
    final doctorNotes = await DoctorNotesService().fetchNotesForPatient(
      patientId,
    );

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
          (diseaseType != 'communicable' && diseaseType != 'non-communicable');
    }).toList();

    final communicableHistory = linkedCheckups.where((record) {
      return _normalize(record['diseaseType']) == 'communicable';
    }).toList();

    final nonCommunicableHistory = linkedCheckups.where((record) {
      return _normalize(record['diseaseType']) == 'non-communicable';
    }).toList();

    final morbidityHistory = linkedCheckups
        .where(_isMorbidityLikeRecord)
        .toList();
    final directMorbidityHistory = allMorbidity.where((record) {
      return _recordMatchesPatient(
        record: record,
        patientIdentifiers: patientIdentifiers,
        patientName: patientName,
        idKeys: const ['linkedPatientId', 'patientId'],
        nameKeys: const ['patientName', 'patient', 'name'],
      );
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

    _sortRecordsByDate(checkUpHistory, const ['datetime', 'date', 'followup']);
    _sortRecordsByDate(communicableHistory, const [
      'datetime',
      'date',
      'followup',
    ]);
    _sortRecordsByDate(nonCommunicableHistory, const [
      'datetime',
      'date',
      'followup',
    ]);
    _sortRecordsByDate(morbidityHistory, const [
      'datetime',
      'dateReported',
      'date',
    ]);
    for (final record in directMorbidityHistory) {
      final recordId = _safeText(record['id']);
      final alreadyIncluded = morbidityHistory.any(
        (existing) =>
            _safeText(existing['id']) == recordId && recordId.isNotEmpty,
      );
      if (!alreadyIncluded) {
        morbidityHistory.add(record);
      }
    }
    _sortRecordsByDate(morbidityHistory, const [
      'reportedDate',
      'datetime',
      'dateReported',
      'date',
    ]);
    _sortRecordsByDate(prenatalHistory, const [
      'registrationDate',
      'dueDate',
      'lmpDate',
    ]);
    _sortRecordsByDate(immunizationHistory, const [
      'administrationDate',
      'date',
      'time',
    ]);
    _sortRecordsByDate(mortalityHistory, const ['dateReported', 'date']);

    return PatientModuleHistorySnapshot(
      patient: patient,
      checkUpHistory: checkUpHistory,
      prenatalHistory: prenatalHistory,
      immunizationHistory: immunizationHistory,
      communicableHistory: communicableHistory,
      nonCommunicableHistory: nonCommunicableHistory,
      mortalityHistory: mortalityHistory,
      morbidityHistory: morbidityHistory,
      referralHistory: referralHistory,
      doctorNotes: doctorNotes,
    );
  }

  /// Fetches this patient's referral history using a query filter that
  /// mirrors `canReadReferral` in firestore.rules exactly, so the query
  /// never asks Firestore for documents the current user isn't authorized
  /// to read: CHO/SuperAdmin see every referral for the patient; a DOCTOR
  /// sees referrals assigned to them; a BHW sees referrals they created.
  Future<List<Map<String, dynamic>>> _loadReferralHistory({
    required Map<String, dynamic> patient,
    required String patientId,
  }) async {
    final rawPatientName = _buildPatientName(patient);
    if (patientId.isEmpty && rawPatientName.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    try {
      final scope = await UserAccessScopeService.instance.loadCurrentScope();
      Query<Map<String, dynamic>> query = getFirestoreInstance().collection(
        'referrals',
      );
      query = patientId.isNotEmpty
          ? query.where('patientId', isEqualTo: patientId)
          : query.where('patientName', isEqualTo: rawPatientName);

      if (!scope.canViewAllBarangays) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) {
          return const <Map<String, dynamic>>[];
        }
        query = scope.role == 'doctor'
            ? query.where('assignedDoctorUid', isEqualTo: uid)
            : query.where('createdByUid', isEqualTo: uid);
      }

      final snapshot = await query.get();
      return snapshot.docs.map(materializeFirestoreRecord).toList();
    } on FirebaseException {
      return const <Map<String, dynamic>>[];
    }
  }

  bool _isMorbidityLikeRecord(Map<String, dynamic> record) {
    final classification = _normalize(record['diseaseType']);
    final disease = _normalize(
      record['symptoms'] ??
          record['disease'] ??
          record['diagnosis'] ??
          record['condition'] ??
          record['ai_category'],
    );
    final severity = _normalize(record['severity'] ?? record['ai_severity']);
    final remarks = _normalize(
      record['remarks'] ?? record['plan'] ?? record['details'],
    );

    return classification == 'communicable' ||
        classification == 'non-communicable' ||
        (classification.isNotEmpty && classification != 'general') ||
        (disease.isNotEmpty &&
            disease != 'general' &&
            disease != 'general clinical case' &&
            disease != 'unspecified') ||
        (severity.isNotEmpty &&
            severity != 'n/a' &&
            severity != 'unspecified') ||
        (remarks.isNotEmpty && remarks != 'no remarks recorded') ||
        disease.contains('disease') ||
        disease.contains('fever') ||
        disease.contains('infection') ||
        disease.contains('hypertension') ||
        disease.contains('diabetes');
  }

  List<Map<String, dynamic>> _sortPatients(
    List<Map<String, dynamic>> patients,
  ) {
    final sorted = List<Map<String, dynamic>>.from(patients);
    _sortRecordsByDate(sorted, const [
      'registrationDate',
      'latestActivityDate',
      'dateReported',
      'administrationDate',
      'datetime',
      'createdAt',
    ]);
    return sorted;
  }

  Future<List<Map<String, dynamic>>> _loadMorbidityRecords() async {
    try {
      final accessScope = await UserAccessScopeService.instance
          .loadCurrentScope();
      final snapshot = await buildScopedRecordQuery(
        getFirestoreInstance(),
        'morbidity_records',
        accessScope,
      ).get();

      return snapshot.docs.map(materializeFirestoreRecord).toList();
    } on FirebaseException {
      return const <Map<String, dynamic>>[];
    }
  }

  bool _candidateMatchesQuery({
    required Map<String, dynamic> candidate,
    required String normalizedQuery,
    List<dynamic> extraFields = const [],
  }) {
    final candidateFields = [
      candidate['id'],
      candidate['patientId'],
      candidate['linkedPatientId'],
      candidate['patientCode'],
      candidate['fullName'],
      candidate['firstName'],
      candidate['surname'],
      candidate['patientName'],
      candidate['name'],
      candidate['dateOfBirth'],
      candidate['phoneNumber'],
      candidate['contactNumber'],
      candidate['barangay'],
      candidate['municipality'],
      candidate['address'],
      candidate['age'],
      ...extraFields,
    ];

    return candidateFields.any(
      (value) => _normalize(value).contains(normalizedQuery),
    );
  }

  Map<String, dynamic> _normalizePatientCandidate(
    Map<String, dynamic> patient,
  ) {
    final patientName = _buildPatientName(patient);
    final nameParts = _splitName(patientName);
    final patientId = _safeText(
      patient['patientId'],
      fallback: _safeText(patient['id']),
    );

    return {
      ...patient,
      'id': _safeText(patient['id'], fallback: patientId),
      'linkedPatientId': _safeText(
        patient['linkedPatientId'],
        fallback: patientId,
      ),
      'patientId': patientId,
      'patientCode': _safeText(patient['patientCode']),
      'patientName': patientName,
      'patient': patientName,
      'name': patientName,
      'firstName': _safeText(patient['firstName'], fallback: nameParts.first),
      'surname': _safeText(patient['surname'], fallback: nameParts.last),
      'age': _safeText(patient['age']),
      'address': _composeAddress(patient),
      'barangay': _safeText(patient['barangay']),
      'municipality': _safeText(patient['municipality']),
      'contactNumber': _safeText(
        patient['contactNumber'],
        fallback: _safeText(patient['phoneNumber']),
      ),
      'phoneNumber': _safeText(
        patient['phoneNumber'],
        fallback: _safeText(patient['contactNumber']),
      ),
      'emergencyContact': _safeText(
        patient['emergencyContact'],
        fallback: _safeText(patient['emergencyContactName']),
      ),
      'emergencyContactNumber': _safeText(
        patient['emergencyContactNumber'],
        fallback: _safeText(patient['emergencyContactPhone']),
      ),
      'gender': _safeText(
        patient['gender'],
        fallback: _safeText(patient['sex']),
      ),
      'sex': _safeText(patient['sex'], fallback: _safeText(patient['gender'])),
      'latestActivityDate': _safeText(
        patient['registrationDate'],
        fallback: _safeText(patient['createdAt']),
      ),
    };
  }

  Map<String, dynamic> _buildSearchCandidateFromRecord(
    Map<String, dynamic> record, {
    required List<String> patientNameKeys,
    required List<String> idKeys,
    required List<String> ageKeys,
    required List<String> addressKeys,
    required List<String> phoneKeys,
    required List<String> genderKeys,
    required List<String> dateKeys,
  }) {
    final patientName = _firstText(record, patientNameKeys);
    final nameParts = _splitName(patientName);
    final patientId = _firstText(record, idKeys);
    final linkedPatientId = _safeText(
      record['linkedPatientId'],
      fallback: _safeText(record['patientId']),
    );

    return {
      ...record,
      'recordId': _safeText(record['id']),
      'id': _safeText(linkedPatientId, fallback: patientId),
      'linkedPatientId': linkedPatientId,
      'patientId': patientId,
      'patientCode': _safeText(record['patientCode']),
      'patientName': patientName,
      'patient': patientName,
      'name': patientName,
      'firstName': _safeText(record['firstName'], fallback: nameParts.first),
      'surname': _safeText(record['surname'], fallback: nameParts.last),
      'age': _firstText(record, ageKeys),
      'address': _firstText(record, addressKeys),
      'barangay': _safeText(record['barangay']),
      'municipality': _safeText(record['municipality']),
      'contactNumber': _firstText(record, phoneKeys),
      'phoneNumber': _safeText(
        record['phoneNumber'],
        fallback: _firstText(record, phoneKeys),
      ),
      'gender': _firstText(record, genderKeys),
      'sex': _safeText(record['sex'], fallback: _firstText(record, genderKeys)),
      'latestActivityDate': _firstText(record, dateKeys),
    };
  }

  void _mergePatientCandidate(
    Map<String, dynamic> existing,
    Map<String, dynamic> incoming,
    String sourceModule,
  ) {
    final existingModules = List<String>.from(
      existing['sourceModules'] as List? ?? const <String>[],
    );
    if (!existingModules.contains(sourceModule)) {
      existingModules.add(sourceModule);
      existing['sourceModules'] = existingModules;
    }

    for (final entry in incoming.entries) {
      if (entry.key == 'sourceModules') {
        continue;
      }

      final currentValue = _safeText(existing[entry.key]);
      final nextValue = _safeText(entry.value);
      if (currentValue.isEmpty && nextValue.isNotEmpty) {
        existing[entry.key] = entry.value;
      }
    }

    final existingDate = _tryParseDate(existing['latestActivityDate']);
    final incomingDate = _tryParseDate(incoming['latestActivityDate']);
    if (incomingDate != null &&
        (existingDate == null || incomingDate.isAfter(existingDate))) {
      existing['latestActivityDate'] = incoming['latestActivityDate'];
    }
  }

  String _buildPatientMergeKey(Map<String, dynamic> patient) {
    final lookupKeys = _buildPatientLookupKeys(patient);
    if (lookupKeys.isNotEmpty) {
      return lookupKeys.first;
    }

    return '';
  }

  List<String> _buildPatientLookupKeys(Map<String, dynamic> patient) {
    final keys = <String>[];
    final identifiers = [
      patient['patientId'],
      patient['linkedPatientId'],
      patient['patientCode'],
      patient['id'],
    ];

    for (final value in identifiers) {
      final normalized = _normalize(value);
      if (normalized.isNotEmpty) {
        final key = 'id:$normalized';
        if (!keys.contains(key)) {
          keys.add(key);
        }
      }
    }

    final patientName = _normalize(
      patient['patientName'] ?? patient['name'] ?? _buildPatientName(patient),
    );
    final address = _normalize(patient['address']);
    final age = _normalize(patient['age']);
    final contact = _normalize(
      patient['contactNumber'] ?? patient['phoneNumber'],
    );

    if (patientName.isNotEmpty && address.isNotEmpty) {
      final key = 'name_address:$patientName|$address';
      if (!keys.contains(key)) {
        keys.add(key);
      }
    }

    if (patientName.isNotEmpty && age.isNotEmpty) {
      final key = 'name_age:$patientName|$age';
      if (!keys.contains(key)) {
        keys.add(key);
      }
    }

    if (patientName.isNotEmpty && contact.isNotEmpty) {
      final key = 'name_contact:$patientName|$contact';
      if (!keys.contains(key)) {
        keys.add(key);
      }
    }

    final hasSpecificNameKey =
        patientName.isNotEmpty &&
        (address.isNotEmpty || age.isNotEmpty || contact.isNotEmpty);
    if (patientName.isNotEmpty &&
        !hasSpecificNameKey &&
        keys.where((key) => key.startsWith('id:')).isEmpty) {
      final key = 'name:$patientName';
      if (!keys.contains(key)) {
        keys.add(key);
      }
    }

    return keys;
  }

  String _firstText(Map<String, dynamic> record, List<String> keys) {
    for (final key in keys) {
      final value = _safeText(record[key]);
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  String _composeAddress(Map<String, dynamic> patient) {
    final directAddress = _safeText(patient['address']);
    if (directAddress.isNotEmpty) {
      return directAddress;
    }

    final parts = [
      _safeText(patient['street']),
      _safeText(patient['barangay']),
      _safeText(patient['municipality']),
    ].where((value) => value.isNotEmpty).toList();

    return parts.join(', ');
  }

  List<String> _splitName(String fullName) {
    final parts = patientNameParts({'fullName': fullName});
    return [parts.firstName, parts.surname];
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
    return patientDisplayName(patient, fallback: '');
  }

  DateTime? _firstValidDate(Map<String, dynamic> record, List<String> keys) {
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
