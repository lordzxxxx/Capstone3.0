import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/shared/barangay_scope_utils.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/shared/components/app_sidebar.dart';
import 'package:mycapstone_project/web/features/auth/login.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';

const Color _primaryAqua = Color(0xFF2F80ED);
const Color _darkDeepTeal = Color(0xFF071A33);
const Color _panelSurface = Colors.white;
const Color _panelAlt = Color(0xFFEDF3FA);
const Color _lightOffWhite = Color(0xFF0B1F3A);
const Color _mutedCoolGray = Color(0xFF4B6075);

class BHWAnalyticsPage extends StatefulWidget {
  const BHWAnalyticsPage({super.key});

  @override
  State<BHWAnalyticsPage> createState() => _BHWAnalyticsPageState();
}

class _BHWAnalyticsPageState extends State<BHWAnalyticsPage> {
  static const List<_AnalyticsModuleDefinition>
  _modules = <_AnalyticsModuleDefinition>[
    _AnalyticsModuleDefinition(
      id: 'immunization_records',
      title: 'Immunization',
      subtitle:
          'Track vaccine coverage, missed follow-ups, and monthly protection activity.',
      icon: Icons.vaccines_rounded,
      accent: Color(0xFF4DD0E1),
    ),
    _AnalyticsModuleDefinition(
      id: 'checkup_records',
      title: 'Check-up',
      subtitle:
          'Monitor outpatient workload, service demand, and consultation movement.',
      icon: Icons.assignment_turned_in_rounded,
      accent: Color(0xFF5EEAD4),
    ),
    _AnalyticsModuleDefinition(
      id: 'mortality_records',
      title: 'Mortality',
      subtitle:
          'Review reported deaths, likely causes, and outcome reporting patterns.',
      icon: Icons.monitor_heart_outlined,
      accent: Color(0xFFF87171),
    ),
    _AnalyticsModuleDefinition(
      id: 'morbidity',
      title: 'Morbidity',
      subtitle:
          'Visualize disease burden, severity patterns, and encoded case load.',
      icon: Icons.bar_chart_rounded,
      accent: Color(0xFFFFB74D),
    ),
    _AnalyticsModuleDefinition(
      id: 'referrals',
      title: 'Referrals',
      subtitle:
          'Track submitted referrals, destination facilities, and follow-through activity.',
      icon: Icons.assignment_ind_rounded,
      accent: Color(0xFF22D3EE),
    ),
    _AnalyticsModuleDefinition(
      id: 'communicable',
      title: 'Communicable',
      subtitle:
          'Surface outbreak-prone conditions that need quick community response.',
      icon: Icons.coronavirus_rounded,
      accent: Color(0xFFFF8A65),
    ),
    _AnalyticsModuleDefinition(
      id: 'non_communicable',
      title: 'Non-Communicable',
      subtitle:
          'Track chronic disease load for continuity of care and follow-up planning.',
      icon: Icons.health_and_safety_rounded,
      accent: Color(0xFF64B5F6),
    ),
    _AnalyticsModuleDefinition(
      id: 'patient_records',
      title: 'Patient Records',
      subtitle:
          'Monitor registry growth, patient continuity, and barangay record coverage.',
      icon: Icons.people_alt_rounded,
      accent: Color(0xFFA78BFA),
    ),
  ];

  static const List<String> _baseCollections = <String>[
    'patient_records',
    'checkup_records',
    'immunization_records',
    'morbidity_records',
    'mortality_records',
    'referrals',
  ];

  static const Set<String> _communicableKeywords = <String>{
    'covid',
    'dengue',
    'fever',
    'flu',
    'influenza',
    'infection',
    'measles',
    'malaria',
    'rabies',
    'tuberculosis',
    'tb',
    'pneumonia',
    'diarrhea',
    'diarrhoea',
    'hepatitis',
    'chickenpox',
    'hand foot mouth',
  };

  static const Set<String> _nonCommunicableKeywords = <String>{
    'arthritis',
    'asthma',
    'cancer',
    'chronic',
    'copd',
    'diabetes',
    'heart',
    'hypertension',
    'kidney',
    'obesity',
    'renal',
    'stroke',
    'tumor',
  };

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FirebaseFirestore _firestore = getFirestoreInstance();
  Timer? _refreshTimer;

  UserAccessScope _accessScope = UserAccessScope.unauthenticated;
  bool _isLoading = true;
  final String _selectedWindowLabel = '6 Months';
  String? _hoveredProgramCardId;
  String? _hoveredInsightPanelId;
  DateTime? _lastUpdatedAt;
  List<Map<String, dynamic>> _patientRawRecords =
      const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _checkupRawRecords =
      const <Map<String, dynamic>>[];
  Map<String, List<_AnalyticsRecord>> _programRecords =
      <String, List<_AnalyticsRecord>>{
        for (final module in _modules) module.id: <_AnalyticsRecord>[],
      };

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
    _refreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _loadAnalytics(showLoader: false);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  int get _selectedWindowMonths {
    switch (_selectedWindowLabel) {
      case '3 Months':
        return 3;
      case '12 Months':
        return 12;
      case '6 Months':
      default:
        return 6;
    }
  }

  Future<void> _loadAnalytics({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final scope = await UserAccessScopeService.instance.loadCurrentScope();
      if (!scope.isAuthenticated) {
        if (!mounted) return;
        Get.offAll(() => const Login());
        return;
      }

      final snapshots = await Future.wait(
        _baseCollections.map((collection) {
          Query<Map<String, dynamic>> query = buildScopedRecordQuery(
            _firestore,
            collection,
            scope,
          );

          // Referral rules only allow BHW users to read their own referrals.
          if (collection == 'referrals' && scope.isBhw) {
            query = query.where('createdByUid', isEqualTo: scope.userId);
          }

          return query.get();
        }),
      );

      final rawByCollection = <String, List<Map<String, dynamic>>>{};
      for (int index = 0; index < _baseCollections.length; index++) {
        final collection = _baseCollections[index];
        final docs = snapshots[index].docs;
        final scopedRecords = docs
            .map(materializeFirestoreRecord)
            .map(
              (record) =>
                  applyBarangayScopeToRecord(record, accessScope: scope),
            )
            .where(
              (record) => recordMatchesAccessScope(
                record,
                scope,
                allowHistoricalBhwAnalyticsDemo: true,
              ),
            )
            .toList();
        rawByCollection[collection] = scopedRecords;
      }

      final nextProgramRecords = <String, List<_AnalyticsRecord>>{
        for (final module in _modules) module.id: <_AnalyticsRecord>[],
      };

      for (final record in rawByCollection['patient_records'] ?? const []) {
        final normalized = _normalizeRecord(
          moduleId: 'patient_records',
          sourceCollection: 'patient_records',
          record: record,
        );
        if (normalized != null) {
          nextProgramRecords['patient_records']!.add(normalized);
        }
      }

      for (final record in rawByCollection['checkup_records'] ?? const []) {
        final normalized = _normalizeRecord(
          moduleId: 'checkup_records',
          sourceCollection: 'checkup_records',
          record: record,
        );
        if (normalized != null) {
          nextProgramRecords['checkup_records']!.add(normalized);
        }
      }

      for (final record
          in rawByCollection['immunization_records'] ?? const []) {
        final normalized = _normalizeRecord(
          moduleId: 'immunization_records',
          sourceCollection: 'immunization_records',
          record: record,
        );
        if (normalized != null) {
          nextProgramRecords['immunization_records']!.add(normalized);
        }
      }

      for (final record in rawByCollection['mortality_records'] ?? const []) {
        final normalized = _normalizeRecord(
          moduleId: 'mortality_records',
          sourceCollection: 'mortality_records',
          record: record,
        );
        if (normalized != null) {
          nextProgramRecords['mortality_records']!.add(normalized);
        }
      }

      for (final record in rawByCollection['referrals'] ?? const []) {
        final normalized = _normalizeRecord(
          moduleId: 'referrals',
          sourceCollection: 'referrals',
          record: record,
        );
        if (normalized != null) {
          nextProgramRecords['referrals']!.add(normalized);
        }
      }

      final morbidityPool = <Map<String, dynamic>>[
        ...(rawByCollection['morbidity_records'] ?? const []),
        ...(rawByCollection['checkup_records'] ?? const []),
      ].where(_looksLikeMorbidityRecord);

      for (final record in morbidityPool) {
        final sourceCollection =
            (record['_firestorePath'] ?? '').toString().contains(
              'morbidity_records',
            )
            ? 'morbidity_records'
            : 'checkup_records';

        final morbidityRecord = _normalizeRecord(
          moduleId: 'morbidity',
          sourceCollection: sourceCollection,
          record: record,
        );
        if (morbidityRecord != null) {
          nextProgramRecords['morbidity']!.add(morbidityRecord);
        }

        if (_matchesCommunicable(record)) {
          final communicableRecord = _normalizeRecord(
            moduleId: 'communicable',
            sourceCollection: sourceCollection,
            record: record,
          );
          if (communicableRecord != null) {
            nextProgramRecords['communicable']!.add(communicableRecord);
          }
        }

        if (_matchesNonCommunicable(record)) {
          final nonCommunicableRecord = _normalizeRecord(
            moduleId: 'non_communicable',
            sourceCollection: sourceCollection,
            record: record,
          );
          if (nonCommunicableRecord != null) {
            nextProgramRecords['non_communicable']!.add(nonCommunicableRecord);
          }
        }
      }

      for (final records in nextProgramRecords.values) {
        records.sort(
          (left, right) => right.recordDate.compareTo(left.recordDate),
        );
      }

      if (!mounted) return;
      setState(() {
        _accessScope = scope;
        _patientRawRecords = List<Map<String, dynamic>>.from(
          rawByCollection['patient_records'] ?? const <Map<String, dynamic>>[],
        );
        _checkupRawRecords = List<Map<String, dynamic>>.from(
          rawByCollection['checkup_records'] ?? const <Map<String, dynamic>>[],
        );
        _programRecords = nextProgramRecords;
        _isLoading = false;
        _lastUpdatedAt = DateTime.now();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      Get.snackbar(
        'Analytics unavailable',
        'Failed to load BHW analytics data: $error',
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
      );
    }
  }

  _AnalyticsRecord? _normalizeRecord({
    required String moduleId,
    required String sourceCollection,
    required Map<String, dynamic> record,
  }) {
    final activityDate = _extractDate(record);
    if (activityDate == null) {
      return null;
    }

    final recordId = (record['id'] ?? record['documentId'] ?? '').toString();
    final subjectLabel = _extractSubjectLabel(moduleId, record);
    final primaryLabel = _extractPrimaryLabel(moduleId, record);
    final statusLabel = _extractStatusLabel(record);

    return _AnalyticsRecord(
      id: recordId.isEmpty
          ? activityDate.microsecondsSinceEpoch.toString()
          : recordId,
      moduleId: moduleId,
      sourceCollection: sourceCollection,
      subjectLabel: subjectLabel,
      primaryLabel: primaryLabel,
      statusLabel: statusLabel,
      barangay: (record['barangay'] ?? 'Unassigned').toString(),
      recordDate: activityDate,
    );
  }

  DateTime? _extractDate(Map<String, dynamic> record) {
    final candidates = <dynamic>[
      record['referralDateTime'],
      record['registrationDate'],
      record['datetime'],
      record['dateReported'],
      record['administrationDate'],
      record['dateTimeOfDeath'],
      record['date'],
      record['createdAt'],
      record['updatedAt'],
      record['time'],
    ];

    for (final candidate in candidates) {
      if (candidate == null) continue;
      if (candidate is Timestamp) return candidate.toDate();
      if (candidate is DateTime) return candidate;
      if (candidate is String && candidate.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(candidate.trim());
        if (parsed != null) {
          return parsed;
        }
      }
    }

    return null;
  }

  String _extractSubjectLabel(String moduleId, Map<String, dynamic> record) {
    if (moduleId == 'referrals') {
      final surname = (record['patientSurname'] ?? '').toString().trim();
      final firstName = (record['patientFirstName'] ?? '').toString().trim();
      final middleName = (record['patientMiddleName'] ?? '').toString().trim();

      final givenNames = <String>[
        firstName,
        middleName,
      ].where((value) => value.isNotEmpty).join(' ').trim();

      if (surname.isNotEmpty && givenNames.isNotEmpty) {
        return '$surname, $givenNames';
      }

      final joinedName = <String>[
        firstName,
        middleName,
        surname,
      ].where((value) => value.isNotEmpty).join(' ').trim();
      if (joinedName.isNotEmpty) {
        return joinedName;
      }
    }

    if (moduleId == 'patient_records') {
      final firstName = (record['firstName'] ?? '').toString().trim();
      final middleName = (record['middleName'] ?? '').toString().trim();
      final surname = (record['surname'] ?? '').toString().trim();
      final fullName = [
        firstName,
        middleName,
        surname,
      ].where((value) => value.isNotEmpty).join(' ');
      return fullName.isEmpty ? 'Unnamed patient' : fullName;
    }

    final fallback = <dynamic>[
      record['patientName'],
      record['patient'],
      record['name'],
      record['reportedBy'],
    ];
    for (final candidate in fallback) {
      final text = candidate?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }

    return 'Unknown patient';
  }

  String _extractPrimaryLabel(String moduleId, Map<String, dynamic> record) {
    final candidates = switch (moduleId) {
      'patient_records' => <dynamic>[
        record['status'],
        record['sex'],
        record['barangay'],
      ],
      'checkup_records' => <dynamic>[
        record['diseaseType'],
        record['diagnosis'],
        record['chiefComplaint'],
        record['type'],
      ],
      'immunization_records' => <dynamic>[
        record['vaccine'],
        record['immunizationType'],
        record['status'],
      ],
      'mortality_records' => <dynamic>[
        record['causeOfDeath'],
        record['causeCategory'],
        record['place'],
      ],
      'referrals' => <dynamic>[
        record['referralCategorySummary'],
        record['referralCategories'],
        record['referralType'],
        record['referredTo'],
        record['referralReason'],
        record['chiefComplaint'],
      ],
      'morbidity' => <dynamic>[
        record['disease'],
        record['symptoms'],
        record['diagnosis'],
        record['condition'],
        record['ai_category'],
      ],
      'communicable' => <dynamic>[
        record['disease'],
        record['condition'],
        record['diagnosis'],
        record['symptoms'],
      ],
      'non_communicable' => <dynamic>[
        record['disease'],
        record['condition'],
        record['diagnosis'],
        record['symptoms'],
      ],
      _ => <dynamic>[record['status']],
    };

    for (final candidate in candidates) {
      final text = candidate?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return switch (moduleId) {
      'patient_records' => 'Registered patient',
      'checkup_records' => 'General consultation',
      'immunization_records' => 'Vaccination service',
      'mortality_records' => 'Reported mortality case',
      'referrals' => 'Referred case',
      'morbidity' => 'Tracked disease case',
      'communicable' => 'Communicable disease case',
      'non_communicable' => 'Non-communicable condition',
      _ => 'No category',
    };
  }

  String _extractStatusLabel(Map<String, dynamic> record) {
    final candidates = <dynamic>[
      record['status'],
      record['verification'],
      record['severity'],
      record['ai_severity'],
      record['riskLevel'],
      record['urgency'],
    ];

    for (final candidate in candidates) {
      final text = candidate?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return 'Active';
  }

  bool _looksLikeMorbidityRecord(Map<String, dynamic> record) {
    final classification = _classificationToken(record);
    final diseaseText = _recordNarrative(record);
    final severity = _safeToken(
      record['severity'] ?? record['ai_severity'] ?? record['urgency'],
    );
    final remarks = _safeToken(
      record['remarks'] ?? record['plan'] ?? record['details'],
    );

    return classification == 'communicable' ||
        classification == 'noncommunicable' ||
        (classification.isNotEmpty && classification != 'general') ||
        (diseaseText.isNotEmpty &&
            diseaseText != 'general' &&
            diseaseText != 'general clinical case' &&
            diseaseText != 'unspecified') ||
        (severity.isNotEmpty &&
            severity != 'na' &&
            severity != 'n/a' &&
            severity != 'unspecified') ||
        (remarks.isNotEmpty && remarks != 'no remarks recorded');
  }

  bool _matchesCommunicable(Map<String, dynamic> record) {
    final classification = _classificationToken(record);
    if (classification == 'communicable' ||
        classification == 'communicabledisease') {
      return true;
    }
    if (classification.contains('noncommunicable')) {
      return false;
    }

    final narrative = _recordNarrative(record);
    if (_containsKeyword(narrative, _communicableKeywords)) {
      return true;
    }
    if (_containsKeyword(narrative, _nonCommunicableKeywords)) {
      return false;
    }
    return false;
  }

  bool _matchesNonCommunicable(Map<String, dynamic> record) {
    final classification = _classificationToken(record);
    if (classification == 'noncommunicable' ||
        classification == 'noncommunicabledisease') {
      return true;
    }

    final narrative = _recordNarrative(record);
    if (_containsKeyword(narrative, _nonCommunicableKeywords)) {
      return true;
    }
    if (_containsKeyword(narrative, _communicableKeywords)) {
      return false;
    }
    return false;
  }

  String _classificationToken(Map<String, dynamic> record) {
    return _safeToken(
      record['caseClassification'] ??
          record['classification'] ??
          record['diseaseType'] ??
          record['ai_category'] ??
          record['type'],
    );
  }

  String _recordNarrative(Map<String, dynamic> record) {
    return [
      record['disease'],
      record['condition'],
      record['diagnosis'],
      record['symptoms'],
      record['chiefComplaint'],
      record['details'],
      record['remarks'],
      record['plan'],
      record['causeOfDeath'],
      record['vaccine'],
    ].map((value) => value?.toString().trim().toLowerCase() ?? '').join(' ');
  }

  String _safeToken(dynamic value) {
    return value?.toString().trim().toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]+'),
          '',
        ) ??
        '';
  }

  bool _containsKeyword(String haystack, Set<String> keywords) {
    final normalizedHaystack = haystack.toLowerCase();
    for (final keyword in keywords) {
      if (normalizedHaystack.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  List<_AnalyticsRecord> _recordsForModule(String moduleId) {
    return _programRecords[moduleId] ?? const <_AnalyticsRecord>[];
  }

  List<_AnalyticsRecord> _recordsWithinCurrentWindow(
    Iterable<_AnalyticsRecord> records,
  ) {
    final range = _currentWindowRange();
    return records.where((record) {
      return !record.recordDate.isBefore(range.start) &&
          !record.recordDate.isAfter(range.end);
    }).toList();
  }

  List<_AnalyticsRecord> _recordsWithinPreviousWindow(
    Iterable<_AnalyticsRecord> records,
  ) {
    final currentRange = _currentWindowRange();
    final previousStart = DateTime(
      currentRange.start.year,
      currentRange.start.month - _selectedWindowMonths,
      1,
    );
    final previousEnd = currentRange.start.subtract(const Duration(seconds: 1));

    return records.where((record) {
      return !record.recordDate.isBefore(previousStart) &&
          !record.recordDate.isAfter(previousEnd);
    }).toList();
  }

  _DateRange _currentWindowRange() {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month - (_selectedWindowMonths - 1),
      1,
    );
    return _DateRange(start: start, end: now);
  }

  List<_MonthPoint> _buildSeries(List<_AnalyticsRecord> records) {
    final now = DateTime.now();
    final months = List<DateTime>.generate(
      _selectedWindowMonths,
      (index) => DateTime(
        now.year,
        now.month - (_selectedWindowMonths - 1 - index),
        1,
      ),
    );

    final counts = <String, int>{
      for (final month in months) DateFormat('yyyy-MM').format(month): 0,
    };
    for (final record in _recordsWithinCurrentWindow(records)) {
      final key = DateFormat(
        'yyyy-MM',
      ).format(DateTime(record.recordDate.year, record.recordDate.month, 1));
      if (counts.containsKey(key)) {
        counts[key] = counts[key]! + 1;
      }
    }

    return months
        .map(
          (month) => _MonthPoint(
            label: DateFormat('MMM').format(month),
            count: counts[DateFormat('yyyy-MM').format(month)] ?? 0,
          ),
        )
        .toList();
  }

  List<Map<String, dynamic>> _recordsWithinCurrentWindowRaw(dynamic records) {
    final range = _currentWindowRange();
    return _coerceRawRecords(records).where((record) {
      final date = _extractDate(record);
      if (date == null) return false;
      return !date.isBefore(range.start) && !date.isAfter(range.end);
    }).toList();
  }

  List<Map<String, dynamic>> _coerceRawRecords(dynamic records) {
    if (records is! Iterable) {
      return const <Map<String, dynamic>>[];
    }

    return records
        .whereType<Map>()
        .map((record) => Map<String, dynamic>.from(record))
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _latestRecordsByPerson(
    Iterable<Map<String, dynamic>> records,
  ) {
    final latestByPerson = <String, Map<String, dynamic>>{};
    for (final record in records) {
      final key = _personKey(record);
      final date = _extractDate(record);
      if (key.isEmpty || date == null) continue;

      final existing = latestByPerson[key];
      final existingDate = existing == null ? null : _extractDate(existing);
      if (existing == null ||
          existingDate == null ||
          date.isAfter(existingDate)) {
        latestByPerson[key] = record;
      }
    }
    return latestByPerson.values.toList();
  }

  String _personKey(Map<String, dynamic> record) {
    final idCandidates = <dynamic>[
      record['patientId'],
      record['linkedPatientId'],
      record['patientID'],
      record['patient_id'],
    ];
    for (final candidate in idCandidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return 'id:${value.toLowerCase()}';
      }
    }

    final fullName =
        [record['firstName'], record['middleName'], record['surname']]
            .map((value) => value?.toString().trim() ?? '')
            .where((value) => value.isNotEmpty)
            .join(' ');
    if (fullName.isNotEmpty) {
      return 'name:${fullName.toLowerCase()}';
    }

    final fallbackNameCandidates = <dynamic>[
      record['patientName'],
      record['patient'],
      record['name'],
    ];
    for (final candidate in fallbackNameCandidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return 'name:${value.toLowerCase()}';
      }
    }

    final path = (record['_firestorePath'] ?? record['id'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return path.isEmpty ? '' : 'record:$path';
  }

  double? _extractDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();

    final text = value.toString().trim();
    if (text.isEmpty) return null;

    final match = RegExp(
      r'-?\d+(?:\.\d+)?',
    ).firstMatch(text.replaceAll(',', ''));
    if (match == null) return null;
    return double.tryParse(match.group(0)!);
  }

  double? _extractLabeledValue(String text, List<String> labels) {
    if (text.trim().isEmpty) return null;

    for (final label in labels) {
      final pattern = RegExp(
        '${RegExp.escape(label)}\\s*[:=]?\\s*(-?\\d+(?:\\.\\d+)?)',
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

  Map<String, double>? _extractBloodPressure(dynamic value) {
    if (value == null) return null;

    final text = value.toString();
    final match = RegExp(r'(\d{2,3})\s*/\s*(\d{2,3})').firstMatch(text);
    if (match == null) return null;

    final systolic = double.tryParse(match.group(1)!);
    final diastolic = double.tryParse(match.group(2)!);
    if (systolic == null || diastolic == null) return null;

    return <String, double>{
      'blood_pressure_sys': systolic,
      'blood_pressure_dia': diastolic,
    };
  }

  Map<String, double>? _extractBloodPressureFromRecord(
    Map<String, dynamic> record,
  ) {
    final systolic = _extractDouble(
      record['bpSystolic'] ?? record['systolic'] ?? record['bp_systolic'],
    );
    final diastolic = _extractDouble(
      record['bpDiastolic'] ?? record['diastolic'] ?? record['bp_diastolic'],
    );

    final combinedText = [
      record['bloodPressure'],
      record['bp'],
      record['vitalsigns'],
      record['details'],
    ].where((value) => value != null).join(' | ');

    final parsed = _extractBloodPressure(combinedText);
    final resolvedSystolic = systolic ?? parsed?['blood_pressure_sys'];
    final resolvedDiastolic = diastolic ?? parsed?['blood_pressure_dia'];
    if (resolvedSystolic == null || resolvedDiastolic == null) {
      return null;
    }

    return <String, double>{
      'blood_pressure_sys': resolvedSystolic,
      'blood_pressure_dia': resolvedDiastolic,
    };
  }

  double? _extractBmiFromRecord(Map<String, dynamic> record) {
    final directBmi = _extractDouble(record['bmi']);
    if (directBmi != null) return directBmi;

    final combinedText = [
      record['details'],
      record['vitalsigns'],
      record['remarks'],
    ].where((value) => value != null).join(' | ');
    final parsedBmi = _extractLabeledValue(combinedText, const <String>[
      'BMI',
      'Body Mass Index',
    ]);
    if (parsedBmi != null) return parsedBmi;

    final weight = _extractDouble(record['weight'] ?? record['wt']);
    final height = _extractDouble(record['height'] ?? record['ht']);
    if (weight != null && height != null && height > 0) {
      final heightMeters = height > 3 ? height / 100 : height;
      if (heightMeters > 0) {
        return weight / (heightMeters * heightMeters);
      }
    }

    return null;
  }

  int? _extractAgeFromRecord(Map<String, dynamic> record) {
    final directAge = _extractDouble(record['age'])?.round();
    if (directAge != null && directAge >= 0) {
      return directAge;
    }

    final dobText = (record['dateOfBirth'] ?? '').toString().trim();
    final dob = dobText.isEmpty ? null : DateTime.tryParse(dobText);
    if (dob != null) {
      final now = DateTime.now();
      var age = now.year - dob.year;
      if (now.month < dob.month ||
          (now.month == dob.month && now.day < dob.day)) {
        age -= 1;
      }
      if (age >= 0) return age;
    }

    final detailsText = (record['details'] ?? '').toString();
    final match = RegExp(
      r'Age:\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(detailsText);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }

    return null;
  }

  String _normalizeSexValue(dynamic value) {
    final text = (value ?? '').toString().trim().toLowerCase();
    if (text.isEmpty) return 'Unknown';
    if (text.startsWith('m')) return 'Male';
    if (text.startsWith('f')) return 'Female';
    return 'Other';
  }

  String _bmiCategory(double bmi) {
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25) return 'Normal';
    if (bmi < 30) return 'Overweight';
    return 'Obese';
  }

  String _ageBucketLabel(int age) {
    if (age <= 14) return '0-14';
    if (age <= 24) return '15-24';
    if (age <= 44) return '25-44';
    if (age <= 64) return '45-64';
    return '65+';
  }

  List<_ClinicalSlice> _bmiDistributionSlices() {
    final records = _latestRecordsByPerson([
      ..._recordsWithinCurrentWindowRaw(_patientRawRecords),
      ..._recordsWithinCurrentWindowRaw(_checkupRawRecords),
    ]);

    final counts = <String, int>{
      'Underweight': 0,
      'Normal': 0,
      'Overweight': 0,
      'Obese': 0,
    };

    for (final record in records) {
      final bmi = _extractBmiFromRecord(record);
      if (bmi == null || bmi <= 0) continue;
      final category = _bmiCategory(bmi);
      counts[category] = (counts[category] ?? 0) + 1;
    }

    return <_ClinicalSlice>[
      _ClinicalSlice(
        label: 'Underweight',
        value: counts['Underweight'] ?? 0,
        color: const Color(0xFFF59E0B),
      ),
      _ClinicalSlice(
        label: 'Normal',
        value: counts['Normal'] ?? 0,
        color: const Color(0xFF10B981),
      ),
      _ClinicalSlice(
        label: 'Overweight',
        value: counts['Overweight'] ?? 0,
        color: const Color(0xFF60A5FA),
      ),
      _ClinicalSlice(
        label: 'Obese',
        value: counts['Obese'] ?? 0,
        color: const Color(0xFFEF4444),
      ),
    ];
  }

  List<_BloodPressureTrendPoint> _bloodPressureTrendPoints() {
    final now = DateTime.now();
    final months = List<DateTime>.generate(
      _selectedWindowMonths,
      (index) => DateTime(
        now.year,
        now.month - (_selectedWindowMonths - 1 - index),
        1,
      ),
    );

    final sums = <String, _BloodPressureAccumulator>{
      for (final month in months)
        DateFormat('yyyy-MM').format(month): const _BloodPressureAccumulator(),
    };

    for (final record in _recordsWithinCurrentWindowRaw(_checkupRawRecords)) {
      final date = _extractDate(record);
      final pressure = _extractBloodPressureFromRecord(record);
      if (date == null || pressure == null) continue;

      final key = DateFormat(
        'yyyy-MM',
      ).format(DateTime(date.year, date.month, 1));
      final existing = sums[key];
      if (existing == null) continue;
      sums[key] = existing.copyWith(
        systolicTotal: existing.systolicTotal + pressure['blood_pressure_sys']!,
        diastolicTotal:
            existing.diastolicTotal + pressure['blood_pressure_dia']!,
        count: existing.count + 1,
      );
    }

    return months.map((month) {
      final key = DateFormat('yyyy-MM').format(month);
      final bucket = sums[key] ?? const _BloodPressureAccumulator();
      return _BloodPressureTrendPoint(
        label: DateFormat('MMM').format(month),
        systolicAverage: bucket.count == 0
            ? null
            : bucket.systolicTotal / bucket.count,
        diastolicAverage: bucket.count == 0
            ? null
            : bucket.diastolicTotal / bucket.count,
        sampleCount: bucket.count,
      );
    }).toList();
  }

  List<_CountBarPoint> _patientDemographicAgePoints() {
    final sourceRecords = _latestRecordsByPerson(
      _recordsWithinCurrentWindowRaw(_patientRawRecords),
    );
    final counts = <String, int>{
      '0-14': 0,
      '15-24': 0,
      '25-44': 0,
      '45-64': 0,
      '65+': 0,
    };

    for (final record in sourceRecords) {
      final age = _extractAgeFromRecord(record);
      if (age == null) continue;
      final bucket = _ageBucketLabel(age);
      counts[bucket] = (counts[bucket] ?? 0) + 1;
    }

    return <_CountBarPoint>[
      _CountBarPoint(
        label: '0-14',
        value: counts['0-14'] ?? 0,
        color: const Color(0xFF38BDF8),
      ),
      _CountBarPoint(
        label: '15-24',
        value: counts['15-24'] ?? 0,
        color: const Color(0xFF818CF8),
      ),
      _CountBarPoint(
        label: '25-44',
        value: counts['25-44'] ?? 0,
        color: const Color(0xFF34D399),
      ),
      _CountBarPoint(
        label: '45-64',
        value: counts['45-64'] ?? 0,
        color: const Color(0xFFF59E0B),
      ),
      _CountBarPoint(
        label: '65+',
        value: counts['65+'] ?? 0,
        color: const Color(0xFFEF4444),
      ),
    ];
  }

  List<_ClinicalSlice> _patientSexSlices() {
    final sourceRecords = _latestRecordsByPerson(
      _recordsWithinCurrentWindowRaw(_patientRawRecords),
    );
    final counts = <String, int>{
      'Male': 0,
      'Female': 0,
      'Other': 0,
      'Unknown': 0,
    };

    for (final record in sourceRecords) {
      final sex = _normalizeSexValue(record['gender'] ?? record['sex']);
      counts[sex] = (counts[sex] ?? 0) + 1;
    }

    return <_ClinicalSlice>[
      _ClinicalSlice(
        label: 'Male',
        value: counts['Male'] ?? 0,
        color: const Color(0xFF60A5FA),
      ),
      _ClinicalSlice(
        label: 'Female',
        value: counts['Female'] ?? 0,
        color: const Color(0xFFF472B6),
      ),
      _ClinicalSlice(
        label: 'Other',
        value: counts['Other'] ?? 0,
        color: const Color(0xFFA78BFA),
      ),
      _ClinicalSlice(
        label: 'Unknown',
        value: counts['Unknown'] ?? 0,
        color: const Color(0xFF94A3B8),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : user?.email?.split('@').first ?? 'BHW User';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F7FA),
      drawer: WebAppSidebar(
        userName: userName,
        activeItem: WebSidebarItem.analytics,
      ),
      appBar: AppBar(
        backgroundColor: _darkDeepTeal,
        title: const Text('BHW Analytics'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh analytics',
            onPressed: _loadAnalytics,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryAqua))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroSection(),
                  const SizedBox(height: 20),
                  _buildProgramBoard(),
                  const SizedBox(height: 20),
                  _buildClinicalInsightsSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeroSection() {
    final scopeLabel = _accessScope.canViewAllBarangays
        ? 'City-wide operations view'
        : 'Barangay operations view';
    final locationLabel = _accessScope.canViewAllBarangays
        ? 'All barangays'
        : _accessScope.barangay.isEmpty
        ? 'Assigned barangay'
        : _accessScope.barangay;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_panelSurface, _panelAlt],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _primaryAqua.withValues(alpha: 0.18)),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 20,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BHW Health Program Analytics',
                  style: TextStyle(
                    color: _lightOffWhite,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 310,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _panelAlt,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFD9E5F2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current Scope',
                  style: TextStyle(
                    color: _mutedCoolGray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  scopeLabel,
                  style: const TextStyle(
                    color: _lightOffWhite,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  locationLabel,
                  style: const TextStyle(
                    color: _primaryAqua,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _lastUpdatedAt == null
                      ? 'Awaiting first refresh'
                      : 'Updated ${DateFormat('MMM d, y - h:mm a').format(_lastUpdatedAt!)}',
                  style: TextStyle(
                    color: _lightOffWhite.withValues(alpha: 0.72),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgramBoard() {
    final screenWidth = MediaQuery.of(context).size.width;
    final visibleProgramRecords = _modules.fold<int>(
      0,
      (total, module) =>
          total +
          _recordsWithinCurrentWindow(_recordsForModule(module.id)).length,
    );
    final crossAxisCount = screenWidth >= 1500
        ? 3
        : screenWidth >= 980
        ? 2
        : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Program Graphs',
                    style: TextStyle(
                      color: _lightOffWhite,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Hover a monthly bar for its exact count. Select a program card to inspect records and trends.',
                    style: TextStyle(color: _mutedCoolGray, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: _primaryAqua.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _primaryAqua.withValues(alpha: 0.24)),
              ),
              child: Text(
                '$visibleProgramRecords visible program records',
                style: const TextStyle(
                  color: _primaryAqua,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh program graphs',
              onPressed: _loadAnalytics,
              icon: const Icon(Icons.refresh_rounded),
              color: _primaryAqua,
            ),
          ],
        ),
        const SizedBox(height: 18),
        GridView.builder(
          itemCount: _modules.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 18,
            mainAxisSpacing: 18,
            childAspectRatio: crossAxisCount == 1 ? 1.55 : 1.18,
          ),
          itemBuilder: (context, index) {
            return _buildProgramCard(_modules[index]);
          },
        ),
      ],
    );
  }

  String _programTrendLabel(int currentCount, int previousCount) {
    final delta = currentCount - previousCount;
    if (delta == 0) {
      return 'No change';
    }
    if (delta > 0) {
      return '+$delta vs previous window';
    }
    return '$delta vs previous window';
  }

  Future<void> _showProgramDetailDialog(
    _AnalyticsModuleDefinition module,
  ) async {
    final records = _recordsForModule(module.id);
    final activeRecords = _recordsWithinCurrentWindow(records);
    final previousRecords = _recordsWithinPreviousWindow(records);
    final series = _buildSeries(records);
    final topCategory = _topCategoryLabel(activeRecords);
    final latestRecord = activeRecords.isEmpty ? null : activeRecords.first;
    final trendLabel = _programTrendLabel(
      activeRecords.length,
      previousRecords.length,
    );
    final recentRecords = activeRecords.take(5).toList(growable: false);

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final showTwoColumns = screenWidth >= 980;

        final chartPanel = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _darkDeepTeal.withValues(alpha: 0.52),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: SizedBox(
            height: 300,
            child: activeRecords.isEmpty
                ? _buildNoDataState(module)
                : _buildBarChart(module, series),
          ),
        );

        final detailsPanel = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _darkDeepTeal.withValues(alpha: 0.52),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildMetricChip(
                    icon: Icons.inventory_2_outlined,
                    label: '${activeRecords.length} records',
                    accent: module.accent,
                  ),
                  _buildMetricChip(
                    icon: Icons.label_outline_rounded,
                    label: topCategory,
                    accent: module.accent,
                  ),
                  _buildMetricChip(
                    icon: Icons.trending_up_rounded,
                    label: trendLabel,
                    accent: module.accent,
                  ),
                  _buildMetricChip(
                    icon: Icons.schedule_rounded,
                    label: latestRecord == null
                        ? 'No recent activity'
                        : DateFormat(
                            'MMM d, y',
                          ).format(latestRecord.recordDate),
                    accent: module.accent,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Recent Visible Records',
                style: TextStyle(
                  color: _lightOffWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (recentRecords.isEmpty)
                Text(
                  'No records available in the selected window.',
                  style: TextStyle(
                    color: _lightOffWhite.withValues(alpha: 0.72),
                    fontSize: 12.5,
                  ),
                )
              else
                ...recentRecords.map(
                  (record) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildProgramRecordPreview(record, module.accent),
                  ),
                ),
            ],
          ),
        );

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _panelSurface,
                    Color.lerp(_panelSurface, module.accent, 0.12) ?? _panelAlt,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: module.accent.withValues(alpha: 0.42),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.24),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: module.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            module.icon,
                            color: module.accent,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${module.title} Analytics',
                                style: const TextStyle(
                                  color: _lightOffWhite,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                module.subtitle,
                                style: TextStyle(
                                  color: _lightOffWhite.withValues(alpha: 0.78),
                                  fontSize: 13.5,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: _lightOffWhite,
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (showTwoColumns)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: chartPanel),
                          const SizedBox(width: 18),
                          Expanded(flex: 5, child: detailsPanel),
                        ],
                      )
                    else ...[
                      chartPanel,
                      const SizedBox(height: 18),
                      detailsPanel,
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgramRecordPreview(_AnalyticsRecord record, Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panelSurface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.subjectLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _lightOffWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${record.primaryLabel} • ${record.statusLabel}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _lightOffWhite.withValues(alpha: 0.74),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            DateFormat('MMM d').format(record.recordDate),
            style: TextStyle(
              color: accent,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClinicalInsightsSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = maxWidth > 1380 ? 3 : (maxWidth > 920 ? 2 : 1);
        const spacing = 18.0;
        final panelWidth = columns == 1
            ? maxWidth
            : (maxWidth - (spacing * (columns - 1))) / columns;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Clinical Insights',
              style: TextStyle(
                color: _lightOffWhite,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                SizedBox(
                  width: panelWidth,
                  child: _buildInsightPanel(
                    panelId: 'bmi_distribution',
                    title: 'BMI Distribution',
                    subtitle:
                        'Latest BMI readings grouped by nutritional status.',
                    icon: Icons.monitor_weight_outlined,
                    accent: const Color(0xFFF59E0B),
                    onTap: _showBmiDistributionDialog,
                    child: _buildBmiDistributionChart(),
                  ),
                ),
                SizedBox(
                  width: panelWidth,
                  child: _buildInsightPanel(
                    panelId: 'blood_pressure_trend',
                    title: 'Blood Pressure Trend',
                    subtitle:
                        'Average systolic and diastolic readings across the selected window.',
                    icon: Icons.favorite_outline_rounded,
                    accent: const Color(0xFFEF4444),
                    onTap: _showBloodPressureTrendDialog,
                    child: _buildBloodPressureTrendChart(),
                  ),
                ),
                SizedBox(
                  width: panelWidth,
                  child: _buildInsightPanel(
                    panelId: 'patient_demographic',
                    title: 'Patient Demographic',
                    subtitle:
                        'Age-group distribution with visible sex breakdown from patient records.',
                    icon: Icons.groups_rounded,
                    accent: const Color(0xFF818CF8),
                    onTap: _showPatientDemographicDialog,
                    child: _buildPatientDemographicChart(),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  _ClinicalSlice? _topClinicalSlice(List<_ClinicalSlice> slices) {
    final nonZeroSlices = slices.where((slice) => slice.value > 0).toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    return nonZeroSlices.isEmpty ? null : nonZeroSlices.first;
  }

  _CountBarPoint? _topCountBarPoint(List<_CountBarPoint> points) {
    final nonZeroPoints = points.where((point) => point.value > 0).toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    return nonZeroPoints.isEmpty ? null : nonZeroPoints.first;
  }

  _BloodPressureTrendPoint? _latestActiveBloodPressurePoint(
    List<_BloodPressureTrendPoint> points,
  ) {
    for (int index = points.length - 1; index >= 0; index--) {
      final point = points[index];
      if (point.sampleCount > 0) {
        return point;
      }
    }
    return null;
  }

  Future<void> _showBmiDistributionDialog() async {
    const accent = Color(0xFFF59E0B);
    final slices = _bmiDistributionSlices();
    final total = slices.fold<int>(0, (runningTotal, item) {
      return runningTotal + item.value;
    });
    final dominantSlice = _topClinicalSlice(slices);
    final atRiskCount = slices
        .where((slice) => slice.label == 'Overweight' || slice.label == 'Obese')
        .fold<int>(0, (runningTotal, slice) => runningTotal + slice.value);

    await _showClinicalInsightDialog(
      title: 'BMI Distribution',
      subtitle: 'Latest BMI readings grouped by nutritional status.',
      icon: Icons.monitor_weight_outlined,
      accent: accent,
      summaryChips: [
        _buildMetricChip(
          icon: Icons.monitor_weight_outlined,
          label: '$total profiles',
          accent: accent,
        ),
        _buildMetricChip(
          icon: Icons.pie_chart_outline_rounded,
          label: dominantSlice == null
              ? 'No dominant group'
              : '${dominantSlice.label} largest group',
          accent: accent,
        ),
        _buildMetricChip(
          icon: Icons.warning_amber_rounded,
          label: '$atRiskCount at-risk',
          accent: accent,
        ),
        _buildMetricChip(
          icon: Icons.calendar_month_rounded,
          label: '$_selectedWindowMonths-month window',
          accent: accent,
        ),
      ],
      chart: _buildBmiDistributionChart(),
    );
  }

  Future<void> _showBloodPressureTrendDialog() async {
    const accent = Color(0xFFEF4444);
    final points = _bloodPressureTrendPoints();
    final totalReadings = points.fold<int>(
      0,
      (readingCount, point) => readingCount + point.sampleCount,
    );
    final monthsWithReadings = points
        .where((point) => point.sampleCount > 0)
        .length;
    final latestPoint = _latestActiveBloodPressurePoint(points);
    final latestAverage =
        latestPoint == null ||
            latestPoint.systolicAverage == null ||
            latestPoint.diastolicAverage == null
        ? 'No recent average'
        : '${latestPoint.label} ${latestPoint.systolicAverage!.round()}/${latestPoint.diastolicAverage!.round()}';

    await _showClinicalInsightDialog(
      title: 'Blood Pressure Trend',
      subtitle:
          'Average systolic and diastolic readings across the selected window.',
      icon: Icons.favorite_outline_rounded,
      accent: accent,
      summaryChips: [
        _buildMetricChip(
          icon: Icons.monitor_heart_outlined,
          label: '$totalReadings readings',
          accent: accent,
        ),
        _buildMetricChip(
          icon: Icons.timeline_rounded,
          label: '$monthsWithReadings / ${points.length} active months',
          accent: accent,
        ),
        _buildMetricChip(
          icon: Icons.favorite_rounded,
          label: latestAverage,
          accent: accent,
        ),
        _buildMetricChip(
          icon: Icons.calendar_month_rounded,
          label: '$_selectedWindowMonths-month window',
          accent: accent,
        ),
      ],
      chart: _buildBloodPressureTrendChart(),
    );
  }

  Future<void> _showPatientDemographicDialog() async {
    const accent = Color(0xFF818CF8);
    final agePoints = _patientDemographicAgePoints();
    final sexSlices = _patientSexSlices();
    final totalProfiles = agePoints.fold<int>(
      0,
      (profileCount, point) => profileCount + point.value,
    );
    final dominantAgeBand = _topCountBarPoint(agePoints);
    final dominantSex = _topClinicalSlice(sexSlices);

    await _showClinicalInsightDialog(
      title: 'Patient Demographic',
      subtitle:
          'Age-group distribution with visible sex breakdown from patient records.',
      icon: Icons.groups_rounded,
      accent: accent,
      summaryChips: [
        _buildMetricChip(
          icon: Icons.people_outline_rounded,
          label: '$totalProfiles profiles',
          accent: accent,
        ),
        _buildMetricChip(
          icon: Icons.cake_outlined,
          label: dominantAgeBand == null
              ? 'No age focus'
              : '${dominantAgeBand.label} largest age band',
          accent: accent,
        ),
        _buildMetricChip(
          icon: Icons.wc_rounded,
          label: dominantSex == null
              ? 'No sex breakdown'
              : '${dominantSex.label} most visible',
          accent: accent,
        ),
        _buildMetricChip(
          icon: Icons.calendar_month_rounded,
          label: '$_selectedWindowMonths-month window',
          accent: accent,
        ),
      ],
      chart: _buildPatientDemographicChart(),
    );
  }

  Future<void> _showClinicalInsightDialog({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required List<Widget> summaryChips,
    required Widget chart,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _panelSurface,
                    Color.lerp(_panelSurface, accent, 0.12) ?? _panelAlt,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: accent.withValues(alpha: 0.42)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.24),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(icon, color: accent, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: _lightOffWhite,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: _lightOffWhite.withValues(alpha: 0.76),
                                  fontSize: 14,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: _lightOffWhite.withValues(alpha: 0.84),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Wrap(spacing: 10, runSpacing: 10, children: summaryChips),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: _darkDeepTeal.withValues(alpha: 0.54),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: SizedBox(height: 360, child: chart),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInsightPanel({
    required String panelId,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final isHovered = _hoveredInsightPanelId == panelId;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredInsightPanelId = panelId),
      onExit: (_) {
        if (_hoveredInsightPanelId == panelId) {
          setState(() => _hoveredInsightPanelId = null);
        }
      },
      child: Tooltip(
        message: 'Open $title insight details',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: AnimatedScale(
              scale: isHovered ? 1.01 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                height: 360,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _panelSurface,
                      Color.lerp(_panelSurface, accent, 0.12) ?? _panelAlt,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: accent.withValues(alpha: isHovered ? 0.58 : 0.34),
                  ),
                  boxShadow: isHovered
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.14),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : const <BoxShadow>[],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(icon, color: accent, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: _lightOffWhite,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: _lightOffWhite.withValues(alpha: 0.74),
                                  fontSize: 12.5,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isHovered
                                ? accent.withValues(alpha: 0.14)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.open_in_full_rounded,
                                size: 14,
                                color: accent,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isHovered ? 'Inspect' : 'Open',
                                style: TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBmiDistributionChart() {
    final slices = _bmiDistributionSlices();
    final total = slices.fold<int>(0, (runningTotal, item) {
      return runningTotal + item.value;
    });
    if (total == 0) {
      return _buildInsightEmptyState('No BMI measurements available yet.');
    }

    return Column(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 34,
              sectionsSpace: 3,
              sections: slices.map((slice) {
                if (slice.value <= 0) {
                  return PieChartSectionData(
                    value: 0,
                    title: '',
                    radius: 0,
                    color: Colors.transparent,
                  );
                }
                final percent = ((slice.value / total) * 100).round();
                return PieChartSectionData(
                  value: slice.value.toDouble(),
                  color: slice.color,
                  radius: 50,
                  title: '$percent%',
                  titleStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: slices.map((slice) {
            return _buildLegendChip(
              color: slice.color,
              label: '${slice.label} (${slice.value})',
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBloodPressureTrendChart() {
    final points = _bloodPressureTrendPoints();
    final hasData = points.any((point) => point.sampleCount > 0);
    if (!hasData) {
      return _buildInsightEmptyState(
        'No blood pressure readings found in check-up records.',
      );
    }

    final systolicValues = points
        .where((point) => point.systolicAverage != null)
        .map((point) => point.systolicAverage!)
        .toList();
    final diastolicValues = points
        .where((point) => point.diastolicAverage != null)
        .map((point) => point.diastolicAverage!)
        .toList();
    final combinedValues = <double>[...systolicValues, ...diastolicValues];
    final minValue = combinedValues.reduce(math.min);
    final maxValue = combinedValues.reduce(math.max);
    final minY = math.max(40, ((minValue - 10) ~/ 10) * 10).toDouble();
    final maxY = (((maxValue + 15) / 10).ceil() * 10).toDouble();
    final interval = math
        .max(10, (((maxY - minY) / 4).ceil() ~/ 10) * 10)
        .toDouble();

    final systolicSpots = <FlSpot>[];
    final diastolicSpots = <FlSpot>[];
    for (int index = 0; index < points.length; index++) {
      final point = points[index];
      if (point.systolicAverage != null) {
        systolicSpots.add(FlSpot(index.toDouble(), point.systolicAverage!));
      }
      if (point.diastolicAverage != null) {
        diastolicSpots.add(FlSpot(index.toDouble(), point.diastolicAverage!));
      }
    }

    return Column(
      children: [
        Expanded(
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (points.length - 1).toDouble(),
              minY: minY,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: Colors.white.withValues(alpha: 0.10),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  color: const Color(0xFFEF4444),
                  barWidth: 3,
                  dotData: FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  ),
                  spots: systolicSpots,
                ),
                LineChartBarData(
                  isCurved: true,
                  color: const Color(0xFF60A5FA),
                  barWidth: 3,
                  dotData: FlDotData(show: true),
                  belowBarData: BarAreaData(show: false),
                  spots: diastolicSpots,
                ),
              ],
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: interval,
                    getTitlesWidget: (value, _) => Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.65),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, _) {
                      final index = value.toInt();
                      if (index < 0 || index >= points.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          points[index].label,
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.70),
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _buildLegendChip(
              color: const Color(0xFFEF4444),
              label:
                  'Systolic (${systolicValues.isEmpty ? 'N/A' : systolicValues.last.toStringAsFixed(0)})',
            ),
            _buildLegendChip(
              color: const Color(0xFF60A5FA),
              label:
                  'Diastolic (${diastolicValues.isEmpty ? 'N/A' : diastolicValues.last.toStringAsFixed(0)})',
            ),
            _buildLegendChip(
              color: const Color(0xFF94A3B8),
              label:
                  'Readings (${points.fold<int>(0, (readingCount, point) => readingCount + point.sampleCount)})',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPatientDemographicChart() {
    final agePoints = _patientDemographicAgePoints();
    final sexSlices = _patientSexSlices();
    final totalAgeCount = agePoints.fold<int>(
      0,
      (ageCount, item) => ageCount + item.value,
    );
    if (totalAgeCount == 0) {
      return _buildInsightEmptyState(
        'No patient demographic records available yet.',
      );
    }

    final maxY = math
        .max(
          4,
          agePoints.fold<int>(
                0,
                (maxValue, item) => math.max(maxValue, item.value),
              ) +
              1,
        )
        .toDouble();

    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: maxY,
              barTouchData: BarTouchData(enabled: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: math.max(1, (maxY / 4).ceil()).toDouble(),
                getDrawingHorizontalLine: (_) => FlLine(
                  color: Colors.white.withValues(alpha: 0.08),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, _) => Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.6),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, _) {
                      final index = value.toInt();
                      if (index < 0 || index >= agePoints.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          agePoints[index].label,
                          style: TextStyle(
                            color: _lightOffWhite.withValues(alpha: 0.70),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: List<BarChartGroupData>.generate(agePoints.length, (
                index,
              ) {
                final point = agePoints[index];
                return BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: point.value.toDouble(),
                      width: 16,
                      gradient: LinearGradient(
                        colors: [
                          point.color.withValues(alpha: 0.45),
                          point.color,
                        ],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: sexSlices.map((slice) {
            return _buildLegendChip(
              color: slice.color,
              label: '${slice.label} (${slice.value})',
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildInsightEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _lightOffWhite.withValues(alpha: 0.74),
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendChip({required Color color, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _darkDeepTeal.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: _lightOffWhite,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgramCard(_AnalyticsModuleDefinition module) {
    final records = _recordsForModule(module.id);
    final activeRecords = _recordsWithinCurrentWindow(records);
    final topCategory = _topCategoryLabel(activeRecords);
    final series = _buildSeries(records);
    final latestRecord = activeRecords.isEmpty ? null : activeRecords.first;
    final isHovered = _hoveredProgramCardId == module.id;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredProgramCardId = module.id),
      onExit: (_) {
        if (_hoveredProgramCardId == module.id) {
          setState(() => _hoveredProgramCardId = null);
        }
      },
      child: Tooltip(
        message: 'Open ${module.title} analytics details',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => _showProgramDetailDialog(module),
            child: AnimatedScale(
              scale: isHovered ? 1.01 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _panelSurface,
                      Color.lerp(_panelSurface, module.accent, 0.14) ??
                          _panelAlt,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: module.accent.withValues(
                      alpha: isHovered ? 0.62 : 0.34,
                    ),
                  ),
                  boxShadow: isHovered
                      ? [
                          BoxShadow(
                            color: module.accent.withValues(alpha: 0.14),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : const <BoxShadow>[],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: module.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            module.icon,
                            color: module.accent,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                module.title,
                                style: const TextStyle(
                                  color: _lightOffWhite,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                module.subtitle,
                                style: TextStyle(
                                  color: _lightOffWhite.withValues(alpha: 0.74),
                                  fontSize: 12.5,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isHovered
                                ? module.accent.withValues(alpha: 0.14)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.open_in_full_rounded,
                                size: 14,
                                color: module.accent,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isHovered ? 'Inspect' : 'Open',
                                style: TextStyle(
                                  color: module.accent,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildMetricChip(
                          icon: Icons.inventory_2_outlined,
                          label: '${activeRecords.length} records',
                          accent: module.accent,
                        ),
                        _buildMetricChip(
                          icon: Icons.label_outline_rounded,
                          label: topCategory,
                          accent: module.accent,
                        ),
                        _buildMetricChip(
                          icon: Icons.schedule_rounded,
                          label: latestRecord == null
                              ? 'No recent activity'
                              : DateFormat(
                                  'MMM d, y',
                                ).format(latestRecord.recordDate),
                          accent: module.accent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: activeRecords.isEmpty
                          ? _buildNoDataState(module)
                          : _buildBarChart(module, series),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricChip({
    required IconData icon,
    required String label,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _darkDeepTeal.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: _lightOffWhite,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataState(_AnalyticsModuleDefinition module) {
    const moduleLabels = <String, String>{
      'patient_records': 'patient registry',
      'checkup_records': 'check-up',
      'immunization_records': 'immunization',
      'mortality_records': 'mortality',
      'referrals': 'referral',
      'morbidity': 'morbidity',
      'communicable': 'communicable',
      'non_communicable': 'non-communicable',
    };

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _darkDeepTeal.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                module.icon,
                color: module.accent.withValues(alpha: 0.72),
                size: 30,
              ),
              const SizedBox(height: 10),
              Text(
                'No encoded records yet',
                style: TextStyle(
                  color: _lightOffWhite.withValues(alpha: 0.88),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'This graph will populate as soon as visible ${moduleLabels[module.id] ?? 'program'} records are encoded.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _lightOffWhite.withValues(alpha: 0.66),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarChart(
    _AnalyticsModuleDefinition module,
    List<_MonthPoint> series,
  ) {
    final maxCount = series.fold<int>(
      0,
      (maxValue, point) => math.max(maxValue, point.count),
    );
    final maxY = math.max(4, maxCount + 1).toDouble();
    final interval = maxCount <= 4
        ? 1.0
        : math.max(1, (maxCount / 3).ceil()).toDouble();

    return Container(
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY,
          barTouchData: BarTouchData(
            enabled: true,
            handleBuiltInTouches: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => _darkDeepTeal,
              tooltipBorderRadius: BorderRadius.circular(10),
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
              tooltipMargin: 8,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              tooltipBorder: BorderSide(
                color: module.accent.withValues(alpha: 0.42),
              ),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                if (groupIndex < 0 || groupIndex >= series.length) {
                  return null;
                }
                final point = series[groupIndex];
                return BarTooltipItem(
                  '${point.label}\n',
                  TextStyle(
                    color: module.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  children: <TextSpan>[
                    TextSpan(
                      text:
                          '${point.count} ${point.count == 1 ? 'record' : 'records'}',
                      style: const TextStyle(
                        color: _lightOffWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.white.withValues(alpha: 0.08),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: interval,
                getTitlesWidget: (value, _) => Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    color: _lightOffWhite.withValues(alpha: 0.6),
                    fontSize: 10,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final index = value.toInt();
                  if (index < 0 || index >= series.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      series[index].label,
                      style: TextStyle(
                        color: _lightOffWhite.withValues(alpha: 0.7),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: List<BarChartGroupData>.generate(series.length, (index) {
            final point = series[index];
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: point.count.toDouble(),
                  width: 16,
                  gradient: LinearGradient(
                    colors: [
                      module.accent.withValues(alpha: 0.45),
                      module.accent,
                    ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  String _topCategoryLabel(List<_AnalyticsRecord> records) {
    if (records.isEmpty) {
      return 'No category yet';
    }

    final counts = <String, int>{};
    for (final record in records) {
      final label = record.primaryLabel.trim();
      if (label.isEmpty) continue;
      counts[label] = (counts[label] ?? 0) + 1;
    }

    if (counts.isEmpty) {
      return 'No category yet';
    }

    final entries = counts.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    return entries.first.key;
  }
}

class _AnalyticsModuleDefinition {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  const _AnalyticsModuleDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });
}

class _AnalyticsRecord {
  final String id;
  final String moduleId;
  final String sourceCollection;
  final String subjectLabel;
  final String primaryLabel;
  final String statusLabel;
  final String barangay;
  final DateTime recordDate;

  const _AnalyticsRecord({
    required this.id,
    required this.moduleId,
    required this.sourceCollection,
    required this.subjectLabel,
    required this.primaryLabel,
    required this.statusLabel,
    required this.barangay,
    required this.recordDate,
  });
}

class _MonthPoint {
  final String label;
  final int count;

  const _MonthPoint({required this.label, required this.count});
}

class _DateRange {
  final DateTime start;
  final DateTime end;

  const _DateRange({required this.start, required this.end});
}

class _ClinicalSlice {
  final String label;
  final int value;
  final Color color;

  const _ClinicalSlice({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _CountBarPoint {
  final String label;
  final int value;
  final Color color;

  const _CountBarPoint({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _BloodPressureTrendPoint {
  final String label;
  final double? systolicAverage;
  final double? diastolicAverage;
  final int sampleCount;

  const _BloodPressureTrendPoint({
    required this.label,
    required this.systolicAverage,
    required this.diastolicAverage,
    required this.sampleCount,
  });
}

class _BloodPressureAccumulator {
  final double systolicTotal;
  final double diastolicTotal;
  final int count;

  const _BloodPressureAccumulator({
    this.systolicTotal = 0,
    this.diastolicTotal = 0,
    this.count = 0,
  });

  _BloodPressureAccumulator copyWith({
    double? systolicTotal,
    double? diastolicTotal,
    int? count,
  }) {
    return _BloodPressureAccumulator(
      systolicTotal: systolicTotal ?? this.systolicTotal,
      diastolicTotal: diastolicTotal ?? this.diastolicTotal,
      count: count ?? this.count,
    );
  }
}
